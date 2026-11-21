import AppKit
import QuartzHubCore
import SwiftUI

/// The selection of a plugin variable in the Variables tab, which shares one selection
/// (`styles.vars.selected`) with the other two lists: `plugin|<plugin>|<name>`.
enum PluginVariableKey {
  static let prefix = "plugin|"

  static func make(_ plugin: String, _ name: String) -> String { "\(prefix)\(plugin)|\(name)" }

  static func parse(_ key: String) -> (plugin: String, name: String)? {
    guard key.hasPrefix(prefix), let bar = key.lastIndex(of: "|") else { return nil }
    let plugin = String(key[key.index(key.startIndex, offsetBy: prefix.count)..<bar])
    let name = String(key[key.index(after: bar)...])
    return plugin.isEmpty && name.isEmpty ? nil : (plugin, name)
  }

  /// The plugin and variable a key names in what was read, nil when it is gone.
  static func find(_ key: String, in result: PluginVariables.Result?) -> (PluginVariables.Plugin, PluginVariables.Variable)? {
    guard let (pluginName, name) = parse(key), let result else { return nil }
    for plugin in PluginVariablesSection.ordered(result) where plugin.name == pluginName {
      if let variable = plugin.variables.first(where: { $0.name == name }) { return (plugin, variable) }
    }
    return nil
  }
}

/// "Plugin-Variablen" on the Variables tab (docs/plan-plugin-variablen.md, B3): a fold per plugin,
/// a described plugin's variables under its groups in its own order, each with its description.
struct PluginVariablesSection: View {
  let model: StylesModel
  let place: VariablesPlace

  /// The unattributed ones as a plugin without a name, last.
  static let unattributedName = ""

  /// Described plugins first (their order is the config's), then those read from the build, then
  /// Quartz's own and the unattributed ones.
  static func ordered(_ result: PluginVariables.Result) -> [PluginVariables.Plugin] {
    let described = result.plugins.filter(\.described)
    let others = result.plugins.filter { !$0.described && $0.name != "quartz" }
    let quartz = result.plugins.filter { !$0.described && $0.name == "quartz" }
    let unattributed = result.unattributed.isEmpty ? [] : [PluginVariables.Plugin(name: unattributedName, displayName: nil, groups: [],
                                                                                    variables: result.unattributed, described: false)]
    return described + others + quartz + unattributed
  }

  static func label(_ plugin: PluginVariables.Plugin) -> String {
    plugin.name == unattributedName ? L10n.t("styles.variables.pluginsUnattributed") : (plugin.displayName ?? plugin.name)
  }

  static var german: Bool { L10n.language == "de" }

  static func description(_ variable: PluginVariables.Variable) -> String? {
    let text = german ? (variable.descriptionDe ?? variable.description) : (variable.description ?? variable.descriptionDe)
    return text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
  }

