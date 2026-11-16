import Foundation
import Testing
@testable import QuartzHubCore

/// Areas across the full window (`fullWidth` on an area of frame.json), QuartzHub's addition to
/// QuartzControl's frames. Without the key the CSS stays QuartzControl's (LayoutFramesTests).
@Suite struct FullWidthAreasTests {
  static func frame(fullWidth: JSONValue?, mobileHeaderSpan: Int = 2) throws -> JSONValue {
    let header = fullWidth.map { #","fullWidth":\#(JSJSON.compact($0))"# } ?? ""
    let text = #"""
    {"id":"frame-x","frameName":"x","areas":[
      {"id":"area-header","name":"header","slot":"header"\#(header)},
      {"id":"area-body","name":"body","slot":"pageBody"}],
     "breakpoints":{
      "desktop":{"rows":2,"cols":4,"rowGap":"2rem","columnGap":"4rem","maxWidth":"1440px","align":"center","paddingBlock":"20px","paddingInline":"20px",
        "placements":{"area-header":{"row":1,"col":1,"rowSpan":1,"colSpan":4},"area-body":{"row":2,"col":2,"rowSpan":1,"colSpan":2}}},
      "tablet":{"rows":2,"cols":4,"rowGap":"2rem","columnGap":"3rem","maxWidth":"100%","align":"left","paddingInline":"20px",
        "placements":{"area-header":{"row":1,"col":1,"rowSpan":1,"colSpan":4},"area-body":{"row":2,"col":1,"rowSpan":1,"colSpan":4}}},
      "mobile":{"rows":2,"cols":4,"rowGap":"1rem","columnGap":"1rem","paddingInline":"20px",
        "placements":{"area-header":{"row":1,"col":1,"rowSpan":1,"colSpan":\#(mobileHeaderSpan)},"area-body":{"row":2,"col":1,"rowSpan":1,"colSpan":4}}}}}
    """#
    return try JSJSON.parse(Data(text.utf8))
  }

  static let widths = (tablet: 1200.0, mobile: 900.0)

  @Test func withoutTheKeyNothingChanges() throws {
    let plain = try GridFrameCss.frameCss(Self.frame(fullWidth: nil), widths: Self.widths)
    #expect(try plain == GridFrameCss.frameCss(Self.frame(fullWidth: .bool(false)), widths: Self.widths))
    #expect(!plain.contains("qgframe-full") && !plain.contains("overflow-x: clip"))
  }

  @Test func aFullAreaGetsEdgeTracks() throws {
    let css = try GridFrameCss.frameCss(Self.frame(fullWidth: .bool(true), mobileHeaderSpan: 1), widths: Self.widths)
    // Desktop: centred, so both edge tracks take half the room beside 1440px, plus the padding.
    let edge = "calc(20px + max(0px, (100% - 2 * (4rem) - 1440px) / 2))"
    #expect(css.contains("grid-template-columns: [qgframe-full-start] \(edge) 1fr 1fr 1fr 1fr \(edge) [qgframe-full-end];"))
    #expect(css.contains("  width: calc(100% + 2 * (4rem));\n  max-width: none;\n  margin-inline: calc(-1 * (4rem));"))
    #expect(css.contains("\"header header header header header header\"\n      \". . body body . .\""))
    #expect(css.contains(".qgframe-area-header { grid-area: header; margin-inline: 4rem; }"))
    // Tablet: maxWidth 100% leaves no room; the edge tracks are the padding.
    #expect(css.contains("grid-template-columns: [qgframe-full-start] 20px 1fr 1fr 1fr 1fr calc(20px + max(0px, (100% - 2 * (3rem) - 100%))) [qgframe-full-end];"))
    // Mobile: the header fills half a row, so the grid stays as it was, the margin goes back to 0.
    let mobile = try #require(css.components(separatedBy: "@media (max-width: 900px)").last)
    #expect(mobile.contains("grid-template-columns: 1fr 1fr 1fr 1fr;") && mobile.contains("padding-inline: 20px;"))
    #expect(mobile.contains(".qgframe-area-header { grid-area: header; margin-inline: 0; }"))
    #expect(css.contains("> #quartz-body {\n  padding-inline: 0;\n  overflow-x: clip;\n}"))
  }

  @Test func fillsRowsAndTheCheck() throws {
    let def = try Self.frame(fullWidth: .bool(true), mobileHeaderSpan: 1)
    let header = try #require(def["areas"]?.arrayValue?.first)
    #expect(GridFrameCss.fillsRows(def["breakpoints"]?["desktop"], header))
    #expect(!GridFrameCss.fillsRows(def["breakpoints"]?["mobile"], header))
    #expect(FrameDefinitionCheck.problem(def) == nil)
    #expect(try FrameDefinitionCheck.problem(Self.frame(fullWidth: .string("yes"))) != nil)
  }

  @Test func editingTheSwitch() throws {
    let plain = try Self.frame(fullWidth: nil, mobileHeaderSpan: 1)
    let on = FrameEditing.withAreaFullWidth(plain, "area-header", true)
    #expect(FrameEditing.fullWidthShortRows(on, "area-header") == ["mobile"])
    #expect(FrameEditing.fullWidthShortRows(plain, "area-header").isEmpty)
    #expect(FrameEditing.withAreaFullWidth(on, "area-header", false) == plain)
  }
}
