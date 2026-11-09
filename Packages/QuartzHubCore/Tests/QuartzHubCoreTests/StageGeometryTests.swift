import Foundation
import Testing
@testable import QuartzHubCore

/// `StageGeometry` and `FrameEditing` against QuartzControl's own code
/// (`scripts/stage-geometry-golden.mjs`), and the frame editor's edits by hand.
@Suite struct StageGeometryTests {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/stage-geometry")
  static let golden: JSONValue? = (try? Data(contentsOf: directory.appendingPathComponent("cases.json"))).flatMap { try? JSJSON.parse($0) }
  static let breakpoints = ["desktop", "tablet", "mobile"]

  static func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap(\.stringValue) }

  @Test func lengthsAsQuartzControlReadsThem() throws {
    let lengths = try #require(Self.golden?["lengths"]?.arrayValue)
    #expect(lengths.count == 94)
    for item in lengths {
      let mine = StageGeometry.lengthToPx(item["value"]!.stringValue!, percentBase: item["percentBase"]!.numberValue!, viewport: item["viewport"]!.numberValue!)
      #expect(mine.map(JSONValue.number) ?? .null == item["px"], "\(item["value"]!.stringValue!)")
    }
  }

  @Test func tracksAsQuartzControlSharesThem() throws {
    for item in try #require(Self.golden?["tracks"]?.arrayValue) {
      let mine = StageGeometry.tracks(Self.strings(item["sizes"]), inner: item["inner"]!.numberValue!, gap: item["gap"]!.numberValue!,
                                      viewport: item["viewport"]!.numberValue!)
      #expect(mine.css == item["columns"]?.stringValue, "\(Self.strings(item["sizes"]))")
      #expect(mine.approximate == Self.strings(item["approximate"]), "\(Self.strings(item["sizes"]))")
    }
    for (bp, width) in StageGeometry.referenceWidth { #expect(Self.golden?["reference"]?[bp] == .number(width)) }
  }

  @Test func framesOnTheStageAndTheirWarnings() throws {
    let frames = try #require(Self.golden?["perFrame"]?.arrayValue)
    #expect(frames.count == 7)
    var warnings = 0
    for item in frames {
      let raw = item["frame"]!
      let view = FrameView(raw)
      for bp in Self.breakpoints {
        let stage = StageGeometry.frame(view.layout(bp), bp)
        let want = try #require(item["stage"]?[bp]?.objectValue)
        for (key, value) in stage.css { #expect(.string(value) == want[key], "\(view.frameName) \(bp) \(key)") }
        #expect(stage.tracks.approximate.map(JSONValue.string) == want["approximate"]?.arrayValue, "\(view.frameName) \(bp)")

        let w = FrameEditing.slotWarnings(view, bp)
        let ww = item["slotWarnings"]?[bp]
        #expect(w.unassigned == Self.strings(ww?["unassigned"]) && w.homeless == Self.strings(ww?["homeless"])
                && w.doubled == Self.strings(ww?["doubled"]) && w.hiddenGroups == Self.strings(ww?["hiddenGroups"]), "\(view.frameName) \(bp)")
        let p = FrameEditing.placementWarnings(view, bp)
        #expect(p.overlapping.map { JSONValue.array([.string($0.0), .string($0.1)]) } == item["placementWarnings"]?[bp]?["overlapping"]?.arrayValue, "\(view.frameName) \(bp)")
        #expect(p.outside == Self.strings(item["placementWarnings"]?[bp]?["outside"]), "\(view.frameName) \(bp)")
        warnings += FrameEditing.warningKeys(view, bp).count

        let layout = view.layout(bp)
        var cells: [JSONValue] = []
        for r in 0...(layout.rows + 1) {
          for c in 0...(layout.cols + 1) { cells.append(FrameEditing.placementAt(view, bp, row: r, col: c).map { .string($0.id) } ?? .null) }
        }
        #expect(cells == item["cells"]?[bp]?.arrayValue, "\(view.frameName) \(bp)")
        var overlaps: [JSONValue] = []
        for a in view.areas {
          for (rs, cs) in [(1, 1), (2, 2), (1, 3)] {
            overlaps.append(.bool(FrameEditing.overlaps(view, bp, row: 1, col: 1, rowSpan: rs, colSpan: cs, except: a.id)))
            overlaps.append(.bool(FrameEditing.overlaps(view, bp, row: 2, col: 2, rowSpan: rs, colSpan: cs)))
          }
        }
        #expect(overlaps == item["overlaps"]?[bp]?.arrayValue, "\(view.frameName) \(bp)")
        let fits = view.areas.map { a in view.placement(bp, a.id).map { JSONValue.bool(FrameEditing.fitsGrid(layout, $0)) } ?? .null }
        #expect(fits == item["fits"]?[bp]?.arrayValue, "\(view.frameName) \(bp)")
      }
      #expect(FrameEditing.nextAreaName(raw) == item["nextAreaName"]?.stringValue)
      let placement = JSONValue.object(JSONObject([("row", .number(2)), ("col", .number(1)), ("rowSpan", .number(1)), ("colSpan", .number(2)), ("hidden", .bool(false))]))
      for (k, area) in view.areas.prefix(3).enumerated() {
        #expect(FrameEditing.replacingPlacement(raw, "tablet", area.id, placement) == item["withPlacement"]?.arrayValue?[k], "\(view.frameName) \(area.id)")
      }
    }
    #expect(warnings > 10)
  }

  @Test func namesAndQuartzsOwnFrame() throws {
    for item in Self.golden?["slugs"]?.arrayValue ?? [] {
      #expect(FrameEditing.slugify(item["text"]!.stringValue!) == item["slug"]?.stringValue, "\(item["text"]!.stringValue!)")
    }
    for item in Self.golden?["slots"]?.arrayValue ?? [] {
      #expect(FrameEditing.slotToName(item["slot"]!.stringValue!) == item["name"]?.stringValue)
    }
    // The empty draft is the last frame of the golden.
    #expect(FrameEditing.emptyDraft(id: "frame-fixed") == Self.golden?["perFrame"]?.arrayValue?.last?["frame"])
    let standard = try #require(Self.golden?["standard"]?.arrayValue)
    #expect(FrameEditing.quartzDefaultFrame(id: "frame-fixed", frameName: "standard") == standard[0]["frame"])
    let measured = ScssCheck.Measures(
      grids: ["desktop": .init(columns: ["18rem", "auto", "18rem", "10px"], rowGap: "6px", columnGap: "8px"),
              "tablet": .init(columns: ["300px", "auto"], rowGap: "6px", columnGap: "9px"),
              "mobile": .init(columns: ["auto"], rowGap: "2px", columnGap: "3px")],
      breakpoints: (mobile: 700, desktop: 1100), pageMaxWidth: nil)
    #expect(FrameEditing.quartzDefaultFrame(id: "frame-fixed", frameName: "eigen", measures: measured) == standard[1]["frame"])
    for bp in Self.breakpoints { #expect(.bool(FrameEditing.columnsFit(measured, bp)) == standard[1]["fit"]?[bp]) }
    for item in Self.golden?["shown"]?.arrayValue ?? [] {
      #expect(.bool(LayoutStage.shownInView(item["display"]?.stringValue, item["bp"]!.stringValue!)) == item["shown"])
    }
  }

  // MARK: the editor's edits, by hand

  /// A 3×3 grid: `a` on row 1 across all columns, `b` at 2/1, `c` at 2/3, `d` in the tray.
  static func board() -> JSONValue {
    let area = { (id: String, slot: String) in JSONValue.object(JSONObject([("id", .string(id)), ("name", .string(id)), ("slot", .string(slot))])) }
    let at = { (r: Int, c: Int, rs: Int, cs: Int) in
      JSONValue.object(JSONObject([("row", .number(Double(r))), ("col", .number(Double(c))), ("rowSpan", .number(Double(rs))), ("colSpan", .number(Double(cs)))]))
    }
    let desktop = JSONValue.object(JSONObject([("rows", .number(3)), ("cols", .number(3)), ("rowGap", .string("1rem")), ("columnGap", .string("1rem")),
                                               ("placements", .object(JSONObject([("a", at(1, 1, 1, 3)), ("b", at(2, 1, 1, 1)), ("c", at(2, 3, 1, 1))])))]))
    return .object(JSONObject([("id", .string("frame-1")), ("frameName", .string("brett")),
                               ("areas", .array([area("a", "header"), area("b", "left"), area("c", "right"), area("d", "footer")])),
                               ("breakpoints", .object(JSONObject([("desktop", desktop), ("tablet", desktop), ("mobile", desktop)])))]))
  }

  @Test func aSpanGrowsUntilItMeetsAnotherArea() throws {
    let def = Self.board()
    let wider = try FrameEditing.withSpan(def, "desktop", "b", colSpan: 2).get()
    #expect(FrameView(wider).placement("desktop", "b")?.colSpan == 2)
    #expect(FrameEditing.withSpan(def, "desktop", "b", colSpan: 3) == .failure(.overlap))
    // Clamped to the grid: four rows on a three-row grid from row 2 are two.
    #expect(FrameView(try FrameEditing.withSpan(def, "desktop", "b", rowSpan: 4).get()).placement("desktop", "b")?.rowSpan == 2)
    // A span edit keeps the placement's other keys and adds no `hidden`.
    #expect(wider["breakpoints"]?["desktop"]?["placements"]?["b"]?.objectValue?.keys == ["row", "col", "rowSpan", "colSpan"])
    // The other breakpoints are untouched.
    #expect(wider["breakpoints"]?["tablet"] == def["breakpoints"]?["tablet"])
  }

  @Test func showingAgainIsRefusedWhereItNoLongerFits() throws {
    let def = Self.board()
    let hidden = try FrameEditing.withHidden(def, "desktop", "b", true).get()
    #expect(hidden["breakpoints"]?["desktop"]?["placements"]?["b"]?["hidden"] == .bool(true))
    let covered = try FrameEditing.dropping(hidden, "desktop", "c", row: 2, col: 1)!.get()
    #expect(FrameEditing.withHidden(covered, "desktop", "b", false) == .failure(.overlap))
    let shrunk = FrameEditing.withSetting(hidden, "desktop", "rows", .number(1))
    #expect(FrameEditing.withHidden(shrunk, "desktop", "b", false) == .failure(.outside))
    #expect(try FrameEditing.withHidden(hidden, "desktop", "b", false).get()["breakpoints"]?["desktop"]?["placements"]?["b"]?["hidden"] == .bool(false))
  }

  @Test func aDropKeepsTheSpanThatFitsAndRefusesAnOverlap() throws {
    let def = Self.board()
    // a spans three columns; dropped on column 2 of row 3 it keeps two.
    let landing = try #require(FrameEditing.landing(def, "desktop", "a", row: 3, col: 2))
    #expect(landing.colSpan == 2 && !landing.refused)
    #expect(FrameEditing.landing(def, "desktop", "d", row: 2, col: 1)?.refused == true)
    let placed = try FrameEditing.dropping(def, "desktop", "d", row: 3, col: 1)!.get()
    #expect(placed["breakpoints"]?["desktop"]?["placements"]?["d"]?.objectValue?.keys == ["row", "col", "rowSpan", "colSpan", "hidden"])
    #expect(FrameEditing.landing(def, "desktop", "nope", row: 1, col: 1) == nil)
    let back = FrameEditing.unplacing(placed, "desktop", "d")
    #expect(back == def)
    let gone = FrameEditing.deletingArea(def, "b")
    #expect(FrameView(gone).areas.map(\.id) == ["a", "c", "d"])
    #expect(Self.breakpoints.allSatisfy { FrameView(gone).placement($0, "b") == nil })
  }

  @Test func aDraggedEdgeStopsBeforeAnotherArea() throws {
    let view = FrameView(Self.board())
    let b = try #require(view.placement("desktop", "b"))
    // Right edge of b towards column 3: c sits there, so it stops at 2.
    #expect(FrameEditing.resized(view, "desktop", "b", from: b, sides: .right, toCol: 3, toRow: 2).colSpan == 2)
    // Bottom edge into the free row 3.
    #expect(FrameEditing.resized(view, "desktop", "b", from: b, sides: .bottom, toCol: 1, toRow: 3).rowSpan == 2)
    // Top edge into a: blocked, nothing changes.
    #expect(FrameEditing.resized(view, "desktop", "b", from: b, sides: .top, toCol: 1, toRow: 1) == b)
    // The corner: right and bottom together, around c.
    let corner = FrameEditing.resized(view, "desktop", "b", from: b, sides: [.right, .bottom], toCol: 2, toRow: 3)
    #expect(corner.colSpan == 2 && corner.rowSpan == 2)
    // Shrinking from the left moves the start.
    let wide = FrameView.Placement(row: 3, col: 1, rowSpan: 1, colSpan: 3)
    let left = FrameEditing.resized(view, "desktop", "d", from: wide, sides: .left, toCol: 3, toRow: 3)
    #expect(left.col == 3 && left.colSpan == 1)
  }

  @Test func settingsOfABreakpointAsTheEditorWritesThem() {
    let def = Self.board()
    let sized = FrameEditing.withTrackSize(def, "desktop", "columnSizes", 2, "200px")
    #expect(sized["breakpoints"]?["desktop"]?["columnSizes"] == .array([.null, .null, .string("200px")]))
    let named = FrameEditing.withLineName(FrameEditing.withLineName(def, "desktop", "columnLineNames", 3, " end "), "desktop", "columnLineNames", 0, "start")
    #expect(named["breakpoints"]?["desktop"]?["columnLineNames"]?.objectValue?.keys == ["0", "3"])
    #expect(FrameEditing.withLineName(named, "desktop", "columnLineNames", 3, "  ")["breakpoints"]?["desktop"]?["columnLineNames"]?.objectValue?.keys == ["0"])
    let copied = FrameEditing.copyLayout(sized, from: "desktop", to: "mobile")
    #expect(copied["breakpoints"]?["mobile"] == sized["breakpoints"]?["desktop"])
    let added = FrameEditing.addingArea(def, id: "area-9")
    #expect(added["areas"]?.arrayValue?.last == .object(JSONObject([("id", .string("area-9")), ("name", .string("custom-5"))])))
    let grouped = FrameEditing.withAreaGroup(FrameEditing.withAreaName(added, "b", "Seiten Leiste"), "b", own: true)
    #expect(FrameView(grouped).areas[1].group == "seiten-leiste")
    // Renaming does not rename the group; a slot without groups (page body) takes it away.
    #expect(FrameView(FrameEditing.withAreaName(grouped, "b", "neu")).areas[1].group == "seiten-leiste")
    #expect(FrameView(FrameEditing.withAreaSlot(grouped, "b", "pageBody")).areas[1].group == nil)
    #expect(FrameView(FrameEditing.withAreaSlot(grouped, "b", nil)).areas[1].slot == nil)
    let frames = [FrameView(def)]
    #expect(FrameEditing.freeName("brett", frames: frames) == "brett-2")
    #expect(FrameEditing.freeName("minimal", frames: frames) == "minimal-2")
    #expect(FrameView(FrameEditing.duplicate(def, id: "frame-2", frames: frames)).frameName == "brett-kopie")
    #expect(FrameEditing.nameCollision(FrameView(FrameEditing.duplicate(def, id: "frame-2", frames: frames)), frames: frames) == false)
  }
}
