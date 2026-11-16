import QuartzHubCore
import SwiftUI

/// Where an entry stands on the page, the step every setup in the inspector shares
/// (docs/plan-assistenten.md): position, its place among the neighbours there, the screens it
/// shows on and, where the layout has groups, its group. Each change writes at once through the
/// caller's `commit`, which carries the setup's snapshot rule, with the board's own functions
/// (`LayoutEntries.place`, `LayoutBoard.withDisplay`, `LayoutBoard.withGroup`); the Layout page
/// stays one button away.
struct PlacementStep: View {
  let index: Int
  /// What the entry is called in the announcements.
  let name: String
  /// The position the plugin recommends for this kind of entry, with the kind's name.
  var suggested: (position: String, kind: String)?
  let model: PluginsModel
  let commit: @MainActor (([PluginEntry]) -> [PluginEntry]) async -> Bool
  @Environment(\.openLayout) private var openLayout
  /// The content pages' frame and the groups the frames name, read once.
  @State private var frame: LayoutStage.Frame?
  @State private var frameGroups: [String] = []

  private var plugins: [PluginEntry] { model.config?.plugins ?? [] }

  var body: some View {
    let plugins = plugins
    let layout = plugins.indices.contains(index) ? LayoutEntries.layout(plugins[index]) : nil
    let position = layout?["position"]?.stringValue ?? ""
    let list = LayoutEntries.positionMap(plugins)[position] ?? []
    let place = list.firstIndex(of: index)
    Section {
      Picker(L10n.t("layoutEditor.inspector.position"), selection: Binding(get: { position }, set: { next in
        guard !next.isEmpty, next != position else { return }
        Task { await move(to: next, at: nil) }
      })) {
        if position.isEmpty { Text(L10n.t("navigationsEditor.notPlaced")).tag("") }
        ForEach(LayoutEntries.positions, id: \.self) { Text(LayoutWords.position($0)).tag($0) }
      }
      .accessibilityIdentifier("placement.position")
      if let suggested, suggested.position != position {
        VStack(alignment: .leading, spacing: 4) {
          Note(L10n.t("placement.suggested", ["variant": suggested.kind, "position": LayoutWords.position(suggested.position)]))
          Button(L10n.t("placement.useSuggested")) { Task { await move(to: suggested.position, at: nil) } }
        }
      }
      if !position.isEmpty, let warning = frameWarning(position) { Callout(.warning, warning) }
    }
    if let place {
      Section(L10n.t("placement.neighbours")) {
        ForEach(Array(list.enumerated()), id: \.element) { n, entry in
          HStack {
            Text(verbatim: "\(n + 1).").monospacedDigit().foregroundStyle(.secondary)
            Text(verbatim: neighbourName(entry, plugins: plugins)).fontWeight(entry == index ? .semibold : .regular)
            if entry == index { Text(L10n.t("placement.thisEntry")).font(.caption).foregroundStyle(.secondary) }
          }
        }
        HStack {
          Button { Task { await shift(-1, list: list, place: place, position: position) } } label: {
            Label(L10n.t("layoutEditor.inspector.earlier"), systemImage: "arrow.up")
          }
          .disabled(place == 0)
          Button { Task { await shift(1, list: list, place: place, position: position) } } label: {
            Label(L10n.t("layoutEditor.inspector.later"), systemImage: "arrow.down")
          }
          .disabled(place == list.count - 1)
          Spacer()
          Text(L10n.t("layoutEditor.inspector.orderOf", ["n": String(place + 1), "count": String(list.count)]))
            .font(.caption).foregroundStyle(.secondary)
        }
        // ⌥⌘↑/↓ through Anordnen, as on the Layout page's inspector.
        .focusedSceneValue(\.moveSelection, MoveSelectionAction(canMoveUp: place > 0, canMoveDown: place < list.count - 1) { delta in
          Task { await shift(delta, list: list, place: place, position: position) }
        })
      }
    }
    Section {
      Picker(L10n.t("layoutEditor.displayLabel"), selection: Binding(get: { layout?["display"]?.stringValue ?? "all" }, set: { next in
        Task { await write(LayoutBoard.withDisplay(self.plugins, index, next)) }
      })) {
        Text(L10n.t("layoutEditor.displayAll")).tag("all")
        Text(L10n.t("layoutEditor.displayDesktopOnly")).tag("desktop-only")
        Text(L10n.t("layoutEditor.displayMobileOnly")).tag("mobile-only")
      }
      .accessibilityIdentifier("placement.display")
      Note(L10n.t("layoutEditor.inspector.displayHint"))
      let groups = groupNames
      if !groups.isEmpty {
        Picker(L10n.t("layoutEditor.groupLabel"), selection: Binding(get: { layout?["group"]?.stringValue ?? "" }, set: { next in
          Task { await write(LayoutBoard.withGroup(self.plugins, index, next)) }
        })) {
          Text(L10n.t("layoutEditor.noGroup")).tag("")
          ForEach(groups, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        .accessibilityIdentifier("placement.group")
      }
      Button(L10n.t("pluginsInstalled.showOnStage")) { openLayout(.component(self.plugins, index)) }
    }
    .task(id: model.config?.plugins.map { "\($0.name)|\($0.source.map(JSJSON.compact) ?? "")" }.joined(separator: "\n") ?? "") {
      await readFrame()
    }
  }

  private var groupNames: [String] {
    guard let config = model.config else { return [] }
    var names = LayoutBoard.groupNames(config, frames: [])
    for group in frameGroups where !names.contains(group) { names.append(group) }
    return names
  }

  /// What another entry is called among the neighbours: its plugin's name, "#n" where it is there twice.
  private func neighbourName(_ entry: Int, plugins: [PluginEntry]) -> String {
    if entry == index { return name }
    let plugin = plugins[entry]
    let count = plugins.filter { $0.name == plugin.name && LayoutEntries.layout($0) != nil }.count
    return count > 1 ? "\(plugin.name) #\(LayoutEntries.duplicateRanks(plugins)[entry] ?? 1)" : plugin.name
  }

  private func frameWarning(_ position: String) -> String? {
    guard let frame else { return nil }
    let widths = LayoutBoard.breakpoints.filter { LayoutStage.missingPositions(frame, $0).contains(position) }
    if widths.isEmpty { return nil }
    if widths.count == LayoutBoard.breakpoints.count {
      return L10n.t("placement.notInFrame", ["position": LayoutWords.position(position)])
    }
    return L10n.t("placement.notInFrameOn", ["position": LayoutWords.position(position),
                                             "breakpoints": widths.map(LayoutWords.breakpoint).joined(separator: ", ")])
  }

  private func readFrame() async {
    guard let config = model.config else { return }
    let path = model.project.path
    let frames = LayoutFrames.listFrames(project: path).map(FrameView.init)
    let environment = await AppServices.current()
    let pluginFrames = await PluginSchemaReader.shared.pageTypeFrames(project: path, plugins: config.plugins.map { ($0.name, $0.source) },
                                                                      runtime: environment.runtime)
    let chosen = PageTypeOverride.resolvedFrame(config, "content", pluginFrames: pluginFrames)
    frame = LayoutStage.frame(named: chosen.name, frames: frames, pluginFrames: pluginFrames)
    frameGroups = LayoutBoard.groupNames(config, frames: frames)
  }

  // MARK: Writing

  private func write(_ next: [PluginEntry]) async {
    if await commit({ _ in next }) { model.flagSaved(index) }
  }

  /// Into `position`, at `at` or its end. An entry without a layout block gets one first, after
  /// the last entry there, as the forms editor's position field does.
  private func move(to position: String, at: Int?) async {
    let done = await commit { plugins in
      guard plugins.indices.contains(index) else { return plugins }
      if LayoutEntries.layout(plugins[index]) != nil {
        return LayoutEntries.place(plugins, index: index, position: position, insertIndex: at)
      }
      let others = (LayoutEntries.positionMap(plugins)[position] ?? []).map { LayoutEntries.layout(plugins[$0])?["priority"]?.numberValue ?? 0 }
      var object = plugins[index].object
      object["layout"] = .object(JSONObject([("position", .string(position)), ("priority", .number((others.max() ?? 0) + 10))]))
      var out = plugins
      out[index] = PluginEntry(object: object)
      return out
    }
    if done {
      model.flagSaved(index, announce: false)
      Announce.post(L10n.t("placement.positionAnnounce", ["name": name, "position": LayoutWords.position(position)]))
    }
  }

  private func shift(_ delta: Int, list: [Int], place: Int, position: String) async {
    let target = place + delta
    guard target >= 0, target < list.count else { return }
    let done = await commit { LayoutEntries.place($0, index: index, position: position, insertIndex: target) }
    if done {
      model.flagSaved(index, announce: false)
      Announce.post(L10n.t("layoutEditor.inspector.moved", ["name": name, "n": String(target + 1), "count": String(list.count),
                                                            "position": LayoutWords.position(position)]))
    }
  }
}
