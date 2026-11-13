import Testing
@testable import QuartzHubCore

/// Review 2026-11-13, H2: saving a frame took `plugins:` from disk whole and dropped the stage's
/// unsaved edits.
struct PluginListMergeTests {
  static func entry(_ name: String, source: String? = nil, position: String = "left", priority: Double = 0) -> PluginEntry {
    PluginEntry(object: JSONObject([
      ("name", .string(name)), ("source", .string(source ?? "github:x/\(name)")), ("enabled", .bool(true)),
      ("layout", .object(JSONObject([("position", .string(position)), ("priority", .number(priority))]))),
    ]))
  }

  static func positions(_ entries: [PluginEntry]) -> [String] {
    entries.map { "\($0.name):\($0.object["layout"]?["position"]?.stringValue ?? "")" }
  }

  /// The review's case: a component moved on the stage, then a frame saved (the CLI appends its
  /// entry). Before, the result was the disk's list: the move was gone.
  @Test func aStageEditSurvivesAFrameSaved() {
    let base = [Self.entry("explorer"), Self.entry("search")]
    let local = [Self.entry("explorer", position: "right"), Self.entry("search")]
    let disk = base + [Self.entry("frame-1", source: "./.quartz/plugins/frame-1")]
    let merged = PluginListMerge.merge(base: base, local: local, disk: disk)
    #expect(Self.positions(merged) == ["explorer:right", "search:left", "frame-1:left"])
    // The old rule, for the record: the move is lost.
    #expect(Self.positions(disk) != Self.positions(merged))
  }

  /// The page's order stays; a new entry comes after the one before it on disk.
  @Test func aReorderStaysAndANewEntryFindsItsPlace() {
    let base = [Self.entry("a"), Self.entry("b"), Self.entry("c")]
    let local = [Self.entry("c"), Self.entry("a"), Self.entry("b")]
    let disk = [Self.entry("a"), Self.entry("new"), Self.entry("b"), Self.entry("c")]
    #expect(PluginListMerge.merge(base: base, local: local, disk: disk).map(\.name) == ["c", "a", "new", "b"])
    let first = [Self.entry("new"), Self.entry("a"), Self.entry("b"), Self.entry("c")]
    #expect(PluginListMerge.merge(base: base, local: local, disk: first).map(\.name) == ["new", "c", "a", "b"])
  }

  /// What the CLI removed goes, even when the page had edited it; an entry the page did not touch
  /// takes the disk's version.
  @Test func removedGoesAndUntouchedTakesTheDisk() {
    let base = [Self.entry("a"), Self.entry("frame-1", source: "./f"), Self.entry("b")]
    let local = [Self.entry("a", position: "right"), Self.entry("frame-1", source: "./f", position: "right"), Self.entry("b")]
    let disk = [Self.entry("a"), Self.entry("b", priority: 5)]
    let merged = PluginListMerge.merge(base: base, local: local, disk: disk)
    #expect(Self.positions(merged) == ["a:right", "b:left"])
    #expect(merged.last?.object["layout"]?["priority"] == .number(5))
  }

  /// Without edits of the page the result is the disk's list, and with them nothing else changes:
  /// the counter-check that the merge does not invent differences.
  @Test func withoutEditsItIsTheDisk() {
    let base = [Self.entry("a"), Self.entry("a"), Self.entry("b")]
    let disk = [Self.entry("a"), Self.entry("a"), Self.entry("b"), Self.entry("f", source: "./f")]
    #expect(PluginListMerge.merge(base: base, local: base, disk: disk) == disk)
    #expect(PluginListMerge.merge(base: base, local: base, disk: base) == base)
  }

  /// Two entries of one plugin are told apart by their place among their namesakes.
  @Test func namesakesKeepTheirOwnEdits() {
    let base = [Self.entry("a"), Self.entry("a")]
    let local = [Self.entry("a"), Self.entry("a", position: "right")]
    let disk = base + [Self.entry("f", source: "./f")]
    #expect(Self.positions(PluginListMerge.merge(base: base, local: local, disk: disk)) == ["a:left", "a:right", "f:left"])
  }
}
