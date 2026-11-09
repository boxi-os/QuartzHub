import QuartzHubCore
import SwiftUI
import UniformTypeIdentifiers

/// The fields of one form (QuartzControl's `FormFieldsEditor.tsx`): a list sorted by dragging, by
/// the arrow pair, the context menu, Anordnen ▸ Nach oben/unten and the accessibility actions; one
/// field open at a time with the keys its type reads; "Feld hinzufügen" as tiles by type.
///
/// While the form takes its template's fields, they are shown as editable as its own: the first
/// change writes the whole list as the form's own. Opening a row writes nothing.
struct FormFieldsEditor: View {
  let def: JSONObject
  /// The form's own fields, or the template's while it has none.
  let fields: [JSONObject]
  /// The schema of one form (`FormsOptions.formSchema`).
  let schema: NormalizedOptionSchema?
  let languages: [String]
  let anonymous: Bool
  /// The plugin's problems that name a field by its place (`fields[i]`).
  let fieldMessages: [FormsOptions.PlacedMessage]
  /// The installed quartz-forms when it is older than `FormsOptions.layoutSince`, else nil.
  let olderPlugin: String?
  let projectPath: String
  let onFields: ([JSONObject]) -> Void
  @Environment(\.unsavedGuard) private var unsaved

  @State private var open: String?
  @State private var adding = false

  private var lang: String { FormsView.lang }
  private var ids: [String] { Self.ids(fields) }
  private var hasPgpKey: Bool { fields.contains { $0["type"] == .string("pgpKey") } }

  /// Unique ids for the rows: a name written twice gets its place; a page break is `page:<n>`, n
  /// counting the breaks, which a title edit leaves alone.
  static func ids(_ list: [JSONObject]) -> [String] {
    list.enumerated().map { i, field in
      if FormsOptions.isPageBreak(field) { return "page:\(list.prefix(i).filter(FormsOptions.isPageBreak).count + 1)" }
      let name = field["name"].map { $0.stringValue ?? OptionFormText.inline($0) } ?? ""
      return list.firstIndex { $0["name"] == field["name"] } == i ? name : "\(name)#\(i)"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let template = def["template"]?.stringValue, FormsOptions.isTemplate(.string(template)), def["fields"]?.arrayValue == nil {
        Note(L10n.t("formsEditor.templateFieldsNote", ["template": FormsView.templateName(template)]))
      }
      if let olderPlugin { NoEffectLine(L10n.t("formsEditor.olderPlugin", ["since": FormsOptions.layoutSince, "installed": olderPlugin])) }
      if fields.isEmpty { Warning(L10n.t("formsEditor.noFields")) }
      ForEach(Array(fields.enumerated()), id: \.offset) { i, field in
        row(field, at: i)
      }
      Button { adding = true } label: { Label(L10n.t("formsEditor.addField"), systemImage: "plus") }
        .popover(isPresented: $adding, arrowEdge: .bottom) {
          AddFieldTiles(hasPgpKey: hasPgpKey, withBreaks: olderPlugin == nil) { type in
            adding = false
            add(type)
          }
        }
        .accessibilityIdentifier("forms.fields.add")
    }
    .focusedSceneValue(\.moveSelection, moveAction)
  }

  // MARK: Rows

  private func rowLabel(_ field: JSONObject, _ i: Int) -> String {
    guard FormsOptions.isPageBreak(field) else { return FormsOptions.fieldLabel(field, lang: lang) ?? "" }
    let step = L10n.t("formsEditor.stepLabel", ["n": String(fields.prefix(i).filter(FormsOptions.isPageBreak).count + 2)])
    let title = FormsOptions.fieldLabel(field, lang: lang) ?? ""
    return title.isEmpty ? step : "\(step) · \(title)"
  }

  /// "Nur sichtbar, wenn …" for the row, in the words visitors see.
  private func conditionText(_ field: JSONObject) -> String? {
    guard let condition = FormsOptions.showIf(field) else { return nil }
    let controller = fields.first { $0["name"] == .string(condition.field) }
    let label = controller.flatMap { FormsOptions.fieldLabel($0, lang: lang) } ?? condition.field
    if controller?["type"] == .string("checkbox") { return L10n.t("formsEditor.conditionSentenceTicked", ["field": label]) }
    let offered = controller.map { FormsOptions.controllerValues($0, lang: lang) } ?? []
    let values = condition.equals.map { v in L10n.t("formsEditor.quoted", ["text": offered.first { $0.value == v }?.label ?? v]) }
      .joined(separator: L10n.t("formsEditor.orWord"))
    return L10n.t("formsEditor.conditionSentence", ["field": label, "values": values])
  }

