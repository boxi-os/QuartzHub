import Foundation

/// Rows of a frame's breakpoint as things of their own (docs/plan-frame-zeilen.md): inserting and
/// removing one moves the areas below it, stretches or shortens the areas across it, and takes the
/// row's size (`rowSizes`) and its lines' names (`rowLineNames`) along, which are kept by index.
/// On these, moving an area into a row of its own (reordering like a list) and swapping two areas.
/// The format stays QuartzControl 1.3's: only numbers and lists change.
extension FrameEditing {
  /// Rows (1-based) no shown area touches: they hold nothing and still cost a row gap.
  public static func emptyRows(_ view: FrameView, _ bp: String) -> [Int] {
    let layout = view.layout(bp)
    guard layout.rows >= 1 else { return [] }
    let shown = view.areas.compactMap { view.placement(bp, $0.id) }.filter(\.shown)
    return (1...layout.rows).filter { r in !shown.contains { r >= $0.row && r < $0.row + max($0.rowSpan, 1) } }
  }

  /// Shown areas whose rows all have the size 0: whatever they hold overlaps the next row (00_test,
  /// 2026-11-22: before-body in left's old row, the title under the right column on phones).
  public static func collapsedAreas(_ view: FrameView, _ bp: String) -> [String] {
    let sizes = view.layout(bp).rowSizes ?? []
    let zero = { (r: Int) in
      guard sizes.indices.contains(r - 1) else { return false }
      return JSText.test(JS.trim(sizes[r - 1]), #"^[+-]?0*\.?0+(?:[a-zA-Z%]+)?$"#)
    }
    return view.areas.filter { area in
      guard let p = view.placement(bp, area.id), p.shown else { return false }
      return (p.row..<(p.row + max(p.rowSpan, 1))).allSatisfy(zero)
    }.map(\.id)
  }

  /// Every placement of the breakpoint rewritten by `change(row, rowSpan)`; other keys stay.
  static func movingPlacements(_ layout: inout JSONObject, _ change: (Int, Int, Bool) -> (Int, Int)) {
    guard var placements = layout["placements"]?.objectValue else { return }
    for key in placements.keys {
      guard var object = placements[key]?.objectValue else { continue }
      let row = FrameView.int(object["row"]), span = max(FrameView.int(object["rowSpan"]), 1)
      let hidden = object["hidden"].map(JS.truthy) ?? false
      let (nextRow, nextSpan) = change(row, span, hidden)
      if nextRow != row { object["row"] = .number(Double(nextRow)) }
      if nextSpan != span { object["rowSpan"] = .number(Double(nextSpan)) }
      placements[key] = .object(object)
    }
    layout["placements"] = .object(placements)
  }

  /// A row before row `r` (1…rows + 1): the areas from `r` down move one row down, an area reaching
  /// across the line gets one row longer; the new row's size is a hole (`auto`), the names of the
  /// lines from `r` on move with their rows, and a name on the grid's last line stays at the end.
  public static func insertingRow(_ def: JSONValue, _ bp: String, before r: Int) -> JSONValue {
    let rows = FrameView(def).layout(bp).rows
    guard r >= 1, r <= rows + 1 else { return def }
    return withLayout(def, bp) { layout in
      movingPlacements(&layout) { row, span, _ in
        if row >= r { return (row + 1, span) }
        if row + span - 1 >= r { return (row, span + 1) }
        return (row, span)
      }
      if var sizes = layout["rowSizes"]?.arrayValue, sizes.count >= r {
        sizes.insert(.null, at: r - 1)
        layout["rowSizes"] = .array(sizes)
      }
      if let names = layout["rowLineNames"], !LayoutBoxes.spread(names).isEmpty {
        let old = LayoutBoxes.spread(names)
        var next = JSONObject()
        for key in old.keys {
          guard let line = Int(key) else { next[key] = old[key]; continue }
          next[String(line >= r || (r == rows + 1 && line == rows) ? line + 1 : line)] = old[key]
        }
        layout["rowLineNames"] = .object(next)
      }
      layout["rows"] = .number(Double(rows + 1))
    }
  }

  /// Row `r` taken out, refused (nil) while a shown area lies in it alone or it is the only row:
  /// the areas below move one row up, an area reaching across it gets one row shorter. Its size
  /// goes, and the line under it (above it for the last row, so the grid's last line keeps its name).
  /// A hidden placement only in this row keeps its place, within the grid.
  public static func removingRow(_ def: JSONValue, _ bp: String, _ r: Int) -> JSONValue? {
    let view = FrameView(def)
    let rows = view.layout(bp).rows
    guard rows > 1, r >= 1, r <= rows else { return nil }
    let alone = view.areas.contains { area in
      guard let p = view.placement(bp, area.id), p.shown else { return false }
      return p.row == r && max(p.rowSpan, 1) == 1
    }
    if alone { return nil }
    return withLayout(def, bp) { layout in
      movingPlacements(&layout) { row, span, _ in
        if row > r { return (row - 1, span) }
        if row + span - 1 >= r { return span > 1 ? (row, span - 1) : (min(row, rows - 1), 1) }
        return (row, span)
      }
      if var sizes = layout["rowSizes"]?.arrayValue, sizes.count >= r {
        sizes.remove(at: r - 1)
        layout["rowSizes"] = .array(sizes)
      }
      if let names = layout["rowLineNames"], !LayoutBoxes.spread(names).isEmpty {
        let old = LayoutBoxes.spread(names)
        let gone = r == rows ? r - 1 : r
        var next = JSONObject()
        for key in old.keys {
          guard let line = Int(key) else { next[key] = old[key]; continue }
          if line == gone { continue }
          next[String(line > gone ? line - 1 : line)] = old[key]
        }
        layout["rowLineNames"] = .object(next)
      }
      layout["rows"] = .number(Double(rows - 1))
    }
  }

  /// Every empty row taken out, from the bottom up.
  public static func removingEmptyRows(_ def: JSONValue, _ bp: String) -> JSONValue {
    var next = def
    for r in emptyRows(FrameView(def), bp).reversed() {
      if let removed = removingRow(next, bp, r) { next = removed }
    }
    return next
  }

  public struct RowMove: Equatable, Sendable {
    public var def: JSONValue
    /// Where the area landed.
    public var placement: FrameView.Placement
    /// Its height before, when it had more than one row.
    public var rowSpanBefore: Int?
  }

  /// The area in a new row before row `r` (1…rows + 1), as in a list: its columns stay where they
  /// are free (else the widest free run of the new row), its height is one row, and a row it leaves
  /// is taken out unless another area lies in it alone. Nil when the area is unknown or the new row has no free column.
  public static func movingToNewRow(_ def: JSONValue, _ bp: String, _ id: String, before r: Int) -> RowMove? {
    let view = FrameView(def)
    guard view.areas.contains(where: { $0.id == id }) else { return nil }
    let layout = view.layout(bp)
    guard r >= 1, r <= layout.rows + 1 else { return nil }
    let old = view.placement(bp, id)
    let oldRows: [Int] = old.flatMap { $0.shown ? Array($0.row..<($0.row + max($0.rowSpan, 1))) : nil } ?? []
    var next = insertingRow(unplacing(def, bp, id), bp, before: r)
    let inserted = FrameView(next)
    let cols = max(layout.cols, 1)
    let free = (1...cols).map { c in placementAt(inserted, bp, row: r, col: c) == nil }
    let wanted = old.map { (col: max($0.col, 1), span: max($0.colSpan, 1)) } ?? (col: 1, span: cols)
    let fits = wanted.col + wanted.span - 1 <= cols && (wanted.col..<(wanted.col + wanted.span)).allSatisfy { free[$0 - 1] }
    var col = wanted.col, span = min(wanted.span, cols)
    if !fits {
      // The widest run of free columns, the first of equals.
      var best = (col: 0, span: 0), start = 0
      for c in 1...(cols + 1) {
        if c <= cols && free[c - 1] { if start == 0 { start = c } } else if start > 0 {
          if c - start > best.span { best = (start, c - start) }
          start = 0
        }
      }
      guard best.span > 0 else { return nil }
      col = best.col
      span = old == nil ? best.span : min(wanted.span, best.span)
    }
    let placed = FrameView.Placement(row: r, col: col, rowSpan: 1, colSpan: span, hidden: false)
    next = replacingPlacement(next, bp, id, placementJSON(placed, over: nil, hidden: true))
    var landed = placed
    // The rows it left, in the numbering after the insertion, bottom up: gone unless another area
    // lies in one alone. An area only passing through (right beside rows 2 to 5) gets shorter, as a
    // list closes the gap; "empty" in `emptyRows` would have kept such a row.
    for row in oldRows.map({ $0 >= r ? $0 + 1 : $0 }).sorted(by: >) {
      guard let removed = removingRow(next, bp, row) else { continue }
      next = removed
      if row < landed.row { landed.row -= 1 }
    }
    let before = old.flatMap { $0.shown && $0.rowSpan > 1 ? $0.rowSpan : nil }
    return RowMove(def: next, placement: landed, rowSpanBefore: before)
  }

  /// Two shown areas trade places, each keeping its spans: refused when one would reach past the
  /// grid or onto a third area, or onto the other.
  public static func swapping(_ def: JSONValue, _ bp: String, _ a: String, _ b: String) -> Result<JSONValue, Refusal>? {
    let view = FrameView(def)
    guard a != b, let pa = view.placement(bp, a), pa.shown, let pb = view.placement(bp, b), pb.shown else { return nil }
    let layout = view.layout(bp)
    let na = FrameView.Placement(row: pb.row, col: pb.col, rowSpan: max(pa.rowSpan, 1), colSpan: max(pa.colSpan, 1), hidden: false)
    let nb = FrameView.Placement(row: pa.row, col: pa.col, rowSpan: max(pb.rowSpan, 1), colSpan: max(pb.colSpan, 1), hidden: false)
    guard fitsGrid(layout, na), fitsGrid(layout, nb) else { return .failure(.outside) }
    let crossing = na.row < nb.row + nb.rowSpan && nb.row < na.row + na.rowSpan && na.col < nb.col + nb.colSpan && nb.col < na.col + na.colSpan
    let others = { (p: FrameView.Placement) in
      (p.row..<(p.row + p.rowSpan)).contains { r in
        (p.col..<(p.col + p.colSpan)).contains { c in
          placementAt(view, bp, row: r, col: c).map { $0.id != a && $0.id != b } ?? false
        }
      }
    }
    if crossing || others(na) || others(nb) { return .failure(.overlap) }
    return .success(withPlacement(withPlacement(def, bp, a, na), bp, b, nb))
  }
}
