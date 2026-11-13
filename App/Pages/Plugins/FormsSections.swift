import QuartzHubCore
import SwiftUI

/// The public keys encrypting forms send to (QuartzControl's `FormsKeys.tsx`). Each row says what
/// quartz-forms itself reads in it (fingerprint, user id, expiry, or the problem that stops the
/// build) from its own check, not from a copy of OpenPGP. A key comes from a file, copied into the
/// project under quartz-forms/keys/, or pasted; a pasted text is stored as its public key block
/// alone, after the plugin has read it.
struct FormsKeysSection: View {
  let view: FormsView
  @Bindable var model: PluginsModel
  let state: FormsState
  @Environment(\.unsavedGuard) private var unsaved

  @State private var adding: Bool?
  @State private var name = ""
  @State private var way = "file"
  @State private var pasted = ""
  @State private var error: String?
  @State private var busy = false

  private var options: JSONObject { view.options }
  private var keys: JSONObject { options["keys"]?.objectValue ?? JSONObject() }

  var body: some View {
    let reports: [String: FormsKeyReport] = if case .checked(_, _, let list)? = state.check {
      Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    } else { [:] }
    let isAdding = adding ?? keys.isEmpty
    let problem = FormsOptions.keyNameProblem(name, existing: keys.keys)
    Section {
      if case .unavailable(let reason)? = state.check { Callout(.warning, L10n.t("formsEditor.keys.notChecked", ["reason": reason])) }
      if keys.isEmpty, !isAdding { Note(L10n.t("formsEditor.keys.none")) }
      ForEach(keys.keys, id: \.self) { key in
        keyRow(key, report: reports[key])
      }
      if state.checking { Note(L10n.t("formsEditor.keys.checking")) }
      if !isAdding {
        Button(L10n.t("formsEditor.keys.add")) { adding = true }
      }
    }
    if isAdding {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.t("formsEditor.keys.name"))
          TextField(L10n.t("formsEditor.keys.name"), text: Binding(get: { name }, set: { name = $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
                    prompt: Text(L10n.t("formsEditor.placeholders.keyName")))
            .textFieldStyle(.roundedBorder).labelsHidden()
          Text(L10n.t("formsEditor.keys.nameHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          if !name.isEmpty, let problem { FieldProblem(Self.nameProblem(problem)) }
        }
        Picker(L10n.t("formsEditor.keys.way"), selection: $way) {
          Text(L10n.t("formsEditor.keys.wayFile")).tag("file")
          Text(L10n.t("formsEditor.keys.wayPaste")).tag("paste")
        }
        .pickerStyle(.segmented)
        if way == "file" {
          VStack(alignment: .leading, spacing: 4) {
            Button { Task { await fromFile() } } label: { Label(L10n.t("formsEditor.keys.pickFile"), systemImage: "doc.badge.arrow.up") }
              .disabled(problem != nil || busy)
            Text(L10n.t("formsEditor.keys.pickFileHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
        } else {
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("formsEditor.keys.pasteLabel"))
            TextEditor(text: $pasted)
              .font(.system(.caption, design: .monospaced))
              .frame(minHeight: 110, maxHeight: 220)
              .scrollContentBackground(.hidden)
              .padding(4)
              .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
              .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
              .overlay(alignment: .topLeading) {
                if pasted.isEmpty {
                  Text(verbatim: "-----BEGIN PGP PUBLIC KEY BLOCK-----").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false)
                }
              }
              .accessibilityLabel(L10n.t("formsEditor.keys.pasteLabel"))
            Button(L10n.t("formsEditor.keys.pasteSubmit")) { Task { await fromPaste() } }
              .disabled(problem != nil || pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
          }
        }
        if let error { Callout(.error, error) }
        Button(L10n.t("common.cancel")) { adding = false }
      }
    }
  }

  private func keyRow(_ key: String, report: FormsKeyReport?) -> some View {
    let source = keys[key]?.objectValue
    let users = FormsOptions.formsUsingKey(options, name: key)
    return HStack(alignment: .top, spacing: 8) {
      Image(systemName: "key").foregroundStyle(.secondary).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(key).fontWeight(.medium)
        Text(source?["file"]?.stringValue.map { L10n.t("formsEditor.keys.fromFile", ["file": $0]) } ?? L10n.t("formsEditor.keys.pasted"))
          .font(.caption).foregroundStyle(.secondary)
        if let report {
          if !report.fingerprint.isEmpty {
            Text(verbatim: report.fingerprint).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
          }
          if let user = report.userIds.first { Text(user).font(.caption).foregroundStyle(.secondary) }
          if let problem = report.problem {
            Callout(.error, problem)
          } else {
            if let expires = report.expires { Text(L10n.t("formsEditor.keys.expires", ["date": expires])).font(.caption).foregroundStyle(.secondary) }
            if let notice = report.notice { Callout(.warning, notice) }
          }
        } else if case .checked? = state.check, !state.checking {
          Text(L10n.t("formsEditor.keys.unread")).font(.caption).foregroundStyle(.secondary)
        }
        Text(users.isEmpty ? L10n.t("formsEditor.keys.unused") : L10n.t("formsEditor.keys.usedBy", ["forms": users.joined(separator: ", ")]))
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button { Task { await remove(key) } } label: {
        Label(L10n.t("common.removeNamed", ["name": key]), systemImage: "trash").labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.t("common.removeNamed", ["name": key]))
    }
    .accessibilityElement(children: .contain)
  }

  static func nameProblem(_ problem: FormsOptions.KeyNameProblem) -> String {
    switch problem {
    case .empty: L10n.t("formsEditor.keys.nameProblem.empty")
    case .pattern: L10n.t("formsEditor.keys.nameProblem.pattern")
    case .taken: L10n.t("formsEditor.keys.nameProblem.taken")
    }
  }

  // MARK: Writing

  private func remove(_ key: String) async {
    let users = FormsOptions.formsUsingKey(options, name: key)
    let text = users.isEmpty ? L10n.t("formsEditor.keys.removeConfirm", ["name": key])
      : L10n.t("formsEditor.keys.removeConfirmUsed", ["name": key, "forms": users.joined(separator: ", "), "count": String(users.count)], count: users.count)
    let (question, detail) = Confirm.split(text)
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("common.remove"), destructive: true, window: unsaved?.window) else { return }
    if await FormsTab.update(model, { FormsOptions.withoutKey($0, name: key) }) {
      Announce.post(L10n.t("formsEditor.keys.removedAnnounce", ["name": key]))
    }
  }

  private func store(_ name: String, _ value: JSONObject) async {
    if await FormsTab.update(model, { options in
      var next = options
      var keys = options["keys"]?.objectValue ?? JSONObject()
      keys[name] = .object(value)
      next["keys"] = .object(keys)
      return next
    }) {
      Announce.post(L10n.t("formsEditor.keys.addedAnnounce", ["name": name]))
      adding = false
      self.name = ""
      pasted = ""
    }
  }

  private func fromFile() async {
    error = nil
    guard let path = FilePick.one(extensions: ["asc", "gpg", "pgp", "key", "txt"], message: L10n.t("formsEditor.keys.pickFileHint")) else { return }
    busy = true
    defer { busy = false }
    let project = model.project.path
    let name = name
    do {
      var result = try FormsCLI.importKeyFile(project: project, from: path, name: name, overwrite: false)
      if case .exists(let file) = result {
        let (question, detail) = Confirm.split(L10n.t("formsEditor.keys.overwriteConfirm", ["file": file]))
        guard await Confirm.ask(question, detail: detail, confirm: L10n.t("formsEditor.keys.overwrite"), destructive: true,
                                window: unsaved?.window) else { return }
        result = try FormsCLI.importKeyFile(project: project, from: path, name: name, overwrite: true)
      }
      if case .file(let file) = result { await store(name, JSONObject([("file", .string(file))])) }
    } catch {
      self.error = error.message
    }
  }

  private func fromPaste() async {
    error = nil
    guard let source = PluginSource(view.entry.plugin.source) else { return }
    busy = true
    defer { busy = false }
    let environment = await AppServices.current()
    switch await FormsCLI(project: model.project.path, source: source, environment: environment).inspectKey(pasted) {
    case .unavailable(let reason):
      error = L10n.t("formsEditor.keys.notChecked", ["reason": reason])
    case .key(let report, let armored):
      guard report.problem == nil, let armored else {
        error = L10n.t("formsEditor.keys.refused", ["problem": report.problem ?? ""])
        return
      }
      await store(name, JSONObject([("armored", .string(armored))]))
    }
  }
}

/// The Texte section (QuartzControl's `FormsTexts.tsx`): every text of quartz-forms in one site
/// language, with the plugin's wording as the placeholder and the site's own (`options.texts`) as
/// the value. The wording comes from the installed plugin (`FormsCLI.texts`), not from a copy;
/// while it cannot be read, the plugin's form for `texts` stands in, with the reason above it.
struct FormsTextsSection: View {
  let view: FormsView
  @Bindable var model: PluginsModel
  let state: FormsState

