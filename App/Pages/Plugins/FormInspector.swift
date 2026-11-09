import AppKit
import QuartzHubCore
import SwiftUI

/// One form in the inspector (QuartzControl's `FormPanel`): its id, which renames it, and its
/// settings in parts that fold. The plugin's problems with a part stand on its title, so a folded
/// part does not hide them; all of them stand above the parts as well.
///
/// A value the template already gives is not written: written again, it would stay when the
/// template changes. Every write goes against the newest state of the form.
struct FormInspector: View {
  let id: String
  let def: JSONObject
  let view: FormsView
  @Bindable var model: PluginsModel
  let state: FormsState
  @Binding var selection: String?
  @Environment(\.unsavedGuard) private var unsaved

  /// Which parts stand open, for every form, as `general=1;fields=0`. General and fields start open.
  @SceneStorage("forms.parts") private var openParts = ""
  @State private var idDraft: String?
  /// A rename that was not done puts the id back in its field.
  @State private var idReset = 0
  @State private var copied: String?

  private var lang: String { FormsView.lang }
  private var options: JSONObject { view.options }
  private var templateName: String? { def["template"]?.stringValue.flatMap { FormsOptions.isTemplate(.string($0)) ? $0 : nil } }
  private var template: JSONObject? { templateName.flatMap { FormsOptions.templates[$0] } }
  private var effective: JSONObject { FormsOptions.effectiveForm(def) }
  private var languages: [String] { model.config?.siteLanguages ?? [] }
  private var formSchema: NormalizedOptionSchema? { FormsOptions.formSchema(view.schema) }