  var body: some View {
    let result = model.pluginVariables
    let plugins = result.map(Self.ordered) ?? []
    let total = plugins.reduce(0) { $0 + $1.variables.count }
    Section {
      Fold(isExpanded: place.pluginsOpen) {
        Note(L10n.t("styles.variables.pluginsDescription"))
        if model.graphLoading {
          Note(L10n.t("common.loading"))
        } else if plugins.isEmpty {
          Note(L10n.t("styles.variables.pluginsNone"))
          if result?.sources.build == false { Note(L10n.t("styles.variables.pluginsNoBuild")) }
        } else {
          if result?.sources.build == false { Note(L10n.t("styles.variables.pluginsNoBuild")) }
          let query = VariableResolve.normalizeQuery(place.query.wrappedValue)
          ForEach(plugins, id: \.name) { plugin in
            let matching = query.isEmpty ? plugin.variables : plugin.variables.filter { Self.matches($0, query) }
            if !matching.isEmpty {
              // While searching, every plugin with a match is open; its own state is kept.
              Fold(isExpanded: query.isEmpty ? VariablesPlace.member(place.openPlugins, plugin.name) : .constant(true)) {
                ForEach(Self.sections(plugin, matching), id: \.id) { section in
                  if let label = section.label {
                    Text(label).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  ForEach(section.variables, id: \.name) { variable in row(plugin, variable) }
                }
              } label: {
                HStack(spacing: 8) {
                  Text(Self.label(plugin)).fontWeight(.semibold)
                  Text("\(matching.count)").foregroundStyle(.secondary).monospacedDigit()
                }
              }
            }
          }
        }
      } label: {
        HStack {
          Text(L10n.t("styles.variables.pluginsHeading")).fontWeight(.semibold)
          Spacer()
          if total > 0 { Text("\(total)").font(.callout).foregroundStyle(.secondary).monospacedDigit() }
        }
      }
      .accessibilityIdentifier("variables.plugins")
    }
  }

  static func matches(_ variable: PluginVariables.Variable, _ query: String) -> Bool {
    variable.name.lowercased().contains(query) || (description(variable)?.lowercased().contains(query) ?? false)
  }

  struct Part {
    var id: String
    var label: String?
    var variables: [PluginVariables.Variable]
  }

  /// A described plugin's groups in its order, the variables without a known group last under
  /// "Weitere"; a plugin read from the build is one list.
  static func sections(_ plugin: PluginVariables.Plugin, _ variables: [PluginVariables.Variable]) -> [Part] {
    guard plugin.described, !plugin.groups.isEmpty else { return [Part(id: "", label: nil, variables: variables)] }
    var parts = plugin.groups.map { Part(id: $0.id, label: german ? $0.labelDe : $0.label, variables: []) }
    var rest: [PluginVariables.Variable] = []
    for variable in variables {
      if let index = parts.firstIndex(where: { $0.id == variable.group }) { parts[index].variables.append(variable) } else { rest.append(variable) }
    }
    if !rest.isEmpty { parts.append(Part(id: "\u{0}other", label: L10n.t("styles.variables.pluginOther"), variables: rest)) }
    return parts.filter { !$0.variables.isEmpty }
  }

  private func row(_ plugin: PluginVariables.Plugin, _ variable: PluginVariables.Variable) -> some View {
    let key = PluginVariableKey.make(plugin.name, variable.name)
    return PluginVariableRowView(variable: variable, model: model, selected: place.selected.wrappedValue == key) {
      place.selected.wrappedValue = place.selected.wrappedValue == key ? nil : key
    }
    .id("var-\(key)")
  }
}

/// A plugin variable's swatch, resolved over the page's `:root` values (`var(--tpl-icon)` included).
enum PluginVariableValue {
  static func value(_ variable: PluginVariables.Variable, _ mode: VariableResolve.Mode) -> String? {
    mode == .dark ? (variable.dark ?? variable.light) : variable.light
  }

  /// What the page's value makes of it in a mode: its own value, else the plugin's.
  static func current(_ variable: PluginVariables.Variable, _ override: PluginVariableOverride?, _ mode: VariableResolve.Mode) -> String? {
    guard let o = override else { return value(variable, mode) }
    let light = o.light.trimmingCharacters(in: .whitespaces), dark = (o.dark ?? "").trimmingCharacters(in: .whitespaces)
    if mode == .dark { return !dark.isEmpty ? dark : (o.lightOnly || light.isEmpty ? value(variable, .dark) : light) }
    return light.isEmpty ? value(variable, .light) : light
  }

  /// The plugin's value, or with `override` the page's, resolved.
  static func resolved(_ variable: PluginVariables.Variable, _ mode: VariableResolve.Mode, _ ctx: VariableResolve.Context,
                       _ override: PluginVariableOverride? = nil) -> String? {
    VariableResolve.resolveValueLiteral(current(variable, override, mode), mode, ctx)
  }

  static func isColor(_ variable: PluginVariables.Variable, _ ctx: VariableResolve.Context) -> Bool {
    if let kind = variable.kind { return kind == "color" }
    return CssColor.isDisplayable(resolved(variable, .light, ctx))
  }
}

/// One plugin variable in the list: swatches, name, the plugin's value, whether the project sets
/// it too, and its description.
struct PluginVariableRowView: View {
  let variable: PluginVariables.Variable
  let model: StylesModel
  let selected: Bool
  let select: () -> Void

