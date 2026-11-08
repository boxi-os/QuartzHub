import QuartzHubCore
import SwiftUI

/// The selected entry in the inspector (QuartzControl's `PluginPanel`): what it is, where it
/// sits, and its options. A component's placement is Quartz's own five fields and `groupOptions`;
/// a frame is set up on the Layout page and only says so.
///
/// Every field writes on its own through the model's queue; there is no Save on this tab, and the
/// inspector says so beside the name.
struct PluginInspector: View {
  let item: IndexedPlugin
  @Bindable var model: PluginsModel
  @Environment(\.openPage) private var openPage
  @Environment(\.openURL) private var openURL

  /// One choice for every plugin: whoever opens it wants to see placements.
  @SceneStorage("plugins.placementOpen") private var placementOpen = false
  @State private var schema: PluginOptionSchemaResult?
  @State private var schemaError: String?

  private var busy: Bool { model.busy || model.maintenance != nil }

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(item.displayName, systemImage: item.frame != nil ? "rectangle.split.3x3" : item.layout != nil ? "square.stack.3d.up" : "puzzlepiece.extension")
            .font(.headline)
            .accessibilityIdentifier("plugins.inspector.name")
          HStack(spacing: 6) {
            if item.frame != nil { WordBadge(text: L10n.t("pluginsInstalled.frameBadge")) }
            if model.outdated.contains(item.entry.name) { WordBadge(text: L10n.t("pluginsInstalled.updateAvailable")).foregroundStyle(.orange) }
            if model.savedIndex == item.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          }
          Note(L10n.t("plugins.savesImmediately"))
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(item.frame != nil ? L10n.t("pluginsInstalled.frameSource") : item.sourceLabel)
              .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let url = PluginRepository.url(item.entry.source), let link = URL(string: url) {
              Button { openURL(link) } label: {
                Label(L10n.t("pluginsInstalled.openRepo"), systemImage: "arrow.up.right.square").labelStyle(.iconOnly)
              }
              .buttonStyle(.borderless)
              .help(L10n.t("pluginsInstalled.openRepo"))
            }
          }
          if let description = item.description { Text(description).foregroundStyle(.secondary) }
        }
        Toggle(L10n.t("pluginsInstalled.panelEnabled"), isOn: Binding(get: { item.enabled }, set: { _ in
          Task { await model.toggleEnabled(item.index) }
        }))
        .disabled(busy)
        .accessibilityIdentifier("plugins.inspector.enabled")
      }

      if item.frame != nil {
        Section {
          Note(L10n.t("pluginsInstalled.framesDescription"))
          Button(L10n.t("pluginsInstalled.openInLayoutEditor")) { openPage(.layout) }
        }
      }

      if let layout = item.layout { placement(layout) }

      if item.frame == nil { options }
    }
    .formStyle(.grouped)
    .disabled(busy)
    .task(id: item.id + "|" + (item.entry.source.map(JSJSON.compact) ?? "")) { await loadSchema() }
  }

  // MARK: Placement

  private static let positions = ["header", "left", "right", "beforeBody", "afterBody", "footer"]
  private static let displays = ["all", "mobile-only", "desktop-only"]

  /// Folded by default: the Layout page is where placement is set by dragging; folded, one line
  /// says where the component stands.
  private func placement(_ layout: JSONObject) -> some View {
    Section {
      DisclosureGroup(isExpanded: $placementOpen) {
        VStack(alignment: .leading, spacing: 12) {
          LayoutField(key: "position", kind: .choice(Self.positions), value: layout["position"],
                      hint: L10n.t("pluginsInstalled.layoutFields.position")) { set(["layout", "position"], $0) }
          LayoutField(key: "priority", kind: .number, value: layout["priority"],
                      hint: L10n.t("pluginsInstalled.layoutFields.priority")) { set(["layout", "priority"], $0) }
          LayoutField(key: "display", kind: .choice(Self.displays), value: layout["display"],
                      hint: L10n.t("pluginsInstalled.layoutFields.display")) { set(["layout", "display"], $0) }
          LayoutField(key: "condition", kind: .text, value: layout["condition"],
                      hint: L10n.t("pluginsInstalled.layoutFields.condition")) { set(["layout", "condition"], $0) }
          LayoutField(key: "group", kind: .text, value: layout["group"],
                      hint: L10n.t("pluginsInstalled.layoutFields.group")) { set(["layout", "group"], $0) }
          // groupOptions only once the component is placed in a group.
          if let group = layout["group"], group != .null, JSRead.string(group) != "" {
            Divider()
            Text(verbatim: "groupOptions").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            let options = layout["groupOptions"]?.objectValue ?? JSONObject()
            ForEach(Self.groupOptions, id: \.key) { field in
              LayoutField(key: field.key, kind: field.kind, value: options[field.key], hint: field.hint) {
                set(["layout", "groupOptions", field.key], $0)
              }
            }
          }
        }
        .padding(.top, 6)
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.t("pluginsInstalled.placementHeading")).fontWeight(.medium)
          if !placementOpen {
            Text(placementSummary(layout)).font(.callout).foregroundStyle(.secondary)
          }
        }
      }
      Button(L10n.t("pluginsInstalled.showOnStage")) { openPage(.layout) }
    }
  }

  private static var groupOptions: [(key: String, kind: LayoutField.Kind, hint: String)] {
    [("grow", .toggle, L10n.t("pluginsInstalled.groupOptionsFields.grow")),
     ("shrink", .toggle, L10n.t("pluginsInstalled.groupOptionsFields.shrink")),
     ("basis", .text, L10n.t("pluginsInstalled.groupOptionsFields.basis")),
     ("order", .number, L10n.t("pluginsInstalled.groupOptionsFields.order")),
     ("align", .text, L10n.t("pluginsInstalled.groupOptionsFields.align")),
     ("justify", .text, L10n.t("pluginsInstalled.groupOptionsFields.justify"))]
  }

  private func placementSummary(_ layout: JSONObject) -> String {
    var parts = [InstalledTab.positionTitle(layout["position"].map { JSRead.string($0) } ?? "undefined"),
                 L10n.t("pluginsInstalled.placementPriority", ["priority": layout["priority"].map { JSRead.string($0) } ?? ""])]
    if let group = layout["group"], JSRead.string(group) != "", group != .null {
      parts.append(L10n.t("pluginsInstalled.placementGroup", ["group": JSRead.string(group)]))
    }
    return parts.joined(separator: " · ")
  }

  private func set(_ path: [String], _ value: JSONValue?) {
    Task { await model.updateField(item.index, path: path, value: value) }
  }

  // MARK: Options

  @ViewBuilder private var options: some View {
    if let schemaError {
      Section(L10n.t("pluginsInstalled.optionsHeading")) {
        Text(L10n.t("layoutEditor.inspector.optionsError", ["reason": schemaError])).foregroundStyle(.red)
      }
    } else if let schema {
      if let unreadable = schema.unreadable {
        Section(L10n.t("pluginsInstalled.optionsHeading")) {
          Text(L10n.t("pluginOptions.unreadable", ["reason": unreadable])).font(.callout).foregroundStyle(.orange)
        }
      } else {
        Section {} header: { Text(L10n.t("pluginsInstalled.optionsHeading")) }
      }
      OptionsForm(schema: schema.schema, values: item.entry.object["options"]?.objectValue ?? JSONObject(),
                  onChange: { next in set(["options"], next.map(JSONValue.object)) },
                  explicitEmpty: true, languages: model.config?.siteLanguages ?? [])
    } else {
      Section(L10n.t("pluginsInstalled.optionsHeading")) {
        Text(L10n.t("layoutEditor.inspector.optionsLoading")).foregroundStyle(.secondary)
      }
    }
  }

  private func loadSchema() async {
    schema = nil
    schemaError = nil
    guard let source = PluginSource(item.entry.source) else {
      schemaError = ""
      return
    }
    let environment = await AppServices.current()
    schema = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime)
  }
}

