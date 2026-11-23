import Foundation
import Testing
@testable import QuartzHubCore

/// `StyleSettingsSchema.schema(of:)`: the blocks core 3's `parseStyleSettings` read (here written
/// the way it answers, YAML documents as JSON) turned into the form's schema, with a 2.x preset as
/// the defaults. What core reads from a real theme was measured through `theme-fetch`
/// (decisions/phase-5-gleichstand.md, „Style Settings aus core“).
struct StyleSettingsCoreTests {
  static func block(_ id: JSONValue, _ settings: [JSONValue]) -> JSONValue {
    .object(JSONObject([("id", id), ("name", .string("Name")), ("settings", .array(settings))]))
  }

  static func setting(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(JSONObject(pairs)) }

  static func theme(_ blocks: [JSONValue], preset: JSONObject? = nil) -> ThemeFetch.Theme {
    ThemeFetch.Theme(name: "Catppuccin", source: "https://example.invalid", preset: preset, css: "", settingsBlocks: blocks)
  }

  static let blocks: [JSONValue] = [
    block(.string("ctp"), [
      setting([("id", .string("head")), ("type", .string("heading")), ("title", .string("Farben")), ("level", .number(1))]),
      setting([("id", .string("ctp-dark")), ("type", .string("class-select")), ("title", .string("Dunkel")),
               ("options", .array([.string("ctp-mocha"), .string("ctp-frappe")])), ("default", .string("ctp-mocha"))]),
      setting([("id", .string("ctp-pill")), ("type", .string("class-toggle")), ("title", .string("Pillen"))]),
      setting([("id", .string("ctp-h1")), ("type", .string("variable-text")), ("default", .string("var(--ctp-red)"))]),
      setting([("id", .string("accent")), ("type", .string("variable-themed-color")), ("format", .string("hsl-split")),
               ("default-light", .string("#ffffff")), ("default-dark", .string("#000000"))]),
      setting([("id", .string("width")), ("type", .string("variable-number")), ("default", .number(40))])
    ]),
    // A number as id is a key in core's object; an empty or missing list is no block there.
    block(.number(7), [setting([("id", .string("x")), ("type", .string("class-toggle"))])]),
    block(.string("leer"), []),
    .object(JSONObject([("id", .string("ohne"))])),
    block(.string(""), [setting([("id", .string("y")), ("type", .string("class-toggle"))])])
  ]

  static func field(_ schema: JSONValue, _ id: String) -> JSONObject? {
    schema["fields"]?.arrayValue?.first { $0["id"]?.stringValue == id }?.objectValue
  }

  @Test func blocksAsCoreCountsThem() {
    let schema = StyleSettingsSchema.schema(of: Self.theme(Self.blocks), author: "Catppuccin-Team")
    #expect(schema["ids"] == .array([.string("ctp"), .string("7")]))
    #expect(schema["themeName"] == .string("Catppuccin"))
    #expect(schema["author"] == .string("Catppuccin-Team"))
    #expect(schema["fields"]?.arrayValue?.count == 7)
    #expect(Self.field(schema, "x")?["blockId"] == .string("7"))
    // The same field shape as before: title falls back to the id, kinds as the form knows them.
    #expect(Self.field(schema, "ctp-h1")?["title"] == .string("ctp-h1"))
    #expect(Self.field(schema, "accent")?["defaultLight"] == .string("#ffffff"))
    #expect(StyleSettingsValues.fields(schema).map(\.kind) == ["heading", "class-select", "class-toggle", "variable-text",
                                                                "variable-themed-color", "variable-number", "class-toggle"])
  }

  @Test func noBlockNoSchema() {
    #expect(StyleSettingsSchema.schema(of: Self.theme([])) == .null)
    #expect(StyleSettingsSchema.schema(of: Self.theme(Array(Self.blocks.suffix(3)))) == .null)
    #expect(StyleSettingsSchema.schema(of: Self.theme(Self.blocks))["author"] == nil)
  }

  /// `catppuccin.frappe`: what the variation stood for is what a field shows until the entry sets its own.
  @Test func thePresetIsTheDefault() {
    let preset = JSONObject([("ctp@@ctp-dark", .string("ctp-frappe")), ("ctp@@ctp-pill", .bool(true)), ("ctp@@ctp-h1", .string("var(--ctp-pink)")),
                             ("ctp@@accent@@light", .string("#eeeeee")), ("ctp@@accent", .string("#111111")), ("ctp@@width", .number(52)),
                             ("anders@@ctp-dark", .string("nein"))])
    let schema = StyleSettingsSchema.schema(of: Self.theme(Self.blocks, preset: preset))
    #expect(Self.field(schema, "ctp-dark")?["default"] == .string("ctp-frappe"))
    #expect(Self.field(schema, "ctp-pill")?["default"] == .bool(true))
    #expect(Self.field(schema, "ctp-h1")?["default"] == .string("var(--ctp-pink)"))
    #expect(Self.field(schema, "width")?["default"] == .string("52"))
    // core: a themed colour without a mode is the dark one.
    #expect(Self.field(schema, "accent")?["defaultLight"] == .string("#eeeeee"))
    #expect(Self.field(schema, "accent")?["defaultDark"] == .string("#111111"))
    #expect(Self.field(schema, "x")?["default"] == nil)
  }

  /// Every class core 3 can switch counts as shipped: no switch of the form is left out.
  @Test func everyClassIsShipped() {
    let schema = StyleSettingsSchema.schema(of: Self.theme(Self.blocks))
    let info = StyleSettingsSchema.info(of: schema)
    #expect(info.styleSettingsId == ["ctp", "7"])
    #expect(info.classSettingKeys == ["ctp-mocha", "ctp-frappe", "ctp-pill", "x"])
    let usable = StyleSettingsValues.usable(StyleSettingsValues.fields(schema), shippedClassKeys: Set(info.classSettingKeys))
    #expect(usable.count == StyleSettingsValues.fields(schema).count)
    #expect(StyleSettingsSchema.info(of: .null) == ThemeStyleSettingsInfo(styleSettingsId: [], classSettingKeys: []))
  }
}
