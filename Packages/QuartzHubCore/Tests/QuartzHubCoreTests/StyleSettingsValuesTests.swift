import Foundation
import Testing
@testable import QuartzHubCore

/// StyleSettingsValues against QuartzControl's styleSettings.ts and the grouping of
/// StyleSettingsForm.tsx (`scripts/style-settings-golden.mjs`).
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
      for e in entry["entries"]?.arrayValue ?? [] {
        let got = StyleSettingsValues.colorEntries(field, hex: e["hex"]?.stringValue ?? "", mode: Self.mode(e["mode"]))
        let want = e["entries"]?.objectValue
        let wantPairs = (want?.keys ?? []).map { ($0, want?[$0]?.stringValue ?? "") }
        if got.map({ "\($0.key)=\($0.value)" }) != wantPairs.map({ "\($0.0)=\($0.1)" }) {
          mismatches.append("\(label) entries \(e["hex"]?.stringValue ?? "") \(String(describing: e["mode"])): \(wantPairs), here \(got)")
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

  @Test func hslToHex() throws {
    let (cases, _) = try Self.load()
    for entry in cases["hsl"]?.arrayValue ?? [] {
      let h = entry["h"]?.numberValue ?? 0, s = entry["s"]?.numberValue ?? 0, l = entry["l"]?.numberValue ?? 0
      #expect(StyleSettingsValues.hslToHex(h, s, l) == entry["hex"]?.stringValue, "\(h) \(s) \(l)")
    }
  }

  @Test func aPatchSetsAndRemoves() {
    let start = JSONObject([("a@@x", .string("1")), ("a@@y", .bool(true))])
    let next = StyleSettingsValues.apply([("a@@x", nil), ("a@@y", .string("")), ("a@@z", .number(3))], to: start)
    #expect(next == JSONObject([("a@@z", .number(3))]))
  }
}
