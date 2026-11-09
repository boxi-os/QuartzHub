import Foundation

/// What a CSS value is as a colour, the way Chrome's canvas answers it: QuartzControl asked
/// `fillStyle` (`probeColor` in `src/routes/Styles/variableGraph.ts`), so its colour parser is what
/// this has to agree with. Measured against Chrome (`scripts/css-color-golden.mjs`).
///
/// Canvas answers in three forms, and so does `canvas`: an sRGB colour of the legacy notations
/// (hex, names, `rgb()`, `hsl()`, `hwb()`) as `#rrggbb` or `rgba(r, g, b, a)` with eight bits per
/// channel; a `color-mix()` that ends in sRGB as `color(srgb r g b / a)`; anything in another space
/// (`oklch()`, `lab()`, `color(display-p3 …)`, a mix in one of those) as itself. Only the first two
/// give the colour picker a hex.
///
/// Not read, though Chrome reads them: system colours (`Canvas`, `ButtonText`: their value is the
/// platform's), relative colours (`rgb(from red r g b)`), and functions other than `calc()` inside a
/// channel. No theme the golden saw uses them.
public enum CssColor {
  public enum Space: String, Sendable, CaseIterable {
    case srgb, srgbLinear = "srgb-linear", displayP3 = "display-p3", a98 = "a98-rgb", prophoto = "prophoto-rgb", rec2020
    case xyzD50 = "xyz-d50", xyzD65 = "xyz-d65", lab, lch, oklab, oklch, hsl, hwb

    var isPolar: Bool { self == .lch || self == .oklch || self == .hsl || self == .hwb }
    /// The index of the hue among the three components.
    var hueIndex: Int? {
      switch self {
      case .lch, .oklch: 2
      case .hsl, .hwb: 0
      default: nil
      }
    }
  }

  /// A parsed colour: three components in `space` (nil is `none`), and alpha. `legacy` is a colour
  /// of the old notations, which Chrome holds in eight bits per channel.
  public struct Color: Equatable, Sendable {
    public var space: Space
    public var components: [Double?]
    public var alpha: Double?
    public var legacy: Bool
  }

  /// What canvas makes of the value, by form.
  public enum Canvas: Equatable, Sendable {
    /// Eight bits per channel; `#rrggbb` when opaque.
    case legacy(r: Int, g: Int, b: Int, a: Int)
    /// `color(srgb r g b / a)`, as Chrome writes it.
    case srgbFunction(String)
    /// Kept in its own space: a colour, but none the picker can hold.
    case other(Color)
  }

  // MARK: QuartzControl's questions

