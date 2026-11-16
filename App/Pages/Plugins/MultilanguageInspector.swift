import QuartzHubCore
import SwiftUI

/// One language in the inspector (QuartzControl's `LanguagePanel`), in steps
/// (docs/plan-assistenten.md, `MultilanguageOptions.languageSteps`): its code, which renames it
/// everywhere the options name it, and its names; home page and flag; default, published and its
/// place in the list; a summary. One snapshot per setup, as in the other editors.
struct LanguageInspector: View {
  let language: MultilanguageOptions.Language
  let view: MultilanguageView
  @Bindable var model: PluginsModel
  @Binding var selection: String?
  /// The language ➕ just added, while its first run lasts.
  @Binding var setup: SetupRun?
  @Environment(\.unsavedGuard) private var unsaved

  /// "<code>:<step>": where this window was, by the language's code.
  @SceneStorage("multilanguage.step") private var stored = ""
  @State private var codeDraft: String?
  @State private var snapshot = SnapshotOnce()

  /// The fields of a language, in the order of the plugin's schema.
  private static let fields = ["label", "native", "locale"]
  private static let advanced = ["home", "flag"]

  private var languages: [MultilanguageOptions.Language] { view.languages }
  private var position: Int { languages.firstIndex { $0.code == language.code } ?? 0 }
  private var isDefault: Bool { language.code == view.defaultCode }
  private var published: Bool { MultilanguageOptions.isPublished(language.code, view.published) }
  private var onlyPublished: Bool {
    published && languages.filter { MultilanguageOptions.isPublished($0.code, view.published) }.count == 1
  }
  private var firstRun: Bool { setup?.key == language.code }

  private var current: Binding<String> {
    Binding(get: {
      guard let split = stored.lastIndex(of: ":"), stored[..<split] == language.code else { return "name" }
      return String(stored[stored.index(after: split)...])
    }, set: { step in
      stored = "\(language.code):\(step)"
      if firstRun { setup?.visited.insert(step) }
    })
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
    let steps = MultilanguageOptions.languageSteps.map { InspectorStep(id: $0.id, title: Self.title($0.id)) }
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
      InspectorSteps(steps: steps, current: current, firstRun: firstRun, visited: setup?.visited ?? [], finish: finish,
                     cancel: { Task { await cancel() } }) { step in
        Section { Note(Self.hint(step.id)) }
        stepContent(step.id)
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
    .onAppear {
      if firstRun { setup?.visited.insert(current.wrappedValue) }
    }
  }

  @ViewBuilder private func stepContent(_ id: String) -> some View {
    switch id {
    case "name":
      let problem = codeDraft.flatMap { MultilanguageOptions.codeProblem($0, languages, own: language.code) }
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
        if let problem { FieldProblem(MultilanguageTab.problemText(problem)) }
        ForEach(Self.fields, id: \.self) { textField($0) }
      }
    case "home":
      Section { ForEach(Self.advanced, id: \.self) { textField($0) } }
    case "publish":
      Section {
        Toggle(L10n.t("multilanguageEditor.isDefault"), isOn: Binding(get: { isDefault }, set: { on in if on { Task { await makeDefault() } } }))
          .disabled(isDefault)
          .accessibilityIdentifier("multilanguage.inspector.default")
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
          Spacer()
          Text(L10n.t("multilanguageEditor.positionOf", ["n": String(position + 1), "count": String(languages.count)]))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    default:
      Section {
        LabeledContent("code", value: language.code)
        ForEach(Self.fields + Self.advanced, id: \.self) { key in
          if let value = language[key], !value.isEmpty { LabeledContent(key, value: value) }
        }
        LabeledContent(L10n.t("multilanguageEditor.isDefault"), value: isDefault ? L10n.t("multilanguageEditor.on") : L10n.t("multilanguageEditor.off"))
        LabeledContent(L10n.t("multilanguageEditor.publish"), value: published ? L10n.t("multilanguageEditor.on") : L10n.t("multilanguageEditor.off"))
      }
    }
  }

  static func title(_ id: String) -> String {
    switch id {
    case "name": L10n.t("multilanguageEditor.steps.name")
    case "home": L10n.t("multilanguageEditor.steps.home")
    case "publish": L10n.t("multilanguageEditor.steps.publish")
    case "finish": L10n.t("multilanguageEditor.steps.finish")
    default: id
    }
  }

  static func hint(_ id: String) -> String {
    switch id {
    case "name": L10n.t("multilanguageEditor.steps.nameHint")
    case "home": L10n.t("multilanguageEditor.steps.homeHint")
    case "publish": L10n.t("multilanguageEditor.steps.publishHint")
    case "finish": L10n.t("multilanguageEditor.steps.finishHint")
    default: ""
    }
  }

  /// One snapshot per setup: ➕ took it for a new language; an existing one takes it with the first
  /// write after the inspector opened.
  private func policy() -> PluginsModel.SnapshotPolicy {
    model.once(&snapshot, firstRun: firstRun)
  }

  private func finish() {
    setup = nil
    snapshot.taken(failures: model.failures)
    Announce.post(L10n.t("multilanguageEditor.steps.doneAnnounce", ["name": MultilanguageView.name(language)]))
  }

  /// Takes the new language out again, after asking; the safe answer first. The plugin's options
  /// get back the default and the published languages from before ➕, where they still name
  /// languages of the site (`MultilanguageOptions.cancelSetup`).
  private func cancel() async {
    let (question, detail) = Confirm.split(L10n.t("multilanguageEditor.steps.cancelQuestion"))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("multilanguageEditor.steps.cancelRemove"), destructive: true,
                            cancel: L10n.t("inspectorSteps.cancelKeep"), window: unsaved?.window) else { return }
    let code = language.code
    let before = (setup?.before).flatMap { MultilanguageOptions.entries($0).first?.plugin.object["options"]?.objectValue }
    setup = nil
    selection = nil
    if await MultilanguageTab.update(model, snapshot: .none, { MultilanguageOptions.cancelSetup($0, code: code, before: before) }) {
      Announce.post(L10n.t("multilanguageEditor.steps.cancelledAnnounce"))
    }
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
    await MultilanguageTab.update(model, snapshot: policy(), change)
  }

