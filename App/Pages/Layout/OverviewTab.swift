import QuartzHubCore
import SwiftUI

/// Übersicht (QuartzControl's `LayoutOverview.tsx`): the whole layout on one screen, a matrix of
/// component × page type. The stage shows one page type at a time; this answers where each
/// component ends up on every one, which is decided on three levels: components are placed once
/// (rows, by position and group), each page type has a frame and may hide or clear (columns), the
/// frame decides which positions and groups get an area (cells). Every name is the way to where
/// it is changed.
struct OverviewTab: View {
  @Bindable var model: LayoutModel
  /// The stage on this page type ("" all pages), with this component selected.
  let openPageType: (String, Int?) -> Void
  /// The frame editor on this frame, "default" for Quartz's.
  let openFrame: (String) -> Void

  enum Tile: String { case placed, conditioned, disabled, pageTypes, frames }
  @SceneStorage("layoutOverview.openTile") private var openTile = ""

  var body: some View {
    if let config = model.config {
      let facts = Facts(model: model, config: config)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Note(L10n.t("layoutEditor.overview.intro"))
          tiles(facts)
          if let tile = Tile(rawValue: openTile) {
            GroupBox { panel(tile, facts).frame(maxWidth: .infinity, alignment: .leading).padding(4) }
          }
          GroupBox {
            VStack(alignment: .leading, spacing: 10) {
              ScrollView(.horizontal) { matrix(facts).padding(.bottom, 6) }
              legend
            }
            .padding(4)
          } label: {
            Label(L10n.t("layoutEditor.overview.title"), systemImage: "tablecells").font(.headline)
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityIdentifier("layout.overview")
    }
  }

  /// What the overview works out once per drawing.
  struct Facts {
    let config: QuartzConfig
    let plugins: [PluginEntry]
    let parked: Set<Int>
    let positions: [String: [Int]]
    let pageTypes: [String]
    let groupNames: [String]
    let frames: [FrameView]
    let pluginFrames: Set<String>
    let chosen: [String: (name: String, from: PageTypeOverride.FrameOrigin)]
    let shapes: [String: LayoutStage.Shape?]
    let counts: [String: Int]
    let ranks: [Int: Int]

    @MainActor init(model: LayoutModel, config: QuartzConfig) {
      self.config = config
      plugins = config.plugins
      parked = LayoutBoard.parked(plugins)
      positions = LayoutBoard.boardPositions(plugins, parked: parked)
      pageTypes = LayoutBoard.pageTypes(config)
      frames = model.frames
      groupNames = LayoutBoard.groupNames(config, frames: frames)
      pluginFrames = Set((model.pluginFrames ?? [:]).values)
      var chosen: [String: (name: String, from: PageTypeOverride.FrameOrigin)] = [:]
      var shapes: [String: LayoutStage.Shape?] = [:]
      for type in pageTypes {
        let frame = PageTypeOverride.resolvedFrame(config, type, pluginFrames: model.pluginFrames ?? [:])
        chosen[type] = frame
        shapes[type] = LayoutStage.shape(frame.name, frames: model.frames, pluginFrames: pluginFrames)
      }
      self.chosen = chosen
      self.shapes = shapes
      counts = LayoutBoard.nameCounts(plugins)
      ranks = LayoutEntries.duplicateRanks(plugins)
    }

    var placed: [Int] { LayoutEntries.positions.flatMap { positions[$0] ?? [] } }
    func label(_ i: Int) -> String { (counts[plugins[i].name] ?? 0) > 1 ? "\(plugins[i].name) #\(ranks[i] ?? 1)" : plugins[i].name }
    func layout(_ i: Int) -> JSONObject { LayoutEntries.layout(plugins[i]) ?? JSONObject() }
    func group(_ i: Int) -> String? { layout(i)["group"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
    func display(_ i: Int) -> String { layout(i)["display"]?.stringValue ?? "all" }
    func customized(_ type: String) -> Bool { PageTypeOverride.customizes(PageTypeOverride.stored(config, type)?.objectValue) }
    func openable(_ name: String) -> Bool { name == "default" || frames.contains { $0.frameName == name } }
  }

  // MARK: figures

  private func tiles(_ facts: Facts) -> some View {
    let placed = facts.placed
    let desktop = placed.filter { facts.display($0) == "desktop-only" }.count
    let mobile = placed.filter { facts.display($0) == "mobile-only" }.count
    let conditioned = placed.filter { facts.layout($0)["condition"] != nil }.count
    let customized = facts.pageTypes.filter(facts.customized).count
    let used = Set(facts.chosen.values.map(\.name))
    let unused = facts.frames.filter { !used.contains($0.frameName) }.count
    return FlowLayout(spacing: 8, minItem: 0, stretch: false) {
      tile(.placed, placed.count, L10n.t("layoutEditor.overview.statPlaced", count: placed.count),
           "\(L10n.t("layoutEditor.overview.statAlways", count: placed.count - desktop - mobile)) · \(desktop) \(L10n.t("layoutEditor.displayDesktopOnly")) · \(mobile) \(L10n.t("layoutEditor.displayMobileOnly"))")
      tile(.conditioned, conditioned, L10n.t("layoutEditor.overview.statConditioned", count: conditioned), nil)
      tile(.disabled, facts.parked.count, L10n.t("layoutEditor.overview.statDisabled", count: facts.parked.count), nil)
      tile(.pageTypes, facts.pageTypes.count, L10n.t("layoutEditor.overview.statPageTypes", count: facts.pageTypes.count),
           L10n.t("layoutEditor.overview.statCustomized", count: customized))
      tile(.frames, facts.frames.count, L10n.t("layoutEditor.overview.statFrames", count: facts.frames.count),
           unused > 0 ? L10n.t("layoutEditor.overview.statUnused", count: unused) : nil)
    }
  }

  /// A figure is a switch: it opens what it counts right under the figures, one at a time.
  private func tile(_ tile: Tile, _ value: Int, _ label: String, _ extra: String?) -> some View {
    let open = openTile == tile.rawValue
    return Button {
      openTile = open ? "" : tile.rawValue
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(verbatim: "\(value)").font(.title2.weight(.semibold))
          Spacer()
          Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
        }
        Text(label).font(.caption).foregroundStyle(.secondary)
        if let extra { Text(extra).font(.caption2).foregroundStyle(.tertiary) }
      }
      .frame(minWidth: 140, alignment: .leading)
      .padding(10)
      .background(RoundedRectangle(cornerRadius: 8).fill(open ? Color.accentColor.opacity(0.12) : Color.clear))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(open ? Color.accentColor : Color.secondary.opacity(0.3)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(open ? .isSelected : [])
    .accessibilityIdentifier("layout.overview.tile.\(tile.rawValue)")
  }

  // MARK: the panels under the figures

  private func pill(_ i: Int, _ facts: Facts, muted: Bool = false) -> some View {
    ComponentPill(plugin: facts.plugins[i], label: facts.label(i), groupNames: facts.groupNames, muted: muted) { openPageType("", i) }
      .fixedSize()
  }

  private func placedRow(_ i: Int, _ facts: Facts, detail: String? = nil) -> some View {
    HStack(spacing: 8) {
      pill(i, facts)
      Text([LayoutWords.position(facts.layout(i)["position"]?.stringValue ?? ""), detail].compactMap { $0 }.joined(separator: " · "))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private func panel(_ tile: Tile, _ facts: Facts) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      switch tile {
      case .placed:
        Text(L10n.t("layoutEditor.overview.panelPlacedTitle")).font(.headline)
        if facts.placed.isEmpty { Note(L10n.t("layoutEditor.overview.panelPlacedNone")) }
        ForEach([("all", L10n.t("layoutEditor.overview.panelAlways")), ("desktop-only", L10n.t("layoutEditor.displayDesktopOnly")),
                 ("mobile-only", L10n.t("layoutEditor.displayMobileOnly"))], id: \.0) { display, title in
          let items = facts.placed.filter { facts.display($0) == display }
          if !items.isEmpty {
            Text("\(title) \(items.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            FlowLayout(spacing: 12, minItem: 0, stretch: false) { ForEach(items, id: \.self) { placedRow($0, facts) } }
          }
        }
      case .conditioned:
        let items = facts.placed.filter { facts.layout($0)["condition"] != nil }
        Text(L10n.t("layoutEditor.overview.panelConditionedTitle")).font(.headline)
        if items.isEmpty { Note(L10n.t("layoutEditor.overview.panelConditionedNone")) }
        ForEach(items, id: \.self) { i in
          placedRow(i, facts, detail: LayoutWords.condition(facts.layout(i)["condition"]?.stringValue ?? ""))
        }
      case .disabled:
        Text(L10n.t("layoutEditor.overview.disabledTitle")).font(.headline)
        if facts.parked.isEmpty {
          Note(L10n.t("layoutEditor.overview.disabledNone"))
        } else {
          Note(L10n.t("layoutEditor.overview.disabledText"))
          FlowLayout(spacing: 6, minItem: 0, stretch: false) { ForEach(facts.parked.sorted(), id: \.self) { pill($0, facts, muted: true) } }
        }
      case .pageTypes:
        Text(L10n.t("layoutEditor.overview.panelPageTypesTitle")).font(.headline)
        ForEach(facts.pageTypes, id: \.self) { type in
          let override = PageTypeOverride.of(facts.config, type)
          let hidden = facts.placed.filter { PageTypeOverride.isExcluded(override, facts.plugins[$0]) }
          let cleared = LayoutEntries.positions.filter { PageTypeOverride.isCleared(override, $0) }
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              Button(LayoutWords.pageType(type)) { openPageType(type, nil) }.buttonStyle(.link)
              framePill(facts.chosen[type]!.name, facts.chosen[type]!.from, facts)
              if !facts.customized(type) { Text(L10n.t("layoutEditor.overview.panelSameAsAll")).font(.caption).foregroundStyle(.secondary) }
            }
            if !hidden.isEmpty {
              FlowLayout(spacing: 6, minItem: 0, stretch: false) {
                Text(L10n.t("layoutEditor.overview.panelHidden")).font(.caption).foregroundStyle(.secondary)
                ForEach(hidden, id: \.self) { pill($0, facts, muted: true) }
              }
            }
            if !cleared.isEmpty {
              Text("\(L10n.t("layoutEditor.overview.panelCleared")) \(cleared.map(LayoutWords.position).joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Divider()
        }
      case .frames:
        Text(L10n.t("layoutEditor.overview.framesTitle")).font(.headline)
        framesList(facts)
      }
    }
  }

  private func framesList(_ facts: Facts) -> some View {
    let used = facts.chosen.values.map(\.name)
    var list: [(String, String)] = [("default", "builtin")] + facts.frames.map { ($0.frameName, "own") }
    for name in Array(NSOrderedSet(array: used)).compactMap({ $0 as? String })
    where name != "default" && !facts.frames.contains(where: { $0.frameName == name }) && !list.contains(where: { $0.0 == name }) {
      list.append((name, facts.pluginFrames.contains(name) ? "plugin" : "builtin"))
    }
    return ForEach(list, id: \.0) { name, kind in
      let users = facts.pageTypes.filter { facts.chosen[$0]?.name == name }
      let own = facts.frames.first { $0.frameName == name }
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          framePill(name, nil, facts)
          Text(kind == "own" ? L10n.t("layoutEditor.overview.frameKind.own") : kind == "plugin" ? L10n.t("layoutEditor.overview.frameKind.plugin")
               : L10n.t("layoutEditor.overview.frameKind.builtin")).font(.caption).foregroundStyle(.secondary)
          if users.isEmpty { WordBadge(text: L10n.t("layoutEditor.overview.unassigned")).foregroundStyle(.orange) }
        }
        if !users.isEmpty {
          HStack(spacing: 6) { ForEach(users, id: \.self) { type in Button(LayoutWords.pageType(type)) { openPageType(type, nil) }.controlSize(.small) } }
        }
        let areas = (own?.areas ?? []).filter { $0.group != nil && $0.slot != nil && $0.slot != "pageBody" }
        if !areas.isEmpty {
          FlowLayout(spacing: 6, minItem: 0, stretch: false) {
            Text(L10n.t("layoutEditor.overview.customAreas")).font(.caption).foregroundStyle(.secondary)
            ForEach(areas) { area in
              Text("\(area.name) · \(LayoutWords.position(area.slot ?? ""))").font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .foregroundStyle(LayoutWords.groupColor(area.group, facts.groupNames) ?? .primary)
                .overlay(Capsule().strokeBorder((LayoutWords.groupColor(area.group, facts.groupNames) ?? .secondary).opacity(0.5)))
            }
          }
        }
        Divider()
      }
    }
  }

  // MARK: the matrix

  private func framePill(_ name: String, _ from: PageTypeOverride.FrameOrigin?, _ facts: Facts) -> some View {
    let origin: String? = switch from {
    case .override?: L10n.t("layoutEditor.overview.frameFrom.override")
    case .plugin?: L10n.t("layoutEditor.overview.frameFrom.plugin")
    case .default?: L10n.t("layoutEditor.overview.frameFrom.default")
    case nil: nil
    }
    let body = HStack(spacing: 3) {
      Image(systemName: "rectangle.split.3x1").font(.caption2).foregroundStyle(.secondary)
      Text(LayoutWords.frame(name)).lineLimit(1)
      if from == .override { Image(systemName: "pin").font(.caption2).foregroundStyle(.secondary) }
      if from == .plugin { Image(systemName: "puzzlepiece.extension").font(.caption2).foregroundStyle(.secondary) }
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 6).padding(.vertical, 2)
    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(from == .default ? 0.08 : 0.15)))
    return Group {
      if facts.openable(name) {
        Button { openFrame(name) } label: { body }.buttonStyle(.plain)
      } else {
        body
      }
    }
    .help(origin ?? LayoutWords.frame(name))
    .accessibilityLabel(origin.map { "\(LayoutWords.frame(name)) – \($0)" } ?? LayoutWords.frame(name))
  }

  static func symbol(_ cell: LayoutStage.Cell) -> (String, Color)? {
    switch cell {
    case .shown: nil
    case .someWidths: ("circle.dotted", .green)
    case .excluded: ("eye.slash", .secondary)
    case .cleared: ("nosign", .secondary)
    case .noArea: ("square.dashed", .orange)
    case .hiddenArea: ("circle.slash", .orange)
    case .noWidth: ("rectangle.and.arrow.up.right.and.arrow.down.left.slash", .orange)
    case .unknown: ("questionmark.circle", .secondary)
    }
  }

  static func stateText(_ cell: LayoutStage.Cell) -> String {
    switch cell {
    case .shown: L10n.t("layoutEditor.overview.state.shown")
    case .someWidths(let on): L10n.t("layoutEditor.overview.someWidthsOn", ["breakpoints": on.map(LayoutWords.breakpoint).joined(separator: ", ")])
    case .excluded: L10n.t("layoutEditor.overview.state.excluded")
    case .cleared: L10n.t("layoutEditor.overview.state.cleared")
    case .noArea: L10n.t("layoutEditor.overview.state.noArea")
    case .hiddenArea: L10n.t("layoutEditor.overview.state.hiddenArea")
    case .noWidth: L10n.t("layoutEditor.overview.state.noWidth")
    case .unknown: L10n.t("layoutEditor.overview.state.unknown")
    }
  }

  @ViewBuilder static func mark(_ cell: LayoutStage.Cell) -> some View {
    if let (symbol, color) = symbol(cell) {
      Image(systemName: symbol).foregroundStyle(color)
    } else {
      Circle().fill(.green).frame(width: 9, height: 9)
    }
  }

  private func matrix(_ facts: Facts) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
      GridRow {
        Text(L10n.t("layoutEditor.overview.componentColumn")).font(.caption).foregroundStyle(.clear).accessibilityHidden(true)
        ForEach(facts.pageTypes, id: \.self) { type in
          Button { openPageType(type, nil) } label: {
            HStack(spacing: 3) {
              Text(LayoutWords.pageType(type)).fontWeight(.medium)
              if facts.customized(type) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                  .accessibilityLabel(L10n.t("layoutEditor.overview.customized")).help(L10n.t("layoutEditor.overview.customized"))
              }
            }
          }
          .buttonStyle(.plain)
          .gridColumnAlignment(.center)
        }
      }
      GridRow {
        Text(L10n.t("layoutEditor.overview.assignedFrame")).font(.caption).foregroundStyle(.secondary)
        ForEach(facts.pageTypes, id: \.self) { type in framePill(facts.chosen[type]!.name, facts.chosen[type]!.from, facts) }
      }
      ForEach(LayoutEntries.positions, id: \.self) { position in
        let items = facts.positions[position] ?? []
        Divider().gridCellUnsizedAxes(.horizontal)
        GridRow {
          HStack(spacing: 6) {
            Text(LayoutWords.position(position)).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            Text(items.isEmpty ? L10n.t("layoutEditor.overview.empty") : "\(items.count)").font(.caption).foregroundStyle(.tertiary)
              .accessibilityLabel(items.isEmpty ? L10n.t("layoutEditor.overview.empty") : L10n.t("layoutEditor.overview.componentCount", count: items.count))
          }
          .gridCellColumns(facts.pageTypes.count + 1)
        }
        ForEach(items.filter { facts.group($0) == nil }, id: \.self) { row($0, facts) }
        ForEach(facts.groupNames.filter { g in items.contains { facts.group($0) == g } }, id: \.self) { group in
          groupHead(position, group, facts)
          ForEach(items.filter { facts.group($0) == group }, id: \.self) { row($0, facts) }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("layout.overview.matrix")
  }

  private func groupHead(_ position: String, _ group: String, _ facts: Facts) -> some View {
    let ownIn = facts.frames.filter { $0.areas.contains { $0.slot == position && $0.group == group } }
    let names = Array(NSOrderedSet(array: ownIn.flatMap { $0.areas.filter { $0.slot == position && $0.group == group }.map(\.name) })).compactMap { $0 as? String }
    let color = LayoutWords.groupColor(group, facts.groupNames) ?? .secondary
    return GridRow {
      HStack(spacing: 6) {
        if names.isEmpty {
          Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
          Text(L10n.t("layoutEditor.overview.flexGroup", ["name": group])).font(.caption.weight(.medium))
        } else {
          RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 2).frame(width: 9, height: 9).accessibilityHidden(true)
          Text(L10n.t("layoutEditor.overview.ownArea", ["name": names.joined(separator: ", ")])).font(.caption.weight(.medium))
          Text(L10n.t("layoutEditor.overview.ownAreaIn")).font(.caption).foregroundStyle(.secondary)
          ForEach(ownIn) { framePill($0.frameName, nil, facts) }
        }
      }
      .padding(.leading, 12)
      .gridCellColumns(facts.pageTypes.count + 1)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(LayoutWords.position(position)): \(names.isEmpty ? L10n.t("layoutEditor.overview.flexGroup", ["name": group]) : L10n.t("layoutEditor.overview.ownArea", ["name": names.joined(separator: ", ")]))")
    }
  }