  var body: some View {
    let messages = view.messages { $0.form == id }
    let problem = idDraft.flatMap { FormsOptions.formIdProblem($0, existing: view.ids, own: id) }
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(view.title(id, def), systemImage: "list.clipboard").font(.headline).accessibilityIdentifier("forms.inspector.title")
          if model.savedIndex == view.entry.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          Note(L10n.t("plugins.savesImmediately"))
          // A change saved here reaches the server with the next upload of the relay, which only
          // the list row and the Relay section said, both out of sight.
          if FormsOptions.transportKind(def, options) == "relay", let relay = state.relay, RelayWords.outdated(relay) {
            HStack {
              WordBadge(text: L10n.t("formsEditor.relay.panelChanged")).foregroundStyle(.orange)
              Button { selection = "section:relay" } label: { Label(L10n.t("formsEditor.sections.relay"), systemImage: "server.rack") }
            }
          }
        }
      }
      Section {
        row(L10n.t("formsEditor.id"), hint: L10n.t("formsEditor.idRenameHint")) {
          CommitField(name: L10n.t("formsEditor.id"), text: id) { raw in
            let to = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            idDraft = nil
            if to == id { return true }
            if FormsOptions.formIdProblem(to, existing: view.ids, own: id) != nil {
              idDraft = to
              return false
            }
            Task { await rename(to) }
            return true
          }
          .id(idReset)
          .accessibilityIdentifier("forms.inspector.id")
        }
        if let problem { ErrorLine(FormsView.idProblem(problem)) }
        FormMessages(problems: messages.problems, hints: messages.hints)
      }
      part(.general, L10n.t("formsEditor.parts.general"), "slider.horizontal.3", messages.problems) { general }
      part(.fields, L10n.t("formsEditor.parts.fields"), "list.bullet.rectangle", messages.problems) { fields }
      part(.sending, L10n.t("formsEditor.parts.sending"), "paperplane", messages.problems) { sending }
      part(.privacy, L10n.t("formsEditor.parts.privacy"), "lock", messages.problems) { privacy }
      part(.spam, L10n.t("formsEditor.parts.spam"), "checkmark.shield", messages.problems) { spam }
      part(.embed, L10n.t("formsEditor.parts.embed"), "chevron.left.forwardslash.chevron.right", messages.problems) { embed }
      if hasUnknown {
        part(.more, L10n.t("pluginOptions.moreKeys"), "wrench.and.screwdriver", messages.problems) { more }
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
  }

  // MARK: Parts

  private func isOpen(_ part: FormsOptions.Part) -> Bool {
    for item in openParts.split(separator: ";") {
      let pair = item.split(separator: "=")
      if pair.count == 2, pair[0] == part.rawValue { return pair[1] == "1" }
    }
    return part == .general || part == .fields
  }

  private func setOpen(_ part: FormsOptions.Part, _ open: Bool) {
    var items = openParts.split(separator: ";").map(String.init).filter { !$0.hasPrefix("\(part.rawValue)=") }
    items.append("\(part.rawValue)=\(open ? 1 : 0)")
    openParts = items.joined(separator: ";")
  }

  private func part<Content: View>(_ part: FormsOptions.Part, _ title: String, _ symbol: String, _ problems: [FormsOptions.PlacedMessage],
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
    let count = problems.filter { FormsOptions.part($0) == part }.count
    return Section {
      DisclosureGroup(isExpanded: Binding(get: { isOpen(part) }, set: { setOpen(part, $0) })) {
        VStack(alignment: .leading, spacing: 14) { content() }
          .padding(.top, 6)
      } label: {
        HStack {
          Label(title, systemImage: symbol).fontWeight(.medium)
          Spacer()
          if count > 0 { FormsView.problemBadge(count) }
        }
      }
      .accessibilityIdentifier("forms.part.\(part.rawValue)")
    }
  }

  @ViewBuilder private var general: some View {
    let ownFields = def["fields"]?.arrayValue != nil
    row(L10n.t("formsEditor.template"),
        hint: ownFields && template != nil ? L10n.t("formsEditor.templateOwnFieldsHint") : L10n.t("formsEditor.templateHint")) {
      Picker(L10n.t("formsEditor.template"), selection: Binding(get: { templateName ?? "" }, set: { name in Task { await setTemplate(name) } })) {
        Text(L10n.t("formsEditor.noTemplate")).tag("")
        ForEach(FormsOptions.templateNames, id: \.self) { Text(FormsView.templateName($0)).tag($0) }
      }
      .labelsHidden()
    }
    FormTextField(label: L10n.t("formsEditor.title"), value: def["title"], fallback: template?["title"], languages: languages) { v in
      Task { await setKey("title", v) }
    }
    FormTextField(label: L10n.t("formsEditor.description"), hint: L10n.t("formsEditor.descriptionHint"), value: def["description"],
                  languages: languages, multiline: true) { v in Task { await setKey("description", v) } }
    FormTextField(label: L10n.t("formsEditor.submitLabel"), hint: L10n.t("formsEditor.submitLabelHint"), value: def["submitLabel"],
                  languages: languages) { v in Task { await setKey("submitLabel", v) } }
    let success = def["success"]?.objectValue ?? JSONObject()
    let mode = success["mode"] == .string("redirect") ? "redirect" : "inline"
    row(L10n.t("formsEditor.afterSending"), hint: nil) {
      Picker(L10n.t("formsEditor.afterSending"), selection: Binding(get: { mode }, set: { m in Task { await setSuccess(["mode": .string(m)]) } })) {
        Text(L10n.t("formsEditor.successModes.inline")).tag("inline")
        Text(L10n.t("formsEditor.successModes.redirect")).tag("redirect")
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    if mode == "inline" {
      FormTextField(label: L10n.t("formsEditor.successText"), hint: L10n.t("formsEditor.successTextHint"), value: success["text"],
                    languages: languages) { v in Task { await setSuccess(["text": v]) } }
    } else {
      SlugField(value: success["slug"]?.stringValue ?? "", slugs: state.usages?.slugs ?? []) { v in
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await setSuccess(["slug": trimmed.isEmpty ? nil : .string(trimmed)]) }
      }
    }
    Text(L10n.t("pluginOptions.rarelyUsed")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    row("className", hint: L10n.t("formsEditor.classNameHint"), key: true) {
      CommitField(name: "className", text: def["className"]?.stringValue ?? "", monospaced: true) { raw in
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await setKey("className", v.isEmpty ? nil : .string(v)) }
        return true
      }
    }
  }

  @ViewBuilder private var fields: some View {
    let installed = state.schema?.packageVersion
    FormFieldsEditor(def: def, fields: FormsOptions.fields(def), schema: formSchema, languages: languages,
                     anonymous: effective["anonymous"] == .bool(true),
                     fieldMessages: view.messages { $0.form == id }.problems.filter { $0.field != nil },
                     olderPlugin: installed.flatMap { SemVer.isNewer(FormsOptions.layoutSince, than: $0) ? $0 : nil },
                     projectPath: model.project.path) { next in
      Task { await setKey("fields", .array(next.map(JSONValue.object))) }
    }
    if let templateName, def["fields"]?.arrayValue != nil {
      Button(L10n.t("formsEditor.templateFieldsBack", ["template": FormsView.templateName(templateName)])) {
        Task { await takeTemplateFields() }
      }
    }
  }

  @ViewBuilder private var sending: some View {
    let kind = FormsOptions.transportKind(def, options)
    Note(L10n.t("formsEditor.sendsVia", ["kind": FormsView.kindLabel(kind)]))
    let role = kind == "relay" || kind == "mailto" || kind == "demo" ? kind : "none"
    if role == "relay" {
      let others = view.forms.filter { $0.id != id && FormsOptions.transportKind($0.def, options) == "relay" }
        .compactMap { $0.def["recipient"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      RelayRecipientField(value: def["recipient"]?.stringValue ?? "", names: others + (state.relay?.secrets.recipients ?? []),
                          stored: state.relay?.secrets.recipients, storageAvailable: state.relay?.secrets.storageAvailable ?? true,
                          pick: { name in Task { await setKey("recipient", name.map(JSONValue.string)) } },
                          saveAddress: { name, address in
                            try AppDeploy.connections().saveRelaySecrets(model.project.id, RelaySecretsChange(recipients: JSONObject([(name, .string(address))])))
                            Announce.post(L10n.t("formsEditor.relay.addressSetAnnounce", ["name": name]))
                            state.relayRound += 1
                          })
    } else {
      row(Self.recipientLabel(role), hint: Self.recipientHint(role), muted: role == "none" || role == "demo") {
        CommitField(name: Self.recipientLabel(role), text: def["recipient"]?.stringValue ?? "",
                    placeholder: role == "mailto" ? "name@example.org" : nil) { raw in
          let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
          Task { await setKey("recipient", v.isEmpty ? nil : .string(v)) }
          return true
        }
      }
    }
    FormTextField(label: L10n.t("formsEditor.subject"), hint: L10n.t("formsEditor.subjectHint"), value: def["subject"],
                  fallback: effective["title"], languages: languages) { v in Task { await setKey("subject", v) } }
    InheritedBlock(title: L10n.t("formsEditor.ownTransport"), hint: L10n.t("formsEditor.ownTransportHint"),
                   schema: FormsOptions.objectSchema(view.schema, key: "transport"),
                   above: FormsOptions.resolvedGlobal(view.schema, options, key: "transport"),
                   values: def["transport"]?.objectValue ?? JSONObject(), languages: languages, projectPath: model.project.path) { next in
      Task { await setKey("transport", next.map(JSONValue.object)) }
    }
  }

  @ViewBuilder private var privacy: some View {
    let encryption = def["encryption"]?.objectValue ?? JSONObject()
    let mode = FormsOptions.encryptionMode(def)
    let keyNames = options["keys"]?.objectValue?.keys ?? []
    let chosen = encryption["keys"]?.arrayValue.map { $0.compactMap(\.stringValue) } ?? keyNames
    row(L10n.t("formsEditor.encryption"), hint: Self.encryptionHint(mode)) {
      Picker(L10n.t("formsEditor.encryption"), selection: Binding(get: { mode }, set: { m in Task { await setEncryption(["mode": .string(m)]) } })) {
        Text(L10n.t("formsEditor.encryptionChoices.off")).tag("off")
        Text(L10n.t("formsEditor.encryptionChoices.optional")).tag("optional")
        Text(L10n.t("formsEditor.encryptionChoices.required")).tag("required")
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    if mode != "off" {
      if keyNames.isEmpty {
        HStack {
          Warning(L10n.t("formsEditor.noKeysYet"))
          Button { selection = "section:keys" } label: { Label(L10n.t("formsEditor.sections.keys"), systemImage: "key") }
        }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.t("formsEditor.encryptTo")).foregroundStyle(.secondary)
          ForEach(keyNames, id: \.self) { name in
            Toggle(name, isOn: Binding(get: { chosen.contains(name) }, set: { on in
              var next = chosen.filter { $0 != name }
              if on { next = chosen.contains(name) ? chosen : chosen + [name] }
              // Every key: the list goes, and a key added later is used too. None: the build
              // stops ("no keys to encrypt to"), so the last one stays.
              guard !next.isEmpty else { return }
              let all = keyNames.allSatisfy(next.contains)
              Task { await setEncryption(["keys": all ? nil : .array(next.map(JSONValue.string))]) }
            }))
          }
          Text(L10n.t("formsEditor.encryptToHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      toggle(L10n.t("formsEditor.showFingerprint"), hint: L10n.t("formsEditor.showFingerprintHint"), on: encryption["showFingerprint"] != .bool(false)) { on in
        Task { await setEncryption(["showFingerprint": on ? nil : .bool(false)]) }
      }
    }
    let anonymous = effective["anonymous"] == .bool(true)
    toggle(L10n.t("formsEditor.anonymous"), hint: L10n.t("formsEditor.anonymousHint"), on: anonymous) { on in
      Task { await setKey("anonymous", on == (template?["anonymous"] == .bool(true)) ? nil : .bool(on)) }
    }
    VStack(alignment: .leading, spacing: 4) {
      toggle(L10n.t("formsEditor.pageContext"), hint: anonymous ? nil : L10n.t("formsEditor.pageContextHint"),
             on: effective["pageContext"] == .bool(true)) { on in
        Task { await setKey("pageContext", on == (template?["pageContext"] == .bool(true)) ? nil : .bool(on)) }
      }
      if anonymous {
        HStack(spacing: 6) {
          WordBadge(text: L10n.t("pluginOptions.noEffect"))
          Text(L10n.t("formsEditor.pageContextAnonymous")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  @ViewBuilder private var spam: some View {
    InheritedBlock(hint: L10n.t("formsEditor.ownSpamHint"), schema: FormsOptions.objectSchema(view.schema, key: "spam"),
                   above: FormsOptions.resolvedGlobal(view.schema, options, key: "spam"),
                   values: def["spam"]?.objectValue ?? JSONObject(), languages: languages, projectPath: model.project.path) { next in
      Task { await setKey("spam", next.map(JSONValue.object)) }
    }
  }

  @ViewBuilder private var embed: some View {
    let snippets = FormsOptions.embed(id, options)
    Note(L10n.t("formsEditor.embedHint"))
    ForEach([("placeholder", snippets.placeholder), ("codeBlock", snippets.codeBlock), ("frontmatter", snippets.frontmatter)], id: \.0) { kind, text in
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(Self.embedKind(kind)).font(.callout).foregroundStyle(.secondary)
          Spacer()
          Button { copy(text, kind: kind) } label: { Label(L10n.t("formsEditor.copy"), systemImage: "doc.on.doc") }
            .help("\(L10n.t("formsEditor.copy")): \(Self.embedKind(kind))")
        }
        Text(verbatim: text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(6)
          .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
      }
    }
    if copied != nil { Text(L10n.t("formsEditor.copied")).font(.caption).foregroundStyle(.green) }
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.t("formsEditor.usedOn")).font(.callout).foregroundStyle(.secondary)
        Spacer()
        Button(L10n.t("formsEditor.rescan")) { state.scanRound += 1 }.disabled(state.scanning)
      }
      if state.usages == nil {
        Note(L10n.t("formsEditor.scanning"))
      } else {
        let pages = view.pages(id)
        if pages.isEmpty {
          Note(view.layoutForm == id ? L10n.t("formsEditor.onNoPageLayout") : L10n.t("formsEditor.onNoPageHint"))
        }
        ForEach(pages, id: \.file) { page in
          HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
              Text(page.title ?? page.file).lineLimit(1).truncationMode(.middle)
              if page.title != nil { Text(page.file).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            .help(page.file)
            Spacer()
            if let unbuilt = page.unbuilt {
              Text(unbuilt == .draft ? L10n.t("formsEditor.unbuilt.draft") : L10n.t("formsEditor.unbuilt.unpublished"))
                .font(.caption).foregroundStyle(.secondary)
            } else {
              Button(L10n.t("formsEditor.showInPreview")) { state.goTo = PreviewGoTo(page: FormUsages.slugPath(page.slug)) }
            }
          }
        }
      }
      Text(L10n.t("formsEditor.usedOnHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    toggle(L10n.t("formsEditor.useAsLayoutForm"), hint: L10n.t("formsEditor.useAsLayoutFormHint"), on: view.layoutForm == id) { on in
      Task { await setLayoutForm(on) }
    }
  }

  @ViewBuilder private var more: some View {
    let all = OptionSchema.withPresentKeys(formSchema ?? .empty, .object(def)).fields.filter { !FormsOptions.formKeys.contains($0.key) }
    ObjectBlock(fields: all, values: def, onValue: { next in
      let keys = Set(all.map(\.key))
      Task { await change { current in
        var out = current
        for key in keys { out[key] = next[key] }
        return out
      } }
    }, context: context(), root: OptionRoot(flat: true))
  }

  private var hasUnknown: Bool {
    def.keys.contains { !FormsOptions.formKeys.contains($0) } || (formSchema?.fields.contains { !FormsOptions.formKeys.contains($0.key) } ?? false)
  }

  // MARK: Pieces

  private func context() -> OptionsFormContext {
    OptionsFormContext(language: L10n.language == "en" ? .en : .de, explicitEmpty: true, languages: languages, query: "", mark: "",
                       projectPath: model.project.path)
  }

  private func row<Content: View>(_ label: String, hint: String?, key: Bool = false, muted: Bool = false,
                                  @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(key ? .system(.callout, design: .monospaced) : .body).foregroundStyle(muted || key ? .secondary : .primary)
      content()
      if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
  }

  private func toggle(_ label: String, hint: String?, on: Bool, set: @escaping @Sendable (Bool) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle(label, isOn: Binding(get: { on }, set: set))
      if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
  }

  private func copy(_ text: String, kind: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    copied = kind
    Announce.post(L10n.t("formsEditor.copied"))
  }

  static func recipientLabel(_ role: String) -> String {
    switch role {
    case "relay": L10n.t("formsEditor.recipient.relay")
    case "mailto": L10n.t("formsEditor.recipient.mailto")
    case "demo": L10n.t("formsEditor.recipient.demo")
    default: L10n.t("formsEditor.recipient.none")
    }
  }

  static func recipientHint(_ role: String) -> String {
    switch role {
    case "relay": L10n.t("formsEditor.recipientHint.relay")
    case "mailto": L10n.t("formsEditor.recipientHint.mailto")
    case "demo": L10n.t("formsEditor.recipientHint.demo")
    default: L10n.t("formsEditor.recipientHint.none")
    }
  }

  static func encryptionHint(_ mode: String) -> String {
    switch mode {
    case "required": L10n.t("formsEditor.encryptionHints.required")
    case "optional": L10n.t("formsEditor.encryptionHints.optional")
    default: L10n.t("formsEditor.encryptionHints.off")
    }
  }

  static func embedKind(_ kind: String) -> String {
    switch kind {
    case "placeholder": L10n.t("formsEditor.embedKinds.placeholder")
    case "codeBlock": L10n.t("formsEditor.embedKinds.codeBlock")
    default: L10n.t("formsEditor.embedKinds.frontmatter")
    }
  }

  // MARK: Writing, each against the newest state of the form

  @discardableResult
  private func change(_ transform: @escaping (JSONObject) -> JSONObject) async -> Bool {
    let id = id
    let fallback = def
    return await FormsTab.update(model) { options in
      let current = FormsOptions.forms(options).first { $0.id == id }?.def ?? fallback
      return FormsOptions.withForm(options, id: id, def: transform(current))
    }
  }

  /// Sets one key of the form; nil takes it away, and so does a value the template already gives.
  private func setKey(_ key: String, _ value: JSONValue?) async {
    await change { current in
      var next = current
      let template = current["template"]?.stringValue.flatMap { FormsOptions.templates[$0] }
      if let value, !(key != "fields" && template?[key].map(JSJSON.compact) == JSJSON.compact(value)) {
        next[key] = value
      } else {
        next[key] = nil
      }
      return next
    }
  }

  private func setEncryption(_ change: [String: JSONValue?]) async {
    await self.change { current in
      var encryption = current["encryption"]?.objectValue ?? JSONObject()
      for (key, value) in change { encryption[key] = value }
      var next = current
      // `mode` is required by the schema; off without anything else is the plugin's default.
      if encryption["mode"] == .string("off"), encryption.count == 1 {
        next["encryption"] = nil
      } else {
        var ordered = JSONObject([("mode", encryption["mode"] ?? .string("off"))])
        for key in encryption.keys where key != "mode" { ordered[key] = encryption[key] }
        next["encryption"] = .object(ordered)
      }
      return next
    }
  }

  private func setSuccess(_ change: [String: JSONValue?]) async {
    await self.change { current in
      let success = current["success"]?.objectValue ?? JSONObject()
      var merged = JSONObject([("mode", .string(success["mode"] == .string("redirect") ? "redirect" : "inline"))])
      for key in success.keys { merged[key] = success[key] }
      for (key, value) in change { merged[key] = value }
      var next = current
      next["success"] = merged["mode"] == .string("inline") && merged.count == 1 ? nil : .object(merged)
      return next
    }
  }

  /// Leaving the template: its fields, title and switches become the form's own, so the form stays
  /// what it was; without them a form with no fields of its own stops the build.
  private func setTemplate(_ name: String) async {
    guard name != (def["template"]?.stringValue ?? "") else { return }
    await change { current in
      guard name.isEmpty else {
        var next = current
        next["template"] = .string(name)
        return next
      }
      var own = current["template"]?.stringValue.flatMap { FormsOptions.templates[$0] } ?? JSONObject()
      for key in current.keys { own[key] = current[key] }
      own["template"] = nil
      return own
    }
  }

  private func takeTemplateFields() async {
    guard let templateName else { return }
    let name = FormsView.templateName(templateName)
    let (question, detail) = Confirm.split(L10n.t("formsEditor.templateFieldsBackConfirm", ["template": name]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("formsEditor.templateFieldsBackSubmit"), destructive: true,
                            window: unsaved?.window) else { return }
    await setKey("fields", nil)
    Announce.post(L10n.t("formsEditor.templateFieldsBackAnnounce", ["template": name]))
  }

  private func setLayoutForm(_ on: Bool) async {
    let id = id
    if await FormsTab.update(model, { options in
      var next = options
      next["layoutForm"] = .string(on ? id : "")
      return next
    }) {
      Announce.post(on ? L10n.t("formsEditor.layoutOnAnnounce", ["id": id]) : L10n.t("formsEditor.layoutOffAnnounce", ["id": id]))
    }
  }

  private func rename(_ to: String) async {
    let from = id
    let used = view.pages(from)
    // Asked only where a page names the old id, or where the scan could not say.
    let text: String? = !used.isEmpty
      ? L10n.t("formsEditor.renameConfirmUsed", ["from": from, "to": to, "count": String(used.count), "pages": view.pageNames(used)], count: used.count)
      : state.usages != nil ? nil : L10n.t("formsEditor.renameConfirm", ["from": from, "to": to])
    if let text {
      let (question, detail) = Confirm.split(text)
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("formsEditor.renameSubmit"), window: unsaved?.window) else {
        idReset += 1
        return
      }
    }
    selection = "form:\(to)"
    guard await FormsTab.update(model, { FormsOptions.rename($0, from: from, to: to) }) else { return }
    Announce.post(L10n.t("formsEditor.renamedAnnounce", ["from": from, "to": to]))
    // A captcha secret of the form's own is stored under its id; it goes along once the new id is
    // in the file (nothing happens when there is none).
    do {
      try AppDeploy.connections().saveRelaySecrets(model.project.id, RelaySecretsChange(moveCaptchaSecret: (from, to)))
      state.relayRound += 1
    } catch {
      Announce.post(error.message)
    }
  }
}

/// A Text of quartz-forms (QuartzControl's `FormText.tsx`): one string for every language, or a
/// record by language code. A site with several languages offers "per language" beside the label,
/// which writes one entry per language; a record shows one field per site language, plus any code
/// it names beside them. `fallback` is what applies while the value is unset (the template's, the
/// plugin's): its words stand as the placeholder. An emptied entry goes, an emptied record takes
/// the key with it.
struct FormTextField: View {
  let label: String
  var hint: String?
  let value: JSONValue?
  var fallback: JSONValue?
  let languages: [String]
  var multiline = false
  /// The plugin refuses an empty text here; emptying the field is not offered as a value.
  var required = false
  let onValue: (JSONValue?) -> Void

  var body: some View {
    let own = languages.isEmpty ? [FormsView.lang] : languages
    VStack(alignment: .leading, spacing: 4) {
      if case .object(let entries)? = value {
        HStack(spacing: 4) {
          Text(label)
          Button {
            let first = FormsOptions.text(.object(entries), own[0])
            onValue(first.isEmpty ? nil : .string(first))
          } label: {
            Label(L10n.t("formsEditor.text.oneForAllNamed", ["name": label]), systemImage: "globe").labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .help(L10n.t("formsEditor.text.oneForAllNamed", ["name": label]))
        }
        let codes = own + entries.keys.filter { !own.contains($0) }
        ForEach(codes, id: \.self) { code in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(code.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              .lineLimit(1).fixedSize().frame(minWidth: 28, alignment: .leading)
              .accessibilityHidden(true)
            CommitField(name: "\(label) \(code)", text: entries[code]?.stringValue ?? "",
                        placeholder: nonEmpty(FormsOptions.text(fallback, code)), multiline: multiline) { raw in
              let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
              var next = JSONObject()
              for key in entries.keys { if let text = entries[key]?.stringValue { next[key] = .string(text) } }
              next[code] = v.isEmpty ? nil : .string(v)
              onValue(next.isEmpty ? nil : .object(next))
              return true
            }
          }
        }
      } else {
        HStack(spacing: 4) {
          Text(label)
          if own.count > 1 {
            Button {
              let base = value?.stringValue ?? ""
              var next = JSONObject()
              for code in own {
                let text = base.isEmpty ? FormsOptions.text(fallback, code) : base
                if !text.isEmpty { next[code] = .string(text) }
              }
              onValue(next.isEmpty ? nil : .object(next))
            } label: {
              Label(L10n.t("formsEditor.text.perLanguageNamed", ["name": label]), systemImage: "globe").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L10n.t("formsEditor.text.perLanguageNamed", ["name": label]))
          }
        }
        CommitField(name: label, text: value?.stringValue ?? "", placeholder: nonEmpty(FormsOptions.text(fallback, own[0])), multiline: multiline) { raw in
          let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
          if v == (value?.stringValue ?? "") { return true }
          onValue(v.isEmpty ? (required ? value : nil) : .string(v))
          return true
        }
      }
      if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
  }

  private func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }
}

/// The inside of a form's `spam` or `transport`: each key either stands as the setting for all
/// forms, shown as what it is there, or is set for this form. Resetting a key gives it back.
struct InheritedBlock: View {
  var title: String?
  let hint: String
  let schema: NormalizedOptionSchema?
  let above: JSONObject
  let values: JSONObject
  let languages: [String]
  let projectPath: String
  let onValues: (JSONObject?) -> Void

  var body: some View {
    if let schema {
      VStack(alignment: .leading, spacing: 8) {
        if let title { Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary) }
        Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        ObjectBlock(fields: schema.fields, values: values, onValue: { onValues($0.isEmpty ? nil : $0) },
                    context: OptionsFormContext(language: L10n.language == "en" ? .en : .de, explicitEmpty: false, languages: languages,
                                                query: "", mark: "", projectPath: projectPath,
                                                above: (L10n.t("formsEditor.asAllForms"), L10n.t("formsEditor.asAllFormsChoice", ["value": "{{value}}"]))),
                    inherit: Inherited(values: above, fields: schema.fields), root: OptionRoot(flat: true))
      }
    }
  }
}

/// The target page of a redirect: free text, the site's pages as suggestions.
struct SlugField: View {
  let value: String
  let slugs: [String]
  let commit: (String) -> Void

  @State private var draft: String?
  @FocusState private var focused: Bool

  var body: some View {
    let text = draft ?? value
    let unknown = !value.isEmpty && !slugs.isEmpty && !slugs.contains(value)
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.t("formsEditor.successSlug"))
      TextField(L10n.t("formsEditor.successSlug"), text: Binding(get: { text }, set: { next in
        draft = next
        if slugs.contains(next), next != value { commit(next) }
      }), prompt: Text(verbatim: "danke"))
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .focused($focused)
        .onSubmit(finish)
        .onChange(of: focused) { _, now in if !now { finish() } }
        .onChange(of: value) { _, _ in if !focused { draft = nil } }
        .textInputSuggestions {
          ForEach(slugs.filter { text.isEmpty || $0.localizedCaseInsensitiveContains(text) }.prefix(40), id: \.self) { slug in
            Text(slug).textInputCompletion(slug)
          }
        }
      Text(unknown ? L10n.t("formsEditor.successSlugUnknown") : L10n.t("formsEditor.successSlugHint"))
        .font(.caption).foregroundStyle(unknown ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func finish() {
    guard let draft, draft != value else { return }
    commit(draft)
  }
}

/// One group of the settings for all forms (QuartzControl's `SectionPanel`). A group that is one
/// object (`spam`, `transport`) shows what is inside it, with the plugin's defaults on each key and
/// the keys as they stand in quartz.config.yaml (`spam.pow`).
struct FormsSectionInspector: View {
  let id: String
  let view: FormsView
  @Bindable var model: PluginsModel
  let state: FormsState
  @Binding var selection: String?

  var body: some View {
    let keys = FormsOptions.sections.first { $0.id == id }?.keys ?? []
    let options = view.options
    let messages = view.messages { $0.section == id }
    let languages = model.config?.siteLanguages ?? []
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(FormsView.sectionTitle(id), systemImage: FormsView.sectionSymbol(id)).font(.headline)
          Text(FormsView.sectionHint(id)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          if model.savedIndex == view.entry.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          Note(L10n.t("plugins.savesImmediately"))
        }
        FormMessages(problems: messages.problems, hints: messages.hints)
      }
      if id == "layout" { layout(view) }
      if id == "relay" {
        FormsRelaySection(view: view, model: model, state: state, selection: $selection)
      } else if id == "keys" {
        FormsKeysSection(view: view, model: model, state: state)
      } else if id == "texts" {
        FormsTextsSection(view: view, model: model, state: state)
      } else if keys.count == 1, let sole = soleSchema(keys[0]) {
        let key = keys[0]
        OptionsForm(schema: sole, values: options[key]?.objectValue ?? JSONObject(),
                    onChange: { next in Task { await FormsTab.update(model) { current in
                      var rest = current
                      rest[key] = next.map(JSONValue.object)
                      return rest
                    } } },
                    explicitEmpty: true, languages: languages, freeKeys: false,
                    root: OptionRoot(flat: true, keyPrefix: "\(key)."), projectPath: model.project.path)
      } else {
        OptionsForm(schema: view.schema, values: options,
                    onChange: { next in Task { await FormsTab.update(model) { _ in next ?? JSONObject() } } },
                    explicitEmpty: true, languages: languages, pick: { keys.contains($0) && $0 != "layoutForm" }, freeKeys: false,
                    root: OptionRoot(flat: true), projectPath: model.project.path)
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
  }

  /// The section's schema with the defaults of the plugin's default object on each key, so an
  /// unset key shows what the plugin takes for it.
  private func soleSchema(_ key: String) -> NormalizedOptionSchema? {
    guard var sole = FormsOptions.objectSchema(view.schema, key: key) else { return nil }
    let field = view.schema?.fields.first { $0.key == key }
    let defaults = field?.hasDefault == true ? field?.defaultValue?.objectValue ?? JSONObject() : JSONObject()
    sole.fields = sole.fields.map { f in
      guard !f.hasDefault, let value = defaults[f.key] else { return f }
      var with = f
      with.defaultValue = value
      return with
    }
    return sole
  }

  @ViewBuilder private func layout(_ view: FormsView) -> some View {
    let layoutForm = view.layoutForm
    let ids = view.ids
    Section {
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: "layoutForm").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
        Picker("layoutForm", selection: Binding(get: { ids.contains(layoutForm) || layoutForm.isEmpty ? layoutForm : "__unknown" }, set: { next in
          guard next != "__unknown" else { return }
          Task { await FormsTab.update(model) { options in
            var rest = options
            rest["layoutForm"] = .string(next)
            return rest
          } }
        })) {
          Text(L10n.t("formsEditor.noLayoutForm")).tag("")
          if !ids.contains(layoutForm), !layoutForm.isEmpty {
            Text(L10n.t("formsEditor.unknownForm", ["id": layoutForm])).tag("__unknown")
          }
          ForEach(ids, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        .labelsHidden()
        Text(L10n.t("formsEditor.layoutFormHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      FormsPositionField(view: view, model: model)
    }
  }
}

/// Nothing selected: what the tab is for.
struct FormsOverview: View {
  var body: some View {
    Section(L10n.t("formsEditor.panelEmptyTitle")) {
      Note(L10n.t("formsEditor.panelEmptyText"))
    }
  }
}
