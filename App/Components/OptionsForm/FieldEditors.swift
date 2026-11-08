import QuartzHubCore
import SwiftUI

// One option of the options form: its label, control, reset and explanation (QuartzControl's
// `editors.tsx`, FieldRow and NodeEditor with the editors for lists, records, unions and JSON).

struct FieldRow: View {
  let field: OptionField
  let value: JSONValue?
  let onValue: (JSONValue?) -> Void
  let context: OptionsFormContext
  let inherit: Inherited
  /// In a record entry: the value an unset field takes from above (`.some(nil)`: none).
  let inherited: JSONValue??
  /// Why the field does nothing right now. Greyed where it stands, not disabled.
  let inactive: String?
  /// The key as shown, where it is not the field's own.
  var keyLabel: String?

  private var shownKey: String { keyLabel ?? field.key }

  private var isBlock: Bool {
    switch field.node {
    case .object, .record, .array, .json: true
    default: false
    }
  }

  var body: some View {
    let text = OptionFormText.texts(field, context.language)
    let dim = inactive != nil || context.muted
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        label(text, dim: dim)
        Spacer(minLength: 4)
        if value != nil { resetButton }
      }
      if let inactive {
        Text(inactive).font(.caption).italic().foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityHidden(!isBlock)
      }
      if isBlock, let description = text.description { explanation(description) }
      editor
        .padding(.leading, isBlock ? 10 : 0)
        .overlay(alignment: .leading) {
          if isBlock { Rectangle().fill(.separator).frame(width: 1) }
        }
      if !isBlock, let description = text.description { explanation(description) }
    }
    .accessibilityElement(children: .contain)
  }

  /// The plugin's own words first where it has any, the key beside them: the key is what stands in
  /// quartz.config.yaml, the title what one reads. A set value says so in a word.
  private func label(_ text: OptionFormText.Texts, dim: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      if let title = text.title {
        Marked(text: title, query: context.mark).fontWeight(.medium).foregroundStyle(dim ? .secondary : .primary)
      }
      Marked(text: shownKey, query: context.mark)
        .font(.system(text.title == nil && !dim ? .callout : .caption, design: .monospaced))
        .foregroundStyle(.secondary)
      if inactive != nil {
        WordBadge(text: L10n.t("pluginOptions.noEffect")).accessibilityHidden(true)
      }
      if value != nil {
        Text(L10n.t("pluginOptions.changed")).font(.caption.weight(.medium)).foregroundStyle(.tint)
      }
    }
  }

  private func explanation(_ text: String) -> some View {
    Marked(text: text, query: context.mark).font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// "Back to what the plugin does without me": the key goes. Named after what it does.
  private var resetButton: some View {
    let title = inherited != nil ? L10n.t("pluginOptions.resetInheritNamed", ["name": shownKey])
      : field.hasDefault ? L10n.t("pluginOptions.resetNamed", ["name": shownKey])
      : L10n.t("pluginOptions.removeNamed", ["name": shownKey])
    return Button {
      onValue(nil)
    } label: {
      Label(title, systemImage: "arrow.counterclockwise").labelStyle(.iconOnly)
    }
    .buttonStyle(.borderless)
    .help(title)
  }

  private var editor: some View {
    var inner = context
    if inactive != nil { inner.muted = true }
    let fromAbove = inherited != nil
    let defaultValue: JSONValue? = if let inherited { inherited ?? nil } else { field.defaultValue }
    return NodeEditor(node: field.node, field: field, value: value, defaultValue: defaultValue,
                      hasDefault: fromAbove ? true : field.hasDefault, fromAbove: fromAbove, onValue: onValue,
                      context: inner, inherit: inherit,
                      name: inactive.map { "\(field.key). \($0)" } ?? (OptionFormText.texts(field, context.language).title ?? field.key))
  }
}

/// A word in a capsule: "wirkt nicht", "Frame".
struct WordBadge: View {
  let text: String
  var body: some View {
    Text(text).font(.caption2.weight(.semibold))
      .padding(.horizontal, 5).padding(.vertical, 1)
      .background(Capsule().fill(.quaternary))
  }
}

// MARK: - One value of any kind

struct NodeEditor: View {
  let node: OptionNode
  let field: OptionField?
  let value: JSONValue?
  let defaultValue: JSONValue?
  let hasDefault: Bool
  var fromAbove = false
  let onValue: (JSONValue?) -> Void
  let context: OptionsFormContext
  var inherit: Inherited?
  /// The control's accessible name: the field's title or key, with the reason it does nothing.
  let name: String

