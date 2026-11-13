import QuartzHubCore
import SwiftUI

/// Where a drop on the stage lands.
enum StageDropTarget: Equatable {
  /// Before this component, in its area.
  case chip(Int)
  /// At the end of an area: a position's plain area (group nil) or a group's own.
  case area(position: String, group: String?, name: String)
  /// The tray: a duplicate goes, a sole instance is switched off.
  case tray
}

/// What the stage works out from the page's draft, once per drawing.
struct StageFacts {
  let config: QuartzConfig
  let plugins: [PluginEntry]
  let parked: Set<Int>
  let positions: [String: [Int]]
  let counts: [String: Int]
  let ranks: [Int: Int]
  let pageTypes: [String]
  let pageType: String?
  let override: JSONObject?
  let groupNames: [String]
  let frameChoice: (name: String, from: PageTypeOverride.FrameOrigin)
  let frame: LayoutStage.Frame

  @MainActor init(model: LayoutModel, config: QuartzConfig, storedPageType: String) {
    self.config = config
    plugins = config.plugins
    parked = LayoutBoard.parked(plugins)
    positions = LayoutBoard.boardPositions(plugins, parked: parked)
    counts = LayoutBoard.nameCounts(plugins)
    ranks = LayoutEntries.duplicateRanks(plugins)
    pageTypes = LayoutBoard.pageTypes(config)
    // A type that is gone falls back to all pages rather than to a selector showing nothing.
    pageType = pageTypes.contains(storedPageType) ? storedPageType : nil
    override = pageType.map { PageTypeOverride.of(config, $0) }
    groupNames = LayoutBoard.groupNames(config, frames: model.frames)
    // "All pages" has no frame of its own and is drawn in the content pages' one.
    frameChoice = PageTypeOverride.resolvedFrame(config, pageType ?? "content", pluginFrames: model.pluginFrames ?? [:])
    frame = LayoutStage.frame(named: frameChoice.name, frames: model.frames, pluginFrames: model.pluginFrames ?? [:])
  }

  func label(_ index: Int) -> String {
    let name = plugins[index].name
    return (counts[name] ?? 0) > 1 ? "\(name) #\(ranks[index] ?? 1)" : name
  }

  var typeLabel: String { pageType.map(LayoutWords.pageType) ?? "" }

  func hiddenReason(_ index: Int, bp: String?) -> String? {
    guard let reason = LayoutStage.hidden(plugins[index], override: override, bp: bp) else { return nil }
    return LayoutWords.hidden(reason, type: pageType ?? "")
  }

  func hiddenOnTypes(_ index: Int) -> String? {
    guard pageType == nil else { return nil }
    let types = LayoutStage.hiddenOnTypes(config, plugins[index], pageTypes: pageTypes)
    return types.isEmpty ? nil : L10n.t("layoutEditor.componentPill.hiddenOnTypes", ["types": types.map(LayoutWords.pageType).joined(separator: ", ")])
  }

  func customized(_ type: String) -> Bool {
    PageTypeOverride.customizes(PageTypeOverride.stored(config, type)?.objectValue)
  }
}

/// Komponenten, the stage (QuartzControl's `GlobalBoard.tsx`): the page in miniature, drawn in the
/// frame the shown page type is built with, with the tray above and the flex groups below. A drag
/// moves a component; the inspector does the same by keyboard (position, earlier/later, tray).
struct StageTab: View {
  @Bindable var model: LayoutModel
  @Binding var selected: String
  @Binding var storedPageType: String
  @Binding var breakpoint: String
  let editFrame: (FrameView) -> Void

  @State private var trayTargeted = false
  @State private var dragging: String?
  @State private var newGroup = ""

  var body: some View {
    if let config = model.config {
      let facts = StageFacts(model: model, config: config, storedPageType: storedPageType)
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.m) {
          header(facts)
          tray(facts)
          stage(facts)
          groupsPanel(config)
        }
        .padding(Spacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .onExitCommand { selected = "" }
    }
  }

  // MARK: selection and changes

  private func select(_ plugins: [PluginEntry], _ index: Int?) {
    guard let index, let ref = LayoutEntries.componentRef(plugins, index) else {
      selected = ""
      return
    }
    selected = "\(ref.name)\n\(ref.occurrence)"
  }

