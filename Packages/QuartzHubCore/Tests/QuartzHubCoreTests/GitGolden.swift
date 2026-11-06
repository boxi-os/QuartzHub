import Darwin
import Foundation
import Synchronization
@testable import QuartzHubCore

/// The steps of `scripts/git-golden.mjs`, replayed with the same git (`/usr/bin/git`), the same
/// pinned identities and dates and the same npx stand-in. Every suite replays all setups (they
/// build on each other) and checks the steps of its own call.
final class GitGolden: @unchecked Sendable {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/git")
  static let file: JSONValue = try! JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("steps.json")))
  static var steps: [JSONValue] { file["steps"]!.arrayValue! }

  let scratch: HostPathTests.Scratch
  /// The work folder, resolved: /var is a link to /private/var, and git answers with the real path.
  let work: String
  let environment: ToolEnvironment
  let token = Mutex<String?>(nil)

  init() throws {
    scratch = try HostPathTests.Scratch()
    work = TemplatePackageTests.realpath(scratch.url.path)
    try SnapshotStoreTests.Harness.write("\(work)/gitconfig", "")
    try SnapshotStoreTests.Harness.write("\(work)/bin/npx", JS.string(Self.file["npx"]).replacingOccurrences(of: "@W@", with: work))
    chmod("\(work)/bin/npx", 0o755)
    environment = ToolEnvironment(
      base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "\(work)/gitconfig", "GIT_CONFIG_NOSYSTEM": "1",
             "GIT_EDITOR": "true"],
      hostPath: HostPath(entries: ["\(work)/bin", "/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system,
      runtime: .repository, git: nil, bundledGitFailure: nil)
  }

  func path(_ relative: String) -> String { relative.isEmpty ? work : "\(work)/\(relative)" }
  func url(_ relative: String) -> URL { URL(fileURLWithPath: path(relative)) }
  func sub(_ text: String) -> String { text.replacingOccurrences(of: "@W@", with: work) }

  func act(_ action: JSONValue) async throws {
    let path = action["path"]?.stringValue.map(self.path)
    switch action["do"]!.stringValue! {
    case "write": try SnapshotStoreTests.Harness.write(path!, sub(action["text"]!.stringValue!))
    case "many":
      SnapshotStoreTests.Harness.mkdirs(path!)
      let prefix = action["prefix"]!.stringValue!
      for i in 0..<Int(action["count"]!.numberValue!) {
        try SnapshotStoreTests.Harness.write("\(path!)/\(prefix)\(String(format: "%04d", i)).md", "\(i)\n")
      }
    case "mkdir": SnapshotStoreTests.Harness.mkdirs(path!)
    case "remove": try? FileManager.default.removeItem(atPath: path!)
    case "symlink":
      unlink(path!)
      try Posix.symlink(sub(action["target"]!.stringValue!), path!)
    case "git":
      let when = action["when"]?.stringValue ?? "2026-11-01T10:00:00+01:00"
      let command = environment.command("git", action["args"]!.arrayValue!.map { sub($0.stringValue!) }, in: URL(fileURLWithPath: path!))
        .adding(["GIT_AUTHOR_NAME": "Jörg Prüfer", "GIT_AUTHOR_EMAIL": "test@example.com", "GIT_COMMITTER_NAME": "Jörg Prüfer",
                 "GIT_COMMITTER_EMAIL": "test@example.com", "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when])
      let result = await ProcessRunner.run(command)
      if !result.success && action["mayFail"] != .bool(true) {
        throw GitFailure(description: "git \(command.arguments.joined(separator: " ")): \(result.output)")
      }
    case "token": token.withLock { $0 = action["value"]?.stringValue }
    default: throw GitFailure(description: "unknown action")
    }
  }

  struct GitFailure: Error, CustomStringConvertible { let description: String }

  /// Runs every step's setup and hands the steps of `op` to `check`, in order.
  func replay(_ op: String, _ check: (JSONValue) async throws -> Void) async throws {
    for step in Self.steps {
      for action in step["setup"]!.arrayValue! { try await act(action) }
      if step["op"]!.stringValue == op { try await check(step) }
    }
  }
}
