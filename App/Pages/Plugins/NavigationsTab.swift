import QuartzHubCore
import SwiftUI

/// One navigation: one config entry of quartz-navigations.
struct NavigationInstance: Identifiable {
  let entry: PluginEntry
  let index: Int
  /// 1-based among the navigations, in config order: the "#n" the list and the stage show.
  let occurrence: Int
  var id: Int { occurrence }

  var options: JSONObject { entry.object["options"]?.objectValue ?? JSONObject() }
  var variant: NavigationVariants.Variant { NavigationVariants.variant(options) }

  static func all(_ plugins: [PluginEntry]) -> [NavigationInstance] {
    var out: [NavigationInstance] = []
    for (index, entry) in plugins.enumerated() where PluginSource(entry.source)?.quartzName == NavigationVariants.plugin {
      out.append(NavigationInstance(entry: entry, index: index, occurrence: out.count + 1))
    }
    return out
  }

  /// What the navigation is called: its title, else its variant; with "#n" where there are several.
  func label(among count: Int) -> String {
    let title: String = if case .string(let text)? = options["title"] { text.trimmingCharacters(in: .whitespacesAndNewlines) } else { "" }
    let base = title.isEmpty ? NavigationVariants.catalog(NavigationVariants.label(variant), nil) : title
    return count > 1 ? "\(base) #\(occurrence)" : base
  }
}

/// Navigationen (QuartzControl's `routes/Plugins/Navigations.tsx`): the navigations of
/// quartz-navigations as a list, the selected one in the inspector (`NavigationInspector`), the
/// real site below. It starts from the question the generic form leaves for last, which kind of
/// navigation; placement stays on the Layout page and every option in the plugin list.
///
/// Every change goes through the plugin list's write queue (`PluginsModel.commit`).
struct NavigationsTab: View {
  @Bindable var model: PluginsModel
  @Binding var selection: Int?
  /// The classes the project's stylesheets and plugins already name, read once: a new class must
  /// not be one a rule is written for.
  @Binding var styled: Set<String>
  @Environment(\.unsavedGuard) private var unsaved
  @State private var adding = false

  private var instances: [NavigationInstance] { NavigationInstance.all(model.config?.plugins ?? []) }

  var body: some View {
    let instances = instances
    if let error = model.loadError {
      Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
    } else if model.config == nil {
      Text(L10n.t("common.loading")).foregroundStyle(.secondary).padding()
    } else if instances.isEmpty {
      ContentUnavailableView {
        Label(L10n.t("navigationsEditor.notInstalledTitle"), systemImage: "list.bullet.indent")
      } description: {
        Text(L10n.t("navigationsEditor.notInstalledText"))
      }
    } else {
      VSplitView {
        list(instances)
          .frame(minHeight: 180)
        EditorPreview(project: model.project, prefix: "navigations", hint: L10n.t("navigationsEditor.previewHint"),
                      highlight: highlight(instances), onAssignClass: assignClass)
          .frame(minHeight: 320)
      }
    }
  }