  /// `cssColorToHexAlpha`: `#rrggbb` and the alpha the picker cannot show, or nil when canvas says
  /// "no colour" or answers outside sRGB.
  public static func hexAlpha(_ value: String?) -> (hex: String, alpha: Double)? {
    guard let canvas = probe(value) else { return nil }
    switch canvas {
    case .legacy(let r, let g, let b, let a):
      return (hex(r, g, b), a == 255 ? 1 : (Double(legacyAlpha(a)) ?? 1))
    case .srgbFunction(let text):
      // QuartzControl's own pattern over canvas' text: no sign, no exponent.
      guard let match = text.wholeMatch(of: #/color\(srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+)\s*)?\)/#.ignoresCase()) else { return nil }
      let channels = [match.1, match.2, match.3].map { channel -> Int in
        let n = Double(channel) ?? .nan
        return n.isNaN ? 0 : max(0, min(255, Int(jsRound(n * 255))))
      }
      var alpha = 1.0
      if let raw = match.4 {
        let n = Double(raw) ?? .nan
        alpha = n.isNaN ? Double.nan : max(0, min(1, n))
      }
      return (hex(channels[0], channels[1], channels[2]), alpha)
    case .other:
      return nil
    }
  }

  /// `cssColorToHex`: only an opaque colour.
  public static func hex(_ value: String?) -> String? {
    guard let parsed = hexAlpha(value), parsed.alpha == 1 else { return nil }
    return parsed.hex
  }

  /// `isDisplayableColor`: a value canvas paints, `currentColor` left out (it paints the colour of
  /// the element it is used on).
  public static func isDisplayable(_ value: String?) -> Bool {
    guard let value, !value.isEmpty else { return false }
    if value.wholeMatch(of: #/\s*currentcolor\s*/#.ignoresCase()) != nil { return false }
    return probe(value) != nil
  }

  /// `probeColor`: canvas' answer, nil for "no colour". QuartzControl primed the canvas with
  /// `#010203` and read an unchanged answer as "no colour", so a value that *is* `#010203` in
  /// another spelling (`rgb(1, 2, 3)`) is no colour there either; kept, it is the answer the page
  /// gave.
  public static func probe(_ value: String?) -> Canvas? {
    guard let raw = value else { return nil }
    let v = JS.trim(raw)
    if v.isEmpty || v.contains("var(") { return nil }
    guard let color = parse(v) else { return nil }
    let canvas = canvasForm(color)
    if case .legacy(1, 2, 3, 255) = canvas, v.lowercased() != "#010203" { return nil }
    return canvas
  }

  /// The colour as sRGB components (unclipped; a colour outside sRGB goes past 0 and 1), for a
  /// swatch. nil when the value is no colour canvas paints.
  public static func srgb(_ value: String?) -> (r: Double, g: Double, b: Double, a: Double)? {
    guard let value, isDisplayable(value), let color = parse(JS.trim(value)) else { return nil }
    let c = convert(color, to: .srgb)
    return (c.components[0] ?? 0, c.components[1] ?? 0, c.components[2] ?? 0, c.alpha ?? 1)
  }

  // MARK: Canvas' form

  static func canvasForm(_ color: Color) -> Canvas {
    if color.legacy {
      if color.space == .hsl || color.space == .hwb {
        // In 32-bit floats, as Chrome's gfx::HSLToSRGB: hsl(254, 75%, 50%) is 0.2999998 red there,
        // #4c, and 0.3 in doubles, #4d.
        let c = color.components.map { Float($0 ?? 0) }
        let rgb = color.space == .hsl ? hslToSRGB32(c[0], c[1] / 100, c[2] / 100) : hwbToSRGB32(c[0], c[1] / 100, c[2] / 100)
        let bytes = rgb.map { max(0, min(255, Int(($0 * 255).rounded()))) }
        return .legacy(r: bytes[0], g: bytes[1], b: bytes[2], a: byte(color.alpha ?? 1))
      }
      let c = color.components
      return .legacy(r: byte(c[0] ?? 0), g: byte(c[1] ?? 0), b: byte(c[2] ?? 0), a: byte(color.alpha ?? 1))
    }
    if color.space == .srgb {
      let parts = color.components.map { chromeNumber($0 ?? 0) }.joined(separator: " ")
      let alpha = color.alpha ?? 1
      return .srgbFunction(alpha >= 1 ? "color(srgb \(parts))" : "color(srgb \(parts) / \(chromeNumber(alpha)))")
    }
    return .other(color)
  }

  /// Chrome's alpha in `rgba()`: two decimals when they name the same eight bits, else three.
  static func legacyAlpha(_ a: Int) -> String {
    let value = Double(a) / 255
    let two = jsRound(value * 100) / 100
    if Int(jsRound(two * 255)) == a { return chromeNumber(two) }
    return chromeNumber(jsRound(value * 1000) / 1000)
  }

  /// Six significant digits, trailing zeros dropped; in exponent form five decimals and the
  /// exponent without padding.
  static func chromeNumber(_ value: Double) -> String {
    if value == 0 { return "0" }
    var text = String(format: "%.6g", value)
    if text.contains("e") {
      // In exponent form Chrome keeps the zeros: 1.00000e-7.
      let full = String(format: "%.5e", value)
      let e = full.firstIndex(of: "e")!
      return "\(full[..<e])e\(Int(full[full.index(after: e)...]) ?? 0)"
    }
    if text.contains(".") {
      while text.hasSuffix("0") { text.removeLast() }
      if text.hasSuffix(".") { text.removeLast() }
    }
    return text
  }

  static func byte(_ unit: Double) -> Int { max(0, min(255, Int(jsRound(unit * 255)))) }

  /// JavaScript's `Math.round`: halves go up, also below zero.
  static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

  static func hex(_ r: Int, _ g: Int, _ b: Int) -> String {
    "#" + [r, g, b].map { String(format: "%02x", $0) }.joined()
  }

  // MARK: Parsing

  /// A colour canvas reads, or nil. `text` is trimmed.
  public static func parse(_ text: String) -> Color? {
    let lower = text.lowercased()
    if lower.hasPrefix("#") { return parseHex(String(lower.dropFirst())) }
    if let open = lower.firstIndex(of: "("), lower.hasSuffix(")") {
      let name = String(lower[..<open])
      let inner = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
      return parseFunction(name, inner)
    }
    if lower == "transparent" { return Color(space: .srgb, components: [0, 0, 0], alpha: 0, legacy: true) }
    if lower == "currentcolor" { return Color(space: .srgb, components: [0, 0, 0], alpha: 1, legacy: true) }
    if let rgb = namedColors[lower] {
      return Color(space: .srgb, components: [Double(rgb >> 16) / 255, Double((rgb >> 8) & 255) / 255, Double(rgb & 255) / 255], alpha: 1, legacy: true)
    }
    return nil
  }

  static func parseHex(_ digits: String) -> Color? {
    guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
    let values = digits.map { Int(String($0), radix: 16)! }
    let bytes: [Int] = digits.count <= 4 ? values.map { $0 * 17 } : stride(from: 0, to: values.count, by: 2).map { values[$0] * 16 + values[$0 + 1] }
    return Color(space: .srgb, components: bytes.prefix(3).map { Double($0) / 255 }, alpha: bytes.count == 4 ? Double(bytes[3]) / 255 : 1, legacy: true)
  }

  static func parseFunction(_ name: String, _ inner: String) -> Color? {
    switch name {
    case "rgb", "rgba": return legacyColor(parseRgb(inner))
    // hsl() and hwb() keep their own numbers: Chrome mixes them unrounded (measured: a mix of
    // hsl(0, 0%, 15%) came out at the lightness of 15 %, not of 38/255) and rounds only when it
    // writes them out as rgb.
    case "hsl", "hsla": return parseHslHwb(inner, hwb: false)
    case "hwb": return parseHslHwb(inner, hwb: true)
    case "lab", "oklab": return parseLabLike(inner, space: name == "lab" ? .lab : .oklab, polar: false)
    case "lch", "oklch": return parseLabLike(inner, space: name == "lch" ? .lch : .oklch, polar: true)
    case "color": return parseColorFunction(inner)
    case "color-mix": return parseColorMix(inner)
    default: return nil
    }
  }

  /// rgb() is held in eight bits per channel, alpha too (measured: rgba(255, 0, 0, 0.5) mixed with
  /// blue gives the alpha 0.75098, the half of 128/255 and 1).
  static func legacyColor(_ color: Color?) -> Color? {
    guard let color else { return nil }
    return Color(space: .srgb, components: color.components.map { Double(byte($0 ?? 0)) / 255 },
                 alpha: Double(byte(color.alpha ?? 1)) / 255, legacy: true)
  }

  // MARK: Arguments

  enum Arg: Equatable {
    case number(Double), percent(Double), angle(Double), none
  }

  /// The arguments of a colour function: the channels and an optional alpha, and whether they were
  /// separated by commas (the legacy syntax).
  struct Args {
    var channels: [Arg]
    var alpha: Arg?
    var commas: Bool
  }

  /// Splits on whitespace (comments count as whitespace), commas and one slash, at depth zero.
  static func splitArgs(_ inner: String) -> Args? {
    var tokens: [String] = []
    var separators: [Character] = []
    var current = ""
    var depth = 0
    let chars = Array(inner)
    var i = 0
    func flush() {
      if !current.isEmpty { tokens.append(current); current = "" }
    }
    while i < chars.count {
      let c = chars[i]
      if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
        guard let end = (i + 2..<max(i + 2, chars.count - 1)).first(where: { chars[$0] == "*" && chars[$0 + 1] == "/" }) else { return nil }
        if depth == 0 { flush() } else { current.append(" ") }
        i = end + 2
        continue
      }
      if c == "(" { depth += 1 }
      if c == ")" { depth -= 1; if depth < 0 { return nil } }
      if depth == 0 && (c == "," || c == "/") {
        flush()
        separators.append(c)
        tokens.append(String(c))
      } else if depth == 0 && c.isWhitespace {
        flush()
      } else {
        current.append(c)
      }
      i += 1
    }
    guard depth == 0 else { return nil }
    flush()
    let commas = separators.contains(",")
    if commas {
      // a, b, c[, d]: every other token a comma, no slash
      guard !separators.contains("/") else { return nil }
      var values: [String] = []
      var expectValue = true
      for token in tokens {
        if token == "," {
          guard !expectValue else { return nil }
          expectValue = true
        } else {
          guard expectValue else { return nil }
          values.append(token)
          expectValue = false
        }
      }
      guard !expectValue, values.count == 3 || values.count == 4 else { return nil }
      var args = values.compactMap(parseArg)
      guard args.count == values.count else { return nil }
      let alpha = args.count == 4 ? args.removeLast() : nil
      return Args(channels: args, alpha: alpha, commas: true)
    }
    guard separators.filter({ $0 == "/" }).count <= 1 else { return nil }
    if let slash = tokens.firstIndex(of: "/") {
      let channels = tokens[..<slash].compactMap(parseArg)
      let after = Array(tokens[(slash + 1)...])
      guard channels.count == slash, channels.count == 3, after.count == 1, let alpha = parseArg(after[0]) else { return nil }
      return Args(channels: channels, alpha: alpha, commas: false)
    }
    let channels = tokens.compactMap(parseArg)
    guard channels.count == tokens.count, channels.count == 3 else { return nil }
    return Args(channels: channels, alpha: nil, commas: false)
  }

  static func parseArg(_ token: String) -> Arg? {
    let lower = token.lowercased()
    if lower == "none" { return Arg.none }
    if lower.hasPrefix("calc(") && lower.hasSuffix(")") {
      var parser = CalcParser(text: Array(lower.dropFirst(5).dropLast()))
      guard let value = parser.parseSum(), parser.atEnd else { return nil }
      return value.arg
    }
    return dimension(lower)
  }

  /// A number with an optional unit: `%`, or an angle in degrees.
  static func dimension(_ text: String) -> Arg? {
    guard let match = text.wholeMatch(of: #/([+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)(%|deg|rad|grad|turn)?/#) else { return nil }
    guard let n = Double(match.1) else { return nil }
    switch match.2 {
    case nil: return .number(n)
    case "%": return .percent(n)
    case "deg": return .angle(n)
    case "rad": return .angle(n * 180 / .pi)
    case "grad": return .angle(n * 0.9)
    case "turn": return .angle(n * 360)
    default: return nil
    }
  }

  /// `calc()` over numbers, percentages and angles: + - * / and parentheses. A sum needs both sides
  /// of one type; a product needs a plain number on one side.
  struct CalcParser {
    enum Kind { case number, percent, angle }
    struct Value {
      var n: Double
      var kind: Kind
      var arg: Arg? {
        guard n.isFinite else { return nil }
        switch kind {
        case .number: return .number(n)
        case .percent: return .percent(n)
        case .angle: return .angle(n)
        }
      }
    }

    var text: [Character]
    var i = 0
    var atEnd: Bool { var j = i; while j < text.count, text[j].isWhitespace { j += 1 }; return j == text.count }

    mutating func skip() { while i < text.count, text[i].isWhitespace { i += 1 } }

    mutating func parseSum() -> Value? {
      guard var left = parseProduct() else { return nil }
      while true {
        skip()
        guard i < text.count, text[i] == "+" || text[i] == "-" else { return left }
        let op = text[i]
        i += 1
        guard let right = parseProduct(), right.kind == left.kind else { return nil }
        left.n = op == "+" ? left.n + right.n : left.n - right.n
      }
    }

    mutating func parseProduct() -> Value? {
      guard var left = parseFactor() else { return nil }
      while true {
        skip()
        guard i < text.count, text[i] == "*" || text[i] == "/" else { return left }
        let op = text[i]
        i += 1
        guard let right = parseFactor() else { return nil }
        if op == "*" {
          if left.kind == .number { left = Value(n: left.n * right.n, kind: right.kind) }
          else if right.kind == .number { left.n *= right.n }
          else { return nil }
        } else {
          guard right.kind == .number, right.n != 0 else { return nil }
          left.n /= right.n
        }
      }
    }

    mutating func parseFactor() -> Value? {
      skip()
      guard i < text.count else { return nil }
      if text[i] == "(" || text[i...].starts(with: "calc(") {
        i += text[i] == "(" ? 1 : 5
        guard let inner = parseSum() else { return nil }
        skip()
        guard i < text.count, text[i] == ")" else { return nil }
        i += 1
        return inner
      }
      let start = i
      if text[i] == "+" || text[i] == "-" { i += 1 }
      while i < text.count, text[i].isNumber || text[i] == "." { i += 1 }
      if i < text.count, text[i] == "e", i + 1 < text.count, text[i + 1].isNumber || text[i + 1] == "-" || text[i + 1] == "+" {
        i += 2
        while i < text.count, text[i].isNumber { i += 1 }
      }
      while i < text.count, text[i].isLetter || text[i] == "%" { i += 1 }
      switch CssColor.dimension(String(text[start..<i])) {
      case .number(let n)?: return Value(n: n, kind: .number)
      case .percent(let n)?: return Value(n: n, kind: .percent)
      case .angle(let n)?: return Value(n: n, kind: .angle)
      default: return nil
      }
    }
  }

  static func alphaValue(_ arg: Arg?) -> Double?? {
    switch arg {
    case nil: return .some(1)
    case .number(let n)?: return .some(min(1, max(0, n)))
    case .percent(let n)?: return .some(min(1, max(0, n / 100)))
    case .none?: return .some(nil)
    case .angle?: return nil
    }
  }

  // MARK: The functions

  static func parseRgb(_ inner: String) -> Color? {
    guard let args = splitArgs(inner) else { return nil }
    if args.commas {
      let allNumbers = args.channels.allSatisfy { if case .number = $0 { true } else { false } }
      let allPercent = args.channels.allSatisfy { if case .percent = $0 { true } else { false } }
      guard allNumbers || allPercent else { return nil }
      if case .none? = args.alpha { return nil }
    }
    var channels: [Double?] = []
    for arg in args.channels {
      switch arg {
      case .number(let n): channels.append(min(255, max(0, n)) / 255)
      case .percent(let n): channels.append(min(100, max(0, n)) / 100)
      case .none: channels.append(nil)
      case .angle: return nil
      }
    }
    guard let alpha = alphaValue(args.alpha) else { return nil }
    return Color(space: .srgb, components: channels.map { $0 ?? 0 }, alpha: alpha ?? 0, legacy: true)
  }

  static func parseHslHwb(_ inner: String, hwb: Bool) -> Color? {
    guard let args = splitArgs(inner) else { return nil }
    if args.commas {
      guard !hwb else { return nil }
      if case .none = args.channels[0] { return nil }
      for arg in args.channels.dropFirst() { guard case .percent = arg else { return nil } }
      if case .none? = args.alpha { return nil }
    }
    var hue: Double
    switch args.channels[0] {
    case .number(let n), .angle(let n): hue = n
    case .none: hue = 0
    case .percent: return nil
    }
    hue = hue.truncatingRemainder(dividingBy: 360)
    if hue < 0 { hue += 360 }
    var rest: [Double] = []
    for arg in args.channels.dropFirst() {
      switch arg {
      case .number(let n), .percent(let n): rest.append(n)
      case .none: rest.append(0)
      case .angle: return nil
      }
    }
    guard let alpha = alphaValue(args.alpha) else { return nil }
    if hwb {
      return Color(space: .hwb, components: [hue, max(0, min(100, rest[0])), max(0, min(100, rest[1]))], alpha: alpha ?? 0, legacy: true)
    }
    return Color(space: .hsl, components: [hue, max(0, min(100, rest[0])), max(0, min(100, rest[1]))], alpha: alpha ?? 0, legacy: true)
  }

  static func parseLabLike(_ inner: String, space: Space, polar: Bool) -> Color? {
    guard let args = splitArgs(inner), !args.commas else { return nil }
    // What 100 % is, per component.
    let scale: [Double] = switch space {
    case .lab: [100, 125, 125]
    case .lch: [100, 150, 1]
    case .oklab: [1, 0.4, 0.4]
    default: [1, 0.4, 1]
    }
    var components: [Double?] = []
    for (index, arg) in args.channels.enumerated() {
      switch arg {
      case .none: components.append(nil)
      case .number(let n): components.append(n)
      case .percent(let n):
        if polar && index == 2 { return nil }
        components.append(n / 100 * scale[index])
      case .angle(let n):
        guard polar && index == 2 else { return nil }
        components.append(n)
      }
    }
    if let l = components[0] { components[0] = max(0, min(space == .lab || space == .lch ? 100 : 1, l)) }
    if polar {
      if let c = components[1] { components[1] = max(0, c) }
      if let h = components[2] { var h = h.truncatingRemainder(dividingBy: 360); if h < 0 { h += 360 }; components[2] = h }
    }
    guard let alpha = alphaValue(args.alpha) else { return nil }
    return Color(space: space, components: components, alpha: alpha, legacy: false)
  }

  static let colorFunctionSpaces: [String: Space] = [
    "srgb": .srgb, "srgb-linear": .srgbLinear, "display-p3": .displayP3, "a98-rgb": .a98, "prophoto-rgb": .prophoto,
    "rec2020": .rec2020, "xyz": .xyzD65, "xyz-d50": .xyzD50, "xyz-d65": .xyzD65
  ]

  static func parseColorFunction(_ inner: String) -> Color? {
    let trimmed = JS.trim(inner)
    guard let space = trimmed.firstIndex(where: \.isWhitespace),
          let name = colorFunctionSpaces[trimmed[..<space].lowercased()],
          let args = splitArgs(String(trimmed[space...])), !args.commas else { return nil }
    var components: [Double?] = []
    for arg in args.channels {
      switch arg {
      case .none: components.append(nil)
      case .number(let n): components.append(n)
      case .percent(let n): components.append(n / 100)
      case .angle: return nil
      }
    }
    guard let alpha = alphaValue(args.alpha) else { return nil }
    return Color(space: name, components: components, alpha: alpha, legacy: false)
  }

  // MARK: color-mix

  static let mixSpaces: [String: Space] = colorFunctionSpaces.merging(
    ["lab": .lab, "lch": .lch, "oklab": .oklab, "oklch": .oklch, "hsl": .hsl, "hwb": .hwb]) { a, _ in a }

  enum HueMethod: String { case shorter, longer, increasing, decreasing }

  /// `color-mix([in <space> [<hue> hue]], <color> [<p>], <color> [<p>])`. Without `in`, oklab.
  static func parseColorMix(_ inner: String) -> Color? {
    var parts: [String] = []
    var current = ""
    var depth = 0
    for c in inner {
      if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
      if c == "," && depth == 0 { parts.append(current); current = "" } else { current.append(c) }
    }
    parts.append(current)
    parts = parts.map(JS.trim)
    var space = Space.oklab
    var method = HueMethod.shorter
    if parts.count == 3 {
      let words = parts.removeFirst().lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
      guard words.count >= 2, words[0] == "in", let named = mixSpaces[words[1]] else { return nil }
      space = named
      if words.count > 2 {
        guard words.count == 4, words[3] == "hue", space.isPolar, let m = HueMethod(rawValue: words[2]) else { return nil }
        method = m
      }
    }
    guard parts.count == 2, let first = mixPart(parts[0]), let second = mixPart(parts[1]) else { return nil }
    var p1 = first.percent
    var p2 = second.percent
    switch (p1, p2) {
    case (nil, nil): p1 = 50; p2 = 50
    case (let a?, nil): p2 = 100 - a
    case (nil, let b?): p1 = 100 - b
    default: break
    }
    guard let a = p1, let b = p2, a >= 0, b >= 0, a <= 100, b <= 100 else { return nil }
    let sum = a + b
    let weight = sum == 0 ? 0.5 : b / sum
    let multiplier = min(1, sum / 100)
    var mixed = interpolate(convert(first.color, to: space), convert(second.color, to: space), weight, method: method)
    mixed.alpha = (mixed.alpha ?? 1) * multiplier
    // Chrome hands a mix in sRGB, hsl or hwb back as color(srgb …).
    if space == .hsl || space == .hwb { mixed = convert(mixed, to: .srgb) }
    mixed.legacy = false
    return mixed
  }

  static func mixPart(_ text: String) -> (color: Color, percent: Double?)? {
    // A percentage before or after the colour, at depth zero.
    var depth = 0
    var splitAt: String.Index?
    for index in text.indices {
      let c = text[index]
      if c == "(" { depth += 1 } else if c == ")" { depth -= 1 } else if c.isWhitespace && depth == 0 { splitAt = index }
    }
    if let split = splitAt {
      let head = JS.trim(String(text[..<split]))
      let tail = JS.trim(String(text[split...]))
      if case .percent(let p)? = dimension(tail.lowercased()), let color = parse(head) { return (color, p) }
      if let space = text.firstIndex(where: \.isWhitespace) {
        let lead = String(text[..<space])
        if case .percent(let p)? = dimension(lead.lowercased()), let color = parse(JS.trim(String(text[space...]))) { return (color, p) }
      }
    }
    guard let color = parse(text) else { return nil }
    return (color, nil)
  }

  static func interpolate(_ a: Color, _ b: Color, _ t: Double, method: HueMethod) -> Color {
    var ca = a.components
    var cb = b.components
    // A missing component takes the other colour's value; missing in both stays missing.
    for i in 0..<3 {
      if ca[i] == nil { ca[i] = cb[i] }
      if cb[i] == nil { cb[i] = ca[i] }
    }
    let alphaA = a.alpha ?? b.alpha ?? 1
    let alphaB = b.alpha ?? a.alpha ?? 1
    let alpha = alphaA + (alphaB - alphaA) * t
    let hue = a.space.hueIndex
    if let h = hue, let h1 = ca[h], let h2 = cb[h] {
      var x = h1, y = h2
      switch method {
      case .shorter:
        if y - x > 180 { x += 360 } else if y - x < -180 { y += 360 }
      case .longer:
        if 0 < y - x && y - x < 180 { x += 360 } else if -180 < y - x && y - x <= 0 { y += 360 }
      case .increasing:
        if y < x { y += 360 }
      case .decreasing:
        if x < y { x += 360 }
      }
      ca[h] = x
      cb[h] = y
    }
    var out: [Double?] = []
    for i in 0..<3 {
      guard let x = ca[i], let y = cb[i] else { out.append(nil); continue }
      if i == hue {
        var v = x + (y - x) * t
        v = v.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        out.append(v)
      } else if alpha == 0 {
        out.append(x + (y - x) * t)
      } else {
        // premultiplied
        out.append((x * alphaA + (y * alphaB - x * alphaA) * t) / alpha)
      }
    }
    return Color(space: a.space, components: out, alpha: alpha, legacy: false)
  }

  // MARK: Conversion

  /// The colour in `space`. A hue that has no meaning (no chroma) comes out missing.
  public static func convert(_ color: Color, to space: Space) -> Color {
    if color.space == space { return color }
    var out: [Double]
    let direct = color.components.map { $0 ?? 0 }
    switch (color.space, space) {
    // Straight, without XYZ: hsl(120deg 100% 25%) is #008000 in Chrome, and through XYZ 0.5 came
    // back a hair under it and rounded to 7f.
    case (.hsl, .srgb): out = hslToSRGB(direct)
    case (.hwb, .srgb): out = hwbToSRGB(direct)
    case (.srgb, .hsl): out = srgbToHSL(direct)
    case (.srgb, .hwb): out = srgbToHWB(direct)
    case (.hsl, .hwb): out = srgbToHWB(hslToSRGB(direct))
    case (.hwb, .hsl): out = srgbToHSL(hwbToSRGB(direct))
    default: out = fromXYZD65(toXYZD65(color), space)
    }
    if let h = space.hueIndex {
      let chroma = space == .hsl ? out[1] : space == .hwb ? (100 - out[1] - out[2]) : out[1]
      if abs(chroma) < (space == .hsl || space == .hwb ? 1e-6 : 4e-5) { out[h] = .nan }
    }
    return Color(space: space, components: out.map { $0.isNaN ? nil : $0 }, alpha: color.alpha, legacy: false)
  }

  static func toXYZD65(_ color: Color) -> [Double] {
    let c = color.components.map { $0 ?? 0 }
    switch color.space {
    case .srgb: return mul(linSRGBToXYZ, c.map(srgbToLinear))
    case .srgbLinear: return mul(linSRGBToXYZ, c)
    case .displayP3: return mul(linP3ToXYZ, c.map(srgbToLinear))
    case .a98: return mul(linA98ToXYZ, c.map { sign($0) * pow(abs($0), 563 / 256) })
    case .prophoto: return mul(d50ToD65, mul(linProPhotoToXYZ, c.map(prophotoToLinear)))
    case .rec2020: return mul(lin2020ToXYZ, c.map(rec2020ToLinear))
    case .xyzD65: return c
    case .xyzD50: return mul(d50ToD65, c)
    case .lab: return mul(d50ToD65, labToXYZD50(c))
    case .lch: return mul(d50ToD65, labToXYZD50(polarToRect(c)))
    case .oklab: return oklabToXYZ(c)
    case .oklch: return oklabToXYZ(polarToRect(c))
    case .hsl: return mul(linSRGBToXYZ, hslToSRGB(c).map(srgbToLinear))
    case .hwb: return mul(linSRGBToXYZ, hwbToSRGB(c).map(srgbToLinear))
    }
  }

  static func fromXYZD65(_ xyz: [Double], _ space: Space) -> [Double] {
    switch space {
    case .srgb: return mul(xyzToLinSRGB, xyz).map(linearToSRGB)
    case .srgbLinear: return mul(xyzToLinSRGB, xyz)
    case .displayP3: return mul(inverse(linP3ToXYZ), xyz).map(linearToSRGB)
    case .a98: return mul(inverse(linA98ToXYZ), xyz).map { sign($0) * pow(abs($0), 256 / 563) }
    case .prophoto: return mul(inverse(linProPhotoToXYZ), mul(d65ToD50, xyz)).map(linearToProPhoto)
    case .rec2020: return mul(inverse(lin2020ToXYZ), xyz).map(linearToRec2020)
    case .xyzD65: return xyz
    case .xyzD50: return mul(d65ToD50, xyz)
    case .lab: return xyzD50ToLab(mul(d65ToD50, xyz))
    case .lch: return rectToPolar(xyzD50ToLab(mul(d65ToD50, xyz)))
    case .oklab: return xyzToOklab(xyz)
    case .oklch: return rectToPolar(xyzToOklab(xyz))
    case .hsl: return srgbToHSL(mul(xyzToLinSRGB, xyz).map(linearToSRGB))
    case .hwb: return srgbToHWB(mul(xyzToLinSRGB, xyz).map(linearToSRGB))
    }
  }

  static func sign(_ x: Double) -> Double { x < 0 ? -1 : 1 }

  static func srgbToLinear(_ v: Double) -> Double {
    abs(v) <= 0.04045 ? v / 12.92 : sign(v) * pow((abs(v) + 0.055) / 1.055, 2.4)
  }

  static func linearToSRGB(_ v: Double) -> Double {
    abs(v) > 0.0031308 ? sign(v) * (1.055 * pow(abs(v), 1 / 2.4) - 0.055) : 12.92 * v
  }

  static func prophotoToLinear(_ v: Double) -> Double {
    abs(v) <= 16.0 / 512 ? v / 16 : sign(v) * pow(abs(v), 1.8)
  }

  static func linearToProPhoto(_ v: Double) -> Double {
    abs(v) >= 1.0 / 512 ? sign(v) * pow(abs(v), 1 / 1.8) : 16 * v
  }

  static let rec2020Alpha = 1.09929682680944
  static let rec2020Beta = 0.018053968510807

  static func rec2020ToLinear(_ v: Double) -> Double {
    abs(v) < rec2020Beta * 4.5 ? v / 4.5 : sign(v) * pow((abs(v) + rec2020Alpha - 1) / rec2020Alpha, 1 / 0.45)
  }

  static func linearToRec2020(_ v: Double) -> Double {
    abs(v) > rec2020Beta ? sign(v) * (rec2020Alpha * pow(abs(v), 0.45) - (rec2020Alpha - 1)) : 4.5 * v
  }

  static func polarToRect(_ c: [Double]) -> [Double] {
    let h = c[2] * .pi / 180
    return [c[0], c[1] * cos(h), c[1] * sin(h)]
  }

  static func rectToPolar(_ c: [Double]) -> [Double] {
    var h = atan2(c[2], c[1]) * 180 / .pi
    if h < 0 { h += 360 }
    return [c[0], (c[1] * c[1] + c[2] * c[2]).squareRoot(), h]
  }

  static let d50White = [0.3457 / 0.3585, 1.0, (1.0 - 0.3457 - 0.3585) / 0.3585]
  static let labKappa = 24389.0 / 27
  static let labEpsilon = 216.0 / 24389

  static func labToXYZD50(_ lab: [Double]) -> [Double] {
    let f1 = (lab[0] + 16) / 116
    let f0 = lab[1] / 500 + f1
    let f2 = f1 - lab[2] / 200
    let x = pow(f0, 3) > labEpsilon ? pow(f0, 3) : (116 * f0 - 16) / labKappa
    let y = lab[0] > labKappa * labEpsilon ? pow((lab[0] + 16) / 116, 3) : lab[0] / labKappa
    let z = pow(f2, 3) > labEpsilon ? pow(f2, 3) : (116 * f2 - 16) / labKappa
    return [x * d50White[0], y * d50White[1], z * d50White[2]]
  }

  static func xyzD50ToLab(_ xyz: [Double]) -> [Double] {
    let f = zip(xyz, d50White).map { v, w -> Double in
      let x = v / w
      return x > labEpsilon ? cbrt(x) : (labKappa * x + 16) / 116
    }
    return [116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])]
  }

