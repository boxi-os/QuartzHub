import AppKit
import QuartzHubCore
import SwiftUI

/// What the Formulare tab knows besides the config: the plugin's schema, its own verdict on the
/// options (`FormsCLI.check`), and which pages embed which form (`FormUsages`). Shared by the tab
/// and the inspector; the tab asks for them.
@MainActor @Observable final class FormsState {
  var schema: PluginOptionSchemaResult?
  var schemaLoaded = false
  var check: FormsCheckResult?
  var checking = false
  var usages: FormUsages.Result?
  var scanning = false
  var scanError: String?
  /// "Neu suchen": the pages are the user's notes, which change outside QuartzHub; read once per
  /// visit and on request, not per write.
  var scanRound = 0
  /// "In der Vorschau zeigen".
  var goTo: PreviewGoTo?
  /// The relay's state, asked with the check and after every change in its section; only while a
  /// form sends through the relay.
  var relay: RelayState?
  var relayLoading = false
  var relayRound = 0
}

/// What the Formulare tab shows of the plugin's options, in the words of its rows (QuartzControl's
/// `Forms.tsx`: `titleOf`, `subtitle`, `sectionSummary`).
@MainActor struct FormsView {
  let entry: FormsOptions.Entry
  let state: FormsState

  static var lang: String { L10n.language == "en" ? "en" : "de" }

  var schema: NormalizedOptionSchema? { state.schema?.schema }
  var options: JSONObject { entry.plugin.object["options"]?.objectValue ?? JSONObject() }
  var forms: [(id: String, def: JSONObject)] { FormsOptions.forms(options) }
  var ids: [String] { forms.map(\.id) }
  var layoutForm: String { options["layoutForm"]?.stringValue ?? "" }
  var usesRelay: Bool { forms.contains { FormsOptions.transportKind($0.def, options) == "relay" } }
  /// The sections of the global settings; the relay's only while a form sends through it.
  var sections: [(id: String, keys: [String])] { FormsOptions.sections.filter { $0.id != "relay" || usesRelay } }

  func title(_ id: String, _ def: JSONObject) -> String {
    let text = FormsOptions.text(FormsOptions.effectiveForm(def)["title"], Self.lang)
    return text.isEmpty ? id : text
  }

  func pages(_ id: String) -> [FormUsages.Page] { state.usages?.pages.filter { $0.forms.contains(id) } ?? [] }

  func pageNames(_ pages: [FormUsages.Page]) -> String {
    let names = pages.prefix(5).map(\.file).joined(separator: ", ")
    return pages.count > 5 ? L10n.t("formsEditor.andMore", ["list": names, "count": String(pages.count - 5)], count: pages.count - 5) : names
  }

  /// The plugin's messages, each placed at the form, field or section it names.
  var placed: (problems: [FormsOptions.PlacedMessage], hints: [FormsOptions.PlacedMessage]) {
    guard case .checked(let problems, let hints, _)? = state.check else { return ([], []) }
    return (problems.map(FormsOptions.place), hints.map(FormsOptions.place))
  }

  func messages(_ keep: (FormsOptions.PlacedMessage) -> Bool) -> (problems: [FormsOptions.PlacedMessage], hints: [FormsOptions.PlacedMessage]) {
    let all = placed
    return (all.problems.filter(keep), all.hints.filter(keep))
  }

  /// Pages that name a form the options do not have: the build stops on them.
  var unknownUses: [(form: String, file: String)] {
    let ids = ids
    return (state.usages?.pages ?? []).flatMap { page in page.forms.filter { !ids.contains($0) }.map { ($0, page.file) } }
  }

  func subtitle(_ id: String, _ def: JSONObject) -> String {
    let effective = FormsOptions.effectiveForm(def)
    let fields = FormsOptions.fields(effective)
    var parts: [String] = []
    if FormsOptions.usesTemplateFields(def) {
      parts.append(L10n.t("formsEditor.fromTemplate", ["template": Self.templateName(def["template"]?.stringValue ?? "")]))
    } else {
      let steps = FormsOptions.stepCount(fields)
      if steps > 1 { parts.append(L10n.t("formsEditor.stepCount", ["steps": String(steps)])) }
      let count = fields.filter { !FormsOptions.isPageBreak($0) }.count
      parts.append(L10n.t("formsEditor.fieldCount", ["count": String(count)], count: count))
    }
    parts.append(Self.kindLabel(FormsOptions.transportKind(def, options)))
    parts.append(Self.modeLabel(FormsOptions.encryptionMode(def)))
    if state.usages != nil {
      let n = pages(id).count
      if n > 0 { parts.append(L10n.t("formsEditor.onPages", ["count": String(n)], count: n)) } else if layoutForm != id { parts.append(L10n.t("formsEditor.onNoPage")) }
    }
    return parts.joined(separator: " · ")
  }

