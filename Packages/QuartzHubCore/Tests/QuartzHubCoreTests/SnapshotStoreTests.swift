import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own snapshotService.ts with real git: `scripts/snapshots-golden.mjs`
/// ran 70 steps (creating, skipping, coalescing, comparing, the content switch, a file the index
/// keeps although the project ignores it, restoring everything, two files, with the HEAD, through
/// a linked vault, 2150 named paths; the old config backups; thinning by day, week and month; the
/// failures) and recorded answer, calls and the state after each: the store's refs with their
/// commit objects and trees, its index and exclude file, and every file of the folder.
@Suite(.serialized) struct SnapshotStoreTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/snapshots")

  /// A work folder like the golden script's, with the same clock, git config and stand-ins.
  final class Harness: @unchecked Sendable {
    let scratch: HostPathTests.Scratch
    let work: String
    let environment: ToolEnvironment
    /// The clock and the calls of the stand-ins, shared with their closures.
    final class Box: Sendable {
      let now = Mutex(Date())
      let tail = Mutex(0)
      let calls = Mutex<[[String]]>([])
    }
    let box = Box()
    var calls: [[String]] { box.calls.withLock { $0 } }
    var store: SnapshotStore!

    /// The store's own prune expiry, so its default is what the tests see.
    init() throws {
      scratch = try HostPathTests.Scratch(umlaut: true)
      work = TemplatePackageTests.realpath(scratch.path)
      try Posix.write("\(work)/gitconfig", Data())
      environment = ToolEnvironment(
        base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "\(work)/gitconfig", "GIT_CONFIG_NOSYSTEM": "1"],
        hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system,
        runtime: .repository, git: nil, bundledGitFailure: nil)
      let clock = SnapshotStore.Clock(
        now: { [box] in box.now.withLock { $0 } },
        tail: { [box] in box.tail.withLock { $0 += 1; return String(format: "%04d", $0) } },
        pinsGit: true)
      let work = work
      store = SnapshotStore(
        environment: environment,
        npm: { [box] project in
          box.calls.withLock { $0.append(["npm", "install", project.replacingOccurrences(of: work, with: "@W@", options: .literal)]) }
          return PluginCommands.Result(success: true, output: "npm stub")
        },
        repoint: { [box] project in box.calls.withLock { $0.append(["repoint", project.replacingOccurrences(of: work, with: "@W@", options: .literal)]) } },
        clock: clock)
    }

    /// A path as a string: `URL.path` hands a name back decomposed as well.
    func path(_ relative: String) -> String { "\(work)/\(relative)" }
    /// The project as the store takes it: a string with the bytes of the disk.
    func url(_ relative: String) -> String { path(relative) }
    func mask(_ text: String) -> String { text.replacingOccurrences(of: work, with: "@W@", options: .literal) }

    @discardableResult
    func git(_ arguments: [String], in dir: String, env: [String: String] = [:]) async throws -> String {
      let result = await ProcessRunner.run(environment.command("git", arguments, in: dir).adding(env))
      guard result.success else { throw SnapshotStore.Failure(message: "git \(arguments): \(result.output)") }
      return result.stdout
    }

    /// Through POSIX, as Node writes: Foundation decomposes a name on its way to the disk ("Über"
    /// arrives as U+0055 U+0308), and the listing compares bytes.
    static func mkdirs(_ path: String) {
      var built = ""
      for part in path.split(separator: "/") {
        built += "/\(part)"
        mkdir(built, 0o755)
      }
    }

    static func write(_ path: String, _ text: String) throws {
      mkdirs((path as NSString).deletingLastPathComponent)
      let fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0o644)
      guard fd >= 0 else { throw NodeFileError(code: errno, syscall: "open", path: path) }
      defer { close(fd) }
      let bytes = Array(text.utf8)
      guard bytes.isEmpty || Darwin.write(fd, bytes, bytes.count) == bytes.count else { throw NodeFileError(code: errno, syscall: "write", path: path) }
    }

    func act(_ action: JSONValue) async throws {
      let path = action["path"]?.stringValue.map(self.path)
      let manager = FileManager.default
      switch action["do"]!.stringValue! {
      case "write":
        try Self.write(path!, action["text"]!.stringValue!)
      case "many":
        Self.mkdirs(path!)
        for i in 0 ..< Int(action["count"]!.numberValue!) {
          try Self.write(path! + String(format: "/n%04d.md", i), "\(action["text"]!.stringValue!) \(i)\n")
        }
      case "remove":
        try? manager.removeItem(atPath: path!)
      case "chmod":
        try manager.setAttributes([.posixPermissions: Int(action["mode"]!.stringValue!, radix: 8)!], ofItemAtPath: path!)
      case "symlink":
        Self.mkdirs((path! as NSString).deletingLastPathComponent)
        symlink(action["target"]!.stringValue!.replacingOccurrences(of: "@W@", with: work, options: .literal), path!)
      case "git":
        let when = action["when"]?.stringValue ?? "2026-11-01T00:00:00Z"
        try await git(action["args"]!.arrayValue!.map { $0.stringValue! }, in: path!, env: [
          "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com", "GIT_COMMITTER_NAME": "Test",
          "GIT_COMMITTER_EMAIL": "test@example.com", "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when,
        ])
      case "handRef":
        let store = "\(path!)/.quartz-gui/snapshots.git"
        let tree = JS.trim(try await git(["--git-dir", store, "rev-parse", "refs/snapshots/\(action["from"]!.stringValue!)^{tree}"], in: work))
        let commit = JS.trim(try await git(["--git-dir", store, "commit-tree", tree, "-m", ""], in: work, env: [
          "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com", "GIT_COMMITTER_NAME": "Test",
          "GIT_COMMITTER_EMAIL": "test@example.com", "GIT_AUTHOR_DATE": "2026-11-06T09:00:00Z", "GIT_COMMITTER_DATE": "2026-11-06T09:00:00Z",
        ]))
        try await git(["--git-dir", store, "update-ref", "refs/snapshots/\(action["id"]!.stringValue!)", commit], in: work)
      case "clock":
        let date = SnapshotStore.date(action["at"]!.stringValue!)!
        box.now.withLock { $0 = date }
      default:
        Issue.record("unknown action \(action)")
      }
    }

    // MARK: State, as the golden script records it

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func utf16Order(_ a: String, _ b: String) -> Bool { a.utf16.lexicographicallyPrecedes(b.utf16) }

    func listing(_ root: String) -> JSONValue {
      var files: [(String, JSONValue)] = []
      func walk(_ dir: String, _ rel: String) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted(by: Self.utf16Order)
        for name in names {
          let full = "\(dir)/\(name)"
          let path = rel.isEmpty ? name : "\(rel)/\(name)"
          if path == ".git" || path == ".quartz-gui/snapshots.git" { continue }
          var info = stat()
          lstat(full, &info)
          switch info.st_mode & S_IFMT {
          case S_IFLNK:
            files.append((path, .string("link:\(mask((try? FileManager.default.destinationOfSymbolicLink(atPath: full)) ?? ""))")))
          case S_IFDIR:
            files.append(("\(path)/", .string("dir")))
            walk(full, path)
          default:
            let mode = info.st_mode & 0o777
            let content = mode & 0o400 != 0 ? Self.sha((try? Posix.read(full)) ?? Data()) : "unreadable"
            files.append((path, .string("\(String(mode, radix: 8)) \(content)")))
          }
        }
      }
      if FileManager.default.fileExists(atPath: path(root)) { walk(path(root), "") }
      let object = JSONValue.object(JSONObject(files))
      if files.count > 200 {
        return .object(JSONObject([("count", .number(Double(files.count))), ("digest", .string(Self.sha(Data(JSJSON.compact(object).utf8))))]))
      }
      return object
    }

    func storeState(_ root: String) async throws -> JSONValue {
      let store = path("\(root)/.quartz-gui/snapshots.git")
      guard FileManager.default.fileExists(atPath: "\(store)/HEAD") else { return .null }
      let g = { (args: [String]) async throws -> String in try await self.git(["--git-dir", store] + args, in: self.work) }
      var refs: [JSONValue] = []
      for line in try await g(["for-each-ref", "--format=%(refname) %(objectname)", "refs/snapshots/"]).split(separator: "\n") {
        let parts = line.split(separator: " ").map(String.init)
        let object = JSText.replaceAll(try await g(["cat-file", "commit", parts[1]]), #"(?m)^(author|committer) .* <[^>]*>"#, template: "$1 @ID@")
        let tree = try await g(["ls-tree", "-r", "-z", parts[1]]).components(separatedBy: "\0").filter { !$0.isEmpty }
        refs.append(.object(JSONObject([("ref", .string(parts[0])), ("object", .string(object)),
                                        ("tree", .string(Self.sha(Data(tree.joined(separator: "\n").utf8))))])))
      }
      var index: JSONValue = .null
      if FileManager.default.fileExists(atPath: "\(store)/index") {
        let lines = try await g(["ls-files", "-s", "-z"]).components(separatedBy: "\0").filter { !$0.isEmpty }
        index = lines.count > 200
          ? .object(JSONObject([("count", .number(Double(lines.count))), ("digest", .string(Self.sha(Data(lines.joined(separator: "\n").utf8))))]))
          : .array(lines.map(JSONValue.string))
      }
      let exclude = (try? String(contentsOfFile: "\(store)/info/exclude", encoding: .utf8)).map(JSONValue.string) ?? .null
      return .object(JSONObject([("refs", .array(refs)), ("index", index), ("exclude", exclude)]))
    }

    // MARK: Calls

    func snapshotJSON(_ s: SnapshotStore.Snapshot) -> JSONValue {
      var fields: [(String, JSONValue)] = [("id", .string(s.id)), ("commit", .string(s.commit)), ("createdAt", .string(s.createdAt)),
                                           ("kind", .string(s.kind)), ("label", .string(s.label))]
      if let head = s.projectHead { fields.append(("projectHead", .string(head))) }
      return .object(JSONObject(fields))
    }

    func settingsJSON(_ s: SnapshotStore.Settings) -> JSONValue {
      .object(JSONObject([("includeContent", .bool(s.includeContent)), ("contentExists", .bool(s.contentExists)),
                          ("contentIsSymlink", .bool(s.contentIsSymlink))]))
    }

    func call(_ op: String, root: String, args: [JSONValue]) async throws -> JSONValue {
      let project = url(root)
      let string = { (i: Int) in args[i].stringValue! }
      switch op {
      case "list": return .array(await store.list(project: project).map(snapshotJSON))
      case "settings": return settingsJSON(store.settings(project: project))
      case "saveSettings": return settingsJSON(try await store.saveSettings(project: project, includeContent: args[0] == .bool(true)))
      case "create": return try await store.create(project: project, kind: string(0), label: string(1)).map(snapshotJSON) ?? .null
      case "diff":
        return .array(try await store.diff(project: project, id: string(0)).map {
          .object(JSONObject([("path", .string($0.path)), ("status", .string($0.status.rawValue))]))
        })
      case "fileDiff": return .string(try await store.fileDiff(project: project, id: string(0), path: string(1)))
      case "restore":
        let options = args.count > 1 ? args[1] : .object(JSONObject())
        let result = try await store.restore(project: project, id: string(0), paths: options["paths"]?.arrayValue?.map { $0.stringValue! },
                                             resetProjectHead: options["resetProjectHead"] == .bool(true))
        return .object(JSONObject([("success", .bool(result.success)), ("output", .string(mask(result.output)))]))
      case "delete":
        try await store.delete(project: project, id: string(0))
        return .null
      case "migrate": return .number(Double(try await store.migrateConfigBackups(project: project)))
      case "prune": return .number(Double(try await store.pruneAutomatic(project: project)))
      case "export":
        let target = url("exports/\(string(0)).zip")
        try Posix.mkdirs(NodePath.dirname(target))
        try await store.export(project: project, id: string(0), to: target)
        defer { try? FileManager.default.removeItem(atPath: target) }
        let files = try ZipArchive.read(contentsOf: target)
        return .object(JSONObject(files.names.sorted(by: Self.utf16Order).map { ($0, .string(Self.sha(files[$0]!))) }))
      default:
        Issue.record("unknown op \(op)")
        return .null
      }
    }
  }

  /// Key order does not count, commit ids differ by the identity (compared as objects), and
  /// mainT's stand-in text becomes the catalog's.
  static func canon(_ value: JSONValue?) -> JSONValue {
    switch value {
    case .object(let object)?:
      return .object(JSONObject(object.keys.filter { $0 != "commit" }.sorted().map { ($0, canon(object[$0])) }))
    case .array(let items)?:
      return .array(items.map(canon))
    case .string(let text)?:
      return .string(QC.render(text, mask: "@W@"))
    case let other?: return other
    case nil: return .null
    }
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let golden = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps.json")))
    let steps = golden["steps"]!.arrayValue!
    #expect(steps.count == 70)
    let h = try Harness()
    for step in steps {
      let name = step["name"]!.stringValue!
      let root = step["root"]!.stringValue!
      for action in step["setup"]!.arrayValue! { try await h.act(action) }
      h.box.calls.withLock { $0 = [] }
      var result: JSONValue = .null, failure: String?
      let args = step["args"]!.arrayValue!
      do {
        result = try await h.call(step["op"]!.stringValue!, root: root, args: args)
      } catch {
        failure = h.mask("\(error)")
      }
      let error = failure
      let differs = step["qhDiffers"]?.stringValue
      switch differs {
      case "projectHead":
        // QuartzControl wrote git's error into the subject; here the head is "-" and the label stays.
        #expect(error == nil, "\(name): \(error ?? "")")
        #expect(result["projectHead"] == nil && result["label"] == args[1], "\(name): \(result)")
        #expect(step["result"]!["projectHead"]!.stringValue!.hasPrefix("fatal:"), "\(name): the golden's head")
      case "contentLeftOut":
        // QuartzControl listed the notes of a content folder switched off as removed since; they
        // are neither compared nor restored here (review 2026-11-11, H1).
        #expect(error == nil, "\(name): \(error ?? "")")
        let kept = step["result"]!.arrayValue!.filter { !SnapshotStore.isContent($0["path"]!.stringValue!) }
        #expect(Self.canon(result) == Self.canon(.array(kept)), "\(name): \(result)")
      case "settings":
        #expect(Self.canon(result) == Self.canon(h.settingsJSON(.init(includeContent: true, contentExists: true, contentIsSymlink: false))), "\(name): \(result)")
      default:
        if let expected = step["error"]?.stringValue {
          #expect(error == QC.render(expected, mask: "@W@"), "\(name): \(error ?? JSJSON.compact(result))")
        } else {
          #expect(error == nil, "\(name): \(error ?? "")")
          #expect(Self.canon(result) == Self.canon(step["result"]), "\(name):\n\(JSJSON.compact(Self.canon(result)))\n\(JSJSON.compact(Self.canon(step["result"])))")
        }
      }
      let calls = JSONValue.array(h.calls.map { .array($0.map(JSONValue.string)) })
      #expect(calls == step["calls"], "\(name): calls \(calls)")

      let state = step["state"]!.objectValue!
      for folder in state.keys {
        let expected = state[folder]!
        let files = h.listing(folder)
        // By bytes: Swift's == takes "Ü" and "U\u{308}" for one string, and the disk does not.
        #expect(Array(JSJSON.compact(files).utf8) == Array(JSJSON.compact(expected["files"]!).utf8), "\(name): files of \(folder)\n\(JSJSON.compact(files))\n\(JSJSON.compact(expected["files"]!))")
        let store = try await h.storeState(folder)
        if differs == "projectHead", case .object(let got) = store, case .object(let want)? = expected["store"] {
          // Only the subject of the new commit differs.
          let strip = { (refs: JSONValue?) in refs?.arrayValue?.map { JSONValue.object(JSONObject([("ref", $0["ref"]!), ("tree", $0["tree"]!)])) } }
          #expect(strip(got["refs"]) == strip(want["refs"]), "\(name): refs")
          #expect(got["index"] == want["index"] && got["exclude"] == want["exclude"], "\(name): index")
          let objects = got["refs"]!.arrayValue!.map { $0["object"]!.stringValue! }
          #expect(objects.contains { $0.hasSuffix("\n\nmanual - \(args[1].stringValue!)\n") }, "\(name): \(objects)")
        } else if differs == "storeIndex", case .object(let got) = store, case .object(let want)? = expected["store"] {
          // A restore that leaves content/ alone leaves it out of the store's index too, until the
          // next staging drops it there as well; everything else is QuartzControl's.
          let withoutContent = { (index: JSONValue?) in index?.arrayValue?.filter { !SnapshotStore.isContent(String($0.stringValue!.split(separator: "\t", maxSplits: 1).last ?? "")) } }
          #expect(got["refs"] == want["refs"] && got["exclude"] == want["exclude"], "\(name): refs")
          #expect(withoutContent(got["index"]) == withoutContent(want["index"]), "\(name): index\n\(JSJSON.compact(got["index"]!))")
          #expect(got["index"] != want["index"], "\(name): the golden's index had content/")
        } else {
          #expect(store == expected["store"], "\(name): store of \(folder)\n\(JSJSON.compact(store))\n\(JSJSON.compact(expected["store"]!))")
        }
      }
    }
  }

  // MARK: - Both apps on one store

  /// A project of a few files with a commit, for the tests below.
  static func project(_ h: Harness) async throws -> String {
    try Harness.write(h.path("p/quartz.config.yaml"), "configuration:\n  pageTitle: Eins\n")
    try Harness.write(h.path("p/content/Über.md"), "Über\n")
    try Harness.write(h.path("p/.gitignore"), ".quartz-gui/\n")
    let env = ["GIT_AUTHOR_NAME": "T", "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "T", "GIT_COMMITTER_EMAIL": "t@example.com"]
    for args in [["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-q", "-m", "Initial"]] { try await h.git(args, in: h.path("p"), env: env) }
    return h.url("p")
  }

  /// QuartzControl's snapshotService.ts as a command (`qc-snapshots.cjs`), in the same environment.
  static func quartzControl(_ h: Harness, _ op: String, _ project: String, _ args: [JSONValue] = []) async -> JSONValue {
    let node = "\(RuntimeLocation.repository.nodeBin)/node"
    let script = fixtures.appendingPathComponent("qc-snapshots.cjs").path
    let result = await ProcessRunner.run(h.environment.command(node, [script, op, project, JSJSON.compact(.array(args))]))
    return (try? JSJSON.parse(Data(result.stdout.utf8))) ?? .object(JSONObject([("error", .string(result.output))]))
  }

  @Test func quartzControlReadsWritesAndRestoresTheSameStore() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)

    let ours = try await h.store.create(project: p, kind: "manual", label: "von QuartzHub")!
    try Harness.write(h.path("p/quartz.config.yaml"), "configuration:\n  pageTitle: Zwei\n")
    let theirs = await Self.quartzControl(h, "create", p, [.string("manual"), .string("von QuartzControl")])["result"]!
    #expect(theirs["label"] == .string("von QuartzControl"), "\(theirs)")

    // One list, read by both.
    let listed = await h.store.list(project: p).map(h.snapshotJSON)
    let theyList = await Self.quartzControl(h, "list", p)["result"]!
    #expect(Self.canon(.array(listed)) == Self.canon(theyList))
    #expect(listed.map { $0["id"]! } == [theirs["id"]!, .string(ours.id)])

    // The same comparison of our snapshot, from both sides.
    try Harness.write(h.path("p/content/neu.md"), "neu\n")
    let diff = try await h.store.diff(project: p, id: ours.id).map { JSONValue.object(JSONObject([("path", .string($0.path)), ("status", .string($0.status.rawValue))])) }
    #expect(.array(diff) == (await Self.quartzControl(h, "diff", p, [.string(ours.id)]))["result"])
    #expect(diff.count == 2, "\(diff)")

    // QuartzControl restores ours, we restore theirs.
    let restored = await Self.quartzControl(h, "restore", p, [.string(ours.id)])
    #expect(restored["result"]?["success"] == .bool(true), "\(restored)")
    #expect(try String(contentsOfFile: h.path("p/quartz.config.yaml"), encoding: .utf8) == "configuration:\n  pageTitle: Eins\n")
    #expect(!FileManager.default.fileExists(atPath: h.path("p/content/neu.md")))
    let back = try await h.store.restore(project: p, id: theirs["id"]!.stringValue!)
    #expect(back.success, "\(back.output)")
    #expect(try String(contentsOfFile: h.path("p/quartz.config.yaml"), encoding: .utf8) == "configuration:\n  pageTitle: Zwei\n")
    let fsck = await ProcessRunner.run(h.environment.command("git", ["--git-dir", h.path("p/.quartz-gui/snapshots.git"), "fsck", "--no-dangling"]))
    #expect(fsck.success, "\(fsck.output)")
  }

  /// Both apps writing at once: QuartzControl's index is never ours, so neither meets the other's
  /// index.lock, and every snapshot is whole.
  @Test func bothAppsAtOnce() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    _ = try await h.store.create(project: p, kind: "manual", label: "Anfang")
    let rounds = 8
    async let ours: [String] = {
      var failures: [String] = []
      for i in 0 ..< rounds {
        do { _ = try await h.store.create(project: p, kind: "manual", label: "QH \(i)") } catch { failures.append("\(error)") }
      }
      return failures
    }()
    async let theirs: [String] = {
      var failures: [String] = []
      for i in 0 ..< rounds {
        let answer = await Self.quartzControl(h, "create", p, [.string("manual"), .string("QC \(i)")])
        if let error = answer["error"] { failures.append(JSJSON.compact(error)) }
        // QuartzControl checks neither commit-tree nor update-ref: a failure comes back as a result
        // whose commit is git's error text.
        if let commit = answer["result"]?["commit"]?.stringValue, commit.wholeMatch(of: /[0-9a-f]{40}/) == nil {
          failures.append("QC \(i): \(commit)")
        }
      }
      return failures
    }()
    let (a, b) = await (ours, theirs)
    #expect(a.isEmpty, "QuartzHub: \(a)")
    #expect(b.isEmpty, "QuartzControl: \(b)")
    let listed = await h.store.list(project: p)
    #expect(listed.count == 1 + 2 * rounds, "\(listed.map { "\($0.id) \($0.label)" })")
    let fsck = await ProcessRunner.run(h.environment.command("git", ["--git-dir", h.path("p/.quartz-gui/snapshots.git"), "fsck", "--no-dangling"]))
    #expect(fsck.success, "\(fsck.output)")
  }

  /// While QuartzControl holds the store's index.lock, an operation here runs on its copy and
  /// leaves both the index and the lock alone.
  @Test func aHeldIndexLockIsLeftAlone() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    _ = try await h.store.create(project: p, kind: "manual", label: "eins")
    let store = h.path("p/.quartz-gui/snapshots.git")
    let index = try Posix.read("\(store)/index")
    try Posix.write("\(store)/index.lock", Data("held".utf8))
    try Harness.write(h.path("p/neu.md"), "neu\n")
    let second = try await h.store.create(project: p, kind: "manual", label: "zwei")
    #expect(second != nil)
    #expect(try Posix.read("\(store)/index") == index)
    #expect(try String(contentsOfFile: "\(store)/index.lock", encoding: .utf8) == "held")
    try FileManager.default.removeItem(atPath: "\(store)/index.lock")
    _ = try await h.store.create(project: p, kind: "manual", label: "drei")
    #expect(try Posix.read("\(store)/index") != index, "written back once the lock is free")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: store).filter { $0.hasPrefix("qh-index-") }
    #expect(leftovers.isEmpty, "\(leftovers)")
  }

  /// Putting the copy back never holds the store's index.lock, not even for a moment: QuartzControl's
  /// `write-tree` takes that lock as well, and meeting it took git's error for a tree and answered
  /// with a snapshot that names nothing (bothAppsAtOnce, QC 4 missing, 2026-11-11). Watched from a
  /// thread of its own while the store writes and puts back twenty times.
  @Test func puttingTheIndexBackTakesNoLock() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    _ = try await h.store.create(project: p, kind: "manual", label: "Anfang")
    let lock = h.path("p/.quartz-gui/snapshots.git/index.lock")
    let watching = Mutex(true), seen = Mutex(0)
    let watcher = Thread {
      while watching.withLock({ $0 }) { if access(lock, F_OK) == 0 { seen.withLock { $0 += 1 } } }
    }
    watcher.start()
    for i in 0 ..< 20 {
      try Harness.write(h.path("p/content/neu.md"), "\(i)\n")
      _ = try await h.store.create(project: p, kind: "manual", label: "\(i)")
    }
    watching.withLock { $0 = false }
    #expect(seen.withLock { $0 } == 0)
    let staged = await ProcessRunner.run(h.environment.command("git", ["--git-dir", h.path("p/.quartz-gui/snapshots.git"), "ls-files", "--", "content/neu.md"]))
    #expect(staged.stdout == "content/neu.md\n", "the index was put back: \(staged.output)")
  }

  /// A copy a crash left behind goes after an hour, a younger one stays.
  @Test func staleIndexCopiesAreRemoved() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    _ = try await h.store.create(project: p, kind: "manual", label: "eins")
    let store = h.path("p/.quartz-gui/snapshots.git")
    for (name, age) in [("qh-index-alt", 2 * 3600.0), ("qh-index-jung", 600.0)] {
      try Posix.write("\(store)/\(name)", Data("x".utf8))
      try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: "\(store)/\(name)")
    }
    _ = await h.store.list(project: p)
    #expect(FileManager.default.fileExists(atPath: "\(store)/qh-index-alt"), "a read takes no index")
    _ = try await h.store.diff(project: p, id: await h.store.list(project: p)[0].id)
    #expect(!FileManager.default.fileExists(atPath: "\(store)/qh-index-alt"))
    #expect(FileManager.default.fileExists(atPath: "\(store)/qh-index-jung"))
  }

  /// The objects of a deleted snapshot go once they are ten minutes old, not before: an object
  /// written just now may belong to a snapshot the other app has not given a ref yet. Aged before
  /// the first gc: from then on git keeps the age per object inside its cruft pack (`.mtimes`), and
  /// the file's own date says nothing.
  @Test func pruningWaitsTenMinutes() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    let store = h.path("p/.quartz-gui/snapshots.git")
    let exists = { (object: String) async in
      await ProcessRunner.run(h.environment.command("git", ["--git-dir", store, "cat-file", "-e", object])).success
    }
    /// A snapshot holding one file no other holds, and the blob of that file.
    func unique(_ label: String) async throws -> (SnapshotStore.Snapshot, String) {
      try Harness.write(h.path("p/einmalig.md"), "nur in \(label) \(UUID())\n")
      let snapshot = try await h.store.create(project: p, kind: "manual", label: label)!
      let blob = JS.trim(try await h.git(["--git-dir", store, "rev-parse", "\(snapshot.commit):einmalig.md"], in: h.work))
      try FileManager.default.removeItem(atPath: h.path("p/einmalig.md"))
      return (snapshot, blob)
    }

    let (old, oldBlob) = try await unique("alt")
    let kept = try await h.store.create(project: p, kind: "manual", label: "bleibt")!
    let objects = "\(store)/objects"
    for file in try FileManager.default.subpathsOfDirectory(atPath: objects) {
      try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: "\(objects)/\(file)")
    }
    try await h.store.delete(project: p, id: old.id)
    #expect(!(await exists(oldBlob)), "an hour old: gone")
    #expect(await exists(kept.commit))

    let (fresh, freshBlob) = try await unique("frisch")
    _ = try await h.store.create(project: p, kind: "manual", label: "bleibt auch")
    try await h.store.delete(project: p, id: fresh.id)
    #expect(await exists(freshBlob), "younger than ten minutes: kept")
    #expect(await h.store.list(project: p).map(\.label) == ["bleibt auch", "bleibt"])
  }

  /// argv has a ceiling (5000 paths of ~55 characters spawned, 10000 failed in QuartzControl's
  /// measurement); the golden's 2150 paths stay far below it, so the size is asked here.
  @Test func namedPathsGoInBatchesOfAThousand() {
    #expect(SnapshotStore.batches(Array(repeating: "x", count: 2500)).map(\.count) == [1000, 1000, 500])
    #expect(SnapshotStore.batches([]).isEmpty)
  }

  /// What the writers are handed: a snapshot of that kind and label, answered by its id; nil when
  /// nothing changed.
  @Test func takeIsCreateAnsweringTheId() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    let id = try await h.store.take(p, "pluginChange", "github:a/b")
    let newest = await h.store.list(project: p).first
    #expect(id != nil && newest?.id == id && newest?.kind == "pluginChange" && newest?.label == "github:a/b")
    #expect(try await h.store.take(p, "pluginChange", "noch einmal") == nil, "nothing changed")
  }

  /// A commit or ref git could not write stops the writer instead of handing it an id that names
  /// nothing (review 2026-11-11, nebenbei 2): first the ref folder read-only, then the object store.
  @Test func aSnapshotGitCouldNotStoreIsAFailure() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    _ = try await h.store.create(project: p, kind: "manual", label: "eins")
    let store = "\(p)/.quartz-gui/\(SnapshotStore.storeDirectory)"
    let before = await h.store.list(project: p).count

    let refs = "\(store)/\(SnapshotStore.refPrefix)"
    #expect(chmod(refs, 0o555) == 0)
    await #expect(throws: SnapshotStore.Failure.self) { _ = try await h.store.create(project: p, kind: "manual", label: "ohne Ref") }
    #expect(chmod(refs, 0o755) == 0)

    // The same tree, so only commit-tree has something to write.
    let objectsDir = "\(store)/objects"
    let objects = [objectsDir] + (Posix.entries(objectsDir) ?? []).filter { $0.kind == .directory }.map { "\(objectsDir)/\($0.name)" }
    for dir in objects { chmod(dir, 0o555) }
    defer { for dir in objects { chmod(dir, 0o755) } }
    await #expect(throws: SnapshotStore.Failure.self) { _ = try await h.store.create(project: p, kind: "manual", label: "ohne Objekt") }
    #expect(await h.store.list(project: p).count == before)
  }

  /// A git call of the store that hangs ends at the deadline, so it does not hold the project's
  /// lock for good, and the next snapshot works again (review 2026-11-11, nebenbei 5). The hang
  /// is a clean filter that sleeps.
  @Test func aHungGitCallEndsAtTheDeadline() async throws {
    let h = try Harness()
    let p = try await Self.project(h)
    h.store = SnapshotStore(environment: h.environment, npm: { _ in PluginCommands.Result(success: true, output: "") }, repoint: { _ in },
                            gitDeadline: .seconds(1))
    _ = try await h.store.create(project: p, kind: "manual", label: "vorher")
    try Posix.write(h.path("gitconfig"), Data("[filter \"hang\"]\n\tclean = sleep 30\n".utf8))
    try Harness.write(h.path("p/.gitattributes"), "*.md filter=hang\n")
    try Harness.write(h.path("p/content/Über.md"), "neu\n")
    let started = ContinuousClock.now
    await #expect(throws: SnapshotStore.Failure.self) { _ = try await h.store.create(project: p, kind: "manual", label: "hängt") }
    #expect(ContinuousClock.now - started < .seconds(15))

    try Posix.write(h.path("gitconfig"), Data())
    let after = try await h.store.create(project: p, kind: "manual", label: "danach")
    let newest = await h.store.list(project: p).first
    #expect(after != nil && newest?.label == "danach")
  }

  // MARK: - Content switched off since the snapshot (review 2026-11-11, H1)

  /// The review's case: a snapshot with the notes, the switch off, a note changed, "restore
  /// everything". The notes stay as they are now, the comparison does not call them removed, and
  /// the output says why; outside content/ the restore still happens.
  @Test func aContentFolderSwitchedOffIsNotRestored() async throws {
    let h = try Harness()
    h.box.now.withLock { $0 = Date() }
    let p = try await Self.project(h)
    let note = h.path("p/content/Über.md")
    let s1 = try await h.store.create(project: p, kind: "manual", label: "mit Inhalt")!
    _ = try await h.store.saveSettings(project: p, includeContent: false)
    try Harness.write(note, "v2, neuer Text\n")
    try Harness.write(h.path("p/quartz.config.yaml"), "configuration:\n  pageTitle: Zwei\n")

    let changes = try await h.store.diff(project: p, id: s1.id)
    #expect(changes.map(\.path) == ["quartz.config.yaml"], "\(changes)")

    let all = try await h.store.restore(project: p, id: s1.id)
    #expect(all.success, "\(all.output)")
    #expect(all.output.contains(L10n.t("main.snapshotContentUntouched")), "\(all.output)")
    #expect(try String(contentsOfFile: note, encoding: .utf8) == "v2, neuer Text\n")
    #expect(try String(contentsOfFile: h.path("p/quartz.config.yaml"), encoding: .utf8) == "configuration:\n  pageTitle: Eins\n")

    // A note named on its own is not restored either, and nothing else happens.
    let one = try await h.store.restore(project: p, id: s1.id, paths: ["content/Über.md"])
    #expect(one.success && one.output == L10n.t("main.snapshotContentUntouched"), "\(one.output)")
    #expect(try String(contentsOfFile: note, encoding: .utf8) == "v2, neuer Text\n")

    // The counter-check: with the switch on again, the same restore does bring the old note back,
    // and the snapshot before it holds the new one.
    _ = try await h.store.saveSettings(project: p, includeContent: true)
    #expect(try await h.store.diff(project: p, id: s1.id).map(\.path) == ["content/Über.md"])
    let back = try await h.store.restore(project: p, id: s1.id)
    #expect(back.success && !back.output.contains(L10n.t("main.snapshotContentUntouched")), "\(back.output)")
    #expect(try String(contentsOfFile: note, encoding: .utf8) == "Über\n")
    let safety = await h.store.list(project: p).first { $0.kind == "restore" }!
    let held = await ProcessRunner.run(h.environment.command("git", ["--git-dir", h.path("p/.quartz-gui/snapshots.git"), "show", "\(safety.commit):content/Über.md"]))
    #expect(held.stdout == "v2, neuer Text\n", "\(held.output)")
  }
}