  private func apply(_ plugins: [PluginEntry], select index: Int?? = nil) {
    model.config?.plugins = plugins
    if let index { select(plugins, index) }
  }

  // MARK: the head

  private func header(_ facts: StageFacts) -> some View {
    let own: FrameView? = if case .own(let frame) = facts.frame { frame } else { nil }
    return WorkspaceHeader(symbol: facts.pageType == nil ? "doc.on.doc" : "doc.text", kicker: L10n.t("layoutEditor.pageType.label"),
                           title: facts.pageType == nil ? L10n.t("layoutEditor.pageType.all") : facts.typeLabel) {
        fact("rectangle.split.3x1", L10n.t("layoutEditor.summary.frame"), LayoutWords.frame(facts.frameChoice.name))
        fact(LayoutWords.breakpointSymbol(breakpoint), nil, LayoutWords.breakpoint(breakpoint))
        if let type = facts.pageType, facts.customized(type) {
          fact("slider.horizontal.3", nil, L10n.t("layoutEditor.context.customized")).foregroundStyle(.tint)
        }
    } controls: {
      // Wraps: beside each other the two are wider than the middle of the smallest window.
      FlowLayout(spacing: 12, minItem: 0, stretch: false) {
        Picker(L10n.t("layoutEditor.pageType.label"), selection: $storedPageType) {
          Text(L10n.t("layoutEditor.pageType.all")).tag("")
          ForEach(facts.pageTypes, id: \.self) { type in
            Text(facts.customized(type) ? L10n.t("layoutEditor.pageType.customized", ["type": LayoutWords.pageType(type)]) : LayoutWords.pageType(type))
              .tag(type)
          }
        }
        .fixedSize()
        .accessibilityIdentifier("layout.pageType")
        // With the widths, without, as a menu: whatever the middle of the window holds.
        ViewThatFits(in: .horizontal) {
          viewPicker(ranges: own != nil).pickerStyle(.segmented).fixedSize()
          viewPicker(ranges: false).pickerStyle(.segmented).fixedSize()
          viewPicker(ranges: own != nil).pickerStyle(.menu).fixedSize()
        }
      }
      FlowLayout(spacing: 12, minItem: 0, stretch: false) {
        if let type = facts.pageType {
          framePicker(facts, type)
        } else {
          Text(L10n.t("layoutEditor.pageType.allPagesFrame", ["name": LayoutWords.frame(facts.frameChoice.name)]))
            .font(.callout).foregroundStyle(.secondary).fixedSize()
        }
        if model.features.sidebars {
          sidebarPicker(facts, "left")
          sidebarPicker(facts, "right")
        }
        if let own {
          Button { editFrame(own) } label: { Label(L10n.t("layoutEditor.stage.editFrame"), systemImage: "rectangle.split.3x3") }
        }
        if let type = facts.pageType, PageTypeOverride.stored(facts.config, type) != nil {
          Button {
            model.config = PageTypeOverride.without(facts.config, type)
            Announce.post(L10n.t("layoutEditor.pageType.removedAnnounce", ["type": facts.typeLabel]))
          } label: { Label(L10n.t("layoutEditor.pageType.removeOverride"), systemImage: "arrow.uturn.backward") }
        }
      }
      hints(facts)
    }
  }

  private func viewPicker(ranges: Bool) -> some View {
    Picker(L10n.t("layoutEditor.stage.viewLabel"), selection: $breakpoint) {
      ForEach(LayoutBoard.breakpoints, id: \.self) { bp in
        Text(ranges ? "\(LayoutWords.breakpoint(bp)) · \(LayoutBoard.rangeLabel(bp, widths: model.widths))" : LayoutWords.breakpoint(bp)).tag(bp)
      }
    }
    .accessibilityIdentifier("layout.view")
  }

