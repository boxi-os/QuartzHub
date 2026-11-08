import QuartzHubCore
import SwiftUI

/// One language in the inspector (QuartzControl's `LanguagePanel`): its code, which renames it
/// everywhere the options name it, its own fields, default and published, its place in the list.
struct LanguageInspector: View {
  let language: MultilanguageOptions.Language
  let view: MultilanguageView
  @Bindable var model: PluginsModel
  @Binding var selection: String?

  @State private var codeDraft: String?

  /// The fields of a language, in the order of the plugin's schema; `home` and `flag` are advanced
  /// there and stand under "selten gebraucht" here.
  private static let fields = ["label", "native", "locale"]
  private static let advanced = ["home", "flag"]

  private var languages: [MultilanguageOptions.Language] { view.languages }
  private var position: Int { languages.firstIndex { $0.code == language.code } ?? 0 }
  private var isDefault: Bool { language.code == view.defaultCode }
  private var published: Bool { MultilanguageOptions.isPublished(language.code, view.published) }
  private var onlyPublished: Bool {
    published && languages.filter { MultilanguageOptions.isPublished($0.code, view.published) }.count == 1
  }

  /// The schema's own words for each field: the object variant of `languages`' items.
  private var itemFields: [OptionField] {
    guard case .array(let items)? = view.schema?.fields.first(where: { $0.key == "languages" })?.node else { return [] }
    switch items {
    case .object(let fields, _): return fields
    case .union(let variants):
      for case .object(let fields, _) in variants { return fields }
      return []
    default: return []
    }
  }

  var body: some View {
    let name = MultilanguageView.name(language)
    let problem = codeDraft.flatMap { MultilanguageOptions.codeProblem($0, languages, own: language.code) }
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(name, systemImage: "globe").font(.headline).accessibilityIdentifier("multilanguage.inspector.name")
          HStack(spacing: 6) {
            Text(L10n.t("multilanguageEditor.positionOf", ["n": String(position + 1), "count": String(languages.count)]))
              .font(.caption).foregroundStyle(.secondary)
            if model.savedIndex == view.entry.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          }
          Note(L10n.t("plugins.savesImmediately"))
        }
      }
      Section {
        field("code", hint: L10n.t("multilanguageEditor.codeHint")) {
          CommitField(name: "code", text: language.code) { raw in
            codeDraft = nil
            let to = MultilanguageOptions.normalizeCode(raw)
            if MultilanguageOptions.codeProblem(raw, languages, own: language.code) != nil {
              codeDraft = raw
              return false
            }
            if to != language.code { Task { await rename(to) } }
            return true
          }
          .accessibilityIdentifier("multilanguage.inspector.code")
        }
        if let problem { ErrorLine(MultilanguageTab.problemText(problem)) }
        ForEach(Self.fields, id: \.self) { textField($0) }
      }
      Section {
        Toggle(L10n.t("multilanguageEditor.isDefault"), isOn: Binding(get: { isDefault }, set: { on in if on { Task { await makeDefault() } } }))
          .disabled(isDefault)
        Note(isDefault ? L10n.t("multilanguageEditor.isDefaultHintOn") : L10n.t("multilanguageEditor.isDefaultHint")).font(.caption)
        Toggle(L10n.t("multilanguageEditor.publish"), isOn: Binding(get: { published }, set: { on in Task { await publish(on) } }))
          .disabled(onlyPublished)
        Note(onlyPublished ? L10n.t("multilanguageEditor.publishOnlyHint") : L10n.t("multilanguageEditor.publishHint")).font(.caption)
      }
      Section(L10n.t("multilanguageEditor.order")) {
        Note(L10n.t("multilanguageEditor.orderHint")).font(.caption)
        HStack {
          Button { Task { await move(-1) } } label: { Label(L10n.t("layoutEditor.inspector.earlier"), systemImage: "arrow.up") }
            .disabled(position == 0)
          Button { Task { await move(1) } } label: { Label(L10n.t("layoutEditor.inspector.later"), systemImage: "arrow.down") }
            .disabled(position == languages.count - 1)
        }
      }
      Section(L10n.t("pluginOptions.rarelyUsed")) {
        ForEach(Self.advanced, id: \.self) { textField($0) }
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
  }

  private func hint(_ key: String) -> String? {
    itemFields.first { $0.key == key }.flatMap { OptionFormText.texts($0, MultilanguageView.language).description }
  }

  @ViewBuilder private func field<Content: View>(_ key: String, hint: String?, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: key).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
      content()
      if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
  }

  private func textField(_ key: String) -> some View {
    field(key, hint: hint(key)) {
      CommitField(name: key, text: language[key] ?? "") { raw in
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await set(key, value.isEmpty ? nil : .string(value)) }
        return true
      }
    }
  }

  // MARK: Writing, each against the newest state

  private func update(_ change: @escaping (JSONObject) -> JSONObject) async -> Bool {
    await model.commit { plugins in
      guard let entry = MultilanguageOptions.entries(plugins).first else { return plugins }
      var object = entry.plugin.object
      let next = change(object["options"]?.objectValue ?? JSONObject())
      object["options"] = next.isEmpty ? nil : .object(next)
      var out = plugins
      out[entry.index] = PluginEntry(object: object)
      return out
    }
  }

  private func set(_ key: String, _ value: JSONValue?) async {
    let code = language.code
    await update { options in
      MultilanguageOptions.withLanguages(options, MultilanguageOptions.languages(options).map { $0.code == code ? $0.with(key, value) : $0 })
    }
  }

  private func rename(_ to: String) async {
    let from = language.code
    selection = "lang:\(to)"
    if await update({ MultilanguageOptions.rename($0, MultilanguageOptions.languages($0), from: from, to: to) }) {
      Announce.post(L10n.t("multilanguageEditor.renamedAnnounce", ["from": from, "to": to]))
    }
  }

  private func makeDefault() async {
    let code = language.code
    let name = MultilanguageView.name(language)
    if await update({ options in
      var next = options
      next["defaultLanguage"] = .string(code)
      return next
    }) {
      Announce.post(L10n.t("multilanguageEditor.defaultAnnounce", ["name": name]))
    }
  }

  private func publish(_ on: Bool) async {
    let code = language.code
    let name = MultilanguageView.name(language)
    if await update({ MultilanguageOptions.withPublished($0, MultilanguageOptions.languages($0), code: code, on: on) }) {
      Announce.post(on ? L10n.t("multilanguageEditor.publishedAnnounce", ["name": name]) : L10n.t("multilanguageEditor.unpublishedAnnounce", ["name": name]))
    }
  }

  private func move(_ delta: Int) async {
    let code = language.code
    let name = MultilanguageView.name(language)
    let to = position + delta
    let count = languages.count
    if await update({ options in
      var now = MultilanguageOptions.languages(options)
      guard let i = now.firstIndex(where: { $0.code == code }), now.indices.contains(i + delta) else { return options }
      now.swapAt(i, i + delta)
      return MultilanguageOptions.withLanguages(options, now)
    }) {
      Announce.post(L10n.t("multilanguageEditor.movedAnnounce", ["name": name, "n": String(to + 1), "count": String(count)]))
    }
  }
}