/// One of Quartz's placement fields: the key is the label, the hint under the control.
private struct LayoutField: View {
  enum Kind {
    case choice([String]), number, text, toggle
  }

  let key: String
  let kind: Kind
  let value: JSONValue?
  let hint: String
  let write: (JSONValue?) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: key).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
      control
      Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var control: some View {
    switch kind {
    case .choice(let values):
      let current = value?.stringValue.flatMap { values.contains($0) ? $0 : nil } ?? ""
      Picker(key, selection: Binding(get: { current }, set: { write(.string($0)) })) {
        Text(L10n.t("pluginsInstalled.notSet")).tag("").selectionDisabled()
        ForEach(values, id: \.self) { Text(verbatim: $0).tag($0) }
      }
      .labelsHidden()
      .fixedSize()
    case .number:
      CommitField(name: key, text: value.map { JSRead.string($0) } ?? "") { raw in
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { write(nil); return true }
        guard let number = Double(trimmed), number.isFinite else { return false }
        write(.number(number))
        return true
      }
      .frame(maxWidth: 130)
    case .text:
      CommitField(name: key, text: value.map { JSRead.string($0) } ?? "") { raw in
        write(raw.isEmpty ? nil : .string(raw))
        return true
      }
    case .toggle:
      Toggle(key, isOn: Binding(get: { value == .bool(true) || value == .string("true") }, set: { write(.bool($0)) }))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
  }
}