  private func row(_ i: Int, _ facts: Facts) -> some View {
    GridRow {
      pill(i, facts).padding(.leading, 12)
      ForEach(facts.pageTypes, id: \.self) { type in
        let cell = LayoutStage.cell(facts.config, i, pageType: type, shape: facts.shapes[type] ?? nil)
        let text = L10n.t("layoutEditor.overview.cellTitle", ["component": facts.label(i), "pageType": LayoutWords.pageType(type), "state": Self.stateText(cell)])
        Self.mark(cell)
          .frame(minWidth: 20)
          .help(text)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(text)
          .gridColumnAlignment(.center)
      }
    }
  }

  private var legend: some View {
    let states: [LayoutStage.Cell] = [.shown, .someWidths([]), .excluded, .cleared, .noArea, .hiddenArea, .noWidth, .unknown]
    return FlowLayout(spacing: 14, minItem: 0, stretch: false) {
      ForEach(Array(states.enumerated()), id: \.offset) { _, cell in
        HStack(spacing: 5) {
          Self.mark(cell).frame(width: 16)
          Text(cell == .someWidths([]) ? L10n.t("layoutEditor.overview.state.someWidths") : Self.stateText(cell))
        }
      }
      HStack(spacing: 5) { Image(systemName: "desktopcomputer"); Text(L10n.t("layoutEditor.displayDesktopOnly")) }
      HStack(spacing: 5) { Image(systemName: "iphone"); Text(L10n.t("layoutEditor.displayMobileOnly")) }
      HStack(spacing: 5) { Image(systemName: "line.3.horizontal.decrease.circle"); Text(L10n.t("layoutEditor.overview.legendCondition")) }
      HStack(spacing: 5) { Image(systemName: "pin"); Text(L10n.t("layoutEditor.overview.frameFrom.override")) }
      HStack(spacing: 5) { Image(systemName: "puzzlepiece.extension"); Text(L10n.t("layoutEditor.overview.frameFrom.plugin")) }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.t("layoutEditor.overview.legend"))
  }
}
