import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own deploy/gitBranch.ts (`scripts/git-branch-golden.mjs`): 15 calls
/// against a local bare repository, with the same git, identity and dates, so the shas in the
/// output match; after each, origin's refs, the published branch (tree, subject, parents), the
/// project's worktrees, .quartz-gui/ and the .gitignore.
@Suite struct GitBranchTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/git-branch/steps.json")))

  final class Events: Sendable {
    let items = Mutex<[JSONValue]>([])
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 15)
    let root = TemplatePackageTests.realpath(TestFolder.make("qh-git-branch"))
    defer { try? FileManager.default.removeItem(atPath: root) }
    try Posix.write("\(root)/gitconfig", Data())
    var base = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "\(root)/gitconfig", "GIT_CONFIG_NOSYSTEM": "1", "GIT_EDITOR": "true"]
    let identity = Self.golden["identity"]!.objectValue!
    for key in identity.keys { base[key] = identity[key]!.stringValue! }
    let environment = ToolEnvironment(base: base, hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    let W = { (text: String) in text.replacingOccurrences(of: "@W@", with: root, options: .literal) }
    let mask = { (text: String) in text.replacingOccurrences(of: root, with: "@W@", options: .literal) }
    let project = "\(root)/Gärten-Ü", origin = "\(root)/origin.git"
    let adapter = GitBranchAdapter(environment: environment, token: { nil }, now: { Date(timeIntervalSince1970: 1_793_959_200) })
    func git(_ args: [String], _ dir: String) async -> CommandResult { await ProcessRunner.run(environment.command("git", args, in: dir)) }

    for step in steps {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! {
        if let write = action["write"]?.arrayValue {
          let path = W(write[0].stringValue!)
          try Posix.mkdirs(NodePath.dirname(path))
          try Posix.write(path, Data(write[1].stringValue!.utf8))
        }
        if let rm = action["rm"]?.stringValue { try? FileManager.default.removeItem(atPath: W(rm)) }
        if let change = action["chmod"]?.arrayValue { _ = chmod(W(change[0].stringValue!), mode_t(change[1].stringValue!, radix: 8)!) }
        if let call = action["git"]?.arrayValue {
          let result = await git(call[1].arrayValue!.map { W($0.stringValue!) }, W(call[0].stringValue!))
          #expect(result.success, "\(name): setup git \(result.output)")
        }
      }
      let target = PublishTarget(object: try JSJSON.parse(Data(W(JSJSON.compact(step["target"]!)).utf8)).objectValue!)
      let events = Events()
      var context = DeployContext(project: project, target: target, buildDir: "\(root)/build")
      context.progress = { processed, total, file in
        events.items.withLock {
          $0.append(.object(JSONObject([("processed", .number(Double(processed))), ("total", .number(Double(total))),
                                        ("currentFile", file.map(JSONValue.string) ?? .null)])))
        }
      }
      var actual: JSONValue
      do {
        if step["op"] == .string("preview") {
          actual = .object(JSONObject([("ok", .array(try await adapter.preview(context).map(\.json)))]))
        } else {
          let result = try await adapter.run(context, excluding: ["index.html"])
          actual = .object(JSONObject([("ok", .object(JSONObject([("success", .bool(result.success)), ("output", .string(result.output))])))]))
        }
      } catch {
        actual = .object(JSONObject([("error", .string(error.message))]))
      }
      let want = JSJSON.compact(GoldenText.localize(step["result"]!))
      #expect(mask(JSJSON.compact(actual)) == want, "\(name): \(mask(JSJSON.compact(actual)))\nvs \(want)")
      #expect(JSJSON.compact(.array(events.items.withLock { $0 })) == JSJSON.compact(step["events"]!), "\(name): events")

      let state = step["state"]!
      let refs = await git(["for-each-ref", "--format=%(refname) %(objectname)"], origin).stdout
      #expect(mask(refs) == state["refs"]!.stringValue!, "\(name): refs\n\(refs)")
      let branches = state["branches"]!.objectValue!
      for ref in branches.keys {
        let want = branches[ref]!
        let sha = want["sha"]!.stringValue!
        #expect(await git(["log", "-1", "--format=%s", sha], origin).stdout == want["subject"]!.stringValue!, "\(name): \(ref) subject")
        #expect(JS.trim(await git(["log", "-1", "--format=%P", sha], origin).stdout) == want["parents"]!.stringValue!, "\(name): \(ref) parents")
        let tree = JSText.split(await git(["ls-tree", "-r", "-z", sha], origin).stdout, "\0").filter { !$0.isEmpty }
        #expect(tree == want["tree"]!.arrayValue!.map { $0.stringValue! }, "\(name): \(ref) tree")
      }
      let worktrees = JSText.split(await git(["worktree", "list", "--porcelain"], project).stdout, "\n").filter { $0.hasPrefix("worktree ") }.map(mask)
      #expect(worktrees == state["worktrees"]!.arrayValue!.map { $0.stringValue! }, "\(name): worktrees \(worktrees)")
      let gui = Posix.entries("\(project)/.quartz-gui").map { JSONValue.array($0.map { .string($0.name) }) } ?? .null
      #expect(gui == state["gui"]!, "\(name): .quartz-gui \(gui)")
      let ignore = (try? Posix.read("\(project)/.gitignore")).map { JSONValue.string(String(decoding: $0, as: UTF8.self)) } ?? .null
      #expect(JSJSON.compact(ignore) == JSJSON.compact(GoldenText.localize(state["gitignore"]!)), "\(name): .gitignore")
    }
  }

  /// Review 2026-11-11, N2: a branch from the file reached `git fetch origin <branch>`, and with a
  /// path remote `--upload-pack=…` ran a command. The adapter refuses the name before any git.
  @Test func aBranchThatIsAnOptionNeverReachesGit() async throws {
    let root = TemplatePackageTests.realpath(TestFolder.make("qh-git-branch-option"))
    defer { try? FileManager.default.removeItem(atPath: root) }
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1"],
                                      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    let project = "\(root)/p", pwned = "\(root)/pwned"
    try Posix.mkdirs(project)
    try Posix.mkdirs("\(root)/build")
    for args in [["init", "-q", "--bare", "\(root)/origin.git"], ["-C", project, "init", "-q"], ["-C", project, "remote", "add", "origin", "\(root)/origin.git"]] {
      #expect(await ProcessRunner.run(environment.command("git", args, in: root)).success)
    }
    let branch = "--upload-pack=touch \(pwned); false"
    let target = PublishTarget(object: JSONObject([("id", .string("t")), ("name", .string("T")),
                                                   ("destination", .object(JSONObject([("type", .string("git-branch")), ("provider", .string("github")), ("branch", .string(branch))])))]))
    let adapter = GitBranchAdapter(environment: environment, token: { nil })
    let context = DeployContext(project: project, target: target, buildDir: "\(root)/build")
    await #expect(throws: PublishFailure(L10n.t("main.deployBadBranch", ["branch": branch]))) { try await adapter.preview(context) }
    let run = try? await adapter.run(context, excluding: [])
    #expect(run == nil || run?.success == false)
    #expect(!FileManager.default.fileExists(atPath: pwned))
  }

  /// A remote that never answers ends at the deadline with git's timeout sentence instead of a
  /// page that runs for good (review 2026-11-11, nebenbei 5): first the fetch hangs, and nothing
  /// is pushed after it; then the fetch fails at once and the push hangs. The "server" is an ssh
  /// command that sleeps; no network.
  @Test func aRemoteThatNeverAnswersEndsAtTheDeadline() async throws {
    let root = TemplatePackageTests.realpath(TestFolder.make("qh-git-branch-hang"))
    defer { try? FileManager.default.removeItem(atPath: root) }
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1",
                                             "GIT_CONFIG_GLOBAL": "/dev/null"],
                                      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    let project = "\(root)/p", hang = "\(root)/hang.sh", reached = "\(root)/reached", fetchFails = "\(root)/fetch-fails"
    try Posix.mkdirs(project)
    try Posix.mkdirs("\(root)/build")
    try Posix.write("\(root)/build/index.html", Data("x".utf8))
    try Posix.write(hang, Data("""
      #!/bin/sh
      echo "$@" >> '\(reached)'
      case "$*" in *upload-pack*) [ -f '\(fetchFails)' ] && exit 128 ;; esac
      exec sleep 30

      """.utf8))
    #expect(chmod(hang, 0o755) == 0)
    for args in [["-C", project, "init", "-q"], ["-C", project, "remote", "add", "origin", "ssh://qh-hang.invalid/site.git"],
                 ["-C", project, "config", "core.sshCommand", hang],
                 // Without it git first asks the command "-G" to learn which ssh it is.
                 ["-C", project, "config", "ssh.variant", "ssh"],
                 // The worktree needs a HEAD, or the run ends before the push.
                 ["-C", project, "-c", "user.name=T", "-c", "user.email=t@example.org", "commit", "-q", "--allow-empty", "-m", "x"]] {
      #expect(await ProcessRunner.run(environment.command("git", args, in: root)).success)
    }
    let target = PublishTarget(object: JSONObject([("id", .string("t")), ("name", .string("T")),
                                                   ("destination", .object(JSONObject([("type", .string("git-branch")), ("provider", .string("github")), ("branch", .string("gh-pages"))])))]))
    var deadlines = GitBranchAdapter.Deadlines()
    deadlines.fetch = .seconds(1)
    deadlines.push = .seconds(1)
    let adapter = GitBranchAdapter(environment: environment, token: { nil }, deadlines: deadlines)
    let context = DeployContext(project: project, target: target, buildDir: "\(root)/build")
    let calls = { (try? String(decoding: Posix.read(reached), as: UTF8.self)) ?? "" }

    var started = ContinuousClock.now
    var run = try await adapter.run(context, excluding: [])
    #expect(ContinuousClock.now - started < .seconds(15))
    #expect(!run.success && run.output.contains("git fetch"), "\(run.output)")
    #expect(calls().contains("git-upload-pack") && !calls().contains("git-receive-pack"), "\(calls())")

    try Posix.write(fetchFails, Data())
    started = ContinuousClock.now
    run = try await adapter.run(context, excluding: [])
    #expect(ContinuousClock.now - started < .seconds(15))
    #expect(!run.success && run.output.contains("git push"), "\(run.output)")
    #expect(calls().contains("git-receive-pack"), "\(calls())")
  }

  @Test func readsNameStatusAsQuartzControl() {
    let raw = "M\0ä.html\0A\0neu ö.html\0D\0alt\0T\0link\0R100\0a\0b\0\0\0X\0y\0"
    #expect(GitBranchAdapter.parseNameStatus(raw) == [
      .init(path: "ä.html", status: .changed), .init(path: "neu ö.html", status: .added), .init(path: "alt", status: .removed),
      .init(path: "link", status: .changed)
    ])
  }
}
