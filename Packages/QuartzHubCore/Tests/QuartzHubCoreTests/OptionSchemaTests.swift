import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's shared/pluginOptionSchema.ts: `scripts/option-schema-golden.mjs` ran
/// each case of `Fixtures/option-schema/normalizer.json` through it and wrote the canonical answer
/// (scripts/lib/option-schema-canon.mjs); here the same inputs go through OptionSchema and are
/// compared byte for byte.
@Suite struct OptionSchemaTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/option-schema/normalizer.json")
  static var cases: [JSONValue] { (try? JSJSON.parse(Data(contentsOf: fixture)).arrayValue) ?? [] }
  static var names: [String] { cases.compactMap { $0["name"]?.stringValue } }

  static func normalize(_ spec: JSONValue) -> NormalizedOptionSchema {
    if spec["op"] == .string("flat") { return OptionSchema.normalize(optionSchema: spec["schema"]!) }
    let source = spec["source"]?.stringValue.flatMap(NormalizedOptionSchema.Source.init) ?? .configSchema
    return OptionSchema.normalize(jsonSchema: spec["schema"]!, source: source)
  }

  static func run(_ spec: JSONValue) -> JSONValue {
    let canonical = { (schema: NormalizedOptionSchema?) in schema?.canonicalJSON ?? .null }
    switch spec["op"]!.stringValue! {
    case "json", "flat":
      return canonical(normalize(spec))
    case "defaults":
      return canonical(OptionSchema.applyDefaults(normalize(spec), spec["defaults"]))
    case "fromDefaults":
      return canonical(OptionSchema.fromDefaults(spec["defaults"]))
    case "present":
      var base = normalize(spec)
      if let defaults = spec["defaults"] { base = OptionSchema.applyDefaults(base, defaults) }
      return canonical(OptionSchema.withPresentKeys(base, spec["values"]))
    case "conditions":
      let fields = normalize(spec).fields
      return .array(spec["checks"]!.arrayValue!.map { check in
        .bool(OptionSchema.evaluate(check["when"]?.objectValue, values: check["values"], fields: fields))
      })
    default:
      let sets = spec["checks"]!.arrayValue!.map { check -> JSONValue in
        .object(OptionSchema.setting(check["value"], at: check["path"]!.arrayValue!.compactMap(\.stringValue), in: check["obj"]!.objectValue!))
      }
      let gets = spec["gets"]!.arrayValue!.map { check -> JSONValue in
        let found = OptionSchema.value(at: check["path"]!.arrayValue!.compactMap(\.stringValue), in: check["obj"])
        return .object(found.map { JSONObject([("value", $0)]) } ?? JSONObject([("absent", .bool(true))]))
      }
      let prunes = spec["prunes"]!.arrayValue!.map { JSONValue.object(OptionSchema.pruningEmptyObjects($0.objectValue!)) }
      return .object(JSONObject([("sets", .array(sets)), ("gets", .array(gets)), ("prunes", .array(prunes))]))
    }
  }

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 26, "scripts/option-schema-golden.mjs")
  }

  @Test(arguments: names)
  func sameAsQuartzControl(_ name: String) throws {
    let spec = try #require(Self.cases.first { $0["name"] == .string(name) })
    // Where QuartzControl threw, there is nothing to compare: see whereQuartzControlThrew.
    guard let expected = spec["expected"] else { return }
    #expect(JSJSON.stringify(Self.run(spec)) == JSJSON.stringify(expected))
  }

  /// The two cases QuartzControl answered with an exception (URIError, RangeError), and what this
  /// port says instead: a note at the field, the rest of the schema intact.
  @Test func whereQuartzControlThrew() throws {
    let thrown = Self.cases.filter { $0["throws"] != nil }.compactMap { $0["name"]?.stringValue }
    #expect(thrown.sorted() == ["json-ref-alias-loop", "json-ref-bad-escape"])

    let escape = Self.normalize(try #require(Self.cases.first { $0["name"] == .string("json-ref-bad-escape") }))
    #expect(escape.fields.map(\.key) == ["a"])
    #expect(escape.notes == [OptionSchemaNote(path: ["a"], reason: "unresolvable $ref #/$defs/%E0%A4%A")])

    let loop = Self.normalize(try #require(Self.cases.first { $0["name"] == .string("json-ref-alias-loop") }))
    #expect(loop.fields.map(\.key) == ["a"])
    #expect(loop.notes == [OptionSchemaNote(path: ["a"], reason: "refers to itself (#/$defs/a)")])
  }

  @Test func ownKeysOnly() {
    // QuartzControl's `key in values` found `constructor` on every object and widened the field
    // with a function; here a key is a key of the object.
    let schema = OptionSchema.normalize(jsonSchema: .object(JSONObject([("properties", .object(JSONObject([
      ("constructor", .object(JSONObject([("type", .string("string"))])))
    ])))])), source: .configSchema)
    let merged = OptionSchema.withPresentKeys(schema, .object(JSONObject([("a", .number(1))])))
    #expect(merged.fields.map(\.key) == ["constructor", "a"])
    #expect(merged.fields[0].node == .string)
  }
}