  static func oklabToXYZ(_ lab: [Double]) -> [Double] {
    mul(inverse(xyzToLMS), mul(inverse(lmsToOklab), lab).map { $0 * $0 * $0 })
  }

  static func xyzToOklab(_ xyz: [Double]) -> [Double] {
    mul(lmsToOklab, mul(xyzToLMS, xyz).map(cbrt))
  }

  static func hslToSRGB(_ c: [Double]) -> [Double] {
    let s = c[1] / 100, l = c[2] / 100
    func f(_ n: Double) -> Double {
      let k = (n + c[0] / 30).truncatingRemainder(dividingBy: 12)
      let a = s * min(l, 1 - l)
      return l - a * max(-1, min(k - 3, 9 - k, 1))
    }
    return [f(0), f(8), f(4)]
  }

  static func hslToSRGB32(_ h: Float, _ s: Float, _ l: Float) -> [Float] {
    if s == 0 { return [l, l, l] }
    func f(_ n: Float) -> Float {
      let k = fmodf(n + h / 30, 12)
      let a = s * min(l, 1 - l)
      return l - a * max(-1, min(k - 3, 9 - k, 1))
    }
    return [f(0), f(8), f(4)]
  }

  static func hwbToSRGB32(_ h: Float, _ w: Float, _ b: Float) -> [Float] {
    if w + b >= 1 {
      let gray = w / (w + b)
      return [gray, gray, gray]
    }
    return hslToSRGB32(h, 1, 0.5).map { $0 * (1 - w - b) + w }
  }

