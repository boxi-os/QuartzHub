import Foundation

/// `Localizable.xcstrings`, read as the JSON it is.
///
/// Why not `String(localized:)`: the catalog keeps QuartzControl's named placeholders (`{{name}}`)
/// and the language is a setting of the app (system/de/en) that applies without a restart. Both
/// need the texts themselves, not the system's lookup. The file stays a real String Catalog, so
/// Xcode can still edit it; `qh-check i18n` and the app read the same file.
public struct StringCatalog: Sendable {
  public enum PluralForm: String, Sendable, CaseIterable { case zero, one, other }

  public enum Entry: Sendable, Equatable {
    case text(String)
    case plural([PluralForm: String])
  }

  public let sourceLanguage: String
  /// key → language → entry
  public let entries: [String: [String: Entry]]
  public let comments: [String: String]

  public init(sourceLanguage: String, entries: [String: [String: Entry]], comments: [String: String] = [:]) {
    self.sourceLanguage = sourceLanguage
    self.entries = entries
    self.comments = comments
  }

  public struct ReadError: Error, CustomStringConvertible {
    public let description: String
  }

  public static func load(from path: String) throws -> StringCatalog {
    try parse(Posix.read(path))
  }

  public static func parse(_ data: Data) throws -> StringCatalog {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = root["strings"] as? [String: Any]
    else { throw ReadError(description: "not a string catalog (no \"strings\" object)") }
    let source = root["sourceLanguage"] as? String ?? "de"
    var entries: [String: [String: Entry]] = [:]
    var comments: [String: String] = [:]
    for (key, raw) in strings {
      guard let item = raw as? [String: Any] else { continue }
      if let comment = item["comment"] as? String { comments[key] = comment }
      let localizations = item["localizations"] as? [String: Any] ?? [:]
      var byLanguage: [String: Entry] = [:]
      for (language, rawLocalization) in localizations {
        guard let localization = rawLocalization as? [String: Any] else { continue }
        if let value = Self.unitValue(localization) {
          byLanguage[language] = .text(value)
        } else if let variations = localization["variations"] as? [String: Any],
                  let plural = variations["plural"] as? [String: Any] {
          var forms: [PluralForm: String] = [:]
          for form in PluralForm.allCases {
            if let unit = plural[form.rawValue] as? [String: Any], let value = Self.unitValue(unit) {
              forms[form] = value
            }
          }
          byLanguage[language] = .plural(forms)
        } else {
          throw ReadError(description: "\(key) [\(language)]: neither a stringUnit nor plural variations")
        }
      }
      entries[key] = byLanguage
    }
    return StringCatalog(sourceLanguage: source, entries: entries, comments: comments)
  }

  private static func unitValue(_ object: [String: Any]) -> String? {
    (object["stringUnit"] as? [String: Any])?["value"] as? String
  }

  /// Plural choice for German and English, the two languages there are. Same rule as i18next:
  /// `zero` only when the catalog has it, `one` for exactly 1, everything else `other`.
  public static func pluralForm(for count: Int, available: Set<PluralForm>) -> PluralForm {
    if count == 0, available.contains(.zero) { return .zero }
    return count == 1 && available.contains(.one) ? .one : .other
  }

  /// `{{name}}` in a text, in order of appearance, without duplicates.
  public static func placeholders(in text: String) -> [String] {
    var seen: [String] = []
    var rest = text[...]
    while let open = rest.range(of: "{{") {
      guard let close = rest[open.upperBound...].range(of: "}}") else { break }
      let name = String(rest[open.upperBound..<close.lowerBound])
      if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), !seen.contains(name) {
        seen.append(name)
      }
      rest = rest[close.upperBound...]
    }
    return seen
  }

  /// Fills `{{name}}`; an unknown placeholder stays as it is, as in QuartzControl's `mainT`.
  public static func fill(_ template: String, _ args: [String: String]) -> String {
    guard !args.isEmpty, template.contains("{{") else { return template }
    var result = template
    for (name, value) in args {
      result = result.replacingOccurrences(of: "{{\(name)}}", with: value)
    }
    return result
  }
}
