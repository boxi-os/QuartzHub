import Foundation
import Testing
@testable import QuartzHubCore

/// `layout.sidebars` and `byPageType.<type>.sidebars` as Quartz 5.1's `parseSidebars` and
/// `buildLayout` read them (config-loader.ts): the page type over the site, "fit" without either.
@Suite struct SidebarModesTests {
  static func config(_ layout: JSONValue) -> QuartzConfig { QuartzConfig(layout: layout.objectValue) }

  @Test func thePageTypeOverridesTheSite() throws {
    let layout = try JSJSON.parse(#"{"sidebars":{"left":"scroll","right":"bogus"},"byPageType":{"folder":{"sidebars":{"right":"static"}}}}"#)
    let config = Self.config(layout)
    #expect(PageTypeOverride.sidebar(config, nil, "left") == ("scroll", true))
    // An unknown mode is fit, as Quartz warns and uses fit.
    #expect(PageTypeOverride.sidebar(config, nil, "right") == ("fit", false))
    #expect(PageTypeOverride.sidebar(config, "folder", "left") == ("scroll", false))
    #expect(PageTypeOverride.sidebar(config, "folder", "right") == ("static", true))
    #expect(PageTypeOverride.sidebar(QuartzConfig(), "tag", "left") == ("fit", false))
  }

  @Test func writingKeepsWhatElseIsThereAndLeavesNoEmptyShells() throws {
    var config = Self.config(try JSJSON.parse(#"{"groups":{},"byPageType":{}}"#))
    config = PageTypeOverride.withSidebar(config, nil, "left", "static")
    #expect(config.layout?["sidebars"] == .object(JSONObject([("left", .string("static"))])))
    config = PageTypeOverride.withSidebar(config, "folder", "right", "scroll")
    #expect(PageTypeOverride.stored(config, "folder") == .object(JSONObject([("sidebars", .object(JSONObject([("right", .string("scroll"))])))])))
    // A page type with only sidebars customizes something and survives the next write through `with`.
    config = PageTypeOverride.withTemplate(config, "folder", nil)
    #expect(PageTypeOverride.sidebar(config, "folder", "right") == ("scroll", true))
    config = PageTypeOverride.withSidebar(config, "folder", "right", nil)
    #expect(PageTypeOverride.stored(config, "folder") == nil)
    config = PageTypeOverride.withSidebar(config, nil, "left", nil)
    #expect(config.layout?["sidebars"] == nil)
    #expect(config.layout?["groups"] == .object(JSONObject()))
  }
}
