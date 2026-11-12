import QuartzHubCore
import SwiftUI

/// The site's own settings (QuartzControl's `SiteSettings.tsx`): three sections, one per question
/// the form answers. Each field writes into the page's draft; "Speichern" writes the file.
struct SiteSettingsSections: View {
  @Bindable var model: ConfigModel
  /// The patterns as typed: the draft keeps them trimmed and without empty lines, and a binding
  /// that went through that on every keystroke would swallow the Return that starts a new line.
  @State private var ignoreText = ""

  var body: some View {
    SettingsSection(L10n.t("siteSettings.heading"), symbol: "gearshape") {
      FormField(hint: L10n.t("siteSettings.pageTitleHint")) {
        TextField(L10n.t("siteSettings.pageTitle"), text: binding("pageTitle"))
          .accessibilityIdentifier("config.pageTitle")
      }
      FormField(hint: L10n.t("siteSettings.pageTitleSuffixHint")) {
        TextField(L10n.t("siteSettings.pageTitleSuffix"), text: binding("pageTitleSuffix"))
      }
      FormField(hint: L10n.t("siteSettings.baseUrlHint")) {
        TextField(L10n.t("siteSettings.baseUrl"), text: binding("baseUrl"), prompt: Text(verbatim: "example.com"))
      }
      localeField
      FormField(hint: L10n.t("siteSettings.spaHint")) {
        Toggle(L10n.t("siteSettings.spa"), isOn: flag("enableSPA"))
      }
      FormField(hint: L10n.t("siteSettings.popoversHint")) {
        Toggle(L10n.t("siteSettings.popovers"), isOn: flag("enablePopovers"))
      }
      if model.features.prefetch {
        FormField(hint: L10n.t("siteSettings.prefetchHint")) {
          Picker(L10n.t("siteSettings.prefetch"), selection: choice("prefetch", default: "viewport")) {
            Text(L10n.t("siteSettings.prefetchViewport")).tag("viewport")
            Text(L10n.t("siteSettings.prefetchHover")).tag("hover")
            Text(L10n.t("siteSettings.prefetchOff")).tag("off")
            unknown("prefetch", known: ["viewport", "hover", "off"])
          }
          .accessibilityIdentifier("config.prefetch")
        }
      }
    }

    SettingsSection(L10n.t("siteSettings.ignoreHeading"), symbol: "eye.slash") {
      FormField(hint: L10n.t("siteSettings.ignorePatternsHint")) {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.t("siteSettings.ignorePatterns"))
          TextEditor(text: $ignoreText)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 96)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .accessibilityLabel(L10n.t("siteSettings.ignorePatterns"))
            .accessibilityIdentifier("config.ignorePatterns")
        }
      }
      if model.features.publishAssets {
        FormField(hint: L10n.t("siteSettings.publishAssetsHint")) {
          Picker(L10n.t("siteSettings.publishAssets"), selection: choice("publishAssets", default: "all")) {
            Text(L10n.t("siteSettings.publishAssetsAll")).tag("all")
            Text(L10n.t("siteSettings.publishAssetsReferenced")).tag("referenced")
            unknown("publishAssets", known: ["all", "referenced"])
          }
          .accessibilityIdentifier("config.publishAssets")
        }
      }
    }
    .onChange(of: model.ignorePatterns, initial: true) { _, patterns in
      // Only when the draft changed under the text (read, saved, read again), not on our own edit.
      if Self.parse(ignoreText) != patterns { ignoreText = patterns.joined(separator: "\n") }
    }
    .onChange(of: ignoreText) { _, text in
      let patterns = Self.parse(text)
      if patterns != model.ignorePatterns { model.setIgnorePatterns(patterns) }
    }

    AnalyticsSection(model: model)
  }

  static func parse(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private func binding(_ key: String) -> Binding<String> {
    Binding(get: { model.string(key) }, set: { model.setString(key, $0) })
  }

  private func flag(_ key: String) -> Binding<Bool> {
    Binding(get: { model.bool(key) }, set: { model.setBool(key, $0) })
  }

  /// One of Quartz's words for a key; a missing key shows Quartz's default and stays missing
  /// until a choice is made.
  private func choice(_ key: String, default fallback: String) -> Binding<String> {
    Binding(get: { model.config?.configuration[key]?.stringValue ?? fallback }, set: { model.setString(key, $0) })
  }

  /// A value the file has that QuartzHub has no word for stays selectable as it is.
  @ViewBuilder private func unknown(_ key: String, known: [String]) -> some View {
    if let value = model.config?.configuration[key]?.stringValue, !known.contains(value) {
      Text(verbatim: value).tag(value)
    }
  }

  /// The valid values are the locale files in the project: Quartz's `i18n()` is a plain lookup, and
  /// a wrong key failed the build in an emitter with an error naming neither the locale nor the
  /// setting. A locale the project does not ship stays selectable, marked: it is what the file says.
  @ViewBuilder private var localeField: some View {
    let locale = model.string("locale")
    let shipped = model.locales ?? []
    if shipped.isEmpty {
      FormField(hint: L10n.t("siteSettings.localeHintFree")) {
        TextField(L10n.t("siteSettings.locale"), text: binding("locale"), prompt: Text(verbatim: "en-US"))
      }
    } else {
      let options = Array(Set(shipped + [locale]).filter { !$0.isEmpty }).sorted()
      FormField(hint: L10n.t("siteSettings.localeHint")) {
        Picker(L10n.t("siteSettings.locale"), selection: binding("locale")) {
          if locale.isEmpty { Text(verbatim: "–").tag("") }
          ForEach(options, id: \.self) { code in
            Text(shipped.contains(code) ? code : "\(code) \(L10n.t("siteSettings.localeUnknownSuffix"))").tag(code)
          }
        }
        .accessibilityIdentifier("config.locale")
      }
    }
  }
}