  private func list(_ instances: [NavigationInstance]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Note(L10n.t("navigationsEditor.intro"))
      if let message = model.message { Text(message).foregroundStyle(.red).textSelection(.enabled).lineLimit(6) }
      HStack {
        Text(L10n.t("navigationsEditor.listTitle", ["count": String(instances.count)], count: instances.count)).font(.headline)
        Spacer()
        Button { adding = true } label: { Label(L10n.t("navigationsEditor.add"), systemImage: "plus") }
          .disabled(model.busy)
          .popover(isPresented: $adding, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
              Text(L10n.t("navigationsEditor.addQuestion")).foregroundStyle(.secondary)
              VariantTiles(selected: nil) { variant in
                adding = false
                Task { await add(variant) }
              }
            }
            .padding(12)
            .frame(width: 460)
          }
          .accessibilityIdentifier("navigations.add")
      }
      List(selection: $selection) {
        ForEach(instances) { item in row(item, count: instances.count).tag(item.occurrence) }
      }
      .accessibilityIdentifier("navigations.list")
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
  }

  private func row(_ item: NavigationInstance, count: Int) -> some View {
    let label = item.label(among: count)
    let position: String = if case .string(let p)? = item.entry.object["layout"]?["position"] { InstalledTab.positionTitle(p) }
      else { L10n.t("navigationsEditor.notPlaced") }
    return HStack(spacing: 8) {
      Image(systemName: item.variant.symbol).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(label).fontWeight(.medium)
        Text("\(NavigationVariants.catalog(NavigationVariants.label(item.variant), nil)) · \(position)").font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      if !item.entry.enabled { WordBadge(text: L10n.t("navigationsEditor.off")) }
      Button { Task { await duplicate(item, count: count) } } label: {
        Label(L10n.t("navigationsEditor.duplicateNamed", ["name": label]), systemImage: "plus.square.on.square").labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.t("navigationsEditor.duplicateNamed", ["name": label]))
      .disabled(model.busy)
      // The last one is the plugin itself; removing that is the plugin list's job.
      if count > 1 {
        Button { Task { await remove(item, count: count) } } label: {
          Label(L10n.t("common.removeNamed", ["name": label]), systemImage: "trash").labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(L10n.t("common.removeNamed", ["name": label]))
        .disabled(model.busy)
      }
    }
    .padding(.vertical, 2)
    .contextMenu {
      Button(L10n.t("navigationsEditor.duplicateNamed", ["name": label])) { Task { await duplicate(item, count: count) } }
      if count > 1 {
        Button(L10n.t("common.removeNamed", ["name": label]), role: .destructive) { Task { await remove(item, count: count) } }
      }
    }
    .accessibilityIdentifier("navigations.row.\(item.occurrence)")
  }

  // MARK: Preview

  private func highlight(_ instances: [NavigationInstance]) -> PreviewHighlight? {
    guard let selection, let current = instances.first(where: { $0.occurrence == selection }),
          let found = ComponentSelectors.entry(current.entry, siblings: instances.map(\.entry)) else { return nil }
    return PreviewHighlight(selector: found.selector, name: current.label(among: instances.count), matches: found.matches,
                            ownClass: found.ownClass, pages: nil)
  }

  // MARK: Writing

  private func add(_ variant: NavigationVariants.Variant) async {
    guard let plugins = model.config?.plugins, let first = instances.first else { return }
    let position = variant.position
    // Last in its position, ten after whatever is there.
    let priorities = plugins.compactMap { entry -> Double? in
      guard let layout = LayoutEntries.layout(entry), layout["position"] == .string(position) else { return nil }
      return layout["priority"]?.numberValue
    }
    var object = JSONObject([("name", .string(NavigationVariants.plugin))])
    object["source"] = first.entry.object["source"]
    object["enabled"] = .bool(true)
    if let order = first.entry.object["order"] { object["order"] = order }
    // A class of its own from the start, so a stylesheet and the preview can tell it apart.
    object["options"] = .object(JSONObject([
      ("variant", .string(variant.rawValue)),
      ("className", .string(InstanceClass.suggest(prefix: InstanceClass.navigationPrefix, name: variant.rawValue, fallback: "navigation",
                                                  plugins: plugins, styled: styled)))
    ]))
    object["layout"] = .object(JSONObject([("position", .string(position)), ("priority", .number((priorities.max() ?? 0) + 10))]))
    let count = instances.count
    selection = count + 1
    if await model.commit({ $0 + [PluginEntry(object: object)] }) {
      Announce.post(L10n.t("navigationsEditor.addedAnnounce", ["variant": NavigationVariants.catalog(NavigationVariants.label(variant), nil),
                                                                "position": InstalledTab.positionTitle(position)]))
    }
  }

  private func duplicate(_ item: NavigationInstance, count: Int) async {
    guard let plugins = model.config?.plugins, let result = LayoutEntries.duplicateAfter(plugins, item.index, styled: styled) else { return }
    selection = count + 1
    if await model.commit({ _ in result.plugins }) {
      Announce.post(L10n.t("navigationsEditor.duplicatedAnnounce", ["name": item.label(among: count)]))
    }
  }

  private func remove(_ item: NavigationInstance, count: Int) async {
    let name = item.label(among: count)
    let parts = L10n.t("navigationsEditor.removeConfirm", ["name": name]).components(separatedBy: "\n\n")
    guard await Confirm.ask(parts[0], detail: parts.dropFirst().joined(separator: "\n\n"), confirm: L10n.t("common.remove"),
                            destructive: true, window: unsaved?.window) else { return }
    if selection == item.occurrence { selection = nil } else if let s = selection, s > item.occurrence { selection = s - 1 }
    if await model.commit({ plugins in plugins.enumerated().filter { $0.offset != item.index }.map(\.element) }) {
      Announce.post(L10n.t("navigationsEditor.removedAnnounce", ["name": name]))
    }
  }

  /// „Eigene Klasse vergeben“ beside the sentence that says the selected one has none.
  private func assignClass() {
    guard let selection, let plugins = model.config?.plugins,
          let item = instances.first(where: { $0.occurrence == selection }) else { return }
    let cls = InstanceClass.suggest(prefix: InstanceClass.navigationPrefix, name: InstanceClass.source(item.entry), fallback: "navigation",
                                    plugins: plugins, styled: styled)
    let name = item.label(among: instances.count)
    Task {
      let done = await model.commit { plugins in
        plugins.enumerated().map { offset, plugin in
          guard offset == item.index else { return plugin }
          var object = plugin.object
          object["options"] = .object(InstanceClass.with(plugin.object["options"]?.objectValue, cls))
          return PluginEntry(object: object)
        }
      }
      if done { Announce.post(L10n.t("sitePreview.classAssigned", ["name": name, "cls": cls])) }
    }
  }
}

