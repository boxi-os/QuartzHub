import QuartzHubCore
import SwiftUI

/// What the Mehrsprachigkeit tab shows of the plugin's options, in the words of its rows
/// (QuartzControl's `Multilanguage.tsx`: `nameOf`, `summary`).
struct MultilanguageView {
  let entry: MultilanguageOptions.Entry
  let schema: NormalizedOptionSchema?

  var options: JSONObject { entry.plugin.object["options"]?.objectValue ?? JSONObject() }
  var languages: [MultilanguageOptions.Language] { MultilanguageOptions.languages(options) }
  var defaultCode: String { MultilanguageOptions.defaultLanguage(options, languages) }
  var published: [String] { MultilanguageOptions.published(options, languages) }
  var groups: [MultilanguageOptions.SettingsGroup] {
    MultilanguageOptions.settingsGroups(schema, options: options, lang: Self.language)
  }

  static var language: OptionFormText.Language { L10n.language == "en" ? .en : .de }

  /// Its own name where it has one, else its code in capitals.
  static func name(_ l: MultilanguageOptions.Language) -> String {
    for key in ["native", "label"] {
      if let text = l[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
    }
    return l.code.uppercased()
  }

  func title(_ group: MultilanguageOptions.SettingsGroup) -> String {
    if !group.title.isEmpty { return group.title }
    return group.id == MultilanguageOptions.unknownGroup ? L10n.t("pluginOptions.moreKeys") : L10n.t("multilanguageEditor.otherGroup")
  }

  private func field(_ key: String) -> OptionField? { schema?.fields.first { $0.key == key } }
  /// What applies: set, or the plugin's default.
  func value(_ key: String) -> JSONValue? { options[key] ?? field(key)?.defaultValue }
  private func sub(_ key: String, _ child: String) -> JSONValue? {
    if case .object(let own)? = options[key], let value = own[child] { return value }
    if case .object(let fallback)? = field(key)?.defaultValue { return fallback[child] }
    return nil
  }
  private func subField(_ key: String, _ child: String) -> OptionField? {
    guard case .object(let fields, _)? = field(key)?.node else { return nil }
    return fields.first { $0.key == child }
  }

  static func detection(_ value: String) -> String {
    switch value {
    case "folder": L10n.t("multilanguageEditor.detectionValues.folder")
    case "frontmatter": L10n.t("multilanguageEditor.detectionValues.frontmatter")
    case "suffix": L10n.t("multilanguageEditor.detectionValues.suffix")
    default: value
    }
  }

  func detectionList() -> String {
    guard case .array(let list)? = value("detection"), !list.isEmpty else { return L10n.t("multilanguageEditor.none") }
    return list.map { Self.detection($0.stringValue ?? OptionFormText.inline($0)) }.joined(separator: ", ")
  }

  private func onOff(_ value: JSONValue?) -> String {
    value == .bool(true) ? L10n.t("multilanguageEditor.on") : L10n.t("multilanguageEditor.off")
  }

  /// One line per group: what it is set to, built per key, so a key the app knows nothing about adds nothing.
  private func part(_ key: String) -> String? {
    let lang = Self.language
    switch key {
    case "detection": return "\(L10n.t("multilanguageEditor.summaryDetection")): \(detectionList())"
    case "switcher":
      return [sub("switcher", "style"), sub("switcher", "label")].enumerated().compactMap { offset, value -> String? in
        guard case .string(let text)? = value else { return nil }
        return OptionFormText.enumLabel(subField("switcher", offset == 0 ? "style" : "label"), .string(text), lang)
      }.joined(separator: " · ")
    case "seo": return "hreflang \(onOff(sub("seo", "hreflang"))) · og:locale \(onOff(sub("seo", "ogLocale")))"
    case "rootRedirect":
      let root: String = if case .string(let text)? = value("rootRedirect") { OptionFormText.enumLabel(field("rootRedirect"), .string(text), lang) } else { "—" }
      return "\(L10n.t("multilanguageEditor.summaryRoot")): \(root)"
    case "rememberChoice": return value("rememberChoice") == .bool(true) ? L10n.t("multilanguageEditor.summaryRemember") : nil
    default: return nil
    }
  }

  static let switches = ["missingTranslationNotice", "availableTranslationNotice", "rewriteCrossLanguageLinks", "localizeDates"]

  static func short(_ key: String) -> String {
    switch key {
    case "missingTranslationNotice": L10n.t("multilanguageEditor.short.missingTranslationNotice")
    case "availableTranslationNotice": L10n.t("multilanguageEditor.short.availableTranslationNotice")
    case "rewriteCrossLanguageLinks": L10n.t("multilanguageEditor.short.rewriteCrossLanguageLinks")
    case "localizeDates": L10n.t("multilanguageEditor.short.localizeDates")
    default: key
    }
  }

  func summary(_ group: MultilanguageOptions.SettingsGroup) -> String {
    if group.id == MultilanguageOptions.unknownGroup { return group.keys.joined(separator: ", ") }
    var parts = group.keys.compactMap(part).filter { !$0.isEmpty }
    let switches = group.keys.filter(Self.switches.contains)
    if !switches.isEmpty {
      let on = switches.filter { value($0) == .bool(true) }.map(Self.short)
      parts.append(on.isEmpty ? L10n.t("multilanguageEditor.allOff") : on.joined(separator: ", "))
    }
    return parts.joined(separator: " · ")
  }
}

/// Mehrsprachigkeit (QuartzControl's `routes/Plugins/Multilanguage.tsx`). The plugin is one entry
/// for the whole site, so the list is not its instances but its languages, and below them the
/// plugin's other groups, each a row that opens in the inspector. Renaming or removing a language
/// also changes every option that names it by code (`MultilanguageOptions`).
///
/// Every change goes through the plugin list's write queue (`PluginsModel.commit`), each against
/// the newest state.
struct MultilanguageTab: View {
  @Bindable var model: PluginsModel
  /// `lang:<code>` or `section:<id>`: a code and a group's id are stable, a row's place is not.
  @Binding var selection: String?
  @Binding var schema: PluginOptionSchemaResult?
  let showAllOptions: () -> Void
  @Environment(\.unsavedGuard) private var unsaved
  @State private var adding = false

