import QuartzHubCore
import SwiftUI

/// The selected component in the inspector (QuartzControl's `LayoutEditor/Inspector.tsx`):
/// everything about its place on the page, then its own options. It writes into the page's draft
/// like a drop does; Speichern writes the file. It is also the keyboard's way to do what the stage
/// does by dragging: position and earlier/later answer every direction, "In den Vorrat legen" is
/// the drop on the tray.
struct ComponentInspector: View {
  @Bindable var model: LayoutModel
  let index: Int
  let facts: StageFacts
  @Binding var selected: String

  @State private var schema: PluginOptionSchemaResult?
  @State private var schemaError: String?
  @State private var customCondition: Bool?

  private var plugins: [PluginEntry] { facts.plugins }
  private var plugin: PluginEntry { plugins[index] }
  private var layout: JSONObject { LayoutEntries.layout(plugin) ?? JSONObject() }
  private var position: String { layout["position"]?.stringValue ?? "" }
  private var name: String { facts.label(index) }
  private var parked: Bool { facts.parked.contains(index) }
  private var isDuplicate: Bool { (facts.counts[plugin.name] ?? 0) > 1 }
  /// The plugin's other categories: switching the component off switches them off too.
  private var kinds: String {
    (schema?.categories ?? []).filter { $0 != "component" }.map { category in
      switch category {
      case "emitter": L10n.t("layoutEditor.inspector.categories.emitter")
      case "filter": L10n.t("layoutEditor.inspector.categories.filter")
      case "pageType": L10n.t("layoutEditor.inspector.categories.pageType")
      case "transformer": L10n.t("layoutEditor.inspector.categories.transformer")
      default: category
      }
    }.joined(separator: ", ")
  }

  private func apply(_ next: [PluginEntry], select: Int?? = nil) {
    model.config?.plugins = next
    if let select {
      if let index = select, let ref = LayoutEntries.componentRef(next, index) {
        selected = "\(ref.name)\n\(ref.occurrence)"
      } else {
        selected = ""
      }
    }
  }

