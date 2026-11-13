import Foundation
import Testing
@testable import QuartzHubCore

/// A renamed frame keeps its page types (review 2026-11-13, handbook, N2).
@Suite struct FrameRenameTests {
  @Test func pageTypesFollowARenamedFrame() throws {
    let raw = try JSJSON.parse(Data(#"""
    {"configuration": {}, "theme": {}, "plugins": [], "layout": {"byPageType": {
      "content": {"template": "breit"}, "folder": {"template": "schmal"},
      "tag": {"template": "breit", "sidebars": {"left": false}}, "404": {}
    }}}
    """#.utf8))
    let config = try #require(QuartzConfig(jsonValue: raw))
    let (renamed, changed) = PageTypeOverride.renamingTemplate(config, from: "breit", to: "weit")
    #expect(changed.sorted() == ["content", "tag"])
    #expect(PageTypeOverride.of(renamed, "content")["template"] == .string("weit"))
    #expect(PageTypeOverride.of(renamed, "tag")["template"] == .string("weit"))
    #expect(PageTypeOverride.of(renamed, "tag")["sidebars"] == PageTypeOverride.of(config, "tag")["sidebars"])
    #expect(PageTypeOverride.of(renamed, "folder")["template"] == .string("schmal"))
    // The same name, or no old name: nothing changes.
    #expect(PageTypeOverride.renamingTemplate(config, from: "breit", to: "breit").1.isEmpty)
    #expect(PageTypeOverride.renamingTemplate(config, from: "", to: "x").1.isEmpty)
  }
}