  var body: some View {
    let ctx = model.context
    let showsColor = PluginVariableValue.isColor(variable, ctx)
    let override = model.pluginOverride(selector: variable.selector, key: variable.name)
    Button(action: select) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          HStack(spacing: 2) {
            VariableSwatch(value: showsColor ? PluginVariableValue.resolved(variable, .light, ctx, override) : nil, ground: VariableResolve.pageGround(.light, ctx))
            VariableSwatch(value: showsColor ? PluginVariableValue.resolved(variable, .dark, ctx, override) : nil, ground: VariableResolve.pageGround(.dark, ctx))
          }
          .opacity(showsColor ? 1 : 0)
          Text("--\(variable.name)").font(.system(.body, design: .monospaced))
          Text(override.map(\.light).flatMap { $0.isEmpty ? nil : $0 } ?? variable.light ?? L10n.t("styles.variables.pluginInspector.unset"))
            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
          Spacer(minLength: 4)
          if override != nil {
            StateBadge(text: L10n.t("styles.variables.pluginChanged"), color: .green).font(.caption)
          } else if !model.projectRules(variable).isEmpty {
            StateBadge(text: L10n.t("styles.variables.pluginSetByProject"), color: .gray).font(.caption)
          }
        }
        if let description = PluginVariablesSection.description(variable) {
          Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            .padding(.leading, 34)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.vertical, 2)
    .padding(.horizontal, 4)
    .background(selected ? Color.accentColor.opacity(0.22) : (override != nil ? Color.green.opacity(0.08) : Color.clear), in: RoundedRectangle(cornerRadius: 5))
    .accessibilityIdentifier("variables.pluginRow.\(variable.name)")
  }
}

/// The selected plugin variable: what it is for, the plugin's values in both modes, where the
/// plugin sets it, which rules of the project set it too, and a rule to copy.
struct PluginVariableInspector: View {
  let plugin: PluginVariables.Plugin
  let variable: PluginVariables.Variable
  let model: StylesModel
  /// A dark field asked for before a dark value is typed.
  @State private var splitDark = false

  private var override: PluginVariableOverride? { model.pluginOverride(selector: variable.selector, key: variable.name) }

  var snippet: String {
    "\(variable.selector) {\n  --\(variable.name): \(PluginVariableValue.current(variable, override, .light) ?? "");\n}"
  }