  var body: some View {
    switch node {
    case .boolean:
      let effective = value.map { $0 == .bool(true) } ?? (defaultValue == .bool(true))
      HStack(spacing: 8) {
        Toggle(name, isOn: Binding(get: { effective }, set: { onValue(.bool($0)) }))
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .accessibilityLabel(name)
        if value == nil {
          Text(fromAbove ? (context.above?.short ?? L10n.t("pluginOptions.asAbove"))
               : hasDefault ? L10n.t("pluginOptions.isDefault") : L10n.t("pluginOptions.notSet"))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    case .enumeration(let values):
      EnumPicker(values: values, field: field, value: value, defaultValue: defaultValue, hasDefault: hasDefault,
                 fromAbove: fromAbove, onValue: onValue, context: context, name: name)
    case .number:
      let text: String = if case .number(let number)? = value { OptionFormText.inline(.number(number)) } else { "" }
      CommitField(name: name, text: text, placeholder: hasDefault ? defaultValue.map(OptionFormText.inline) : nil) { raw in
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
          if value != nil { onValue(nil) }
          return true
        }
        guard let number = Double(trimmed), number.isFinite else { return false }
        if value != .number(number) { onValue(.number(number)) }
        return true
      }
      .frame(maxWidth: 130)
    case .string:
      StringEditor(field: field, value: value, defaultValue: defaultValue, hasDefault: hasDefault, onValue: onValue,
                   context: context, name: name)
    case .object(let fields, _):
      VStack(alignment: .leading, spacing: 12) {
        ObjectBlock(fields: fields, values: value?.objectValue ?? JSONObject(), onValue: { onValue(.object($0)) }, context: context)
      }
    case .record(let inner, let languageKeys):
      RecordEditor(valueNode: inner, languageKeys: languageKeys, value: value, onValue: onValue, context: context, inherit: inherit)
    case .array(let items):
      ListEditor(items: items, field: field, value: value, defaultValue: defaultValue, hasDefault: hasDefault, onValue: onValue,
                 context: context, name: name)
    case .union(let variants):
      UnionEditor(variants: variants, field: field, value: value, defaultValue: defaultValue, hasDefault: hasDefault,
                  onValue: onValue, context: context, inherit: inherit, name: name)
    case .json:
      JSONEditor(value: value, defaultValue: hasDefault ? defaultValue : nil, onValue: onValue, name: name)
    }
  }
}

/// A choice. The empty choice is "not set", and it says what that means.
struct EnumPicker: View {
  let values: [OptionEnumValue]
  let field: OptionField?
  let value: JSONValue?
  let defaultValue: JSONValue?
  let hasDefault: Bool
  var fromAbove = false
  let onValue: (JSONValue?) -> Void
  let context: OptionsFormContext
  let name: String

  private static let notSet = -1, unknown = -2

  var body: some View {
    let index = value.flatMap { value in values.firstIndex { $0.jsonValue == value } }
    let selection = value == nil ? Self.notSet : index ?? Self.unknown
    Picker(name, selection: Binding(get: { selection }, set: { chosen in
      if chosen == Self.notSet { onValue(nil) } else if chosen >= 0 { onValue(values[chosen].jsonValue) }
    })) {
      Text(emptyChoice).tag(Self.notSet)
      if let value, index == nil { Text(OptionFormText.inline(value)).tag(Self.unknown) }
      ForEach(Array(values.enumerated()), id: \.offset) { offset, option in
        let label = OptionFormText.enumLabel(field, option, context.language)
        let raw = OptionFormText.enumLabel(nil, option, context.language)
        Text(label == raw ? raw : "\(label) (\(raw))").tag(offset)
      }
    }
    .labelsHidden()
    .fixedSize()
  }

  private var emptyChoice: String {
    guard hasDefault, let defaultValue, let option = OptionEnumValue.from(defaultValue) else { return L10n.t("pluginOptions.notSet") }
    let label = OptionFormText.enumLabel(field, option, context.language)
    if fromAbove, let above = context.above { return above.choice.replacingOccurrences(of: "{{value}}", with: label) }
    return fromAbove ? L10n.t("pluginOptions.asAboveChoice", ["value": label]) : L10n.t("pluginOptions.defaultChoice", ["value": label])
  }
}

extension OptionEnumValue {
  static func from(_ value: JSONValue) -> OptionEnumValue? {
    switch value {
    case .string(let text): .string(text)
    case .number(let number): .number(number)
    case .bool(let bool): .bool(bool)
    default: nil
    }
  }
}

/// Text. A cleared field removes the key ("not set"); an empty text the plugin reads as "show
/// nothing" has a button of its own where the caller allows it.
private struct StringEditor: View {
  let field: OptionField?
  let value: JSONValue?
  let defaultValue: JSONValue?
  let hasDefault: Bool
  let onValue: (JSONValue?) -> Void
  let context: OptionsFormContext
  let name: String

