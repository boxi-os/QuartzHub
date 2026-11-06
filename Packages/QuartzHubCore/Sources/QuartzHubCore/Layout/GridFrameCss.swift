import Foundation

/// The CSS of an authored frame, and the group orderings baked into its module: a port of
/// `shared/gridFrameCss.ts` (QuartzControl's layout-frames.md and styles-and-fonts.md hold the
/// measurements behind every rule written here; the comments below keep the short reason).
///
/// It works on the frame definition as JSON, not on a model: QuartzControl wrote `frame.json` back
/// whole and put `JSON.stringify(def.areas)` into the module, so key order and unknown keys are
/// part of the output. And it reads that JSON with JavaScript's coercions, because a frame.json
/// that never went through `FrameDefinitionCheck` (one written by hand, or by an older version)
/// still goes into the build: a missing gap reads "undefined", a missing name "" in
/// `grid-template-areas` and "undefined" in a class. Where JavaScript threw, this throws a
/// `JS.TypeError` with V8's sentence for the shapes a frame.json can plausibly have; for stranger
/// ones the wording may differ (docs/decisions/phase-3-dienste.md, "Frames").
public enum GridFrameCss {
  /// Desktop is the unconditional base; tablet and mobile narrow it with max-width queries, in this
  /// order, so the narrower block wins below its own width.
  public static let breakpoints = ["desktop", "tablet", "mobile"]

  public static func isDefault(_ widths: (tablet: Double, mobile: Double)) -> Bool {
    widths.tablet == FrameBreakpointWidths.defaults.tablet && widths.mobile == FrameBreakpointWidths.defaults.mobile
  }

  // MARK: tracks and areas

  /// `obj?.[key]` for a value JavaScript indexes: an array by index, an object by key, a string by
  /// character; anything else (and null/undefined) has no such property here.
  static func member(_ value: JSONValue?, _ key: String) -> JSONValue? {
    switch value {
    case .array(let items):
      guard let index = Int(key), index >= 0, index < items.count, String(index) == key else { return nil }
      return items[index]
    case .object(let object): return object[key]
    case .string(let text):
      let units = Array(text.utf16)
      guard let index = Int(key), index >= 0, index < units.count, String(index) == key else { return nil }
      return .string(String(decoding: [units[index]], as: UTF16.self))
    default: return nil
    }
  }

  /// `value?.trim()`: nil for null and undefined, a TypeError for anything that is not a string.
  static func trimmed(_ value: JSONValue?, _ expression: String) throws -> String? {
    switch value {
    case nil, .null?: return nil
    case .string(let text)?: return JS.trim(text)
    default: throw JS.TypeError("\(expression) is not a function")
    }
  }

  static func trackSize(_ sizes: JSONValue?, _ index: Int, _ fallback: String) throws -> String {
    let value = try trimmed(member(sizes, String(index)), "sizes?.[index]?.trim")
    guard let value, !value.isEmpty else { return fallback }
    return value
  }

  static func lineNamePrefix(_ names: JSONValue?, _ index: Int) throws -> String {
    guard let list = member(names, String(index)), JS.truthy(list) else { return "" }
    switch list {
    case .array(let items): return items.isEmpty ? "" : "[\(JS.join(items, " "))] "
    case .string(let text): if text.utf16.isEmpty { return "" }
    default: return ""
    }
    throw JS.TypeError("list.join is not a function")
  }

  /// A `grid-template-columns`/`-rows` value with `[line-name]` prefixes; `count + 1` line positions
  /// around `count` tracks.
  static func trackList(_ sizes: JSONValue?, count: JSONValue?, fallback: String, lineNames: JSONValue?) throws -> String {
    var parts: [String] = []
    let limit = JS.toNumber(count)
    var index = 0
    while Double(index) < limit {
      parts.append(try lineNamePrefix(lineNames, index) + trackSize(sizes, index, fallback))
      index += 1
    }
    parts.append(try lineNamePrefix(lineNames, index))
    return JS.trim(parts.joined(separator: " "))
  }

  /// `Array.from({ length })`: ToLength of the number.
  static func arrayLength(_ value: JSONValue?) -> Int {
    let number = JS.toNumber(value)
    guard number.isFinite, number > 0 else { return 0 }
    return Int(min(number.rounded(.down), 10_000))
  }