  @SceneStorage("forms.textsLanguage") private var picked = ""
  @State private var result: FormsTextsResult?
  @State private var search = ""

  private var options: JSONObject { view.options }
  private var codes: [String] {
    let languages = model.config?.siteLanguages ?? []
    return languages.isEmpty ? [FormsView.lang] : languages
  }
  private var code: String { codes.contains(picked) ? picked : codes[0] }

  var body: some View {
    let installed = state.schema?.packageVersion
    let older = installed.map { SemVer.isNewer(FormsOptions.textsSince, than: $0) } ?? false
    Group {
      if let plugin = wording {
        list(plugin)
      } else if older, let installed {
        Section { Callout(.warning, L10n.t("formsEditor.textList.older", ["since": FormsOptions.textsSince, "installed": installed])) }
        fallback
      } else if case .unavailable(let reason)? = result {
        Section { Callout(.warning, L10n.t("formsEditor.textList.unavailable", ["reason": reason])) }
        fallback
      } else {
        Section { Note(L10n.t("formsEditor.textList.reading")) }
      }
    }
    .task(id: view.entry.plugin.source.map(JSJSON.compact) ?? "") {
      guard let source = PluginSource(view.entry.plugin.source) else { return }
      let environment = await AppServices.current()
      result = await FormsCLI(project: model.project.path, source: source, environment: environment).texts()
    }
  }