  func summary(_ section: String) -> String {
    switch section {
    case "transport":
      let transport = FormsOptions.resolvedGlobal(schema, options, key: "transport")
      let url = transport["url"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.t("formsEditor.noUrl")
      let kind = transport["kind"].map { $0.stringValue ?? OptionFormText.inline($0) } ?? "relay"
      return "\(Self.kindLabel(kind)) · \(url)"
    case "keys":
      let names = options["keys"]?.objectValue?.keys ?? []
      return names.isEmpty ? L10n.t("formsEditor.noKeys") : names.joined(separator: ", ")
    case "spam":
      let spam = FormsOptions.resolvedGlobal(schema, options, key: "spam")
      var parts: [String] = []
      if spam["honeypot"] != .bool(false) { parts.append(L10n.t("formsEditor.spamShort.honeypot")) }
      if case .number(let seconds)? = spam["minSeconds"], seconds > 0 {
        parts.append(L10n.t("formsEditor.spamShort.minSeconds", ["seconds": OptionFormText.inline(.number(seconds))]))
      }
      if spam["pow"] == .bool(true) { parts.append(L10n.t("formsEditor.spamShort.pow")) }
      switch spam["captcha"] {
      case nil, .null?, .bool(false)?, .string("")?, .string("none")?, .number(0)?: break
      case let captcha?: parts.append(captcha.stringValue ?? OptionFormText.inline(captcha))
      }
      if case .number(let rate)? = spam["rateLimitPerHour"], rate > 0 {
        parts.append(L10n.t("formsEditor.spamShort.rate", ["perHour": OptionFormText.inline(.number(rate))]))
      }
      return parts.isEmpty ? L10n.t("formsEditor.allOff") : parts.joined(separator: " · ")
    case "layout":
      guard !layoutForm.isEmpty else { return L10n.t("formsEditor.noLayoutForm") }
      let position = LayoutEntries.layout(entry.plugin)?["position"]?.stringValue
      return "\(layoutForm) · \(position.map(InstalledTab.positionTitle) ?? L10n.t("formsEditor.notPlaced"))"
    case "relay":
      guard let relay = state.relay else { return state.relayLoading ? L10n.t("formsEditor.relay.loading") : "" }
      return RelayWords.status(relay, dateOnly: true).text
    case "texts":
      let texts = options["texts"]?.objectValue ?? JSONObject()
      let count = texts.keys.reduce(0) { $0 + (texts[$1]?.objectValue?.count ?? 0) }
      return count > 0 ? L10n.t("formsEditor.ownTexts", ["count": String(count)], count: count) : L10n.t("formsEditor.pluginTexts")
    case "technical":
      let lang = options["codeBlockLang"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "quartz-form"
      let key = options["frontmatterKey"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "form"
      return "\(lang) · \(key)"
    default:
      return ""
    }
  }

  // MARK: Words for the plugin's names

  static func templateName(_ name: String) -> String {
    switch name {
    case "contact": L10n.t("formsEditor.templates.contact")
    case "feedback": L10n.t("formsEditor.templates.feedback")
    case "rsvp": L10n.t("formsEditor.templates.rsvp")
    case "survey": L10n.t("formsEditor.templates.survey")
    case "empty": L10n.t("formsEditor.templates.empty")
    default: name
    }
  }

  static func templateHint(_ name: String) -> String {
    switch name {
    case "contact": L10n.t("formsEditor.templateHints.contact")
    case "feedback": L10n.t("formsEditor.templateHints.feedback")
    case "rsvp": L10n.t("formsEditor.templateHints.rsvp")
    case "survey": L10n.t("formsEditor.templateHints.survey")
    default: L10n.t("formsEditor.templateHints.empty")
    }
  }

  static func templateId(_ name: String) -> String {
    switch name {
    case "contact": L10n.t("formsEditor.templateIds.contact")
    case "feedback": L10n.t("formsEditor.templateIds.feedback")
    case "rsvp": L10n.t("formsEditor.templateIds.rsvp")
    case "survey": L10n.t("formsEditor.templateIds.survey")
    default: L10n.t("formsEditor.templateIds.empty")
    }
  }

  static func templateSymbol(_ name: String) -> String {
    switch name {
    case "contact": "message"
    case "feedback": "hand.thumbsup"
    case "rsvp": "person.crop.circle.badge.checkmark"
    case "survey": "checklist"
    default: "doc"
    }
  }

  static func kindLabel(_ kind: String) -> String {
    switch kind {
    case "relay": L10n.t("formsEditor.transportKinds.relay")
    case "endpoint": L10n.t("formsEditor.transportKinds.endpoint")
    case "formspree": L10n.t("formsEditor.transportKinds.formspree")
    case "web3forms": L10n.t("formsEditor.transportKinds.web3forms")
    case "mailto": L10n.t("formsEditor.transportKinds.mailto")
    case "demo": L10n.t("formsEditor.transportKinds.demo")
    default: kind
    }
  }

  static func modeLabel(_ mode: String) -> String {
    switch mode {
    case "required": L10n.t("formsEditor.encryptionModes.required")
    case "optional": L10n.t("formsEditor.encryptionModes.optional")
    case "off": L10n.t("formsEditor.encryptionModes.off")
    default: mode
    }
  }

  static func sectionTitle(_ id: String) -> String {
    switch id {
    case "transport": L10n.t("formsEditor.sections.transport")
    case "keys": L10n.t("formsEditor.sections.keys")
    case "spam": L10n.t("formsEditor.sections.spam")
    case "layout": L10n.t("formsEditor.sections.layout")
    case "relay": L10n.t("formsEditor.sections.relay")
    case "texts": L10n.t("formsEditor.sections.texts")
    case "technical": L10n.t("formsEditor.sections.technical")
    default: id
    }
  }

  static func sectionHint(_ id: String) -> String {
    switch id {
    case "transport": L10n.t("formsEditor.sectionHints.transport")
    case "keys": L10n.t("formsEditor.sectionHints.keys")
    case "spam": L10n.t("formsEditor.sectionHints.spam")
    case "layout": L10n.t("formsEditor.sectionHints.layout")
    case "relay": L10n.t("formsEditor.sectionHints.relay")
    case "texts": L10n.t("formsEditor.sectionHints.texts")
    case "technical": L10n.t("formsEditor.sectionHints.technical")
    default: ""
    }
  }

  static func sectionSymbol(_ id: String) -> String {
    switch id {
    case "transport": "paperplane"
    case "keys": "key"
    case "spam": "checkmark.shield"
    case "layout": "rectangle.3.group"
    case "relay": "server.rack"
    case "texts": "textformat"
    default: "wrench.and.screwdriver"
    }
  }

  static func idProblem(_ problem: FormsOptions.IdProblem) -> String {
    switch problem {
    case .empty: L10n.t("formsEditor.idProblem.empty")
    case .pattern: L10n.t("formsEditor.idProblem.pattern")
    case .taken: L10n.t("formsEditor.idProblem.taken")
    }
  }

  /// Filled, so it reads on a selected row too.
  static func problemBadge(_ count: Int) -> some View {
    Text(L10n.t("formsEditor.check.problemBadge", ["count": String(count)], count: count))
      .font(.caption2.weight(.semibold)).foregroundStyle(.white)
      .padding(.horizontal, 5).padding(.vertical, 1)
      .background(Capsule().fill(.red))
  }
}

/// Formulare (QuartzControl's `routes/Plugins/Forms.tsx`). Like quartz-multilanguage the plugin is
/// one entry for the whole site, so the list holds its forms (the entries of `options.forms`) and
/// below them the global settings, each a row that opens in the inspector. A form's inspector
/// shows the plugin's own schema for a form in parts; its spam and transport settings lie over
/// the global ones and say so.
///
/// Every change goes through the plugin list's write queue (`PluginsModel.commit`), each against
/// the newest state; the plugin's own check runs a moment after the writes settle.
struct FormsTab: View {
  @Bindable var model: PluginsModel
  let state: FormsState
  /// `form:<id>` or `section:<id>`: an id is stable, a row's place is not.
  @Binding var selection: String?
  let showAllOptions: () -> Void
  @Environment(\.unsavedGuard) private var unsaved
  @State private var adding = false

  var body: some View {
    let entries = FormsOptions.entries(model.config?.plugins ?? [])
    if let error = model.loadError {
      Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
    } else if model.config == nil {
      Text(L10n.t("common.loading")).foregroundStyle(.secondary).padding()
    } else if let entry = entries.first {
      let view = FormsView(entry: entry, state: state)
      VSplitView {
        list(view, count: entries.count)
          .frame(minHeight: 260)
        EditorPreview(project: model.project, prefix: "forms", hint: L10n.t("formsEditor.previewHint"),
                      highlight: highlight(view), goTo: state.goTo)
          .frame(minHeight: 300)
      }
      .toolbar {
        // ➕ in the toolbar (docs/conventions.md, Liste); name and start in a popover.
        ToolbarItem(placement: .primaryAction) {
          Button { adding = true } label: { Label(L10n.t("formsEditor.add"), systemImage: "plus") }
            .help(L10n.t("formsEditor.add"))
            .disabled(model.busy)
            .popover(isPresented: $adding, arrowEdge: .bottom) {
              AddFormForm(ids: view.ids) { id, start in
                adding = false
                Task { await add(id, start: start) }
              } cancel: { adding = false }
            }
            .accessibilityIdentifier("forms.add")
        }
      }
      .task(id: entry.plugin.source.map(JSJSON.compact) ?? "") { await loadSchema(entry) }
      .task(id: JSJSON.compact(.object(entry.plugin.object))) { await check(entry, relay: view.usesRelay) }
      .task(id: state.relayRound) { if state.relayRound > 0, view.usesRelay { await loadRelay(entry) } }
      .task(id: "\(view.options["codeBlockLang"].map(JSJSON.compact) ?? "")|\(view.options["frontmatterKey"].map(JSJSON.compact) ?? "")|\(state.scanRound)") {
        await scan(view)
      }
    } else {
      ContentUnavailableView {
        Label(L10n.t("formsEditor.notInstalledTitle"), systemImage: "list.clipboard")
      } description: {
        Text(L10n.t("formsEditor.notInstalledText"))
      }
      // The whole column: at its text's width, the tab picker above moved to the left.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func list(_ view: FormsView, count: Int) -> some View {
    let forms = view.forms
    let placed = view.placed
    let unknown = view.unknownUses
    // The intro is in the inspector, adding is ➕ in the toolbar.
    return VStack(alignment: .leading, spacing: Spacing.xs) {
      if let installed = state.schema?.packageVersion, installed != FormsOptions.readAgainst {
        Callout(.warning, L10n.t("plugins.readAgainst", ["plugin": FormsOptions.plugin, "read": FormsOptions.readAgainst, "installed": installed]))
      }
      if let message = model.message { Callout(.error) { Text(message).textSelection(.enabled) } }
      if count > 1 { Callout(.warning, L10n.t("formsEditor.severalEntries", ["count": String(count)], count: count)) }
      if !unknown.isEmpty {
        Callout(.warning, L10n.t("formsEditor.unknownUses", ["count": String(unknown.count),
                                                    "list": unknown.prefix(5).map { "\($0.form) (\($0.file))" }.joined(separator: ", ")],
                       count: unknown.count))
      }
      CheckSummary(check: state.check, checking: state.checking, unplaced: placed.problems.filter { $0.form == nil && $0.section == nil })
      if let error = state.scanError { Callout(.warning, L10n.t("formsEditor.scanFailed", ["reason": error])) }
      HStack(spacing: 12) {
        Label(view.entry.plugin.name, systemImage: "puzzlepiece.extension").font(.headline)
        Toggle(L10n.t("formsEditor.enabled"), isOn: Binding(get: { view.entry.plugin.enabled }, set: { on in
          Task {
            await model.toggleEnabled(view.entry.index)
            Announce.post(on ? L10n.t("formsEditor.enabledAnnounce") : L10n.t("formsEditor.disabledAnnounce"))
          }
        }))
        .toggleStyle(.switch)
        .controlSize(.small)
        .help(L10n.t("formsEditor.enabledHint"))
        .accessibilityIdentifier("forms.enabled")
        Spacer()
        Button(L10n.t("formsEditor.allOptions"), action: showAllOptions)
      }
      List(selection: $selection) {
        Section {
          if forms.isEmpty { Note(L10n.t("formsEditor.empty")) }
          ForEach(forms, id: \.id) { form in
            formRow(form.id, form.def, view: view, problems: placed.problems.filter { $0.form == form.id }.count)
          }
        } header: {
          Text(L10n.t("formsEditor.listTitle", ["count": String(forms.count)], count: forms.count))
        }
        Section(L10n.t("formsEditor.sectionsTitle")) {
          if !state.schemaLoaded {
            Note(L10n.t("layoutEditor.inspector.optionsLoading"))
          } else {
            if let reason = state.schema?.unreadable { Callout(.warning, L10n.t("pluginOptions.unreadable", ["reason": reason])) }
            ForEach(view.sections, id: \.id) { section in
              sectionRow(section.id, view: view, problems: placed.problems.filter { $0.section == section.id }.count)
            }
          }
        }
      }
      .accessibilityIdentifier("forms.list")
    }
    .padding(.horizontal, Spacing.page)
    .padding(.top, Spacing.s)
  }

  private func formRow(_ id: String, _ def: JSONObject, view: FormsView, problems: Int) -> some View {
    let name = view.title(id, def)
    return HStack(spacing: 8) {
      Image(systemName: "list.clipboard").foregroundStyle(.secondary).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(name == id ? id : "\(name) (\(id))").fontWeight(.medium)
        Text(view.subtitle(id, def)).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      if problems > 0 { FormsView.problemBadge(problems) }
      if view.layoutForm == id { WordBadge(text: L10n.t("formsEditor.layoutBadge"), tint: .green) }
      if FormsOptions.isAnonymous(def) { WordBadge(text: L10n.t("formsEditor.anonymousBadge")) }
      Button { Task { await duplicate(id) } } label: {
        Label(L10n.t("formsEditor.duplicateNamed", ["name": id]), systemImage: "plus.square.on.square").labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.t("formsEditor.duplicateNamed", ["name": id]))
      .disabled(model.busy)
      Button { Task { await remove(id, def, view: view) } } label: {
        Label(L10n.t("common.removeNamed", ["name": id]), systemImage: "trash").labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.t("common.removeNamed", ["name": id]))
      .disabled(model.busy)
    }
    .padding(.vertical, 2)
    .tag("form:\(id)")
    .contextMenu {
      Button(L10n.t("formsEditor.duplicateNamed", ["name": id])) { Task { await duplicate(id) } }
      Divider()
      Button(L10n.t("common.removeNamed", ["name": id]), role: .destructive) { Task { await remove(id, def, view: view) } }
    }
    .accessibilityIdentifier("forms.form.\(id)")
  }

  private func sectionRow(_ id: String, view: FormsView, problems: Int) -> some View {
    HStack(spacing: 8) {
      Image(systemName: FormsView.sectionSymbol(id)).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(FormsView.sectionTitle(id)).fontWeight(.medium)
        let line = view.summary(id)
        if !line.isEmpty { Text(line).font(.callout).foregroundStyle(.secondary) }
      }
      Spacer()
      if problems > 0 { FormsView.problemBadge(problems) }
    }
    .padding(.vertical, 2)
    .tag("section:\(id)")
    .accessibilityIdentifier("forms.section.\(id)")
  }

  // MARK: Preview

  /// The selected form, on the pages that embed it. An id the plugin would refuse is no selector.
  private func highlight(_ view: FormsView) -> PreviewHighlight? {
    guard let selection, selection.hasPrefix("form:") else { return nil }
    let id = String(selection.dropFirst(5))
    guard FormsOptions.isFormId(id), let form = view.forms.first(where: { $0.id == id }) else { return nil }
    // A page a filter leaves out is no page to go to: the dev server answers 404 there.
    let pages = state.usages.map { _ in view.pages(id).filter { $0.unbuilt == nil }.map { FormUsages.slugPath($0.slug) } }
    return PreviewHighlight(selector: "form.quartz-form[data-form=\"\(id)\"]", name: view.title(id, form.def), matches: 1, ownClass: true,
                            pages: pages)
  }

  // MARK: Asking

  private func loadSchema(_ entry: FormsOptions.Entry) async {
    guard let source = PluginSource(entry.plugin.source) else {
      state.schema = nil
      state.schemaLoaded = true
      return
    }
    let environment = await AppServices.current()
    state.schema = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime)
    state.schemaLoaded = true
  }

  /// The plugin's own verdict, a moment after the writes settle: it runs in a child process.
  private func loadRelay(_ entry: FormsOptions.Entry) async {
    guard let source = PluginSource(entry.plugin.source) else { return }
    state.relayLoading = true
    let relay = await RelayWords.relay(model, source: source)
    let next = await relay.state()
    if Task.isCancelled { return }
    state.relay = next
    state.relayLoading = false
  }

  private func check(_ entry: FormsOptions.Entry, relay usesRelay: Bool) async {
    if state.check != nil {
      try? await Task.sleep(for: .milliseconds(600))
      if Task.isCancelled { return }
    }
    await model.waitForWrites()
    guard let source = PluginSource(entry.plugin.source) else { return }
    state.checking = true
    let environment = await AppServices.current()
    let result = await FormsCLI(project: model.project.path, source: source, environment: environment).check()
    if Task.isCancelled { return }
    state.check = result
    state.checking = false
    // The relay's state needs the plugin too (the hash of what it would write).
    if usesRelay { await loadRelay(entry) } else { state.relay = nil }
  }

  private func scan(_ view: FormsView) async {
    state.scanning = true
    defer { state.scanning = false }
    let environment = await AppServices.current()
    do {
      let result = try await FormUsages.scan(project: model.project.path, codeBlockLang: view.options["codeBlockLang"]?.stringValue ?? "",
                                             frontmatterKey: view.options["frontmatterKey"]?.stringValue ?? "", runtime: environment.runtime)
      if Task.isCancelled { return }
      state.usages = result
      state.scanError = nil
    } catch {
      if Task.isCancelled { return }
      state.scanError = error.message
    }
  }

  // MARK: Writing

  private func add(_ id: String, start: String) async {
    selection = "form:\(id)"
    let label = L10n.t("formsEditor.messageLabel")
    if await FormsTab.update(model, { FormsOptions.withForm($0, id: id, def: FormsOptions.newForm(start, messageLabel: label)) }) {
      Announce.post(L10n.t("formsEditor.addedAnnounce", ["id": id]))
    }
  }

  private func duplicate(_ id: String) async {
    guard let entry = FormsOptions.entries(model.config?.plugins ?? []).first else { return }
    let copy = FormsOptions.duplicate(entry.plugin.object["options"]?.objectValue ?? JSONObject(), id: id).id
    selection = "form:\(copy)"
    if await FormsTab.update(model, { FormsOptions.duplicate($0, id: id).options }) {
      Announce.post(L10n.t("formsEditor.duplicatedAnnounce", ["id": copy]))
    }
  }

  private func remove(_ id: String, _ def: JSONObject, view: FormsView) async {
    let name = view.title(id, def)
    let used = view.pages(id)
    // Three answers, by what the scan knows: pages that embed it, none, or no scan to ask.
    let text = !used.isEmpty
      ? L10n.t("formsEditor.removeConfirmUsed", ["name": name, "id": id, "count": String(used.count), "pages": view.pageNames(used)], count: used.count)
      : state.usages != nil ? L10n.t("formsEditor.removeConfirmUnused", ["name": name]) : L10n.t("formsEditor.removeConfirm", ["name": name, "id": id])
    let (question, detail) = Confirm.split(text)
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("common.remove"), destructive: true, window: unsaved?.window) else { return }
    if selection == "form:\(id)" { selection = nil }
    if await FormsTab.update(model, { FormsOptions.remove($0, id: id) }) {
      Announce.post(L10n.t("formsEditor.removedAnnounce", ["name": name]))
    }
  }

  /// The plugin's options changed against the newest state; no options left removes the key.
  @discardableResult
  static func update(_ model: PluginsModel, _ change: @escaping (JSONObject) -> JSONObject) async -> Bool {
    var index: Int?
    let done = await model.commit { plugins in
      guard let entry = FormsOptions.entries(plugins).first else { return plugins }
      index = entry.index
      var object = entry.plugin.object
      let next = change(object["options"]?.objectValue ?? JSONObject())
      object["options"] = next.isEmpty ? nil : .object(next)
      var out = plugins
      out[entry.index] = PluginEntry(object: object)
      return out
    }
    if done, let index { model.flagSaved(index) }
    return done
  }
}

/// One line above the list: whether the plugin's own check passes, and what it says outside a
/// form or section.
struct CheckSummary: View {
  let check: FormsCheckResult?
  let checking: Bool
  let unplaced: [FormsOptions.PlacedMessage]