  static func placements(_ layout: JSONValue, _ area: JSONValue) throws -> JSONValue? {
    let key = JS.string(try field(area, "id"))
    guard let placements = layout["placements"], placements != .null else {
      throw JS.readError(layout["placements"], key)
    }
    return member(placements, key)
  }

  /// `area.id` on an element of `areas`: a TypeError on null, nothing on a primitive.
  static func field(_ value: JSONValue, _ key: String) throws -> JSONValue? {
    if value == .null { throw JS.readError(.null, key) }
    return value[key]
  }

  static func isVisible(_ placement: JSONValue?) -> Bool {
    guard let placement, JS.truthy(placement) else { return false }
    return !JS.truthy(placement["hidden"] ?? .null)
  }

  static func number(_ value: JSONValue?) -> Double {
    value.map { JS.toNumber($0) } ?? .nan
  }

  /// One row of `grid-template-areas` per grid row; a cell no visible area covers is ".".
  static func templateAreas(_ layout: JSONValue, _ areas: [JSONValue]) throws -> String {
    let rows = arrayLength(layout["rows"]), cols = arrayLength(layout["cols"])
    let rowLimit = JS.toNumber(layout["rows"]), colLimit = JS.toNumber(layout["cols"])
    var grid: [[JSONValue?]] = Array(repeating: Array(repeating: .string("."), count: cols), count: rows)
    for area in areas {
      let placement = try placements(layout, area)
      guard isVisible(placement), let placement else { continue }
      let row = number(placement["row"]), col = number(placement["col"])
      let rowEnd = row + number(placement["rowSpan"]), colEnd = col + number(placement["colSpan"])
      // The same cells JavaScript's loops visit, without visiting the ones that cannot land: a
      // span of a million rows would otherwise hang the build door the way it hung QuartzControl.
      var r = row < 1 ? row + (1 - row).rounded(.up) : row
      while r < rowEnd && r <= rowLimit {
        var c = col < 1 ? col + (1 - col).rounded(.up) : col
        while c < colEnd && c <= colLimit {
          if r >= 1 && r <= rowLimit && c >= 1 && c <= colLimit {
            // `grid[r - 1][c - 1] = area.name`: a fractional row reads a property the outer array
            // does not have and throws; a fractional column sets one the join never sees.
            guard r == r.rounded() else { throw JS.TypeError("Cannot set properties of undefined (setting '\(JSJSON.numberToString(c - 1))')") }
            if c == c.rounded() { grid[Int(r) - 1][Int(c) - 1] = area["name"] }
          }
          c += 1
        }
        r += 1
      }
    }
    return grid.map { "\"\(JS.join($0, " "))\"" }.joined(separator: "\n      ")
  }

  // MARK: one breakpoint

  struct Box: Equatable {
    var width = "100%"
    var maxWidth: String
    var marginInline: String
    var paddingBlock: String
    var paddingInline: String
  }

  /// Auto margins for `align` (a frame is a grid item, and auto margins beat its stretch), and
  /// `width: 100%`, without which an auto margin shrinks the frame to its max-content width.
  static func box(_ layout: JSONValue) throws -> Box {
    let maxWidth = try trimmed(layout["maxWidth"], "layout.maxWidth?.trim")
    let align = layout["align"].flatMap { $0 == .null ? nil : $0 } ?? .string("left")
    let margin = align == .string("center") ? "auto" : align == .string("right") ? "auto 0" : "0"
    let paddingBlock = try trimmed(layout["paddingBlock"], "layout.paddingBlock?.trim")
    let paddingInline = try trimmed(layout["paddingInline"], "layout.paddingInline?.trim")
    return Box(maxWidth: maxWidth.flatMap { $0.isEmpty ? nil : $0 } ?? "none", marginInline: margin,
               paddingBlock: paddingBlock.flatMap { $0.isEmpty ? nil : $0 } ?? "0",
               paddingInline: paddingInline.flatMap { $0.isEmpty ? nil : $0 } ?? "0")
  }

  static func areaList(_ areas: JSONValue?) throws -> [JSONValue] {
    switch areas {
    case .array(let items)?: return items
    case .string(let text)?: return text.map { .string(String($0)) }
    case nil: throw JS.TypeError("areas is not iterable")
    case .null?: throw JS.TypeError("areas is not iterable")
    default: throw JS.TypeError("areas is not iterable")
    }
  }

