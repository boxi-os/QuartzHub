import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// The one-off build against a stand-in for `npx` that prints what Quartz prints, and once against
/// the real `quartz build` on a copy of gui-test (`QH_QUARTZ_TESTS=1`).
@Suite struct BuildServiceTests {
  let scratch: HostPathTests.Scratch
  var project: String { "\(scratch.path)/Projekt mit Ä" }
  var calls: String { "\(scratch.path)/npx.log" }
  init() throws {
    scratch = try HostPathTests.Scratch(umlaut: true)
    try Posix.mkdirs(project)
    try Posix.write("\(project)/package.json", Data("{}".utf8))
  }

  final class Events: Sendable {
    let all = Mutex<[BuildService.Event]>([])
    func add(_ event: BuildService.Event) { all.withLock { $0.append(event) } }
    var activities: [BuildActivity?] {
      all.withLock { $0.compactMap { if case .activity(_, let a) = $0 { return .some(a) } else { return nil } } }
    }
    func logs(_ stream: LogLine.Stream) -> String {
      all.withLock { $0.compactMap { if case .log(.build, let line) = $0, line.stream == stream { line.text } else { nil } }.joined() }
    }
  }

  /// `npx` that notes its call and prints a build in Quartz's words, a line cut across two writes
  /// among them; it waits for `release` when that file is named, and exits with the number in
  /// `exit`, if there is one.
  func environment(npx body: String? = nil) throws -> ToolEnvironment {
    let script = body ?? """
    echo "npx $* @ $(pwd)" >> '\(calls)'
    echo "Quartz v5.0.0"
    echo "Cleaned output directory"
    while [ -e '\(scratch.path)/hold' ]; do sleep 0.02; done
    printf 'Parsing input '; sleep 0.1; echo 'files using 8 threads'
    echo "Something to say" >&2
    sleep 0.1
    echo "Emitting files"
    sleep 0.1
    echo "Done processing 3 files in 0.3s"
    exit $(cat '\(scratch.path)/exit' 2>/dev/null || echo 0)
    """
    try scratch.script("bin/npx", script)
    let hostPath = HostPath(entries: ["\(scratch.path)/bin", "/usr/bin", "/bin"], source: .inherited, added: [])
    return ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"], hostPath: hostPath, nodeMode: .system,
                           runtime: .repository, git: nil, bundledGitFailure: nil)
  }

  func service(_ environment: ToolEnvironment, _ events: Events, logs: LogBuffer = LogBuffer(),
               preparation: [BuildService.PreparationStep] = []) -> BuildService {
    BuildService(logs: logs, environment: { environment }, preparation: preparation, onEvent: events.add)
  }

  /// Holds the stand-in at its start until `release`, or for three seconds at most: a test whose
  /// expectation fails must not wait forever on a build nobody releases.
  func hold() throws -> @Sendable () -> Void {
    let file = "\(scratch.path)/hold"
    try Posix.write(file, Data("".utf8))
    let release: @Sendable () -> Void = { try? FileManager.default.removeItem(atPath: file) }
    Task {
      try? await Task.sleep(for: .seconds(3))
      release()
    }
    return release
  }

  var callLines: [String] { ((try? Posix.read(calls)).map { String(decoding: $0, as: UTF8.self) } ?? "").split(separator: "\n").map(String.init) }

  @Test func aBuildSaysWhatQuartzDoesWhileItRuns() async throws {
    let events = Events()
    let logs = LogBuffer()
    let builds = service(try environment(), events, logs: logs)
    let result = try await builds.build(projectId: "p", project: project, outputDir: nil)
    #expect(result.success && result.exitCode == 0)
    #expect(result.duration > .milliseconds(300))
    #expect(events.activities.map { $0.map { "\($0.kind) \($0.phase)" } } == ["build preparing", "build parsing", "build emitting", nil])
    #expect(await builds.activity("p") == nil)
    #expect(events.logs(.stdout) == "Quartz v5.0.0\nCleaned output directory\nParsing input files using 8 threads\nEmitting files\nDone processing 3 files in 0.3s\n")
    #expect(events.logs(.stderr) == "Something to say\n")
    #expect(logs.history("p").build.map(\.text).joined() == events.all.withLock { $0 }.compactMap {
      if case .log(_, let line) = $0 { line.text } else { nil } }.joined())
    #expect(callLines == ["npx quartz build @ \(BuildOutputGuard.realPath(project))"])
  }

  @Test func aSecondBuildIntoTheSameFolderJoinsTheFirst() async throws {
    let events = Events()
    let builds = service(try environment(), events)
    let project = self.project
    let release = try hold()
    async let first = builds.build(projectId: "p", project: project, outputDir: "dist")
    try await LaunchedProcessTests.waitFor { !callLines.isEmpty }
    async let second = builds.build(projectId: "p", project: project, outputDir: "./dist/")
    try await Task.sleep(for: .milliseconds(100))
    release()
    let (a, b) = try await (first, second)
    #expect(a == b && a.success)
    #expect(callLines == ["npx quartz build --output dist @ \(BuildOutputGuard.realPath(project))"], "one build, not two")
  }

  @Test func aBuildIntoAnotherFolderWaitsItsTurn() async throws {
    let builds = service(try environment(), Events())
    let project = self.project
    let release = try hold()
    async let first = builds.build(projectId: "p", project: project, outputDir: nil)
    try await LaunchedProcessTests.waitFor { !callLines.isEmpty }
    let refusal = BuildService.Refusal.anotherBuildRuns(running: project + "/public", wanted: project + "/elsewhere")
    await #expect(throws: refusal) { try await builds.build(projectId: "p", project: project, outputDir: "elsewhere") }
    #expect(refusal.message.contains("„\(project)/public“") || refusal.message.contains("“\(project)/public”"))
    // Another project builds meanwhile.
    let other = "\(scratch.path)/Anderes"
    try Posix.mkdirs(other)
    release()
    #expect(try await builds.build(projectId: "q", project: other, outputDir: nil).success)
    #expect(try await first.success)
    #expect(try await builds.build(projectId: "p", project: project, outputDir: "elsewhere").success, "after the first is done")
  }

  @Test func missingPackagesAreASentenceAndNoBuild() async throws {
    try Posix.write("\(project)/package.json", Data(#"{"dependencies":{"@jackyzha0/quartz":"5","left-pad":"1","a":"1","b":"1"}}"#.utf8))
    let events = Events()
    let result = try await service(try environment(), events).build(projectId: "p", project: project, outputDir: nil)
    // The packages too, so the page says "Nicht gebaut" rather than "Fehlgeschlagen in 0,0 s".
    #expect(result == BuildService.Result(success: false, duration: .zero, exitCode: nil,
                                          missingDependencies: ["@jackyzha0/quartz", "left-pad", "a", "b"]))
    #expect(events.logs(.warn) == L10n.t("main.dependenciesMissing", ["names": "@jackyzha0/quartz, left-pad, a …"]) + "\n")
    #expect(callLines.isEmpty)
    #expect(events.activities.map { $0?.kind } == [.build, nil])
  }

  @Test func theEndIsTheExitCodeOrNone() async throws {
    try Posix.write("\(scratch.path)/exit", Data("3".utf8))
    let failed = try await service(try environment(), Events()).build(projectId: "p", project: project, outputDir: nil)
    #expect(!failed.success && failed.exitCode == 3)

    let killed = try await service(try environment(npx: "kill -TERM $$"), Events()).build(projectId: "p", project: project, outputDir: nil)
    #expect(!killed.success && killed.exitCode == nil, "a signal is no code")

    var noNpx = try environment()
    noNpx.hostPath = HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: [])
    let events = Events()
    let missing = try await service(noNpx, events).build(projectId: "p", project: project, outputDir: nil)
    #expect(!missing.success && missing.exitCode == nil)
    #expect(events.logs(.stderr) == "spawn npx ENOENT\n")
  }

  @Test func thePreparationReportsIntoTheConsoleBeforeTheBuild() async throws {
    let events = Events()
    let seen = Mutex<[String]>([])
    let step: BuildService.PreparationStep = { project, report in
      seen.withLock { $0.append(project) }
      report(.warn, "Frames aufgefrischt\n")
    }
    _ = try await service(try environment(), events, preparation: [step, step]).build(projectId: "p", project: project, outputDir: nil)
    #expect(seen.withLock { $0 } == [project, project])
    let first = events.all.withLock { $0 }.compactMap { if case .log(_, let line) = $0 { line } else { nil } }.prefix(3)
    #expect(first.map(\.stream) == [.warn, .warn, .stdout])
  }

  /// The real `quartz build` of a copy of gui-test (APFS clone, node_modules included), with the
  /// Node runtime in Runtime/.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["QH_QUARTZ_TESTS"] == "1", "QH_QUARTZ_TESTS=1"))
  func theRealQuartzBuildsACopyOfGuiTest() async throws {
    let original = "\(NSHomeDirectory())/Documents/QuartzProjekte/gui-test"
    let copy = "\(scratch.path)/gui-test"
    let clone = await ProcessRunner.run(Command("/bin/cp", ["-cR", original, copy]))
    try #require(clone.success, "\(clone.output)")
    try? FileManager.default.removeItem(atPath: "\(copy)/public")
    let environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    let events = Events()
    let result = try await BuildService(logs: LogBuffer(), environment: { environment }, onEvent: events.add)
      .build(projectId: "g", project: copy, outputDir: nil)
    #expect(result.success, "\(events.logs(.stdout))\n\(events.logs(.stderr))")
    let phases = events.activities.map { $0.map { "\($0.kind) \($0.phase)" } }
    #expect(phases == ["build preparing", "build parsing", "build emitting", nil], "\(phases)")
    #expect(BuildOutputGuard.looksLikeQuartzBuild("\(copy)/public"))
    print("gui-test: \(result.duration), \(events.logs(.stdout).split(separator: "\n").count) Zeilen")
  }
}