  var body: some View {
    switch check {
    case nil:
      if checking { Note(L10n.t("formsEditor.check.checking")) }
    case .unavailable(let reason)?:
      Callout(.warning, L10n.t("formsEditor.check.unavailable", ["reason": reason]))
    case .checked(let problems, _, _)?:
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(problems.isEmpty ? L10n.t("formsEditor.check.summaryOk")
               : L10n.t("formsEditor.check.summaryProblems", ["count": String(problems.count)], count: problems.count))
            .foregroundStyle(problems.isEmpty ? .green : .red)
          if checking { Text(L10n.t("formsEditor.check.checking")).font(.caption).foregroundStyle(.secondary) }
        }
        if !unplaced.isEmpty { FormMessages(problems: unplaced, hints: []) }
      }
    }
  }
}

/// What quartz-forms says about a form or a section: its problems, which stop the build, and its
/// hints, in its own words, with the path the place already names taken off.
struct FormMessages: View {
  let problems: [FormsOptions.PlacedMessage]
  let hints: [FormsOptions.PlacedMessage]

  var body: some View {
    if !problems.isEmpty || !hints.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        if !problems.isEmpty {
          Text(L10n.t("formsEditor.check.problems", ["count": String(problems.count)], count: problems.count))
            .font(.caption.weight(.semibold)).foregroundStyle(.red)
          ForEach(Array(problems.enumerated()), id: \.offset) { _, m in
            Text(verbatim: m.rest.isEmpty ? m.text : m.rest).font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
          }
        }
        if !hints.isEmpty {
          Text(L10n.t("formsEditor.check.hints", ["count": String(hints.count)], count: hints.count))
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          ForEach(Array(hints.enumerated()), id: \.offset) { _, m in
            Text(verbatim: m.rest.isEmpty ? m.text : m.rest).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
          }
        }
      }
    }
  }
}