  var body: some View {
    let current = value?.stringValue ?? ""
    let placeholder = value == .string("") ? L10n.t("pluginsInstalled.explicitlyEmpty")
      : hasDefault ? defaultValue.map(OptionFormText.inline) : nil
    let multiline = field?.widget == .html || field?.widget == .markdown
    VStack(alignment: .leading, spacing: 4) {
      CommitField(name: name, text: current, placeholder: placeholder, multiline: multiline, monospaced: multiline) { raw in
        if raw != current { onValue(raw.isEmpty ? nil : .string(raw)) }
        return true
      }
      if context.explicitEmpty, value == nil || value == .string("") {
        let isEmpty = value == .string("")
        Button(isEmpty ? L10n.t("pluginsInstalled.unsetEmpty") : L10n.t("pluginsInstalled.setEmpty")) {
          onValue(isEmpty ? nil : .string(""))
        }
        .buttonStyle(.link)
        .font(.caption)
        .help(isEmpty ? L10n.t("pluginsInstalled.unsetEmptyHint") : L10n.t("pluginsInstalled.setEmptyHint"))
      }
    }
  }
}

/// A text field that writes when it is left or on Return, as QuartzControl's did on blur; a page
/// switch leaves it too. `commit` answers whether the text was taken: a JSON text that does not
/// parse stays as typed, with its error.
struct CommitField: View {
  let name: String
  /// What is written now.
  let text: String
  var placeholder: String?
  var multiline = false
  var monospaced = false
  let commit: (String) -> Bool

  @State private var draft: String?
  @State private var committed: String?
  @FocusState private var focused: Bool

  var body: some View {
    let binding = Binding(get: { draft ?? text }, set: { draft = $0 })
    Group {
      if multiline {
        TextEditor(text: binding)
          .font(.system(.callout, design: .monospaced))
          .frame(minHeight: 70, maxHeight: 220)
          .scrollContentBackground(.hidden)
          .padding(4)
          .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
          .overlay(alignment: .topLeading) {
            if (draft ?? text).isEmpty, let placeholder {
              Text(placeholder).font(.system(.callout, design: .monospaced)).foregroundStyle(.tertiary)
                .padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false).lineLimit(3)
            }
          }
          .accessibilityLabel(name)
      } else {
        TextField(name, text: binding, prompt: placeholder.map { Text($0) })
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .font(monospaced ? .system(.body, design: .monospaced) : .body)
          .onSubmit(finish)
      }
    }
    .focused($focused)
    .onChange(of: focused) { _, now in if !now { finish() } }
    // The page's new value has arrived: the draft has done its job.
    .onChange(of: text) { _, _ in
      if !focused { draft = nil }
      committed = nil
    }
    .onDisappear(perform: finish)
  }

  /// A taken text stays the draft until the page hands the new value back. Dropped at once, the
  /// field showed the old value for a moment and wrote it back when it was left next (measured:
  /// a cleared `condition` came back as "has-tags").
  private func finish() {
    // Already handed over, waiting for the page: not a second write.
    guard let typed = draft, typed != committed else { return }
    if typed == text {
      draft = nil
    } else if commit(typed) {
      committed = typed
    }
  }
}

// MARK: - Lists

private struct ListEditor: View {
  let items: OptionNode
  let field: OptionField?
  let value: JSONValue?
  let defaultValue: JSONValue?
  let hasDefault: Bool
  let onValue: (JSONValue?) -> Void
  let context: OptionsFormContext
  let name: String