  static func hwbToSRGB(_ c: [Double]) -> [Double] {
    var w = c[1] / 100, b = c[2] / 100
    if w + b >= 1 {
      let gray = w / (w + b)
      return [gray, gray, gray]
    }
    let rgb = hslToSRGB([c[0], 100, 50])
    w = max(0, w); b = max(0, b)
    return rgb.map { $0 * (1 - w - b) + w }
  }

  static func srgbToHSL(_ rgb: [Double]) -> [Double] {
    let maxV = rgb.max()!, minV = rgb.min()!
    let l = (minV + maxV) / 2
    let d = maxV - minV
    var h = Double.nan, s = 0.0
    if d != 0 {
      s = (l == 0 || l == 1) ? 0 : (maxV - l) / min(l, 1 - l)
      switch maxV {
      case rgb[0]: h = (rgb[1] - rgb[2]) / d + (rgb[1] < rgb[2] ? 6 : 0)
      case rgb[1]: h = (rgb[2] - rgb[0]) / d + 2
      default: h = (rgb[0] - rgb[1]) / d + 4
      }
      h *= 60
    }
    return [h, s * 100, l * 100]
  }

  static func srgbToHWB(_ rgb: [Double]) -> [Double] {
    let hsl = srgbToHSL(rgb)
    return [hsl[0], rgb.min()! * 100, (1 - rgb.max()!) * 100]
  }