  var body: some View {
    Form {
      Section {
        Label(name, systemImage: "slider.horizontal.3").font(.headline).accessibilityIdentifier("layout.inspector.name")
        Note(L10n.t("layoutEditor.inspector.savesWithPage"))
        if !plugin.enabled {
          Text(parked ? L10n.t("layoutEditor.inspector.parked") : L10n.t("layoutEditor.inspector.disabled")).foregroundStyle(.secondary)
          if !kinds.isEmpty { Text(L10n.t("layoutEditor.inspector.offWhole", ["kinds": kinds])).foregroundStyle(.secondary) }
          Button(L10n.t("layoutEditor.inspector.enable")) {
            let on = LayoutBoard.withEnabled(plugins, index, true)
            apply(parked ? LayoutEntries.place(on, index: index, position: position, positions: facts.positions) : on)
            Announce.post(L10n.t("layoutEditor.inspector.enabledAnnounce", ["name": name, "position": LayoutWords.position(position)]))
          }
        }
      }

      if let type = facts.pageType, let override = facts.override {
        Section {
          Toggle(L10n.t("layoutEditor.pageType.hideOnType", ["type": facts.typeLabel]), isOn: Binding(
            get: { PageTypeOverride.isExcluded(override, plugin) },
            set: { hidden in
              if let config = model.config { model.config = PageTypeOverride.withExcluded(config, type, plugin, hidden) }
              let params = ["name": plugin.name, "type": facts.typeLabel]
              Announce.post(hidden ? L10n.t("layoutEditor.pageType.hiddenAnnounce", params) : L10n.t("layoutEditor.pageType.shownAnnounce", params))
            }))
          .accessibilityIdentifier("layout.inspector.hideOnType")
          // Quartz excludes by name, so the switch reaches every instance.
          if isDuplicate {
            Callout(.warning, L10n.t("layoutEditor.excludeDuplicateHint", ["name": plugin.name], count: facts.counts[plugin.name] ?? 1))
          }
        }
      }

      Section {
        Picker(L10n.t("layoutEditor.inspector.position"), selection: Binding(get: { position }, set: setPosition)) {
          ForEach(LayoutEntries.positions, id: \.self) { Text(LayoutWords.position($0)).tag($0) }
        }
        .accessibilityIdentifier("layout.inspector.position")
        if let list = facts.positions[position], let place = list.firstIndex(of: index) {
          LabeledContent(L10n.t("layoutEditor.inspector.order")) {
            HStack {
              Button { move(-1, list, place) } label: { Label(L10n.t("layoutEditor.inspector.earlier"), systemImage: "arrow.up") }
                .disabled(place == 0)
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
              Button { move(1, list, place) } label: { Label(L10n.t("layoutEditor.inspector.later"), systemImage: "arrow.down") }
                .disabled(place == list.count - 1)
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
            }
          }
          Text(L10n.t("layoutEditor.inspector.orderOf", ["n": String(place + 1), "count": String(list.count)])).font(.caption).foregroundStyle(.secondary)
        }
        Picker(L10n.t("layoutEditor.displayLabel"), selection: Binding(get: { layout["display"]?.stringValue ?? "all" },
                                                                      set: { apply(LayoutBoard.withDisplay(plugins, index, $0)) })) {
          Text(L10n.t("layoutEditor.displayAll")).tag("all")
          Text(L10n.t("layoutEditor.displayDesktopOnly")).tag("desktop-only")
          Text(L10n.t("layoutEditor.displayMobileOnly")).tag("mobile-only")
        }
        Note(L10n.t("layoutEditor.inspector.displayHint"))
        conditionFields
        Picker(L10n.t("layoutEditor.groupLabel"), selection: Binding(get: { layout["group"]?.stringValue ?? "" },
                                                                    set: { apply(LayoutBoard.withGroup(plugins, index, $0)) })) {
          Text(L10n.t("layoutEditor.noGroup")).tag("")
          ForEach(facts.groupNames, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        .accessibilityIdentifier("layout.inspector.group")
      }

      if let group = layout["group"]?.stringValue, !group.isEmpty { groupOptions }

      Section(L10n.t("layoutEditor.inspector.actions")) {
        HStack {
          Button(L10n.t("layoutEditor.componentPill.duplicate")) {
            if let result = LayoutEntries.duplicateAfter(plugins, index, styled: model.styled) { apply(result.plugins, select: result.newIndex) }
          }
          if isDuplicate {
            Button(L10n.t("layoutEditor.componentPill.removeDuplicate"), role: .destructive) {
              apply(LayoutBoard.removing(plugins, index, selected: index).plugins, select: .some(nil))
              Announce.post(L10n.t("dnd.removed", ["name": plugin.name]))
            }
          } else if plugin.enabled {
            Button(L10n.t("layoutEditor.inspector.park")) {
              apply(LayoutBoard.withEnabled(plugins, index, false))
              Announce.post(kinds.isEmpty ? L10n.t("dnd.disabled", ["name": name]) : L10n.t("dnd.disabledWhole", ["name": name, "kinds": kinds]))
            }
          }
        }
        if !isDuplicate && plugin.enabled {
          Note(kinds.isEmpty ? L10n.t("layoutEditor.inspector.parkHint") : L10n.t("layoutEditor.inspector.parkHintWhole", ["kinds": kinds]))
        }
      }

      options
    }
    .formStyle(.grouped)
    .task(id: plugin.source.map(JSJSON.compact) ?? "") { await loadSchema() }
  }

  // MARK: moving

  private func move(_ delta: Int, _ list: [Int], _ place: Int) {
    let target = place + delta
    guard target >= 0, target < list.count else { return }
    apply(LayoutEntries.place(plugins, index: index, position: position, insertIndex: target, positions: facts.positions))
    Announce.post(L10n.t("layoutEditor.inspector.moved", ["name": name, "n": String(target + 1), "count": String(list.count),
                                                          "position": LayoutWords.position(position)]))
  }

  private func setPosition(_ next: String) {
    guard next != position else { return }
    apply(LayoutEntries.place(plugins, index: index, position: next, positions: facts.positions))
    let count = (facts.positions[next]?.count ?? 0) + (parked ? 0 : 1)
    Announce.post(L10n.t("layoutEditor.inspector.moved", ["name": name, "n": String(count), "count": String(count),
                                                          "position": LayoutWords.position(next)]))
  }

  // MARK: condition and group

  @ViewBuilder private var conditionFields: some View {
    let condition = layout["condition"]?.stringValue ?? ""
    let builtin = LayoutBoard.builtinConditions.contains(condition)
    let custom = customCondition ?? (!condition.isEmpty && !builtin)
    Picker(L10n.t("layoutEditor.inspector.condition"), selection: Binding(get: { custom ? "__custom" : condition }, set: { value in
      if value == "__custom" {
        customCondition = true
        return
      }
      customCondition = false
      apply(LayoutBoard.withCondition(plugins, index, value))
    })) {
      Text(L10n.t("layoutEditor.inspector.conditionAlways")).tag("")
      ForEach(LayoutBoard.builtinConditions, id: \.self) { Text(LayoutWords.condition($0)).tag($0) }
      Text(L10n.t("layoutEditor.inspector.conditionCustom")).tag("__custom")
    }
    if custom {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("layoutEditor.inspector.conditionCustomLabel"))
        CommitField(name: L10n.t("layoutEditor.inspector.conditionCustomLabel"), text: builtin ? "" : condition) { raw in
          apply(LayoutBoard.withCondition(plugins, index, raw))
          return true
        }
        Note(L10n.t("layoutEditor.inspector.conditionCustomHint"))
      }
    }
  }

