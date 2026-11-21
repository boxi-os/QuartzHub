import Foundation
import Testing
@testable import QuartzHubCore

/// A template's catalogue of its variables in a stylesheet comment (docs/plan-plugin-variablen.md, Teil D).
@Suite struct TemplateVariablesTests {
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

  static let foundation = """
    :root { --tpl-fade-mask: linear-gradient(black, black); }

    /* quartz-variables
    { "groups": [ { "id": "space", "label": "Spacing", "label_de": "Abstände" } ],
      "variables": [
        { "name": "tpl-space-md", "group": "space", "kind": "length", "description": "Medium.", "description_de": "Mittel." },
        { "name": "--tpl-target", "group": "space", "kind": "length", "description": "Targets.", "description_de": "Ziele." }
      ] }
    */
    """

  @Test func readsTheCataloguesOfTheLoadedStylesheetsInLoadOrder() throws {
    let root = try project([
      "quartz/styles/custom.scss": """
        @use "./variables.scss" as *;

        @use "./quartzcontrol";

        /* quartz-variables { "groups": [ { "id": "space", "label": "Other" }, { "id": "own", "label": "Own", "label_de": "Eigene" } ],
           "variables": [ { "name": "tpl-space-md", "group": "own", "description": "Later." }, { "name": "my-gap", "group": "own" } ] } */
        /* quartz-variables { not json } */
        """,
      "quartz/styles/_quartzcontrol.scss": ManagedBlocks.managedFileHeader + """

        /* --- QuartzControl:managed:imports:start --- */
        @use "./custom/foundation";
        /* --- QuartzControl:managed:imports:end --- */
        """,
      "quartz/styles/custom/foundation.scss": Self.foundation,
      // Not loaded: its catalogue does not count.
      "quartz/styles/custom/unused.scss": "/* quartz-variables { \"variables\": [ { \"name\": \"unused\" } ] } */",
    ])
    let catalog = try #require(TemplateVariables.read(project: root))
    // The template's file loads first and gives tpl-space-md its group and text; custom.scss adds.
    #expect(catalog.variables.map(\.name) == ["tpl-space-md", "tpl-target", "my-gap"])
    #expect(catalog.variables[0].descriptionDe == "Mittel.")
    #expect(catalog.variables[0].selector == ":root")
    #expect(catalog.groups.map(\.id) == ["space", "own"])
    #expect(catalog.groups[0].labelDe == "Abstände")
    #expect(catalog.source.contains("custom/foundation.scss"))
  }

  @Test func noCatalogueIsNil() throws {
    let root = try project(["quartz/styles/custom.scss": "body { margin: 0; }\n"])
    #expect(TemplateVariables.read(project: root) == nil)
  }
}
