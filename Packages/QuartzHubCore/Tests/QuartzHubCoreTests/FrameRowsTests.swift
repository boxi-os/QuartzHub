import Foundation
import Testing
@testable import QuartzHubCore

/// Rows of a frame (docs/plan-frame-zeilen.md): inserting, removing, moving into a row of one's
/// own, swapping. The shapes are the base template's index frame on Mobile and Desktop.
struct FrameRowsTests {
  static func at(_ r: Int, _ c: Int, _ rs: Int = 1, cs: Int) -> JSONValue {
    .object(JSONObject([("row", .number(Double(r))), ("col", .number(Double(c))), ("rowSpan", .number(Double(rs))), ("colSpan", .number(Double(cs)))]))
  }

  static func frame(_ layout: [(String, JSONValue)]) -> JSONValue {
    let names = ["header", "left", "beforeBody", "right", "pageBody", "custom", "afterBody", "footer"]
    return .object(JSONObject([("id", .string("frame-index")), ("frameName", .string("index")),
                               ("areas", .array(names.map { .object(JSONObject([("id", .string($0)), ("name", .string($0))])) })),
                               ("breakpoints", .object(JSONObject([("mobile", .object(JSONObject(layout)))])))]))
  }

  /// The template's index frame on Mobile: left in a row of height 0 under the header.
  static func mobile() -> JSONValue {
    frame([("rows", .number(8)), ("cols", .number(12)),
           ("rowSizes", .array(["auto", "0", "auto", "auto", "1fr", "auto", "auto", "auto"].map { .string($0) })),
           ("rowLineNames", .object(JSONObject([("0", .array([.string("top")])), ("3", .array([.string("main")])), ("8", .array([.string("end")]))]))),
           ("placements", .object(JSONObject([
             ("header", at(1, 1, cs: 12)), ("left", at(2, 1, cs: 12)), ("beforeBody", at(3, 1, cs: 12)), ("right", at(4, 1, cs: 12)),
             ("pageBody", at(5, 1, cs: 12)), ("custom", at(6, 1, cs: 12)), ("afterBody", at(7, 1, cs: 12)), ("footer", at(8, 1, cs: 12)),
           ])))])
  }

  /// The template's index frame on Desktop: right beside rows 2 to 5.
  static func desktop() -> JSONValue {
    frame([("rows", .number(6)), ("cols", .number(12)),
           ("rowSizes", .array([.string("auto"), .null, .string("auto")])),
           ("placements", .object(JSONObject([
             ("header", at(1, 1, cs: 12)), ("beforeBody", at(2, 1, cs: 9)), ("pageBody", at(3, 1, cs: 9)), ("custom", at(4, 1, cs: 9)),
             ("afterBody", at(5, 1, cs: 9)), ("right", at(2, 10, 4, cs: 3)), ("footer", at(6, 1, cs: 12)),
           ])))])
  }

  static func row(_ def: JSONValue, _ id: String) -> Int? { FrameView(def).placement("mobile", id)?.row }
  static func sizes(_ def: JSONValue) -> [String]? { FrameView(def).layout("mobile").rowSizes }

  @Test func leftIntoTheTrayLeavesAnEmptyRowThatGoesWithItsHeight() throws {
    let unplaced = FrameEditing.unplacing(Self.mobile(), "mobile", "left")
    #expect(FrameEditing.emptyRows(FrameView(unplaced), "mobile") == [2])
    let removed = FrameEditing.removingEmptyRows(unplaced, "mobile")
    #expect(FrameView(removed).layout("mobile").rows == 7)
    // The 0 was left's; before-body is under the header in a row of its own height.
    #expect(Self.sizes(removed) == ["auto", "auto", "auto", "1fr", "auto", "auto", "auto"])
    #expect(Self.row(removed, "beforeBody") == 2 && Self.row(removed, "footer") == 7)
    // The lines keep their rows: "main" was above right and still is, "end" stays last.
    let names = removed["breakpoints"]?["mobile"]?["rowLineNames"]?.objectValue
    #expect(names?.keys.sorted() == ["0", "2", "7"])
    #expect(names?["2"] == .array([.string("main")]))
    #expect(FrameEditing.emptyRows(FrameView(removed), "mobile").isEmpty)
  }

