import Foundation

/// The frame editor's rules: the module-level functions of QuartzControl's
/// `routes/LayoutEditor/FrameBuilder.tsx` and `defaultFrame.ts`, measured with
/// `scripts/stage-geometry-golden.mjs`, and the edits its component made (span, visibility, resize,
/// copy to another breakpoint), checked by hand in `StageGeometryTests`.
///
/// It works on the frame definition as JSON, as the editor there did with spreads: what the file
/// holds beyond the editor's fields stays, and a changed key keeps its place.
public enum FrameEditing {
  public static let reservedNames = ["default", "full-width", "minimal"]
  public static let slots = ["header", "left", "right", "beforeBody", "pageBody", "afterBody", "footer"]
  public static let alignments = ["left", "center", "right"]

  // MARK: Quartz's own frame

  /// `QUARTZ_MEASURES`: Quartz's numbers from `variables.scss` and `base.scss`, for when the
  /// project's cannot be read.
  public static let quartzMeasures = ScssCheck.Measures(
    grids: ["desktop": .init(columns: ["320px", "auto", "320px"], rowGap: "5px", columnGap: "5px"),
            "tablet": .init(columns: ["320px", "auto"], rowGap: "5px", columnGap: "5px"),
            "mobile": .init(columns: ["auto"], rowGap: "5px", columnGap: "5px")],
    breakpoints: (mobile: 800, desktop: 1200), pageMaxWidth: "1500px")

  /// `columnsFit`: whether a breakpoint's measured columns fit Quartz's arrangement (3, 2, 1).
  public static func columnsFit(_ measures: ScssCheck.Measures, _ bp: String) -> Bool {
    measures.grids[bp]?.columns.count == quartzMeasures.grids[bp]?.columns.count
  }

  /// `quartzDefaultFrame`: Quartz's DefaultFrame as an own frame, what "Als eigenen Frame anpassen"
  /// copies. Sizes from the project where they fit Quartz's arrangement, the arrangement always
  /// Quartz's; beforeBody, the page and afterBody each get a row of the middle column.
  public static func quartzDefaultFrame(id: String, frameName: String, measures: ScssCheck.Measures = quartzMeasures) -> JSONValue {
    let names: [(String, String)] = [("header", "header"), ("left", "left"), ("right", "right"), ("beforeBody", "before-body"),
                                     ("pageBody", "page-body"), ("afterBody", "after-body"), ("footer", "footer")]
    let areas = names.map { slot, name in JSONValue.object(JSONObject([("id", .string("area-\(slot)")), ("name", .string(name)), ("slot", .string(slot))])) }
    func at(_ row: Int, _ col: Int, _ rowSpan: Int = 1) -> (Int, Int, Int) { (row, col, rowSpan) }
    func layout(_ bp: String, _ placements: [(String, (Int, Int, Int))]) -> JSONValue {
      let rows = placements.map { $0.1.0 + $0.1.2 - 1 }.max() ?? 0
      let grid = (columnsFit(measures, bp) ? measures : quartzMeasures).grids[bp]!
      let own = measures.grids[bp] ?? grid
      let columnSizes = grid.columns.map { $0 == "auto" ? "1fr" : $0 }
      return .object(JSONObject([
        ("rows", .number(Double(rows))), ("cols", .number(Double(columnSizes.count))),
        ("columnSizes", .array(columnSizes.map(JSONValue.string))),
        ("rowGap", .string(own.rowGap)), ("columnGap", .string(own.columnGap)),
        ("maxWidth", .string(measures.pageMaxWidth ?? quartzMeasures.pageMaxWidth!)), ("align", .string("center")),
        ("placements", .object(JSONObject(placements.map { slot, p in
          ("area-\(slot)", .object(JSONObject([("row", .number(Double(p.0))), ("col", .number(Double(p.1))),
                                              ("rowSpan", .number(Double(p.2))), ("colSpan", .number(1))])))
        }))),
      ]))
    }
    return .object(JSONObject([
      ("id", .string(id)), ("frameName", .string(frameName)), ("areas", .array(areas)),
      ("breakpoints", .object(JSONObject([
        ("desktop", layout("desktop", [("left", at(1, 1, 5)), ("header", at(1, 2)), ("beforeBody", at(2, 2)), ("pageBody", at(3, 2)),
                                       ("afterBody", at(4, 2)), ("footer", at(5, 2)), ("right", at(1, 3, 5))])),
        ("tablet", layout("tablet", [("left", at(1, 1, 6)), ("header", at(1, 2)), ("beforeBody", at(2, 2)), ("pageBody", at(3, 2)),
                                     ("afterBody", at(4, 2)), ("right", at(5, 2)), ("footer", at(6, 2))])),
        ("mobile", layout("mobile", [("left", at(1, 1)), ("header", at(2, 1)), ("beforeBody", at(3, 1)), ("pageBody", at(4, 1)),
                                     ("afterBody", at(5, 1)), ("right", at(6, 1)), ("footer", at(7, 1))])),
      ]))),
    ]))
  }

