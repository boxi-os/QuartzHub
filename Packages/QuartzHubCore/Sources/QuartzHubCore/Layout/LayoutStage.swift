import Foundation

/// What the Layout page's stage and overview say about a component on a page type: which frame
/// draws it, which area holds it, and why it is not on the page. QuartzControl computed this inside
/// `GlobalBoard.tsx` and `LayoutOverview.tsx`; the overview's cells are measured with
/// `scripts/layout-board-golden.mjs` (`frameShape` loaded, `stateOf` copied there word for word),
/// the stage's reasons by hand in `LayoutBoardTests`.
public enum LayoutStage {
  /// The frame the stage draws, as far as the page knows it.
  public enum Frame: Equatable, Sendable {
    /// Quartz's default frame: three columns on desktop.
    case standard
    /// `full-width` or `minimal`: one column, only these positions.
    case builtin(name: String, slots: [String])
    /// An own frame of the project.
    case own(FrameView)
    /// A page type plugin's own frame (canvas-page brings "canvas"): no shape the page could draw.
    case plugin(name: String)
    /// A name no frame is registered under; Quartz renders the default frame.
    case unknown(name: String)
  }

  /// Which frame a name stands for. `known` is false until the frames and the plugins' frames are
  /// both read: until then every own frame would look unknown.
  public static func frame(named name: String, frames: [FrameView], pluginFrames: [String: String]) -> Frame {
    if name != "default", let own = frames.first(where: { $0.frameName == name }) { return .own(own) }
    if let slots = LayoutBoard.builtinFrameSlots[name] { return .builtin(name: name, slots: slots) }
    if name == "default" { return .standard }
    if pluginFrames.values.contains(name) { return .plugin(name: name) }
    return .unknown(name: name)
  }

  /// The areas of an own frame shown on this breakpoint, in the file's order.
  public static func shownAreas(_ frame: FrameView, _ bp: String) -> [FrameView.Area] {
    frame.areas.filter { frame.isShown($0, on: bp) }
  }

  /// `indicesForArea`: a group area holds its group; the plain area of a position holds what no
  /// group area of the frame claims, also groups the frame gave no area. Claimed by every area of
  /// the frame, placed here or not, as the frame's own `contentsFor()` reads them.
  public static func indices(for area: FrameView.Area, in frame: FrameView, positions: [String: [Int]],
                             plugins: [PluginEntry]) -> [Int] {
    guard let position = area.slot else { return [] }
    let all = positions[position] ?? []
    let group = { (i: Int) in LayoutEntries.layout(plugins[i])?["group"]?.stringValue }
    if let own = area.group { return all.filter { group($0) == own } }
    let claimed = Set(frame.areas.filter { $0.slot == position }.compactMap(\.group))
    return all.filter { group($0).map { !claimed.contains($0) } ?? true }
  }

  /// The positions the frame shows nothing of on this breakpoint: what sits there is built nowhere.
  /// Empty for the default frame, and for one whose shape is unknown.
  public static func missingPositions(_ frame: Frame, _ bp: String) -> [String] {
    let shown: Set<String>
    switch frame {
    case .own(let own): shown = Set(shownAreas(own, bp).compactMap(\.slot).filter { $0 != "pageBody" })
    case .builtin(_, let slots): shown = Set(slots)
    default: return []
    }
    return LayoutEntries.positions.filter { !shown.contains($0) }
  }

  /// `shownInView`: on a page with an own frame, `.desktop-only`/`.mobile-only` switch at the
  /// project's own mobile width, so the views and the switch agree.
  public static func shownInView(_ display: String?, _ bp: String) -> Bool {
    switch display {
    case "desktop-only": bp != "mobile"
    case "mobile-only": bp == "mobile"
    default: true
    }
  }

  public enum Hidden: Equatable, Sendable {
    /// The page type's `exclude` names it.
    case excluded
    /// The page type clears its position.
    case cleared
    /// Its `display` leaves this view out.
    case notInView
  }

  /// `hiddenReason`: why a component is not on the page the stage shows. The page type's answers
  /// come first, they hold in every view. `override` is nil for "all pages".
  public static func hidden(_ plugin: PluginEntry, override: JSONObject?, bp: String?) -> Hidden? {
    let layout = LayoutEntries.layout(plugin)
    if let override {
      if PageTypeOverride.isExcluded(override, plugin) { return .excluded }
      if let position = layout?["position"]?.stringValue, PageTypeOverride.isCleared(override, position) { return .cleared }
    }
    if let bp, !shownInView(layout?["display"]?.stringValue, bp) { return .notInView }
    return nil
  }