  /// Writes one half; both halves empty is no override.
  private func set(light: String? = nil, dark: String?? = .none) {
    var next = override ?? PluginVariableOverride(selector: variable.selector, key: variable.name, light: "")
    if let light { next.light = light }
    if case .some(let value) = dark { next.dark = value }
    let empty = next.light.trimmingCharacters(in: .whitespaces).isEmpty && (next.dark ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    model.setPluginOverride(selector: variable.selector, key: variable.name, empty && !splitDark ? nil : next)
  }

  private func field(_ mode: VariableResolve.Mode, label: String, ctx: VariableResolve.Context) -> some View {
    let text = mode == .light ? (override?.light ?? "") : (override?.dark ?? "")
    let placeholder = PluginVariableValue.value(variable, mode) ?? ""
    let resolved = VariableResolve.resolveValueLiteral(text.isEmpty ? placeholder : text, mode, ctx)
    let isColor = PluginVariableValue.isColor(variable, ctx)
    let unsafe = !text.trimmingCharacters(in: .whitespaces).isEmpty && !PluginVariableOverrides.isSafeValue(text)
    return VStack(alignment: .leading, spacing: 4) {
      LabeledContent(label) {
        HStack(spacing: 6) {
          if isColor {
            ColorPicker(selection: Binding(get: { CssColorField.color(resolved ?? placeholder) },
                                           set: { mode == .light ? set(light: CssColorField.css($0)) : set(dark: .some(CssColorField.css($0))) }),
                        supportsOpacity: true) { Text(label) }
              .labelsHidden()
          }
          TextField(label, text: Binding(get: { text }, set: { mode == .light ? set(light: $0) : set(dark: .some($0)) }),
                    prompt: Text(placeholder))
            .labelsHidden().textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityIdentifier("variables.pluginValue.\(mode == .light ? "light" : "dark")")
        }
      }
      if unsafe { FieldProblem(L10n.t("styles.variables.pluginInspector.unsafe")) }
    }
  }

  /// The project's rules that beat the page's value, per mode.
  private func stronger(_ mode: String) -> [PluginVariables.Setter] {
    guard let override else { return [] }
    let custom = model.customSelectors[variable.name] ?? []
    return PluginVariableCascade.stronger(override, setBy: model.projectRules(variable), mode: mode) { custom.contains(PluginVariableCascade.normalized($0.rule)) }
  }

  var body: some View {
    let ctx = model.context
    let showsColor = PluginVariableValue.isColor(variable, ctx)
    let differs = variable.dark != nil && variable.dark != variable.light
    Form {
      Section {
        HStack {
          if showsColor {
            VariableSwatch(value: PluginVariableValue.resolved(variable, .light, ctx, override), ground: VariableResolve.pageGround(.light, ctx), size: 14)
            VariableSwatch(value: PluginVariableValue.resolved(variable, .dark, ctx, override), ground: VariableResolve.pageGround(.dark, ctx), size: 14)
          }
          Text("--\(variable.name)").font(.system(.title3, design: .monospaced)).textSelection(.enabled)
        }
        if let description = PluginVariablesSection.description(variable) { Note(description) }
        LabeledContent(L10n.t("styles.variables.pluginInspector.plugin"), value: PluginVariablesSection.label(plugin))
      }
      Section(L10n.t("styles.variables.pluginInspector.default")) {
        let modes: [VariableResolve.Mode] = differs ? [.light, .dark] : [.light]
        ForEach(modes, id: \.self) { mode in
          let raw = PluginVariableValue.value(variable, mode)
          let resolved = PluginVariableValue.resolved(variable, mode, ctx)
          LabeledContent(differs ? (mode == .light ? L10n.t("styles.variables.light") : L10n.t("styles.variables.dark")) : L10n.t("styles.variables.bothModes")) {
            HStack(spacing: 6) {
              if CssColor.isDisplayable(resolved) { VariableSwatch(value: resolved, ground: VariableResolve.pageGround(mode, ctx), size: 14) }
              Text(raw ?? L10n.t("styles.variables.pluginInspector.unset")).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
              if let resolved, resolved != raw {
                Text("→ \(resolved)").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
              }
            }
          }
        }
        LabeledContent(L10n.t("styles.variables.pluginInspector.selector")) {
          Text(variable.selector).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        }
      }
      Section(L10n.t("styles.variables.pluginInspector.setBy")) {
        let rules = model.projectRules(variable)
        if rules.isEmpty {
          Note(L10n.t("styles.variables.pluginInspector.setByNone"))
        } else {
          Note(L10n.t("styles.variables.pluginInspector.setByNote"))
          ForEach(Array(rules.enumerated()), id: \.offset) { _, setter in
            LabeledContent(setter.mode == "dark" ? "\(setter.selector) (\(L10n.t("styles.variables.dark")))" : setter.selector) {
              Text(setter.value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
            .font(.system(.callout, design: .monospaced))
          }
        }
      }
      if !variable.alsoAt.isEmpty {
        Section(L10n.t("styles.variables.pluginInspector.alsoAt")) {
          ForEach(variable.alsoAt.prefix(24), id: \.self) { selector in
            Text(selector).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
          }
          if variable.alsoAt.count > 24 { Note(L10n.t("styles.variables.moreKeys", count: variable.alsoAt.count - 24)) }
        }
      }
      Section(L10n.t("styles.variables.section.edit")) {
        let split = splitDark || !(override?.dark ?? "").isEmpty
        field(.light, label: split ? L10n.t("styles.variables.light") : L10n.t("styles.variables.bothModes"), ctx: ctx)
        if split { field(.dark, label: L10n.t("styles.variables.dark"), ctx: ctx) }
        if !split {
          Button(L10n.t("styles.variables.splitDark")) { splitDark = true }.buttonStyle(.link)
        } else {
          Button(L10n.t("styles.variables.unsplitDark")) {
            splitDark = false
            set(dark: .some(nil))
          }
          .buttonStyle(.link)
        }
        let light = stronger("light"), dark = stronger("dark").filter { d in !light.contains(d) }
        if !light.isEmpty {
          Callout(.warning, L10n.t("styles.variables.pluginInspector.stronger", ["rules": light.map(\.rule).joined(separator: ", ")]))
        }
        if !dark.isEmpty {
          Callout(.warning, L10n.t("styles.variables.pluginInspector.strongerDark", ["rules": dark.map(\.rule).joined(separator: ", ")]))
        }
        if override != nil {
          Button(L10n.t("styles.variables.resetToOriginal")) {
            splitDark = false
            model.setPluginOverride(selector: variable.selector, key: variable.name, nil)
          }
          .accessibilityIdentifier("variables.pluginReset")
        }
      }
      Section(L10n.t("styles.variables.pluginInspector.snippet")) {
        Text(snippet).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        Note(L10n.t("styles.variables.pluginInspector.snippetNote"))
        Button(L10n.t("styles.variables.pluginInspector.copy")) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(snippet, forType: .string)
          Announce.post(L10n.t("styles.variables.pluginInspector.copied"))
        }
      }
    }
    .formStyle(.grouped)
  }
}
