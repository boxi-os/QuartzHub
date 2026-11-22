import Foundation
import Testing
@testable import QuartzHubCore

/// FontDelivery against QuartzControl's fontDelivery.ts, fontSpec.ts, previewFonts.ts and
/// cssFixes.ts (`scripts/font-delivery-golden.mjs`).
struct FontDeliveryTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/font-delivery")

  static func load() throws -> JSONValue {
    try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("cases.json")))
  }

  static func faces(_ value: JSONValue?) -> [SiteFonts.Face] {
    (value?.arrayValue ?? []).map {
      SiteFonts.Face(family: $0["family"]?.stringValue ?? "", weight: $0["weight"]?.stringValue ?? "", style: $0["style"]?.stringValue ?? "",
                     origin: $0["origin"]?.stringValue ?? "", source: $0["source"]?.stringValue ?? "")
    }
  }

  static func state(_ state: FontDelivery.BuildState?) -> JSONValue {
    let families: (String, [String]) -> JSONValue = { kind, list in
      .object(JSONObject([("kind", .string(kind)), ("families", .array(list.map { .string($0) }))]))
    }
    switch state {
    case nil: return .null
    case .notBuilt?: return .object(JSONObject([("kind", .string("notBuilt"))]))
    case .missing(let list)?: return families("missing", list)
    case .notFetched(let list)?: return families("notFetched", list)
    case .noRule(let list)?: return families("noRule", list)
    }
  }

  @Test func everyConfig() throws {
    let cases = try Self.load()
    let configs = cases["configs"]?.arrayValue ?? []
    #expect(configs.count > 250)
    let blocks = (cases["blocks"]?.arrayValue ?? []).compactMap(\.stringValue)
    var mismatches: [String] = []
    for entry in configs {
      let name = entry["name"]?.stringValue ?? ""
      guard let config = entry["config"].flatMap(QuartzConfig.init(jsonValue:)) else { mismatches.append("\(name): config not read"); continue }
      func check(_ what: String, _ got: JSONValue, _ expected: JSONValue?) {
        if got != expected { mismatches.append("\(name) \(what): \(expected.map(JSJSON.stringify) ?? "nil"), here \(JSJSON.stringify(got))") }
      }
      let loaders = FontDelivery.loaders(config).map { JSONValue.object(JSONObject([("via", .string($0.via)), ("mode", .string($0.mode))])) }
      check("loaders", .array(loaders), entry["loaders"])
      check("callsGoogle", .bool(FontDelivery.callsGoogle(config)), entry["callsGoogle"])
      check("themeFontsEnabled", .bool(FontDelivery.themeFontsEnabled(config)), entry["themeFontsEnabled"])
      check("withThemeFonts on", FontDelivery.withThemeFonts(config, true).jsonValue, entry["withThemeFontsOn"])
      check("withThemeFonts off", FontDelivery.withThemeFonts(config, false).jsonValue, entry["withThemeFontsOff"])
      // QuartzHub's one addition to QuartzControl's answer: `configuration.fonts.fontOrigin: local`
      // with "local" (Quartz 5.2), and nothing else; taken out here, checked on its own.
      func ownAddition(_ got: QuartzConfig, local: Bool) -> JSONValue {
        let added = got.configuration["fonts"]
        if config.configuration["fonts"] == nil {
          let expected: JSONValue? = local ? .object(JSONObject([("fontOrigin", .string("local"))])) : nil
          if added != expected { mismatches.append("\(name): configuration.fonts \(added.map(JSJSON.stringify) ?? "nil")") }
        }
        var stripped = got
        stripped.configuration["fonts"] = config.configuration["fonts"]
        return stripped.jsonValue
      }
      check("selfHosted on", ownAddition(FontDelivery.withSelfHostedFonts(config, true), local: true), entry["selfHostedOn"])
      check("selfHosted off", ownAddition(FontDelivery.withSelfHostedFonts(config, false), local: false), entry["selfHostedOff"])
      check("fetchesGoogleFonts", .bool(FontDelivery.fetchesGoogleFonts(config)), entry["fetchesGoogleFonts"])
      check("persist", ownAddition(FontDelivery.persist(config), local: FontDelivery.fetchesGoogleFonts(config)), entry["persist"])
      check("present", .array(blocks.map { FontDelivery.present(config, scss: $0).jsonValue }), entry["present"])
      for (key, list) in cases["faceSets"]?.objectValue.map({ object in object.keys.map { ($0, object[$0]) } }) ?? [] {
        let got = [nil, true, false].map { Self.state(FontDelivery.buildState(config, faces: Self.faces(list), built: $0)) }
        check("buildState \(key)", .array(got), entry["buildState"]?[key])
      }
      let fixes = FontDelivery.cssFixes.map { JSONValue.object(JSONObject([("id", .string($0.id)), ("applies", .bool($0.appliesTo(config, .quartz51)))])) }
      check("fixes", .array(fixes), entry["fixes"])
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(20).joined(separator: "\n"))")
  }

  @Test func familiesFacesAndFixes() throws {
    let cases = try Self.load()
    for entry in cases["primaryFamily"]?.arrayValue ?? [] {
      #expect(FontDelivery.primaryFamily(entry["stack"]?.stringValue) == entry["family"]?.stringValue, "\(String(describing: entry["stack"]))")
    }
    let all = Self.faces(cases["faceSets"]?["all"])
    for entry in cases["summaries"]?.arrayValue ?? [] {
      let summary = FontDelivery.summarizeFaces(all, family: entry["family"]?.stringValue ?? "")
      let got: JSONValue = summary.map {
        .object(JSONObject([("weights", .array($0.weights.map { .string($0) })), ("italic", .bool($0.italic)), ("origins", .array($0.origins.map { .string($0) }))]))
      } ?? .null
      #expect(got == entry["summary"], "\(entry["family"]?.stringValue ?? "")")
    }
    let fixes = cases["fixes"]?.arrayValue ?? []
    #expect(fixes.count == FontDelivery.cssFixes.count)
    for (fix, expected) in zip(FontDelivery.cssFixes, fixes) {
      #expect(fix.id == expected["id"]?.stringValue)
      #expect(fix.fileName == expected["fileName"]?.stringValue)
      #expect(fix.content { "[[\($0)]]" } == expected["content"]?.stringValue)
    }
    #expect(GoogleFontList.families.count == Int(cases["googleFontsCount"]?.numberValue ?? 0))
    #expect(GoogleFontList.families.first == GoogleFontList.Family(name: "Roboto", category: .sansSerif))
  }

  // MARK: Quartz 5.2's built-in fonts (measured on gui-test, 2026-11-22, decisions/phase-5-gleichstand.md)

  static func config52(theme: [(String, JSONValue)], fonts: JSONValue? = nil, plugins: [PluginEntry] = []) -> QuartzConfig {
    var config = QuartzConfig(plugins: plugins)
    config.theme = JSONObject(theme)
    if let fonts { config.configuration["fonts"] = fonts }
    return config
  }

  static func quartzFonts(_ enabled: Bool) -> PluginEntry {
    PluginEntry(object: JSONObject([("source", .string("@quartz-community/quartz-fonts")), ("enabled", .bool(enabled))]))
  }

  @Test func theBuiltInIsALoaderOn52Only() {
    // No entry, no configuration.fonts, Quartz's own fonts local: 5.2 links Google (148 pages).
    let local = Self.config52(theme: [("fontOrigin", .string("local"))])
    #expect(FontDelivery.loaders(local, .quartz52) == [FontDelivery.Loader(via: "builtin", mode: "google")])
    #expect(FontDelivery.callsGoogle(local, .quartz52))
    #expect(FontDelivery.loaders(local, .quartz51).isEmpty)
    // fontOrigin local loads nothing; selfHosted downloads at build.
    let builtinLocal = Self.config52(theme: [("fontOrigin", .string("local"))], fonts: .object(JSONObject([("fontOrigin", .string("local"))])))
    #expect(FontDelivery.loaders(builtinLocal, .quartz52).isEmpty)
    let selfHosted = Self.config52(theme: [("fontOrigin", .string("local"))], fonts: .object(JSONObject([("fontOrigin", .string("selfHosted"))])))
    #expect(FontDelivery.loaders(selfHosted, .quartz52) == [FontDelivery.Loader(via: "builtin", mode: "selfHosted")])
    // A disabled quartz-fonts entry turns it off (gui-test: no file named Google).
    let entryOff = Self.config52(theme: [("fontOrigin", .string("local"))], plugins: [Self.quartzFonts(false)])
    #expect(FontDelivery.loaders(entryOff, .quartz52).isEmpty)
    // An enabled entry is the built-in's on 5.2, the plugin's on 5.1.
    let entryOn = Self.config52(theme: [("fontOrigin", .string("local"))], plugins: [Self.quartzFonts(true)])
    #expect(FontDelivery.loaders(entryOn, .quartz52) == [FontDelivery.Loader(via: "builtin", mode: "google")])
    #expect(FontDelivery.loaders(entryOn, .quartz51) == [FontDelivery.Loader(via: "plugin", mode: "google")])
  }

  @Test func servingLocallyTurnsTheBuiltInToLocal() {
    // The page's draft spelling of "served by QuartzHub": Google with cdnCaching false.
    let draft = Self.config52(theme: [("fontOrigin", .string("googleFonts"))])
    let on = FontDelivery.withSelfHostedFonts(draft, true, .quartz52)
    #expect(on.configuration["fonts"] == .object(JSONObject([("fontOrigin", .string("local"))])))
    #expect(!FontDelivery.callsGoogle(on, .quartz52))
    #expect(FontDelivery.loaders(on, .quartz52) == [FontDelivery.Loader(via: "core", mode: "selfHosted")])
    let persisted = FontDelivery.persist(on)
    #expect(persisted.theme["fontOrigin"] == .string("local"))
    #expect(persisted.configuration["fonts"]?["fontOrigin"] == .string("local"))
    // Back: the key goes, the other options stay.
    var withOptions = on
    withOptions.configuration["fonts"] = .object(JSONObject([("fontOrigin", .string("local")), ("h1", .string("Lora"))]))
    let off = FontDelivery.withSelfHostedFonts(withOptions, false, .quartz52)
    #expect(off.configuration["fonts"] == .object(JSONObject([("h1", .string("Lora"))])))
    #expect(FontDelivery.withSelfHostedFonts(on, false, .quartz52).configuration["fonts"] == nil)
    // Someone else's selfHosted stays when QuartzHub turns its own off.
    let theirs = Self.config52(theme: [], fonts: .object(JSONObject([("fontOrigin", .string("selfHosted"))])))
    #expect(FontDelivery.withSelfHostedFonts(theirs, false, .quartz52).configuration["fonts"] == theirs.configuration["fonts"])
    // `fonts: false` keeps its meaning.
    let disabled = Self.config52(theme: [], fonts: .bool(false))
    #expect(FontDelivery.withSelfHostedFonts(disabled, true, .quartz52).configuration["fonts"]
            == .object(JSONObject([("enabled", .bool(false)), ("fontOrigin", .string("local"))])))
  }

  @Test func theFontSourcePickerSetsTheBuiltInsToo() {
    let draft = Self.config52(theme: [("fontOrigin", .string("googleFonts"))])
    let local = FontDelivery.withCoreFontOrigin(draft, "local")
    #expect(local.theme["fontOrigin"] == .string("local"))
    #expect(local.configuration["fonts"]?["fontOrigin"] == .string("local"))
    #expect(FontDelivery.loaders(local, .quartz52).isEmpty)
    let google = FontDelivery.withCoreFontOrigin(local, "googleFonts")
    #expect(google.configuration["fonts"] == nil)
  }

  @Test func theHeadingFixIsForThePluginOnly() {
    let theme = PluginEntry(object: JSONObject([("source", .string("@quartz-themes/core")), ("enabled", .bool(true))]))
    let config = QuartzConfig(plugins: [Self.quartzFonts(true), theme])
    #expect(FontDelivery.headingFontFix.appliesTo(config, .quartz51))
    #expect(!FontDelivery.headingFontFix.appliesTo(config, .quartz52), "5.2 leaves a theme's headings alone")
  }

  /// `activeThemeIdOf` of the Styles page: the first theme plugin decides, on or off.
  @Test func activeThemeId() {
    func config(_ plugins: [(String, Bool, JSONValue?)]) -> QuartzConfig {
      QuartzConfig(plugins: plugins.map { source, enabled, theme in
        var object = JSONObject([("source", .string(source)), ("enabled", .bool(enabled))])
        if let theme { object["options"] = .object(JSONObject([("theme", theme)])) }
        return PluginEntry(object: object)
      })
    }
    #expect(FontDelivery.activeThemeId(config([("@quartz-themes/minimal", true, .string("minimal"))])) == "minimal")
    #expect(FontDelivery.activeThemeId(config([("@quartz-themes/minimal", false, .string("minimal")), ("@quartz-themes/b", true, .string("b"))])) == nil)
    #expect(FontDelivery.activeThemeId(config([("@quartz-themes/minimal", true, .number(3))])) == nil)
    #expect(FontDelivery.activeThemeId(config([("@quartz-themes/minimal", true, nil)])) == nil)
    #expect(FontDelivery.activeThemeId(config([("other", true, .string("x"))])) == nil)
  }
}