  private func row(_ field: JSONObject, at i: Int) -> some View {
    let id = ids[i]
    let label = rowLabel(field, i)
    let type = field["type"]?.stringValue ?? ""
    let isOpen = open == id
    let divider = FormsOptions.isPageBreak(field)
    let problems = fieldMessages.filter { $0.field == i }
    let required = type == "consent" || field["required"] == .bool(true)
    let optionalByAnonymous = anonymous && field["required"] == .bool(true) && FormsOptions.isPersonalField(field)
    let condition = conditionText(field)
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Button { open = isOpen ? nil : id } label: {
          HStack(spacing: 6) {
            Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary).frame(width: 12)
            Image(systemName: Self.typeSymbol(type)).foregroundStyle(.secondary).frame(width: 18)
            // Name above, type below: in the inspector's width one line cut the name to "Nach…".
            VStack(alignment: .leading, spacing: 1) {
              Text(label).foregroundStyle(divider ? .secondary : .primary).fontWeight(divider ? .medium : .regular)
                .lineLimit(2).truncationMode(.tail)
              HStack(spacing: 4) {
                Text(Self.typeName(type))
                if let width = field["width"]?.stringValue, width == "half" || width == "third" {
                  Text(verbatim: "· " + (width == "half" ? "½" : "⅓"))
                    .help(width == "half" ? L10n.t("formsEditor.widthBadge.half") : L10n.t("formsEditor.widthBadge.third"))
                    .accessibilityLabel(width == "half" ? L10n.t("formsEditor.widthBadge.half") : L10n.t("formsEditor.widthBadge.third"))
                }
              }
              .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? L10n.t("formsEditor.fieldExpanded") : L10n.t("formsEditor.fieldCollapsed"))
        if !problems.isEmpty { FormsView.problemBadge(problems.count) }
        if let condition { WordBadge(text: L10n.t("formsEditor.conditionalBadge")).help(condition).accessibilityLabel(condition) }
        if required && !optionalByAnonymous { WordBadge(text: L10n.t("formsEditor.requiredBadge")) }
        if optionalByAnonymous { WordBadge(text: L10n.t("formsEditor.optionalByAnonymousBadge")).foregroundStyle(.orange) }
        iconButton(L10n.t("pluginsInstalled.moveUp", ["name": label]), "arrow.up", disabled: i == 0) { move(i, to: i - 1) }
        iconButton(L10n.t("pluginsInstalled.moveDown", ["name": label]), "arrow.down", disabled: i == fields.count - 1) { move(i, to: i + 1) }
        iconButton(L10n.t("common.removeNamed", ["name": label]), "trash", disabled: false) { Task { await remove(i) } }
      }
      .padding(.horizontal, 6).padding(.vertical, 5)
      .draggable(Self.dragPrefix + id) {
        Label(label, systemImage: Self.typeSymbol(type)).padding(6)
      }
      .dropDestination(for: String.self) { items, _ in
        guard let item = items.first, item.hasPrefix(Self.dragPrefix),
              let from = ids.firstIndex(of: String(item.dropFirst(Self.dragPrefix.count))), from != i else { return false }
        move(from, to: i, said: false)
        return true
      }
      if isOpen {
        Divider()
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(problems.enumerated()), id: \.offset) { _, m in
            Text(verbatim: m.rest.isEmpty ? m.text : m.rest).font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
          }
          let controllers = fields.prefix(i).filter(FormsOptions.isController)
          if divider {
            PageBreakEditor(field: field, controllers: Array(controllers), languages: languages) { update(i, $0) }
          } else {
            FieldEditor(field: field, others: fields.enumerated().filter { $0.offset != i }.compactMap { $0.element["name"]?.stringValue },
                        controllers: Array(controllers), schema: schema, languages: languages, hasPgpKey: hasPgpKey,
                        olderPlugin: olderPlugin, projectPath: projectPath) { next in
              if next["name"] != field["name"], isOpen, let name = next["name"]?.stringValue { open = name }
              update(i, next)
            }
          }
        }
        .padding(10)
      }
    }
    .background(RoundedRectangle(cornerRadius: 6).fill(divider ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.background.opacity(0.4))))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: divider ? [4, 3] : [])))
    .padding(.top, divider ? 6 : 0)
    .contextMenu {
      Button(L10n.t("shell.menu.moveUp")) { move(i, to: i - 1) }.disabled(i == 0)
      Button(L10n.t("shell.menu.moveDown")) { move(i, to: i + 1) }.disabled(i == fields.count - 1)
      Divider()
      Button(L10n.t("common.removeNamed", ["name": label]), role: .destructive) { Task { await remove(i) } }
    }
    .accessibilityElement(children: .contain)
    .accessibilityActions {
      if i > 0 { Button(L10n.t("pluginsInstalled.moveUp", ["name": label])) { move(i, to: i - 1) } }
      if i < fields.count - 1 { Button(L10n.t("pluginsInstalled.moveDown", ["name": label])) { move(i, to: i + 1) } }
    }
    .accessibilityIdentifier("forms.field.\(id)")
  }

  private static let dragPrefix = "quartzhub-form-field:"

  private func iconButton(_ title: String, _ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Label(title, systemImage: symbol).labelStyle(.iconOnly) }
      .buttonStyle(.borderless)
      .help(title)
      .disabled(disabled)
  }

  // MARK: Changing the list

  /// The open row followed to its new place: ids count places, so a row that goes or moves
  /// renumbers the breaks after it.
  private func keepOpen(_ next: [JSONObject]) {
    guard let open, let current = ids.firstIndex(of: open) else { return }
    let opened = fields[current]
    self.open = next.firstIndex(of: opened).map { Self.ids(next)[$0] }
  }

  private func move(_ from: Int, to: Int, said: Bool = true) {
    guard to >= 0, to < fields.count, from != to else { return }
    var next = fields
    let item = next.remove(at: from)
    next.insert(item, at: to)
    keepOpen(next)
    onFields(next)
    if said {
      Announce.post(L10n.t("formsEditor.fieldMovedAnnounce", ["name": rowLabel(item, from), "n": String(to + 1), "count": String(fields.count)]))
    }
  }

  private func update(_ index: Int, _ next: JSONObject) {
    let before = fields[index]
    var list = fields
    list[index] = next
    // A condition names its field by name: a rename takes the conditions along.
    if case .string(let from)? = before["name"], let to = next["name"]?.stringValue, from != to {
      list = FormsOptions.renameInConditions(list, from: from, to: to)
    }
    onFields(list)
  }

  private func remove(_ index: Int) async {
    let name = rowLabel(fields[index], index)
    let pageBreak = FormsOptions.isPageBreak(fields[index])
    let text = pageBreak ? L10n.t("formsEditor.removeBreakConfirm", ["name": name]) : L10n.t("formsEditor.removeFieldConfirm", ["name": name])
    let (question, detail) = Confirm.split(text)
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("common.remove"), destructive: true, window: unsaved?.window) else { return }
    var next = fields
    next.remove(at: index)
    keepOpen(next)
    onFields(next)
    Announce.post(pageBreak ? L10n.t("formsEditor.breakRemovedAnnounce", ["name": name]) : L10n.t("formsEditor.fieldRemovedAnnounce", ["name": name]))
  }

  private func add(_ type: String) {
    if type == "pageBreak" {
      // At the end, where the next fields will go; until one follows, the plugin says it may not stand last.
      let n = fields.filter(FormsOptions.isPageBreak).count + 1
      onFields(fields + [JSONObject([("type", .string(type))])])
      open = "page:\(n)"
      Announce.post(L10n.t("formsEditor.breakAddedAnnounce", ["name": L10n.t("formsEditor.stepLabel", ["n": String(n + 1)])]))
      return
    }
    let taken = fields.compactMap { $0["name"]?.stringValue }
    let name = FormsOptions.freeFieldName(Self.defaultName(type), taken: taken)
    let label = Self.typeName(type)
    let field: JSONObject = switch type {
    case "consent": JSONObject([("type", .string(type)), ("name", .string(name)), ("text", .string(L10n.t("formsEditor.consentDefault")))])
    case "hidden": JSONObject([("type", .string(type)), ("name", .string(name)), ("value", .string("web"))])
    case "scale": JSONObject([("type", .string(type)), ("name", .string(name)), ("label", .string(label)), ("min", .number(1)), ("max", .number(5))])
    case "select", "radio", "checkboxes":
      JSONObject([("type", .string(type)), ("name", .string(name)), ("label", .string(label)), ("options", .array([
        .object(JSONObject([("value", .string("a")), ("label", .string(L10n.t("formsEditor.optionDefault", ["n": "1"])))])),
        .object(JSONObject([("value", .string("b")), ("label", .string(L10n.t("formsEditor.optionDefault", ["n": "2"])))])),
      ]))])
    default: JSONObject([("type", .string(type)), ("name", .string(name)), ("label", .string(label))])
    }
    onFields(fields + [field])
    open = name
    Announce.post(L10n.t("formsEditor.fieldAddedAnnounce", ["name": label]))
  }

  /// Anordnen ▸ Nach oben/unten for the open field.
  private var moveAction: MoveSelectionAction? {
    guard let open, let index = ids.firstIndex(of: open) else { return nil }
    return MoveSelectionAction(canMoveUp: index > 0, canMoveDown: index < fields.count - 1) { delta in move(index, to: index + delta) }
  }

  // MARK: Words for the types

  static func typeName(_ type: String) -> String {
    switch type {
    case "text": L10n.t("formsEditor.fieldTypes.text")
    case "textarea": L10n.t("formsEditor.fieldTypes.textarea")
    case "email": L10n.t("formsEditor.fieldTypes.email")
    case "tel": L10n.t("formsEditor.fieldTypes.tel")
    case "url": L10n.t("formsEditor.fieldTypes.url")
    case "number": L10n.t("formsEditor.fieldTypes.number")
    case "date": L10n.t("formsEditor.fieldTypes.date")
    case "select": L10n.t("formsEditor.fieldTypes.select")
    case "radio": L10n.t("formsEditor.fieldTypes.radio")
    case "checkboxes": L10n.t("formsEditor.fieldTypes.checkboxes")
    case "checkbox": L10n.t("formsEditor.fieldTypes.checkbox")
    case "scale": L10n.t("formsEditor.fieldTypes.scale")
    case "consent": L10n.t("formsEditor.fieldTypes.consent")
    case "pgpKey": L10n.t("formsEditor.fieldTypes.pgpKey")
    case "hidden": L10n.t("formsEditor.fieldTypes.hidden")
    case "pageBreak": L10n.t("formsEditor.fieldTypes.pageBreak")
    default: type
    }
  }

  static func typeHint(_ type: String) -> String {
    switch type {
    case "text": L10n.t("formsEditor.fieldTypeHints.text")
    case "textarea": L10n.t("formsEditor.fieldTypeHints.textarea")
    case "email": L10n.t("formsEditor.fieldTypeHints.email")
    case "tel": L10n.t("formsEditor.fieldTypeHints.tel")
    case "url": L10n.t("formsEditor.fieldTypeHints.url")
    case "number": L10n.t("formsEditor.fieldTypeHints.number")
    case "date": L10n.t("formsEditor.fieldTypeHints.date")
    case "select": L10n.t("formsEditor.fieldTypeHints.select")
    case "radio": L10n.t("formsEditor.fieldTypeHints.radio")
    case "checkboxes": L10n.t("formsEditor.fieldTypeHints.checkboxes")
    case "checkbox": L10n.t("formsEditor.fieldTypeHints.checkbox")
    case "scale": L10n.t("formsEditor.fieldTypeHints.scale")
    case "consent": L10n.t("formsEditor.fieldTypeHints.consent")
    case "pgpKey": L10n.t("formsEditor.fieldTypeHints.pgpKey")
    case "hidden": L10n.t("formsEditor.fieldTypeHints.hidden")
    default: L10n.t("formsEditor.fieldTypeHints.pageBreak")
    }
  }

  static func defaultName(_ type: String) -> String {
    switch type {
    case "text": L10n.t("formsEditor.fieldNames.text")
    case "textarea": L10n.t("formsEditor.fieldNames.textarea")
    case "email": L10n.t("formsEditor.fieldNames.email")
    case "tel": L10n.t("formsEditor.fieldNames.tel")
    case "url": L10n.t("formsEditor.fieldNames.url")
    case "number": L10n.t("formsEditor.fieldNames.number")
    case "date": L10n.t("formsEditor.fieldNames.date")
    case "select": L10n.t("formsEditor.fieldNames.select")
    case "radio": L10n.t("formsEditor.fieldNames.radio")
    case "checkboxes": L10n.t("formsEditor.fieldNames.checkboxes")
    case "checkbox": L10n.t("formsEditor.fieldNames.checkbox")
    case "scale": L10n.t("formsEditor.fieldNames.scale")
    case "consent": L10n.t("formsEditor.fieldNames.consent")
    case "pgpKey": L10n.t("formsEditor.fieldNames.pgpKey")
    case "hidden": L10n.t("formsEditor.fieldNames.hidden")
    default: type
    }
  }

  static func groupName(_ group: String) -> String {
    switch group {
    case "text": L10n.t("formsEditor.fieldGroups.text")
    case "choice": L10n.t("formsEditor.fieldGroups.choice")
    case "other": L10n.t("formsEditor.fieldGroups.other")
    default: L10n.t("formsEditor.fieldGroups.structure")
    }
  }

  static func typeSymbol(_ type: String) -> String {
    switch type {
    case "textarea": "text.alignleft"
    case "email": "at"
    case "tel": "phone"
    case "url": "link"
    case "number": "number"
    case "date": "calendar"
    case "select": "list.bullet"
    case "radio": "circle.inset.filled"
    case "checkboxes": "checklist"
    case "checkbox": "checkmark.square"
    case "scale": "slider.horizontal.3"
    case "consent": "checkmark.shield"
    case "pgpKey": "key"
    case "hidden": "eye.slash"
    case "pageBreak": "rectangle.split.1x2"
    default: "textformat"
    }
  }
}