  /// The plugin's own lookup: a locale of the same primary subtag, else en-US.
  private var wording: (locale: String, words: JSONObject, own: Bool)? {
    guard case .read(let locales)? = result else { return nil }
    let match = locales.keys.first { FormsOptions.primary($0) == FormsOptions.primary(code) }
    let locale = match ?? "en-US"
    let words = locales[locale]?.objectValue ?? locales.keys.first.flatMap { locales[$0]?.objectValue } ?? JSONObject()
    return (locale, words, match != nil)
  }

  private var fallback: some View {
    OptionsForm(schema: view.schema, values: options,
                onChange: { next in Task { await FormsTab.update(model) { _ in next ?? JSONObject() } } },
                explicitEmpty: true, languages: model.config?.siteLanguages ?? [], pick: { $0 == "texts" }, freeKeys: false,
                root: OptionRoot(flat: true), projectPath: model.project.path)
  }

  @ViewBuilder private func list(_ plugin: (locale: String, words: JSONObject, own: Bool)) -> some View {
    let texts = options["texts"]?.objectValue ?? JSONObject()
    let key = FormsOptions.entryKey(texts, code: code)
    // Two entries of one language (`de` and `de-DE`, only by hand): which one a page shows is not
    // this tab's to know, and it says so.
    let sameLanguage = texts.keys.filter { FormsOptions.primary($0) == FormsOptions.primary(code) }
    let own = texts[key]?.objectValue ?? JSONObject()
    let names = plugin.words.keys + own.keys.filter { plugin.words[$0] == nil }
    let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let shown = needle.isEmpty ? names : names.filter { name in
      [name, plugin.words[name]?.stringValue ?? "", own[name]?.stringValue ?? ""].contains { $0.lowercased().contains(needle) }
    }
    Section {
      if codes.count > 1 {
        Picker(L10n.t("formsEditor.textList.language"), selection: Binding(get: { code }, set: { picked = $0 })) {
          ForEach(codes, id: \.self) { Text($0.uppercased()).tag($0) }
        }
        .pickerStyle(.segmented)
      }
      Note(L10n.t("formsEditor.textList.hint") + (own.isEmpty ? "" : " " + L10n.t("formsEditor.ownTexts", ["count": String(own.count)], count: own.count)))
      if !plugin.own { Note(L10n.t("formsEditor.textList.fallbackLocale", ["code": code, "locale": plugin.locale])) }
      if sameLanguage.count > 1 { Callout(.warning, L10n.t("formsEditor.textList.severalEntries", ["keys": sameLanguage.joined(separator: ", "), "key": key])) }
      TextField(L10n.t("formsEditor.textList.search"), text: $search, prompt: Text(L10n.t("formsEditor.textList.search")))
        .textFieldStyle(.roundedBorder).labelsHidden()
    }
    Section {
      if shown.isEmpty { Note(L10n.t("formsEditor.textList.noMatch")) }
      ForEach(shown, id: \.self) { name in
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline) {
            Text(verbatim: name).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            if own[name] != nil { Text(L10n.t("pluginOptions.changed")).font(.caption.weight(.medium)).foregroundStyle(.tint) }
            Spacer()
            if own[name] != nil {
              Button(L10n.t("formsEditor.textList.reset")) { Task { await setText(name, nil, key: key) } }
                .buttonStyle(.borderless)
                .help(L10n.t("formsEditor.textList.resetHint", ["name": name]))
            }
          }
          // Written as typed: some of the plugin's own carry spaces at their edges (" oder "), and
          // an emptied own text is an empty text, not the plugin's.
          CommitField(name: name, text: own[name]?.stringValue ?? "",
                      placeholder: own[name] == .string("") ? L10n.t("formsEditor.textList.empty") : plugin.words[name]?.stringValue) { raw in
            Task { await setText(name, raw, key: key) }
            return true
          }
          .id("\(key):\(name)")
          if FormsOptions.relayOwnWords.contains(name) {
            Text(L10n.t("formsEditor.textList.relayOwnWords")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
          if plugin.words[name] == nil { NoEffectLine(L10n.t("formsEditor.textList.unknown")) }
        }
      }
    }
  }

