import Foundation

/// One plugin variable the Styles page sets, at the plugin's own selector.
public struct PluginVariableOverride: Equatable, Sendable {
  /// The plugin's selector, as its catalogue or its build names it (`.quartz-nav`).
  public var selector: String
  public var key: String
  public var light: String
  /// nil: no dark value of its own.
  public var dark: String?
  /// Only the light mode gets `light`; the dark mode keeps the plugin's value.
  public var lightOnly: Bool

  public init(selector: String, key: String, light: String, dark: String? = nil, lightOnly: Bool = false) {
    self.selector = selector
    self.key = key
    self.light = light
    self.dark = dark
    self.lightOnly = lightOnly
  }
}

/// The `plugin-vars` block (docs/plan-plugin-variablen.md, B1): QuartzHub's extension of 1.3's
/// stylesheet format, decided 2026-11-21. The three kinds of rule of `css-vars`, each prefixed to
/// the plugin's selector:
///
/// ```scss
/// .quartz-nav {
///   --quartz-nav-rail-icon-size: 1.5rem;
/// }
///
/// :root[saved-theme="dark"] .quartz-nav { … }
/// :root:not([saved-theme="dark"]) .quartz-nav { … }
/// ```
///
/// Not inside `css-vars`: its reader takes every declaration there as a `:root` value. QuartzControl
/// 1.3 keeps the block as text (its `writeManagedBlocks` strips and re-adds only its four), so it
/// survives a write of 1.3 and then stands before `css-vars`, which changes nothing (other selectors).
/// The block is unlayered and comes after the template's stylesheets, so it wins against a plugin's
/// rule (inside `@layer quartz-base`) and against a project rule of the same specificity.
public enum PluginVariableOverrides {
  public static let blockId = "plugin-vars"
  static let darkPrefix = #":root[saved-theme="dark"]"#
  static let lightOnlyPrefix = #":root:not([saved-theme="dark"])"#
  static let darkHead = #"\A:root\[saved-theme=["']?dark["']?\]["# + JSText.space + #"]+"#
  static let lightOnlyHead = #"\A:root:not\(\[saved-theme=["']?dark["']?\]\)["# + JSText.space + #"]+"#

