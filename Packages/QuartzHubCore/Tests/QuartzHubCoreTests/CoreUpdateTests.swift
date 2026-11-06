import Darwin
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own updateService.ts with real git (`scripts/core-update-golden.mjs`):
/// 30 scenes over a local upstream with six branches, npm as `Fixtures/core-update/npm-stub.cjs`
/// (the same file, the same Node), npx as the same script. After each step the answer, the calls of
/// npm, npx and the snapshot, and the state of the project, all compared as QuartzControl left them.
@Suite(.serialized) struct CoreUpdateTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/core-update")
  static let file: JSONValue = try! JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("steps.json")))

  final class Harness: @unchecked Sendable {
    let scratch: HostPathTests.Scratch
    let work: String
    let environment: ToolEnvironment
    let snapshots = Mutex<[[String]]>([])

    init() throws {
      scratch = try HostPathTests.Scratch()
      work = TemplatePackageTests.realpath(scratch.url.path)
      try SnapshotStoreTests.Harness.write("\(work)/gitconfig", "")
      try Posix.mkdirs("\(work)/bin")
      try Posix.write("\(work)/npm-stub.cjs", try Posix.read(CoreUpdateTests.fixtures.appendingPathComponent("npm-stub.cjs").path))
      let node = "\(RuntimeLocation.repository.nodeBin)/node"
      try SnapshotStoreTests.Harness.write("\(work)/bin/npm", "#!/bin/sh\nexec '\(node)' '\(work)/npm-stub.cjs' \"$@\"\n")
      try SnapshotStoreTests.Harness.write("\(work)/bin/npx", JS.string(CoreUpdateTests.file["npx"]).replacingOccurrences(of: "@W@", with: work, options: .literal))
      chmod("\(work)/bin/npm", 0o755)
      chmod("\(work)/bin/npx", 0o755)
      let when = "2026-11-06T12:00:00+01:00"
      environment = ToolEnvironment(
        base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "\(work)/gitconfig", "GIT_CONFIG_NOSYSTEM": "1",
               "GIT_EDITOR": "true", "GIT_AUTHOR_NAME": "Jörg Prüfer", "GIT_AUTHOR_EMAIL": "test@example.com",
               "GIT_COMMITTER_NAME": "Jörg Prüfer", "GIT_COMMITTER_EMAIL": "test@example.com", "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when],
        hostPath: HostPath(entries: ["\(work)/bin", "/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system,
        runtime: .repository, git: nil, bundledGitFailure: nil)
    }

    func path(_ relative: String) -> String { relative.isEmpty ? work : "\(work)/\(relative)" }
    func sub(_ text: String) -> String { text.replacingOccurrences(of: "@W@", with: work, options: .literal) }

    func service() -> CoreUpdate {
      CoreUpdate(environment: environment, snapshot: { [self] _, kind, label in
        self.snapshots.withLock { $0.append([kind, label]) }
        return "snap-1"
      }, templateRepository: path("upstream.git"))
    }

    func git(_ args: [String], _ dir: String) async -> CommandResult {
      await ProcessRunner.run(environment.command("git", args, in: URL(fileURLWithPath: dir)))
    }

    func act(_ action: JSONValue) async throws {
      let path = action["path"].map { self.path($0.stringValue!) }
      switch action["do"]!.stringValue! {
      case "write": try SnapshotStoreTests.Harness.write(path!, sub(action["text"]!.stringValue!))
      case "mkdir": try Posix.mkdirs(path!)
      case "remove": try? FileManager.default.removeItem(atPath: path!)
      case "symlink":
        try? FileManager.default.removeItem(atPath: path!)
        try Posix.symlink(sub(action["target"]!.stringValue!), path!)
      case "git":
        let result = await git(action["args"]!.arrayValue!.map { sub($0.stringValue!) }, path!)
        if !result.success && action["mayFail"] != .bool(true) { Issue.record("git \(JSJSON.compact(action["args"]!)): \(result.output)") }
      default: Issue.record("unknown action")
      }
    }

    func text(_ path: String) -> JSONValue {
      (try? Posix.read(path)).map { .string(String(decoding: $0, as: UTF8.self)) } ?? .null
    }

    func state(_ dir: String) async -> JSONValue {
      let p = path(dir)
      func out(_ args: [String]) async -> String { JS.trim(await git(args, p).stdout) }
      var content: JSONValue = .null
      if let kind = Posix.kind("\(p)/content") {
        content = kind == .link ? .string("link:\((try? Posix.readlink("\(p)/content")) ?? "")") : .string("folder")
      }
      let status = await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], p).stdout
      let stash = await git(["stash", "list", "--format=%gd %s"], p).stdout
      return JSONValue.object(JSONObject([
        ("head", .string(await out(["rev-parse", "-q", "--verify", "HEAD"]))), ("parents", .string(await out(["log", "-1", "--format=%P"]))),
        ("subject", .string(await out(["log", "-1", "--format=%s"]))), ("reflog", .string(await out(["reflog", "-1", "--format=%gs"]))),
        ("status", .array(status.components(separatedBy: "\0").filter { !$0.isEmpty }.map(JSONValue.string))),
        ("stash", .array(stash.components(separatedBy: "\n").filter { !$0.isEmpty }.map(JSONValue.string))),
        ("mergeHead", .string(await out(["rev-parse", "-q", "--verify", "MERGE_HEAD"]))),
        ("packageJson", text("\(p)/package.json")), ("lockfile", text("\(p)/package-lock.json")),
        ("note", text("\(p)/.quartz-gui/core-update.json")), ("content", content)
      ])).masked(work)
    }
  }

  static func json(_ result: CoreUpdate.Result) -> JSONValue {
    var fields: [(String, JSONValue)] = [("success", .bool(result.success)), ("output", .string(result.output))]
    if let id = result.snapshotId { fields.append(("snapshotId", .string(id))) }
    if let conflicts = result.conflicts { fields.append(("conflicts", .array(conflicts.map(JSONValue.string)))) }
    return .object(JSONObject(fields))
  }

  static func json(_ status: CoreUpdate.Status) -> JSONValue {
    var fields: [(String, JSONValue)] = [("currentCommit", .string(status.currentCommit)), ("latestCommit", .string(status.latestCommit)),
                                         ("state", .string(status.state.rawValue))]
    if let missing = status.missingCommits { fields.append(("missingCommits", .number(Double(missing)))) }
    if let packages = status.pendingPackages { fields.append(("pendingPackages", .array(packages.map(JSONValue.string)))) }
    return .object(JSONObject(fields))
  }

  /// QuartzControl's sentences are `mainT` stand-ins; rendered here in QuartzHub's catalog.
  static func rendered(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string(let text): .string(QC.render(text, mask: "@W@"))
    case .array(let items): .array(items.map(rendered))
    case .object(let object): .object(JSONObject(object.keys.map { ($0, rendered(object[$0]!)) }))
    default: value
    }
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let harness = try Harness()
    let service = harness.service()
    let steps = Self.file["steps"]!.arrayValue!
    #expect(steps.count == 85)
    for step in steps {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! { try await harness.act(action) }
      unlink(harness.path("npm-calls.log"))
      unlink(harness.path("npx-calls.log"))
      harness.snapshots.withLock { $0 = [] }
      let dir = step["dir"]!.stringValue!
      let project = URL(fileURLWithPath: harness.path(dir))
      var result: JSONValue = .null
      switch step["op"]!.stringValue! {
      case "update": result = Self.json(try await service.run(project: project))
      case "abort":
        let answer = try await service.abort(project: project)
        result = .object(JSONObject([("success", .bool(answer.success)), ("output", .string(answer.output)),
                                     ("sentences", .array(answer.sentences.map(JSONValue.string)))]))
      case "status": result = Self.json(await service.status(project: project, resolveInstalled: step["args"]?["resolveInstalled"] == .bool(true)))
      case "noteSucceeded": try service.noteInstallSucceeded(project: project)
      case "none": break
      default: Issue.record("unknown op")
      }
      var expected = Self.rendered(step["result"]!)
      // QuartzControl splits a refused abort's sentences at "\n\n" and trims them. Its `mainT`
      // stand-in answered JSON, which has no "\n\n", so the split happens here, on the sentences
      // as the catalog says them.
      if step["op"] == .string("abort"), expected["success"] == .bool(false), case .array(let sentences)? = expected["sentences"] {
        let split = sentences.flatMap { JSText.split($0.stringValue!, "\n\n").map(JS.trim).filter { !$0.isEmpty } }
        expected = expected.setting("sentences", .array(split.map(JSONValue.string)))
      }
      #expect(result.masked(harness.work) == expected, "\(name)\n\(JSJSON.compact(result.masked(harness.work)))\n\(JSJSON.compact(expected))")
      let npm = (harness.text(harness.path("npm-calls.log")).stringValue ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
        .map { try! JSJSON.parse(Data($0.utf8)) }
      #expect(JSONValue.array(npm) == step["npm"], "\(name): npm")
      #expect((harness.text(harness.path("npx-calls.log")).stringValue ?? "").replacingOccurrences(of: harness.work, with: "@W@", options: .literal) == step["npx"]!.stringValue!,
              "\(name): npx")
      #expect(JSONValue.array(harness.snapshots.withLock { $0 }.map { .array($0.map(JSONValue.string)) }) == step["snapshots"], "\(name): snapshots")
      let state = await harness.state(dir)
      #expect(state == step["state"], "\(name): state\n\(JSJSON.compact(state))\n\(JSJSON.compact(step["state"]!))")
    }
  }

  /// `explainGitFailure` over git's texts and the lists the abort hands in.
  @Test func explainsAsQuartzControl() {
    let texts = Self.file["texts"]!
    let cases = Self.file["explained"]!.arrayValue!
    #expect(cases.count == 84)
    for item in cases {
      let lists = item["args"]!.arrayValue!.map { $0.arrayValue!.map { $0.stringValue! } }
      func list(_ i: Int) -> [String] { i < lists.count ? lists[i] : [] }
      let text = texts[item["text"]!.stringValue!]!.stringValue!
      let actual = CoreUpdate.explain(text, editedSinceMerge: list(0), ownStaged: list(1), untrackedInTheWay: list(2),
                                      ownStagedOnMerge: list(3), declaredToAdd: list(4))
      #expect(actual == QC.render(item["result"]!.stringValue!, mask: "@W@"), "\(item["text"]!.stringValue!) \(JSJSON.compact(item["args"]!))")
    }
  }

  /// A second run or abort for the same project while one runs is answered at once.
  @Test func aSecondRunIsTurnedAway() async throws {
    let harness = try Harness()
    final class Flags: @unchecked Sendable {
      let started = Mutex(false)
      let release = Mutex(false)
    }
    let flags = Flags()
    let service = CoreUpdate(environment: harness.environment, snapshot: { _, _, _ in
      flags.started.withLock { $0 = true }
      while !flags.release.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
      return nil
    }, templateRepository: harness.path("nowhere.git"))
    let project = URL(fileURLWithPath: harness.path("p"))
    try Posix.mkdirs(project.path)
    _ = await harness.git(["init", "-q"], project.path)
    let first = Task { try await service.run(project: project) }
    while !flags.started.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
    let second = try await service.run(project: project)
    let abort = try await service.abort(project: project)
    flags.release.withLock { $0 = true }
    _ = try await first.value
    #expect(second == CoreUpdate.Result(success: false, output: L10n.t("main.updateAlreadyRunning")))
    #expect(abort.sentences == [L10n.t("main.updateAlreadyRunning")])
    #expect(try await service.abort(project: project).sentences != [L10n.t("main.updateAlreadyRunning")])
  }

  @Test func deadlines() {
    #expect(CoreUpdate.Deadlines().fetch == .seconds(60))
    #expect(CoreUpdate.Deadlines().lsRemote == .seconds(20))
  }

  /// The two names are a format both apps read on the same disk.
  @Test func namesAreQuartzControls() {
    #expect(CoreUpdate.stashName == "QuartzControl: core update")
    #expect(CoreUpdate.mergeMessage == "Merge quartz-upstream (via QuartzControl)")
  }
}