  var body: some View {
    let entries = MultilanguageOptions.entries(model.config?.plugins ?? [])
    if let error = model.loadError {
      Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
    } else if model.config == nil {
      Text(L10n.t("common.loading")).foregroundStyle(.secondary).padding()
    } else if let entry = entries.first {
      let view = MultilanguageView(entry: entry, schema: schema?.schema)
      VSplitView {
        list(view, count: entries.count)
          .frame(minHeight: 260)
        EditorPreview(project: model.project, prefix: "multilanguage", hint: L10n.t("multilanguageEditor.previewHint"),
                      highlight: highlight(view), onAssignClass: {})
          .frame(minHeight: 300)
      }
    } else {
      ContentUnavailableView {
        Label(L10n.t("multilanguageEditor.notInstalledTitle"), systemImage: "globe")
      } description: {
        Text(L10n.t("multilanguageEditor.notInstalledText"))
      }
      // The whole column: at its text's width, the tab picker above moved to the left.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func list(_ view: MultilanguageView, count: Int) -> some View {
    let options = view.options
    let languages = view.languages
    let defaultCode = view.defaultCode
    let published = view.published
    return VStack(alignment: .leading, spacing: 8) {
      Note(L10n.t("multilanguageEditor.intro"))
      if let installed = schema?.packageVersion, installed != MultilanguageOptions.readAgainst, !MultilanguageOptions.sameCode.contains(installed) {
        Warning(L10n.t("plugins.readAgainst", ["plugin": MultilanguageOptions.plugin, "read": MultilanguageOptions.readAgainst, "installed": installed]))
      }
      if let message = model.message { ErrorLine(message) }
      if count > 1 { Warning(L10n.t("multilanguageEditor.severalEntries", ["count": String(count)], count: count)) }
      if let set = options["defaultLanguage"]?.stringValue, MultilanguageOptions.normalizeCode(set) != defaultCode {
        Warning(L10n.t("multilanguageEditor.defaultUnknown", ["code": set, "name": MultilanguageView.name(languages[0])]))
      }
      HStack(spacing: 12) {
        Label(view.entry.plugin.name, systemImage: "puzzlepiece.extension").font(.headline)
        Toggle(L10n.t("multilanguageEditor.enabled"), isOn: Binding(get: { view.entry.plugin.enabled }, set: { on in
          Task {
            await model.toggleEnabled(view.entry.index)
            Announce.post(on ? L10n.t("multilanguageEditor.enabledAnnounce") : L10n.t("multilanguageEditor.disabledAnnounce"))
          }
        }))
        .toggleStyle(.switch)
        .controlSize(.small)
        .help(L10n.t("multilanguageEditor.enabledHint"))
        .accessibilityIdentifier("multilanguage.enabled")
        Spacer()
        Button(L10n.t("multilanguageEditor.allOptions"), action: showAllOptions)
      }
      List(selection: $selection) {
        Section {
          ForEach(Array(languages.enumerated()), id: \.element.code) { offset, language in
            languageRow(language, at: offset, of: languages, isDefault: language.code == defaultCode,
                        published: MultilanguageOptions.isPublished(language.code, published))
          }
          .onMove { from, to in
            guard let first = from.first else { return }
            let moved = languages[first]
            var order = languages
            order.move(fromOffsets: from, toOffset: to)
            let at = order.firstIndex { $0.code == moved.code } ?? 0
            Task { await reorder(order, moved: moved, at: at, count: languages.count) }
          }
        } header: {
          HStack {
            Text(L10n.t("multilanguageEditor.listTitle", ["count": String(languages.count)], count: languages.count))
            Spacer()
            Button { adding = true } label: { Label(L10n.t("multilanguageEditor.add"), systemImage: "plus") }
              .disabled(model.busy)
              .popover(isPresented: $adding, arrowEdge: .bottom) {
                AddLanguageForm(languages: languages) { code in
                  adding = false
                  Task { await add(code) }
                } cancel: { adding = false }
              }
              .accessibilityIdentifier("multilanguage.add")
          }
        }
        Section(L10n.t("multilanguageEditor.sectionsTitle")) {
          if let reason = schema?.unreadable { Warning(L10n.t("pluginOptions.unreadable", ["reason": reason])) }
          if view.schema == nil { Note(L10n.t("multilanguageEditor.noSchema")) }
          ForEach(view.groups, id: \.id) { group in
            VStack(alignment: .leading, spacing: 2) {
              Text(view.title(group)).fontWeight(.medium)
              let line = view.summary(group)
              if !line.isEmpty { Text(line).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(.vertical, 2)
            .tag("section:\(group.id)")
          }
        }
      }
      .accessibilityIdentifier("multilanguage.list")
      .focusedSceneValue(\.moveSelection, moveAction(languages))
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
  }

  private func languageRow(_ language: MultilanguageOptions.Language, at offset: Int, of languages: [MultilanguageOptions.Language],
                           isDefault: Bool, published: Bool) -> some View {
    let name = MultilanguageView.name(language)
    let sub = [language.code] + (language["locale"].map { $0.isEmpty ? [] : [$0] } ?? [])
    return HStack(spacing: 8) {
      // One line, wider where a code is longer: "EN-GB" broke into two in a fixed width.
      Text(language.code.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .lineLimit(1).fixedSize().frame(minWidth: 32)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(name).fontWeight(.medium)
        Text(sub.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      if isDefault { WordBadge(text: L10n.t("multilanguageEditor.defaultBadge"), tint: .green) }
      if !published { WordBadge(text: L10n.t("multilanguageEditor.unpublishedBadge"), tint: .orange) }
      // The last language cannot go: without one the plugin falls back to `en`.
      if languages.count > 1 {
        Button { Task { await remove(language) } } label: {
          Label(L10n.t("common.removeNamed", ["name": name]), systemImage: "trash").labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(L10n.t("common.removeNamed", ["name": name]))
        .disabled(model.busy)
      }
    }
    .padding(.vertical, 2)
    .tag("lang:\(language.code)")
    .contextMenu {
      Button(L10n.t("shell.menu.moveUp")) { Task { await move(language, by: -1) } }.disabled(offset == 0)
      Button(L10n.t("shell.menu.moveDown")) { Task { await move(language, by: 1) } }.disabled(offset == languages.count - 1)
      if languages.count > 1 {
        Divider()
        Button(L10n.t("common.removeNamed", ["name": name]), role: .destructive) { Task { await remove(language) } }
      }
    }
    .accessibilityActions {
      if offset > 0 { Button(L10n.t("pluginsInstalled.moveUp", ["name": name])) { Task { await move(language, by: -1) } } }
      if offset < languages.count - 1 { Button(L10n.t("pluginsInstalled.moveDown", ["name": name])) { Task { await move(language, by: 1) } } }
    }
    .accessibilityIdentifier("multilanguage.language.\(language.code)")
  }

  // MARK: Preview

  /// One component for the whole plugin: whatever is selected, the switcher is what it changes on
  /// the page, marked once something is selected.
  private func highlight(_ view: MultilanguageView) -> PreviewHighlight? {
    guard selection != nil, let found = ComponentSelectors.entry(view.entry.plugin, siblings: [view.entry.plugin]) else { return nil }
    let switcher = view.groups.first { $0.keys.contains("switcher") }
    return PreviewHighlight(selector: found.selector, name: switcher.map(view.title) ?? view.entry.plugin.name, matches: found.matches,
                            ownClass: found.ownClass, pages: nil)
  }

  // MARK: Writing

  /// The plugin's options changed against the newest state; no options left removes the key.
  @discardableResult
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

  private func add(_ code: String) async {
    let c = MultilanguageOptions.normalizeCode(code)
    selection = "lang:\(c)"
    if await update({ MultilanguageOptions.withLanguages($0, MultilanguageOptions.languages($0) + [MultilanguageOptions.Language(code: c)]) }) {
      Announce.post(L10n.t("multilanguageEditor.addedAnnounce", ["code": c]))
    }
  }

  private func remove(_ language: MultilanguageOptions.Language) async {
    guard let entry = MultilanguageOptions.entries(model.config?.plugins ?? []).first else { return }
    let options = entry.plugin.object["options"]?.objectValue ?? JSONObject()
    let languages = MultilanguageOptions.languages(options)
    let name = MultilanguageView.name(language)
    // Removing the one published language publishes all the others, which were held back on
    // purpose: the question says which, and the button is named after it.
    let others = MultilanguageOptions.publishedByRemoving(options, languages, code: language.code)
    let (text, confirm) = others.isEmpty
      ? (L10n.t("multilanguageEditor.removeConfirm", ["name": name]), L10n.t("common.remove"))
      : (L10n.t("multilanguageEditor.removeOnlyPublishedConfirm", ["name": name, "others": others.map(MultilanguageView.name).joined(separator: ", ")]),
         L10n.t("multilanguageEditor.removeAndPublish"))
    let (question, detail) = Confirm.split(text)
    guard await Confirm.ask(question, detail: detail, confirm: confirm, destructive: true, window: unsaved?.window) else { return }
    if selection == "lang:\(language.code)" { selection = nil }
    if await update({ MultilanguageOptions.remove($0, MultilanguageOptions.languages($0), code: language.code) }) {
      Announce.post(L10n.t("multilanguageEditor.removedAnnounce", ["name": name]))
    }
  }

  private func move(_ language: MultilanguageOptions.Language, by delta: Int) async {
    guard let entry = MultilanguageOptions.entries(model.config?.plugins ?? []).first else { return }
    let languages = MultilanguageOptions.languages(entry.plugin.object["options"]?.objectValue)
    guard let from = languages.firstIndex(where: { $0.code == language.code }), languages.indices.contains(from + delta) else { return }
    var order = languages
    order.swapAt(from, from + delta)
    await reorder(order, moved: language, at: from + delta, count: languages.count)
  }

  /// The languages in a new order, against the newest state: the codes decide the order, the
  /// entries are read again so the written form of the others stays.
  private func reorder(_ order: [MultilanguageOptions.Language], moved: MultilanguageOptions.Language, at: Int, count: Int) async {
    let codes = order.map(\.code)
    let done = await update { options in
      let now = MultilanguageOptions.languages(options)
      guard Set(now.map(\.code)) == Set(codes) else { return options }
      return MultilanguageOptions.withLanguages(options, codes.compactMap { code in now.first { $0.code == code } })
    }
    if done {
      Announce.post(L10n.t("multilanguageEditor.movedAnnounce", ["name": MultilanguageView.name(moved), "n": String(at + 1), "count": String(count)]))
    }
  }

  /// Anordnen ▸ Nach oben/unten for the selected language.
  private func moveAction(_ languages: [MultilanguageOptions.Language]) -> MoveSelectionAction? {
    guard let selection, selection.hasPrefix("lang:"),
          let index = languages.firstIndex(where: { "lang:\($0.code)" == selection }) else { return nil }
    let language = languages[index]
    return MoveSelectionAction(canMoveUp: index > 0, canMoveDown: index < languages.count - 1) { delta in
      Task { await move(language, by: delta) }
    }
  }
}

/// A new language: its code, checked as the plugin reads it.
private struct AddLanguageForm: View {
  let languages: [MultilanguageOptions.Language]
  let add: (String) -> Void
  let cancel: () -> Void

  @State private var code = ""
  @State private var tried = false
  @FocusState private var focused: Bool

  var body: some View {
    let problem = MultilanguageOptions.codeProblem(code, languages)
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: "code").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
      TextField("code", text: $code, prompt: Text(verbatim: "fr"))
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .focused($focused)
        .onSubmit(submit)
        .accessibilityLabel(Text(verbatim: "code"))
      Text(L10n.t("multilanguageEditor.addHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if tried, let problem { ErrorLine(MultilanguageTab.problemText(problem)) }
      HStack {
        Spacer()
        Button(L10n.t("common.cancel"), action: cancel).keyboardShortcut(.cancelAction)
        Button(L10n.t("multilanguageEditor.addSubmit"), action: submit).keyboardShortcut(.defaultAction)
      }
    }
    .padding(12)
    .frame(width: 320)
    .onAppear { focused = true }
  }

  private func submit() {
    tried = true
    if MultilanguageOptions.codeProblem(code, languages) == nil { add(code) }
  }
}

extension MultilanguageTab {
  static func problemText(_ problem: MultilanguageOptions.CodeProblem) -> String {
    switch problem {
    case .empty: L10n.t("multilanguageEditor.codeProblem.empty")
    case .taken: L10n.t("multilanguageEditor.codeProblem.taken")
    case .form: L10n.t("multilanguageEditor.codeProblem.form")
    }
  }
}
