import Foundation

/// A template's description of its own variables (docs/plan-plugin-variablen.md, Teil D): the
/// catalogue of `quartz.cssVariables` (`PluginVariables.catalog`) in a comment of one of the
/// project's stylesheets, so it travels with the template's files and needs no new format in a
/// `.qtpl` or in `.quartz-gui/`:
///
/// ```scss
/// /* quartz-variables
/// { "groups": [...], "variables": [ { "name": "tpl-space-md", "group": "space", "kind": "length",
///   "description": "...", "description_de": "..." } ] }
/// */
/// ```
///
/// The variables are global (`:root`, the selector is left out); their values stay where they are
/// (the `css-vars` block, the template's stylesheets) and are read and changed as before. The
/// catalogue only gives them groups, an order and an explanation.
public enum TemplateVariables {
  public struct Catalog: Equatable, Sendable {
    public var groups: [PluginVariables.Group]
    public var variables: [PluginVariables.Variable]
    /// The stylesheet it was read from, relative to `quartz/styles`.
    public var source: String
  }

  static let marker = #"/\*[\#(JSText.space)]*quartz-variables[\#(JSText.space)]+([\s\S]*?)\*/"#
  static let maxCatalogBytes = 512 * 1024

  /// Every catalogue comment in a text, in order.
  static func catalogs(in text: String) -> [(groups: [PluginVariables.Group], variables: [PluginVariables.Variable])] {
    JSText.matches(text, marker).compactMap { match in
      guard let json = match.groups[1], json.utf8.count <= maxCatalogBytes, let value = try? JSJSON.parse(Data(json.utf8)) else { return nil }
      return PluginVariables.catalog(value, defaultSelector: ":root")
    }
  }

  /// The catalogues of the stylesheets the site loads, merged: the first file in load order gives
  /// a variable its description, groups keep their first label. Nil when no stylesheet has one.
  public static func read(project: String) -> Catalog? {
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project))
    var groups: [PluginVariables.Group] = []
    var variables: [PluginVariables.Variable] = []
    var sources: [String] = []
    let files = ((try? StyleSheets.loadedStylesheetsLastFirst(project: project)) ?? []).reversed()
    for file in files {
      guard let text = try? StyleSheets.readText(file), JSText.includes(text, "quartz-variables") else { continue }
      for found in catalogs(in: text) {
        for group in found.groups where !groups.contains(where: { $0.id == group.id }) { groups.append(group) }
        for variable in found.variables where !variables.contains(where: { $0.name == variable.name }) { variables.append(variable) }
        let source = NodePath.relative(styles, NodePath.normalize(file))
        if !sources.contains(source) { sources.append(source) }
      }
    }
    return variables.isEmpty ? nil : Catalog(groups: groups, variables: variables, source: sources.joined(separator: ", "))
  }
}