/// "wirkt nicht" and why, under an option that does nothing where it stands.
struct NoEffectLine: View {
  let reason: String
  init(_ reason: String) { self.reason = reason }
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      WordBadge(text: L10n.t("pluginOptions.noEffect"))
      Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// "Feld hinzufügen": the types as tiles, by group.
private struct AddFieldTiles: View {
  let hasPgpKey: Bool
  /// False under a plugin older than `FormsOptions.layoutSince`, which refuses a page break.
  let withBreaks: Bool
  let add: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(FormsOptions.fieldGroups.filter { withBreaks || $0.types.contains { $0 != "pageBreak" } }, id: \.id) { group in
        VStack(alignment: .leading, spacing: 4) {
          Text(FormFieldsEditor.groupName(group.id)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          // Two columns: in three, "Schlüssel des Absenders" was cut.
          LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(group.types.filter { withBreaks || $0 != "pageBreak" }, id: \.self) { type in
              let disabled = type == "pgpKey" && hasPgpKey
              Button { add(type) } label: {
                Label(FormFieldsEditor.typeName(type), systemImage: FormFieldsEditor.typeSymbol(type))
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .disabled(disabled)
              .help(disabled ? L10n.t("formsEditor.onePgpKey") : FormFieldsEditor.typeHint(type))
            }
          }
        }
      }
    }
    .lineLimit(nil)
    .padding(12)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// One field, open: the keys its type reads, and through the plugin's own schema the rest.
private struct FieldEditor: View {
  let field: JSONObject
  let others: [String]
  /// The fields before this one a condition may name.
  let controllers: [JSONObject]
  let schema: NormalizedOptionSchema?
  let languages: [String]
  let hasPgpKey: Bool
  let olderPlugin: String?
  let projectPath: String
  let onField: (JSONObject) -> Void

