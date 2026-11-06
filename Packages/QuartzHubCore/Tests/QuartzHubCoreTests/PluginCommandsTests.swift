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
  var w: URL { scratch.url.appendingPathComponent("w") }
  var log: URL { scratch.url.appendingPathComponent("calls.log") }
  init() throws { scratch = try HostPathTests.Scratch() }

  /// One script per tool; npx answers by its third argument (`quartz plugin <sub>`).
  func environment(answers: JSONValue, npmBody: String? = nil) throws -> ToolEnvironment {
    func respond(_ answer: JSONValue?) -> String {
      guard let answer else { return "exit 0" }
      let creates = (answer["creates"]?.arrayValue ?? []).compactMap(\.stringValue)
        .map { "mkdir -p \"$(dirname '\($0)')\" && echo '{}' > '\($0)'" }.joined(separator: "\n")
      return "\(creates)\nprintf '%s' '\(answer["output"]?.stringValue ?? "")'\nexit \(answer["success"] == .bool(true) ? 0 : 1)"
    }
    try scratch.script("bin/npm", "echo \"npm $* $(pwd)\" >> '\(log.path)'\n\(npmBody ?? respond(answers["npm"]))")
    var npx = "echo \"npx $* $(pwd)\" >> '\(log.path)'\ncase \"$3\" in\n"
    for sub in ["install", "add", "remove", "prune"] { npx += "\(sub))\n\(respond(answers[sub]))\n;;\n" }
    try scratch.script("bin/npx", npx + "esac")
    let hostPath = HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"], source: .inherited, added: [])
    return ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"], hostPath: hostPath, nodeMode: .system,
                           runtime: .repository, git: nil, bundledGitFailure: nil)
  }

  func mask(_ text: String) -> String {
    let real = ContentFolder.realPath(w.path) ?? w.path
    return text.replacingOccurrences(of: real, with: "@W@").replacingOccurrences(of: w.path, with: "@W@")
  }

  var calls: [String] { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map { mask(String($0)) } }

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 9, "scripts/plugins-golden.mjs")
  }

  @Test(arguments: cases)
  func sameAsQuartzControl(_ name: String) async throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("\(name)/case.json")))
    let project = w.appendingPathComponent("P")
    try ProjectDuplicatorTests.layOut(spec["tree"]!, at: project) { $0 }
    let environment = try environment(answers: spec["answers"]!)
    let run = spec["run"]!.arrayValue!.compactMap(\.stringValue)
    let commands = PluginCommands()
    let log = log

    let result: PluginCommands.Result = switch run[0] {
    case "installFromLock":
      // In the log, in order, as the golden script's forgetDependencyErrors notes it.
      await commands.installFromLock(project: project, environment: environment) { url in
        try? "forget \(url.path)\n".appendLine(to: log)
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
    let project = w.appendingPathComponent("P")
    try ProjectDuplicatorTests.layOut(.object(JSONObject([("package.json", .string("{\"dependencies\":{\"a\":\"1\"}}"))])), at: project) { $0 }
    let gate = scratch.url.appendingPathComponent("gate")
    // npm waits until the test opens the gate, so both calls overlap for certain.
    let environment = try environment(answers: .object(JSONObject()),
                                      npmBody: "while [ ! -e '\(gate.path)' ]; do sleep 0.05; done\nexit 0")
    let commands = PluginCommands()
    async let first = commands.installFromLock(project: project, environment: environment)
    while !commands.isInstallingFromLock(project: project) { try await Task.sleep(for: .milliseconds(10)) }
    async let second = commands.installFromLock(project: project, environment: environment)
    try await Task.sleep(for: .milliseconds(200))
    try Data().write(to: gate)
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
    let project = w.appendingPathComponent("P")
    try ProjectDuplicatorTests.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n"))])), at: project) { $0 }
    let environment = try environment(answers: .object(JSONObject()))
    let calls = SnapshotCalls()
    let commands = PluginCommands()
    let log = log
    // How many CLI calls each snapshot saw: it comes before its own command.
    let seen = Mutex<[Int]>([])
    let snapshot = calls.take { _ in
      let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").count
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
    #expect(seen.withLock { $0 } == [0, 1, 3])
  }

  @Test func aSnapshotThatFailsStopsTheCommand() async throws {
    let project = w.appendingPathComponent("P")
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