  /// One text of the language's entry; nil takes the own text back. An emptied list stays where it
  /// stood (`texts: {}`) and is not written where it did not.
  private func setText(_ name: String, _ value: String?, key: String) async {
    await FormsTab.update(model) { options in
      var all = options["texts"]?.objectValue ?? JSONObject()
      var entry = all[key]?.objectValue ?? JSONObject()
      entry[name] = value.map(JSONValue.string)
      all[key] = entry.isEmpty ? nil : .object(entry)
      var next = options
      if !all.isEmpty || options["texts"]?.objectValue != nil { next["texts"] = .object(all) } else { next["texts"] = nil }
      return next
    }
  }
}

/// The layout form's place on the page: in a position the board knows, or not placed.
struct FormsPositionField: View {
  let view: FormsView
  @Bindable var model: PluginsModel
  @Environment(\.openLayout) private var openLayout

  var body: some View {
    let position = LayoutEntries.layout(view.entry.plugin)?["position"]?.stringValue
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.t("layoutEditor.inspector.position"))
      Picker(L10n.t("layoutEditor.inspector.position"), selection: Binding(get: { position ?? "" }, set: { next in
        guard !next.isEmpty else { return }
        Task { await place(next) }
      })) {
        if position == nil { Text(L10n.t("formsEditor.notPlaced")).tag("") }
        ForEach(LayoutEntries.positions, id: \.self) { Text(InstalledTab.positionTitle($0)).tag($0) }
      }
      .labelsHidden()
      if position == nil {
        Text(L10n.t("formsEditor.notPlacedHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else {
        Button(L10n.t("pluginsInstalled.showOnStage")) { openLayout(.component(model.config?.plugins ?? [], view.entry.index)) }
      }
    }
  }

  /// Into the position's list, at its end; an entry without a layout block gets one after the last
  /// entry there.
  private func place(_ position: String) async {
    var index: Int?
    let done = await model.commit { plugins in
      guard let entry = FormsOptions.entries(plugins).first else { return plugins }
      index = entry.index
      if LayoutEntries.layout(plugins[entry.index]) != nil {
        return LayoutEntries.place(plugins, index: entry.index, position: position)
      }
      let others = (LayoutEntries.positionMap(plugins)[position] ?? []).map { LayoutEntries.layout(plugins[$0])?["priority"]?.numberValue ?? 0 }
      var object = plugins[entry.index].object
      object["layout"] = .object(JSONObject([("position", .string(position)), ("priority", .number((others.max() ?? 0) + 10))]))
      var out = plugins
      out[entry.index] = PluginEntry(object: object)
      return out
    }
    if done, let index {
      model.flagSaved(index)
      Announce.post(L10n.t("formsEditor.positionAnnounce", ["position": InstalledTab.positionTitle(position)]))
    }
  }
}