  @State private var nameDraft: String?

  /// The keys shown with controls of their own; the rest of a type's keys go through the plugin's form.
  static let ownKeys: Set<String> = ["type", "name", "label", "hint", "required", "placeholder", "options", "text", "linkLabel", "minLabel",
                                     "maxLabel", "width", "layout", "showIf"]

  private var type: String { field["type"]?.stringValue ?? "" }
  private var hasLabel: Bool { type != "consent" && type != "hidden" }
  /// Under an older plugin a key of 0.4.0 shows only where it is set, to be taken out.
  private func offer(_ key: String) -> Bool { olderPlugin == nil || field[key] != nil }

  private func set(_ key: String, _ value: JSONValue?) {
    var next = field
    next[key] = value
    onField(next)
  }

  var body: some View {
    let problem = nameDraft.flatMap { FormsOptions.fieldNameProblem($0, others: others) }
    let shape = FormsOptions.sameShape.first { $0.contains(type) }
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.t("formsEditor.fieldName"))
      CommitField(name: L10n.t("formsEditor.fieldName"), text: field["name"]?.stringValue ?? "", monospaced: true) { raw in
        let to = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A refused name keeps its draft and the sentence saying why.
        if to != (field["name"]?.stringValue ?? ""), FormsOptions.fieldNameProblem(to, others: others) != nil {
          nameDraft = to
          return false
        }
        nameDraft = nil
        if to != (field["name"]?.stringValue ?? "") { set("name", .string(to)) }
        return true
      }
      Text(L10n.t("formsEditor.fieldNameHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let problem { ErrorLine(Self.nameProblem(problem)) }
    }
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.t("formsEditor.fieldType"))
      if let shape {
        Picker(L10n.t("formsEditor.fieldType"), selection: Binding(get: { type }, set: { next in
          var changed = field
          changed["type"] = .string(next)
          // A select's options are a list to open: its `layout` would do nothing.
          if next == "select" { changed["layout"] = nil }
          onField(changed)
        })) {
          ForEach(shape, id: \.self) { t in
            Text(FormFieldsEditor.typeName(t)).tag(t)
          }
        }
        .labelsHidden()
      } else {
        Text(FormFieldsEditor.typeName(type))
      }
    }
    if hasLabel {
      FormTextField(label: L10n.t("formsEditor.fieldLabel"), value: field["label"], languages: languages, required: true) { set("label", $0) }
    }
    if type == "consent" {
      FormTextField(label: L10n.t("formsEditor.consentText"), value: field["text"], languages: languages, multiline: true, required: true) { set("text", $0) }
      FormTextField(label: L10n.t("formsEditor.consentLinkLabel"), hint: L10n.t("formsEditor.consentLinkLabelHint"), value: field["linkLabel"],
                    languages: languages) { set("linkLabel", $0) }
    }
    if type == "scale" {
      FormTextField(label: L10n.t("formsEditor.minLabel"), value: field["minLabel"], languages: languages) { set("minLabel", $0) }
      FormTextField(label: L10n.t("formsEditor.maxLabel"), value: field["maxLabel"], languages: languages) { set("maxLabel", $0) }
    }
    if hasLabel, type != "checkbox", type != "scale", FormsOptions.inputKeys[type]?.contains("placeholder") == true {
      FormTextField(label: L10n.t("formsEditor.placeholder"), value: field["placeholder"], languages: languages) { set("placeholder", $0) }
    }
    if hasLabel {
      FormTextField(label: L10n.t("formsEditor.fieldHint"), hint: L10n.t("formsEditor.fieldHintHint"), value: field["hint"], languages: languages) {
        set("hint", $0)
      }
      Toggle(L10n.t("formsEditor.required"), isOn: Binding(get: { field["required"] == .bool(true) }, set: { set("required", $0 ? .bool(true) : nil) }))
    }
    if type != "hidden", offer("width") {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("formsEditor.fieldWidth"))
        let width = field["width"]?.stringValue.flatMap { ["full", "half", "third"].contains($0) ? $0 : nil } ?? "full"
        Picker(L10n.t("formsEditor.fieldWidth"), selection: Binding(get: { width }, set: { set("width", $0 == "full" ? nil : .string($0)) })) {
          Text(L10n.t("formsEditor.fieldWidths.full")).tag("full")
          Text(L10n.t("formsEditor.fieldWidths.half")).tag("half")
          Text(L10n.t("formsEditor.fieldWidths.third")).tag("third")
        }
        .pickerStyle(.segmented).labelsHidden()
        Text(L10n.t("formsEditor.fieldWidthHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if olderPlugin != nil { NoEffectLine(L10n.t("formsEditor.needsNewerPlugin", ["since": FormsOptions.layoutSince])) }
      }
    }
    if type == "select" || type == "radio" || type == "checkboxes" {
      ChoiceOptions(value: field["options"], languages: languages) { set("options", $0) }
    }
    if type == "radio" || type == "checkboxes", offer("layout") {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("formsEditor.optionLayout"))
        Picker(L10n.t("formsEditor.optionLayout"), selection: Binding(get: { field["layout"] == .string("inline") ? "inline" : "stacked" },
                                                                    set: { set("layout", $0 == "inline" ? .string("inline") : nil) })) {
          Text(L10n.t("formsEditor.optionLayouts.stacked")).tag("stacked")
          Text(L10n.t("formsEditor.optionLayouts.inline")).tag("inline")
        }
        .pickerStyle(.segmented).labelsHidden()
        if olderPlugin != nil { NoEffectLine(L10n.t("formsEditor.needsNewerPlugin", ["since": FormsOptions.layoutSince])) }
      }
    }
    if type != "hidden", type != "consent", offer("showIf") {
      ConditionEditor(value: field["showIf"], controllers: controllers) { set("showIf", $0) }
      if olderPlugin != nil { NoEffectLine(L10n.t("formsEditor.needsNewerPlugin", ["since": FormsOptions.layoutSince])) }
    }
    let variant = FormsOptions.fieldVariant(schema, type: type)
    let typeKeys = FormsOptions.inputKeys[type]
    // The plugin's form for the keys this type reads beyond the ones above, and any key the field
    // sets that the editor does not know, so nothing is hidden.
    let more = OptionSchema.withPresentKeys(NormalizedOptionSchema(source: schema?.source ?? .defaults, fields: variant, notes: []), .object(field))
      .fields.filter { f in !Self.ownKeys.contains(f.key) && (typeKeys.map { keys in keys.contains(f.key) || field[f.key] != nil } ?? true) }
    if !variant.isEmpty, !more.isEmpty {
      ObjectBlock(fields: more, values: field, onValue: { next in
        var out = next
        if out["type"] == nil { out["type"] = field["type"] }
        onField(out)
      }, context: OptionsFormContext(language: L10n.language == "en" ? .en : .de, explicitEmpty: false, languages: languages, query: "", mark: "",
                                     projectPath: projectPath),
      root: OptionRoot(flat: true))
    }
  }

  static func nameProblem(_ problem: FormsOptions.FieldNameProblem) -> String {
    switch problem {
    case .empty: L10n.t("formsEditor.fieldNameProblem.empty")
    case .pattern: L10n.t("formsEditor.fieldNameProblem.pattern")
    case .reserved: L10n.t("formsEditor.fieldNameProblem.reserved")
    case .taken: L10n.t("formsEditor.fieldNameProblem.taken")
    }
  }
}

