import Foundation

/// The catalogue of the custom properties Quartz's own `joinStyles()` (`quartz/util/theme.ts`)
/// emits, and how their defaults are computed: a port of `shared/cssVariables.ts`. The nine classic
/// colours and four font slots are written from the config; everything after them is a `var()`
/// alias of one of those, or (accent h/s/l) computed from `secondary` with Quartz's `hexToHsl`.
public enum CssVariables {
  public struct Definition: Equatable, Sendable {
    public var key: String
    /// An id, not a label: the label is a text in the catalog (`styles.variables.groups.*`).
    public var group: String
    /// `discovered` is a key from the theme or build scan: nothing is known about it.
    public var kind: String
    public var source: String?
  }

  static func entry(_ key: String, _ group: String, _ kind: String, _ source: String? = nil) -> Definition {
    Definition(key: key, group: group, kind: kind, source: source)
  }

  public static let all: [Definition] = [
    entry("light", "baseColors", "color", "light"), entry("lightgray", "baseColors", "color", "lightgray"),
    entry("gray", "baseColors", "color", "gray"), entry("darkgray", "baseColors", "color", "darkgray"),
    entry("dark", "baseColors", "color", "dark"), entry("secondary", "baseColors", "color", "secondary"),
    entry("tertiary", "baseColors", "color", "tertiary"), entry("highlight", "baseColors", "color", "highlight"),
    entry("textHighlight", "baseColors", "color", "textHighlight"),

    entry("background-primary", "surfaces", "color", "light"), entry("background-primary-alt", "surfaces", "color", "light"),
    entry("background-secondary", "surfaces", "color", "lightgray"), entry("background-secondary-alt", "surfaces", "color", "lightgray"),
    entry("background-modifier-border", "surfaces", "color", "lightgray"), entry("background-modifier-border-hover", "surfaces", "color", "gray"),
    entry("background-modifier-border-focus", "surfaces", "color", "secondary"),

    entry("text-normal", "text", "color", "darkgray"), entry("text-muted", "text", "color", "gray"), entry("text-faint", "text", "color", "gray"),
    entry("text-accent", "text", "color", "secondary"), entry("text-accent-hover", "text", "color", "tertiary"),
    entry("text-on-accent", "text", "color", "light"), entry("text-on-accent-inverted", "text", "color", "dark"),
    entry("text-highlight-bg", "text", "color", "textHighlight"),

    entry("interactive-normal", "interaction", "color", "light"), entry("interactive-hover", "interaction", "color", "lightgray"),
    entry("interactive-accent", "interaction", "color", "secondary"), entry("interactive-accent-hover", "interaction", "color", "tertiary"),

    entry("color-base-00", "baseScale", "color", "light"), entry("color-base-05", "baseScale", "color", "light"),
    entry("color-base-10", "baseScale", "color", "light"), entry("color-base-20", "baseScale", "color", "lightgray"),
    entry("color-base-25", "baseScale", "color", "lightgray"), entry("color-base-30", "baseScale", "color", "lightgray"),
    entry("color-base-35", "baseScale", "color", "lightgray"), entry("color-base-40", "baseScale", "color", "gray"),
    entry("color-base-50", "baseScale", "color", "gray"), entry("color-base-60", "baseScale", "color", "gray"),
    entry("color-base-70", "baseScale", "color", "darkgray"), entry("color-base-100", "baseScale", "color", "dark"),

    // Written directly by joinStyles; titleFont falls back to the header font, and all four are
    // mode-independent.
    entry("titleFont", "fonts", "font", "header"), entry("headerFont", "fonts", "font", "header"),
    entry("bodyFont", "fonts", "font", "body"), entry("codeFont", "fonts", "font", "code"),
    entry("font-text", "fonts", "font", "body"), entry("font-monospace", "fonts", "font", "code"), entry("font-interface", "fonts", "font", "body"),

    entry("nav-item-color", "navigation", "color", "darkgray"), entry("nav-item-color-hover", "navigation", "color", "dark"),
    entry("nav-item-color-active", "navigation", "color", "secondary"), entry("nav-item-background-hover", "navigation", "color", "lightgray"),
    entry("nav-item-background-active", "navigation", "color", "highlight"),

    entry("tag-background", "tags", "color", "highlight"), entry("tag-color", "tags", "color", "secondary"),
    entry("tag-background-hover", "tags", "color", "lightgray"),

    entry("icon-color", "other", "color", "darkgray"), entry("icon-color-hover", "other", "color", "dark"),
    entry("icon-color-active", "other", "color", "secondary"), entry("divider-color", "other", "color", "lightgray"),
    entry("link-color", "other", "color", "secondary"), entry("link-color-hover", "other", "color", "tertiary"),

    entry("accent-h", "accentHsl", "accent-h"), entry("accent-s", "accentHsl", "accent-s"), entry("accent-l", "accentHsl", "accent-l")
  ]

