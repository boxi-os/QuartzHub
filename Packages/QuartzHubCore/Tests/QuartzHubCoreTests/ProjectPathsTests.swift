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
  init() throws { scratch = try HostPathTests.Scratch() }

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 5, "scripts/paths-golden.mjs")
  }

  @Test(arguments: cases)
  func sameAsQuartzControl(_ name: String) async throws {
    let dir = Self.fixtures.appendingPathComponent(name)
    let tree = try JSJSON.parse(Data(contentsOf: dir.appendingPathComponent("tree.json")))
    let expected = try JSJSON.parse(Data(contentsOf: dir.appendingPathComponent("expected.json")))
    let a = scratch.url.appendingPathComponent("Original")
    let b = scratch.url.appendingPathComponent("Kopie")
    try Self.layOut(tree, at: a)
    try FileManager.default.copyItem(at: a, to: b)

    if tree["run"] == .string("repointProjectPaths") {
      try await ProjectPaths.repointProjectPaths(from: a, to: b, runtime: HelperRuntime.runtime)
    } else {
      try await ProjectPaths.repointAuthoredFrames(project: b, runtime: HelperRuntime.runtime)
    }
    #expect(Self.record(b, a: a.path, b: b.path) == expected, "\(name)")
  }

  static func layOut(_ tree: JSONValue, at root: URL) throws {
    let fill = { (text: String) in text.replacingOccurrences(of: "@A@", with: root.path, options: .literal) }
    let manager = FileManager.default
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    for dir in tree["dirs"]?.arrayValue ?? [] {
      try manager.createDirectory(at: root.appendingPathComponent(dir.stringValue!), withIntermediateDirectories: true)
    }
    for (path, text) in tree["files"]?.objectValue.map({ object in object.keys.map { ($0, object[$0]!) } }) ?? [] {
      let url = root.appendingPathComponent(path)
      try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(fill(text.stringValue!).utf8).write(to: url)
    }
    for (path, target) in tree["links"]?.objectValue.map({ object in object.keys.map { ($0, object[$0]!) } }) ?? [] {
      let url = root.appendingPathComponent(path)
      try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try manager.createSymbolicLink(atPath: url.path, withDestinationPath: fill(target.stringValue!))
    }
  }

  static func record(_ root: URL, a: String, b: String) -> JSONValue {
    let mask = { (text: String) in text.replacingOccurrences(of: b, with: "@B@", options: .literal).replacingOccurrences(of: a, with: "@A@", options: .literal) }
    func read(_ path: String) -> JSONValue {
      guard let data = try? Data(contentsOf: root.appendingPathComponent(path)) else { return .null }
      return .string(mask(String(decoding: data, as: UTF8.self)))
    }
    var links = JSONObject()
    let dir = root.appendingPathComponent(".quartz/plugins")
    for name in ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() {
      if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: dir.appendingPathComponent(name).path) {
        links[name] = .string(mask(target))
      }
    }
    return .object(JSONObject([("config", read("quartz.config.yaml")), ("lock", read("quartz.lock.json")),
                               ("links", .object(links))]))
  }

  @Test func anUnreadableConfigStopsBeforeTheLockfile() async throws {
    // As in QuartzControl: readConfig's failure ends the run, the other two places stay as they were.
    let a = scratch.url.appendingPathComponent("Original")
    let b = scratch.url.appendingPathComponent("Kopie")
    try Self.layOut(.object(JSONObject([
      ("files", .object(JSONObject([("quartz.config.yaml", .string("- a\n")),
                                    ("quartz.lock.json", .string("{\"plugins\":{\"p\":{\"source\":\"@A@/p\"}}}"))])))
    ])), at: a)
    try FileManager.default.copyItem(at: a, to: b)
    await #expect(throws: ConfigFile.Failure.notAMapping) {
      try await ProjectPaths.repointProjectPaths(from: a, to: b, runtime: HelperRuntime.runtime)
    }
    #expect(try String(contentsOf: b.appendingPathComponent("quartz.lock.json"), encoding: .utf8).contains(a.path))
  }
}