  /// One breakpoint's rules for `selector`: the grid itself, a `grid-area` per visible area and a
  /// `display: none` for every other one (an area left out of `grid-template-areas` would otherwise
  /// be auto-placed). Every value is written out, also when unset: the narrower breakpoints are
  /// overrides of the same selector, and a desktop-only value would still apply on mobile.
  static func breakpointBlock(_ selector: String, _ layout: JSONValue?, _ areasValue: JSONValue?) throws -> String {
    guard let layout, layout != .null else { throw JS.readError(layout, "columnSizes") }
    let columns = try trackList(layout["columnSizes"], count: layout["cols"], fallback: "1fr", lineNames: layout["columnLineNames"])
    let rows = try trackList(layout["rowSizes"], count: layout["rows"], fallback: "auto", lineNames: layout["rowLineNames"])
    let areas = try areaList(areasValue)
    let template = try templateAreas(layout, areas)
    let box = try box(layout)
    var rules = [
      "\(selector) {",
      "  display: grid;",
      "  grid-template-columns: \(columns);",
      "  grid-template-rows: \(rows);",
      "  row-gap: \(JS.string(layout["rowGap"]));",
      "  column-gap: \(JS.string(layout["columnGap"]));",
      // border-box: the editor says "maximum width", and Quartz sets no box-sizing here.
      "  box-sizing: border-box;",
      "  width: \(box.width);",
      "  max-width: \(box.maxWidth);",
      "  margin-inline: \(box.marginInline);",
      "  padding-block: \(box.paddingBlock);",
      "  padding-inline: \(box.paddingInline);",
      "  grid-template-areas:",
      "      \(template);",
      "}"
    ]
    for area in areas {
      let name = JS.string(try field(area, "name"))
      rules.append(isVisible(try placements(layout, area))
        ? ".qgframe-area-\(name) { grid-area: \(name); }"
        : ".qgframe-area-\(name) { display: none; }")
    }
    return rules.joined(separator: "\n")
  }

  // MARK: the frame around the grid

  static func escapeAttribute(_ value: JSONValue?) throws -> String {
    switch value {
    case .string(let text)?: return text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    case nil, .null?: throw JS.readError(value, "replace")
    default: throw JS.TypeError("value.replace is not a function")
    }
  }

  /// Quartz's `.page > #quartz-body` grid would put the frame into its first, sidebar-wide cell,
  /// and `.page` caps every page at 1500px; both are lifted for this frame only. `min-width: 0`
  /// lets an `fr` track keep its proportion on a narrow screen, and the pageBody area's `center`
  /// class loses the auto margin it brings.
  static func outerGridOverride(_ page: String) -> String {
    let selector = "\(page) > #quartz-body"
    return [
      "\(page) {", "  max-width: none;", "}",
      "\(selector) {", "  grid-template-columns: auto;", "  grid-template-rows: auto;", "  grid-template-areas: \"qgframe-root\";", "}",
      "\(selector) > .qgframe-grid {", "  grid-area: qgframe-root;", "}",
      "\(selector) .qgframe-area {", "  min-width: 0;", "  min-height: 0;", "}",
      "\(selector) .qgframe-area.center {", "  width: 100%;", "  max-width: none;", "  margin-inline: 0;", "}"
    ].joined(separator: "\n")
  }

  /// Quartz core's rules that switch on its own breakpoints, restated for the project's widths
  /// (only when they differ). The list is the whole surface outside the grid an authored frame
  /// replaces: `#quartz-body`'s padding and `.desktop-only`/`.mobile-only`, both halves each.
  static func quartzBreakpointCompat(_ page: String, _ widths: (tablet: Double, mobile: Double)) -> String {
    let tablet = JSJSON.numberToString(widths.tablet), mobile = JSJSON.numberToString(widths.mobile)
    return [
      "\(page) > #quartz-body {", "  padding: 0;", "}",
      "@media (max-width: \(tablet)px) {", "\(page) > #quartz-body {", "  padding: 0 1rem;", "}", "}",
      "\(page) .desktop-only {", "  display: contents;", "}",
      "\(page) .desktop-only.flex-component {", "  display: flex;", "}",
      "\(page) .mobile-only, \(page) .mobile-only.flex-component {", "  display: none;", "}",
      "@media (max-width: \(mobile)px) {",
      "\(page) .desktop-only, \(page) .desktop-only.flex-component {", "  display: none;", "}",
      "\(page) .mobile-only {", "  display: contents;", "}",
      "\(page) .mobile-only.flex-component {", "  display: flex;", "}",
      "}"
    ].joined(separator: "\n")
  }