/// The ten variants as tiles, with what each one is.
struct VariantTiles: View {
  let selected: NavigationVariants.Variant?
  let choose: (NavigationVariants.Variant) -> Void

  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 6) {
      ForEach(NavigationVariants.Variant.allCases, id: \.self) { variant in
        let on = variant == selected
        Button { choose(variant) } label: {
          VStack(alignment: .leading, spacing: 2) {
            Label(NavigationVariants.catalog(NavigationVariants.label(variant), nil), systemImage: variant.symbol).fontWeight(.medium)
            Text(NavigationVariants.catalog(NavigationVariants.text(variant), nil))
              .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .contentShape(Rectangle())
          .background(on ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.4)), in: RoundedRectangle(cornerRadius: 7))
          .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("navigations.variant.\(variant.rawValue)")
      }
    }
  }
}

/// The selected navigation in the inspector: on or off, its variant as tiles, then the options
/// that variant reads; what it does not read stays in sight, greyed, with the variants it works with.
struct NavigationInspector: View {
  let item: NavigationInstance
  let label: String
  @Bindable var model: PluginsModel
  let showAllOptions: () -> Void
  @Environment(\.openPage) private var openPage
  @State private var schema: PluginOptionSchemaResult?
  @State private var loaded = false

  private var language: OptionFormText.Language { L10n.language == "en" ? .en : .de }

  var body: some View {
    let options = item.options
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(label, systemImage: "list.bullet.indent").font(.headline)
            .accessibilityIdentifier("navigations.inspector.name")
          HStack(spacing: 6) {
            if case .string(let position)? = item.entry.object["layout"]?["position"] {
              Text(InstalledTab.positionTitle(position)).font(.caption).foregroundStyle(.secondary)
            } else {
              Text(L10n.t("navigationsEditor.notPlaced")).font(.caption).foregroundStyle(.secondary)
            }
            if model.savedIndex == item.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          }
          Note(L10n.t("plugins.savesImmediately"))
          if let installed = schema?.packageVersion, installed != NavigationVariants.readAgainst,
             !NavigationVariants.sameCode.contains(installed) {
            Text(L10n.t("plugins.readAgainst", ["plugin": NavigationVariants.plugin, "read": NavigationVariants.readAgainst, "installed": installed]))
              .font(.caption).foregroundStyle(.orange)
          }
        }
        Toggle(L10n.t("navigationsEditor.enabled"), isOn: Binding(get: { item.entry.enabled }, set: { _ in
          Task { await model.toggleEnabled(item.index) }
        }))
        .accessibilityIdentifier("navigations.inspector.enabled")
      }
      Section(L10n.t("navigationsEditor.variantHeading")) {
        VariantTiles(selected: item.variant) { variant in
          var next = options
          next["variant"] = .string(variant.rawValue)
          Task { await model.updateField(item.index, path: ["options"], value: .object(next)) }
        }
        // Below each other: side by side, both were cut off in the inspector's width.
        VStack(alignment: .leading, spacing: 6) {
          Button(L10n.t("pluginsInstalled.showOnStage")) { openPage(.layout) }
          Button(L10n.t("navigationsEditor.allOptions"), action: showAllOptions)
            .accessibilityIdentifier("navigations.allOptions")
        }
      }
      if !loaded {
        Section(L10n.t("navigationsEditor.optionsHeading")) {
          Text(L10n.t("layoutEditor.inspector.optionsLoading")).foregroundStyle(.secondary)
        }
      } else if let schema {
        Section {} header: { Text(L10n.t("navigationsEditor.optionsHeading")) }
        OptionsForm(schema: schema.schema, values: options,
                    onChange: { next in Task { await model.updateField(item.index, path: ["options"], value: next.map(JSONValue.object)) } },
                    explicitEmpty: true, languages: model.config?.siteLanguages ?? [], pick: { $0 != "variant" }, freeKeys: false,
                    root: NavigationVariants.root(options: options, fields: schema.schema?.fields ?? [], lang: language))
      } else {
        Section(L10n.t("navigationsEditor.optionsHeading")) {
          Text(L10n.t("layoutEditor.inspector.optionsError", ["reason": ""])).foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
    .task(id: item.entry.source.map(JSJSON.compact) ?? "") {
      loaded = false
      if let source = PluginSource(item.entry.source) {
        let environment = await AppServices.current()
        schema = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime)
      } else {
        schema = nil
      }
      loaded = true
    }
  }
}