/// The analytics providers Quartz understands, with the fields each reads: the `Analytics` union in
/// the project's `quartz/cfg.ts`. Switching provider drops the previous one's keys (the config is
/// a union; a leftover `tagId` on a plausible entry is a shape Quartz never reads), an emptied
/// optional field is removed rather than written as "" (Quartz would put it into the script URL),
/// and the required fields still empty are named.
private struct AnalyticsSection: View {
  @Bindable var model: ConfigModel

  struct Field {
    let key: String
    var required = false
    /// Read by Quartz 5.1 and later (umami's `script`, PostHog's hosts and profiles).
    var since51 = false
  }

  static let providers: [(name: String, fields: [Field])] = [
    ("plausible", [Field(key: "host")]),
    ("google", [Field(key: "tagId", required: true)]),
    ("umami", [Field(key: "websiteId", required: true), Field(key: "host"), Field(key: "script", since51: true)]),
    ("goatcounter", [Field(key: "websiteId", required: true), Field(key: "host"), Field(key: "scriptSrc")]),
    ("posthog", [Field(key: "apiKey", required: true), Field(key: "apiHost", since51: true), Field(key: "uiHost", since51: true),
                 Field(key: "personProfiles", since51: true), Field(key: "host")]),
    ("tinylytics", [Field(key: "siteId", required: true)]),
    ("cabin", [Field(key: "host")]),
    ("clarity", [Field(key: "projectId")]),
    ("matomo", [Field(key: "host", required: true), Field(key: "siteId", required: true)]),
    ("vercel", []),
    ("rybbit", [Field(key: "siteId", required: true), Field(key: "host")]),
  ]

  private var value: JSONObject? { model.config?.configuration["analytics"]?.objectValue }
  private var provider: String { value?["provider"]?.stringValue ?? "" }
  private var fields: [Field] {
    (Self.providers.first { $0.name == provider }?.fields ?? []).filter { !$0.since51 || model.features.analytics51 }
  }

  var body: some View {
    SettingsSection(L10n.t("siteSettings.analyticsHeading"), symbol: "chart.bar") {
      Note(L10n.t("siteSettings.analyticsDescription"))
      Picker(L10n.t("siteSettings.analyticsProvider"), selection: Binding(get: { provider }, set: select)) {
        Text(L10n.t("siteSettings.analyticsNone")).tag("")
        // A provider QuartzHub does not know stays what the file says.
        if !provider.isEmpty, !Self.providers.contains(where: { $0.name == provider }) {
          Text(verbatim: provider).tag(provider)
        }
        ForEach(Self.providers, id: \.name) { Text(verbatim: $0.name).tag($0.name) }
      }
      .accessibilityIdentifier("config.analytics")
      ForEach(fields, id: \.key) { field in
        FormField(hint: Self.hint(field, provider: provider, analytics51: model.features.analytics51)) {
          TextField(field.key + (field.required ? " *" : ""), text: text(field.key))
        }
      }
      let missing = fields.filter { $0.required && JSRead.string(value?[$0.key]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.key)
      if !provider.isEmpty, !missing.isEmpty {
        Label(L10n.t("siteSettings.analyticsMissing", ["fields": missing.joined(separator: ", ")]), systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(.orange)
      }
    }
  }

  private func select(_ next: String) {
    model.config?.configuration["analytics"] = next.isEmpty ? .null : .object(JSONObject([("provider", .string(next))]))
  }

  private func text(_ key: String) -> Binding<String> {
    Binding(
      get: { JSRead.string(value?[key]) },
      set: { typed in
        var next = value ?? JSONObject()
        next[key] = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .string(typed)
        model.config?.configuration["analytics"] = .object(next)
      })
  }

  /// `host` is the one key whose meaning flips: optional everywhere, the address of your own
  /// installation for matomo, where "leave it empty" would contradict the asterisk.
  static func hint(_ field: Field, provider: String, analytics51: Bool) -> String? {
    switch field.key {
    case "host" where provider == "posthog" && analytics51:
      L10n.t("siteSettings.analyticsFields.posthogHost")
    case "host": field.required ? L10n.t("siteSettings.analyticsFields.hostRequired") : L10n.t("siteSettings.analyticsFields.host")
    case "script": L10n.t("siteSettings.analyticsFields.script")
    case "apiHost": L10n.t("siteSettings.analyticsFields.apiHost")
    case "uiHost": L10n.t("siteSettings.analyticsFields.uiHost")
    case "personProfiles": L10n.t("siteSettings.analyticsFields.personProfiles")
    case "tagId": L10n.t("siteSettings.analyticsFields.tagId")
    case "websiteId": L10n.t("siteSettings.analyticsFields.websiteId")
    case "apiKey": L10n.t("siteSettings.analyticsFields.apiKey")
    case "siteId": L10n.t("siteSettings.analyticsFields.siteId")
    case "projectId": L10n.t("siteSettings.analyticsFields.projectId")
    case "scriptSrc": L10n.t("siteSettings.analyticsFields.scriptSrc")
    default: nil
    }
  }
}

/// `String(value ?? '')` for a field's text.
enum JSRead {
  static func string(_ value: JSONValue?) -> String {
    switch value {
    case nil, .null?: ""
    case .string(let text)?: text
    case .number(let number)?: number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
    case .bool(let flag)?: flag ? "true" : "false"
    default: ""
    }
  }
}
