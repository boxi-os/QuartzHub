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
  var w: URL { scratch.url.appendingPathComponent("w") }
  var log: URL { scratch.url.appendingPathComponent("calls.log") }
  init() throws { scratch = try HostPathTests.Scratch() }

  /// git and npm as the golden script's runCommand answers them: `remote remove` fails (no origin),
  /// npm says what the case says. Each notes "command args cwd".
  func environment(npm: JSONValue) throws -> ToolEnvironment {
    let ok = npm["success"] == .bool(true)
    let output = npm["output"]?.stringValue ?? ""
    try scratch.script("bin/git", "echo \"git $* $(pwd)\" >> '\(log.path)'\necho 'error: No such remote' >&2\nexit 2")
    try scratch.script("bin/npm", "echo \"npm $* $(pwd)\" >> '\(log.path)'\nprintf '%s' '\(output)'\nexit \(ok ? 0 : 1)")
    let hostPath = HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"], source: .inherited, added: [])
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
    let fill = { (text: String) in text.replacingOccurrences(of: "@W@", with: w.path) }

    try Self.layOut(spec["source"]!, at: w.appendingPathComponent("Original"), fill)
    try Self.layOut(spec["vault"]!, at: w.appendingPathComponent("Vault"), fill)
    let target = URL(fileURLWithPath: fill(spec["targetPath"]!.stringValue!))
    if let tree = spec["target"], tree != .null { try Self.layOut(tree, at: target, fill) }

    let content: ProjectDuplicator.Content = switch spec["content"]?["contentStrategy"]?.stringValue {
    case "copy": .copy(from: fill(spec["content"]!["contentSource"]!.stringValue!))
    case "symlink": .symlink(to: fill(spec["content"]!["contentSource"]!.stringValue!))
    default: .blank
    }
    let result = await ProjectDuplicator.duplicate(
      .init(source: w.appendingPathComponent("Original"), target: target, content: content),
      environment: try environment(npm: spec["npm"]!))

    #expect(result.success == (expected["success"] == .bool(true)), "\(result.output)")
    #expect(mask(result.output) == Self.localized(expected["output"]!.stringValue!), "\(name)")
    let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map { mask(String($0)) }
    #expect(.array(calls.map(JSONValue.string)) == expected["calls"], "\(name)")
    if case .array(let entries)? = expected["tree"] {
      let tree = record(target)
      #expect(tree.count == entries.count, "\(name): \(tree.count) entries, QuartzControl \(entries.count)")
      for (mine, theirs) in zip(tree, entries.map(Self.localizedEntry)) where mine != theirs {
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
    let real = ContentFolder.realPath(w.path) ?? w.path
    return text.replacingOccurrences(of: real, with: "@W@").replacingOccurrences(of: w.path, with: "@W@")
  }

  static func layOut(_ tree: JSONValue, at root: URL, _ fill: (String) -> String) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    var modes: [(URL, Int)] = []
    for path in tree.objectValue?.keys ?? [] {
      let spec = tree[path]!
      let url = root.appendingPathComponent(path)
      try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if case .string(let text) = spec {
        try Data(fill(text).utf8).write(to: url)
      } else if let link = spec["link"]?.stringValue {
        try manager.createSymbolicLink(atPath: url.path, withDestinationPath: fill(link))
      } else if let size = spec["fill"]?.numberValue {
        // A file of that many "x", for size limits (option-schema-golden.mjs fills it the same way).
        try Data(repeating: UInt8(ascii: "x"), count: Int(size)).write(to: url)
      } else if let mode = spec["dir"]?.numberValue {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        modes.append((url, Int(mode)))
      } else {
        try Data(fill(spec["text"]!.stringValue!).utf8).write(to: url)
        chmod(url.path, mode_t(spec["mode"]!.numberValue!))
      }
    }
    for (url, mode) in modes { chmod(url.path, mode_t(mode)) }
  }

  /// The golden script's `record`: every entry below the root, sorted, links by target, folders
  /// and files with their permissions in octal, files with their text.
  func record(_ root: URL) -> [JSONValue] {
    var entries: [JSONValue] = []
    func walk(_ dir: URL, _ relative: String) {
      for name in ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() {
        let url = dir.appendingPathComponent(name)
        let path = relative.isEmpty ? name : "\(relative)/\(name)"
        var info = stat()
        lstat(url.path, &info)
        let mode = String(info.st_mode & 0o7777, radix: 8)
        switch info.st_mode & S_IFMT {
        case S_IFLNK:
          let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
          entries.append(.object(JSONObject([("path", .string(path)), ("link", .string(mask(target)))])))
        case S_IFDIR:
          entries.append(.object(JSONObject([("path", .string(path)), ("dir", .string(mode))])))
          walk(url, path)
        default:
          let text = String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
          entries.append(.object(JSONObject([("path", .string(path)), ("mode", .string(mode)), ("text", .string(mask(text)))])))
        }
      }
    }
    walk(root, "")
    return entries
  }

  // MARK: what the golden files cannot show

  @Test func theCopyLeavesTheOriginalsRemoteBehind() async throws {
    let original = w.appendingPathComponent("Original")
    try Self.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n"))])), at: original) { $0 }
    let git = { (args: [String], dir: URL) in
      await ProcessRunner.run(Command("/usr/bin/git", ["-C", dir.path] + args,
                                      environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "GIT_CONFIG_GLOBAL": "/dev/null"]))
    }
    #expect(await git(["init", "-q"], original).success)
    #expect(await git(["remote", "add", "origin", "https://example.org/original.git"], original).success)
    var environment = try environment(npm: .object(JSONObject([("success", .bool(true)), ("output", .string(""))])))
    environment.hostPath = HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"], source: .inherited, added: [])
    try FileManager.default.removeItem(at: scratch.url.appendingPathComponent("bin/git"))
    let copy = w.appendingPathComponent("Kopie")
    let result = await ProjectDuplicator.duplicate(.init(source: original, target: copy, content: .blank), environment: environment)
    #expect(result.success, "\(result.output)")
    #expect(await git(["remote"], copy).stdout == "")
    #expect(await git(["remote"], original).stdout == "origin\n")
  }

  @Test func aSucceededInstallClearsOnlyTheFailedFlag() async throws {
    let original = w.appendingPathComponent("Original")
    let head = String(repeating: "a", count: 40)
    let note = """
      {"installPendingFor":"\(head)","reinstall":[{"name":"quartz-forms","section":"dependencies","range":"^0.6.0","extra":1},\
      {"name":"-bad","section":"dependencies","range":"1"},{"name":"x","section":"nope","range":"1"}],\
      "filesAtHead":true,"installFailed":true,"putBack":["quartz-forms","quartz-forms","gone",""],"unknown":true}
      """
    try Self.layOut(.object(JSONObject([("quartz.config.yaml", .string("plugins: []\n")),
                                        (".quartz-gui/core-update.json", .string(note))])), at: original) { $0 }
    let copy = w.appendingPathComponent("Kopie")
    let result = await ProjectDuplicator.duplicate(.init(source: original, target: copy, content: .blank),
                                                   environment: try environment(npm: .object(JSONObject([("success", .bool(true))]))))
    #expect(result.success)
    // markInstallPending's form: its five keys in its order, the passing entries as they were,
    // putBack deduplicated and filtered to what reinstall carries.
    let written = try String(contentsOf: QuartzGuiDirectory(project: copy).coreUpdate, encoding: .utf8)
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
    #expect(try String(contentsOf: QuartzGuiDirectory(project: original).coreUpdate, encoding: .utf8) == note)
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
