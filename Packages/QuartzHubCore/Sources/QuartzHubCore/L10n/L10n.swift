import Foundation
import Synchronization

/// The language setting, as QuartzControl stores it in `settings.json` (`language`).
public enum LanguagePreference: String, Sendable, Codable, CaseIterable {
  case system, de, en
}

/// Every text a user can read, from one catalog, for the app and the core alike.
///
/// `L10n.t("projectLayout.tabs.overview")`, with arguments `L10n.t("common.removeNamed",
/// ["name": "x"])`, plurals by `count`. Keys are QuartzControl's (renderer keys as they were,
/// `mainT` keys under `main.`), so its docs and its code stay searchable by the same name.
public enum L10n {
  private static let state = Mutex<String>(resolve(.system))

  private static let catalog: StringCatalog = {
    guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings") else {
      assertionFailure("Localizable.xcstrings is missing from the QuartzHubCore bundle")
      return StringCatalog(sourceLanguage: "de", entries: [:])
    }
    do {
      return try StringCatalog.load(from: Posix.path(url))
    } catch {
      assertionFailure("Localizable.xcstrings: \(error)")
      return StringCatalog(sourceLanguage: "de", entries: [:])
    }
  }()

  /// The language texts are answered in right now: "de" or "en".
  public static var language: String { state.withLock { $0 } }

  /// Anything but German is English, the same fallback QuartzControl has.
  public static func resolve(_ preference: LanguagePreference, preferred: [String] = Locale.preferredLanguages) -> String {
    switch preference {
    case .de: return "de"
    case .en: return "en"
    case .system: return preferred.first?.lowercased().hasPrefix("de") == true ? "de" : "en"
    }
  }

  public static func apply(_ preference: LanguagePreference) {
    let resolved = resolve(preference)
    state.withLock { $0 = resolved }
  }

  public static func t(_ key: String, _ args: [String: String] = [:], count: Int? = nil) -> String {
    t(in: language, key, args, count: count)
  }

  /// A text in a given language instead of the app's (QuartzControl's `mainTIn`: an exported
  /// document speaks the language of its pages).
  public static func t(in language: String, _ key: String, _ args: [String: String] = [:], count: Int? = nil) -> String {
    text(catalog, language: language, key, args, count: count)
  }

  /// The lookup itself, against any catalog, so tests can feed their own.
  public static func text(_ catalog: StringCatalog, language: String, _ key: String, _ args: [String: String] = [:], count: Int? = nil) -> String {
    let lang = language.lowercased().hasPrefix("de") ? "de" : "en"
    guard let byLanguage = catalog.entries[key],
          let entry = byLanguage[lang] ?? byLanguage["en"] ?? byLanguage[catalog.sourceLanguage]
    else { return key }
    var values = args
    let template: String
    switch entry {
    case .text(let value):
      template = value
    case .plural(let forms):
      let n = count ?? 0
      template = forms[StringCatalog.pluralForm(for: n, available: Set(forms.keys))] ?? forms[.other] ?? key
    }
    if let count { values["count"] = values["count"] ?? String(count) }
    return StringCatalog.fill(template, values)
  }
}
