import Foundation
import Testing
@testable import QuartzHubCore

/// Which project rule still wins over a value set on the Variables tab (docs/plan-plugin-variablen.md, B2).
@Suite struct PluginVariableCascadeTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  func spec(_ s: String) -> [Int] { let v = CssSpecificity.of(s); return [v.0, v.1, v.2] }

  @Test func countsSpecificityAsSelectorsLevel4() {
    #expect(spec(".quartz-nav") == [0, 1, 0])
    #expect(spec(".quartz-nav.nav-menue") == [0, 2, 0])
    #expect(spec(".quartz-nav--rail") == [0, 1, 0])
    #expect(spec(#":root[saved-theme="dark"] .quartz-nav"#) == [0, 3, 0])
    #expect(spec(":root:not([saved-theme=dark]) .quartz-nav") == [0, 3, 0])
    #expect(spec(#".quartz-nav[data-quartz-nav="side"]"#) == [0, 2, 0])
    #expect(spec("#main > nav.quartz-nav li a::before") == [1, 1, 4])
    #expect(spec("a:hover::after") == [0, 1, 2])
    #expect(spec("li:nth-child(2n+1)") == [0, 1, 1])
    #expect(spec(":is(#a, .b) .c") == [1, 1, 0])
    #expect(spec(":where(#a, .b) .c") == [0, 1, 0])
    #expect(spec("*") == [0, 0, 0])
    #expect(spec(".a, #b") == [1, 0, 0])
    #expect(spec(#"[title="a,b"] .x"#) == [0, 2, 0])
    #expect(spec(".quartz-nav [data-level=\"1\"]>.quartz-nav__item--folder") == [0, 3, 0])
  }

  typealias S = PluginVariables.Setter
  let icon = PluginVariableOverride(selector: ".quartz-nav", key: "quartz-nav-rail-icon-size", light: "1.5rem")

  @Test func aTemplateRuleOfTheSameWeightLosesACustomOneWins() {
    let template = S(selector: ".quartz-nav--rail", mode: "light", value: "var(--tpl-icon)")
    let custom = S(selector: ".quartz-nav--rail", mode: "light", value: "2rem")
    #expect(PluginVariableCascade.stronger(icon, setBy: [template], mode: "light", inCustom: { _ in false }).isEmpty)
    #expect(PluginVariableCascade.stronger(icon, setBy: [custom], mode: "light", inCustom: { _ in true }) == [custom])
    // More specific wins wherever it stands.
    let instance = S(selector: ".quartz-nav.nav-menue", mode: "light", value: "1.2rem")
    #expect(PluginVariableCascade.stronger(icon, setBy: [instance], mode: "light", inCustom: { _ in false }) == [instance])
  }

  @Test func modesCountTheirOwnRules() {
    let templateDark = S(selector: ".quartz-nav", mode: "dark", value: "#888", rule: ":root[saved-theme=dark] .quartz-nav")
    // A value for both modes is a plain rule: in dark the template's dark rule (0,3,0) beats it.
    #expect(PluginVariableCascade.stronger(icon, setBy: [templateDark], mode: "dark", inCustom: { _ in false }) == [templateDark])
    #expect(PluginVariableCascade.stronger(icon, setBy: [templateDark], mode: "light", inCustom: { _ in false }).isEmpty)
    // A dark value of its own has the same weight and comes later.
    var split = icon
    split.dark = "2rem"
    #expect(PluginVariableCascade.stronger(split, setBy: [templateDark], mode: "dark", inCustom: { _ in false }).isEmpty)
    // Light only: nothing of the page's in dark mode to beat.
    var lightOnly = icon
    lightOnly.lightOnly = true
    #expect(PluginVariableCascade.stronger(lightOnly, setBy: [templateDark], mode: "dark", inCustom: { _ in false }).isEmpty)
    #expect(PluginVariableCascade.ownRule(lightOnly, mode: "light") == #":root:not([saved-theme="dark"]) .quartz-nav"#)
  }

  @Test func thePagesOwnRuleInTheBuildIsNotARival() {
    let built = S(selector: ".quartz-nav", mode: "light", value: "1.5rem")
    #expect(PluginVariableCascade.stronger(icon, setBy: [built], mode: "light", inCustom: { _ in true }).isEmpty)
  }

  @Test func tellsThePagesOwnRulesInTheBuild() {
    var saved = icon
    saved.dark = "2rem"
    #expect(PluginVariableCascade.isOwn(S(selector: ".quartz-nav", mode: "light", value: "1.5rem"), saved: saved))
    #expect(PluginVariableCascade.isOwn(S(selector: ".quartz-nav", mode: "dark", value: "2rem", rule: ":root[saved-theme=dark] .quartz-nav"), saved: saved))
    // The template's rule at the same selector with another value is not the page's.
    #expect(!PluginVariableCascade.isOwn(S(selector: ".quartz-nav", mode: "light", value: "var(--tpl-icon)"), saved: saved))
    #expect(!PluginVariableCascade.isOwn(S(selector: ".quartz-nav.nav-menue", mode: "light", value: "1.5rem"), saved: saved))
    #expect(!PluginVariableCascade.isOwn(S(selector: ".quartz-nav", mode: "light", value: "1.5rem"), saved: nil))
    var lightOnly = icon
    lightOnly.lightOnly = true
    #expect(PluginVariableCascade.isOwn(S(selector: ":root:not([saved-theme=dark]) .quartz-nav", mode: "light", value: "1.5rem",
                                          rule: ":root:not([saved-theme=dark]) .quartz-nav"), saved: lightOnly))
  }

  @Test func findsCustomScssRulesAsTheBuildSpellsThem() throws {
    let root = "\(scratch.path)/\(UUID().uuidString)"
    try Posix.mkdirs("\(root)/quartz/styles")
    try Posix.write("\(root)/quartz/styles/custom.scss", Data("""
      @use "./quartzcontrol";
      // .commented { --x: 1; }
      .quartz-nav.nav-menue {
        --quartz-nav-rail-icon-size: 1.5rem;
      }
      :root[saved-theme="dark"]   .quartz-nav  >  .a { --quartz-nav-color: red; }
      /* --- QuartzControl:managed:plugin-vars:start --- */
      .quartz-nav { --quartz-nav-gap: 1px; }
      /* --- QuartzControl:managed:plugin-vars:end --- */
      """.utf8))
    let found = PluginVariableCascade.customSelectors(project: root)
    #expect(found["quartz-nav-rail-icon-size"] == [".quartz-nav.nav-menue"])
    #expect(found["quartz-nav-color"] == [":root[saved-theme=dark] .quartz-nav>.a"])
    #expect(found["quartz-nav-gap"] == nil)
    #expect(found["x"] == nil)
  }
}
