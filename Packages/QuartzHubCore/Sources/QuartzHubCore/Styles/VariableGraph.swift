import Foundation

/// The variable table and its dependency graph for the Styles page's Variables tab: a port of
/// `variableGraphService.ts`. Every custom property in play, its light and dark value, where it
/// came from, and which other variables reference it. A value like `var(--bg)` is kept verbatim:
/// the page needs the chain, not the end of it.
///
/// Two optional sources, and the answer says which one answered: an installed theme's `theme.json`
/// (each mode's compiled CSS, whose first rule is the theme's whole variable table) and the CSS of
/// the last build. Then the project's own stylesheets: an unlayered declaration beats every layered
/// one whatever its selector, so a stylesheet's `:root` replaces Quartz's value in both modes.
///
/// Read with a brace counter that knows strings and comments, not a CSS parser, as QuartzControl
/// reads its own generated CSS; the cases it learnt (a selector with `{{` in a string, minified rules
/// without the last semicolon, a data URL with `;` inside) are cases here.
public enum VariableGraph {
  public struct Graph: Equatable, Sendable {
    /// Name → `{ origin, light?, dark?, source? }`, in QuartzControl's key order.
    public var vars: JSONObject
    /// Name → the variables that reference it, sorted.
    public var dependents: JSONObject
    public var themeId: String?
    public var sources: (theme: Bool, build: Bool)

    public static func == (a: Graph, b: Graph) -> Bool {
      a.vars == b.vars && a.dependents == b.dependents && a.themeId == b.themeId && a.sources == b.sources
    }
  }

  struct Context {
    var layered = false
    var conditional = false
  }

  /// The first rule of a compiled mode blob, the `:root` block.
  static func firstRuleBody(_ css: String) -> String {
    guard let open = JSText.indexOf(css, "{"), let close = JSText.indexOf(css, "}", from: open) else { return "" }
    return JSText.slice(css, open + 1, close)
  }

  /// Skips a string from its opening quote (to the closing one or the end of the line, `\` escaping
  /// the next unit) or a comment; answers the index of its last unit.
  static func skip(_ units: [UInt16], _ i: Int, _ text: String) -> Int? {
    let ch = units[i]
    if ch == 0x22 || ch == 0x27 {
      var j = i + 1
      while j < units.count && units[j] != ch && units[j] != 0x0A {
        if units[j] == 0x5C { j += 1 }
        j += 1
      }
      return j
    }
    if ch == 0x2F && i + 1 < units.count && units[i + 1] == 0x2A {
      guard let end = JSText.indexOf(text, "*/", from: i + 2) else { return units.count }
      return end + 1
    }
    return nil
  }

  /// A declaration ends at a `;` (or `}`) outside strings, parentheses and comments.
  static func splitDeclarations(_ body: String) -> [String] {
    let units = Array(body.utf16)
    var out: [String] = []
    var depth = 0, start = 0, i = 0
    while i < units.count {
      if let end = skip(units, i, body) { i = end + 1; continue }
      let ch = units[i]
      if ch == 0x28 { depth += 1 }
      else if ch == 0x29 { depth = max(0, depth - 1) }
      else if (ch == 0x3B || ch == 0x7D) && depth == 0 {
        out.append(JSText.slice(body, start, i))
        start = i + 1
      }
      i += 1
    }
    out.append(JSText.slice(body, start))
    return out
  }