  /// A selector that can stand in a rule as given: no braces, no semicolon, no comment, no line
  /// break, nothing that ends or opens a block. Lists (`,`) are refused too: a mode prefix would
  /// reach only their first part.
  public static func isSafeSelector(_ selector: String) -> Bool {
    let trimmed = JS.trim(selector)
    return !trimmed.isEmpty && trimmed.utf16.count <= 512 && !JSText.test(trimmed, #"[{};,\n\r\\]|/\*|\*/|//|\A:root\[saved-theme|\A:root:not"#)
  }

  /// A value that stays one declaration: no `;`, braces, comments or line breaks, nothing after a
  /// `!` but `important`.
  public static func isSafeValue(_ value: String) -> Bool {
    let trimmed = JS.trim(value)
    return !trimmed.isEmpty && trimmed.utf16.count <= 2048 && !JSText.test(trimmed, #"[{};\n\r\\]|/\*|\*/"#)
  }

  public static func isSafeKey(_ key: String) -> Bool { JSText.test(key, #"\A[A-Za-z0-9_-]+\z"#) }

  /// The rules of the block, the later one winning per selector, kind and variable, as the browser
  /// applies them.
  public static func parse(_ body: String) -> [PluginVariableOverride] {
    let css = JSText.replaceAll(body, #"/\*[\s\S]*?\*/"#, with: "")
    var order: [(String, String)] = []
    var light: [String: String] = [:], dark: [String: String] = [:], only: [String: String] = [:]
    func id(_ selector: String, _ key: String) -> String { "\(selector)\u{0}\(key)" }
    VariableGraph.eachRule(css) { rawSelector, ruleBody, context in
      guard !context.conditional else { return }
      let normalized = JSText.replaceAll(JS.trim(rawSelector), "[\(JSText.space)]+", with: " ")
      var selector = normalized
      var kind = "both"
      if let match = JSText.firstMatch(normalized, darkHead) {
        kind = "dark"
        selector = JS.trim(JSText.slice(normalized, match.end))
      } else if let match = JSText.firstMatch(normalized, lightOnlyHead) {
        kind = "only"
        selector = JS.trim(JSText.slice(normalized, match.end))
      }
      guard isSafeSelector(selector) else { return }
      for (key, value) in VariableGraph.declarations(ruleBody) {
        let k = id(selector, key)
        if !order.contains(where: { id($0.0, $0.1) == k }) { order.append((selector, key)) }
        switch kind {
        case "dark": dark[k] = value
        case "only": only[k] = value
        default: light[k] = value
        }
      }
    }
    return order.map { selector, key in
      let k = id(selector, key)
      guard let lightOnly = only[k] else {
        return PluginVariableOverride(selector: selector, key: key, light: light[k] ?? "", dark: dark[k])
      }
      // As in `css-vars`: the light-only rule wins in light mode; a plain value beside it is what
      // dark mode gets, unless a dark rule says otherwise.
      if let darkValue = dark[k] ?? light[k] { return PluginVariableOverride(selector: selector, key: key, light: lightOnly, dark: darkValue) }
      return PluginVariableOverride(selector: selector, key: key, light: lightOnly, lightOnly: true)
    }
  }

  static func hasDark(_ o: PluginVariableOverride) -> Bool { o.dark.map { !JS.trim($0).isEmpty } ?? false }
  static func isLightOnly(_ o: PluginVariableOverride) -> Bool { o.lightOnly && !hasDark(o) }

  /// The block's body: per selector in order of first appearance its rule for both modes, its dark
  /// rule and its light-only rule. An empty half is no declaration; anything that would not stay one
  /// declaration (an unsafe selector, key or value) is left out rather than written broken.
  public static func render(_ overrides: [PluginVariableOverride]) -> String {
    let usable = overrides.filter { isSafeSelector($0.selector) && isSafeKey($0.key) }.map { o -> PluginVariableOverride in
      var o = o
      o.selector = JSText.replaceAll(JS.trim(o.selector), "[\(JSText.space)]+", with: " ")
      return o
    }
    var selectors: [String] = []
    for o in usable where !selectors.contains(o.selector) { selectors.append(o.selector) }
    var rules: [String] = []
    for selector in selectors {
      let mine = usable.filter { $0.selector == selector }
      func rule(_ head: String, _ list: [PluginVariableOverride], _ value: (PluginVariableOverride) -> String) {
        let lines = list.map { ($0.key, JS.trim(value($0))) }.filter { isSafeValue($0.1) }.map { "  --\($0.0): \($0.1);" }
        if !lines.isEmpty { rules.append("\(head) {\n\(lines.joined(separator: "\n"))\n}") }
      }
      rule(selector, mine.filter { !isLightOnly($0) }) { $0.light }
      rule("\(darkPrefix) \(selector)", mine.filter(hasDark)) { $0.dark ?? "" }
      rule("\(lightOnlyPrefix) \(selector)", mine.filter(isLightOnly)) { $0.light }
    }
    return rules.joined(separator: "\n\n")
  }
}

extension StyleSheets {
  public static func pluginVariableOverrides(project: String) throws -> [PluginVariableOverride] {
    managedBody(try readSources(project: project), PluginVariableOverrides.blockId).map(PluginVariableOverrides.parse) ?? []
  }

  /// An empty list (or one of emptied values) clears the block.
  public static func savePluginVariableOverrides(_ overrides: [PluginVariableOverride], project: String) async throws {
    try await ProjectLock.styles.run(project) {
      let body = PluginVariableOverrides.render(overrides)
      let changes: [String: String?] = [PluginVariableOverrides.blockId: body.isEmpty ? nil : body]
      try writeManagedBlocksNow(changes, project: project)
    }
  }
}