/// A new form: where it starts (a template or nothing) and its id, which follows the choice
/// until it was typed in.
private struct AddFormForm: View {
  let ids: [String]
  let add: (String, String) -> Void
  let cancel: () -> Void

  @State private var start = "contact"
  @State private var id: String?
  @State private var tried = false
  @FocusState private var focused: Bool

  private var shownId: String { id ?? FormsOptions.freeId(FormsView.templateId(start), existing: ids) }

  var body: some View {
    let problem = FormsOptions.formIdProblem(shownId, existing: ids)
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.t("formsEditor.start")).font(.headline)
      VStack(spacing: 4) {
        ForEach(FormsOptions.templateNames + ["empty"], id: \.self) { name in
          Button { start = name } label: {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: FormsView.templateSymbol(name)).frame(width: 20).foregroundStyle(.tint)
              VStack(alignment: .leading, spacing: 2) {
                Text(FormsView.templateName(name)).fontWeight(.medium)
                Text(FormsView.templateHint(name)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              }
              Spacer()
              if start == name { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .padding(6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(start == name ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear)))
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(start == name ? .isSelected : [])
        }
      }
      Text(L10n.t("formsEditor.id")).font(.callout).foregroundStyle(.secondary)
      // Only a changed text counts as typed: the field hands its value back when it takes focus.
      TextField(L10n.t("formsEditor.id"), text: Binding(get: { shownId }, set: { next in
        let typed = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed != shownId { id = typed }
      }))
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .focused($focused)
        .onSubmit(submit)
      Text(L10n.t("formsEditor.idHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if tried, let problem { FieldProblem(FormsView.idProblem(problem)) }
      HStack {
        Spacer()
        Button(L10n.t("common.cancel"), action: cancel).keyboardShortcut(.cancelAction)
        Button(L10n.t("formsEditor.addSubmit"), action: submit).keyboardShortcut(.defaultAction)
      }
    }
    // The popover hangs off a list's section header, whose one-line limit it would inherit: the
    // hint was cut at "Ziffern…".
    .lineLimit(nil)
    .padding(12)
    .frame(width: 360)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear { focused = true }
  }

  private func submit() {
    tried = true
    if FormsOptions.formIdProblem(shownId, existing: ids) == nil { add(shownId, start) }
  }
}
