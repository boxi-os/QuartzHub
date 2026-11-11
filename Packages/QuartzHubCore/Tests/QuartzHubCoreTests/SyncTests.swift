import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own syncService.ts (`scripts/git-golden.mjs`): each direction, with and
/// without commit and message, failures the CLI reports in prose and by exit code, the token for a
/// GitHub origin, and shallow clones completed from quartz-upstream, from the template, or not at
/// all. After each: the answer, how npx was called (argv, folder, prompt switch, what the helper
/// answers), whether the helper is gone, and whether the project is still shallow.
@Suite(.serialized) struct SyncTests {
  @Test func replaysQuartzControlsSteps() async throws {
    let golden = try GitGolden()
    var seen = 0
    try await golden.replay("sync") { step in
      seen += 1
      let name = step["name"]!.stringValue!
      let args = step["args"]!.arrayValue!
      let project = golden.url(args[0].stringValue!)
      unlink(golden.path("npx-calls.log"))
      unlink(golden.path("askpass-path"))
      let direction = args.count > 1 ? Sync.Direction(rawValue: args[1].stringValue!)! : .both
      var options = Sync.Options()
      if args.count > 2 {
        options.commit = args[2]["commit"] == .bool(true)
        options.message = args[2]["message"]?.stringValue
      }
      let token = golden.token.withLock { $0 }
      let result = await Sync.run(project: project, direction: direction, options: options, environment: golden.environment,
                                  token: { token }, templateRepository: golden.path("template"))

      let expected = step["result"]!
      #expect(result.success == (expected["success"] == .bool(true)), "\(name)")
      #expect(result.output.replacingOccurrences(of: golden.work, with: "@W@", options: .literal) == QC.render(expected["output"]!.stringValue!, mask: "@W@"),
              "\(name)\n\(result.output)")
      let calls = (try? Posix.read(golden.path("npx-calls.log"))).map { String(decoding: $0, as: UTF8.self) } ?? ""
      #expect(calls.replacingOccurrences(of: golden.work, with: "@W@", options: .literal) == step["calls"]!.stringValue!, "\(name)\n\(calls)")
      let left: JSONValue = (try? Posix.read(golden.path("askpass-path"))).map { .bool(Posix.exists(String(decoding: $0, as: UTF8.self))) } ?? .null
      #expect(left == step["askpassLeft"], "\(name): helper")
      let shallow = await ProcessRunner.run(golden.environment.command("git", ["rev-parse", "--is-shallow-repository"], in: project))
      #expect(JS.trim(shallow.stdout) == step["shallow"]!.stringValue!, "\(name): shallow")
    }
    #expect(seen == 23)
  }

  @Test func deadlines() {
    #expect(Sync.Deadlines().fetch == .seconds(600))
    #expect(Sync.Deadlines().sync == .seconds(1800))
  }

  /// A CLI that does not answer ends at the deadline, with its sentence, and the helper goes.
  @Test func aSyncThatHangsEnds() async throws {
    let golden = try GitGolden()
    try SnapshotStoreTests.Harness.write(golden.path("bin/npx"), "#!/bin/sh\nprintf '%s' \"$GIT_ASKPASS\" > '\(golden.path("askpass-path"))'\nsleep 30\n")
    let project = golden.url("p")
    try Posix.mkdirs(project)
    _ = await ProcessRunner.run(golden.environment.command("git", ["init", "-q"], in: project))
    _ = await ProcessRunner.run(golden.environment.command("git", ["remote", "add", "origin", "https://github.com/o/r"], in: project))
    // 2 s, not 0.5: twice in full runs the stand-in had not written its file when 0.5 s were up
    // (ENOENT, the test over at 0.55 and 0.61 s), so the launch itself took that long; not
    // reproduced in 58 further runs, alone, under load or in the suite (2026-11-11).
    var deadlines = Sync.Deadlines()
    deadlines.sync = .seconds(2)
    let result = await Sync.run(project: project, direction: .push, environment: golden.environment, token: { "t" }, deadlines: deadlines)
    #expect(!result.success)
    #expect(result.output.hasSuffix(L10n.t("main.commandTimeout", ["ms": "2000", "command": "npx quartz"])))
    let script = String(decoding: try Posix.read(golden.path("askpass-path")), as: UTF8.self)
    #expect(!script.isEmpty && !Posix.exists(script))
  }

  /// A fetch that does not answer ends at its deadline; the push is still tried.
  @Test func aFetchThatHangsEnds() async throws {
    let golden = try GitGolden()
    try await golden.act(.object(JSONObject([("do", .string("mkdir")), ("path", .string("full"))])))
    for args in [["init", "-q", "-b", "main"], ["commit", "-q", "--allow-empty", "-m", "one"], ["commit", "-q", "--allow-empty", "-m", "two"]] {
      try await golden.act(.object(JSONObject([("do", .string("git")), ("path", .string("full")), ("args", .array(args.map(JSONValue.string)))])))
    }
    try await golden.act(.object(JSONObject([("do", .string("git")), ("path", .string("")),
                                            ("args", .array(["clone", "-q", "--depth", "1", "file://\(golden.path("full"))", golden.path("sh")].map(JSONValue.string)))])))
    try SnapshotStoreTests.Harness.write(golden.path("bin/git"), "#!/bin/sh\ncase \"$1\" in\n  fetch) sleep 30 ;;\n  *) exec /usr/bin/git \"$@\" ;;\nesac\n")
    chmod(golden.path("bin/git"), 0o755)
    try SnapshotStoreTests.Harness.write(golden.path("npx-out.txt"), "Done!\n")
    var deadlines = Sync.Deadlines()
    deadlines.fetch = .milliseconds(500)
    let started = ContinuousClock.now
    let result = await Sync.run(project: golden.url("sh"), direction: .push, environment: golden.environment, token: { nil },
                                templateRepository: golden.path("full"), deadlines: deadlines)
    #expect(ContinuousClock.now - started < .seconds(10))
    #expect(result.success)
    #expect(result.output.hasPrefix(L10n.t("main.syncHistoryIncomplete")))
    #expect(result.output.contains(L10n.t("main.commandTimeout", ["ms": "500", "command": "git fetch"])))
    #expect(result.output.hasSuffix("Done!\n"))
  }

  /// The real `quartz sync` of a copy of gui-test, against a bare repository in the scratch folder:
  /// a push with a message, a pull and push, and a pull from an origin that is not there, which the
  /// CLI reports in prose and with exit 0.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["QH_QUARTZ_TESTS"] == "1", "QH_QUARTZ_TESTS=1"))
  func theRealQuartzSyncsACopyOfGuiTest() async throws {
    let scratch = try HostPathTests.Scratch()
    let work = TemplatePackageTests.realpath(scratch.url.path)
    let original = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/QuartzProjekte/gui-test")
    let copy = URL(fileURLWithPath: "\(work)/gui-test")
    try #require(await ProcessRunner.run(Command("/bin/cp", ["-cR", original.path, copy.path])).success)
    try SnapshotStoreTests.Harness.write("\(work)/gitconfig", "")
    var base = ProcessInfo.processInfo.environment
    base.merge(["GIT_CONFIG_GLOBAL": "\(work)/gitconfig", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0",
                "GIT_AUTHOR_NAME": "QuartzHub Test", "GIT_AUTHOR_EMAIL": "test@example.com",
                "GIT_COMMITTER_NAME": "QuartzHub Test", "GIT_COMMITTER_EMAIL": "test@example.com"]) { $1 }
    let environment = await ToolEnvironment.resolve(base: base, runtime: .repository, nodeMode: .embedded)
    func git(_ args: [String], in dir: URL = copy) async -> CommandResult { await ProcessRunner.run(environment.command("git", args, in: dir.path)) }

    // Never GitHub: origin is a bare repository here, for fetch and push, before anything runs.
    let bare = URL(fileURLWithPath: "\(work)/remote.git")
    try Posix.mkdirs(bare.path)
    try #require(await git(["init", "-q", "--bare", "-b", "v5"], in: bare).success)
    try #require(await git(["remote", "set-url", "origin", bare.path]).success)
    try #require(await git(["remote", "set-url", "--push", "origin", bare.path]).success)
    try #require(JS.trim(await git(["remote", "get-url", "--push", "origin"]).stdout) == bare.path)
    try #require(JS.trim(await git(["remote", "get-url", "origin"]).stdout) == bare.path)

    try SnapshotStoreTests.Harness.write("\(copy.path)/content/qh-sync-test.md", "# Sync\n")
    let pushed = await Sync.run(project: copy.path, direction: .push, options: .init(commit: true, message: "  QuartzHub sync test  "),
                                environment: environment, token: { nil })
    #expect(pushed.success, "\(pushed.output)")
    #expect(JS.trim(await git(["log", "-1", "--format=%s", "v5"], in: bare).stdout) == "QuartzHub sync test")
    #expect(await git(["cat-file", "-e", "v5:content/qh-sync-test.md"], in: bare).success)

    let both = await Sync.run(project: copy.path, direction: .both, options: .init(commit: false), environment: environment, token: { nil })
    #expect(both.success, "\(both.output)")

    try #require(await git(["remote", "set-url", "origin", "\(work)/nothing-here"]).success)
    let pulled = await Sync.run(project: copy.path, direction: .pull, options: .init(commit: false), environment: environment, token: { nil })
    #expect(!pulled.success)
    #expect(pulled.output.contains("An error occurred while pulling"), "\(pulled.output)")
    #expect(Posix.exists("\(copy.path)/content/qh-sync-test.md"))
  }
}
