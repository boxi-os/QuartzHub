import QuartzHubCore
import SwiftUI

/// Installiert: every entry of `plugins:` in quartz.config.yaml, grouped the way Quartz orders
/// them (QuartzControl's `routes/Plugins/Installed.tsx`). The selected entry is set up in the
/// inspector (`PluginInspector`).
///
/// The one structural split the config allows: an entry with a `layout` block renders into the
/// page (a component, ordered by `layout.priority` within its position), everything else processes
/// content (ordered by `order`, page types apart, as Quartz's loader sorts them per category).
/// Authored frames are plugins too and stand on their own, without an order.
///
/// Reordering has three ways to one function (docs/conventions.md): dragging (`onMove`), Anordnen ▸
/// Nach oben/unten (⌥⌘↑/⌥⌘↓), and the same two in the row's context menu and as accessibility
/// actions. All of it is off while the list is filtered.
struct InstalledTab: View {
  enum Filter: String, CaseIterable {
    case all, active, inactive

    var title: String {
      switch self {
      case .all: L10n.t("pluginsInstalled.filters.all")
      case .active: L10n.t("pluginsInstalled.filters.active")
      case .inactive: L10n.t("pluginsInstalled.filters.inactive")
      }
    }
  }

  /// One sequence of the config: what reordering renumbers.
  struct Group: Identifiable {
    let id: String
    let title: String
    let rawKey: String?
    let items: [IndexedPlugin]
    /// nil: no order of its own (frames).
    let byPriority: Bool?
  }

  @Bindable var model: PluginsModel
  @Binding var selection: String?

  // Search and filter are "where the user was", per window.
  @SceneStorage("plugins.query") private var query = ""
  @SceneStorage("plugins.filter") private var filterID = Filter.all.rawValue
  @Environment(\.unsavedGuard) private var unsaved
  @Environment(\.openURL) private var openURL