/// A page break, open: the title of the step it begins and that step's condition.
private struct PageBreakEditor: View {
  let field: JSONObject
  let controllers: [JSONObject]
  let languages: [String]
  let onField: (JSONObject) -> Void

  private func set(_ key: String, _ value: JSONValue?) {
    var next = field
    next[key] = value
    onField(next)
  }

  var body: some View {
    FormTextField(label: L10n.t("formsEditor.stepTitle"), hint: L10n.t("formsEditor.stepTitleHint"), value: field["title"], languages: languages) {
      set("title", $0)
    }
    ConditionEditor(value: field["showIf"], controllers: controllers, hint: L10n.t("formsEditor.showIfStepHint")) { set("showIf", $0) }
  }
}

/// "Nur zeigen, wenn …": a field before this one and the values it must have, at least one. A
/// condition the plugin would refuse (a field no longer before this one, a value it can no longer
/// have) stays visible so it can be changed; the plugin's check says what is wrong at the row.
struct ConditionEditor: View {
  let value: JSONValue?
  let controllers: [JSONObject]
  var hint: String?
  let onValue: (JSONValue?) -> Void

  private var lang: String { FormsView.lang }

  var body: some View {
    let named = value?.objectValue?["field"]?.stringValue ?? ""
    let chosen = FormsOptions.showIf(JSONObject([("showIf", value ?? .null)]))?.equals ?? []
    let controller = controllers.first { $0["name"] == .string(named) }
    let isCheckbox = controller?["type"] == .string("checkbox")
    let offered = controller.map { c in
      FormsOptions.controllerValues(c, lang: lang).map { (value: $0.value, label: isCheckbox ? L10n.t("formsEditor.showIfTickedValue") : $0.label) }
    } ?? []
    let stale = chosen.filter { v in !offered.contains { $0.value == v } }
    let toggles = controller != nil && (!isCheckbox || !stale.isEmpty)
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.t("formsEditor.showIf"))
      Picker(L10n.t("formsEditor.showIfField"), selection: Binding(get: { named }, set: { pick($0) })) {
        Text(L10n.t("formsEditor.showIfAlways")).tag("")
        ForEach(Array(controllers.enumerated()), id: \.offset) { _, c in
          if let name = c["name"]?.stringValue { Text(FormsOptions.fieldLabel(c, lang: lang) ?? name).tag(name) }
        }
        if !named.isEmpty, controller == nil { Text(L10n.t("formsEditor.showIfMissing", ["name": named])).tag(named) }
      }
      .labelsHidden()
      if isCheckbox, !toggles { Text(L10n.t("formsEditor.showIfTicked")).foregroundStyle(.secondary) }
      if toggles {
        Text(L10n.t("formsEditor.showIfValues")).foregroundStyle(.secondary)
        ForEach(offered.map { ($0.value, $0.label) } + stale.map { ($0, L10n.t("formsEditor.showIfStale", ["value": $0])) }, id: \.0) { v, label in
          Toggle(label, isOn: Binding(get: { chosen.contains(v) }, set: { on in
            let next = on ? chosen + [v] : chosen.filter { $0 != v }
            // A condition without a value is none; the plugin refuses it, so the last value stays.
            guard !next.isEmpty else { return }
            let order = offered.map(\.value) + stale
            onValue(.object(FormsOptions.showIfValue(field: named, equals: order.filter(next.contains))))
          }))
        }
      }
      Text(hint ?? L10n.t("formsEditor.showIfHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func pick(_ name: String) {
    guard !name.isEmpty else { return onValue(nil) }
    let first = controllers.first { $0["name"] == .string(name) }.flatMap { FormsOptions.controllerValues($0, lang: lang).first?.value }
    onValue(.object(FormsOptions.showIfValue(field: name, equals: first.map { [$0] } ?? [])))
  }
}

/// The options of a choice: value and label each; the last one stays (the plugin refuses a choice
/// without options).
private struct ChoiceOptions: View {
  let value: JSONValue?
  let languages: [String]
  let onValue: (JSONValue) -> Void