  @Test func aRowWithAnAreaOfItsOwnIsNotRemoved() {
    #expect(FrameEditing.removingRow(Self.mobile(), "mobile", 3) == nil)
    let one = Self.frame([("rows", .number(1)), ("cols", .number(1)), ("placements", .object(JSONObject()))])
    #expect(FrameEditing.removingRow(one, "mobile", 1) == nil)
  }

  @Test func anInsertedRowMovesTheAreasBelowAndStretchesTheOnesAcross() throws {
    let def = Self.desktop()
    let inserted = FrameEditing.insertingRow(def, "mobile", before: 4)
    let view = FrameView(inserted)
    #expect(view.layout("mobile").rows == 7)
    #expect(view.placement("mobile", "custom")?.row == 5 && view.placement("mobile", "pageBody")?.row == 3)
    // right covered rows 2 to 5 and covers the same rows, now 2 to 6.
    #expect(view.placement("mobile", "right").map { [$0.row, $0.rowSpan] } == [2, 5])
    // Sizes shorter than the rows are left alone past their end; before it, a hole is made.
    #expect(view.layout("mobile").rowSizes == ["auto", "", "auto"])
    let early = FrameEditing.insertingRow(def, "mobile", before: 2)
    #expect(early["breakpoints"]?["mobile"]?["rowSizes"] == .array([.string("auto"), .null, .null, .string("auto")]))
    // Out of range: nothing.
    #expect(FrameEditing.insertingRow(def, "mobile", before: 8) == def)
  }

  @Test func insertingAtTheEndKeepsTheLastLineLast() {
    let inserted = FrameEditing.insertingRow(Self.mobile(), "mobile", before: 9)
    let names = inserted["breakpoints"]?["mobile"]?["rowLineNames"]?.objectValue
    #expect(names?.keys.sorted() == ["0", "3", "9"])
    let first = FrameEditing.insertingRow(Self.mobile(), "mobile", before: 1)
    #expect(first["breakpoints"]?["mobile"]?["rowLineNames"]?.objectValue?.keys.sorted() == ["0", "4", "9"])
    #expect(FrameView(first).placement("mobile", "header")?.row == 2)
  }

