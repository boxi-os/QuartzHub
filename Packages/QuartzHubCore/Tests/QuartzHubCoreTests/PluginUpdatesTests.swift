import Darwin
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own `getPluginsUpdateStatus` and `updatePlugin` with real git
/// (`scripts/plugin-updates-golden.mjs`): a plugin repository with a branch, two kinds of tag, a
/// name that is both, a newer HEAD; lockfiles with every kind of entry, a dashed source and ref.
@Suite(.serialized) struct PluginUpdatesTests {
  static let file: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/plugin-updates/steps.json")))

  final class Calls: @unchecked Sendable { let snapshots = Mutex<[[String]]>([]) }

  static func json(_ status: PluginUpdates.Status) -> JSONValue {
    var fields: [(String, JSONValue)] = [("name", .string(status.name))]
    if status.state != .local {
      if let installed = status.installedCommit { fields.append(("installedCommit", installed)) }
      fields.append(("latestCommit", status.latestCommit.map(JSONValue.string) ?? .null))
    }
    fields.append(("state", .string(status.state.rawValue)))
    return .object(JSONObject(fields))
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let golden = try GitGolden()
    let work = golden.work
    try SnapshotStoreTests.Harness.write("\(work)/bin/npx", JS.string(Self.file["npx"]).replacingOccurrences(of: "@W@", with: work))
    chmod("\(work)/bin/npx", 0o755)
    let calls = Calls()
    let core = CoreUpdate(environment: golden.environment, snapshot: { _, _, _ in nil }, templateRepository: "/nowhere")
    let project = golden.url("p")
    for step in Self.file["steps"]!.arrayValue! {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! { try await golden.act(action) }
      unlink("\(work)/npx-calls.log")
      calls.snapshots.withLock { $0 = [] }
      var result: JSONValue = .null
      switch step["op"]!.stringValue! {
      case "status": result = .array(await PluginUpdates.status(project: project, core: core).map(Self.json))
      case "update":
        let args = step["args"]!.arrayValue!
        let answer = await PluginUpdates.update(project: project, name: args.first?.stringValue, environment: golden.environment,
                                                snapshot: { _, kind, label in calls.snapshots.withLock { $0.append([kind, label]) }; return "snap-1" })
        result = .object(JSONObject([("success", .bool(answer.success)), ("output", .string(answer.output))]))
      default:
        if name == "nothing ran from a dashed source" { result = .bool(Posix.exists("\(work)/pwned")) }
      }
      var expected = step["result"] ?? .null
      if step["error"] != nil {
        // QuartzControl failed the whole list over a null entry; here it is local.
        #expect(name == "an entry that is null", "\(name): \(String(describing: step["error"]))")
        expected = .array([.object(JSONObject([("name", .string("a")), ("state", .string("local"))]))])
      }
      if step["op"] == .string("update") {
        // runCommand's answer carries stdout as well; QuartzHub's carries the shown output.
        expected = .object(JSONObject([("success", expected["success"]!), ("output", expected["output"]!)]))
      }
      #expect(result.masked(work) == expected, "\(name)\n\(JSJSON.compact(result.masked(work)))\n\(JSJSON.compact(expected))")
      let npx = (try? Posix.read("\(work)/npx-calls.log")).map { String(decoding: $0, as: UTF8.self) } ?? ""
      #expect(npx.replacingOccurrences(of: work, with: "@W@") == step["npx"]!.stringValue!, "\(name): npx")
      #expect(JSONValue.array(calls.snapshots.withLock { $0 }.map { .array($0.map(JSONValue.string)) }) == step["snapshots"], "\(name): snapshots")
    }
  }

  /// Four at a time, in the lockfile's order.
  @Test func checksFourAtATime() async throws {
    let scratch = try HostPathTests.Scratch()
    let log = scratch.url.appendingPathComponent("log").path
    try scratch.script("bin/git", "echo \"start $4\" >> '\(log)'; sleep 0.3; echo \"end $4\" >> '\(log)'; exit 1")
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"],
                                      hostPath: HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"],
                                                         source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    let plugins = (0..<6).map { ("p\($0)", JSONValue.object(JSONObject([("resolved", .string("r\($0)")), ("commit", .string("c"))]))) }
    try SnapshotStoreTests.Harness.write(scratch.url.appendingPathComponent("quartz.lock.json").path,
                                         JSJSON.stringify(.object(JSONObject([("plugins", .object(JSONObject(plugins)))]))))
    let core = CoreUpdate(environment: environment, snapshot: { _, _, _ in nil })
    let statuses = await PluginUpdates.status(project: scratch.url, core: core)
    #expect(statuses.map(\.name) == plugins.map(\.0))
    #expect(statuses.allSatisfy { $0.state == .unknown })
    var running = 0, most = 0
    for line in String(decoding: try Posix.read(log), as: UTF8.self).split(separator: "\n") {
      running += line.hasPrefix("start") ? 1 : -1
      most = max(most, running)
    }
    #expect(most == 4)
  }
}
