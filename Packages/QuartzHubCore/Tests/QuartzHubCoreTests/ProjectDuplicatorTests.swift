import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own duplicateService.ts: `scripts/duplicate-golden.mjs` laid out each
/// case of `Fixtures/duplicate/<case>/case.json`, duplicated it with stand-ins for git and npm that
/// note their calls, and recorded the copy entry by entry. Here the same trees go through
/// ProjectDuplicator with stand-ins that do the same.
@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt"))
struct ProjectDuplicatorTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/duplicate")
  static var cases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
  }

  let scratch: HostPathTests.Scratch
  var w: String { "\(scratch.path)/w" }
  var log: String { "\(scratch.path)/calls.log" }
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  /// git and npm as the golden script's runCommand answers them: `remote remove` fails (no origin),
  /// npm says what the case says. Each notes "command args cwd".
  func environment(npm: JSONValue) throws -> ToolEnvironment {
    let ok = npm["success"] == .bool(true)
    let output = npm["output"]?.stringValue ?? ""
    try scratch.script("bin/git", "echo \"git $* $(pwd)\" >> '\(log)'\necho 'error: No such remote' >&2\nexit 2")
    try scratch.script("bin/npm", "echo \"npm $* $(pwd)\" >> '\(log)'\nprintf '%s' '\(output)'\nexit \(ok ? 0 : 1)")
    let hostPath = HostPath(entries: ["\(scratch.path)/bin", "/usr/bin", "/bin"], source: .inherited, added: [])
    return ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"], hostPath: hostPath, nodeMode: .system,
                           runtime: HelperRuntime.runtime, git: nil, bundledGitFailure: nil)
  }

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 10, "scripts/duplicate-golden.mjs")
  }

  @Test(arguments: cases)
  func sameAsQuartzControl(_ name: String) async throws {
    let dir = Self.fixtures.appendingPathComponent(name)
    let spec = try JSJSON.parse(Data(contentsOf: dir.appendingPathComponent("case.json")))
    let expected = try JSJSON.parse(Data(contentsOf: dir.appendingPathComponent("expected.json")))
    let fill = { (text: String) in text.replacingOccurrences(of: "@W@", with: w, options: .literal) }

    try Self.layOut(spec["source"]!, at: "\(w)/Original", fill)
    try Self.layOut(spec["vault"]!, at: "\(w)/Vault", fill)
    let target = fill(spec["targetPath"]!.stringValue!)
    if let tree = spec["target"], tree != .null { try Self.layOut(tree, at: target, fill) }

    let content: ProjectDuplicator.Content = switch spec["content"]?["contentStrategy"]?.stringValue {
    case "copy": .copy(from: fill(spec["content"]!["contentSource"]!.stringValue!))
    case "symlink": .symlink(to: fill(spec["content"]!["contentSource"]!.stringValue!))
    default: .blank
    }
    let result = await ProjectDuplicator.duplicate(
      .init(source: "\(w)/Original", target: target, content: content),
      environment: try environment(npm: spec["npm"]!))

    #expect(result.success == (expected["success"] == .bool(true)), "\(result.output)")
    #expect(mask(result.output) == Self.localized(expected["output"]!.stringValue!), "\(name)")
    let calls = ((try? Posix.read(log)).map { String(decoding: $0, as: UTF8.self) } ?? "").split(separator: "\n").map { mask(String($0)) }
    #expect(.array(calls.map(JSONValue.string)) == expected["calls"], "\(name)")
    if case .array(let entries)? = expected["tree"] {
      let tree = record(target)
      #expect(tree.count == entries.count, "\(name): \(tree.count) entries, QuartzControl \(entries.count)")
      // By bytes: Swift's == takes "Ü" and "U\u{308}" for one name.
      for (mine, theirs) in zip(tree, entries.map(Self.localizedEntry)) where Array(JSJSON.compact(mine).utf8) != Array(JSJSON.compact(theirs).utf8) {
        Issue.record("\(name): \(mine) ≠ \(theirs)")
      }
    }
  }

  /// The golden script's mainT answered `{"key":…,"args":…}`; this is the sentence it stands for,
  /// line by line (a call stands on a line of its own in every output), and an argument that is
  /// itself one (the reason of a config that cannot be read) is translated first.
  static func localized(_ text: String) -> String {
    text.components(separatedBy: "\n").map { line in
      guard let call = try? JSJSON.parse(line), let key = call["key"]?.stringValue,
            let args = call["args"]?.objectValue else { return line }
      var strings: [String: String] = [:]
      for name in args.keys { strings[name] = localized(args[name]?.stringValue ?? "") }
      return L10n.t("main." + key, strings)
    }.joined(separator: "\n")
  }

  static func localizedEntry(_ entry: JSONValue) -> JSONValue {
    guard case .object(var object) = entry, let text = object["text"]?.stringValue else { return entry }
    object["text"] = .string(localized(text))
    return .object(object)
  }

  func mask(_ text: String) -> String {
    let real = ContentFolder.realPath(w) ?? w
    return text.replacingOccurrences(of: real, with: "@W@", options: .literal).replacingOccurrences(of: w, with: "@W@", options: .literal)
  }

  static func layOut(_ tree: JSONValue, at root: String, _ fill: (String) -> String) throws {
    try Posix.mkdirs(root)
    var modes: [(String, Int)] = []
    for path in tree.objectValue?.keys ?? [] {
      let spec = tree[path]!
      let file = "\(root)/\(path)"
      try Posix.mkdirs(NodePath.dirname(file))
      if case .string(let text) = spec {
        try Posix.write(file, Data(fill(text).utf8))
      } else if let link = spec["link"]?.stringValue {
        try Posix.symlink(fill(link), file)
      } else if let size = spec["fill"]?.numberValue {
        // A file of that many "x", for size limits (option-schema-golden.mjs fills it the same way).
        try Posix.write(file, Data(repeating: UInt8(ascii: "x"), count: Int(size)))
      } else if let mode = spec["dir"]?.numberValue {
        try Posix.mkdirs(file)
        modes.append((file, Int(mode)))
      } else {
        try Posix.write(file, Data(fill(spec["text"]!.stringValue!).utf8))
        chmod(file, mode_t(spec["mode"]!.numberValue!))
      }
    }
    for (path, mode) in modes { chmod(path, mode_t(mode)) }
  }

  /// The golden script's `record`: every entry below the root, sorted, links by target, folders
  /// and files with their permissions in octal, files with their text.
  func record(_ root: String) -> [JSONValue] {
    var entries: [JSONValue] = []
    func walk(_ dir: String, _ relative: String) {
      for name in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() {
        let full = "\(dir)/\(name)"
        let path = relative.isEmpty ? name : "\(relative)/\(name)"
        var info = stat()
        lstat(full, &info)
        let mode = String(info.st_mode & 0o7777, radix: 8)
        switch info.st_mode & S_IFMT {
        case S_IFLNK:
          let target = (try? Posix.readlink(full)) ?? ""
          entries.append(.object(JSONObject([("path", .string(path)), ("link", .string(mask(target)))])))
        case S_IFDIR:
          entries.append(.object(JSONObject([("path", .string(path)), ("dir", .string(mode))])))
          walk(full, path)
        default:
          let text = String(decoding: (try? Posix.read(full)) ?? Data(), as: UTF8.self)
          entries.append(.object(JSONObject([("path", .string(path)), ("mode", .string(mode)), ("text", .string(mask(text)))])))
        }
      }
    }
    walk(root, "")
    return entries
  }

  // MARK: what the golden files cannot show

  /// The copy's folder, the title of its blank start page and a link to a vault keep the bytes
  /// they were given; FileManager and `lastPathComponent` decomposed all three.
  @Test func aCopyWithUmlautsKeepsItsBytes() async throws {
    let original = "\(w)/Original"
    try Self.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n"))])), at: original) { $0 }
    try Self.layOut(.object(JSONObject([("a.md", .string("x"))])), at: "\(w)/G\u{E4}rten") { $0 }
    let environment = try environment(npm: .object(JSONObject([("success", .bool(true))])))
    let blank = "\(w)/Kopie \u{DC}ber"
    #expect(await ProjectDuplicator.duplicate(.init(source: original, target: blank, content: .blank), environment: environment).success)
    #expect((Posix.entries(w) ?? []).contains { Array($0.name.utf8) == Array("Kopie \u{DC}ber".utf8) })
    let page = String(decoding: try Posix.read("\(blank)/content/index.md"), as: UTF8.self)
    #expect(Array(page.utf8).starts(with: Array("---\ntitle: Kopie \u{DC}ber\n".utf8)), "\(page)")
    let linked = "\(w)/Verlinkt"
    #expect(await ProjectDuplicator.duplicate(.init(source: original, target: linked, content: .symlink(to: "\(w)/G\u{E4}rten")),
                                              environment: environment).success)
    #expect(Array(try Posix.readlink("\(linked)/content").utf8) == Array("\(w)/G\u{E4}rten".utf8))
  }

  @Test func theCopyLeavesTheOriginalsRemoteBehind() async throws {
    let original = "\(w)/Original"
    try Self.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n"))])), at: original) { $0 }
    let git = { (args: [String], dir: String) in
      await ProcessRunner.run(Command("/usr/bin/git", ["-C", dir] + args,
                                      environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "GIT_CONFIG_GLOBAL": "/dev/null"]))
    }
    #expect(await git(["init", "-q"], original).success)
    #expect(await git(["remote", "add", "origin", "https://example.org/original.git"], original).success)
    var environment = try environment(npm: .object(JSONObject([("success", .bool(true)), ("output", .string(""))])))
    environment.hostPath = HostPath(entries: ["\(scratch.path)/bin", "/usr/bin", "/bin"], source: .inherited, added: [])
    try Posix.unlink("\(scratch.path)/bin/git")
    let copy = "\(w)/Kopie"
    let result = await ProjectDuplicator.duplicate(.init(source: original, target: copy, content: .blank), environment: environment)
    #expect(result.success, "\(result.output)")
    #expect(await git(["remote"], copy).stdout == "")
    #expect(await git(["remote"], original).stdout == "origin\n")
  }

  @Test func aSucceededInstallClearsOnlyTheFailedFlag() async throws {
    let original = "\(w)/Original"
    let head = String(repeating: "a", count: 40)
    let note = """
      {"installPendingFor":"\(head)","reinstall":[{"name":"quartz-forms","section":"dependencies","range":"^0.6.0","extra":1},\
      {"name":"-bad","section":"dependencies","range":"1"},{"name":"x","section":"nope","range":"1"}],\
      "filesAtHead":true,"installFailed":true,"putBack":["quartz-forms","quartz-forms","gone",""],"unknown":true}
      """
    try Self.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n")),
                                        (".quartz-gui/core-update.json", .string(note))])), at: original) { $0 }
    let copy = "\(w)/Kopie"
    let result = await ProjectDuplicator.duplicate(.init(source: original, target: copy, content: .blank),
                                                   environment: try environment(npm: .object(JSONObject([("success", .bool(true))]))))
    #expect(result.success)
    // markInstallPending's form: its five keys in its order, the passing entries as they were,
    // putBack deduplicated and filtered to what reinstall carries.
    let written = String(decoding: try Posix.read(QuartzGuiDirectory(project: copy).coreUpdate), as: UTF8.self)
    #expect(written == """
      {
        "installPendingFor": "\(head)",
        "reinstall": [
          {
            "name": "quartz-forms",
            "section": "dependencies",
            "range": "^0.6.0",
            "extra": 1
          }
        ],
        "filesAtHead": true,
        "installFailed": false,
        "putBack": [
          "quartz-forms"
        ]
      }
      """)
    // The original's note is untouched, and a note without the flag is not rewritten.
    #expect(String(decoding: try Posix.read(QuartzGuiDirectory(project: original).coreUpdate), as: UTF8.self) == note)
    #expect(PendingInstall(object: JSONObject([("installPendingFor", .string(head)), ("installFailed", .bool(false))]))
      .afterInstallSucceeded() == nil)
  }

  @Test func containmentIsByTheResolvedText() {
    #expect(ProjectDuplicator.contains("/a/b", "/a/b"))
    #expect(ProjectDuplicator.contains("/a/b", "/a/b/c"))
    #expect(ProjectDuplicator.contains("/a/b/", "/a/b/c/../d"))
    #expect(!ProjectDuplicator.contains("/a/b", "/a/bc"))
    #expect(!ProjectDuplicator.contains("/a/b/c", "/a/b"))
    #expect(!ProjectDuplicator.contains("/a/b", "/a/b/..x"), "Node's startsWith('..')")
    #expect(ProjectDuplicator.contains("/", "/a"))
  }
}