  // The matrices of CSS Color 4's sample code.
  static let linSRGBToXYZ: [[Double]] = [
    [506752 / 1228815, 87881 / 245763, 12673 / 70218],
    [87098 / 409605, 175762 / 245763, 12673 / 175545],
    [7918 / 409605, 87881 / 737289, 1001167 / 1053270]
  ]
  static let xyzToLinSRGB = inverse(linSRGBToXYZ)
  static let linP3ToXYZ: [[Double]] = [
    [608311 / 1250200, 189793 / 714400, 198249 / 1000160],
    [35783 / 156275, 247089 / 357200, 198249 / 2500400],
    [0, 32229 / 714400, 5220557 / 5000800]
  ]
  static let linA98ToXYZ: [[Double]] = [
    [573536 / 994567, 263643 / 1420810, 187206 / 994567],
    [591459 / 1989134, 6239551 / 9945670, 374412 / 4972835],
    [53769 / 1989134, 351524 / 4972835, 4929758 / 4972835]
  ]
  static let linProPhotoToXYZ: [[Double]] = [
    [0.79776664490064230, 0.13518129740053308, 0.03134773412839220],
    [0.28807482881940130, 0.71183523424187300, 0.00008993693872564],
    [0, 0, 0.82510460251046020]
  ]
  static let lin2020ToXYZ: [[Double]] = [
    [63426534 / 99577255, 20160776 / 139408157, 47086771 / 278816314],
    [26158966 / 99577255, 472592308 / 697040785, 8267143 / 139408157],
    [0, 19567812 / 697040785, 295819943 / 278816314]
  ]
  static let d50ToD65: [[Double]] = [
    [0.955473421488075, -0.02309845494876471, 0.06325924320057072],
    [-0.0283697093338637, 1.0099953980813041, 0.021041441191917323],
    [0.012314014864481998, -0.020507649298898964, 1.330365926242124]
  ]
  static let d65ToD50 = inverse(d50ToD65)
  static let xyzToLMS: [[Double]] = [
    [0.8190224379967030, 0.3619062600528904, -0.1288737815209879],
    [0.0329836539323885, 0.9292868615863434, 0.0361446663506424],
    [0.0481771893596242, 0.2642395317527308, 0.6335478284694309]
  ]
  static let lmsToOklab: [[Double]] = [
    [0.2104542683093140, 0.7936177747023054, -0.0040720430116193],
    [1.9779985324311684, -2.4285922420485799, 0.4505937096174110],
    [0.0259040424655478, 0.7827717124575296, -0.8086757549271372]
  ]

