import QuartzHubCore
import SwiftUI

/// The selected entry in the inspector (QuartzControl's `PluginPanel`): what it is, where it
/// sits, and its options. A component's placement is one line and the way to the Layout page, where
/// it is set; a frame is set up there too and only says so. The four own plugins have tabs of their
/// own: their options lead there, the whole form folded below (docs/plan-eine-stelle.md; until
/// 2026-11-16 Quartz's five placement fields and `groupOptions` stood here as well).
///
/// Every field writes on its own through the model's queue; there is no Save on this tab, and the
/// inspector says so beside the name.
struct PluginInspector: View {
  let item: IndexedPlugin
  @Bindable var model: PluginsModel
  /// The entry on its own tab (the four own plugins).
  var editOnTab: () -> Void = {}
  @Environment(\.openLayout) private var openLayout
  @Environment(\.openPage) private var openPage
  @Environment(\.openURL) private var openURL

  /// One choice for every own plugin: whoever opens the whole form wants it again.
  @SceneStorage("plugins.allOptionsOpen") private var allOptionsOpen = false
  @State private var schema: PluginOptionSchemaResult?
  @State private var schemaError: String?

  private var busy: Bool { model.busy || model.maintenance != nil }

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          TitleLine(saved: model.savedIndex == item.index) {
            Label(item.displayName, systemImage: item.frame != nil ? "rectangle.split.3x3" : item.layout != nil ? "square.stack.3d.up" : "puzzlepiece.extension")
              .font(.headline)
              .accessibilityIdentifier("plugins.inspector.name")
          }
          if item.frame != nil || model.outdated.contains(item.entry.name) {
            HStack(spacing: 6) {
              if item.frame != nil { WordBadge(text: L10n.t("pluginsInstalled.frameBadge")) }
              if model.outdated.contains(item.entry.name) { WordBadge(text: L10n.t("pluginsInstalled.updateAvailable"), tint: .orange) }
            }
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

      if model.builtin(item) != nil {
        Section {
          Note(L10n.t("pluginsInstalled.builtinInspector"))
          Button(L10n.t("pluginsInstalled.builtinOpenConfig")) { openPage(.config) }
          BuiltinMigration(project: model.project, pending: model.pendingMigrations, blockedByEdits: busy) { await model.reload() }
        } header: {
          Text(L10n.t("pluginsInstalled.builtinBadge"))
        }
      }

      let findings = model.findings(item)
      if !findings.isEmpty {
        Section {
          // The intended one once: it is the same sentence for every further entry.
          let shown = findings.filter { !$0.intended } + findings.filter(\.intended).prefix(1)
          ForEach(Array(shown.enumerated()), id: \.offset) { _, finding in
            VStack(alignment: .leading, spacing: 2) {
              if finding.intended {
                Label(finding.message, systemImage: "info.circle").foregroundStyle(.secondary).textSelection(.enabled)
              } else {
                Label(finding.message, systemImage: finding.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                  .foregroundStyle(finding.severity == .error ? .red : .orange)
                  .textSelection(.enabled)
                // Quartz's hint for a frame is `plugin install`; QuartzHub writes its frames itself.
                if let hint = finding.hint, item.frame == nil {
                  Text(verbatim: hint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
              }
            }
          }
          if item.frame != nil { Note(L10n.t("pluginsInstalled.doctorFrameHint")) }
          if findings.contains(where: \.intended) { Note(L10n.t("pluginsInstalled.doctorIntendedHint")) }
        } header: {
          Text(L10n.t("pluginsInstalled.doctorHeading"))
        } footer: {
          Text(L10n.t("pluginsInstalled.doctorFooter")).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("plugins.inspector.doctor")
      }

      if item.frame != nil {
        Section {
          Note(L10n.t("pluginsInstalled.framesDescription"))
          Button(L10n.t("pluginsInstalled.openInLayoutEditor")) { openLayout(.frame(item.frame?["id"]?.stringValue ?? "")) }
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

  /// Where the component stands, in the words of the list's row; it is set on the Layout page.
  private func placement(_ layout: JSONObject) -> some View {
    Section(L10n.t("pluginsInstalled.placementHeading")) {
      Text(placementSummary(layout)).foregroundStyle(.secondary)
      Button(L10n.t("pluginsInstalled.showOnStage")) { openLayout(.component(model.config?.plugins ?? [], item.index)) }
    }
  }

  private func placementSummary(_ layout: JSONObject) -> String {
    // "undefined" and an empty "Priorität" for what the file does not say (review 2026-11-13,
    // nebenbei): the words of the list's row.
    var parts = [InstalledTab.placementLine(layout)]
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
        Callout(.error, L10n.t("layoutEditor.inspector.optionsError", ["reason": schemaError]))
      }
    } else if let schema, schema.notInstalled {
      Section(L10n.t("pluginsInstalled.optionsHeading")) {
        Callout(.warning, L10n.t("pluginsInstalled.packageNotInstalled"))
      }
    } else if let schema, PluginsPage.tab(for: item.entry) != .installed {
      let tab = PluginsPage.tab(for: item.entry)
      Section(L10n.t("pluginsInstalled.optionsHeading")) {
        OptionsSummary(entry: item.entry)
        Note(L10n.t("pluginsInstalled.ownTabHint"))
        Button(L10n.t("layoutEditor.inspector.editOptions", ["tab": tab.title]), action: editOnTab)
          .accessibilityIdentifier("plugins.inspector.editOnTab")
        Fold(isExpanded: $allOptionsOpen) {
          EmptyView()
        } label: {
          Text(L10n.t("pluginsInstalled.allOptions"))
        }
        .accessibilityIdentifier("plugins.inspector.allOptions")
      }
      if allOptionsOpen { form(schema, heading: false) }
    } else if let schema {
      form(schema)
    } else {
      Section(L10n.t("pluginsInstalled.optionsHeading")) {
        Text(L10n.t("layoutEditor.inspector.optionsLoading")).foregroundStyle(.secondary)
      }
    }
  }

  /// The whole form; `heading` false below the own plugins' summary, which has the heading.
  @ViewBuilder private func form(_ schema: PluginOptionSchemaResult, heading: Bool = true) -> some View {
    if let unreadable = schema.unreadable {
      Section(L10n.t("pluginsInstalled.optionsHeading")) {
        Callout(.warning, L10n.t("pluginOptions.unreadable", ["reason": unreadable]))
      }
    } else if heading {
      Section {} header: { Text(L10n.t("pluginsInstalled.optionsHeading")) }
    }
    OptionsForm(schema: schema.schema, values: item.entry.object["options"]?.objectValue ?? JSONObject(),
                onChange: { next in set(["options"], next.map(JSONValue.object)) },
                explicitEmpty: true, languages: model.config?.siteLanguages ?? [],
                root: OptionRoot.withoutTiles(item.entry, fields: schema.schema?.fields ?? [], packageVersion: schema.packageVersion,
                                              lang: L10n.language == "en" ? .en : .de),
                projectPath: model.project.path)
  }

  private func loadSchema() async {
    schema = nil
    schemaError = nil
    // An empty reason read "Die Optionen konnten nicht gelesen werden: " (review 2026-11-13).
    guard let source = PluginSource(item.entry.source) else {
      schemaError = L10n.t("pluginsInstalled.sourceUnreadable")
      return
    }
    let environment = await AppServices.current()
    schema = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime)
  }
}

/// What an entry's options set, in one or two lines: a navigation's variant, how many options it
/// sets. Where the options are not edited (Layout, Installiert for the own plugins), above the
/// way to where they are. Set, not changed: a key with the plugin's default counts as well, as in
/// the steps' „Gesetzte Optionen“ (review 2026-11-17, N2).
struct OptionsSummary: View {
  let entry: PluginEntry

  var body: some View {
    let options = entry.object["options"]?.objectValue ?? JSONObject()
    if PluginsPage.tab(for: entry) == .navigations {
      LabeledContent(L10n.t("navigationsEditor.variantHeading"),
                     value: NavigationVariants.catalog(NavigationVariants.label(NavigationVariants.variant(options)), nil))
    }
    Text(options.keys.isEmpty ? L10n.t("layoutEditor.inspector.optionsNone")
         : L10n.t("layoutEditor.inspector.optionsCount", ["count": String(options.keys.count)], count: options.keys.count))
      .foregroundStyle(.secondary)
  }
}