  private var groupOptions: some View {
    let options = layout["groupOptions"]?.objectValue ?? JSONObject()
    let set = { (key: String, value: JSONValue?) in apply(LayoutBoard.withGroupOption(plugins, index, key, value)) }
    return Section(L10n.t("layoutEditor.inspector.groupOptions")) {
      Toggle(L10n.t("layoutEditor.inspector.grow"), isOn: Binding(get: { options["grow"]?.boolValue ?? false }, set: { set("grow", .bool($0)) }))
      Toggle(L10n.t("layoutEditor.inspector.shrink"), isOn: Binding(get: { options["shrink"]?.boolValue ?? true }, set: { set("shrink", .bool($0)) }))
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("layoutEditor.inspector.basis"))
        CommitField(name: L10n.t("layoutEditor.inspector.basis"), text: options["basis"]?.stringValue ?? "", placeholder: "auto") { raw in
          set("basis", .string(raw.trimmingCharacters(in: .whitespaces)))
          return true
        }
        Note(L10n.t("layoutEditor.inspector.basisHint"))
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("layoutEditor.inspector.itemOrder"))
        CommitField(name: L10n.t("layoutEditor.inspector.itemOrder"), text: options["order"]?.numberValue.map { JSJSON.compact(.number($0)) } ?? "",
                    placeholder: "0") { raw in
          let trimmed = raw.trimmingCharacters(in: .whitespaces)
          if trimmed.isEmpty { set("order", nil); return true }
          guard let n = Int(trimmed) else { return false }
          set("order", .number(Double(n)))
          return true
        }
        Note(L10n.t("layoutEditor.inspector.itemOrderHint"))
      }
      Picker(L10n.t("layoutEditor.inspector.align"), selection: Binding(get: { options["align"]?.stringValue ?? "center" }, set: { set("align", .string($0)) })) {
        Text(L10n.t("layoutEditor.inspector.alignStart")).tag("start")
        Text(L10n.t("layoutEditor.inspector.alignCenter")).tag("center")
        Text(L10n.t("layoutEditor.inspector.alignEnd")).tag("end")
        Text(L10n.t("layoutEditor.inspector.alignStretch")).tag("stretch")
      }
    }
  }

  // MARK: options

  /// Last, because it is the long part: the fields above are what the stage is about.
  @ViewBuilder private var options: some View {
    if let schemaError {
      Section(L10n.t("layoutEditor.inspector.options")) {
        Callout(.error, L10n.t("layoutEditor.inspector.optionsError", ["reason": schemaError]))
      }
    } else if let schema {
      Section(L10n.t("layoutEditor.inspector.options")) {
        if let unreadable = schema.unreadable {
          Callout(.warning, L10n.t("pluginOptions.unreadable", ["reason": unreadable]))
        }
      }
      OptionsForm(schema: schema.schema, values: plugin.object["options"]?.objectValue ?? JSONObject(),
                  onChange: { next in apply(LayoutBoard.withOptions(plugins, index, next)) },
                  explicitEmpty: true, languages: model.config?.siteLanguages ?? [],
                  root: OptionRoot.withoutTiles(plugin, fields: schema.schema?.fields ?? [], packageVersion: schema.packageVersion,
                                                lang: L10n.language == "en" ? .en : .de),
                  projectPath: model.project.path)
    } else {
      Section(L10n.t("layoutEditor.inspector.options")) {
        Text(L10n.t("layoutEditor.inspector.optionsLoading")).foregroundStyle(.secondary)
      }
    }
  }

  private func loadSchema() async {
    schema = nil
    schemaError = nil
    // Not an empty reason after "konnten nicht gelesen werden:" (review 2026-11-13, nebenbei).
    guard let source = PluginSource(plugin.source) else {
      schemaError = L10n.t("pluginsInstalled.sourceUnreadable")
      return
    }
    let environment = await AppServices.current()
    schema = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime)
  }
}

