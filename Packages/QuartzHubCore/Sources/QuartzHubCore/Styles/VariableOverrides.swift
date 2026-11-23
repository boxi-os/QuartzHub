import Foundation

/// One CSS variable the Styles page sets (`CssVariableOverride` in `shared/ipc-contract.ts`).
public struct VariableOverride: Equatable, Sendable {
  public var key: String
  public var light: String
  /// nil: no dark value of its own.
  public var dark: String?
  /// Only the light mode gets `light`; the dark mode keeps the site's value (Form C of 1.1).
  public var lightOnly: Bool

  public init(key: String, light: String, dark: String? = nil, lightOnly: Bool = false) {
    self.key = key
    self.light = light
    self.dark = dark
    self.lightOnly = lightOnly
  }

  /// As QuartzControl's object serialises: `dark` only when set, `lightOnly` only when true.
  public var json: JSONValue {
    var pairs: [(String, JSONValue)] = [("key", .string(key)), ("light", .string(light))]
    if let dark { pairs.append(("dark", .string(dark))) }
    if lightOnly { pairs.append(("lightOnly", .bool(true))) }
    return .object(JSONObject(pairs))
  }
}

/// The `css-vars` block: three kinds of rule (both modes, dark, light only), read as
/// `styleService.ts` does and written as QuartzHub decided on 2026-11-23:
///
/// ```scss
/// :root,
/// :root body { … }
/// :root[saved-theme="dark"],
/// :root[saved-theme="dark"] body { … }
/// :root:not([saved-theme="dark"]),
/// :root:not([saved-theme="dark"]) body { … }
/// ```
///
/// QuartzControl 1.3 wrote `:root` alone. A core 3 theme declares its table on `body`, and a value
/// body declares itself is what the page gets whatever `:root` says: the plain form reached `html`
/// and nothing below it (measured in WebKit, decisions/phase-5-gleichstand.md, „Variablen gegen ein
/// core-3-Theme“). The `body` half carries the value to where the theme sets it; unlayered, it beats
/// the theme's layered rule. Both forms are read; the plain one is rewritten before every build
/// (`upgradeSelectors`). QuartzControl 1.3 reads the new form as no override at all.
public enum VariableOverrides {
  static let darkSelector = #":root[saved-theme="dark"]"#
  static let lightOnlySelector = #":root:not([saved-theme="dark"])"#
  static let space = "[" + JSText.space + "]"
  /// The attribute value with or without quotes: Sass drops them, and a rule copied back from the
  /// browser has none.
  static let darkHead = #":root\[saved-theme=["']?dark["']?\]"#
  static let lightOnlyHead = #":root:not\(\[saved-theme=["']?dark["']?\]\)"#
  /// A rule of one kind: the bare selector (1.3's form) or the list with its `body` half.
  static func rule(_ head: String) -> String {
    head + "(?:\(space)*,\(space)*" + head + "\(space)+body)?\(space)*" + #"\{([^}]*)\}"#
  }
  static let rootRule = rule(":root")
  static let darkRule = rule(darkHead)
  static let lightOnlyRule = rule(lightOnlyHead)

  /// `--name: value;` pairs, with JavaScript's object order (a key like "1" first).
  static func declarations(_ block: String) -> JSONObject {
    var result = JSONObject()
    for match in JSText.matches(block, "--([A-Za-z0-9_-]+)[\(JSText.space)]*:[\(JSText.space)]*([^;]+);") {
      result[match.groups[1]!] = .string(JS.trim(match.groups[2]!))
    }
    return result
  }

  /// Every rule of each kind, the later one winning per variable (two copies of the block carry
  /// two of each, and the browser applies them the same way).
  public static func parse(_ body: String) -> [VariableOverride] {
    func collect(_ pattern: String) -> JSONObject {
      var merged = JSONObject()
      for match in JSText.matches(body, pattern) {
        let found = declarations(match.groups[1]!)
        for key in found.keys { merged[key] = found[key] }
      }
      return merged
    }
    let light = collect(rootRule), dark = collect(darkRule), lightOnly = collect(lightOnlyRule)
    var keys: [String] = []
    for key in light.keys + dark.keys + lightOnly.keys where !keys.contains(key) { keys.append(key) }
    return keys.map { key in
      guard let only = lightOnly[key]?.stringValue else {
        return VariableOverride(key: key, light: light[key]?.stringValue ?? "", dark: dark[key]?.stringValue)
      }
      // The light-only rule wins in light mode whatever `:root` says (0,2,0 against 0,1,0); a
      // `:root` value beside it is what dark mode gets, unless a dark rule says otherwise.
      if let darkValue = dark[key]?.stringValue ?? light[key]?.stringValue {
        return VariableOverride(key: key, light: only, dark: darkValue)
      }
      return VariableOverride(key: key, light: only, lightOnly: true)
    }
  }