  private var filter: Filter { Filter(rawValue: filterID) ?? .all }
  private var filtering: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || filter != .all }
  private var canReorder: Bool { !filtering && !model.busy && model.maintenance == nil }

  private func matches(_ item: IndexedPlugin) -> Bool {
    if filter == .active, !item.enabled { return false }
    if filter == .inactive, item.enabled { return false }
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    if q.isEmpty { return true }
    return [item.displayName, item.sourceLabel, item.description ?? ""].contains { $0.lowercased().contains(q) }
  }

  static let knownPositions = ["header", "left", "right", "beforeBody", "afterBody", "footer"]

  static func groups(_ items: [IndexedPlugin]) -> (frames: [IndexedPlugin], components: [Group], pageTypes: Group, processing: Group) {
    let frames = items.filter { $0.frame != nil }
    let plugins = items.filter { $0.frame == nil }
    var byPosition: [String: [IndexedPlugin]] = [:]
    var seenPositions: [String] = []
    for item in plugins {
      guard let layout = item.layout else { continue }
      // No position: Quartz takes the plugin manifest's default, or does not place it at all;
      // "Im Inhalt" claimed a place (review 2026-11-13, nebenbei).
      let position = layout["position"]?.stringValue ?? ""
      if byPosition[position] == nil { seenPositions.append(position) }
      byPosition[position, default: []].append(item)
    }
    func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }
    func stable(_ list: [IndexedPlugin], by key: (IndexedPlugin) -> Double) -> [IndexedPlugin] {
      list.enumerated().sorted { (key($0.element), $0.offset) < (key($1.element), $1.offset) }.map(\.element)
    }
    let positions = knownPositions.filter { byPosition[$0] != nil } + seenPositions.filter { !knownPositions.contains($0) }
    let components = positions.map { position in
      Group(id: "position.\(position)", title: positionTitle(position), rawKey: position,
            items: stable(byPosition[position] ?? []) { number($0.layout?["priority"]) }, byPriority: true)
    }
    let processing = stable(plugins.filter { $0.layout == nil }) { number($0.entry.object["order"]) }
    return (frames,
            components,
            Group(id: "pageTypes", title: L10n.t("pluginsInstalled.pageTypesGroup"), rawKey: nil,
                  items: processing.filter(\.isPageType), byPriority: false),
            Group(id: "processing", title: L10n.t("pluginsInstalled.otherProcessingGroup"), rawKey: nil,
                  items: processing.filter { !$0.isPageType }, byPriority: false))
  }

  static func positionTitle(_ key: String) -> String {
    switch key {
    case "header": L10n.t("positions.header")
    case "left": L10n.t("positions.left")
    case "right": L10n.t("positions.right")
    case "beforeBody": L10n.t("positions.beforeBody")
    case "afterBody": L10n.t("positions.afterBody")
    case "footer": L10n.t("positions.footer")
    case "": L10n.t("pluginsInstalled.noPosition")
    default: key
    }
  }

  /// Where a component stands, in words: its position, its priority when it has one.
  static func placementLine(_ layout: JSONObject) -> String {
    let position = positionTitle(layout["position"]?.stringValue ?? "")
    guard let priority = layout["priority"], priority != .null, !JSRead.string(priority).isEmpty else { return position }
    return L10n.t("pluginsInstalled.summaryPosPriority", ["position": position, "priority": JSRead.string(priority)])
  }

  var body: some View {
    let items = model.items
    let groups = Self.groups(items)
    let sequences = groups.components + [groups.pageTypes, groups.processing]
    let active = items.filter(\.enabled).count
    let visible = items.filter(matches).count
    VStack(alignment: .leading, spacing: 0) {
      header(items: items, active: active, visible: visible)
      list(items: items, groups: groups, sequences: sequences, visible: visible)
    }
  }

  private func header(items: [IndexedPlugin], active: Int, visible: Int) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        TextField(L10n.t("pluginsInstalled.searchPlaceholder"), text: $query, prompt: Text(L10n.t("pluginsInstalled.searchPlaceholder")))
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 260)
          .accessibilityIdentifier("plugins.search")
        Picker(L10n.t("pluginsInstalled.filterLabel"), selection: $filterID) {
          ForEach(Filter.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        Spacer()
        Text(filtering ? L10n.t("pluginsInstalled.countFiltered", ["visible": String(visible), "total": String(items.count)])
             : L10n.t("pluginsInstalled.countActive", ["active": String(active), "total": String(items.count)]))
          .foregroundStyle(.secondary).monospacedDigit()
          .accessibilityIdentifier("plugins.count")
      }
      if filtering { Note(L10n.t("pluginsInstalled.reorderDisabledByFilter")) }
      if model.markdownOrderProblem {
        Callout(.warning) {
          Text(L10n.t("pluginsInstalled.markdownOrder"))
          Button(L10n.t("pluginsInstalled.markdownOrderFix")) { Task { await model.fixMarkdownOrder() } }
            .disabled(!canReorder)
            .accessibilityIdentifier("plugins.markdownOrderFix")
        }
        .accessibilityIdentifier("plugins.markdownOrder")
      }
      if model.doctorFailed {
        // Review 2026-11-11 (2), N2: without this the tab looked like a clean check.
        Callout(.warning) {
          Text(L10n.t("pluginsInstalled.doctorFailed"))
          Text(model.doctorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(4)
        }
        .accessibilityIdentifier("plugins.doctorFailed")
      }
      ForEach(Array(model.doctorGeneral.enumerated()), id: \.offset) { _, finding in
        Callout(finding.severity == .error ? .error : .warning,
                [finding.subject, finding.message].compactMap { $0 }.joined(separator: ": "))
          .help(finding.hint ?? "")
          .accessibilityIdentifier("plugins.doctorGeneral")
      }
      if let message = model.message {
        Callout(.error) { Text(message).lineLimit(8) }
      } else if model.refused {
        Callout(.error, L10n.t("pluginsInstalled.busyRemoving"))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private func list(items: [IndexedPlugin], groups: (frames: [IndexedPlugin], components: [Group], pageTypes: Group, processing: Group),
                    sequences: [Group], visible: Int) -> some View {
    List(selection: $selection) {
      if let error = model.loadError {
        Callout(.error) {
          Text(L10n.t("configEditor.loadError")).fontWeight(.medium)
          Text(error).font(.system(.callout, design: .monospaced))
        }
      } else if model.config == nil {
        Text(L10n.t("common.loading")).foregroundStyle(.secondary)
      } else if items.isEmpty {
        Text(L10n.t("pluginsInstalled.none")).foregroundStyle(.secondary)
      } else if visible == 0 {
        Text(L10n.t("pluginsInstalled.noMatches")).foregroundStyle(.secondary)
      }

      let frames = groups.frames.filter(matches)
      if !frames.isEmpty {
        Section {
          explanation(L10n.t("pluginsInstalled.framesDescription"))
          ForEach(frames) { row($0, in: nil) }
        } header: {
          heading(L10n.t("pluginsInstalled.framesHeading"), "rectangle.split.3x3")
        }
      }
      if groups.components.contains(where: { $0.items.contains(where: matches) }) {
        Section {
          explanation(L10n.t("pluginsInstalled.componentsDescription"))
        } header: {
          heading(L10n.t("pluginsInstalled.componentsHeading"), "square.stack.3d.up")
        }
        ForEach(groups.components) { sequence($0) }
      }
      if [groups.pageTypes, groups.processing].contains(where: { $0.items.contains(where: matches) }) {
        Section {
          explanation(L10n.t("pluginsInstalled.processingDescription"))
        } header: {
          heading(L10n.t("pluginsInstalled.processingHeading"), "gearshape.2")
        }
        sequence(groups.pageTypes)
        sequence(groups.processing)
      }
      if model.config != nil { maintenance }
    }
    .accessibilityIdentifier("plugins.list")
    // Built anew once the config is there: opened with a search kept from before, the rows that
    // arrived with the config kept the height of one line, the plugin's name without its source
    // and summary (measured 2026-11-09; without a search they were right).
    .id(model.config != nil)
    .focusedSceneValue(\.moveSelection, moveAction(sequences))
  }

  private func heading(_ title: String, _ symbol: String) -> some View {
    Label(title, systemImage: symbol).font(.headline).padding(.top, 8)
  }

  /// What a group is, as the first row under its heading: a section header keeps one line, and
  /// the longer texts ended in "…" (measured 2026-11-09, frames and maintenance at 1200 pt).
  private func explanation(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      .selectionDisabled()
      .listRowSeparator(.hidden)
  }

  /// One sequence: dragged with the mouse, renumbered as a whole.
  @ViewBuilder private func sequence(_ group: Group) -> some View {
    let shown = group.items.filter(matches)
    if !shown.isEmpty {
      Section {
        ForEach(shown) { row($0, in: group) }
          .onMove(perform: canReorder ? { from, to in
            var order = group.items
            guard let first = from.first else { return }
            let moved = order[first]
            order.move(fromOffsets: from, toOffset: to)
            Task { await model.reorder(order, moved: moved, byPriority: group.byPriority == true) }
          } : nil)
      } header: {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(group.title)
          if let raw = group.rawKey { Text(verbatim: raw).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
          Text(verbatim: "(\(shown.count))").foregroundStyle(.secondary)
        }
      }
    }
  }

  private func move(_ item: IndexedPlugin, by delta: Int, in group: Group) {
    guard let from = group.items.firstIndex(where: { $0.index == item.index }), group.items.indices.contains(from + delta) else { return }
    var order = group.items
    order.swapAt(from, from + delta)
    Task { await model.reorder(order, moved: item, byPriority: group.byPriority == true) }
  }

  /// Anordnen ▸ Nach oben/unten for the selected row, while it can move.
  private func moveAction(_ sequences: [Group]) -> MoveSelectionAction? {
    guard canReorder, let selection,
          let group = sequences.first(where: { $0.items.contains { $0.id == selection } }),
          let index = group.items.firstIndex(where: { $0.id == selection }) else { return nil }
    let item = group.items[index]
    return MoveSelectionAction(canMoveUp: index > 0, canMoveDown: index < group.items.count - 1) { delta in
      move(item, by: delta, in: group)
    }
  }

  private func row(_ item: IndexedPlugin, in group: Group?) -> some View {
    let position = group?.items.firstIndex { $0.index == item.index }
    let movable = canReorder && group != nil && position != nil
    let up = movable && position! > 0
    let down = movable && position! < (group?.items.count ?? 0) - 1
    return PluginRow(item: item, saved: model.savedIndex == item.index, outdated: model.outdated.contains(item.entry.name),
                     builtin: model.builtin(item) != nil, findings: model.findings(item),
                     busy: model.busy || model.maintenance != nil) {
      Task { await model.toggleEnabled(item.index) }
    }
    .tag(item.id)
    .moveDisabled(!movable)
    .contextMenu {
      if let group, movable {
        Button(L10n.t("shell.menu.moveUp")) { move(item, by: -1, in: group) }.disabled(!up)
        Button(L10n.t("shell.menu.moveDown")) { move(item, by: 1, in: group) }.disabled(!down)
        Divider()
      }
      if let url = PluginRepository.url(item.entry.source), let link = URL(string: url) {
        Button(L10n.t("pluginsInstalled.openRepo")) { openURL(link) }
      }
      Button(L10n.t("common.removeNamed", ["name": item.displayName]), role: .destructive) {
        Task { await model.remove(item, window: unsaved?.window) }
      }
      // Removing runs the CLI on .quartz/plugins, which a maintenance run is rewriting too.
      .disabled(model.busy || model.maintenance != nil)
    }
    .accessibilityActions {
      if let group, up { Button(L10n.t("pluginsInstalled.moveUp", ["name": item.displayName])) { move(item, by: -1, in: group) } }
      if let group, down { Button(L10n.t("pluginsInstalled.moveDown", ["name": item.displayName])) { move(item, by: 1, in: group) } }
    }
  }

  private var maintenance: some View {
    Section {
      BuiltinMigration(project: model.project, pending: model.pendingMigrations, blockedByEdits: model.busy) { await model.reload() }
      explanation(L10n.t("pluginsInstalled.maintenanceDescription"))
      HStack {
        Button(model.maintenance == .install ? L10n.t("pluginsInstalled.installFromLockRunning") : L10n.t("pluginsInstalled.installFromLock")) {
          Task { await model.runMaintenance(.install, window: unsaved?.window) }
        }
        Button(model.maintenance == .prune ? L10n.t("pluginsInstalled.pruneRunning") : L10n.t("pluginsInstalled.prune")) {
          Task { await model.runMaintenance(.prune, window: unsaved?.window) }
        }
      }
      .disabled(model.maintenance != nil || model.busy)
      if let notice = model.maintenanceNotice {
        Text(notice).foregroundStyle(.green)
      }
    } header: {
      heading(L10n.t("pluginsInstalled.maintenanceHeading"), "wrench.and.screwdriver")
    }
    .selectionDisabled()
  }
}

/// One entry: its switch, its name with what is special about it, where it comes from, what it is,
/// and where it stands.
private struct PluginRow: View {
  let item: IndexedPlugin
  let saved: Bool
  let outdated: Bool
  /// Quartz 5.1 does this itself (crawl-links, remove-draft, content-index).
  let builtin: Bool
  /// What `plugin doctor` says about it.
  let findings: [PluginDoctorReport.Finding]
  let busy: Bool
  let toggle: () -> Void

  /// Doctor's findings but those QuartzHub causes on purpose (a second box or navigation).
  private var open: [PluginDoctorReport.Finding] { findings.filter { !$0.intended } }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Toggle(L10n.t("pluginsInstalled.enabledSwitch", ["name": item.displayName]), isOn: Binding(get: { item.enabled }, set: { _ in toggle() }))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(busy)
        .accessibilityIdentifier("plugins.enabled.\(item.id)")
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(item.displayName).fontWeight(.medium)
          if item.frame != nil { WordBadge(text: L10n.t("pluginsInstalled.frameBadge")) }
          if outdated { WordBadge(text: L10n.t("pluginsInstalled.updateAvailable"), tint: .orange) }
          if builtin { WordBadge(text: L10n.t("pluginsInstalled.builtinBadge")) }
          if open.contains(where: { $0.severity == .error }) {
            WordBadge(text: L10n.t("pluginsInstalled.doctorError"), tint: .red).help(open.map(\.message).joined(separator: "\n"))
          } else if !open.isEmpty {
            WordBadge(text: L10n.t("pluginsInstalled.doctorWarning"), tint: .orange).help(open.map(\.message).joined(separator: "\n"))
          } else if !findings.isEmpty {
            WordBadge(text: L10n.t("pluginsInstalled.doctorIntended")).help(findings.map(\.message).joined(separator: "\n"))
          }
          if saved { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
        }
        Text(item.frame != nil ? L10n.t("pluginsInstalled.frameSource") : item.sourceLabel)
          .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
          .help(item.sourceLabel)
        if let description = builtin ? L10n.t("pluginsInstalled.builtinDescription") : item.description {
          Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(description)
        }
        if let summary { Text(verbatim: summary).font(.caption).foregroundStyle(.secondary) }
      }
      .opacity(item.enabled ? 1 : 0.6)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("plugins.row.\(item.id)")
  }

  private var summary: String? {
    if let layout = item.layout {
      return InstalledTab.placementLine(layout)
    }
    if let frame = item.frame {
      let count = frame["areas"]?.arrayValue?.count ?? 0
      return L10n.t("pluginsInstalled.frameSummary", ["count": String(count)], count: count)
    }
    if let order = item.entry.object["order"], order != .null {
      return L10n.t("pluginsInstalled.summaryOrder", ["order": JSRead.string(order)])
    }
    return nil
  }
}

/// Anordnen ▸ Nach oben/unten: what the frontmost sortable list offers for its selected row.
struct MoveSelectionAction {
  let canMoveUp: Bool
  let canMoveDown: Bool
  let move: (Int) -> Void
}

extension FocusedValues {
  @Entry var moveSelection: MoveSelectionAction?
}

/// The Arrange menu (decisions/phase-4-oberflaeche.md, „Umsortieren“): the keyboard's way to move
/// a row, besides the context menu and the accessibility actions.
struct ArrangeCommands: Commands {
  @FocusedValue(\.moveSelection) private var move

  var body: some Commands {
    let _ = AppAppearance.shared.revision
    CommandMenu(L10n.t("shell.menu.arrange")) {
      Button(L10n.t("shell.menu.moveUp")) { move?.move(-1) }
        .keyboardShortcut(.upArrow, modifiers: [.option, .command])
        .disabled(move?.canMoveUp != true)
      Button(L10n.t("shell.menu.moveDown")) { move?.move(1) }
        .keyboardShortcut(.downArrow, modifiers: [.option, .command])
        .disabled(move?.canMoveDown != true)
    }
  }
}