  private func fact(_ symbol: String, _ label: String?, _ value: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: symbol).accessibilityHidden(true)
      if let label { Text(label).foregroundStyle(.secondary) }
      Text(value).fontWeight(.medium)
    }
    .font(.caption)
    .padding(.horizontal, 8).padding(.vertical, 2)
    .overlay(Capsule().strokeBorder(.separator))
  }

  /// The frame of a page type. Leaving `template` unset is the plugin's own frame where it brings
  /// one, so that option stands for it and "Standard" writes `template: default`. A value none of
  /// the options has stays visible as itself.
  private func framePicker(_ facts: StageFacts, _ type: String) -> some View {
    let plugin = model.pluginFrames?["\(type)-page"]
    let hasPluginDefault = plugin != nil && plugin != "default"
    let noOverride = hasPluginDefault ? plugin! : "default"
    let template = facts.override?["template"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    let authored = model.frames.map(\.frameName)
    let unknown = template.flatMap { t in PageTypeOverride.builtinFrames.contains(t) || authored.contains(t) || t == plugin ? nil : t }
    return Picker(L10n.t("layoutEditor.template"), selection: Binding(get: { template ?? noOverride }, set: { value in
      model.config = PageTypeOverride.withTemplate(facts.config, type, value == noOverride ? nil : value)
    })) {
      if hasPluginDefault, let plugin { Text(L10n.t("layoutEditor.templatePluginDefault", ["frame": plugin])).tag(plugin) }
      Text(L10n.t("layoutEditor.templateDefault")).tag("default")
      Text(L10n.t("layoutEditor.templateFullWidth")).tag("full-width")
      Text(L10n.t("layoutEditor.templateMinimal")).tag("minimal")
      ForEach(authored, id: \.self) { Text(verbatim: $0).tag($0) }
      if let unknown { Text(L10n.t("layoutEditor.pageType.unknownOption", ["frame": unknown])).tag(unknown) }
    }
    .fixedSize()
    .accessibilityIdentifier("layout.frame")
  }

  /// Quartz 5.1's `sidebars`: for all pages `layout.sidebars`, for a page type its own. On a page
  /// type the first option is "as for all pages" and names what that is; choosing it removes the
  /// page type's value.
  private func sidebarPicker(_ facts: StageFacts, _ side: String) -> some View {
    let current = PageTypeOverride.sidebar(facts.config, facts.pageType, side)
    let inherited = PageTypeOverride.sidebar(facts.config, nil, side).mode
    let inherit = "inherit"
    return Picker(side == "left" ? L10n.t("layoutEditor.sidebars.left") : L10n.t("layoutEditor.sidebars.right"),
                  selection: Binding(get: { current.own || facts.pageType == nil ? current.mode : inherit }, set: { value in
      let mode: String? = value == inherit || (facts.pageType == nil && value == "fit") ? nil : value
      model.config = PageTypeOverride.withSidebar(facts.config, facts.pageType, side, mode)
    })) {
      if facts.pageType != nil {
        Text(L10n.t("layoutEditor.sidebars.inherit", ["mode": Self.sidebarWord(inherited)])).tag(inherit)
      }
      ForEach(PageTypeOverride.sidebarModes, id: \.self) { Text(Self.sidebarWord($0)).tag($0) }
    }
    .fixedSize()
    .help(L10n.t("layoutEditor.sidebars.help"))
    .accessibilityIdentifier("layout.sidebars.\(side)")
  }

  static func sidebarWord(_ mode: String) -> String {
    switch mode {
    case "scroll": L10n.t("layoutEditor.sidebars.scroll")
    case "static": L10n.t("layoutEditor.sidebars.static")
    default: L10n.t("layoutEditor.sidebars.fit")
    }
  }

  @ViewBuilder private func hints(_ facts: StageFacts) -> some View {
    let dead = facts.override.map { PageTypeOverride.deadExcludes(facts.config, $0) } ?? []
    let unknownFrame: String? = if case .unknown(let name) = facts.frame, model.framesLoaded, model.pluginFrames != nil { name } else { nil }
    // Quartz renders the sidebar modes in its default frame only (DefaultFrame's
    // data-sidebar-mode); an own frame is a grid whose areas scroll with the page, and
    // full-width/minimal have no sidebars (measured on the 5.1 copy of gui-test: no page carried it).
    let sidebarsIdle: Bool = model.features.sidebars && {
      switch facts.frame {
      case .standard, .unknown: false
      default: true
      }
    }()
    if facts.pageType != nil || !dead.isEmpty || unknownFrame != nil || sidebarsIdle {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if facts.pageType != nil { Note(L10n.t("layoutEditor.pageType.scopeHint", ["type": facts.typeLabel])) }
        if sidebarsIdle { Note(L10n.t("layoutEditor.sidebars.idleHint")) }
        if !dead.isEmpty {
          Callout(.warning, L10n.t("layoutEditor.excludeDeadHint", ["names": dead.joined(separator: ", ")], count: dead.count))
        }
        if let unknownFrame { Callout(.warning, L10n.t("layoutEditor.pageType.unknownFrame", ["frame": unknownFrame])) }
      }
    }
  }

  // MARK: the tray

  private func tray(_ facts: StageFacts) -> some View {
    let dragged = dragging.flatMap { $0.hasPrefix("board:") ? Int($0.dropFirst(6)) : nil }
    let hint: String = if let dragged, facts.plugins.indices.contains(dragged) {
      (facts.counts[facts.plugins[dragged].name] ?? 0) > 1 ? L10n.t("layoutEditor.componentPill.paletteDropToRemove")
        : L10n.t("layoutEditor.componentPill.paletteDropToDisable")
    } else {
      L10n.t("layoutEditor.componentPill.paletteLabel")
    }
    return VStack(alignment: .leading, spacing: 6) {
      Text(hint).font(.caption.weight(.medium)).foregroundStyle(.secondary)
      FlowLayout(spacing: 6, minItem: 0, stretch: false) {
        ForEach(LayoutBoard.trayChips(facts.plugins), id: \.self) { index in
          PaletteChip(name: facts.plugins[index].name, off: facts.parked.contains(index))
            .fixedSize()
            .draggable("palette:\(index)") { PaletteChip(name: facts.plugins[index].name, off: facts.parked.contains(index)) }
            .accessibilityIdentifier("layout.tray.\(facts.plugins[index].name)")
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8).fill(trayTargeted && dragged != nil ? Color.red.opacity(0.08) : Color.clear))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(trayTargeted && dragged != nil ? Color.red.opacity(0.6) : Color.secondary.opacity(0.3),
                                                              style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
      .dropDestination(for: String.self) { items, _ in
        drop(items.first, onto: .tray, facts)
      } isTargeted: { trayTargeted = $0 }
      Note(L10n.t("layoutEditor.componentPill.paletteHint"))
    }
  }

  // MARK: the stage

  @ViewBuilder private func stage(_ facts: StageFacts) -> some View {
    let reference = StageGeometry.referenceWidth[breakpoint] ?? 1456
    VStack(alignment: .leading, spacing: 8) {
      Group {
        switch facts.frame {
        case .own(let frame):
          ownFrame(frame, facts)
        case .builtin(_, let slots):
          VStack(spacing: 12) {
            ForEach(["header", "beforeBody"].filter(slots.contains), id: \.self) { areaBox(position: $0, facts) }
            pageContent
            ForEach(["afterBody", "footer"].filter(slots.contains), id: \.self) { areaBox(position: $0, facts) }
          }
        case .plugin(let name):
          Text(L10n.t("layoutEditor.pluginFrameUnknownLayout", ["frame": name]))
            .font(.callout).foregroundStyle(.orange).frame(maxWidth: .infinity).padding(20)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        case .standard, .unknown:
          standardFrame(facts)
        }
      }
      .frame(maxWidth: reference)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onTapGesture { selected = "" }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("layout.stage")
      if case .own(let frame) = facts.frame {
        let approximate = StageGeometry.frame(frame.layout(breakpoint), breakpoint).tracks.approximate
        if !approximate.isEmpty {
          Note(L10n.t("layoutEditor.stage.approximate", ["sizes": Array(NSOrderedSet(array: approximate)).compactMap { $0 as? String }.joined(separator: ", ")]))
        }
      }
      let missing = LayoutStage.missingPositions(facts.frame, breakpoint)
      if !missing.isEmpty {
        Callout(.warning, L10n.t("layoutEditor.frameBuilder.unassignedWarning", ["slots": missing.map(LayoutWords.position).joined(separator: ", ")]))
      }
    }
  }

  private var pageContent: some View {
    Text(L10n.t("layoutEditor.frameBuilder.preview.pageContent"))
      .font(.callout).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity).padding(.vertical, 10)
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
  }

  private func ownFrame(_ frame: FrameView, _ facts: StageFacts) -> some View {
    let layout = frame.layout(breakpoint)
    let stage = StageGeometry.frame(layout, breakpoint)
    return StageGridLayout(weights: stage.tracks.weights, rows: layout.rows, columnGap: stage.columnGap / 100, rowGap: stage.rowGap / 100,
                           width: stage.width / 100, align: stage.align, paddingInline: stage.paddingInline / 100,
                           paddingBlock: stage.paddingBlock / 100) {
      ForEach(LayoutStage.shownAreas(frame, breakpoint)) { area in
        let p = frame.placement(breakpoint, area.id)!
        Group {
          if area.slot == nil || area.slot == "pageBody" {
            AreaBox(label: area.name, slotLabel: area.slot.map(LayoutWords.position) ?? L10n.t("layoutEditor.frameBuilder.slotNone")) {
              if area.slot == nil {
                Text(L10n.t("layoutEditor.frameBuilder.slotNone")).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
              } else {
                pageContent
              }
            }
          } else {
            let position = area.slot!
            AreaBox(label: area.name, slotLabel: LayoutWords.position(position), action: { clearAction(position, facts) }) {
              slot(position: position, group: area.group, areaName: area.name,
                   indices: LayoutStage.indices(for: area, in: frame, positions: facts.positions, plugins: facts.plugins), row: false, facts)
            }
          }
        }
        .gridCell(row: p.row, col: p.col, rowSpan: p.rowSpan, colSpan: p.colSpan)
      }
    }
  }

  /// Quartz's DefaultFrame, per view (`DEFAULT_FRAME_GRID`): the sidebars beside the middle column
  /// on desktop, the right one below the page on tablet, one column on mobile.
  private func standardFrame(_ facts: StageFacts) -> some View {
    let measures = FrameEditing.columnsFit(model.standardMeasures, breakpoint) ? model.standardMeasures : FrameEditing.quartzMeasures
    let reference = StageGeometry.referenceWidth[breakpoint] ?? 1456
    let tracks = StageGeometry.tracks(measures.grids[breakpoint]?.columns ?? ["auto"], inner: reference, gap: 12, viewport: reference)
    let cells: [(String, Int, Int, Int)] = switch breakpoint {
    case "desktop": [("left", 1, 1, 3), ("header", 1, 2, 1), ("center", 2, 2, 1), ("footer", 3, 2, 1), ("right", 1, 3, 3)]
    case "tablet": [("left", 1, 1, 4), ("header", 1, 2, 1), ("center", 2, 2, 1), ("right", 3, 2, 1), ("footer", 4, 2, 1)]
    default: [("left", 1, 1, 1), ("header", 2, 1, 1), ("center", 3, 1, 1), ("right", 4, 1, 1), ("footer", 5, 1, 1)]
    }
    return StageGridLayout(weights: tracks.weights, rows: cells.map { $0.1 + $0.3 - 1 }.max() ?? 1, columnGap: 12, rowGap: 12, points: true) {
      ForEach(cells, id: \.0) { name, row, col, span in
        Group {
          if name == "center" {
            VStack(spacing: 12) {
              areaBox(position: "beforeBody", facts)
              pageContent
              areaBox(position: "afterBody", facts)
            }
          } else {
            areaBox(position: name, facts, row: (name == "left" || name == "right") && LayoutBoard.sidebarIsRow(name, breakpoint))
          }
        }
        .gridCell(row: row, col: col, rowSpan: span)
      }
    }
  }

  private func areaBox(position: String, _ facts: StageFacts, row: Bool = false) -> some View {
    AreaBox(label: LayoutWords.position(position), action: { clearAction(position, facts) }) {
      slot(position: position, group: nil, areaName: LayoutWords.position(position), indices: facts.positions[position] ?? [], row: row, facts)
    }
  }

  /// The eraser in an area's head while a page type is shown: it clears the position, so every
  /// area of that position follows.
  @ViewBuilder private func clearAction(_ position: String, _ facts: StageFacts) -> some View {
    if let type = facts.pageType, let override = facts.override {
      let cleared = PageTypeOverride.isCleared(override, position)
      let params = ["position": LayoutWords.position(position), "type": facts.typeLabel]
      let title = cleared ? L10n.t("layoutEditor.pageType.restoreArea", params) : L10n.t("layoutEditor.pageType.clearArea", params)
      Button {
        model.config = PageTypeOverride.withCleared(facts.config, type, position, !cleared)
        Announce.post(cleared ? L10n.t("layoutEditor.pageType.restoredAnnounce", params) : L10n.t("layoutEditor.pageType.clearedAnnounce", params))
      } label: {
        Label(title, systemImage: cleared ? "arrow.uturn.backward" : "eraser")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .help(title)
    }
  }

  @ViewBuilder private func slot(position: String, group: String?, areaName: String, indices: [Int], row: Bool, _ facts: StageFacts) -> some View {
    let cleared = facts.override.map { PageTypeOverride.isCleared($0, position) } ?? false
    VStack(alignment: .leading, spacing: 5) {
      if cleared { Text(L10n.t("layoutEditor.pageType.areaCleared", ["type": facts.typeLabel])).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
      if indices.isEmpty {
        Text(L10n.t("layoutEditor.emptySlot")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
      } else if row {
        FlowLayout { ForEach(indices, id: \.self) { chip($0, facts) } }
      } else {
        ForEach(indices, id: \.self) { chip($0, facts) }
      }
    }
    .padding(4)
    // The whole area below its name is the drop target, as QuartzControl's `flex-1`: on the stage a
    // row is as tall as its tallest area, and a drop into the empty rest of a short column hit
    // nothing at all (measured 2026-11-10, „graph“ onto the left sidebar below its three chips).
    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    .dropDestination(for: String.self) { items, _ in
      return drop(items.first, onto: .area(position: position, group: group, name: areaName), facts)
    }
  }

  private func chip(_ index: Int, _ facts: StageFacts) -> some View {
    let label = facts.label(index)
    let isSelected = LayoutEntries.componentRef(facts.plugins, index).map { "\($0.name)\n\($0.occurrence)" } == selected
    return ComponentChip(plugin: facts.plugins[index], label: label, groupNames: facts.groupNames, selected: isSelected,
                         hiddenReason: facts.hiddenReason(index, bp: breakpoint), hiddenOnTypes: facts.hiddenOnTypes(index))
      .onTapGesture { select(facts.plugins, index) }
      .accessibilityAction { select(facts.plugins, index) }
      .draggable("board:\(index)") {
        ComponentChip(plugin: facts.plugins[index], label: label, groupNames: facts.groupNames).frame(width: 180)
          .onAppear { dragging = "board:\(index)" }
          .onDisappear { dragging = nil }
      }
      .dropDestination(for: String.self) { items, _ in
        return drop(items.first, onto: .chip(index), facts)
      }
      .accessibilityIdentifier("layout.chip.\(label)")
  }

  // MARK: dropping

  /// One drop, as QuartzControl's `handleDragEnd`: onto the tray a duplicate goes and a sole
  /// instance is switched off; onto the board a tray chip adds an instance (or switches a parked
  /// one back on there), and a placed one moves. The area decides the group: a group's area makes
  /// it a member, the plain area takes it out.
  private func drop(_ payload: String?, onto target: StageDropTarget, _ facts: StageFacts) -> Bool {
    dragging = nil
    guard let payload else { return false }
    let plugins = facts.plugins
    let fromTray = payload.hasPrefix("palette:")
    guard let index = Int(payload.split(separator: ":").last ?? ""), plugins.indices.contains(index) else { return false }
    let name = plugins[index].name
    let selectedIndex = Self.resolve(selected, plugins)

    if target == .tray {
      guard !fromTray else { return false }
      if (facts.counts[name] ?? 0) > 1 {
        let result = LayoutBoard.removing(plugins, index, selected: selectedIndex)
        apply(result.plugins, select: .some(result.selected))
        Announce.post(L10n.t("dnd.removed", ["name": name]))
      } else {
        apply(LayoutBoard.withEnabled(plugins, index, false), select: index)
        Announce.post(L10n.t("dnd.disabled", ["name": name]))
      }
      return true
    }

    let position: String, group: String?, insertAt: Int?, targetName: String
    switch target {
    case .chip(let over):
      position = LayoutEntries.layout(plugins[over])?["position"]?.stringValue ?? ""
      group = LayoutEntries.layout(plugins[over])?["group"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
      insertAt = facts.positions[position]?.firstIndex(of: over)
      targetName = facts.label(over)
    case .area(let p, let g, let areaName):
      position = p
      group = g
      insertAt = nil
      // QuartzControl's `describeDragId`: an area bound to a group by its own name, a plain one by
      // its position's word. A frame area's name is an identifier ("left"), and it was said as
      // "graph eingeschaltet und bei left abgelegt." (measured 2026-11-10).
      targetName = g == nil ? LayoutWords.position(p) : areaName
    case .tray:
      return false
    }
    guard LayoutEntries.positions.contains(position) else { return false }

    if fromTray {
      if facts.parked.contains(index) {
        let on = LayoutBoard.withEnabled(plugins, index, true)
        apply(LayoutEntries.place(on, index: index, position: position, insertIndex: insertAt, group: .some(group), positions: facts.positions), select: index)
        Announce.post(L10n.t("dnd.reenabled", ["name": name, "target": targetName]))
        return true
      }
      guard let result = LayoutBoard.appendDuplicate(plugins, index, position: position, insertIndex: insertAt, styled: model.styled) else { return false }
      apply(LayoutBoard.withGroup(result.plugins, result.newIndex, group ?? ""), select: result.newIndex)
      Announce.post(L10n.t("dnd.dropped", ["name": name, "target": targetName]))
      return true
    }

    if case .chip(let over) = target, over == index { return false }
    let next = LayoutEntries.place(plugins, index: index, position: position, insertIndex: insertAt, group: .some(group), positions: facts.positions)
    guard next != plugins else {
      Announce.post(L10n.t("dnd.droppedHome", ["name": facts.label(index)]))
      return true
    }
    apply(next)
    Announce.post(L10n.t("dnd.dropped", ["name": facts.label(index), "target": targetName]))
    return true
  }

  static func resolve(_ stored: String, _ plugins: [PluginEntry]) -> Int? {
    let parts = stored.split(separator: "\n", omittingEmptySubsequences: false)
    guard parts.count == 2, let occurrence = Int(parts[1]) else { return nil }
    return LayoutBoard.resolve(plugins, name: String(parts[0]), occurrence: occurrence)
  }

  // MARK: flex groups

  private func groupsPanel(_ config: QuartzConfig) -> some View {
    let groups = config.layout?["groups"]?.objectValue ?? JSONObject()
    let setGroups = { (next: JSONObject) in
      var layout = model.config?.layout ?? JSONObject()
      layout["groups"] = .object(next)
      model.config?.layout = layout
    }
    let update = { (name: String, key: String, value: JSONValue?) in
      var next = groups
      var group = groups[name]?.objectValue ?? JSONObject()
      group[key] = value
      next[name] = .object(group)
      setGroups(next)
    }
    return GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        Note(L10n.t("layoutEditor.groupsPanel.description"))
        if groups.isEmpty { Text(L10n.t("layoutEditor.groupsPanel.none")).font(.callout).foregroundStyle(.secondary) }
        ForEach(Array(groups.keys.enumerated()), id: \.element) { k, name in
          let group = groups[name]?.objectValue ?? JSONObject()
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Circle().fill(LayoutWords.groupColors[k % LayoutWords.groupColors.count]).frame(width: 8, height: 8).accessibilityHidden(true)
              Text(verbatim: name).fontWeight(.medium)
              Spacer()
              Button {
                var next = groups
                next[name] = nil
                setGroups(next)
                if let plugins = model.config?.plugins { model.config?.plugins = LayoutBoard.withoutGroup(plugins, named: name) }
              } label: { Label(L10n.t("common.deleteNamed", ["name": name]), systemImage: "trash") }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            FlowLayout(spacing: 12, minItem: 0, stretch: false) {
              Picker(L10n.t("layoutEditor.groupsPanel.direction"), selection: Binding(get: { group["direction"]?.stringValue ?? "row" },
                                                                                      set: { update(name, "direction", .string($0)) })) {
                Text(L10n.t("layoutEditor.groupsPanel.directionRow")).tag("row")
                Text(L10n.t("layoutEditor.groupsPanel.directionRowReverse")).tag("row-reverse")
                Text(L10n.t("layoutEditor.groupsPanel.directionColumn")).tag("column")
                Text(L10n.t("layoutEditor.groupsPanel.directionColumnReverse")).tag("column-reverse")
              }
              .fixedSize()
              // Quartz reads a missing key as "nowrap", so that writes none.
              Picker(L10n.t("layoutEditor.groupsPanel.wrap"), selection: Binding(get: { group["wrap"]?.stringValue ?? "nowrap" },
                                                                                 set: { update(name, "wrap", $0 == "nowrap" ? nil : .string($0)) })) {
                Text(L10n.t("layoutEditor.groupsPanel.wrapNone")).tag("nowrap")
                Text(L10n.t("layoutEditor.groupsPanel.wrapWrap")).tag("wrap")
                Text(L10n.t("layoutEditor.groupsPanel.wrapReverse")).tag("wrap-reverse")
              }
              .fixedSize()
            }
            // Labelled like the pickers above: outside a Form a TextField shows no title, and the two
            // fields read "0.75rem" and "10" with nothing saying what they are (measured 2026-11-10).
            FlowLayout(spacing: 12, minItem: 0, stretch: false) {
              LabeledContent(L10n.t("layoutEditor.groupsPanel.gap")) {
                TextField(L10n.t("layoutEditor.groupsPanel.gap"), text: Binding(get: { group["gap"]?.stringValue ?? "" }, set: { typed in
                  // Emptied, the key goes and Quartz takes its own gap; "" was written as the value
                  // (review 2026-11-13, nebenbei).
                  update(name, "gap", typed.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .string(typed))
                }),
                          prompt: Text(verbatim: "0.5rem"))
                  .labelsHidden()
                  .frame(width: 140)
              }
              .fixedSize()
              LabeledContent(L10n.t("layoutEditor.groupsPanel.priority")) {
                TextField(L10n.t("layoutEditor.groupsPanel.priority"), text: Binding(
                  get: { group["priority"]?.numberValue.map { JSJSON.compact(.number($0)) } ?? "" },
                  set: { raw in
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { update(name, "priority", nil) } else if let n = Double(trimmed), n.isFinite { update(name, "priority", .number(n)) }
                  }), prompt: Text(L10n.t("layoutEditor.groupsPanel.priorityPlaceholder")))
                  .labelsHidden()
                  .frame(width: 140)
              }
              .fixedSize()
            }
          }
          .padding(8)
          .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
        HStack {
          TextField(L10n.t("layoutEditor.groupsPanel.newGroupPlaceholder"), text: $newGroup).frame(maxWidth: 240)
          Button(L10n.t("layoutEditor.groupsPanel.add")) {
            let name = newGroup.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, groups[name] == nil else { return }
            var next = groups
            next[name] = .object(JSONObject([("direction", .string("row")), ("gap", .string("0.5rem"))]))
            setGroups(next)
            newGroup = ""
          }
          .disabled(newGroup.trimmingCharacters(in: .whitespaces).isEmpty || groups[newGroup.trimmingCharacters(in: .whitespaces)] != nil)
        }
        // A name that is taken did nothing, without a word (review 2026-11-13, nebenbei).
        if groups[newGroup.trimmingCharacters(in: .whitespaces)] != nil {
          FieldProblem(L10n.t("layoutEditor.groupsPanel.nameTaken", ["name": newGroup.trimmingCharacters(in: .whitespaces)]))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(4)
    } label: {
      Text(L10n.t("layoutEditor.groupsPanel.title")).font(.headline)
    }
  }
}

/// One area of the stage: its name, the position it shows, an action, and what it holds.
struct AreaBox<Action: View, Content: View>: View {
  let label: String
  var slotLabel: String?
  @ViewBuilder var action: () -> Action
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 4) {
        Text(verbatim: label).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary).lineLimit(1)
        if let slotLabel, slotLabel != label {
          Text(verbatim: slotLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 5).background(Capsule().fill(.quaternary))
        }
        Spacer(minLength: 0)
        action()
      }
      content()
    }
    .padding(6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 8).fill(.background))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }
}

extension AreaBox where Action == EmptyView {
  init(label: String, slotLabel: String? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.init(label: label, slotLabel: slotLabel, action: { EmptyView() }, content: content)
  }
}
