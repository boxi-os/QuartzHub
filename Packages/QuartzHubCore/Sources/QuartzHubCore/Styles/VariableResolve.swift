import Foundation

/// How the Styles page reads a variable: what it is today, what it would be without the user's
/// override, the derivation chain behind it, the literal that chain ends on, where its value comes
/// from, whether it is a colour. A port of `src/routes/Styles/variableGraph.ts` and `swatch.ts`,
/// measured against QuartzControl's own code in Chrome (`scripts/variable-resolve-golden.mjs`).
///
/// Text is cut and searched in UTF-16, as JavaScript does.
public enum VariableResolve {
  /// One variable's override as the page holds it. An empty `dark` is "no dark declaration"; with
  /// `lightOnly` the light value applies in light mode only and dark keeps the theme's value.
  public struct Override: Equatable, Sendable {
    public var light: String
    public var dark: String
    public var lightOnly: Bool

    public init(light: String, dark: String = "", lightOnly: Bool = false) {
      self.light = light
      self.dark = dark
      self.lightOnly = lightOnly
    }
  }

  public enum Mode: String, Sendable, CaseIterable { case light, dark }

  public struct Context: Sendable {
    /// The graph's `vars`: name → `{ origin, light?, dark? }`.
    public var vars: JSONObject?
    /// In the page's order: the keys of an object in JavaScript keep it, and the list of known
    /// variables follows it.
    public var overrideList: [(key: String, value: Override)]
    public let overrides: [String: Override]
    /// `theme.colors` of the config: `lightMode`, `darkMode`.
    public var colors: JSONObject
    public var typography: JSONObject?

    public init(vars: JSONObject?, overrides: [(key: String, value: Override)], colors: JSONObject, typography: JSONObject?) {
      self.vars = vars
      overrideList = overrides
      self.overrides = Dictionary(overrides.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
      self.colors = colors
      self.typography = typography
    }
  }

  public struct Step: Equatable, Sendable {
    public var key: String
    public var value: String
  }

  // MARK: Aliases

  /// `^\s*--([\w-]+)\s*(?:,|$)` on the inside of a `var()`.
  static let varHead = "\\A[\(JSText.space)]*--([\(JSText.word)-]+)[\(JSText.space)]*(?:,|\\z)"

  /// A value that is nothing but one `var()`: its target and fallback. Counted by parentheses,
  /// because a fallback is routinely another `var()`.
  public static func pureAlias(_ value: String) -> (target: String, fallback: String?)? {
    let v = JS.trim(value)
    guard JSText.startsWith(v, "var("), JSText.endsWith(v, ")") else { return nil }
    let units = Array(v.utf16)
    var depth = 0
    for (i, unit) in units.enumerated() {
      if unit == 0x28 { depth += 1 } else if unit == 0x29 {
        depth -= 1
        if depth == 0 && i != units.count - 1 { return nil }
      }
    }
    let inner = JSText.slice(v, 4, units.count - 1)
    guard let head = JSText.firstMatch(inner, varHead), let target = head.groups[1] else { return nil }
    guard let comma = JSText.indexOf(inner, ",") else { return (target, nil) }
    return (target, JS.trim(JSText.slice(inner, comma + 1)))
  }

  /// Every name a value references, once each, in order.
  public static func referencedVariables(_ value: String) -> [String] {
    var seen: [String] = []
    for match in JSText.matches(value, "var\\([\(JSText.space)]*--([\(JSText.word)-]+)") {
      if let name = match.groups[1], !seen.contains(name) { seen.append(name) }
    }
    return seen
  }

  // MARK: Values

  /// JavaScript's `info[mode] ?? info.light ?? info.dark`, then "is it truthy".
  static func graphValue(_ key: String, _ mode: Mode, _ ctx: Context) -> String? {
    guard case .object(let info)? = ctx.vars?[key] else { return nil }
    let candidates = [info[mode.rawValue], info["light"], info["dark"]]
    guard let first = candidates.first(where: { $0 != nil && $0 != .null }), let value = first else { return nil }
    switch value {
    case .string(let text): return text.isEmpty ? nil : text
    default: return JS.truthy(value) ? JS.string(value) : nil
    }
  }