  private var list: [(value: String, label: JSONValue?)] {
    (value?.arrayValue ?? []).compactMap(\.objectValue).map { o in
      (o["value"].map { $0.stringValue ?? (($0 == .null) ? "" : OptionFormText.inline($0)) } ?? "", o["label"])
    }
  }

  private func write(_ items: [(value: String, label: JSONValue?)]) {
    onValue(.array(items.map { item in
      var o = JSONObject([("value", .string(item.value))])
      if let label = item.label { o["label"] = label }
      return .object(o)
    }))
  }

  var body: some View {
    let items = list
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.t("formsEditor.choiceOptions"))
      ForEach(Array(items.enumerated()), id: \.offset) { i, item in
        HStack(alignment: .top, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("formsEditor.optionValue")).font(.caption).foregroundStyle(.secondary)
            CommitField(name: L10n.t("formsEditor.optionValue"), text: item.value, monospaced: true) { raw in
              let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !v.isEmpty else { return false }
              var next = items
              next[i].value = v
              write(next)
              return true
            }
            .frame(width: 90)
          }
          FormTextField(label: L10n.t("formsEditor.optionLabel"), value: item.label, languages: languages, required: true) { label in
            var next = items
            next[i].label = label ?? item.label
            write(next)
          }
          Button { write(items.enumerated().filter { $0.offset != i }.map(\.element)) } label: {
            Label(L10n.t("common.removeNamed", ["name": item.value]), systemImage: "trash").labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .help(L10n.t("common.removeNamed", ["name": item.value]))
          .disabled(items.count == 1)
        }
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      }
      Button {
        let values = items.map(\.value)
        var n = items.count + 1
        while values.contains(String(n)) { n += 1 }
        write(items + [(String(n), .string(L10n.t("formsEditor.optionDefault", ["n": String(n)])))])
      } label: { Label(L10n.t("formsEditor.addOption"), systemImage: "plus") }
      Text(L10n.t("formsEditor.choiceOptionsHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}
