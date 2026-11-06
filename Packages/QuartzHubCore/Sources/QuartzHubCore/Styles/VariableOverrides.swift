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

/// The `css-vars` block: three kinds of rule (`:root` for both modes, `:root[saved-theme="dark"]`,
/// `:root:not([saved-theme="dark"])` for light only), read and written as `styleService.ts` does.
public enum VariableOverrides {
  static let lightOnlySelector = #":root:not([saved-theme="dark"])"#
  static let rootRule = #":root["# + JSText.space + #"]*\{([^}]*)\}"#
  /// The attribute value with or without quotes: Sass drops them, and a rule copied back from the
  /// browser has none.
  static let darkRule = #":root\[saved-theme=["']?dark["']?\]["# + JSText.space + #"]*\{([^}]*)\}"#
  static let lightOnlyRule = #":root:not\(\[saved-theme=["']?dark["']?\]\)["# + JSText.space + #"]*\{([^}]*)\}"#

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
    var rules: [String] = []
    if !both.isEmpty { rules.append(":root {\n\(lines(both) { $0.light })\n}") }
    if !dark.isEmpty { rules.append(":root[saved-theme=\"dark\"] {\n\(lines(dark) { $0.dark ?? "" })\n}") }
    if !only.isEmpty { rules.append("\(lightOnlySelector) {\n\(lines(only) { $0.light })\n}") }
    return rules.joined(separator: "\n\n")
  }

  /// The variables the page sets that custom.scss also sets in a rule of the same selector: there
  /// the user's rule comes later at the same specificity and wins, and the page would show a value
  /// the site does not have. Only in a moved project (in 1.0's form the variables still come last).
  static func collisions(_ sources: StyleSheets.Sources) -> [String] {
    guard sources.managedExists, let body = StyleSheets.managedBody(sources, "css-vars") else { return [] }
    let overrides = parse(body)
    let inRoot = Set(overrides.filter { !JS.trim($0.light).isEmpty && !($0.lightOnly && !hasDark($0)) }.map(\.key))
    let inDark = Set(overrides.filter(hasDark).map(\.key))
    let inLightOnly = Set(overrides.filter { !JS.trim($0.light).isEmpty && $0.lightOnly && !hasDark($0) }.map(\.key))
    var own = sources.custom
    for marker in ManagedBlocks.movedMarkers { own = ManagedBlocks.strip(own, marker) }
    // Comments out, so a rule quoted in a note does not count.
    own = JSText.replaceAll(own, #"/\*[\s\S]*?\*/"#, with: "")
    own = JSText.replaceAll(own, #"(\A|[^:])//[^\n]*"#, template: "$1")
    var hits: Set<String> = []
    for match in JSText.matches(own, "(\\A|[}\(JSText.space);])(:root[^{};]*)\\{([^}]*)\\}") {
      let selector = JSText.replaceAll(JSText.replaceAll(match.groups[2]!, "[\(JSText.space)]+", with: ""), "'", with: "\"")
      let managed: Set<String>
      switch selector {
      case ":root": managed = inRoot
      case #":root[saved-theme="dark"]"#, ":root[saved-theme=dark]": managed = inDark
      case lightOnlySelector, ":root:not([saved-theme=dark])": managed = inLightOnly
      default: continue
      }
      for key in declarations(match.groups[3]!).keys where managed.contains(key) { hits.insert(key) }
    }
    return hits.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
  }
}
