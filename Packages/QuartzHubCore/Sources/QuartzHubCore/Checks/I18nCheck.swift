import Foundation

/// `qh-check i18n`: the successor of QuartzControl's `check:i18n`.
///
/// It answers four questions, each with its own list, and "could not check" is a separate answer
/// (docs/conventions.md, „Kann nicht prüfen“ ist nie „alles gut“):
/// 1. Is every key the code asks for in the catalog?
/// 2. Does every key exist in both languages, with the same plural forms?
/// 3. Do both languages use the same `{{placeholders}}`?
/// 4. Which calls pass a key that is not a literal (and so cannot be checked)?
/// Unused keys are counted, not listed by default: until the pages are ported, most are unused.
public struct I18nCheck: Sendable {
  public struct Report: Sendable {
    public var missingKeys: [(key: String, location: String)] = []
    public var languageGaps: [String] = []
    public var placeholderMismatches: [String] = []
    public var dynamicCalls: [String] = []
    public var unusedKeys: [String] = []
    public var usedKeyCount = 0
    public var scannedFiles = 0

    public var hasErrors: Bool { !missingKeys.isEmpty || !languageGaps.isEmpty || !placeholderMismatches.isEmpty }
  }

  public static let languages = ["de", "en"]

  public static func run(catalog: StringCatalog, sources: [String], relativeTo root: String) throws -> Report {
    // Calls look like `L10n.t("key"` or `L10n.t(in: lang, "key"`. Local, because Regex is not
    // Sendable and a static would need an unchecked exemption.
    let literalCall = try Regex(#"L10n\.t\(\s*(?:in:\s*[^,]+,\s*)?"((?:[^"\\]|\\.)*)""#)
    let anyCall = try Regex(#"L10n\.t\("#)
    var report = Report()
    var used = Set<String>()
    for file in sources {
      let text = String(decoding: try Posix.read(file), as: UTF8.self)
      report.scannedFiles += 1
      let relative = file.replacingOccurrences(of: root + "/", with: "", options: .literal)
      for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        // Comments are not calls, and neither is the definition of L10n.t itself.
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") || line.contains("func t(") { continue }
        let calls = line.matches(of: anyCall).count
        guard calls > 0 else { continue }
        let literals = line.matches(of: literalCall)
        for match in literals {
          let key = String(match.output[1].substring ?? "")
          used.insert(key)
          if catalog.entries[key] == nil {
            report.missingKeys.append((key, "\(relative):\(index + 1)"))
          }
        }
        if literals.count < calls {
          report.dynamicCalls.append("\(relative):\(index + 1)")
        }
      }
    }
    report.usedKeyCount = used.count

    for key in catalog.entries.keys.sorted() {
      let byLanguage = catalog.entries[key] ?? [:]
      for language in languages where byLanguage[language] == nil {
        report.languageGaps.append("\(key): fehlt in \(language)")
      }
      guard let de = byLanguage["de"], let en = byLanguage["en"] else { continue }
      switch (de, en) {
      case (.text, .text): break
      case (.plural(let a), .plural(let b)):
        if Set(a.keys) != Set(b.keys) {
          report.languageGaps.append("\(key): Pluralformen de \(a.keys.map(\.rawValue).sorted()) ≠ en \(b.keys.map(\.rawValue).sorted())")
        }
      default:
        report.languageGaps.append("\(key): in einer Sprache Plural, in der anderen nicht")
      }
      if placeholders(de) != placeholders(en) {
        report.placeholderMismatches.append("\(key): de \(placeholders(de).sorted()) ≠ en \(placeholders(en).sorted())")
      }
      if !used.contains(key) { report.unusedKeys.append(key) }
    }
    return report
  }

  static func placeholders(_ entry: StringCatalog.Entry) -> Set<String> {
    switch entry {
    case .text(let value):
      return Set(StringCatalog.placeholders(in: value))
    case .plural(let forms):
      // A form may leave {{count}} out ("Ein Paket fehlt"); the others must agree.
      return Set(forms.values.flatMap { StringCatalog.placeholders(in: $0) }).subtracting(["count"])
    }
  }

  /// Swift files under the given directories, skipping build output.
  public static func swiftSources(in directories: [String]) -> [String] {
    var result: [String] = []
    for directory in directories {
      guard let walker = FileManager.default.enumerator(atPath: directory) else { continue }
      for case let relative as String in walker {
        let parts = relative.split(separator: "/")
        if parts.contains(".build") || parts.contains("DerivedData") {
          walker.skipDescendants()
          continue
        }
        if NodePath.extname(relative) == ".swift" { result.append("\(directory)/\(relative)") }
      }
    }
    return result.sorted()
  }
}
