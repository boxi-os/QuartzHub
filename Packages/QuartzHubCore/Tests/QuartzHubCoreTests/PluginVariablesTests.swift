import Foundation
import Testing
@testable import QuartzHubCore

/// The plugins' own custom properties (docs/plan-plugin-variablen.md, A2). QuartzControl never
/// read these, so there is no golden file from it: each case is made up after what gui-test's build
/// holds (measured 2026-11-21: plugin rules inside `@layer quartz-base`, the dark one as
/// `:root[saved-theme=dark] .quartz-nav`, a component's CSS twice, the template's rules unlayered).
@Suite struct PluginVariablesTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  func project(_ files: [String: String]) throws -> String {
    let root = "\(scratch.path)/\(UUID().uuidString)"
    for (path, text) in files {
      try Posix.mkdirs(NodePath.dirname("\(root)/\(path)"))
      try Posix.write("\(root)/\(path)", Data(text.utf8))
    }
    return root
  }

  static let nav = PluginSource.string("github:boxi-os/quartz-navigations")
  static let ofm = PluginSource.string("@quartz-community/obsidian-flavored-markdown")

  static let navPackage = """
    { "name": "quartz-navigations", "quartz": { "displayName": "Navigations", "cssVariables": {
      "groups": [ { "id": "rail", "label": "Rail", "label_de": "Randmenü" }, { "id": "shape", "label": "Shape", "label_de": "Form" } ],
      "variables": [
        { "name": "quartz-nav-rail-icon-size", "selector": ".quartz-nav", "default": "1.4rem", "kind": "length", "group": "rail",
          "description": "Icons in the strip.", "description_de": "Icons in der Leiste." },
        { "name": "--quartz-nav-shadow", "selector": ".quartz-nav", "default": "0 6px 20px #0002", "defaultDark": "0 6px 24px #0009",
          "kind": "other", "group": "shape", "description": "Shadow.", "description_de": "Schatten." },
        { "name": "no selector" },
        { "name": "quartz-nav-shadow", "selector": ".twice" }
      ] } } }
    """

  static let build = """
    @layer quartz-base{.quartz-nav{--quartz-nav-rail-icon-size:1.4rem;--quartz-nav-shadow:0 6px 20px #0002;--quartz-nav-undescribed:2px}\
    :root[saved-theme=dark] .quartz-nav{--quartz-nav-shadow:0 6px 24px #0009}\
    @media (max-width:800px){.callout{--callout-color:red}}\
    .callout{--callout-color:#448aff}.callout[data-callout=warning]{--callout-color:#ff9100}\
    :root[saved-theme=dark] .callout{--callout-color:#82b1ff}\
    .orphan{--orphan-size:1px}\
    :root{--light:#fff}}\
    .quartz-nav--rail{--quartz-nav-rail-icon-size:var(--tpl-icon)}\
    .quartz-nav.nav-menue{--quartz-nav-rail-icon-size:1.5rem}\
    :root{--tpl-icon:1.1rem}
    """

  @Test func readsTheCatalogueInItsOrderWithGroupsAndDescriptions() throws {
    let root = try project([".quartz/plugins/quartz-navigations/package.json": Self.navPackage])
    let result = PluginVariables.read(project: root, plugins: [Self.nav, Self.nav])
    #expect(result.sources == (true, false))
    #expect(result.plugins.count == 1)
    let plugin = try #require(result.plugins.first)
    #expect(plugin.name == "quartz-navigations")
    #expect(plugin.displayName == "Navigations")
    #expect(plugin.described)
    #expect(plugin.groups.map(\.id) == ["rail", "shape"])
    #expect(plugin.groups[0].labelDe == "Randmenü")
    // A leading "--" goes, an entry without selector and a second one with the same name are skipped.
    #expect(plugin.variables.map(\.name) == ["quartz-nav-rail-icon-size", "quartz-nav-shadow"])
    #expect(plugin.variables[0].descriptionDe == "Icons in der Leiste.")
    #expect(plugin.variables[1].light == "0 6px 20px #0002")
    #expect(plugin.variables[1].dark == "0 6px 24px #0009")
    #expect(plugin.variables[1].selector == ".quartz-nav")
  }

  @Test func readsTheBuildForWhatNoCatalogueLists() throws {
    let root = try project([
      ".quartz/plugins/quartz-navigations/package.json": Self.navPackage,
      // An npm plugin ships its CSS as a string in dist/.
      "node_modules/@quartz-community/obsidian-flavored-markdown/package.json": #"{ "name": "x", "quartz": {} }"#,
      "node_modules/@quartz-community/obsidian-flavored-markdown/dist/index.js": #"const css = ".callout{--callout-color:#448aff}";"#,
      "public/index-abc.css": Self.build,
      // The same component CSS once more, as Quartz writes it per component.
      "public/component-1.css": "@layer quartz-base{.quartz-nav{--quartz-nav-rail-icon-size:1.4rem}}",
    ])
    let result = PluginVariables.read(project: root, plugins: [Self.nav, Self.ofm])
    #expect(result.sources == (true, true))
    let nav = try #require(result.plugins.first { $0.name == "quartz-navigations" })
    // Listed ones keep the catalogue's order; one the build adds that the package does not declare
    // is not the plugin's.
    #expect(nav.variables.map(\.name) == ["quartz-nav-rail-icon-size", "quartz-nav-shadow"])
    let icon = nav.variables[0]
    #expect(icon.setBy == [
      .init(selector: ".quartz-nav--rail", mode: "light", value: "var(--tpl-icon)"),
      .init(selector: ".quartz-nav.nav-menue", mode: "light", value: "1.5rem"),
    ])
    #expect(icon.alsoAt.isEmpty)

    let ofm = try #require(result.plugins.first { $0.name == "@quartz-community/obsidian-flavored-markdown" })
    #expect(!ofm.described)
    let color = try #require(ofm.variables.first)
    #expect(ofm.variables.map(\.name) == ["callout-color"])
    // The first light selector is where it is set; the dark value of that selector, the @media one left out.
    #expect(color.selector == ".callout")
    #expect(color.light == "#448aff")
    #expect(color.dark == "#82b1ff")
    #expect(color.alsoAt == [".callout[data-callout=warning]"])

    // Declared by no package: unattributed. Neither :root variable is a plugin's.
    #expect(Set(result.unattributed.map(\.name)) == ["quartz-nav-undescribed", "orphan-size"])
    let all = result.plugins.flatMap(\.variables).map(\.name) + result.unattributed.map(\.name)
    #expect(!all.contains("light") && !all.contains("tpl-icon"))
  }

  @Test func quartzIsAskedFirstAndPrivateHelpersStayOut() throws {
    let root = try project([
      // Quartz's own stylesheet declares it; a theme package names it too.
      "quartz/styles/callouts.scss": ".callout {\n  --callout-color: #448aff;\n}\n",
      // The transpiled cache holds a copy of everything, and the project's own stylesheets are no plugin.
      "quartz/.quartz-cache/transpiled-build.mjs": "const css = `.x{--cached-only:1px}`",
      "quartz/styles/custom.scss": ".x { --cached-only: 2px; }",
      "node_modules/@quartz-themes/core/package.json": #"{ "quartz": {} }"#,
      "node_modules/@quartz-themes/core/dist/theme.css": ".callout{--callout-color:#000}",
      "public/index-abc.css": "@layer quartz-base{.callout{--callout-color:#448aff}.x{--cached-only:1px;--_size:2px}}",
    ])
    let result = PluginVariables.read(project: root, plugins: [.string("@quartz-themes/core")])
    #expect(result.plugins.map(\.name) == ["quartz"])
    #expect(result.plugins.first?.displayName == "Quartz")
    #expect(result.plugins.first?.variables.map(\.name) == ["callout-color"])
    #expect(result.unattributed.map(\.name) == ["cached-only"])
  }

  @Test func declaredNamesAreReadAsBytes() throws {
    let root = try project([
      "dist/index.js": #"a="--one:1;--two :2;x--not:3;--three\#t:4;var(--used)";--"#,
      "dist/skip.txt": "--wrong-extension:1",
    ])
    #expect(PluginVariables.declaredNames(root) == ["one", "two", "three"])
  }

  @Test func scopedModeStripsTheModePrefix() {
    #expect(PluginVariables.scopedMode(":root[saved-theme=dark] .quartz-nav") == (".quartz-nav", "dark"))
    #expect(PluginVariables.scopedMode(#"html[saved-theme="light"]  .x .y"#) == (".x .y", "light"))
    #expect(PluginVariables.scopedMode(#"[saved-theme='dark'] .x"#) == (".x", "dark"))
    #expect(PluginVariables.scopedMode(".quartz-nav") == (".quartz-nav", "light"))
    // A list keeps its text: no mode can be told for all of its parts.
    #expect(PluginVariables.scopedMode(":root[saved-theme=dark] .a, .b") == (":root[saved-theme=dark] .a, .b", "light"))
  }

  @Test func withoutCatalogueOrBuildThereIsNothing() throws {
    let root = try project([".quartz/plugins/quartz-navigations/package.json": #"{ "quartz": {} }"#])
    let result = PluginVariables.read(project: root, plugins: [Self.nav])
    #expect(result.plugins.isEmpty && result.unattributed.isEmpty)
    #expect(result.sources == (false, false))
  }
}
