import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own projectPaths.ts: `scripts/paths-golden.mjs` laid out each tree in
/// `Fixtures/paths/<case>/tree.json`, ran the operation and recorded what config, lockfile and the
/// links under `.quartz/plugins` held afterwards. Here the same tree goes through ProjectPaths.
@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt"))
struct ProjectPathsTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/paths")
  static var cases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  /// Siblings named as in the golden (a relative link there climbs to "Original"), in a folder
  /// with umlauts, so a path that came back decomposed no longer masks.
  var a: String { "\(scratch.path)/Original" }
  var b: String { "\(scratch.path)/Kopie" }

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 5, "scripts/paths-golden.mjs")
  }

  @Test(arguments: cases)
  func sameAsQuartzControl(_ name: String) async throws {
    let dir = Self.fixtures.appendingPathComponent(name)
    let tree = try JSJSON.parse(Data(contentsOf: dir.appendingPathComponent("tree.json")))
    let expected = try JSJSON.parse(Data(contentsOf: dir.appendingPathComponent("expected.json")))
    try Self.layOut(tree, at: a)
    try Posix.mkdirs(b)
    try TreeCopy.copy(from: a, to: b, verbatimSymlinks: true)

    if tree["run"] == .string("repointProjectPaths") {
      try await ProjectPaths.repointProjectPaths(from: a, to: b, runtime: HelperRuntime.runtime)
    } else {
      try await ProjectPaths.repointAuthoredFrames(project: b, runtime: HelperRuntime.runtime)
    }
    // By bytes: Swift's == takes "Ü" and "U\u{308}" for one string.
    let got = Self.record(b, a: a, b: b)
    #expect(Array(JSJSON.compact(got).utf8) == Array(JSJSON.compact(expected).utf8), "\(name)\n\(JSJSON.compact(got))")
  }

  static func layOut(_ tree: JSONValue, at root: String) throws {
    let fill = { (text: String) in text.replacingOccurrences(of: "@A@", with: root, options: .literal) }
    try Posix.mkdirs(root)
    for dir in tree["dirs"]?.arrayValue ?? [] {
      try Posix.mkdirs("\(root)/\(dir.stringValue!)")
    }
    for (path, text) in tree["files"]?.objectValue.map({ object in object.keys.map { ($0, object[$0]!) } }) ?? [] {
      let file = "\(root)/\(path)"
      try Posix.mkdirs(NodePath.dirname(file))
      try Posix.write(file, Data(fill(text.stringValue!).utf8))
    }
    for (path, target) in tree["links"]?.objectValue.map({ object in object.keys.map { ($0, object[$0]!) } }) ?? [] {
      let link = "\(root)/\(path)"
      try Posix.mkdirs(NodePath.dirname(link))
      try Posix.symlink(fill(target.stringValue!), link)
    }
  }

  static func record(_ root: String, a: String, b: String) -> JSONValue {
    let mask = { (text: String) in text.replacingOccurrences(of: b, with: "@B@", options: .literal).replacingOccurrences(of: a, with: "@A@", options: .literal) }
    func read(_ path: String) -> JSONValue {
      guard let data = try? Posix.read("\(root)/\(path)") else { return .null }
      return .string(mask(String(decoding: data, as: UTF8.self)))
    }
    var links = JSONObject()
    let dir = "\(root)/.quartz/plugins"
    for entry in Posix.entries(dir) ?? [] where entry.kind == .link {
      if let target = try? Posix.readlink("\(dir)/\(entry.name)") { links[entry.name] = .string(mask(target)) }
    }
    return .object(JSONObject([("config", read("quartz.config.yaml")), ("lock", read("quartz.lock.json")),
                               ("links", .object(links))]))
  }

  /// Inside is by bytes, as Node's `relative`: the original's path in the other Unicode form is
  /// another folder to QuartzControl, and stays.
  @Test func theOtherUnicodeFormIsNotInside() async throws {
    let decomposed = a.decomposedStringWithCanonicalMapping
    #expect(Array(decomposed.utf8) != Array(a.utf8))
    try Self.layOut(.object(JSONObject([("files", .object(JSONObject([
      ("quartz.config.yaml", .string("plugins:\n  - source: \(decomposed)/p\n    enabled: true\n  - source: \(decomposed)\n    enabled: true\n"))])))])), at: a)
    try Posix.mkdirs(b)
    try TreeCopy.copy(from: a, to: b, verbatimSymlinks: true)
    try await ProjectPaths.repointProjectPaths(from: a, to: b, runtime: HelperRuntime.runtime)
    let text = String(decoding: try Posix.read("\(b)/quartz.config.yaml"), as: UTF8.self)
    #expect(Array(text.utf8).firstRange(of: Array("source: \(decomposed)/p\n".utf8)) != nil, "\(text)")
    #expect(Array(text.utf8).firstRange(of: Array("source: \(decomposed)\n".utf8)) != nil, "\(text)")
  }

  @Test func anUnreadableConfigStopsBeforeTheLockfile() async throws {
    // As in QuartzControl: readConfig's failure ends the run, the other two places stay as they were.
    try Self.layOut(.object(JSONObject([
      ("files", .object(JSONObject([("quartz.config.yaml", .string("- a\n")),
                                    ("quartz.lock.json", .string("{\"plugins\":{\"p\":{\"source\":\"@A@/p\"}}}"))])))
    ])), at: a)
    try Posix.mkdirs(b)
    try TreeCopy.copy(from: a, to: b, verbatimSymlinks: true)
    await #expect(throws: ConfigFile.Failure.notAMapping) {
      try await ProjectPaths.repointProjectPaths(from: a, to: b, runtime: HelperRuntime.runtime)
    }
    #expect(String(decoding: try Posix.read("\(b)/quartz.lock.json"), as: UTF8.self).contains(a))
  }
}
