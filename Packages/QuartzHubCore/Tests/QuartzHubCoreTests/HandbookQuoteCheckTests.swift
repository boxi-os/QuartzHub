import Foundation
import Testing
@testable import QuartzHubCore

/// `qh-check handbook`: quotes, paths and near misses against a small catalog, in a vault on disk.
@Suite struct HandbookQuoteCheckTests {
  static let catalog = StringCatalog(sourceLanguage: "de", entries: [
    "a": ["de": .text("Ein eigener Wert hier wirkt sich auf {{count}} weitere Variablen aus."),
          "en": .text("Your own value here affects {{count}} other variables.")],
    "b": ["de": .text("Nie veröffentlichen (ein Pfad pro Zeile)"), "en": .text("Never publish (one path per line)")],
    "c": ["de": .text("{{status}} in {{seconds}}s"), "en": .text("{{status}} in {{seconds}}s")],
    "d": ["de": .text("{{name}}"), "en": .text("{{name}}")],
    "e": ["de": .text("Auf „{{branch}}“ stellen"), "en": .text("Point at “{{branch}}”")],
    "f": ["de": .text("In den Vorrat legen"), "en": .text("Put in the tray")],
    "g": ["de": .text("Projekt"), "en": .text("Project")],
    "h": ["de": .text("Snapshot anlegen"), "en": .text("Take snapshot")],
    "i": ["de": .plural([.one: "Port {{ports}} ist belegt.", .other: "Ports {{ports}} sind belegt."]),
          "en": .plural([.one: "Port {{ports}} is in use.", .other: "Ports {{ports}} are in use."])],
    "j": ["de": .text("Die Vorschau zeigt die Website über den Dev-Server, und der läuft gerade nicht."),
          "en": .text("The preview shows the site through the dev server, which is not running.")],
  ])

  final class Vault {
    let path = TestFolder.make("qh-handbook")
    init(_ files: [String: String]) throws {
      for (name, text) in files {
        let file = "\(path)/\(name)"
        try FileManager.default.createDirectory(atPath: NodePath.dirname(file), withIntermediateDirectories: true)
        try Posix.write(file, Data(text.utf8))
      }
    }
    deinit { try? FileManager.default.removeItem(atPath: path) }
  }

  static func run(_ files: [String: String]) throws -> HandbookQuoteCheck.Report {
    let vault = try Vault(files)
    return try HandbookQuoteCheck.run(catalog: catalog, vault: vault.path)
  }

  /// Whole texts, a shortened label, a filled-in placeholder, a gap, a sentence from the middle,
  /// a plural form: all say what the app says. (A text put together in code, such as the build's
  /// result line, is not one text of the catalog; the vault's exception list names those.)
  @Test func quotesTheAppSaysPass() throws {
    let report = try Self.run(["seite.md": """
      ---
      title: „steht im Frontmatter“
      ---
      Die Zeile „Ein eigener Wert hier wirkt sich auf … weitere Variablen aus“ und **Nie veröffentlichen**.
      Danach **Auf „gh-pages“ stellen**, dazu „Port 8080 ist belegt“.
      Steht „die Website über den Dev-Server, und der läuft gerade nicht“, dann **Projekt ▸ Snapshot anlegen**.
      ```
      „im Code“
      ```
      Ein `„Inline-Code“` und [[ziel|„Verweis“]] zählen nicht.
      """])
    #expect(report.findings == [], "\(report.findings)")
    #expect(report.quotes == 3 && report.paths == 1, "\(report)")
  }

  /// The two misquotes the first run found: a word the app does not use, in the page's language.
  /// And a German quote on an English page is not compared with the German catalog.
  @Test func aMisquoteIsAFinding() throws {
    let report = try Self.run([
      "en/page.md": "The line “Your own value here affects … further variables” shows it.\n",
      "seite.md": "Hier „Your own value here affects … other variables“ auf Englisch.\n",
    ])
    #expect(report.findings.map(\.file) == ["en/page.md", "seite.md"], "\(report.findings)")
    #expect(report.findings.allSatisfy { $0.kind == .quote })
  }

  /// A text that is only a placeholder ("{{name}}") must not let every quote pass; this was the
  /// first version's mistake (six findings instead of seventy).
  @Test func aPlaceholderAloneMatchesNothing() throws {
    let report = try Self.run(["seite.md": "Das sagt „Programme“, und **Ablage ▸ Snapshot anlegen**.\n"])
    #expect(report.findings.map(\.kind) == [.path, .quote], "\(report.findings)")
  }

  /// Bold close to a text of the app is a near miss; bold far from any is emphasis.
  @Test func boldNearMissesAndEmphasis() throws {
    let report = try Self.run(["seite.md": "**In den Vorrat liegen** schaltet aus. **Erst die Bühne speichern.**\n"])
    #expect(report.findings.map(\.kind) == [.nearMiss], "\(report.findings)")
    #expect(report.findings.first?.resembles == "in den vorrat legen")
  }

  /// An exception covers its text, in its language only; one that covers nothing is reported.
  @Test func exceptionsCoverAndGoStale() throws {
    let report = try Self.run([
      "seite.md": "Im Ordner „Programme“ und unter **Ablage ▸ Snapshot anlegen**.\n",
      "en/page.md": "The “Programme” folder.\n",
      "private/zitat-ausnahmen.txt": """
        # Kommentar
        de Programme # Finder
        de Ablage # macOS
        de Gibt es nicht mehr # veraltet
        """,
      "private/notiz.md": "„Wird nicht geprüft“\n",
    ])
    #expect(report.findings.map { "\($0.kind.rawValue) \($0.file):\($0.line)" }
      == ["quote en/page.md:1", "staleException private/zitat-ausnahmen.txt:4"], "\(report.findings)")
  }
}