  @Test func movingIntoANewRowReordersLikeAList() throws {
    // right above before-body: before-body slides down, nothing else moves, no row is left empty.
    let move = try #require(FrameEditing.movingToNewRow(Self.mobile(), "mobile", "right", before: 3))
    #expect(move.placement == FrameView.Placement(row: 3, col: 1, rowSpan: 1, colSpan: 12))
    #expect(Self.row(move.def, "beforeBody") == 4 && Self.row(move.def, "pageBody") == 5)
    #expect(FrameView(move.def).layout("mobile").rows == 8)
    // Its old row went with its size; the new row is a hole (auto), the 0 stays with left.
    #expect(Self.sizes(move.def) == ["auto", "0", "", "auto", "1fr", "auto", "auto", "auto"])
    #expect(FrameEditing.emptyRows(FrameView(move.def), "mobile").isEmpty)
    // Down: footer before page-body, the rows below shift.
    let down = try #require(FrameEditing.movingToNewRow(Self.mobile(), "mobile", "beforeBody", before: 6))
    #expect(Self.row(down.def, "right") == 3 && Self.row(down.def, "pageBody") == 4 && Self.row(down.def, "beforeBody") == 5
              && Self.row(down.def, "custom") == 6)
    #expect(down.placement.row == 5)
  }

  @Test func onDesktopTheRightColumnStaysAndTheMovedAreaKeepsItsColumns() throws {
    let move = try #require(FrameEditing.movingToNewRow(Self.desktop(), "mobile", "beforeBody", before: 4))
    let view = FrameView(move.def)
    #expect(view.layout("mobile").rows == 6)
    #expect(view.placement("mobile", "pageBody")?.row == 2 && view.placement("mobile", "beforeBody").map { [$0.row, $0.col, $0.colSpan] } == [3, 1, 9])
    // right only passed through the row before-body left: one row shorter, the same rows beside it.
    #expect(view.placement("mobile", "right").map { [$0.row, $0.rowSpan] } == [2, 4])
    #expect(FrameEditing.placementWarnings(view, "mobile").overlapping.isEmpty)
    // From the tray, the widest free run of the new row: beside right, nine columns.
    let tray = FrameEditing.unplacing(Self.desktop(), "mobile", "custom")
    let back = try #require(FrameEditing.movingToNewRow(tray, "mobile", "custom", before: 3))
    #expect(back.placement.col == 1 && back.placement.colSpan == 9)
    // A two-row area becomes one row, and says so; both rows it left go.
    let tall = FrameEditing.withPlacement(FrameEditing.insertingRow(Self.desktop(), "mobile", before: 2), "mobile", "header",
                                          .init(row: 1, col: 1, rowSpan: 2, colSpan: 12))
    let header = try #require(FrameEditing.movingToNewRow(tall, "mobile", "header", before: 8))
    #expect(header.rowSpanBefore == 2 && header.placement.rowSpan == 1 && header.placement.row == 6)
    #expect(FrameView(header.def).layout("mobile").rows == 6)
    #expect(FrameEditing.movingToNewRow(Self.desktop(), "mobile", "nobody", before: 2) == nil)
  }

  @Test func swappingTradesPlacesWhereBothFit() throws {
    let swapped = try FrameEditing.swapping(Self.mobile(), "mobile", "footer", "header")!.get()
    #expect(Self.row(swapped, "footer") == 1 && Self.row(swapped, "header") == 8)
    let desktop = Self.desktop()
    let pages = try FrameEditing.swapping(desktop, "mobile", "beforeBody", "afterBody")!.get()
    #expect(FrameView(pages).placement("mobile", "beforeBody")?.row == 5)
    // header (twelve columns) cannot go where before-body is: right is in the way.
    #expect(FrameEditing.swapping(desktop, "mobile", "header", "beforeBody") == .failure(.overlap))
    // right (four rows) at the footer's place reaches past the grid.
    #expect(FrameEditing.swapping(desktop, "mobile", "right", "footer") == .failure(.outside))
    #expect(FrameEditing.swapping(desktop, "mobile", "right", "right") == nil)
  }
}

extension FrameRowsTests {
  @Test func anAreaInRowsOfHeightZeroIsSaid() {
    // 00_test's index on Mobile: left in the tray, the areas pulled up by hand, the 0 left behind.
    var def = FrameEditing.unplacing(Self.mobile(), "mobile", "left")
    for (id, row) in [("beforeBody", 2), ("right", 3), ("pageBody", 4), ("custom", 5), ("afterBody", 6), ("footer", 7)] {
      def = FrameEditing.withPlacement(def, "mobile", id, .init(row: row, col: 1, rowSpan: 1, colSpan: 12))
    }
    #expect(FrameEditing.collapsedAreas(FrameView(def), "mobile") == ["beforeBody"])
    #expect(FrameEditing.emptyRows(FrameView(def), "mobile") == [8])
    #expect(FrameEditing.warningKeys(FrameView(def), "mobile").contains("emptyRow:8"))
    // The template's own left, in its row of 0, is found too; whether it matters is what its slot
    // holds, which the page knows (an empty left on phones is the template's intent).
    #expect(FrameEditing.collapsedAreas(FrameView(Self.mobile()), "mobile") == ["left"])
    let units = FrameEditing.withSetting(def, "mobile", "rowSizes", .array(["auto", "0px"].map { .string($0) }))
    #expect(FrameEditing.collapsedAreas(FrameView(units), "mobile") == ["beforeBody"])
    let none = FrameEditing.withSetting(def, "mobile", "rowSizes", .array(["auto", "10px"].map { .string($0) }))
    #expect(FrameEditing.collapsedAreas(FrameView(none), "mobile").isEmpty)
  }
}