  var body: some View {
    if case .array(let list)? = value {
      VStack(alignment: .leading, spacing: 6) {
        if list.isEmpty { Note(L10n.t("pluginOptions.emptyList")) }
        ForEach(Array(list.enumerated()), id: \.offset) { index, item in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: String(index + 1)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
              .frame(width: 18, alignment: .trailing)
            NodeEditor(node: items, field: field, value: item, defaultValue: nil, hasDefault: false,
                       onValue: { next in
                         if let next { onValue(.array(list.enumerated().map { $0.offset == index ? next : $0.element })) }
                         else { onValue(.array(list.enumerated().filter { $0.offset != index }.map(\.element))) }
                       },
                       context: context, name: "\(name) \(index + 1)")
            Spacer(minLength: 0)
            iconButton(L10n.t("pluginOptions.moveItemUp", ["n": String(index + 1)]), "arrow.up") { onValue(.array(moved(list, index, -1))) }
              .disabled(index == 0)
            iconButton(L10n.t("pluginOptions.moveItemDown", ["n": String(index + 1)]), "arrow.down") { onValue(.array(moved(list, index, 1))) }
              .disabled(index == list.count - 1)
            iconButton(L10n.t("pluginOptions.removeItem", ["n": String(index + 1)]), "trash") {
              onValue(.array(list.enumerated().filter { $0.offset != index }.map(\.element)))
            }
          }
        }
        Button(L10n.t("pluginOptions.addItem")) { onValue(.array(list + [nextItem(list)])) }
      }
    } else {
      // Nobody changed this list yet: the plugin's own one stands, shown rather than edited, until
      // "Anpassen" copies it, so an untouched list is not written into the config by a glance.
      let defaultList: [JSONValue]? = if case .array(let list)? = defaultValue { list } else { nil }
      HStack(alignment: .firstTextBaseline) {
        Text(hasDefault && defaultValue != nil ? L10n.t("pluginOptions.defaultList", ["value": OptionFormText.inline(defaultValue!)])
             : L10n.t("pluginOptions.notSet"))
          .font(.callout).foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Button(hasDefault && defaultList != nil ? L10n.t("pluginOptions.customize") : L10n.t("pluginOptions.addItem")) {
          onValue(.array(defaultList ?? [OptionFormText.empty(of: items) ?? .null]))
        }
      }
    }
  }

  /// An enum list offers what is not in it yet: detection strategies are a set in priority order.
  private func nextItem(_ list: [JSONValue]) -> JSONValue {
    if case .enumeration(let values) = items {
      return (values.first { !list.contains($0.jsonValue) } ?? values.first)?.jsonValue ?? .null
    }
    return OptionFormText.empty(of: items) ?? .null
  }

  private func moved(_ list: [JSONValue], _ index: Int, _ delta: Int) -> [JSONValue] {
    var next = list
    let item = next.remove(at: index)
    next.insert(item, at: index + delta)
    return next
  }
}

func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    Label(title, systemImage: symbol).labelStyle(.iconOnly)
  }
  .buttonStyle(.borderless)
  .help(title)
}

// MARK: - Records (keys chosen by the user)

private struct RecordEditor: View {
  let valueNode: OptionNode
  let languageKeys: Bool
  let value: JSONValue?
  let onValue: (JSONValue?) -> Void
  let context: OptionsFormContext
  let inherit: Inherited?

  @State private var draftKey = ""

  var body: some View {
    let record = value?.objectValue ?? JSONObject()
    let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let offered = languageKeys ? context.languages.filter { record[$0] == nil } : []
    VStack(alignment: .leading, spacing: 8) {
      if record.isEmpty { Note(L10n.t("pluginOptions.emptyRecord")) }
      ForEach(record.keys, id: \.self) { entryKey in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(verbatim: entryKey).font(.system(.callout, design: .monospaced).weight(.semibold))
            Spacer()
            iconButton(L10n.t("pluginOptions.removeEntry", ["key": entryKey]), "trash") {
              onValue(.object(OptionSchema.setting(nil, at: [entryKey], in: record)))
            }
          }
          if case .object(let fields, _) = valueNode {
            ObjectBlock(fields: fields, values: record[entryKey]?.objectValue ?? JSONObject(),
                        onValue: { next in onValue(.object(OptionSchema.setting(next.isEmpty ? nil : .object(next), at: [entryKey], in: record))) },
                        context: context, inherit: inherit)
          } else {
            NodeEditor(node: valueNode, field: nil, value: record[entryKey], defaultValue: nil, hasDefault: false,
                       onValue: { next in onValue(.object(OptionSchema.setting(next, at: [entryKey], in: record))) },
                       context: context, name: entryKey)
          }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .accessibilityElement(children: .contain)
      }
      HStack {
        if !offered.isEmpty {
          Picker(L10n.t("pluginOptions.addLanguage"), selection: Binding(get: { "" }, set: { add($0, to: record) })) {
            Text(L10n.t("pluginOptions.addLanguage")).tag("")
            ForEach(offered, id: \.self) { Text(verbatim: $0).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
        }
        TextField(L10n.t("pluginOptions.entryKeyPlaceholder"), text: $draftKey, prompt: Text(L10n.t("pluginOptions.entryKeyPlaceholder")))
          .labelsHidden().textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).frame(maxWidth: 130)
          .onSubmit { add(key, to: record) }
        Button(L10n.t("pluginOptions.addEntry")) { add(key, to: record) }
          .disabled(key.isEmpty || record[key] != nil)
      }
    }
  }