/// One group of the plugin's settings in the inspector (QuartzControl's `SectionPanel`). A group
/// that is one object (`switcher`, `seo`) shows what is inside it: the heading already names it.
struct SettingsGroupInspector: View {
  let group: MultilanguageOptions.SettingsGroup
  let view: MultilanguageView
  @Bindable var model: PluginsModel
  @Environment(\.openPage) private var openPage

  var body: some View {
    let schema = view.schema
    let sole = MultilanguageOptions.soleObject(schema, group)
    let options = view.options
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(view.title(group), systemImage: "slider.horizontal.3").font(.headline)
          if let sole, let description = OptionFormText.texts(sole, MultilanguageView.language).description {
            Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
          if model.savedIndex == view.entry.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          Note(L10n.t("plugins.savesImmediately"))
        }
        if group.keys.contains("switcher") {
          VStack(alignment: .leading, spacing: 6) {
            if case .string(let position)? = LayoutEntries.layout(view.entry.plugin)?["position"] {
              Text(L10n.t("multilanguageEditor.switcherAt", ["position": InstalledTab.positionTitle(position)])).font(.callout).foregroundStyle(.secondary)
            } else {
              Text(L10n.t("multilanguageEditor.switcherNotPlaced")).font(.callout).foregroundStyle(.secondary)
            }
            Button(L10n.t("pluginsInstalled.showOnStage")) { openPage(.layout) }
          }
        }
      }
      if let sole, case .object(let fields, _) = sole.node, let schema {
        OptionsForm(schema: NormalizedOptionSchema(source: schema.source, fields: fields, notes: []),
                    values: options[sole.key]?.objectValue ?? JSONObject(),
                    onChange: { next in Task { await set { options in
                      var rest = options
                      rest[sole.key] = next.map(JSONValue.object)
                      return rest
                    } } },
                    explicitEmpty: true, languages: view.languages.map(\.code), freeKeys: false,
                    root: OptionRoot(flat: true, keyPrefix: "\(sole.key)."), projectPath: model.project.path)
      } else {
        OptionsForm(schema: schema, values: options,
                    onChange: { next in Task { await set { _ in next ?? JSONObject() } } },
                    explicitEmpty: true, languages: view.languages.map(\.code), pick: { group.keys.contains($0) },
                    freeKeys: group.id.isEmpty || group.id == MultilanguageOptions.unknownGroup,
                    root: OptionRoot(flat: true), projectPath: model.project.path)
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
  }

  private func set(_ change: @escaping (JSONObject) -> JSONObject) async {
    _ = await model.commit { plugins in
      guard let entry = MultilanguageOptions.entries(plugins).first else { return plugins }
      var object = entry.plugin.object
      let next = change(object["options"]?.objectValue ?? JSONObject())
      object["options"] = next.isEmpty ? nil : .object(next)
      var out = plugins
      out[entry.index] = PluginEntry(object: object)
      return out
    }
  }
}

/// Nothing selected: the languages in one look.
struct MultilanguageOverview: View {
  let view: MultilanguageView

  var body: some View {
    let languages = view.languages
    let published = view.published
    Section(L10n.t("multilanguageEditor.panelEmptyTitle")) {
      Note(L10n.t("multilanguageEditor.panelEmptyText"))
      LabeledContent(L10n.t("multilanguageEditor.summaryLanguages"), value: languages.map(MultilanguageView.name).joined(separator: ", "))
      LabeledContent(L10n.t("multilanguageEditor.summaryDefault"),
                     value: languages.first { $0.code == view.defaultCode }.map(MultilanguageView.name) ?? "")
      LabeledContent(L10n.t("multilanguageEditor.summaryPublished"),
                     value: published.isEmpty ? L10n.t("multilanguageEditor.publishedAll")
                       : languages.filter { published.contains($0.code) }.map(MultilanguageView.name).joined(separator: ", "))
      LabeledContent(L10n.t("multilanguageEditor.summaryDetection"), value: view.detectionList())
    }
  }
}
