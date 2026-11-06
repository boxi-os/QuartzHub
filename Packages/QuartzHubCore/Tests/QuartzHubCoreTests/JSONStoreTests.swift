import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct JSONStoreTests {
  let dir = TestFolder.make("qh-store")

  /// As `readdir` gives them; compared by bytes.
  func names() -> [[UInt8]] { (Posix.entries(dir) ?? []).map { Array($0.name.utf8) } }

  func clean() { try? FileManager.default.removeItem(atPath: dir) }

  @Test func missingIsNotUnreadable() {
    defer { clean() }
    #expect(JSONStore.read("\(dir)/projects.json") == .missing)
    #expect(JSONStore.read("\(dir)/projects.json", orEmpty: .array) == .array([]))
    #expect(names().isEmpty)
  }

  @Test func writeLeavesNoTempFileAndNoFinalNewline() throws {
    defer { clean() }
    let path = "\(dir)/Einstellungen f\u{FC}r \u{DC}ber.json"
    try JSONStore.write(.object(JSONObject([("language", .string("de")), ("n", .number(2))])), to: path)
    #expect(names() == [Array("Einstellungen f\u{FC}r \u{DC}ber.json".utf8)], "the name as given, composed")
    #expect(String(decoding: try Posix.read(path), as: UTF8.self) == "{\n  \"language\": \"de\",\n  \"n\": 2\n}")
  }

  // The incident from jsonStore.ts: a damaged file must survive, not be replaced by the default.
  @Test(arguments: ["{\"a\":", "null", "42", "\"text\"", ""])
  func unreadableIsMovedAside(_ content: String) throws {
    defer { clean() }
    let path = "\(dir)/Verbindungen-\u{C4}.json"
    try Posix.write(path, Data(content.utf8))
    guard case .unreadable(let aside?) = JSONStore.read(path) else {
      Issue.record("expected unreadable")
      return
    }
    #expect(!Posix.exists(path))
    #expect(String(decoding: try Posix.read(aside), as: UTF8.self) == content)
    #expect(names().count == 1 && names()[0].starts(with: Array("Verbindungen-\u{C4}.json.corrupt-".utf8)))
    #expect(Array(aside.utf8).starts(with: Array("\(dir)/Verbindungen-\u{C4}.json.corrupt-".utf8)))
    #expect(JSONStore.quarantinedFiles().contains { $0.quarantinedAs.map { Array($0.utf8) } == Array(aside.utf8) })
  }

  /// Only "no such file" is missing; a read that fails otherwise (a folder in its place) is moved aside.
  @Test func aFolderInPlaceIsUnreadable() throws {
    defer { clean() }
    try Posix.mkdirs("\(dir)/settings.json")
    guard case .unreadable(let aside?) = JSONStore.read("\(dir)/settings.json") else {
      Issue.record("expected unreadable")
      return
    }
    #expect(Posix.kind(aside) == .directory && !Posix.exists("\(dir)/settings.json"))
  }

  @Test func wrongShapeIsMovedAside() throws {
    defer { clean() }
    let path = "\(dir)/projects.json"
    try Posix.write(path, Data("{\"a\":1}".utf8))
    #expect(JSONStore.read(path, orEmpty: .array) == .array([]))
    #expect(names().count == 1 && names()[0].starts(with: Array("projects.json.corrupt-".utf8)))
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
    defer { clean() }
    let path = "\(dir)/project-prefs.json"
    let text = "{\n  \"z\": [\n    1,\n    {}\n  ],\n  \"10\": \"x\"\n}"
    try Posix.write(path, Data(text.utf8))
    guard case .ok(let value) = JSONStore.read(path) else { Issue.record("not ok"); return }
    try JSONStore.write(value, to: path)
    // JavaScript moves the index key "10" first; QuartzControl's own write would do the same.
    #expect(String(decoding: try Posix.read(path), as: UTF8.self) == "{\n  \"10\": \"x\",\n  \"z\": [\n    1,\n    {}\n  ]\n}")
  }
}
