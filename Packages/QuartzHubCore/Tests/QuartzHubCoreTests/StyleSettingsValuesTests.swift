import Foundation
import Testing
@testable import QuartzHubCore

/// StyleSettingsValues against QuartzControl's styleSettings.ts and the grouping of
/// StyleSettingsForm.tsx (`scripts/style-settings-golden.mjs`): keys, reading and groups. Writing a
/// colour follows core 3 since 2026-11-23, and QuartzControl's values still read.
struct StyleSettingsValuesTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/style-settings")

  static func load() throws -> (cases: JSONValue, schemas: [String: [StyleSettingsValues.Field]]) {
    let cases = try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("cases.json")))
    let lobster = try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("ultra-lobster.json")))
    return (cases, ["lobster": StyleSettingsValues.fields(lobster), "tokyo": StyleSettingsValues.fields(cases["schemas"]?["tokyo"]),
                    "made": StyleSettingsValues.fields(cases["schemas"]?["made"])])
  }

  static func mode(_ value: JSONValue?) -> StyleSettingsValues.Mode? { value?.stringValue.flatMap(StyleSettingsValues.Mode.init) }

  @Test func keysEntriesAndReading() throws {
    let (cases, schemas) = try Self.load()
    #expect(schemas["lobster"]?.count ?? 0 > 150)
    let valueSets = (cases["valueSets"]?.arrayValue ?? []).map { $0.objectValue ?? JSONObject() }
    var mismatches: [String] = []
    let fieldCases = cases["fieldCases"]?.arrayValue ?? []
    #expect(fieldCases.count > 200)
    for entry in fieldCases {
      guard let field = entry["field"]?.objectValue.map(StyleSettingsValues.Field.init) else { continue }
      let label = "\(entry["schema"]?.stringValue ?? "")/\(field.id)"
      if StyleSettingsValues.optionKey(field) != entry["key"]?.stringValue { mismatches.append("\(label) key") }
      if StyleSettingsValues.keysOf(field) != (entry["keys"]?.arrayValue ?? []).compactMap(\.stringValue) { mismatches.append("\(label) keys") }
      // Writing is core 3's rule, not QuartzControl's (`colorEntries`): the colour under the field's
      // key, one per mode; QuartzControl's keys must be among those a reset clears, and what is
      // written reads back as the same colour.
      for e in entry["entries"]?.arrayValue ?? [] {
        let hex = e["hex"]?.stringValue ?? "", mode = Self.mode(e["mode"])
        let got = StyleSettingsValues.colorEntries(field, hex: hex, mode: mode)
        let modes: [StyleSettingsValues.Mode?] = field.kind == "variable-themed-color" ? (mode.map { [$0] } ?? [.light, .dark]) : [nil]
        let value = hex == "abcdef" ? "#abcdef" : hex
        if got.map({ "\($0.key)=\($0.value)" }) != modes.map({ "\(StyleSettingsValues.optionKey(field, mode: $0))=\(value)" }) {
          mismatches.append("\(label) entries \(hex) \(String(describing: mode)): \(got)")
        }
        let old = (e["entries"]?.objectValue?.keys ?? [])
        if !old.allSatisfy(StyleSettingsValues.keysOf(field).contains) { mismatches.append("\(label) reset misses \(old)") }
        let written = JSONObject(got.map { ($0.key, JSONValue.string($0.value)) })
        // What the picker hands over: six digits with `#` (`#ABC` reads back as `#AABBCC`, `nope` not at all).
        for m in modes where JSText.test(value, #"\A#[0-9a-fA-F]{6}\z"#) {
          let back = StyleSettingsValues.readColor(field, values: written, mode: m)
          if back.hex?.lowercased() != value.lowercased() || !back.isSet { mismatches.append("\(label) reads \(hex) back as \(back)") }
        }
      }
      for r in entry["read"]?.arrayValue ?? [] {
        let set = Int(r["set"]?.numberValue ?? 0)
        let got = StyleSettingsValues.readColor(field, values: valueSets[set], mode: Self.mode(r["mode"]))
        if got.hex != r["hex"]?.stringValue || got.isSet != (r["isSet"] == .bool(true)) {
          mismatches.append("\(label) read set \(set) \(String(describing: r["mode"])): \(String(describing: r["hex"])) \(String(describing: r["isSet"])), here \(String(describing: got))")
        }
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(20).joined(separator: "\n"))")
  }

  static func json(_ group: StyleSettingsValues.Group) -> JSONValue {
    // The root group has no `heading` key at all in QuartzControl's buildGroups.
    var object = JSONObject()
    if let heading = group.heading { object["heading"] = .object(heading.object) }
    object["fields"] = .array(group.fields.map { .object($0.object) })
    object["children"] = .array(group.children.map(json))
    return .object(object)
  }

  @Test func groups() throws {
    let (cases, schemas) = try Self.load()
    let groupCases = cases["groupCases"]?.arrayValue ?? []
    #expect(groupCases.count == 15)
    for entry in groupCases {
      let fields = schemas[entry["schema"]?.stringValue ?? ""] ?? []
      let shipped = Set((entry["shipped"]?.arrayValue ?? []).compactMap(\.stringValue))
      let query = entry["query"]?.stringValue ?? ""
      let got = StyleSettingsValues.groups(StyleSettingsValues.filter(StyleSettingsValues.usable(fields, shippedClassKeys: shipped), query: query)).map(Self.json)
      #expect(JSONValue.array(got) == entry["groups"], "\(entry["schema"]?.stringValue ?? "") \(query)")
    }
  }

  /// SwiftUI keeps a row's focus and a group's open state only while the group's id stays.
  @Test func aGroupKeepsItsIdAcrossRendersAndSearches() throws {
    let (_, schemas) = try Self.load()
    let fields = StyleSettingsValues.usable(schemas["lobster"] ?? [], shippedClassKeys: [])
    func ids(_ groups: [StyleSettingsValues.Group]) -> [String: String] {
      var out: [String: String] = [:]
      func walk(_ group: StyleSettingsValues.Group) {
        out[group.id] = group.heading?.title ?? "(root)"
        group.children.forEach(walk)
      }
      groups.forEach(walk)
      return out
    }
    let first = ids(StyleSettingsValues.groups(fields))
    #expect(first.count > 10)
    #expect(ids(StyleSettingsValues.groups(fields)) == first)
    let searched = ids(StyleSettingsValues.groups(StyleSettingsValues.filter(fields, query: "gap")))
    #expect(!searched.isEmpty)
    for (id, title) in searched { #expect(first[id] == title, "\(id)") }
  }

  @Test func hslToHex() throws {
    let (cases, _) = try Self.load()
    for entry in cases["hsl"]?.arrayValue ?? [] {
      let h = entry["h"]?.numberValue ?? 0, s = entry["s"]?.numberValue ?? 0, l = entry["l"]?.numberValue ?? 0
      #expect(StyleSettingsValues.hslToHex(h, s, l) == entry["hex"]?.stringValue, "\(h) \(s) \(l)")
    }
  }

  /// A colour picked for an hsl-split field written for core 2 replaces its three parts; the other
  /// mode's stay until that one is picked.
  @Test func aPickedColourClearsQuartzControlsParts() {
    let field = StyleSettingsValues.Field(JSONObject([("id", .string("acc")), ("blockId", .string("t")), ("kind", .string("variable-themed-color")),
                                                      ("format", .string("hsl-split"))]))
    let before = JSONObject([("t@@acc-h@@light", .string("0")), ("t@@acc-s@@light", .string("100%")), ("t@@acc-l@@light", .string("50%")),
                             ("t@@acc-h@@dark", .string("0")), ("t@@acc-s@@dark", .string("100%")), ("t@@acc-l@@dark", .string("50%"))])
    #expect(StyleSettingsValues.readColor(field, values: before, mode: .light) == ("#ff0000", true))
    let after = StyleSettingsValues.apply(StyleSettingsValues.colorPatch(field, hex: "#00ff00", mode: .light), to: before)
    #expect(Set(after.keys) == ["t@@acc@@light", "t@@acc-h@@dark", "t@@acc-s@@dark", "t@@acc-l@@dark"])
    #expect(after["t@@acc@@light"] == .string("#00ff00"))
    #expect(StyleSettingsValues.readColor(field, values: after, mode: .light) == ("#00ff00", true))
    #expect(StyleSettingsValues.readColor(field, values: after, mode: .dark) == ("#ff0000", true))
    let plain = StyleSettingsValues.Field(JSONObject([("id", .string("c")), ("blockId", .string("t")), ("kind", .string("variable-color")),
                                                      ("format", .string("rgb-values"))]))
    #expect(StyleSettingsValues.colorPatch(plain, hex: "#102030").map(\.key) == ["t@@c"])
  }

  @Test func aPatchSetsAndRemoves() {
    let start = JSONObject([("a@@x", .string("1")), ("a@@y", .bool(true))])
    let next = StyleSettingsValues.apply([("a@@x", nil), ("a@@y", .string("")), ("a@@z", .number(3))], to: start)
    #expect(next == JSONObject([("a@@z", .number(3))]))
  }
}