  /// `hiddenOnTypes`: on "all pages", the page types that exclude the component or clear its position.
  public static func hiddenOnTypes(_ config: QuartzConfig, _ plugin: PluginEntry, pageTypes: [String]) -> [String] {
    let position = LayoutEntries.layout(plugin)?["position"]?.stringValue
    return pageTypes.filter { type in
      let override = PageTypeOverride.of(config, type)
      return PageTypeOverride.isExcluded(override, plugin) || position.map { PageTypeOverride.isCleared(override, $0) } ?? false
    }
  }

  // MARK: the overview's cells

  /// Where a frame shows an area: on these breakpoints, or on all of them (a built-in frame).
  public enum Placed: Equatable, Sendable {
    case all
    case on([String])
  }

  /// `frameShape`: the areas a frame builds, positions with a plain area and `<position>#<group>`
  /// with one of its own, each with the breakpoints that place it. Nil for a page type plugin's
  /// own frame, which the page cannot know; a name that is no frame at all is the default frame.
  public struct Shape: Equatable, Sendable {
    public var plain: [String: Placed]
    public var groups: [String: Placed]
  }

  public static func shape(_ name: String, frames: [FrameView], pluginFrames: Set<String>) -> Shape? {
    if name != "default", let own = frames.first(where: { $0.frameName == name }) {
      var shape = Shape(plain: [:], groups: [:])
      for area in own.areas {
        guard let slot = area.slot, slot != "pageBody" else { continue }
        let placed = LayoutBoard.breakpoints.filter { own.isShown(area, on: $0) }
        let union = { (before: Placed?) -> Placed in
          let earlier: [String] = if case .on(let list)? = before { list } else { [] }
          return .on(LayoutBoard.breakpoints.filter { placed.contains($0) || earlier.contains($0) })
        }
        if let group = area.group {
          shape.groups["\(slot)#\(group)"] = union(shape.groups["\(slot)#\(group)"])
        } else {
          shape.plain[slot] = union(shape.plain[slot])
        }
      }
      return shape
    }
    let all = { (positions: [String]) in Shape(plain: Dictionary(uniqueKeysWithValues: positions.map { ($0, Placed.all) }), groups: [:]) }
    if let slots = LayoutBoard.builtinFrameSlots[name] { return all(slots) }
    if pluginFrames.contains(name) { return nil }
    return all(LayoutEntries.positions)
  }

  public enum Cell: Equatable, Sendable {
    case shown
    /// Only on these breakpoints (its area is placed on some, and its `display` agrees on these).
    case someWidths([String])
    case excluded
    case cleared
    /// The frame has no area for its position (or its group's).
    case noArea
    /// Its area is placed on no breakpoint.
    case hiddenArea
    /// Its area and its `display` share no breakpoint.
    case noWidth
    /// The frame comes from a page type plugin.
    case unknown
  }

  /// `stateOf` of `LayoutOverview.tsx`: what the user set comes before what follows from the
  /// frame - cleared, excluded, unknown, no area, hidden area, no width, some widths, shown.
  public static func cell(_ config: QuartzConfig, _ index: Int, pageType: String, shape: Shape?) -> Cell {
    let plugin = config.plugins[index]
    let layout = LayoutEntries.layout(plugin)
    let override = PageTypeOverride.of(config, pageType)
    let position = layout?["position"]?.stringValue ?? ""
    if PageTypeOverride.isCleared(override, position) { return .cleared }
    if PageTypeOverride.isExcluded(override, plugin) { return .excluded }
    guard let shape else { return .unknown }
    let group = layout?["group"]?.stringValue
    let room: Placed? = if let group, let own = shape.groups["\(position)#\(group)"] { own } else { shape.plain[position] }
    guard let room else { return .noArea }
    guard case .on(let placed) = room else { return .shown }
    if placed.isEmpty { return .hiddenArea }
    if placed.count < LayoutBoard.breakpoints.count {
      let on = placed.filter { shownInView(layout?["display"]?.stringValue, $0) }
      return on.isEmpty ? .noWidth : .someWidths(on)
    }
    return .shown
  }
}