  // MARK: new frames and areas

  /// `slugify`: an area's name is its `grid-area` and a class, so it is kept to a-z, 0-9 and "-".
  public static func slugify(_ text: String) -> String {
    let lower = JS.trim(text).lowercased()
    var out = ""
    var dash = false
    for scalar in lower.unicodeScalars {
      if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
        if dash { out += "-" }
        dash = false
        out.unicodeScalars.append(scalar)
      } else {
        dash = true
      }
    }
    if dash && !out.isEmpty { out += "-" }
    while out.hasPrefix("-") { out.removeFirst() }
    while out.hasSuffix("-") { out.removeLast() }
    return out.isEmpty ? "frame" : out
  }

  static func slotToName(_ slot: String) -> String {
    var out = ""
    for c in slot {
      if c.isUppercase { out += "-" + c.lowercased() } else { out.append(c) }
    }
    return out.lowercased()
  }

  /// `nextAreaName`: `custom-<n>`, n from the number of areas on, the first free one.
  public static func nextAreaName(_ def: JSONValue) -> String {
    let names = Set(areas(def).compactMap { $0["name"]?.stringValue })
    var n = areas(def).count + 1
    while names.contains("custom-\(n)") { n += 1 }
    return "custom-\(n)"
  }

  static func defaultLayout(rows: Int, cols: Int) -> JSONValue {
    .object(JSONObject([("rows", .number(Double(rows))), ("cols", .number(Double(cols))), ("rowGap", .string("1rem")),
                        ("columnGap", .string("1rem")), ("placements", .object(JSONObject()))]))
  }

  /// `emptyDraft`: the seven slots as areas, a 2×2 grid on every breakpoint, nothing placed.
  public static func emptyDraft(id: String) -> JSONValue {
    let areas = slots.map { slot in JSONValue.object(JSONObject([("id", .string("area-\(slot)")), ("name", .string(slotToName(slot))), ("slot", .string(slot))])) }
    return .object(JSONObject([
      ("id", .string(id)), ("frameName", .string("")), ("areas", .array(areas)),
      ("breakpoints", .object(JSONObject(GridFrameCss.breakpoints.map { ($0, defaultLayout(rows: 2, cols: 2)) }))),
    ]))
  }

  /// `freeName`: the name, or with `-2`, `-3` … where it is taken.
  public static func freeName(_ base: String, frames: [FrameView]) -> String {
    let taken = Set(reservedNames + frames.map(\.frameName))
    guard taken.contains(base) else { return base }
    var n = 2
    while taken.contains("\(base)-\(n)") { n += 1 }
    return "\(base)-\(n)"
  }

  /// A copy of the frame under a new id and a free name (`duplicateFrame`).
  public static func duplicate(_ def: JSONValue, id: String, frames: [FrameView]) -> JSONValue {
    var object = def.objectValue ?? JSONObject()
    object["id"] = .string(id)
    let name = def["frameName"]?.stringValue ?? ""
    object["frameName"] = .string(freeName("\(name.isEmpty ? "frame" : name)-kopie", frames: frames))
    return .object(object)
  }

  // MARK: reading

  static func areas(_ def: JSONValue) -> [JSONValue] { def["areas"]?.arrayValue ?? [] }

  static func layoutObject(_ def: JSONValue, _ bp: String) -> JSONObject { def["breakpoints"]?[bp]?.objectValue ?? JSONObject() }

  /// `placementAt`: the shown area covering a cell.
  public static func placementAt(_ view: FrameView, _ bp: String, row: Int, col: Int) -> FrameView.Area? {
    view.areas.first { area in
      guard let p = view.placement(bp, area.id), p.shown else { return false }
      return row >= p.row && row < p.row + p.rowSpan && col >= p.col && col < p.col + p.colSpan
    }
  }

  /// `overlaps`: whether any cell of the rectangle is covered by a shown area other than `except`.
  public static func overlaps(_ view: FrameView, _ bp: String, row: Int, col: Int, rowSpan: Int, colSpan: Int, except: String? = nil) -> Bool {
    guard rowSpan > 0, colSpan > 0 else { return false }
    for r in row..<(row + rowSpan) {
      for c in col..<(col + colSpan) {
        if let hit = placementAt(view, bp, row: r, col: c), hit.id != except { return true }
      }
    }
    return false
  }

  /// `fitsGrid`.
  public static func fitsGrid(_ layout: FrameView.Layout, _ p: FrameView.Placement) -> Bool {
    p.row >= 1 && p.col >= 1 && p.row + p.rowSpan - 1 <= layout.rows && p.col + p.colSpan - 1 <= layout.cols
  }

  public struct SlotWarnings: Equatable, Sendable {
    /// Slots no shown area holds: their components render nowhere at this width.
    public var unassigned: [String]
    /// Slots whose shown areas all have a group: the ungrouped components have nowhere to go.
    public var homeless: [String]
    /// Slots with two shown plain areas: their list renders twice.
    public var doubled: [String]
    /// Group areas shown on another breakpoint but not this one: their group is shown by nothing here.
    public var hiddenGroups: [String]
  }

  /// `slotWarnings`.
  public static func slotWarnings(_ view: FrameView, _ bp: String) -> SlotWarnings {
    let shown = view.areas.filter { view.isShown($0, on: bp) }
    let used = Set(shown.compactMap(\.slot))
    return SlotWarnings(
      unassigned: slots.filter { $0 != "pageBody" && !used.contains($0) },
      homeless: slots.filter { s in s != "pageBody" && shown.contains { $0.slot == s && $0.group != nil } && !shown.contains { $0.slot == s && $0.group == nil } },
      doubled: slots.filter { s in shown.filter { $0.slot == s && $0.group == nil }.count > 1 },
      hiddenGroups: view.areas.filter { a in
        a.group != nil && a.slot != nil && a.slot != "pageBody" && !view.isShown(a, on: bp)
          && GridFrameCss.breakpoints.contains { $0 != bp && view.isShown(a, on: $0) }
      }.map(\.id))
  }

  /// `placementWarnings`: two shown areas on one cell (from the file; the editor makes none), and
  /// a shown area reaching past the grid (from shrinking it, which leaves placements alone).
  public static func placementWarnings(_ view: FrameView, _ bp: String) -> (overlapping: [(String, String)], outside: [String]) {
    let layout = view.layout(bp)
    let shown = view.areas.compactMap { area in view.placement(bp, area.id).flatMap { $0.shown ? (area, $0) : nil } }
    var overlapping: [(String, String)] = []
    for i in shown.indices {
      for j in shown.indices where j > i {
        let (a, b) = (shown[i].1, shown[j].1)
        if a.row < b.row + b.rowSpan && b.row < a.row + a.rowSpan && a.col < b.col + b.colSpan && b.col < a.col + a.colSpan {
          overlapping.append((shown[i].0.id, shown[j].0.id))
        }
      }
    }
    return (overlapping, shown.filter { !fitsGrid(layout, $0.1) }.map(\.0.id))
  }

  /// `duplicateAreaNames`: two areas with one name put it on two rectangles, and CSS drops the
  /// whole `grid-template-areas`. Blocks the save.
  public static func duplicateAreaNames(_ view: FrameView) -> [String] {
    var seen: Set<String> = [], twice: [String] = []
    for area in view.areas {
      if seen.contains(area.name), !twice.contains(area.name) { twice.append(area.name) }
      seen.insert(area.name)
    }
    return twice
  }

  /// `duplicateAreaGroups`: two areas holding one group on one slot show its components twice.
  public static func duplicateAreaGroups(_ view: FrameView) -> [String] {
    var seen: Set<String> = [], twice: [String] = []
    for area in view.areas {
      guard let slot = area.slot, let group = area.group else { continue }
      let key = "\(slot)\u{0}\(group)"
      if seen.contains(key), !twice.contains(group) { twice.append(group) }
      seen.insert(key)
    }
    return twice
  }

  /// `nameCollision`: a reserved name, or one another frame has.
  public static func nameCollision(_ view: FrameView, frames: [FrameView]) -> Bool {
    reservedNames.contains(view.frameName) || frames.contains { $0.id != view.id && $0.frameName == view.frameName }
  }

  /// Every warning of a breakpoint as a key, to say which other breakpoints have one of their own.
  public static func warningKeys(_ view: FrameView, _ bp: String) -> [String] {
    let w = slotWarnings(view, bp)
    let p = placementWarnings(view, bp)
    return p.overlapping.map { "overlap:\($0.0):\($0.1)" } + p.outside.map { "outside:\($0)" }
      + w.unassigned.map { "unassigned:\($0)" } + w.homeless.map { "homeless:\($0)" } + w.doubled.map { "doubled:\($0)" }
      + w.hiddenGroups.map { "hiddenGroup:\($0)" }
  }

  // MARK: changing

  /// `{ ...def, breakpoints: { ...def.breakpoints, [bp]: change({ ...layout }) } }`.
  static func withLayout(_ def: JSONValue, _ bp: String, _ change: (inout JSONObject) -> Void) -> JSONValue {
    var object = def.objectValue ?? JSONObject()
    var breakpoints = object["breakpoints"]?.objectValue ?? JSONObject()
    var layout = breakpoints[bp]?.objectValue ?? JSONObject()
    change(&layout)
    breakpoints[bp] = .object(layout)
    object["breakpoints"] = .object(breakpoints)
    return .object(object)
  }

  static func withArea(_ def: JSONValue, _ id: String, _ change: (inout JSONObject) -> Void) -> JSONValue {
    var object = def.objectValue ?? JSONObject()
    object["areas"] = .array(areas(def).map { area in
      guard area["id"]?.stringValue == id, var own = area.objectValue else { return area }
      change(&own)
      return .object(own)
    })
    return .object(object)
  }

  /// `{ ...existing, row, col, rowSpan, colSpan }`, and `hidden` only where the edit is about it.
  static func placementJSON(_ p: FrameView.Placement, over existing: JSONValue?, hidden: Bool) -> JSONValue {
    var object = existing?.objectValue ?? JSONObject()
    object["row"] = .number(Double(p.row))
    object["col"] = .number(Double(p.col))
    object["rowSpan"] = .number(Double(p.rowSpan))
    object["colSpan"] = .number(Double(p.colSpan))
    if hidden { object["hidden"] = .bool(p.hidden) }
    return .object(object)
  }

  /// `withPlacement`: a placement written over the area's old one (its other keys stay);
  /// `hidden` writes the visibility too, as the visibility switch does.
  public static func withPlacement(_ def: JSONValue, _ bp: String, _ areaId: String, _ p: FrameView.Placement, hidden: Bool = false) -> JSONValue {
    replacingPlacement(def, bp, areaId, placementJSON(p, over: def["breakpoints"]?[bp]?["placements"]?[areaId], hidden: hidden))
  }

  /// QuartzControl's `withPlacement`: the area's placement on this breakpoint is `placement`.
  public static func replacingPlacement(_ def: JSONValue, _ bp: String, _ areaId: String, _ placement: JSONValue) -> JSONValue {
    withLayout(def, bp) { layout in
      var placements = layout["placements"]?.objectValue ?? JSONObject()
      placements[areaId] = placement
      layout["placements"] = .object(placements)
    }
  }

  /// One of the breakpoint's own settings (`updateLayout`); nil removes the key.
  public static func withSetting(_ def: JSONValue, _ bp: String, _ key: String, _ value: JSONValue?) -> JSONValue {
    withLayout(def, bp) { $0[key] = value }
  }

  /// `setColumnSize`/`setRowSize`: a list with holes where nothing was typed yet (JSON writes null).
  public static func withTrackSize(_ def: JSONValue, _ bp: String, _ key: String, _ index: Int, _ value: String) -> JSONValue {
    withLayout(def, bp) { layout in
      var sizes = layout[key]?.arrayValue ?? []
      while sizes.count <= index { sizes.append(.null) }
      sizes[index] = .string(value)
      layout[key] = .array(sizes)
    }
  }

  /// `setColumnLineName`/`setRowLineName`: one name per line, an empty one removes it.
  public static func withLineName(_ def: JSONValue, _ bp: String, _ key: String, _ index: Int, _ value: String) -> JSONValue {
    withLayout(def, bp) { layout in
      var names = LayoutBoxes.spread(layout[key])
      let trimmed = JS.trim(value)
      names[String(index)] = trimmed.isEmpty ? nil : .array([.string(trimmed)])
      layout[key] = .object(names)
    }
  }

  /// `copyLayoutTo`: this breakpoint's whole layout replaces the other one's.
  public static func copyLayout(_ def: JSONValue, from bp: String, to target: String) -> JSONValue {
    var object = def.objectValue ?? JSONObject()
    var breakpoints = object["breakpoints"]?.objectValue ?? JSONObject()
    breakpoints[target] = breakpoints[bp] ?? .object(JSONObject())
    object["breakpoints"] = .object(breakpoints)
    return .object(object)
  }

  /// `addNewArea`: an area with a name and nothing else, in the tray.
  public static func addingArea(_ def: JSONValue, id: String) -> JSONValue {
    var object = def.objectValue ?? JSONObject()
    object["areas"] = .array(areas(def) + [.object(JSONObject([("id", .string(id)), ("name", .string(nextAreaName(def)))]))])
    return .object(object)
  }

  /// `updateAreaName`: what is typed, as a name CSS takes. Renaming does not rename the group.
  public static func withAreaName(_ def: JSONValue, _ id: String, _ raw: String) -> JSONValue {
    withArea(def, id) { $0["name"] = .string(slugify(raw)) }
  }

  /// `updateAreaSlot`: a group means nothing without a slot or on the page body.
  public static func withAreaSlot(_ def: JSONValue, _ id: String, _ slot: String?) -> JSONValue {
    let keepsGroup = slot.map { $0 != "pageBody" } ?? false
    return withArea(def, id) { area in
      area["slot"] = slot.map(JSONValue.string)
      if !keepsGroup { area["group"] = nil }
    }
  }

  /// `updateAreaGroup`: an own group is named after the area.
  public static func withAreaGroup(_ def: JSONValue, _ id: String, own: Bool) -> JSONValue {
    withArea(def, id) { area in area["group"] = own ? area["name"] : nil }
  }

  public enum Refusal: Error, Equatable, Sendable {
    /// Another shown area is in the way.
    case overlap
    /// The area reaches past the grid.
    case outside
  }

  /// `updateAreaSpan`: clamped to the grid; refused when it would cover another area.
  public static func withSpan(_ def: JSONValue, _ bp: String, _ id: String, rowSpan: Int? = nil, colSpan: Int? = nil) -> Result<JSONValue, Refusal> {
    let view = FrameView(def)
    let layout = view.layout(bp)
    guard let existing = view.placement(bp, id) else { return .success(def) }
    let rows = rowSpan.map { min(max(1, $0), layout.rows - existing.row + 1) } ?? existing.rowSpan
    let cols = colSpan.map { min(max(1, $0), layout.cols - existing.col + 1) } ?? existing.colSpan
    if overlaps(view, bp, row: existing.row, col: existing.col, rowSpan: rows, colSpan: cols, except: id) { return .failure(.overlap) }
    var p = existing
    p.rowSpan = rows
    p.colSpan = cols
    return .success(withPlacement(def, bp, id, p))
  }

  /// `updateAreaHidden`: showing it again is refused where it no longer fits or is covered.
  public static func withHidden(_ def: JSONValue, _ bp: String, _ id: String, _ hidden: Bool) -> Result<JSONValue, Refusal> {
    let view = FrameView(def)
    guard var existing = view.placement(bp, id) else { return .success(def) }
    if !hidden && !fitsGrid(view.layout(bp), existing) { return .failure(.outside) }
    if !hidden && overlaps(view, bp, row: existing.row, col: existing.col, rowSpan: existing.rowSpan, colSpan: existing.colSpan, except: id) {
      return .failure(.overlap)
    }
    existing.hidden = hidden
    return .success(withPlacement(def, bp, id, existing, hidden: true))
  }

  /// `landing`: where a dropped area ends up, its spans cut at the grid's edge, and whether it may.
  public static func landing(_ def: JSONValue, _ bp: String, _ id: String, row: Int, col: Int) -> (rowSpan: Int, colSpan: Int, refused: Bool)? {
    let view = FrameView(def)
    guard view.areas.contains(where: { $0.id == id }) else { return nil }
    let layout = view.layout(bp)
    let existing = view.placement(bp, id)
    let rowSpan = min(existing?.rowSpan ?? 1, layout.rows - row + 1)
    let colSpan = min(existing?.colSpan ?? 1, layout.cols - col + 1)
    return (rowSpan, colSpan, overlaps(view, bp, row: row, col: col, rowSpan: rowSpan, colSpan: colSpan, except: id))
  }

  /// `handleDrop`: the area on that cell, shown.
  public static func dropping(_ def: JSONValue, _ bp: String, _ id: String, row: Int, col: Int) -> Result<JSONValue, Refusal>? {
    guard let target = landing(def, bp, id, row: row, col: col) else { return nil }
    if target.refused { return .failure(.overlap) }
    let p = FrameView.Placement(row: row, col: col, rowSpan: target.rowSpan, colSpan: target.colSpan, hidden: false)
    return .success(replacingPlacement(def, bp, id, .object(JSONObject([
      ("row", .number(Double(p.row))), ("col", .number(Double(p.col))), ("rowSpan", .number(Double(p.rowSpan))),
      ("colSpan", .number(Double(p.colSpan))), ("hidden", .bool(false)),
    ]))))
  }

  /// `unplaceAreaById`: back into the tray on this breakpoint.
  public static func unplacing(_ def: JSONValue, _ bp: String, _ id: String) -> JSONValue {
    guard def["breakpoints"]?[bp]?["placements"]?[id] != nil else { return def }
    return withLayout(def, bp) { layout in
      var placements = layout["placements"]?.objectValue ?? JSONObject()
      placements[id] = nil
      layout["placements"] = .object(placements)
    }
  }

  /// `deleteAreaById`: the area and its placement on every breakpoint.
  public static func deletingArea(_ def: JSONValue, _ id: String) -> JSONValue {
    var object = def.objectValue ?? JSONObject()
    var breakpoints = object["breakpoints"]?.objectValue ?? JSONObject()
    for bp in GridFrameCss.breakpoints {
      var layout = breakpoints[bp]?.objectValue ?? JSONObject()
      var placements = layout["placements"]?.objectValue ?? JSONObject()
      placements[id] = nil
      layout["placements"] = .object(placements)
      breakpoints[bp] = .object(layout)
    }
    object["areas"] = .array(areas(def).filter { $0["id"]?.stringValue != id })
    object["breakpoints"] = .object(breakpoints)
    return .object(object)
  }

  public struct Sides: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let top = Sides(rawValue: 1)
    public static let bottom = Sides(rawValue: 2)
    public static let left = Sides(rawValue: 4)
    public static let right = Sides(rawValue: 8)
  }

  /// `moveResize`, without the geometry: the view says which grid line each dragged side is
  /// nearest to (`toCol`, `toRow`, 1-based track numbers), and a side grows only up to the last
  /// free line before another area, because an overlap makes `grid-template-areas` invalid.
  public static func resized(_ view: FrameView, _ bp: String, _ id: String, from start: FrameView.Placement, sides: Sides,
                             toCol: Int, toRow: Int) -> FrameView.Placement {
    let blocked = { (r0: Int, r1: Int, c0: Int, c1: Int) in
      overlaps(view, bp, row: r0, col: c0, rowSpan: r1 - r0 + 1, colSpan: c1 - c0 + 1, except: id)
    }
    let layout = view.layout(bp)
    var r0 = start.row, r1 = start.row + start.rowSpan - 1
    var c0 = start.col, c1 = start.col + start.colSpan - 1
    if sides.contains(.right) {
      let target = min(max(toCol, c0), layout.cols)
      var end = min(target, c1)
      var c = c1 + 1
      while c <= target && !blocked(r0, r1, c, c) { end = c; c += 1 }
      c1 = end
    }
    if sides.contains(.left) {
      let target = max(min(toCol, c1), 1)
      var begin = max(target, c0)
      var c = c0 - 1
      while c >= target && !blocked(r0, r1, c, c) { begin = c; c -= 1 }
      c0 = begin
    }
    if sides.contains(.bottom) {
      let target = min(max(toRow, r0), layout.rows)
      var end = min(target, r1)
      var r = r1 + 1
      while r <= target && !blocked(r, r, c0, c1) { end = r; r += 1 }
      r1 = end
    }
    if sides.contains(.top) {
      let target = max(min(toRow, r1), 1)
      var begin = max(target, r0)
      var r = r0 - 1
      while r >= target && !blocked(r, r, c0, c1) { begin = r; r -= 1 }
      r0 = begin
    }
    return FrameView.Placement(row: r0, col: c0, rowSpan: r1 - r0 + 1, colSpan: c1 - c0 + 1, hidden: start.hidden)
  }

  /// What a frame's own CSS box draws: a cap, or a padding.
  public static func hasBox(_ layout: FrameView.Layout) -> Bool {
    let set = { (v: String?) in !(v.map(JS.trim) ?? "").isEmpty }
    let pad = { (v: String?) in set(v) && JS.trim(v!) != "0" }
    return set(layout.maxWidth) || pad(layout.paddingBlock) || pad(layout.paddingInline)
  }
}
