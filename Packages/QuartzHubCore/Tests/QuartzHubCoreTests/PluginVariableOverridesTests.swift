import Foundation
import Testing
@testable import QuartzHubCore

/// The `plugin-vars` block (docs/plan-plugin-variablen.md, B1). QuartzControl has no such block, so
/// the cases are made up: the three kinds of rule of `css-vars` at a plugin's selector, and where
/// the writer puts the block.
@Suite struct PluginVariableOverridesTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  typealias O = PluginVariableOverride

  @Test func rendersPerSelectorTheThreeKindsOfRule() {
    let body = PluginVariableOverrides.render([
      O(selector: ".quartz-nav", key: "quartz-nav-rail-icon-size", light: "1.5rem"),
      O(selector: ".quartz-form", key: "quartz-forms-error", light: "#b00", dark: "#f88"),
      O(selector: ".quartz-nav", key: "quartz-nav-color-icon", light: "#333", lightOnly: true),
      O(selector: "  .quartz-nav ", key: "quartz-nav-shadow", light: "none", dark: "0 0 4px #000"),
      // An empty value is no declaration.
      O(selector: ".quartz-nav", key: "quartz-nav-gap", light: " "),
    ])
    #expect(body == """
      .quartz-nav {
        --quartz-nav-rail-icon-size: 1.5rem;
        --quartz-nav-shadow: none;
      }

      :root[saved-theme="dark"] .quartz-nav {
        --quartz-nav-shadow: 0 0 4px #000;
      }

      :root:not([saved-theme="dark"]) .quartz-nav {
        --quartz-nav-color-icon: #333;
      }

      .quartz-form {
        --quartz-forms-error: #b00;
      }

      :root[saved-theme="dark"] .quartz-form {
        --quartz-forms-error: #f88;
      }
      """)
  }

  @Test func readsWhatItWritesAndWhatTheBrowserWouldApply() {
    let overrides = [
      O(selector: ".quartz-nav", key: "a", light: "1px"),
      O(selector: ".quartz-nav", key: "b", light: "red", dark: "pink"),
      O(selector: ".quartz-nav", key: "c", light: "#333", lightOnly: true),
      O(selector: ".callout[data-callout=warning]", key: "callout-color", light: "255, 0, 0"),
    ]
    #expect(PluginVariableOverrides.parse(PluginVariableOverrides.render(overrides)) == overrides)
    // Unquoted, extra spaces, a comment, a later rule winning; a light-only rule beside a plain one
    // means light only in light, the plain value in dark.
    let read = PluginVariableOverrides.parse("""
      /* note */ .quartz-nav   .x { --a: 1px; }
      :root[saved-theme=dark]  .quartz-nav .x { --a: 2px; }
      .quartz-nav .x { --a: 3px; }
      :root:not([saved-theme='dark']) .y { --b: red; }
      .y { --b: blue; }
      @media (max-width: 800px) { .y { --b: green; } }
      """)
    #expect(read == [
      O(selector: ".quartz-nav .x", key: "a", light: "3px", dark: "2px"),
      O(selector: ".y", key: "b", light: "red", dark: "blue"),
    ])
  }

  @Test func leavesOutWhatWouldNotStayOneDeclaration() {
    let body = PluginVariableOverrides.render([
      O(selector: ".a", key: "ok", light: "1px"),
      O(selector: ".a", key: "semicolon", light: "1px; color: red"),
      O(selector: ".a", key: "brace", light: "1px } body {"),
      O(selector: ".a", key: "comment", light: "1px /* x"),
      O(selector: ".a", key: "bad key!", light: "1px"),
      O(selector: ".a { } .b", key: "x", light: "1px"),
      O(selector: ".a, .b", key: "x", light: "1px"),
      O(selector: #":root[saved-theme="dark"] .a"#, key: "x", light: "1px"),
    ])
    #expect(body == ".a {\n  --ok: 1px;\n}")
  }

  func layOut(_ files: [String: String]) throws -> String {
    let root = "\(scratch.path)/\(UUID().uuidString)"
    for (path, text) in files {
      try Posix.mkdirs(NodePath.dirname("\(root)/\(path)"))
      try Posix.write("\(root)/\(path)", Data(text.utf8))
    }
    return root
  }

  func read(_ root: String, _ path: String) throws -> String { try StyleSheets.readText("\(root)/\(path)") }

  @Test func comesLastInTheManagedFileAndStaysThere() async throws {
    let root = try layOut([
      "quartz/styles/custom.scss": "@use \"./variables.scss\" as *;\n\n\(ManagedBlocks.managedUseLine)\n\nbody { margin: 0; }\n",
      "quartz/styles/_quartzcontrol.scss": ManagedBlocks.managedFileHeader,
    ])
    try await StyleSheets.savePluginVariableOverrides([O(selector: ".quartz-nav", key: "quartz-nav-gap", light: "2px")], project: root)
    try await StyleSheets.saveVariableOverrides([VariableOverride(key: "secondary", light: "#123456")], project: root)
    let managed = try read(root, "quartz/styles/_quartzcontrol.scss")
    let cssVars = try #require(managed.range(of: "QuartzControl:managed:css-vars:start"))
    let pluginVars = try #require(managed.range(of: "QuartzControl:managed:plugin-vars:start"))
    #expect(cssVars.lowerBound < pluginVars.lowerBound)
    #expect(try StyleSheets.pluginVariableOverrides(project: root) == [O(selector: ".quartz-nav", key: "quartz-nav-gap", light: "2px")])
    // The css-vars reader does not take the plugin's rule for a :root value.
    #expect(try StyleSheets.variableOverrides(project: root).map(\.key) == ["secondary"])
    #expect(!(try read(root, "quartz/styles/custom.scss")).contains("plugin-vars"))

    try await StyleSheets.savePluginVariableOverrides([], project: root)
    #expect(!(try read(root, "quartz/styles/_quartzcontrol.scss")).contains("plugin-vars"))
    #expect(try StyleSheets.variableOverrides(project: root).map(\.key) == ["secondary"])
  }

  @Test func inAProjectOf10TheBlockStaysInCustomScss() async throws {
    let root = try layOut(["quartz/styles/custom.scss": "@use \"./variables.scss\" as *;\n\nbody { margin: 0; }\n"])
    try await StyleSheets.savePluginVariableOverrides([O(selector: ".quartz-form", key: "quartz-forms-gap", light: "2rem")], project: root)
    let custom = try read(root, "quartz/styles/custom.scss")
    #expect(custom.contains("QuartzControl:managed:plugin-vars:start"))
    #expect(custom.contains(".quartz-form {\n  --quartz-forms-gap: 2rem;\n}"))
    #expect(!FileManager.default.fileExists(atPath: "\(root)/quartz/styles/_quartzcontrol.scss"))
    // A template made from it does not carry the block as the user's own text.
    #expect(!TemplatePackage.stripAllManaged(custom).contains("quartz-forms-gap"))
  }
}
