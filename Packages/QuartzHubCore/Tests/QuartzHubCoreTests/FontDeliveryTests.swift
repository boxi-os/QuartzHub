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
      check("selfHosted on", FontDelivery.withSelfHostedFonts(config, true).jsonValue, entry["selfHostedOn"])
      check("selfHosted off", FontDelivery.withSelfHostedFonts(config, false).jsonValue, entry["selfHostedOff"])
      check("fetchesGoogleFonts", .bool(FontDelivery.fetchesGoogleFonts(config)), entry["fetchesGoogleFonts"])
      check("persist", FontDelivery.persist(config).jsonValue, entry["persist"])
      check("present", .array(blocks.map { FontDelivery.present(config, scss: $0).jsonValue }), entry["present"])
      for (key, list) in cases["faceSets"]?.objectValue.map({ object in object.keys.map { ($0, object[$0]) } }) ?? [] {
        let got = [nil, true, false].map { Self.state(FontDelivery.buildState(config, faces: Self.faces(list), built: $0)) }
        check("buildState \(key)", .array(got), entry["buildState"]?[key])
      }
      let fixes = FontDelivery.cssFixes.map { JSONValue.object(JSONObject([("id", .string($0.id)), ("applies", .bool($0.appliesTo(config)))])) }
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