  static func mul(_ m: [[Double]], _ v: [Double]) -> [Double] {
    m.map { row in row[0] * v[0] + row[1] * v[1] + row[2] * v[2] }
  }

  static func inverse(_ m: [[Double]]) -> [[Double]] {
    let a = m[0][0], b = m[0][1], c = m[0][2], d = m[1][0], e = m[1][1], f = m[1][2], g = m[2][0], h = m[2][1], i = m[2][2]
    let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
    let det = a * A + b * B + c * C
    return [
      [A / det, -(b * i - c * h) / det, (b * f - c * e) / det],
      [B / det, (a * i - c * g) / det, -(a * f - c * d) / det],
      [C / det, -(a * h - b * g) / det, (a * e - b * d) / det]
    ]
  }

  // MARK: Names

  static let namedColors: [String: Int] = [
    "aliceblue": 0xf0f8ff, "antiquewhite": 0xfaebd7, "aqua": 0x00ffff, "aquamarine": 0x7fffd4, "azure": 0xf0ffff,
    "beige": 0xf5f5dc, "bisque": 0xffe4c4, "black": 0x000000, "blanchedalmond": 0xffebcd, "blue": 0x0000ff,
    "blueviolet": 0x8a2be2, "brown": 0xa52a2a, "burlywood": 0xdeb887, "cadetblue": 0x5f9ea0, "chartreuse": 0x7fff00,
    "chocolate": 0xd2691e, "coral": 0xff7f50, "cornflowerblue": 0x6495ed, "cornsilk": 0xfff8dc, "crimson": 0xdc143c,
    "cyan": 0x00ffff, "darkblue": 0x00008b, "darkcyan": 0x008b8b, "darkgoldenrod": 0xb8860b, "darkgray": 0xa9a9a9,
    "darkgreen": 0x006400, "darkgrey": 0xa9a9a9, "darkkhaki": 0xbdb76b, "darkmagenta": 0x8b008b, "darkolivegreen": 0x556b2f,
    "darkorange": 0xff8c00, "darkorchid": 0x9932cc, "darkred": 0x8b0000, "darksalmon": 0xe9967a, "darkseagreen": 0x8fbc8f,
    "darkslateblue": 0x483d8b, "darkslategray": 0x2f4f4f, "darkslategrey": 0x2f4f4f, "darkturquoise": 0x00ced1, "darkviolet": 0x9400d3,
    "deeppink": 0xff1493, "deepskyblue": 0x00bfff, "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1e90ff,
    "firebrick": 0xb22222, "floralwhite": 0xfffaf0, "forestgreen": 0x228b22, "fuchsia": 0xff00ff, "gainsboro": 0xdcdcdc,
    "ghostwhite": 0xf8f8ff, "gold": 0xffd700, "goldenrod": 0xdaa520, "gray": 0x808080, "green": 0x008000,
    "greenyellow": 0xadff2f, "grey": 0x808080, "honeydew": 0xf0fff0, "hotpink": 0xff69b4, "indianred": 0xcd5c5c,
    "indigo": 0x4b0082, "ivory": 0xfffff0, "khaki": 0xf0e68c, "lavender": 0xe6e6fa, "lavenderblush": 0xfff0f5,
    "lawngreen": 0x7cfc00, "lemonchiffon": 0xfffacd, "lightblue": 0xadd8e6, "lightcoral": 0xf08080, "lightcyan": 0xe0ffff,
    "lightgoldenrodyellow": 0xfafad2, "lightgray": 0xd3d3d3, "lightgreen": 0x90ee90, "lightgrey": 0xd3d3d3, "lightpink": 0xffb6c1,
    "lightsalmon": 0xffa07a, "lightseagreen": 0x20b2aa, "lightskyblue": 0x87cefa, "lightslategray": 0x778899, "lightslategrey": 0x778899,
    "lightsteelblue": 0xb0c4de, "lightyellow": 0xffffe0, "lime": 0x00ff00, "limegreen": 0x32cd32, "linen": 0xfaf0e6,
    "magenta": 0xff00ff, "maroon": 0x800000, "mediumaquamarine": 0x66cdaa, "mediumblue": 0x0000cd, "mediumorchid": 0xba55d3,
    "mediumpurple": 0x9370db, "mediumseagreen": 0x3cb371, "mediumslateblue": 0x7b68ee, "mediumspringgreen": 0x00fa9a, "mediumturquoise": 0x48d1cc,
    "mediumvioletred": 0xc71585, "midnightblue": 0x191970, "mintcream": 0xf5fffa, "mistyrose": 0xffe4e1, "moccasin": 0xffe4b5,
    "navajowhite": 0xffdead, "navy": 0x000080, "oldlace": 0xfdf5e6, "olive": 0x808000, "olivedrab": 0x6b8e23,
    "orange": 0xffa500, "orangered": 0xff4500, "orchid": 0xda70d6, "palegoldenrod": 0xeee8aa, "palegreen": 0x98fb98,
    "paleturquoise": 0xafeeee, "palevioletred": 0xdb7093, "papayawhip": 0xffefd5, "peachpuff": 0xffdab9, "peru": 0xcd853f,
    "pink": 0xffc0cb, "plum": 0xdda0dd, "powderblue": 0xb0e0e6, "purple": 0x800080, "rebeccapurple": 0x663399,
    "red": 0xff0000, "rosybrown": 0xbc8f8f, "royalblue": 0x4169e1, "saddlebrown": 0x8b4513, "salmon": 0xfa8072,
    "sandybrown": 0xf4a460, "seagreen": 0x2e8b57, "seashell": 0xfff5ee, "sienna": 0xa0522d, "silver": 0xc0c0c0,
    "skyblue": 0x87ceeb, "slateblue": 0x6a5acd, "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xfffafa,
    "springgreen": 0x00ff7f, "steelblue": 0x4682b4, "tan": 0xd2b48c, "teal": 0x008080, "thistle": 0xd8bfd8,
    "tomato": 0xff6347, "turquoise": 0x40e0d0, "violet": 0xee82ee, "wheat": 0xf5deb3, "white": 0xffffff,
    "whitesmoke": 0xf5f5f5, "yellow": 0xffff00, "yellowgreen": 0x9acd32
  ]
}