  /// The same for the community plugins, where the breakpoint is felt: explorer's drawer, search
  /// and graph, copied out of explorer 0.1.0, search 0.1.0 and graph 0.1.0 (`dist/index.js`, read
  /// 2026-09-09 by QuartzControl). A copy of a foreign stylesheet: when a plugin changes its
  /// drawer, this keeps stating the old one. What is deliberately left out is listed in
  /// gridFrameCss.ts above `buildPluginBreakpointCompat`.
  static func pluginBreakpointCompat(_ page: String, _ widths: (tablet: Double, mobile: Double)) -> String {
    let tablet = JSJSON.numberToString(widths.tablet), mobile = JSJSON.numberToString(widths.mobile)
    let searchSpace = "\(page) .search > .search-container > .search-space"
    return [
      "\(page) .explorer {", "  order: 0;", "  height: auto;", "  overflow-x: visible;", "  overflow-y: hidden;",
      "  flex: 0 1 auto;", "  align-self: auto;", "  margin-block: 0;", "}",
      "\(page) .explorer.collapsed {", "  flex: 0 1 1.2rem;", "}",
      "\(page) .explorer .explorer-content {", "  box-sizing: content-box;", "  position: static;", "  z-index: auto;",
      "  width: auto;", "  max-width: none;", "  height: auto;", "  max-height: none;", "  padding: 0;",
      "  margin-block-start: 0.5rem;", "  background-color: transparent;", "  transform: none;", "  visibility: visible;",
      "  overflow: hidden;", "  overflow-y: auto;", "}",
      "\(page) > #quartz-body .hide-until-loaded ~ .explorer-content {", "  display: block;", "}",
      "\(page) .explorer button.mobile-explorer {", "  display: none;", "}",
      "\(page) .explorer button.desktop-explorer {", "  display: flex;", "}",
      "\(page) .search {", "  flex-grow: 0;", "}",
      "\(searchSpace) {", "  width: 65%;", "}",
      "\(searchSpace) > .search-layout {", "  flex-direction: row;", "}",
      "\(searchSpace) > .search-layout > .preview-container {", "  display: block;", "}",
      "\(searchSpace) > .search-layout[data-preview] > .results-container {", "  width: auto;", "  height: 63vh;",
      "  max-height: none;", "  flex: 0 0 min(30%, 450px);", "}",
      "\(searchSpace) > .search-layout[data-preview] .result-card > p.card-description {", "  display: none;", "}",
      "\(page) .graph > .global-graph-outer > .global-graph-container {", "  width: 80vw;", "}",
      "@media (max-width: \(tablet)px) {", "\(searchSpace) {", "  width: 90%;", "}", "}",
      "@media (max-width: \(mobile)px) {",
      "\(page) .explorer {", "  order: -1;", "  height: initial;", "  overflow: hidden;", "  flex-shrink: 0;",
      "  align-self: flex-start;", "  margin-block: auto;", "}",
      "\(page) .explorer.collapsed, \(page) .explorer:not(.collapsed) {", "  flex: 0 0 34px;", "}",
      "\(page) .explorer.collapsed > .explorer-content {", "  transform: translateX(-100vw);", "  visibility: hidden;", "}",
      "\(page) .explorer:not(.collapsed) > .explorer-content {", "  transform: translateX(0);", "  visibility: visible;", "}",
      "\(page) .explorer .explorer-content {", "  box-sizing: border-box;", "  position: absolute;", "  top: 0;", "  left: 0;",
      "  z-index: 100;", "  width: 100vw;", "  max-width: 100vw;", "  height: 100dvh;", "  max-height: 100dvh;",
      "  padding: 4rem 0 2rem 0;", "  margin-block-start: 0;", "  background-color: var(--light);", "  overflow: hidden;", "}",
      "\(page) > #quartz-body .hide-until-loaded ~ .explorer-content {", "  display: none;", "}",
      "\(page) .explorer button.mobile-explorer {", "  display: flex;", "  margin: 0;", "  padding: 5px;", "  z-index: 101;", "}",
      "\(page) .explorer button.mobile-explorer .lucide-menu {", "  stroke: var(--darkgray);", "}",
      "\(page) .explorer button.mobile-explorer.hide-until-loaded {", "  display: none;", "}",
      "\(page) .explorer button.desktop-explorer {", "  display: none;", "}",
      "\(page) .search {", "  flex-grow: 0.3;", "}",
      "\(searchSpace) > .search-layout {", "  flex-direction: column;", "}",
      "\(searchSpace) > .search-layout > .preview-container {", "  display: none;", "}",
      "\(searchSpace) > .search-layout[data-preview] > .results-container {", "  width: 100%;", "  height: auto;",
      "  max-height: 60vh;", "  flex: 0 0 100%;", "}",
      "\(searchSpace) > .search-layout[data-preview] .result-card > p.card-description {", "  display: block;", "}",
      "\(page) .graph > .global-graph-outer > .global-graph-container {", "  width: 90%;", "}",
      "}"
    ].joined(separator: "\n")
  }

