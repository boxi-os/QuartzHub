import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own pluginService.ts: `scripts/plugins-golden.mjs` ran each operation of
/// `Fixtures/plugins/<case>/case.json` with a runCommand that answers as the case says; here npm and
/// npx are scripts that answer the same.
@Suite struct PluginCommandsTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/plugins")
  static var cases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
  }

  let scratch: HostPathTests.Scratch
  var w: String { "\(scratch.path)/w" }
  var log: String { "\(scratch.path)/calls.log" }
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  /// One script per tool; npx answers by its third argument (`quartz plugin <sub>`).
  func environment(answers: JSONValue, npmBody: String? = nil) throws -> ToolEnvironment {
    func respond(_ answer: JSONValue?) -> String {
      guard let answer else { return "exit 0" }
      let creates = (answer["creates"]?.arrayValue ?? []).compactMap(\.stringValue)
        .map { "mkdir -p \"$(dirname '\($0)')\" && echo '{}' > '\($0)'" }.joined(separator: "\n")
      return "\(creates)\nprintf '%s' '\(answer["output"]?.stringValue ?? "")'\nexit \(answer["success"] == .bool(true) ? 0 : 1)"
    }
    try scratch.script("bin/npm", "echo \"npm $* $(pwd)\" >> '\(log)'\n\(npmBody ?? respond(answers["npm"]))")
    var npx = "echo \"npx $* $(pwd)\" >> '\(log)'\ncase \"$3\" in\n"
    for sub in ["install", "add", "remove", "prune", "doctor"] { npx += "\(sub))\n\(respond(answers[sub]))\n;;\n" }
    try scratch.script("bin/npx", npx + "esac")
    let hostPath = HostPath(entries: ["\(scratch.path)/bin", "/usr/bin", "/bin"], source: .inherited, added: [])
    return ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"], hostPath: hostPath, nodeMode: .system,
                           runtime: .repository, git: nil, bundledGitFailure: nil)
  }

  func mask(_ text: String) -> String {
    let real = ContentFolder.realPath(w) ?? w
    return text.replacingOccurrences(of: real, with: "@W@", options: .literal).replacingOccurrences(of: w, with: "@W@", options: .literal)
  }

  var calls: [String] { ((try? Posix.read(log)).map { String(decoding: $0, as: UTF8.self) } ?? "").split(separator: "\n").map { mask(String($0)) } }

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 9, "scripts/plugins-golden.mjs")
  }

  @Test(arguments: cases)
  func sameAsQuartzControl(_ name: String) async throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("\(name)/case.json")))
    let project = "\(w)/P"
    try ProjectDuplicatorTests.layOut(spec["tree"]!, at: project) { $0 }
    let environment = try environment(answers: spec["answers"]!)
    let run = spec["run"]!.arrayValue!.compactMap(\.stringValue)
    let commands = PluginCommands()
    let log = log

    let result: PluginCommands.Result = switch run[0] {
    case "installFromLock":
      // In the log, in order, as the golden script's forgetDependencyErrors notes it.
      await commands.installFromLock(project: project, environment: environment) { path in
        try? "forget \(path)\n".appendLine(to: URL(fileURLWithPath: log))
      }
    case "installPluginSource": await commands.add(source: run[1], project: project, environment: environment)
    case "removePlugin": await commands.remove(name: run[1], project: project, environment: environment)
    default: await commands.prune(project: project, environment: environment)
    }

    let expected = spec["expected"]!
    #expect(result.success == (expected["result"]?["success"] == .bool(true)), "\(name)")
    #expect(mask(result.output) == expected["result"]?["output"]?.stringValue, "\(name)")
    #expect(result.failed.map { .array($0.map(JSONValue.string)) } ?? .null == expected["result"]?["failed"] ?? .null, "\(name)")
    #expect(.array(calls.map(JSONValue.string)) == expected["log"], "\(name)")
  }

  @Test func aSecondInstallJoinsTheRunningOne() async throws {
    let project = "\(w)/P"
    try ProjectDuplicatorTests.layOut(.object(JSONObject([("package.json", .string("{\"dependencies\":{\"a\":\"1\"}}"))])), at: project) { $0 }
    let gate = "\(scratch.path)/gate"
    // npm waits until the test opens the gate, so both calls overlap for certain.
    let environment = try environment(answers: .object(JSONObject()),
                                      npmBody: "while [ ! -e '\(gate)' ]; do sleep 0.05; done\nexit 0")
    let commands = PluginCommands()
    async let first = commands.installFromLock(project: project, environment: environment)
    while !commands.isInstallingFromLock(project: project) { try await Task.sleep(for: .milliseconds(10)) }
    async let second = commands.installFromLock(project: project, environment: environment)
    try await Task.sleep(for: .milliseconds(200))
    try Posix.write(gate, Data())
    let (a, b) = await (first, second)
    #expect(a == b)
    #expect(calls.filter { $0.hasPrefix("npm ") }.count == 1, "\(calls)")
    #expect(!commands.isInstallingFromLock(project: project))
    // A call after the end is a run of its own.
    _ = await commands.installFromLock(project: project, environment: environment)
    #expect(calls.filter { $0.hasPrefix("npm ") }.count == 2)
  }

  @Test func failedNamesComeFromTheCrossLines() {
    #expect(PluginCommands.failedPlugins("  \u{1b}[31m✗\u{1b}[39m frame-a: x\n✗ b: y\n  ✗ frame-a: z\n  ✗ c no colon\n  ✓ d: fine\n")
      == ["frame-a", "b"])
    #expect(PluginCommands.failedPlugins("") == [])
  }

  // MARK: the snapshot before add and remove

  @Test func addAndRemoveTakeASnapshotFirstWhenAsked() async throws {
    let project = "\(w)/P"
    try ProjectDuplicatorTests.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n"))])), at: project) { $0 }
    let environment = try environment(answers: .object(JSONObject()))
    let calls = SnapshotCalls()
    let commands = PluginCommands()
    let log = log
    // How many CLI calls each snapshot saw: it comes before its own command.
    let seen = Mutex<[Int]>([])
    let snapshot = calls.take { _ in
      let lines = ((try? Posix.read(log)).map { String(decoding: $0, as: UTF8.self) } ?? "").split(separator: "\n").count
      seen.withLock { $0.append(lines) }
    }
    #expect(await commands.add(source: "github:a/b", project: project, environment: environment, snapshot: snapshot).success)
    #expect(await commands.remove(name: "b", project: project, environment: environment, snapshot: snapshot).success)
    #expect(await commands.add(source: "github:c/d", project: project, environment: environment).success)
    #expect(calls.all == [["pluginChange", "github:a/b"], ["pluginChange", "b"]])
    #expect(self.calls.count == 3)

    // A frame through the CLI: with a snapshot when the frame asks for one.
    let frames = LayoutFrames.Plugins.cli(environment: { environment }, snapshot: snapshot)
    _ = await frames.add("/frame/one", project, true)
    _ = await frames.add("/frame/two", project, false)
    #expect(calls.all.last == ["pluginChange", "/frame/one"] && calls.all.count == 3)
    // Deleting a frame always takes one, as QuartzControl's `deleteFrame` goes through
    // `removePlugin` (measured 2026-11-09: the question promised one and none was taken).
    _ = await frames.remove("frame-one", project)
    #expect(calls.all.last == ["pluginChange", "frame-one"] && calls.all.count == 4)
    #expect(seen.withLock { $0 } == [0, 1, 3, 5])
  }

  /// Quartz 5.1's doctor: a snapshot before `--fix` only, the check alone writes nothing; "found
  /// errors" (exit 1) is no success, and the output goes back either way.
  @Test func doctorFixTakesASnapshotFirstAndTheCheckDoesNot() async throws {
    let project = "\(w)/P"
    try ProjectDuplicatorTests.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n"))])), at: project) { $0 }
    let environment = try environment(answers: .object(JSONObject([("doctor", .object(JSONObject([
      ("success", .bool(false)), ("output", .string("✗ x: npm package is not installed")),
    ])))])))
    let calls = SnapshotCalls()
    let commands = PluginCommands()
    let check = await commands.doctor(project: project, fix: false, environment: environment, snapshot: calls.take { _ in })
    #expect(!check.success && check.output.contains("npm package is not installed"))
    #expect(calls.all.isEmpty)
    _ = await commands.doctor(project: project, fix: true, environment: environment, snapshot: calls.take { _ in })
    #expect(calls.all == [["pluginChange", "plugin doctor --fix"]])
    _ = await commands.info(project: project, environment: environment)
    #expect(self.calls == ["npx quartz plugin doctor @W@/P", "npx quartz plugin doctor --fix @W@/P", "npx quartz info @W@/P"])
  }

  @Test func aSnapshotThatFailsStopsTheCommand() async throws {
    let project = "\(w)/P"
    try ProjectDuplicatorTests.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n"))])), at: project) { $0 }
    let environment = try environment(answers: .object(JSONObject()))
    struct NoWayBack: Error, CustomStringConvertible { var description: String { "kein Weg zurück" } }
    let result = await PluginCommands().add(source: "github:a/b", project: project, environment: environment, snapshot: { _, _, _ in throw NoWayBack() })
    #expect(!result.success && result.output == "kein Weg zurück")
    #expect(calls.isEmpty)
  }
}

private extension String {
  func appendLine(to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(utf8))
  }
}