  private func add(_ key: String, to record: JSONObject) {
    guard !key.isEmpty, record[key] == nil else { return }
    var next = record
    next[key] = OptionFormText.empty(of: valueNode) ?? .null
    onValue(.object(next))
    draftKey = ""
  }
}

// MARK: - Unions: one of several shapes

private struct UnionEditor: View {
  let variants: [OptionNode]
  let field: OptionField?
  let value: JSONValue?
  let defaultValue: JSONValue?
  let hasDefault: Bool
  let onValue: (JSONValue?) -> Void
  let context: OptionsFormContext
  let inherit: Inherited?
  let name: String

  var body: some View {
    // Choices and switches only (navigations' `icons: "both" | true | …`) are one picker, with the
    // two booleans as choices beside the words.
    let simple = variants.allSatisfy { if case .enumeration = $0 { true } else if case .boolean = $0 { true } else { false } }
    if simple {
      let values = variants.flatMap { node -> [OptionEnumValue] in
        if case .enumeration(let values) = node { return values }
        return [.bool(true), .bool(false)]
      }
      EnumPicker(values: values, field: field, value: value, defaultValue: defaultValue, hasDefault: hasDefault,
                 onValue: onValue, context: context, name: name)
    } else {
      let shown = value ?? defaultValue
      let current = shown.flatMap { shown in variants.firstIndex { OptionSchema.accepts($0, shown) } } ?? 0
      let variant = variants[current]
      let defaultFits = defaultValue.map { OptionSchema.accepts(variant, $0) } ?? false
      VStack(alignment: .leading, spacing: 6) {
        Picker(L10n.t("pluginOptions.shape", ["name": field?.key ?? ""]),
               selection: Binding(get: { current }, set: { onValue(OptionFormText.empty(of: variants[$0])) })) {
          ForEach(Array(variants.enumerated()), id: \.offset) { offset, node in
            Text(Self.kindName(node)).tag(offset)
          }
        }
        .labelsHidden()
        .fixedSize()
        NodeEditor(node: variant, field: field, value: value, defaultValue: defaultFits ? defaultValue : nil,
                   hasDefault: hasDefault && defaultFits, onValue: onValue, context: context, inherit: inherit, name: name)
      }
    }
  }

  static func kindName(_ node: OptionNode) -> String {
    switch node {
    case .enumeration: L10n.t("pluginOptions.kind.enum")
    case .boolean: L10n.t("pluginOptions.kind.boolean")
    case .string: L10n.t("pluginOptions.kind.string")
    case .number: L10n.t("pluginOptions.kind.number")
    case .object: L10n.t("pluginOptions.kind.object")
    case .record: L10n.t("pluginOptions.kind.record")
    case .array: L10n.t("pluginOptions.kind.array")
    case .union: L10n.t("pluginOptions.kind.union")
    case .json: L10n.t("pluginOptions.kind.json")
    }
  }
}

// MARK: - What the reader could not describe: JSON text

private struct JSONEditor: View {
  let value: JSONValue?
  let defaultValue: JSONValue?
  let onValue: (JSONValue?) -> Void
  let name: String

  @State private var invalid = false

  var body: some View {
    let current = value.map(JSJSON.stringify) ?? ""
    VStack(alignment: .leading, spacing: 4) {
      CommitField(name: name, text: current, placeholder: defaultValue.map(JSJSON.stringify), multiline: true, monospaced: true) { raw in
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == current.trimmingCharacters(in: .whitespacesAndNewlines) { invalid = false; return true }
        if trimmed.isEmpty {
          invalid = false
          onValue(nil)
          return true
        }
        guard let parsed = try? JSJSON.parse(trimmed) else {
          invalid = true
          return false
        }
        invalid = false
        onValue(parsed)
        return true
      }
      Text(invalid ? L10n.t("pluginOptions.jsonInvalid") : L10n.t("pluginOptions.jsonHint"))
        .font(.caption).foregroundStyle(invalid ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }
  }
}
