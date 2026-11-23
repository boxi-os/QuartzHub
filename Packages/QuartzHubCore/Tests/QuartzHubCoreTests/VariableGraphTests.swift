import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own variableGraphService.ts and cssVariables.ts:
/// `scripts/variable-graph-golden.mjs` built six projects (gui-test's stylesheets and build CSS,
/// made-up CSS with the cases the reader learnt) and recorded the graph, and the catalog with its
/// helpers. core 3's theme in the build is QuartzHub's own: `core3ThemeFromTheBuild`.
@Suite struct VariableGraphTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/variable-graph")

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  static func copy(_ from: String, _ to: String) throws {
    try Posix.mkdirs(NodePath.dirname(to))
    try TestFolder.copy(URL(fileURLWithPath: from), to: to)
  }

  static func layOut(_ files: JSONValue?, at root: String) throws {
    let object = files?.objectValue ?? JSONObject()
    for path in object.keys {
      let url = "\(root)/\(path)"
      try Posix.mkdirs(NodePath.dirname(url))
      try Posix.write(url, Data(object[path]!.stringValue!.utf8))
    }
  }

  @Test func graphsAsQuartzControl() throws {
    let cases = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("graphs.json"))).arrayValue ?? []
    #expect(cases.count >= 6)
    for entry in cases {
      let name = entry["name"]!.stringValue!
      let project = "\(scratch.path)/\(UUID().uuidString)"
      let styles = StyleSheets.stylesDirectory(project)
      try Posix.mkdirs(NodePath.dirname(styles))
      if entry["styles"] == .string("real") { try Self.copy(Self.fixtures.appendingPathComponent("real/styles").path, styles) }
      else { try Posix.mkdirs(styles); try Self.layOut(entry["styles"], at: styles) }
      let build = "\(project)/\(entry["outputDir"]?.stringValue ?? "public")"
      if entry["build"] == .string("real") { try Self.copy(Self.fixtures.appendingPathComponent("real/public").path, build) }
      else if entry["build"] != nil { try Self.layOut(entry["build"], at: build) }
      let graph = try VariableGraph.graph(project: project, themeId: entry["themeId"]?.stringValue, outputDir: entry["outputDir"]?.stringValue)
      var expected = entry["graph"]!
      // custom.scss opens with `@use "./quartzcontrol";` and its `:root` rule right after: QuartzControl
      // read both as one at-rule and lost the rule; QuartzHub ends a statement at its `;` (2026-11-23,
      // core 3's sheet has `@charset "UTF-8";body{…}`), so the stylesheet's own value is seen.
      if JSText.startsWith(name, "edges"), case .object(var graph) = expected, case .object(var vars)? = graph["vars"] {
        #expect(vars["tpl-own"] == nil, "QuartzControl's answer changed")
        vars["tpl-own"] = .object(JSONObject([("origin", .string("project")), ("light", .string("from-custom")), ("source", .string("custom.scss"))]))
        graph["vars"] = .object(vars)
        expected = .object(graph)
      }
      #expect(JSONValue.object(graph.vars) == expected["vars"], "\(name) vars")
      if JSONValue.object(graph.vars) != expected["vars"], let want = expected["vars"]?.objectValue {
        for key in want.keys where graph.vars[key] != want[key] { Issue.record("\(name): --\(key) got \(graph.vars[key].map(JSJSON.compact) ?? "nothing"), expected \(JSJSON.compact(want[key]!))"); break }
        for key in graph.vars.keys where want[key] == nil { Issue.record("\(name): --\(key) not expected"); break }
      }
      #expect(JSONValue.object(graph.dependents) == expected["dependents"], "\(name) dependents")
      #expect(graph.themeId.map { JSONValue.string($0) } == expected["themeId"], "\(name) themeId")
      #expect(.bool(graph.sources.theme) == expected["sources"]?["theme"] && .bool(graph.sources.build) == expected["sources"]?["build"], "\(name) sources")
    }
  }

  /// core 3's sheet as Quartz's minifier writes it (`@layer quartz-base;@layer obsidian{…}`, the
  /// selectors as in the Catppuccin build of 2026-11-23), beside Quartz's own unlayered `:root`.
  static let core3Sheet = "@layer quartz-base;@layer obsidian{"
    + ":root{--dark: ;--root-only:theme}"
    + ":where(body){--light:var(--background-primary);--dark:var(--text-normal);--background-primary:initial}"
    + "@charset \"UTF-8\";body{--background-primary:var(--color-base-00);--twice:first}"
    + ":where(body):is([saved-theme=light] *){--color-base-00:#fff}"
    + ":where(body):is([saved-theme=dark] *){--color-base-00:#1c1c1c}"
    + ":where(body):is([saved-theme=dark] *):not(.qt-0){--accent:padded}body.emulate-mobile{--accent:mobile}"
    + "body{--twice:second}:where(body){--background-primary:later-but-weaker}.dialog{--scoped:1}[dir=rtl]{--rtl:1}:root *{--star:1}"
    + "@media print{:where(body):is([saved-theme=dark] *){--print:1}}}"

  @Test func core3ThemeFromTheBuild() throws {
    let project = "\(scratch.path)/core3"
    try Posix.mkdirs(StyleSheets.stylesDirectory(project))
    try Posix.mkdirs("\(project)/public/static")
    try Posix.write("\(project)/public/static/resource-style-25d3dcfb.css", Data(Self.core3Sheet.utf8))
    try Posix.write("\(project)/public/index-9c1e4958.css", Data(":root{--light:#fcfcfa;--root-only:quartz;--text-normal:#222}".utf8))

    let graph = try VariableGraph.graph(project: project, themeId: "Catppuccin")
    #expect(graph.themeId == "Catppuccin" && graph.sources.theme && graph.sources.build)
    func entry(_ name: String) -> JSONValue? { graph.vars[name] }
    // What body declares is the page's, over Quartz's unlayered :root.
    #expect(entry("light") == .object(JSONObject([("origin", .string("theme")), ("light", .string("var(--background-primary)")), ("dark", .string("var(--background-primary)"))])))
    #expect(entry("dark")?["light"] == .string("var(--text-normal)"))
    // `body` beats `:where(body)`; a mode's `:is([saved-theme=…] *)` beats `body`; of equals the last.
    #expect(entry("background-primary")?["dark"] == .string("var(--color-base-00)"))
    #expect(entry("color-base-00")?["light"] == .string("#fff") && entry("color-base-00")?["dark"] == .string("#1c1c1c"))
    #expect(entry("accent") == .object(JSONObject([("origin", .string("theme")), ("dark", .string("padded"))])))
    #expect(entry("twice")?["light"] == .string("second"))
    #expect(entry("star")?["origin"] == .string("theme"))
    // Only html gets it: a layered root value, which Quartz's unlayered one beats.
    #expect(entry("root-only")?["light"] == .string("quartz") && entry("root-only")?["origin"] == .string("build"))
    #expect(entry("text-normal")?["origin"] == .string("build"))
    for name in ["scoped", "rtl", "print"] { #expect(entry(name) == nil, "\(name)") }
    #expect(graph.dependents["background-primary"] == .array([.string("light")]))

    // A theme that is off: its sheet of an earlier build is no theme.
    let off = try VariableGraph.graph(project: project)
    #expect(off.themeId == nil && !off.sources.theme)
    #expect(off.vars["light"]?["light"] == .string("#fcfcfa"))
  }

  @Test func themeSelectorsAsTheCascadeSeesThem() {
    typealias S = ThemeSelector.Specificity
    func m(_ selector: String, _ element: ThemeSelector.Element = .body, _ mode: String = "dark") -> S? { ThemeSelector.match(selector, element, mode: mode) }
    #expect(m(":where(body)") == S())
    #expect(m("body") == S(c: 1))
    #expect(m(":where(body):is([saved-theme=dark] *)") == S(b: 1))
    #expect(m(":where(body):is([saved-theme=dark] *)", .body, "light") == nil)
    #expect(m(":where(body):is([saved-theme=\"light\"] *),:is([saved-theme=light] *).ctp-latte", .body, "light") == S(b: 1))
    #expect(m(":where(body):is([saved-theme=dark] *):not(.qt-0)") == S(b: 2))
    #expect(m("body:not(:where(body):not(.qt-0))") == nil)
    #expect(m("html > body") == S(c: 2))
    #expect(m(":root") == nil && m(":root", .html) == S(b: 1))
    #expect(m(":root[saved-theme=dark]", .html) == S(b: 2) && m(":root[saved-theme=dark]", .html, "light") == nil)
    #expect(m(":root *") == S(b: 1) && m(":root *", .html) == nil)
    // Not modelled, so not counted: a state, a sibling, another attribute, a pseudo-element.
    for selector in ["body:hover", "head + body", "body[dir=ltr]", "body::before", ".theme-dark", "body .x", "", "body >"] { #expect(m(selector) == nil, "\(selector)") }
    #expect(m("body,[dir=ltr]") == S(c: 1))
  }

  @Test func catalogAsQuartzControl() throws {
    let catalog = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("catalog.json")))
    let variables = catalog["variables"]?.arrayValue ?? []
    #expect(variables.count == CssVariables.all.count)
    for (def, entry) in zip(CssVariables.all, variables) {
      #expect(.string(def.key) == entry["key"] && .string(def.group) == entry["group"] && .string(def.kind) == entry["kind"]
              && def.source.map { JSONValue.string($0) } == entry["source"], "\(def.key)")
    }
    for (callout, entry) in zip(CssVariables.callouts, catalog["callouts"]?.arrayValue ?? []) {
      #expect(.string(callout.type) == entry["type"] && .string(callout.color) == entry["color"] && .string(callout.border) == entry["border"]
              && callout.background.map { JSONValue.string($0) } == entry["bg"], "\(callout.type)")
    }
    for entry in catalog["hsl"]?.arrayValue ?? [] {
      let hsl = CssVariables.hexToHsl(entry["hex"]!.stringValue!)
      #expect(.number(hsl.h) == entry["hsl"]?["h"] && .number(hsl.s) == entry["hsl"]?["s"] && .number(hsl.l) == entry["hsl"]?["l"], "\(entry["hex"]!)")
    }
    let palette = catalog["palette"]!, typography = catalog["typography"]?.objectValue
    for entry in catalog["defaults"]?.arrayValue ?? [] {
      let def = CssVariables.definition(entry["key"]!.stringValue!)!
      let value = CssVariables.defaultValue(def, lightMode: palette["lightMode"]?.objectValue, darkMode: palette["darkMode"]?.objectValue,
                                            typography: typography, dark: entry["mode"] == .string("dark"))
      #expect(.string(value) == entry["value"], "\(def.key) \(entry["mode"]!)")
    }
    for entry in catalog["defaultsWithoutColors"]?.arrayValue ?? [] {
      let def = CssVariables.definition(entry["key"]!.stringValue!)!
      #expect(.string(CssVariables.defaultValue(def, lightMode: nil, darkMode: nil, typography: nil, dark: false)) == entry["value"], "\(def.key)")
    }
    for entry in catalog["writable"]?.arrayValue ?? [] {
      #expect(.bool(CssVariables.isWritable(entry["value"]!.stringValue!)) == entry["writable"], "\(entry["value"]!)")
    }
    for entry in catalog["calloutValues"]?.arrayValue ?? [] {
      let resolved = CssVariables.resolveCalloutValue(entry["value"]?.stringValue, lightMode: palette["lightMode"]?.objectValue,
                                                      darkMode: palette["darkMode"]?.objectValue, dark: entry["mode"] == .string("dark"))
      #expect(.string(resolved) == entry["resolved"], "\(entry["value"]!) \(entry["mode"]!)")
    }
  }
}