  /// The two compat blocks restate rules of `@layer quartz-base`, and an unlayered declaration
  /// beats every layered one: outside the layer they outranked every `.explorer` rule a project can
  /// write. Inside it they still outrank the plugin, and any project stylesheet outranks them.
  static func layered(_ css: String) -> String { "@layer quartz-base {\n\(css)\n}" }

  /// The whole stylesheet of a frame: the outer-grid override, the compat blocks, then desktop and
  /// the narrowing breakpoints.
  public static func frameCss(_ def: JSONValue, widths: (tablet: Double, mobile: Double)) throws -> String {
    var blocks: [String] = []
    for breakpoint in breakpoints {
      guard let all = def["breakpoints"], all != .null else { throw JS.readError(def["breakpoints"], breakpoint) }
      let block = try breakpointBlock(".qgframe-grid", member(all, breakpoint), def["areas"])
      let maxWidth: Double? = breakpoint == "tablet" ? widths.tablet : breakpoint == "mobile" ? widths.mobile : nil
      if let maxWidth, maxWidth != 0, !maxWidth.isNaN {
        blocks.append("@media (max-width: \(JSJSON.numberToString(maxWidth))px) {\n\(block)\n}")
      } else {
        blocks.append(block)
      }
    }
    let page = ".page[data-frame=\"\(try escapeAttribute(def["frameName"]))\"]"
    var parts = [outerGridOverride(page)]
    if !isDefault(widths) {
      parts.append(layered(quartzBreakpointCompat(page, widths)))
      parts.append(layered(pluginBreakpointCompat(page, widths)))
    }
    return (parts + blocks).joined(separator: "\n\n")
  }

  // MARK: the old shape

  /// A frame.json from before breakpoints (flat rows/cols/gap, geometry on the areas) in the current
  /// shape: desktop gets the old grid, tablet and mobile start as copies. A definition in the new
  /// shape passes through untouched.
  public static func migrate(_ def: JSONValue) throws -> JSONValue {
    guard case .number = def["rows"] else { return def }
    let oldAreas: [JSONValue]
    switch def["areas"] {
    case .array(let items)?: oldAreas = items
    case nil: throw JS.readError(nil, "map")
    case .null?: throw JS.readError(.null, "map")
    default: throw JS.TypeError("def.areas.map is not a function")
    }
    var areas: [JSONValue] = []
    var placements = JSONObject()
    for area in oldAreas {
      if area == .null { throw JS.readError(.null, "id") }
      areas.append(.object(present([("id", area["id"]), ("name", area["name"]), ("slot", area["slot"])])))
    }
    for area in oldAreas {
      let placement = JSONValue.object(present([("row", area["row"]), ("col", area["col"]), ("rowSpan", area["rowSpan"]), ("colSpan", area["colSpan"])]))
      placements[JS.string(area["id"])] = placement
    }
    let desktop = present([("rows", def["rows"]), ("cols", def["cols"]), ("rowGap", def["gap"]), ("columnGap", def["gap"]), ("placements", .object(placements))])
    return .object(present([
      ("id", def["id"]), ("frameName", def["frameName"]), ("areas", .array(areas)),
      ("breakpoints", .object(JSONObject([("desktop", .object(desktop)), ("tablet", .object(desktop)), ("mobile", .object(desktop))])))
    ]))
  }

  /// An object literal whose undefined values `JSON.stringify` leaves out.
  static func present(_ pairs: [(String, JSONValue?)]) -> JSONObject {
    JSONObject(pairs.compactMap { key, value in value.map { (key, $0) } })
  }
}