  static func catalogValue(_ key: String, _ mode: Mode, _ ctx: Context) -> String? {
    guard let def = CssVariables.definition(key) else { return nil }
    let value = CssVariables.defaultValue(def, lightMode: ctx.colors["lightMode"]?.objectValue, darkMode: ctx.colors["darkMode"]?.objectValue,
                                          typography: ctx.typography, dark: mode == .dark)
    return value.isEmpty ? nil : value
  }

  /// What the variable is today, one step deep: the override, then the theme or the build, then
  /// the catalogue's derivation from the classic colours.
  public static func effectiveValue(_ key: String, _ mode: Mode, _ ctx: Context) -> String? {
    if let override = ctx.overrides[key] {
      let value = mode == .dark ? (override.dark.isEmpty ? (override.lightOnly ? "" : override.light) : override.dark) : override.light
      if !value.isEmpty { return value }
    }
    return baseValue(key, mode, ctx)
  }

  /// What the variable would be without the user's override: the yardstick a draft is compared
  /// against.
  public static func baseValue(_ key: String, _ mode: Mode, _ ctx: Context) -> String? {
    graphValue(key, mode, ctx) ?? catalogValue(key, mode, ctx)
  }

  /// The chain behind a variable, following pure aliases only; stops on a cycle, after 20 steps,
  /// or where nothing more is known. An undeclared target continues through its fallback.
  public static func resolveChain(_ key: String, _ mode: Mode, _ ctx: Context) -> [Step] {
    var steps: [Step] = []
    var seen: Set<String> = [key]
    var currentKey = key
    var value = effectiveValue(key, mode, ctx)
    while let current = value, steps.count < 20 {
      steps.append(Step(key: currentKey, value: current))
      guard let alias = pureAlias(current), !seen.contains(alias.target) else { break }
      seen.insert(alias.target)
      let next = effectiveValue(alias.target, mode, ctx)
      currentKey = alias.target
      value = next ?? alias.fallback
    }
    return steps
  }

  /// The literal a chain ends on, with embedded references substituted; nil when it never
  /// reaches one.
  public static func resolvedValue(_ key: String, _ mode: Mode, _ ctx: Context, depth: Int = 0) -> String? {
    let steps = resolveChain(key, mode, ctx)
    guard let last = steps.last, pureAlias(last.value) == nil else { return nil }
    if !JSText.includes(last.value, "var(") { return last.value }
    if depth > 4 { return nil }
    let substituted = substituteVars(last.value, mode, ctx, depth + 1)
    return JSText.includes(substituted, "var(") ? nil : substituted
  }

  /// Replaces the leftmost `var()` with what it resolves to and recurses; depth-capped.
  static func substituteVars(_ value: String, _ mode: Mode, _ ctx: Context, _ depth: Int) -> String {
    if depth > 4 { return value }
    guard let start = JSText.indexOf(value, "var(") else { return value }
    let units = Array(value.utf16)
    var open = 0
    var end: Int?
    var i = start + 3
    while i < units.count {
      if units[i] == 0x28 { open += 1 } else if units[i] == 0x29 {
        open -= 1
        if open == 0 { end = i; break }
      }
      i += 1
    }
    guard let close = end else { return value }
    let inner = JSText.slice(value, start + 4, close)
    guard let head = JSText.firstMatch(inner, varHead), let name = head.groups[1] else { return value }
    let fallback = JSText.indexOf(inner, ",").map { JS.trim(JSText.slice(inner, $0 + 1)) }
    let resolved = resolvedValue(name, mode, ctx, depth: depth) ?? fallback.flatMap { $0.isEmpty ? nil : substituteVars($0, mode, ctx, depth + 1) }
    guard let replacement = resolved, !JSText.includes(replacement, "var(") else { return value }
    return substituteVars(JSText.slice(value, 0, start) + replacement + JSText.slice(value, close + 1), mode, ctx, depth + 1)
  }