/// The inspector while nothing is selected on the stage (QuartzControl's `LayoutSummary.tsx`):
/// what the page the stage shows is made of, per position, with the components as the pills of
/// the overview. It answers for the page type, not for the view.
struct LayoutSummary: View {
  let facts: StageFacts
  @Binding var selected: String

  var body: some View {
    let missing = Set(LayoutStage.missingPositions(facts.frame, "desktop"))
    let own: FrameView? = if case .own(let frame) = facts.frame { frame } else { nil }
    InspectorPageContext(page: .layout) {
      Section(L10n.t("layoutEditor.summary.title")) {
        LabeledContent(L10n.t("layoutEditor.pageType.label"), value: facts.pageType == nil ? L10n.t("layoutEditor.pageType.all") : facts.typeLabel)
        LabeledContent(L10n.t("layoutEditor.summary.frame"), value: LayoutWords.frame(facts.frameChoice.name))
        Note(facts.pageType == nil ? L10n.t("layoutEditor.summary.frameAllPages") : origin)
      }
      ForEach(LayoutEntries.positions, id: \.self) { position in
        let indices = facts.positions[position] ?? []
        let reasons = Set(indices.map { pageTypeHidden($0) ?? "" })
        let shared = indices.count > 1 && reasons.count == 1 ? reasons.first.flatMap { $0.isEmpty ? nil : $0 } : nil
        Section(LayoutWords.position(position)) {
          if missing.contains(position), !indices.isEmpty {
            Callout(.warning, L10n.t("layoutEditor.summary.notInFrame"))
          }
          if let shared { Text(shared).font(.caption).foregroundStyle(.secondary) }
          if indices.isEmpty {
            Text(L10n.t("layoutEditor.summary.empty")).font(.caption).foregroundStyle(.secondary)
          } else {
            let groupOf = { (i: Int) in LayoutEntries.layout(facts.plugins[i])?["group"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
            let ungrouped = indices.filter { groupOf($0) == nil }
            if !ungrouped.isEmpty { FlowLayout(spacing: 4, minItem: 0, stretch: false) { ForEach(ungrouped, id: \.self) { pill($0, said: shared != nil) } } }
            ForEach(facts.groupNames.filter { g in indices.contains { groupOf($0) == g } }, id: \.self) { group in
              let areas = Array(NSOrderedSet(array: (own?.areas ?? []).filter { $0.slot == position && $0.group == group }.map(\.name))) as? [String] ?? []
              VStack(alignment: .leading, spacing: 4) {
                Label(areas.isEmpty ? L10n.t("layoutEditor.overview.flexGroup", ["name": group]) : L10n.t("layoutEditor.overview.ownArea", ["name": areas.joined(separator: ", ")]),
                      systemImage: areas.isEmpty ? "circle.fill" : "square")
                  .font(.caption.weight(.medium))
                  .foregroundStyle(LayoutWords.groupColor(group, facts.groupNames) ?? .secondary)
                FlowLayout(spacing: 4, minItem: 0, stretch: false) { ForEach(indices.filter { groupOf($0) == group }, id: \.self) { pill($0, said: shared != nil) } }
              }
            }
          }
        }
      }
      Section {
        if !facts.parked.isEmpty { Note(L10n.t("layoutEditor.summary.parked", count: facts.parked.count)) }
        Note(L10n.t("layoutEditor.inspector.empty"))
      }
    }
  }

  private var origin: String {
    switch facts.frameChoice.from {
    case .override: L10n.t("layoutEditor.summary.frameFrom.override")
    case .plugin: L10n.t("layoutEditor.summary.frameFrom.plugin")
    case .default: L10n.t("layoutEditor.summary.frameFrom.default")
    }
  }

  private func pageTypeHidden(_ index: Int) -> String? {
    guard let reason = LayoutStage.hidden(facts.plugins[index], override: facts.override, bp: nil) else { return nil }
    return LayoutWords.hidden(reason, type: facts.pageType ?? "")
  }

  private func pill(_ index: Int, said: Bool) -> some View {
    let hidden = pageTypeHidden(index)
    return HStack(spacing: 4) {
      ComponentPill(plugin: facts.plugins[index], label: facts.label(index), groupNames: facts.groupNames, struckReason: hidden) {
        if let ref = LayoutEntries.componentRef(facts.plugins, index) { selected = "\(ref.name)\n\(ref.occurrence)" }
      }
      if let hidden, !said { Text(hidden).font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true) }
    }
    .fixedSize()
  }
}