  private func set(_ key: String, _ value: JSONValue?) async {
    let code = language.code
    _ = await update { options in
      MultilanguageOptions.withLanguages(options, MultilanguageOptions.languages(options).map { $0.code == code ? $0.with(key, value) : $0 })
    }
  }

  private func rename(_ to: String) async {
    let from = language.code
    // Asked first: with the run renamed, `firstRun` is false until the file has the new code.
    let rule = policy()
    selection = "lang:\(to)"
    // The first run, with its check marks, and "where was I" follow the language to its new code.
    if firstRun, let run = setup { setup = run.renamed(to) }
    if let split = stored.lastIndex(of: ":"), stored[..<split] == from { stored = "\(to):\(stored[stored.index(after: split)...])" }
    if await MultilanguageTab.update(model, snapshot: rule, { MultilanguageOptions.rename($0, MultilanguageOptions.languages($0), from: from, to: to) }) {
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
  @Environment(\.openLayout) private var openLayout

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
            Button(L10n.t("pluginsInstalled.showOnStage")) { openLayout(.component(model.config?.plugins ?? [], view.entry.index)) }
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

/// Nothing selected: the languages in one look; with fewer than two, the way into the setup.
struct MultilanguageOverview: View {
  let view: MultilanguageView
  var start: (() -> Void)?
  /// "Wähle eine Sprache …": not in the setup's summary, where nothing is to be chosen.
  var asksToChoose = true

  var body: some View {
    let languages = view.languages
    let published = view.published
    Section(L10n.t("multilanguageEditor.panelEmptyTitle")) {
      if asksToChoose { Note(L10n.t("multilanguageEditor.panelEmptyText")) }
      LabeledContent(L10n.t("multilanguageEditor.summaryLanguages"), value: languages.map(MultilanguageView.name).joined(separator: ", "))
      LabeledContent(L10n.t("multilanguageEditor.summaryDefault"),
                     value: languages.first { $0.code == view.defaultCode }.map(MultilanguageView.name) ?? "")
      LabeledContent(L10n.t("multilanguageEditor.summaryPublished"),
                     value: published.isEmpty ? L10n.t("multilanguageEditor.publishedAll")
                       : languages.filter { published.contains($0.code) }.map(MultilanguageView.name).joined(separator: ", "))
      LabeledContent(L10n.t("multilanguageEditor.summaryDetection"), value: view.detectionList())
    }
    if let start, languages.count < 2 {
      Section {
        Button(L10n.t("multilanguageEditor.site.start"), action: start)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("multilanguage.site.start")
        Note(L10n.t("multilanguageEditor.site.startHint"))
      }
    }
  }
}

/// Mehrsprachigkeit einrichten (docs/plan-assistenten.md, `MultilanguageOptions.siteSteps`): the
/// site's languages, default and published, how a page finds its language, where the switcher
/// stands. Started from the overview while the site has fewer than two languages; it stays the
/// selection (`setup:site`) until „Fertig“, so the second language does not end it halfway.
/// One snapshot for the whole setup, with its first write.
struct SiteLanguageSetup: View {
  let view: MultilanguageView
  @Bindable var model: PluginsModel
  @Binding var selection: String?
  @SceneStorage("multilanguage.siteStep") private var step = "languages"
  @State private var visited: Set<String> = ["languages"]
  @State private var snapshot = SnapshotOnce()
  @State private var code = ""
  @State private var tried = false

  private var fields: [OptionField] { view.schema?.fields ?? [] }

  var body: some View {
    let steps = MultilanguageOptions.siteSteps.map { InspectorStep(id: $0.id, title: Self.title($0.id)) }
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(L10n.t("multilanguageEditor.site.title"), systemImage: "globe").font(.headline)
            .accessibilityIdentifier("multilanguage.site.title")
          if model.savedIndex == view.entry.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          Note(L10n.t("plugins.savesImmediately"))
        }
      }
      InspectorSteps(steps: steps, current: Binding(get: { step }, set: { step = $0; visited.insert($0) }), firstRun: true,
                     visited: visited, finish: finish) { item in
        Section { Note(Self.hint(item.id)) }
        content(item.id)
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
    .onAppear { visited.insert(step) }
    // Left from the summary (a button under „Weitere Bereiche“, the list) the setup is done, as
    // with „Fertig“: the next one starts with the languages, not in the summary (review
    // 2026-11-16, nebenbei 4).
    .onDisappear { if step == "finish" { step = "languages" } }
  }

  @ViewBuilder private func content(_ id: String) -> some View {
    let languages = view.languages
    switch id {
    case "languages":
      Section {
        ForEach(languages, id: \.code) { language in
          LabeledContent(MultilanguageView.name(language), value: language.code)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.t("multilanguageEditor.site.addCode"))
          HStack {
            TextField(L10n.t("multilanguageEditor.site.addCode"), text: $code, prompt: Text(verbatim: "fr"))
              .textFieldStyle(.roundedBorder)
              .labelsHidden()
              .onSubmit { Task { await add() } }
              .accessibilityIdentifier("multilanguage.site.code")
            Button(L10n.t("multilanguageEditor.addSubmit")) { Task { await add() } }
              .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        if tried, let problem = MultilanguageOptions.codeProblem(code, languages) { FieldProblem(MultilanguageTab.problemText(problem)) }
        Note(L10n.t("multilanguageEditor.addHint"))
      }
    case "publish":
      Section {
        Picker(L10n.t("multilanguageEditor.isDefault"), selection: Binding(get: { view.defaultCode }, set: { next in
          Task { await set { options in
            var out = options
            out["defaultLanguage"] = .string(next)
            return out
          } }
        })) {
          ForEach(languages, id: \.code) { Text(MultilanguageView.name($0)).tag($0.code) }
        }
        Note(L10n.t("multilanguageEditor.isDefaultHint"))
      }
      Section(L10n.t("multilanguageEditor.publish")) {
        let publishedCount = languages.filter { MultilanguageOptions.isPublished($0.code, view.published) }.count
        ForEach(languages, id: \.code) { language in
          let on = MultilanguageOptions.isPublished(language.code, view.published)
          Toggle(MultilanguageView.name(language), isOn: Binding(get: { on }, set: { next in
            let code = language.code
            Task { await set { MultilanguageOptions.withPublished($0, MultilanguageOptions.languages($0), code: code, on: next) } }
          }))
          .disabled(on && publishedCount == 1)
        }
        Note(L10n.t("multilanguageEditor.publishHint"))
      }
    case "detection":
      let assigned = SetupSteps.assign(MultilanguageOptions.siteSteps, fields: fields)
      OptionsForm(schema: view.schema, values: view.options, onChange: { next in Task { await set { _ in next ?? JSONObject() } } },
                  explicitEmpty: true, languages: languages.map(\.code), pick: { assigned[$0] == "detection" }, freeKeys: false,
                  root: OptionRoot(flat: true), projectPath: model.project.path, searchable: false)
    case "switcher":
      PlacementStep(index: view.entry.index, name: L10n.t("multilanguageEditor.site.switcherName"), model: model) { mutate in
        await model.commit(snapshot: policy(), mutate)
      }
      if let switcher = fields.first(where: { $0.key == "switcher" }), case .object(let inner, _) = switcher.node, let schema = view.schema {
        OptionsForm(schema: NormalizedOptionSchema(source: schema.source, fields: inner, notes: []),
                    values: view.options["switcher"]?.objectValue ?? JSONObject(),
                    onChange: { next in Task { await set { options in
                      var out = options
                      out["switcher"] = next.map(JSONValue.object)
                      return out
                    } } },
                    explicitEmpty: true, languages: languages.map(\.code), freeKeys: false,
                    root: OptionRoot(flat: true, keyPrefix: "switcher."), projectPath: model.project.path, searchable: false)
      }
    default:
      MultilanguageOverview(view: view, asksToChoose: false)
      let assigned = SetupSteps.assign(MultilanguageOptions.siteSteps, fields: fields)
      let rest = view.groups.filter { group in !group.keys.isEmpty && group.keys.allSatisfy { assigned[$0] == "finish" } }
      if !rest.isEmpty {
        Section(L10n.t("multilanguageEditor.site.moreGroups")) {
          ForEach(rest, id: \.id) { group in
            Button(view.title(group)) { selection = "section:\(group.id)" }
          }
        }
      }
    }
  }

  static func title(_ id: String) -> String {
    switch id {
    case "languages": L10n.t("multilanguageEditor.site.languages")
    case "publish": L10n.t("multilanguageEditor.site.publish")
    case "detection": L10n.t("multilanguageEditor.site.detection")
    case "switcher": L10n.t("multilanguageEditor.site.switcher")
    case "finish": L10n.t("multilanguageEditor.site.finish")
    default: id
    }
  }

  static func hint(_ id: String) -> String {
    switch id {
    case "languages": L10n.t("multilanguageEditor.site.languagesHint")
    case "publish": L10n.t("multilanguageEditor.site.publishHint")
    case "detection": L10n.t("multilanguageEditor.site.detectionHint")
    case "switcher": L10n.t("multilanguageEditor.site.switcherHint")
    case "finish": L10n.t("multilanguageEditor.site.finishHint")
    default: ""
    }
  }

  // MARK: Writing

  /// One snapshot for the whole setup, named after it, with the first write.
  private func policy() -> PluginsModel.SnapshotPolicy {
    model.once(&snapshot, labeled: L10n.t("multilanguageEditor.site.snapshotLabel"))
  }

  private func set(_ change: @escaping (JSONObject) -> JSONObject) async {
    if await MultilanguageTab.update(model, snapshot: policy(), change) { model.flagSaved(view.entry.index, announce: false) }
  }

  private func add() async {
    tried = true
    guard MultilanguageOptions.codeProblem(code, view.languages) == nil else { return }
    let c = MultilanguageOptions.normalizeCode(code)
    await set { MultilanguageOptions.withLanguages($0, MultilanguageOptions.languages($0) + [MultilanguageOptions.Language(code: c)]) }
    code = ""
    tried = false
    Announce.post(L10n.t("multilanguageEditor.addedAnnounce", ["code": c]))
  }

  private func finish() {
    step = "languages"
    selection = nil
    Announce.post(L10n.t("multilanguageEditor.site.doneAnnounce"))
  }
}