  static let byKey: [String: Definition] = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

  public static func definition(_ key: String) -> Definition? { byKey[key] }

  /// Quartz's `hexToHsl`, same rounding, same answer for a hex it cannot read.
  public static func hexToHsl(_ hex: String) -> (h: Double, s: Double, l: Double) {
    guard let match = JSText.firstMatch(hex, #"\A#?([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})\z"#) else { return (0, 0, 0) }
    let channel = { (group: Int) in Double(Int(match.groups[group]!, radix: 16)!) / 255 }
    let r = channel(1), g = channel(2), b = channel(3)
    let high = max(r, g, b), low = min(r, g, b)
    let l = (high + low) / 2
    if high == low { return (0, 0, FontFile.jsRound(l * 100)) }
    let d = high - low
    let s = l > 0.5 ? d / (2 - high - low) : d / (high + low)
    var h = 0.0
    switch high {
    case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6
    case g: h = ((b - r) / d + 2) / 6
    case b: h = ((r - g) / d + 4) / 6
    default: break
    }
    return (FontFile.jsRound(h * 360), FontFile.jsRound(s * 100), FontFile.jsRound(l * 100))
  }

  /// The value a variable resolves to today, absent any override: what its "anpassen" toggle
  /// fills both fields with.
  public static func defaultValue(_ def: Definition, lightMode: JSONObject?, darkMode: JSONObject?, typography: JSONObject?, dark: Bool) -> String {
    let palette = (dark ? darkMode : lightMode) ?? JSONObject()
    if def.kind == "color", let source = def.source { return palette[source]?.stringValue ?? "" }
    if def.kind == "font", let source = def.source { return typography?[source]?.stringValue ?? "" }
    if ["accent-h", "accent-s", "accent-l"].contains(def.kind) {
      let hsl = hexToHsl(palette["secondary"]?.stringValue ?? "")
      if def.kind == "accent-h" { return JSJSON.numberToString(hsl.h) }
      if def.kind == "accent-s" { return "\(JSJSON.numberToString(hsl.s))%" }
      return "\(JSJSON.numberToString(hsl.l))%"
    }
    return ""
  }

  /// A raw value goes straight into a stylesheet, so braces, semicolons, backslashes and comment
  /// markers are refused; "/" stays (`rgb(0 0 0 / 50%)`, the font shorthand).
  public static func isWritable(_ value: String) -> Bool {
    !JSText.test(value, "[{};]") && !JSText.includes(value, "/*") && !JSText.includes(value, "*/") && !JSText.includes(value, "\\")
  }

  /// Quartz's callout colours (`quartz/styles/callouts.scss`): redefined per type inside
  /// `.callout[data-callout="<type>"]`, not global. `quote` sets no background of its own.
  public struct Callout: Equatable, Sendable {
    public var type: String
    public var color: String
    public var border: String
    public var background: String?
  }

  public static let callouts: [Callout] = [
    Callout(type: "note", color: "#448aff", border: "#448aff44", background: "#448aff10"),
    Callout(type: "abstract", color: "#00b0ff", border: "#00b0ff44", background: "#00b0ff10"),
    Callout(type: "info", color: "#00b8d4", border: "#00b8d444", background: "#00b8d410"),
    Callout(type: "todo", color: "#00b8d4", border: "#00b8d444", background: "#00b8d410"),
    Callout(type: "tip", color: "#00bfa5", border: "#00bfa544", background: "#00bfa510"),
    Callout(type: "success", color: "#09ad7a", border: "#09ad7144", background: "#09ad7110"),
    Callout(type: "question", color: "#dba642", border: "#dba64244", background: "#dba64210"),
    Callout(type: "warning", color: "#db8942", border: "#db894244", background: "#db894210"),
    Callout(type: "failure", color: "#db4242", border: "#db424244", background: "#db424210"),
    Callout(type: "danger", color: "#db4242", border: "#db424244", background: "#db424210"),
    Callout(type: "bug", color: "#db4242", border: "#db424244", background: "#db424210"),
    Callout(type: "example", color: "#7a43b5", border: "#7a43b544", background: "#7a43b510"),
    Callout(type: "quote", color: "var(--secondary)", border: "var(--lightgray)", background: nil)
  ]

  /// A callout colour's literal value: `quote` aliases the classic colours, looked up like the
  /// defaults so its swatch shows the real colour.
  public static func resolveCalloutValue(_ value: String?, lightMode: JSONObject?, darkMode: JSONObject?, dark: Bool) -> String {
    guard let value, !value.isEmpty else { return "" }
    guard let match = JSText.firstMatch(value, #"\Avar\(--([A-Za-z0-9_]+)\)\z"#) else { return value }
    let palette = (dark ? darkMode : lightMode) ?? JSONObject()
    return palette[match.groups[1]!]?.stringValue ?? ""
  }
}
