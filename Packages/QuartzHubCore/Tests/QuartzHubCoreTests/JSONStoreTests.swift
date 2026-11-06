import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct JSONStoreTests {
  let dir: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qh-store-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  func names() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()) ?? []
  }

  @Test func missingIsNotUnreadable() {
    #expect(JSONStore.read(dir.appendingPathComponent("projects.json")) == .missing)
    #expect(JSONStore.read(dir.appendingPathComponent("projects.json"), orEmpty: .array) == .array([]))
    #expect(names().isEmpty)
  }

  @Test func writeLeavesNoTempFileAndNoFinalNewline() throws {
    let url = dir.appendingPathComponent("settings.json")
    try JSONStore.write(.object(JSONObject([("language", .string("de")), ("n", .number(2))])), to: url)
    #expect(names() == ["settings.json"])
    #expect(try String(contentsOf: url, encoding: .utf8) == "{\n  \"language\": \"de\",\n  \"n\": 2\n}")
  }

  // The incident from jsonStore.ts: a damaged file must survive, not be replaced by the default.
  @Test(arguments: ["{\"a\":", "null", "42", "\"text\"", ""])
  func unreadableIsMovedAside(_ content: String) throws {
    let url = dir.appendingPathComponent("connections.json")
    try Data(content.utf8).write(to: url)
    guard case .unreadable(let aside?) = JSONStore.read(url) else {
      Issue.record("expected unreadable")
      return
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(try String(contentsOf: aside, encoding: .utf8) == content)
    #expect(aside.lastPathComponent.hasPrefix("connections.json.corrupt-"))
    #expect(JSONStore.quarantinedFiles().contains { $0.quarantinedAs == aside })
  }

  @Test func wrongShapeIsMovedAside() throws {
    let url = dir.appendingPathComponent("projects.json")
    try Data("{\"a\":1}".utf8).write(to: url)
    #expect(JSONStore.read(url, orEmpty: .array) == .array([]))
    #expect(names().count == 1 && names()[0].hasPrefix("projects.json.corrupt-"))
  }

  @Test func quarantineStampIsToISOStringWithDashes() {
    let date = Date(timeIntervalSince1970: 1_793_968_496.789)  // 2026-11-06T12:34:56.789Z
    #expect(JSONStore.quarantineStamp(date) == "2026-11-06T12-34-56-789Z")
  }

  /// What Node 24 prints for `new Date(ms).toISOString()` with these milliseconds.
  @Test(arguments: [
    (1_793_000_000_123.0, "2026-10-26T07:33:20.123Z"),
    (1_793_000_000_999.0, "2026-10-26T07:33:20.999Z"),
    (1_793_000_000_000.4, "2026-10-26T07:33:20.000Z"),
    (500.0, "1970-01-01T00:00:00.500Z"),
    (-1.0, "1969-12-31T23:59:59.999Z")
  ])
  func isoStringIsToISOString(milliseconds: Double, node: String) {
    #expect(JS.isoString(Date(timeIntervalSince1970: milliseconds / 1000)) == node)
  }

  @Test func unchangedValueRoundTripsByteForByte() throws {
    let url = dir.appendingPathComponent("project-prefs.json")
    let text = "{\n  \"z\": [\n    1,\n    {}\n  ],\n  \"10\": \"x\"\n}"
    try Data(text.utf8).write(to: url)
    guard case .ok(let value) = JSONStore.read(url) else { Issue.record("not ok"); return }
    try JSONStore.write(value, to: url)
    // JavaScript moves the index key "10" first; QuartzControl's own write would do the same.
    #expect(try String(contentsOf: url, encoding: .utf8) == "{\n  \"10\": \"x\",\n  \"z\": [\n    1,\n    {}\n  ]\n}")
  }
}
