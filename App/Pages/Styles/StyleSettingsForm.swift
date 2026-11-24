import QuartzHubCore
import SwiftUI

/// A theme's own options, built from the upstream theme's `@settings` block, grouped by its
/// headings (QuartzControl's `StyleSettingsForm`). Class settings the port does not ship are left
/// out: they would be switches that do nothing.
struct StyleSettingsForm: View {
  let schema: JSONValue
  let info: ThemeStyleSettingsInfo
  let values: JSONObject
  @Binding var query: String
  let onChange: ([(key: String, value: JSONValue?)]) -> Void

  var body: some View {
    let shipped = Set(info.classSettingKeys)
    let usable = StyleSettingsValues.usable(StyleSettingsValues.fields(schema), shippedClassKeys: shipped)
    let groups = StyleSettingsValues.groups(StyleSettingsValues.filter(usable, query: query))
    let count = usable.filter { $0.kind != "heading" && $0.kind != "info-text" }.count
    if let author = schema["author"]?.stringValue {
      Note(L10n.t("styles.styleSettings.sourceNote", ["theme": schema["themeName"]?.stringValue ?? "", "author": author], count: count))
    } else {
      Note(L10n.t("styles.styleSettings.sourceNoteBare", ["theme": schema["themeName"]?.stringValue ?? ""], count: count))
    }
    TextField(L10n.t("styles.styleSettings.searchPlaceholder"), text: $query, prompt: Text(L10n.t("styles.styleSettings.searchPlaceholder")))
      .labelsHidden()
      .textFieldStyle(.roundedBorder)
      .accessibilityIdentifier("styleSettings.search")
    ForEach(groups) { group in
      StyleSettingsGroupView(group: group, values: values, shipped: shipped, forceOpen: !StylesModel.trim(query).isEmpty, onChange: onChange)
    }
  }
}

struct StyleSettingsGroupView: View {
  let group: StyleSettingsValues.Group
  let values: JSONObject
  let shipped: Set<String>
  let forceOpen: Bool
  let onChange: ([(key: String, value: JSONValue?)]) -> Void
  /// The theme author's `collapsed` decides the first state, as in Obsidian.
  @State private var open: Bool?

  var body: some View {
    if let heading = group.heading {
      if group.hasAnyField {
        Fold(isExpanded: Binding(get: { forceOpen || (open ?? !heading.collapsed) }, set: { open = $0 })) {
          if let description = heading.description { Note(description) }
          content
        } label: {
          Text(heading.title).fontWeight(.semibold)
        }
      }
    } else {
      content
    }
  }

  @ViewBuilder private var content: some View {
    ForEach(Array(group.fields.enumerated()), id: \.offset) { _, field in
      StyleSettingRow(field: field, values: values, shipped: shipped, onChange: onChange)
    }
    ForEach(group.children) { child in
      AnyView(StyleSettingsGroupView(group: child, values: values, shipped: shipped, forceOpen: forceOpen, onChange: onChange))
    }
  }
}

struct StyleSettingRow: View {
  let field: StyleSettingsValues.Field
  let values: JSONObject
  let shipped: Set<String>
  let onChange: ([(key: String, value: JSONValue?)]) -> Void

  private var key: String { StyleSettingsValues.optionKey(field) }

  var body: some View {
    if field.kind == "info-text" {
      Note(field.description.map { "\(field.title) — \($0)" } ?? field.title)
    } else {
      let keys = StyleSettingsValues.keysOf(field)
      let isSet = keys.contains { values[$0] != nil }
      VStack(alignment: .leading, spacing: 2) {
        LabeledContent {
          HStack {
            control
            if isSet {
              Button(L10n.t("styles.styleSettings.reset")) { onChange(keys.map { ($0, nil) }) }
                .buttonStyle(.link).font(.caption)
            }
          }
        } label: {
          Text(field.title).help(field.id)
        }
        if let description = field.description { Text(description).font(.caption).foregroundStyle(.secondary) }
      }
    }
  }

  @ViewBuilder private var control: some View {
    switch field.kind {
    case "class-toggle":
      Toggle(field.title, isOn: Binding(get: { values[key] == .bool(true) }, set: { onChange([(key, $0 ? .bool(true) : nil)]) }))
        .labelsHidden()
    case "class-select", "variable-select":
      // A class select stores the option's class key, and core emits it only when the port ships it.
      let options = field.kind == "class-select" ? field.options.filter { shipped.contains($0.value) } : field.options
      if !options.isEmpty || field.kind == "variable-select" {
        Picker(field.title, selection: Binding(get: { values[key]?.stringValue ?? "" }, set: { onChange([(key, $0.isEmpty ? nil : .string($0))]) })) {
          Text(L10n.t("styles.styleSettings.themeDefault")).tag("")
          ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
      }
    case "variable-number", "variable-number-slider":
      numberControl
    case "variable-text":
      TextField(field.title, text: Binding(get: { values[key]?.stringValue ?? "" }, set: { onChange([(key, $0.isEmpty ? nil : .string($0))]) }),
                prompt: Text(field.defaultValue?.stringValue ?? ""))
        .labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: 220)
    case "variable-color":
      colorControl(mode: nil, label: nil)
    case "variable-themed-color":
      HStack(spacing: 12) {
        colorControl(mode: .light, label: L10n.t("styles.variables.light"))
        colorControl(mode: .dark, label: L10n.t("styles.variables.dark"))
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder private var numberControl: some View {
    let stored = values[key]
    let text = stored.map { $0.stringValue ?? $0.numberValue.map(JSONValue.number).map(JSJSON.compact) ?? "" } ?? ""
    let placeholder = field.defaultValue.map { $0.stringValue ?? JSJSON.compact($0) } ?? ""
    HStack {
      if field.kind == "variable-number-slider", let min = field.min, let max = field.max, min < max {
        let current = Double(text) ?? Double(placeholder) ?? min
        Slider(value: Binding(get: { Swift.min(Swift.max(current, min), max) }, set: { onChange([(key, .number(($0 / (field.step ?? 1)).rounded() * (field.step ?? 1)))]) }),
               in: min...max)
          .frame(width: 140)
      }
      TextField(field.title, text: Binding(get: { text }, set: { next in
        if next.isEmpty { onChange([(key, nil)]) } else if let number = Double(next) { onChange([(key, .number(number))]) }
      }), prompt: Text(placeholder))
        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 70)
    }
  }

  private func colorControl(mode: StyleSettingsValues.Mode?, label: String?) -> some View {
    let read = StyleSettingsValues.readColor(field, values: values, mode: mode)
    return HStack(spacing: 4) {
      if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
      ColorPicker(selection: Binding(get: { CssColorField.color(read.hex ?? "") }, set: { color in
        let css = CssColorField.css(color)
        let hex = css.hasPrefix("#") ? css : (CssColor.hexAlpha(css)?.hex ?? "#000000")
        onChange(StyleSettingsValues.colorPatch(field, hex: hex, mode: mode))
      }), supportsOpacity: false) {
        Text(field.title)
      }
      .labelsHidden()
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(read.isSet ? Color.green : .clear))
    }
  }
}