  static func hasDark(_ override: VariableOverride) -> Bool {
    guard let dark = override.dark else { return false }
    return !JS.trim(dark).isEmpty
  }

  /// Light-only only where it can mean something: with a dark half the two ordinary rules say the
  /// same, and every older reader understands them.
  static func isLightOnly(_ override: VariableOverride) -> Bool {
    override.lightOnly && !hasDark(override)
  }

  /// The block's body. An empty half is no declaration: `--x: ;` is an empty custom property, and
  /// every `var(--x)` then resolves to nothing.
  public static func render(_ overrides: [VariableOverride]) -> String {
    func lines(_ list: [VariableOverride], _ value: (VariableOverride) -> String) -> String {
      list.map { "  --\($0.key): \(value($0));" }.joined(separator: "\n")
    }
    let withLight = overrides.filter { !JS.trim($0.light).isEmpty }
    let both = withLight.filter { !isLightOnly($0) }
    let only = withLight.filter(isLightOnly)
    let dark = overrides.filter(hasDark)
    func head(_ selector: String) -> String { "\(selector),\n\(selector) body {" }
    var rules: [String] = []
    if !both.isEmpty { rules.append("\(head(":root"))\n\(lines(both) { $0.light })\n}") }
    if !dark.isEmpty { rules.append("\(head(darkSelector))\n\(lines(dark) { $0.dark ?? "" })\n}") }
    if !only.isEmpty { rules.append("\(head(lightOnlySelector))\n\(lines(only) { $0.light })\n}") }
    return rules.joined(separator: "\n\n")
  }

  /// A rule head of 1.3's form at the start of the block, of a line or after a rule: the selector
  /// alone before its brace. A head of the new form does not fit: its `,` or ` body` comes first.
  static let plainHead = #"(\A|[\n}])("# + space + #"*?)([ \t]*)(:root(?:\[saved-theme=["']?dark["']?\]|:not\(\[saved-theme=["']?dark["']?\]\))?)"# + space + #"*\{"#

  /// Whether a `css-vars` body still has a rule in 1.3's form.
  static func hasPlainRules(_ body: String) -> Bool { JSText.test(body, plainHead) }

  /// Every rule head of 1.3's form gets its `body` half; declarations, comments and anything else
  /// stay as they are, so a block edited by hand loses nothing.
  public static func upgradeSelectors(_ body: String) -> String {
    JSText.replaceAll(body, plainHead, template: "$1$2$3$4,\n$3$4 body {")
  }

  /// The variables the page sets that custom.scss also sets in a rule that reaches the same element
  /// at the same specificity: there the user's rule comes later and wins, and the page would show a
  /// value the site does not have. Only in a moved project (in 1.0's form the variables still come
  /// last). Against a block in 1.3's form that is a rule of the same selector; against the new form
  /// one whose list holds the `body` half, since a plain `:root` of the user's then reaches `html`
  /// only and the page's value is the one below it.
  static func collisions(_ sources: StyleSheets.Sources) -> [String] {
    guard sources.managedExists, let body = StyleSheets.managedBody(sources, "css-vars") else { return [] }
    let overrides = parse(body)
    let plain = hasPlainRules(body)
    let inRoot = Set(overrides.filter { !JS.trim($0.light).isEmpty && !($0.lightOnly && !hasDark($0)) }.map(\.key))
    let inDark = Set(overrides.filter(hasDark).map(\.key))
    let inLightOnly = Set(overrides.filter { !JS.trim($0.light).isEmpty && $0.lightOnly && !hasDark($0) }.map(\.key))
    var own = sources.custom
    for marker in ManagedBlocks.movedMarkers { own = ManagedBlocks.strip(own, marker) }
    // Comments out, so a rule quoted in a note does not count.
    own = JSText.replaceAll(own, #"/\*[\s\S]*?\*/"#, with: "")
    own = JSText.replaceAll(own, #"(\A|[^:])//[^\n]*"#, template: "$1")
    let kinds: [(selectors: [String], names: Set<String>)] = [
      ([":root"], inRoot),
      ([darkSelector, ":root[saved-theme=dark]"], inDark),
      ([lightOnlySelector, ":root:not([saved-theme=dark])"], inLightOnly)
    ]
    var hits: Set<String> = []
    for match in JSText.matches(own, "(\\A|[}\(JSText.space);])(:root[^{};]*)\\{([^}]*)\\}") {
      let selector = JSText.replaceAll(JSText.replaceAll(match.groups[2]!, "[\(JSText.space)]+", with: ""), "'", with: "\"")
      let parts = Set(JSText.split(selector, ","))
      for kind in kinds {
        let same = plain ? kind.selectors.contains(selector) : kind.selectors.contains { parts.contains($0 + "body") }
        guard same else { continue }
        for key in declarations(match.groups[3]!).keys where kind.names.contains(key) { hits.insert(key) }
      }
    }
    return hits.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
  }
}
