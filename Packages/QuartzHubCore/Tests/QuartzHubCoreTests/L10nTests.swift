import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct L10nTests {
  static let sample = """
  {
    "sourceLanguage" : "de",
    "strings" : {
      "a.plain" : { "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "„{{name}}“ entfernen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Remove “{{name}}”" } } } },
      "a.count" : { "localizations" : {
        "de" : { "variations" : { "plural" : {
          "one" : { "stringUnit" : { "state" : "translated", "value" : "Ein Paket fehlt" } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "{{count}} Pakete fehlen" } } } } },
        "en" : { "variations" : { "plural" : {
          "one" : { "stringUnit" : { "state" : "translated", "value" : "One package is missing" } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "{{count}} packages are missing" } } } } } } },
      "a.zero" : { "localizations" : {
        "de" : { "variations" : { "plural" : {
          "zero" : { "stringUnit" : { "state" : "translated", "value" : "keiner" } },
          "one" : { "stringUnit" : { "state" : "translated", "value" : "einer" } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "{{count}}" } } } } } } },
      "a.onlyDe" : { "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "nur deutsch" } } } }
    },
    "version" : "1.0"
  }
  """

  let catalog = try! StringCatalog.parse(Data(sample.utf8))

  @Test func namedPlaceholders() {
    #expect(L10n.text(catalog, language: "de", "a.plain", ["name": "x"]) == "„x“ entfernen")
    #expect(L10n.text(catalog, language: "en-GB", "a.plain", ["name": "x"]) == "Remove “x”")
  }

  // The trap from the spike: i18next takes the base key as the singular. The importer turns that
  // into `one`; here the catalog side is checked for 0, 1 and many.
  @Test func plurals() {
    #expect(L10n.text(catalog, language: "de", "a.count", count: 1) == "Ein Paket fehlt")
    #expect(L10n.text(catalog, language: "de", "a.count", count: 3) == "3 Pakete fehlen")
    #expect(L10n.text(catalog, language: "en", "a.count", count: 0) == "0 packages are missing")
    #expect(L10n.text(catalog, language: "de", "a.zero", count: 0) == "keiner")
    #expect(L10n.text(catalog, language: "de", "a.zero", count: 1) == "einer")
  }

  @Test func fallbacks() {
    // Missing in English → source language; unknown key → the key itself.
    #expect(L10n.text(catalog, language: "en", "a.onlyDe") == "nur deutsch")
    #expect(L10n.text(catalog, language: "de", "nope") == "nope")
    // Unknown placeholders stay, as in mainT.
    #expect(L10n.text(catalog, language: "de", "a.plain") == "„{{name}}“ entfernen")
  }

  @Test func languageResolution() {
    #expect(L10n.resolve(.system, preferred: ["de-DE"]) == "de")
    #expect(L10n.resolve(.system, preferred: ["fr-FR"]) == "en")
    #expect(L10n.resolve(.en, preferred: ["de-DE"]) == "en")
  }

  @Test func bundledCatalogLoads() {
    // The real catalog, from the package bundle: a known key in both languages.
    #expect(L10n.t(in: "de", "projectLayout.tabs.overview") == "Übersicht")
    #expect(L10n.t(in: "en", "projectLayout.tabs.overview") == "Overview")
    #expect(L10n.t(in: "de", "main.menuFile") == "Datei")
  }

  @Test func checkFindsMissingAndDynamic() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("X.swift")
    try """
    let a = L10n.t("a.plain", ["name": n])
    let b = L10n.t(in: lang, "a.missing")
    let c = L10n.t(key)
    // L10n.t("a.inComment") is documentation, not a call
    """.write(to: file, atomically: true, encoding: .utf8)
    let report = try I18nCheck.run(catalog: catalog, sources: [file], relativeTo: dir)
    #expect(report.missingKeys.map(\.key) == ["a.missing"])
    #expect(report.dynamicCalls == ["X.swift:3"])
    #expect(report.languageGaps.contains("a.onlyDe: fehlt in en"))
    #expect(report.languageGaps.contains("a.zero: fehlt in en"))
  }
}