  /// `--name: value` pairs in order of first appearance, a later value replacing an earlier one in
  /// place (a JavaScript Map). Values wrapped over lines become one line.
  static func declarations(_ body: String) -> [(String, String)] {
    var out: [(String, String)] = []
    for declaration in splitDeclarations(body) {
      let clean = JSText.replaceAll(declaration, #"/\*[\s\S]*?\*/"#, with: "")
      guard let match = JSText.firstMatch(clean, "\\A[\(JSText.space)]*--([A-Za-z0-9_-]+)[\(JSText.space)]*:([\\s\\S]+)\\z"),
            let name = match.groups[1], let raw = match.groups[2] else { continue }
      let value = JSText.replaceAll(JS.trim(raw), "[\(JSText.space)]+", with: " ")
      if let index = out.firstIndex(where: { $0.0 == name }) { out[index].1 = value } else { out.append((name, value)) }
    }
    return out
  }

  /// Every top-level rule with its selector, into `@layer` and other block at-rules (which mark
  /// what is inside as layered or conditional). Braces in strings and comments do not count; a
  /// stray closing brace stops the walk rather than mis-attribute the rest.
  static func eachRule(_ css: String, _ context: Context = Context(), _ visit: (String, String, Context) -> Void) {
    let units = Array(css.utf16)
    var depth = 0, start = 0, selectorStart = 0, i = 0
    while i < units.count {
      if let end = skip(units, i, css) { i = end + 1; continue }
      let ch = units[i]
      if ch == 0x7B {
        if depth == 0 {
          selectorStart = start
          start = i + 1
        }
        depth += 1
      } else if ch == 0x7D {
        depth -= 1
        if depth == 0 {
          let selector = JS.trim(JSText.replaceAll(JSText.slice(css, selectorStart, start - 1), #"/\*[\s\S]*?\*/"#, with: ""))
          let body = JSText.slice(css, start, i)
          if JSText.startsWith(selector, "@") {
            let layer = JSText.test(selector, #"\A@layer(?![A-Za-z0-9_])"#)
            eachRule(body, Context(layered: context.layered || layer, conditional: context.conditional || !layer), visit)
          } else {
            visit(selector, body, context)
          }
          start = i + 1
        }
        if depth < 0 { return }
      }
      i += 1
    }
  }

  static let savedTheme = #"\[saved-theme=["']?(dark|light)["']?\]"#

  /// The mode a global root-level selector sets, or nil for a scoped one: the mode attribute sits on
  /// the root element, so removing it has to leave a bare root behind.
  static func rootMode(_ selector: String) -> String? {
    for part in JSText.split(selector, ",") {
      let normalized = JSText.replaceAll(part, "[\(JSText.space)]+", with: "")
      let mode = JSText.firstMatch(normalized, savedTheme)?.groups[1] ?? "light"
      let stripped = JSText.replaceAll(normalized, savedTheme, with: "")
      if JSText.test(stripped, #"\A(:root|html|body)+\z"#) { return mode }
    }
    return nil
  }

  struct ProjectDeclaration {
    var source: String
    var light: String?
    var dark: String?
  }

  /// Which loaded stylesheet of the project declares a name in a global `:root` rule, the page's
  /// own block taken out first; the file whose rules come last on the site is asked first.
  static func projectDeclarations(_ project: URL) throws -> [(String, ProjectDeclaration)] {
    var out: [(String, ProjectDeclaration)] = []
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project).path)
    for file in try StyleSheets.loadedStylesheetsLastFirst(project: project) {
      let text = ManagedBlocks.strip((try? StyleSheets.readText(file)) ?? "", "css-vars")
      // `//` comments go: an apostrophe in one would open a string for the brace counter.
      let css = JSText.replaceAll(text, "(\\A|[\(JSText.space);{}])//[^\\n]*", template: "$1")
      let source = NodePath.relative(styles, NodePath.normalize(file.path))
      eachRule(css) { selector, body, context in
        guard !context.conditional, let mode = rootMode(selector) else { return }
        for (name, value) in declarations(body) {
          let index = out.firstIndex { $0.0 == name } ?? { out.append((name, ProjectDeclaration(source: source))); return out.count - 1 }()
          if mode == "light" { out[index].1.light = out[index].1.light ?? value } else { out[index].1.dark = out[index].1.dark ?? value }
        }
      }
    }
    return out
  }

  static let ignoredDirectories: Set<String> = ["node_modules", ".git", "dist", ".changeset"]

  static func cssFiles(_ dir: String, _ depth: Int = 0) -> [String] {
    guard depth <= 6 else { return [] }
    var out: [String] = []
    for entry in LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: dir)) where !ignoredDirectories.contains(entry.name) {
      let full = NodePath.join(dir, entry.name)
      if entry.kind == .directory { out += cssFiles(full, depth + 1) } else if JSText.endsWith(entry.name, ".css") { out.append(full) }
    }
    return out
  }

  public static func graph(project: URL, themeId: String? = nil, outputDir: String? = nil) throws -> Graph {
    var vars = JSONObject()
    var dependents: [(String, [String])] = []
    func addDependent(_ target: String, _ name: String) {
      if let index = dependents.firstIndex(where: { $0.0 == target }) {
        if !dependents[index].1.contains(name) { dependents[index].1.append(name) }
      } else {
        dependents.append((target, [name]))
      }
    }
    // theme wins over build for the same name and mode, but a build-only mode still fills a gap; an
    // unlayered declaration wins over both (the theme's CSS is layered too).
    func note(_ name: String, _ mode: String, _ value: String, _ origin: String, unlayered: Bool = false) {
      let existing = vars[name]?.objectValue
      if !unlayered, let existing, existing["origin"] == .string("theme"), origin == "build", existing[mode] != nil { return }
      var entry = existing ?? JSONObject([("origin", .string(origin))])
      entry[mode] = .string(value)
      if origin == "theme" || unlayered { entry["origin"] = .string(origin) }
      vars[name] = .object(entry)
      for match in JSText.matches(value, #"var\(["# + JSText.space + #"]*--([A-Za-z0-9_-]+)"#) {
        let target = match.groups[1]!
        if target != name { addDependent(target, name) }
      }
    }

    var theme: JSONValue?
    if let themeId {
      let path = NodePath.join(project.path, "node_modules/@quartz-themes", themeId, "theme.json")
      // `JSON.parse` of the file, and only a truthy one is a theme (`null`, `0` or `""` are none).
      if let data = FileManager.default.contents(atPath: path), let parsed = try? JSJSON.parse(data), JS.truthy(parsed) { theme = parsed }
    }
    if let theme {
      for mode in ["light", "dark"] {
        guard case .string(let base)? = theme[safe: mode]?[safe: "base"] else { continue }
        for (name, value) in declarations(firstRuleBody(base)) { note(name, mode, value, "theme") }
      }
      if case .object(let links)? = theme[safe: "brokenVarLinks"] {
        for target in links.keys {
          let bare = JSText.replaceAll(target, #"\A--"#, with: "")
          for dep in links[target]?.arrayValue ?? [] { addDependent(bare, JSText.replaceAll(JS.string(dep), #"\A--"#, with: "")) }
        }
      }
    }

    let own = Set(try StyleSheets.variableOverrides(project: project).map(\.key))
    let buildDir = BuildOutputGuard.buildDirectory(project: project.path, outputDir: outputDir)
    let hasBuild = FileManager.default.fileExists(atPath: buildDir)
    var unlayered: [(String, (light: String?, dark: String?))] = []
    func setUnlayered(_ name: String, light: String?? = .none, dark: String?? = .none, replace: Bool = false) {
      if let index = unlayered.firstIndex(where: { $0.0 == name }) {
        if replace { unlayered[index].1 = (light ?? nil, dark ?? nil); return }
        if let light { unlayered[index].1.light = light }
        if let dark { unlayered[index].1.dark = dark }
      } else {
        unlayered.append((name, (light ?? nil, dark ?? nil)))
      }
    }
    if hasBuild {
      // A name the page sets is skipped when unlayered: that is where the page's own rule lands.
      for file in cssFiles(buildDir).prefix(50) {
        let content = (try? StyleSheets.readText(URL(fileURLWithPath: file))) ?? ""
        eachRule(content) { selector, body, context in
          // A :root inside @media is the exception to a base value, not one.
          guard !context.conditional, let mode = rootMode(selector) else { return }
          for (name, value) in declarations(body) {
            if context.layered { note(name, mode, value, "build") }
            else if !own.contains(name) { if mode == "light" { setUnlayered(name, light: .some(value)) } else { setUnlayered(name, dark: .some(value)) } }
          }
        }
      }
    }
    // A name the page sets too keeps the stylesheet's own text as its value (its compiled rule was
    // skipped above); needs no build.
    let declared = try projectDeclarations(project)
    for (name, declaration) in declared where own.contains(name) { setUnlayered(name, light: .some(declaration.light), dark: .some(declaration.dark), replace: true) }
    for (name, values) in unlayered {
      if let light = values.light { note(name, "light", light, "build", unlayered: true) }
      // Without a dark rule of its own, dark mode gets the light one, over any layered dark value.
      let dark = values.dark ?? (vars[name]?[safe: "dark"] != nil ? values.light : nil)
      if let dark { note(name, "dark", dark, "build", unlayered: true) }
    }
    for (name, declaration) in declared {
      guard var entry = vars[name]?.objectValue, entry["origin"] == .string("build") else { continue }
      entry["origin"] = .string("project")
      entry["source"] = .string(declaration.source)
      vars[name] = .object(entry)
    }

    var dependentsObject = JSONObject()
    for (target, names) in dependents {
      dependentsObject[target] = .array(names.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.map { .string($0) })
    }
    return Graph(vars: vars, dependents: dependentsObject, themeId: theme != nil ? themeId : nil, sources: (theme != nil, hasBuild))
  }
}
