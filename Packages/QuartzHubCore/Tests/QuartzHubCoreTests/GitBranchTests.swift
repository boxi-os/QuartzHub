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

  @Test func readsNameStatusAsQuartzControl() {
    let raw = "M\0ä.html\0A\0neu ö.html\0D\0alt\0T\0link\0R100\0a\0b\0\0\0X\0y\0"
    #expect(GitBranchAdapter.parseNameStatus(raw) == [
      .init(path: "ä.html", status: .changed), .init(path: "neu ö.html", status: .added), .init(path: "alt", status: .removed),
      .init(path: "link", status: .changed)
    ])
  }
}
