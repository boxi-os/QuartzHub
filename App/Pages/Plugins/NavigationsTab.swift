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
/// navigation; the inspector then goes through the rest in steps, the placement among them.
///
/// Every change goes through the plugin list's write queue (`PluginsModel.commit`).
struct NavigationsTab: View {
  @Bindable var model: PluginsModel
  @Binding var selection: Int?
  /// The classes the project's stylesheets and plugins already name, read once: a new class must
  /// not be one a rule is written for.
  @Binding var styled: Set<String>
  /// The navigation ➕ just created: the inspector sets it up in steps.
  @Binding var setup: SetupRun?
  @Environment(\.unsavedGuard) private var unsaved
  @State private var adding = false
  /// The variants the installed plugin knows (`NavigationVariants.offered`), read from its schema.
  @State private var offered = NavigationVariants.Variant.quartzControl

  private var instances: [NavigationInstance] { NavigationInstance.all(model.config?.plugins ?? []) }

  var body: some View {
    let instances = instances
    if let error = model.loadError {
      Callout(.error, error).padding(Spacing.page)
    } else if model.config == nil {
      Text(L10n.t("common.loading")).foregroundStyle(.secondary).padding()
    } else if instances.isEmpty {
      ContentUnavailableView {
        Label(L10n.t("navigationsEditor.notInstalledTitle"), systemImage: "list.bullet.indent")
      } description: {
        Text(L10n.t("navigationsEditor.notInstalledText"))
      }
      // The whole column: at its text's width, the tab picker above moved to the left.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      SplitPanes("navigations", initial: 0.4, topMin: 180, bottomMin: 320) {
        list(instances).paneCard()
      } bottom: {
        EditorPreview(project: model.project, prefix: "navigations", hint: L10n.t("navigationsEditor.previewHint"),
                      highlight: highlight(instances), onAssignClass: assignClass).paneCard()
      }
      .padding([.horizontal, .bottom], Spacing.page)
      .padding(.top, Spacing.xxs)
      .toolbar {
        ToolbarItem(placement: .primaryAction) { addButton }
      }
      .task(id: instances.first?.entry.source.map(JSJSON.compact) ?? "") {
        guard let source = PluginSource(instances.first?.entry.source) else { return }
        let environment = await AppServices.current()
        let schema = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime)
        offered = NavigationVariants.offered(schema.schema?.fields)
      }
    }
  }

  /// ➕ in the toolbar (docs/conventions.md, Liste); the variants in a popover under it.
  private var addButton: some View {
    Button { adding = true } label: { Label(L10n.t("navigationsEditor.add"), systemImage: "plus") }
      .help(L10n.t("navigationsEditor.add"))
      .disabled(model.busy)
      .popover(isPresented: $adding, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(L10n.t("navigationsEditor.addQuestion")).foregroundStyle(.secondary)
          VariantTiles(variants: offered, selected: nil) { variant in
            adding = false
            Task { await add(variant) }
          }
        }
        .padding(Spacing.s)
        .frame(width: 460)
      }
      .accessibilityIdentifier("navigations.add")
  }

  private func list(_ instances: [NavigationInstance]) -> some View {
    // No head above the list: the intro is in the inspector, adding is ➕ in the toolbar.
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let message = model.message {
        Callout(.error) { Text(message).textSelection(.enabled).lineLimit(6) }
          .padding(.horizontal, Spacing.page).padding(.top, Spacing.s)
      }
      List(selection: $selection) {
        Section(L10n.t("navigationsEditor.listTitle", ["count": String(instances.count)], count: instances.count)) {
          ForEach(instances) { item in row(item, count: instances.count).tag(item.occurrence) }
        }
      }
      .accessibilityIdentifier("navigations.list")
    }
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
    // Last in its position, ten after whatever is there; the rail first, ten before.
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
    let priority = variant.placedFirst ? (priorities.min() ?? 20) - 10 : (priorities.max() ?? 0) + 10
    object["layout"] = .object(JSONObject([("position", .string(position)), ("priority", .number(priority))]))
    let count = instances.count
    selection = count + 1
    // The inspector takes over in steps; this write is the setup's one snapshot.
    setup = object["options"]?["className"]?.stringValue.map { SetupRun(key: $0, before: plugins) }
    let label = L10n.t("navigationsEditor.steps.snapshotLabel", ["variant": NavigationVariants.catalog(NavigationVariants.label(variant), nil)])
    if await model.commit(snapshot: .labeled(label), { $0 + [PluginEntry(object: object)] }) {
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

/// The variants the plugin knows as tiles, with what each one is.
struct VariantTiles: View {
  let variants: [NavigationVariants.Variant]
  let selected: NavigationVariants.Variant?
  let choose: (NavigationVariants.Variant) -> Void

  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 6) {
      ForEach(variants, id: \.self) { variant in
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

/// The selected navigation in the inspector, in steps (docs/plan-assistenten.md, `InspectorSteps`):
/// the variant first, then its place, then the plugin's options by the steps of
/// `NavigationVariants.steps`. A step whose options all do nothing for the variant says so; inside
/// a step, what does nothing stays in sight, greyed, with the variants it works with.
///
/// Writes go at once, with one snapshot: the one ➕ took for a new navigation, else the first
/// write after the inspector opened.
struct NavigationInspector: View {
  let item: NavigationInstance
  let label: String
  @Bindable var model: PluginsModel
  /// The navigation ➕ just created, while its first run lasts.
  @Binding var setup: SetupRun?
  @Binding var selection: Int?
  let showAllOptions: () -> Void
  @Environment(\.openLayout) private var openLayout
  @Environment(\.unsavedGuard) private var unsaved
  /// "<entry>:<step>": where this window was, by the navigation's class rather than its index.
  @SceneStorage("navigations.step") private var stored = ""
  @State private var schema: PluginOptionSchemaResult?
  @State private var loaded = false
  @State private var visited: Set<String> = []
  @State private var snapshotTaken = false

  private var language: OptionFormText.Language { L10n.language == "en" ? .en : .de }
  private var entryKey: String { InstanceClass.own(item.entry) ?? "#\(item.occurrence)" }
  private var firstRun: Bool { setup != nil && setup?.key == InstanceClass.own(item.entry) }
  private var fields: [OptionField] { schema?.schema?.fields ?? [] }

  private var current: Binding<String> {
    Binding(get: {
      guard let split = stored.lastIndex(of: ":"), stored[..<split] == entryKey else { return firstRun ? "place" : "variant" }
      return String(stored[stored.index(after: split)...])
    }, set: { step in
      stored = "\(entryKey):\(step)"
      visited.insert(step)
    })
  }

  var body: some View {
    let options = item.options
    let steps = NavigationVariants.steps.map { step in
      InspectorStep(id: step.id, title: Self.title(step.id),
                    noEffect: loaded && schema != nil && !NavigationVariants.stepHasEffect(step, options: options, fields: fields))
    }
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(label, systemImage: item.variant.symbol).font(.headline)
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
            Callout(.warning, L10n.t("plugins.readAgainst", ["plugin": NavigationVariants.plugin, "read": NavigationVariants.readAgainst, "installed": installed]))
          }
        }
        Toggle(L10n.t("navigationsEditor.enabled"), isOn: Binding(get: { item.entry.enabled }, set: { _ in
          Task { await model.toggleEnabled(item.index, snapshot: policy()) }
        }))
        .accessibilityIdentifier("navigations.inspector.enabled")
      }
      InspectorSteps(steps: steps, current: current, firstRun: firstRun, visited: visited, finish: finish,
                     cancel: { Task { await cancel() } }) { step in
        Section { Note(Self.hint(step.id)) }
        if step.noEffect {
          Section {
            Callout(.info, L10n.t("navigationsEditor.steps.noEffect", ["variant": NavigationVariants.catalog(NavigationVariants.label(item.variant), nil)]))
          }
        }
        stepContent(step.id, values: options)
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
    .onAppear {
      // ➕ answered the first step already.
      if firstRun { visited = ["variant", current.wrappedValue] }
    }
  }

  @ViewBuilder private func stepContent(_ id: String, values: JSONObject) -> some View {
    switch NavigationVariants.steps.first(where: { $0.id == id })?.part ?? .options {
    case .kind:
      Section(L10n.t("navigationsEditor.variantHeading")) {
        // The current variant stays in sight even if the plugin's schema could not be read.
        let offered = NavigationVariants.offered(schema?.schema?.fields)
        VariantTiles(variants: offered.contains(item.variant) ? offered : offered + [item.variant], selected: item.variant) { variant in
          Task { await choose(variant) }
        }
      }
    case .placement:
      PlacementStep(index: item.index, name: label,
                    suggested: (item.variant.position, NavigationVariants.catalog(NavigationVariants.label(item.variant), nil)),
                    model: model) { mutate in await model.commit(snapshot: policy(), mutate) }
    case .options:
      options(for: id, values: values)
    case .finish:
      Section {
        LabeledContent(L10n.t("navigationsEditor.variantHeading"), value: NavigationVariants.catalog(NavigationVariants.label(item.variant), nil))
        LabeledContent(L10n.t("layoutEditor.inspector.position"), value: placeText)
        LabeledContent(L10n.t("inspectorSteps.summaryChanged"), value: String(values.keys.filter { $0 != "variant" }.count))
        VStack(alignment: .leading, spacing: 6) {
          Button(L10n.t("pluginsInstalled.showOnStage")) { openLayout(.component(model.config?.plugins ?? [], item.index)) }
          Button(L10n.t("navigationsEditor.allOptions"), action: showAllOptions)
            .accessibilityIdentifier("navigations.allOptions")
        }
      }
      options(for: id, values: values)
    }
  }

  /// The plugin's options of one step, as the form of the plugin list shows them.
  @ViewBuilder private func options(for id: String, values: JSONObject) -> some View {
    if !loaded {
      Section { Text(L10n.t("layoutEditor.inspector.optionsLoading")).foregroundStyle(.secondary) }
    } else if let schema {
      let assigned = SetupSteps.assign(NavigationVariants.steps, fields: schema.schema?.fields ?? [])
      let last = NavigationVariants.steps.last?.id
      OptionsForm(schema: schema.schema, values: values,
                  onChange: { next in Task { await model.updateField(item.index, path: ["options"], value: next.map(JSONValue.object), snapshot: policy()) } },
                  explicitEmpty: true, languages: model.config?.siteLanguages ?? [],
                  // A key no schema names (written by hand) belongs to the last step, so nothing is lost.
                  pick: { key in assigned[key] == id || (assigned[key] == nil && id == last) },
                  freeKeys: false, root: root(for: id, values: values, fields: schema.schema?.fields ?? []), searchable: false)
    } else {
      Section {
        Callout(.error, L10n.t("layoutEditor.inspector.optionsError", ["reason": L10n.t("pluginsInstalled.sourceUnreadable")]))
      }
    }
  }

  /// The variant's own options lead "Darstellung" under its name; elsewhere the groups are plain
  /// sections, the step being the fold.
  private func root(for id: String, values: JSONObject, fields: [OptionField]) -> OptionRoot {
    var root = NavigationVariants.root(options: values, fields: fields, lang: language)
    if id != "look" {
      root.lead = nil
      root.flat = true
    }
    return root
  }

  private var placeText: String {
    let plugins = model.config?.plugins ?? []
    guard case .string(let position)? = item.entry.object["layout"]?["position"] else { return L10n.t("navigationsEditor.notPlaced") }
    let list = LayoutEntries.positionMap(plugins)[position] ?? []
    guard let place = list.firstIndex(of: item.index) else { return InstalledTab.positionTitle(position) }
    return "\(InstalledTab.positionTitle(position)), \(L10n.t("layoutEditor.inspector.orderOf", ["n": String(place + 1), "count": String(list.count)]))"
  }

  // MARK: Writing

  /// One snapshot per setup: ➕ took it for a new navigation; an existing one takes it with the
  /// first write after the inspector opened.
  private func policy() -> PluginsModel.SnapshotPolicy {
    if firstRun || snapshotTaken { return .none }
    snapshotTaken = true
    return .each
  }

  /// The variant, and in the first run the place with it: still where ➕ put it for the old
  /// variant, the navigation moves where the new one belongs.
  private func choose(_ variant: NavigationVariants.Variant) async {
    let old = item.variant
    let index = item.index
    var next = item.options
    next["variant"] = .string(variant.rawValue)
    let follows = firstRun && variant.position != old.position
      && LayoutEntries.layout(item.entry)?["position"] == .string(old.position)
    let done = await model.commit(snapshot: policy()) { plugins in
      var out = plugins.enumerated().map { offset, plugin in
        offset == index ? PluginEntry(object: OptionSchema.setting(.object(next), at: ["options"], in: plugin.object)) : plugin
      }
      if follows {
        out = LayoutEntries.place(out, index: index, position: variant.position, insertIndex: variant.placedFirst ? 0 : nil)
      }
      return out
    }
    if done { model.flagSaved(index) }
  }

  private func finish() {
    setup = nil
    snapshotTaken = true
    Announce.post(L10n.t("navigationsEditor.steps.doneAnnounce", ["name": label]))
  }

  /// Takes the new navigation out again, after asking; the safe answer first.
  private func cancel() async {
    let parts = L10n.t("navigationsEditor.steps.cancelQuestion").components(separatedBy: "\n\n")
    guard await Confirm.ask(parts[0], detail: parts.dropFirst().joined(separator: "\n\n"),
                            confirm: L10n.t("navigationsEditor.steps.cancelRemove"), destructive: true,
                            cancel: L10n.t("inspectorSteps.cancelKeep"), window: unsaved?.window) else { return }
    let before = setup?.before ?? []
    setup = nil
    selection = nil
    if await model.cancelSetup(index: item.index, before: before) {
      Announce.post(L10n.t("navigationsEditor.steps.cancelledAnnounce"))
    }
  }

  // MARK: Words

  static func title(_ id: String) -> String {
    switch id {
    case "variant": L10n.t("navigationsEditor.steps.variant")
    case "place": L10n.t("navigationsEditor.steps.place")
    case "pages": L10n.t("navigationsEditor.steps.pages")
    case "hide": L10n.t("navigationsEditor.steps.hide")
    case "look": L10n.t("navigationsEditor.steps.look")
    case "mobile": L10n.t("navigationsEditor.steps.mobile")
    case "labels": L10n.t("navigationsEditor.steps.labels")
    case "finish": L10n.t("navigationsEditor.steps.finish")
    default: id
    }
  }

  static func hint(_ id: String) -> String {
    switch id {
    case "variant": L10n.t("navigationsEditor.steps.variantHint")
    case "place": L10n.t("navigationsEditor.steps.placeHint")
    case "pages": L10n.t("navigationsEditor.steps.pagesHint")
    case "hide": L10n.t("navigationsEditor.steps.hideHint")
    case "look": L10n.t("navigationsEditor.steps.lookHint")
    case "mobile": L10n.t("navigationsEditor.steps.mobileHint")
    case "labels": L10n.t("navigationsEditor.steps.labelsHint")
    case "finish": L10n.t("navigationsEditor.steps.finishHint")
    default: ""
    }
  }
}