  /// The same resolution for a value the user is typing, which is stored under no key yet.
  public static func resolveValueLiteral(_ value: String?, _ mode: Mode, _ ctx: Context, depth: Int = 0) -> String? {
    guard let raw = value else { return nil }
    let v = JS.trim(raw)
    if v.isEmpty || depth > 4 { return nil }
    if let alias = pureAlias(v) {
      return resolvedValue(alias.target, mode, ctx, depth: depth + 1) ?? resolveValueLiteral(alias.fallback, mode, ctx, depth: depth + 1)
    }
    if !JSText.includes(v, "var(") { return v }
    let substituted = substituteVars(v, mode, ctx, depth + 1)
    return JSText.includes(substituted, "var(") ? nil : substituted
  }

  // MARK: Kind and origin

  /// Whether the variable holds a colour. `base` asks the value without the user's override (what
  /// must not change while someone types); `shown` also says yes when the override is a colour.
  public static func isColorVariable(_ key: String, _ ctx: Context, shown: Bool = true) -> Bool {
    if let def = CssVariables.definition(key) { return def.kind == "color" }
    let own = ctx.overrides[key] != nil && ctx.vars?[key] == nil
    return Mode.allCases.contains { mode in
      let base = own ? effectiveValue(key, mode, ctx) : baseValue(key, mode, ctx)
      if CssColor.isDisplayable(resolveValueLiteral(base, mode, ctx)) { return true }
      return shown && ctx.overrides[key] != nil && CssColor.isDisplayable(resolveValueLiteral(effectiveValue(key, mode, ctx), mode, ctx))
    }
  }

  /// Who supplies the value: `user` for an override over something, `own` for a value of the
  /// user's with nothing underneath, else the base origin.
  public static func originOf(_ key: String, _ ctx: Context) -> String {
    if ctx.overrides[key] != nil {
      return baseValue(key, .light, ctx) == nil && baseValue(key, .dark, ctx) == nil ? "own" : "user"
    }
    return baseOriginOf(key, ctx)
  }

  /// Where the value under the user's override comes from: what "Zurücksetzen" brings back.
  public static func baseOriginOf(_ key: String, _ ctx: Context) -> String {
    if case .object(let info)? = ctx.vars?[key], let origin = info["origin"], JS.truthy(origin) { return JS.string(origin) }
    return CssVariables.definition(key) != nil ? "core" : "build"
  }

  /// The catalogue's group, else the name's first segment in capitals.
  public static func groupOf(_ key: String) -> String {
    if let def = CssVariables.definition(key) { return def.group }
    return (JSText.split(key, "-").first ?? key).uppercased()
  }

  /// Every key the catalogue, the graph and the overrides know, in that order.
  public static func allKnownKeys(_ ctx: Context) -> [String] {
    var keys = CssVariables.all.map(\.key)
    var seen = Set(keys)
    for key in (ctx.vars?.keys ?? []) + ctx.overrideList.map(\.key) where !seen.contains(key) {
      keys.append(key)
      seen.insert(key)
    }
    return keys
  }

  /// A search as one types it, `--tpl-space-lg` included: the keys are bare.
  public static func normalizeQuery(_ query: String) -> String {
    JSText.replaceAll(JS.trim(query).lowercased(), "\\A-+", with: "")
  }

  // MARK: Ground

  /// What a swatch sits on in the built website: Quartz paints `body` with `var(--light)`.
  public static func pageGround(_ mode: Mode, _ ctx: Context) -> String {
    let value = resolvedValue("light", mode, ctx)
    return CssColor.isDisplayable(value) ? value! : (mode == .light ? "#ffffff" : "#000000")
  }

  /// The same ground, from a palette as `theme.colors.lightMode`/`darkMode` holds it.
  public static func paletteGround(_ mode: Mode, _ palette: JSONObject?) -> String {
    if case .string(let value)? = palette?["light"], CssColor.isDisplayable(value) { return value }
    return mode == .light ? "#ffffff" : "#000000"
  }
}
