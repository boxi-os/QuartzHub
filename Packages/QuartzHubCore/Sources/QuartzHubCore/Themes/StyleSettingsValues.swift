import Foundation

/// How a community theme's Style Settings value is written into quartz.config.yaml and read back:
/// a port of `src/routes/Styles/styleSettings.ts`, with the grouping of `StyleSettingsForm.tsx`.
/// Measured against QuartzControl's code (`scripts/style-settings-golden.mjs`).
///
/// What QuartzControl verified against `@quartz-themes/core`: the key is `<blockId>@@<settingId>`;
/// a boolean is a class toggle, a string naming a class key a class select, anything else is
/// emitted as `--<settingId>`; `@@light`/`@@dark` on the setting id scopes it to one mode. On top
/// sits Style Settings' own encoding: `hsl-split` is three variables, `rgb` wants `rgb(r, g, b)`.
public enum StyleSettingsValues {
  public enum Mode: String, Sendable { case light, dark }

  /// One field of a `StyleSettingsSchema` (`fields`), read from its JSON.
  public struct Field: Equatable, Sendable {
    public var object: JSONObject
    public init(_ object: JSONObject) { self.object = object }

    public var id: String { object["id"]?.stringValue ?? "" }
    public var blockId: String { object["blockId"]?.stringValue ?? "" }
    public var title: String { object["title"]?.stringValue ?? "" }
    public var description: String? { object["description"]?.stringValue }
    public var kind: String { object["kind"]?.stringValue ?? "" }
    public var format: String? { object["format"]?.stringValue }
    public var level: Double? { object["level"]?.numberValue }
    public var collapsed: Bool { object["collapsed"] == .bool(true) }
    public var defaultValue: JSONValue? { object["default"] }
    public var defaultLight: String? { object["defaultLight"]?.stringValue }
    public var defaultDark: String? { object["defaultDark"]?.stringValue }
    public var min: Double? { object["min"]?.numberValue }
    public var max: Double? { object["max"]?.numberValue }
    public var step: Double? { object["step"]?.numberValue }
    public var options: [(label: String, value: String)] {
      (object["options"]?.arrayValue ?? []).map { ($0["label"]?.stringValue ?? "", $0["value"]?.stringValue ?? "") }
    }

    var isThemedColor: Bool { kind == "variable-themed-color" }
    var isHslSplit: Bool { format == "hsl-split" }
  }

  public static func fields(_ schema: JSONValue?) -> [Field] {
    (schema?["fields"]?.arrayValue ?? []).compactMap { $0.objectValue.map(Field.init) }
  }

  // MARK: Keys

  public static func optionKey(_ field: Field, suffix: String? = nil, mode: Mode? = nil) -> String {
    let id = suffix.map { "\(field.id)\($0)" } ?? field.id
    return mode.map { "\(field.blockId)@@\(id)@@\($0.rawValue)" } ?? "\(field.blockId)@@\(id)"
  }

  /// Every key a field occupies, so a reset clears all of them (an hsl-split themed colour owns six).
  public static func keysOf(_ field: Field) -> [String] {
    let modes: [Mode?] = field.isThemedColor ? [.light, .dark] : [nil]
    let suffixes: [String?] = field.isHslSplit ? ["-h", "-s", "-l"] : [nil]
    var keys: [String] = []
    func add(_ key: String) { if !keys.contains(key) { keys.append(key) } }
    for mode in modes {
      for suffix in suffixes { add(optionKey(field, suffix: suffix, mode: mode)) }
      if field.isHslSplit { add(optionKey(field, mode: mode)) }
    }
    if field.isThemedColor { add(optionKey(field)) }
    return keys
  }

  // MARK: Writing a colour

  /// The pairs a picked colour turns into: three for hsl-split, both modes for a themed colour with
  /// no mode given.
  public static func colorEntries(_ field: Field, hex: String, mode: Mode? = nil) -> [(key: String, value: String)] {
    var entries: [(key: String, value: String)] = []
    func set(_ key: String, _ value: String) {
      if let index = entries.firstIndex(where: { $0.key == key }) { entries[index].value = value } else { entries.append((key, value)) }
    }
    let modes: [Mode?] = field.isThemedColor ? (mode.map { [$0] } ?? [.light, .dark]) : [nil]
    for m in modes {
      if field.isHslSplit {
        let hsl = CssVariables.hexToHsl(hex)
        set(optionKey(field, suffix: "-h", mode: m), JSJSON.numberToString(hsl.h))
        set(optionKey(field, suffix: "-s", mode: m), "\(JSJSON.numberToString(hsl.s))%")
        set(optionKey(field, suffix: "-l", mode: m), "\(JSJSON.numberToString(hsl.l))%")
        continue
      }
      set(optionKey(field, mode: m), formatColor(hex, field.format))
    }
    return entries
  }

  static func formatColor(_ hex: String, _ format: String?) -> String {
    guard let rgb = hexToRgb(hex) else { return hex }
    switch format {
    case "rgb": return "rgb(\(rgb.r), \(rgb.g), \(rgb.b))"
    case "rgb-split", "rgb-values": return "\(rgb.r), \(rgb.g), \(rgb.b)"
    case "hsl":
      let hsl = CssVariables.hexToHsl(hex)
      return "hsl(\(JSJSON.numberToString(hsl.h)), \(JSJSON.numberToString(hsl.s))%, \(JSJSON.numberToString(hsl.l))%)"
    case "hsl-values":
      let hsl = CssVariables.hexToHsl(hex)
      return "\(JSJSON.numberToString(hsl.h)), \(JSJSON.numberToString(hsl.s))%, \(JSJSON.numberToString(hsl.l))%"
    default: return hex
    }
  }

  // MARK: Colour arithmetic

  public static func hexToRgb(_ hex: String) -> (r: Int, g: Int, b: Int)? {
    guard let match = JSText.firstMatch(JS.trim(hex), #"\A#?([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})\z"#) else { return nil }
    return (Int(match.groups[1]!, radix: 16)!, Int(match.groups[2]!, radix: 16)!, Int(match.groups[3]!, radix: 16)!)
  }

  static func clampByte(_ value: Double) -> Int {
    // Math.max(0, Math.min(255, Math.round(value))): NaN stays NaN and prints as "NaN".
    Int(Swift.max(0, Swift.min(255, FontFile.jsRound(value))))
  }

  public static func rgbToHex(_ r: Double, _ g: Double, _ b: Double) -> String {
    "#" + [r, g, b].map { part in
      if part.isNaN { return "NaN" }
      return String(format: "%02x", clampByte(part))
    }.joined()
  }

  /// The inverse of Quartz's `hexToHsl`, for reading an hsl-split value back into a picker.
  public static func hslToHex(_ h: Double, _ s: Double, _ l: Double) -> String {
    let sat = s / 100, light = l / 100
    let c = (1 - abs(2 * light - 1)) * sat
    let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = light - c / 2
    let wrapped = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
    let table: [[Double]] = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]]
    let sector = wrapped.isNaN ? -1 : Int(wrapped.rounded(.down))
    let rgb = table.indices.contains(sector) ? table[sector] : [0, 0, 0]
    return rgbToHex((rgb[0] + m) * 255, (rgb[1] + m) * 255, (rgb[2] + m) * 255)
  }

  /// A stored colour as hex for the picker, in the notations Style Settings writes.
  static func parseColorValue(_ raw: JSONValue?, _ format: String?) -> String? {
    guard case .string(let text)? = raw, !JS.trim(text).isEmpty else { return nil }
    let value = JS.trim(text)
    if JSText.test(value, #"\A#([0-9a-fA-F]{3}){1,2}\z"#) {
      let chars = Array(value)
      if chars.count == 4 { return "#\(chars[1])\(chars[1])\(chars[2])\(chars[2])\(chars[3])\(chars[3])" }
      return value
    }
    let numbers = { (inner: String, dropPercent: Bool) -> [Double] in
      JSText.split(inner, ",").map { part in
        var p = JS.trim(part)
        if dropPercent, let range = p.range(of: "%") { p.removeSubrange(range) }
        return JS.toNumber(.string(p))
      }
    }
    let rgbInner = JSText.firstMatch(value, #"(?i)\Argba?\(([^)]+)\)\z"#)?.groups[1] ?? ((format?.hasPrefix("rgb") ?? false) ? value : nil)
    if let inner = rgbInner {
      let parts = numbers(inner, false)
      if parts.count >= 3, parts.prefix(3).allSatisfy({ !$0.isNaN }) { return rgbToHex(parts[0], parts[1], parts[2]) }
    }
    let hslInner = JSText.firstMatch(value, #"(?i)\Ahsla?\(([^)]+)\)\z"#)?.groups[1] ?? ((format?.hasPrefix("hsl") ?? false) ? value : nil)
    if let inner = hslInner {
      let parts = numbers(inner, true)
      if parts.count >= 3, parts.prefix(3).allSatisfy({ !$0.isNaN }) { return hslToHex(parts[0], parts[1], parts[2]) }
    }
    return nil
  }

  /// The colour stored for this field as hex, or the theme's own default when nothing is stored, so
  /// the picker opens on the colour that applies.
  public static func readColor(_ field: Field, values: JSONObject, mode: Mode? = nil) -> (hex: String?, isSet: Bool) {
    if field.isHslSplit {
      let parts = ["-h", "-s", "-l"].map { values[optionKey(field, suffix: $0, mode: mode)] }
      if parts.allSatisfy({ $0 != nil }) {
        let numbers = parts.map { part -> Double in
          var text = JS.string(part)
          if let range = text.range(of: "%") { text.removeSubrange(range) }
          return JS.toNumber(.string(text))
        }
        if numbers.allSatisfy({ !$0.isNaN }) { return (hslToHex(numbers[0], numbers[1], numbers[2]), true) }
      }
    } else if let parsed = parseColorValue(values[optionKey(field, mode: mode)], field.format) {
      return (parsed, true)
    }
    let fallback = mode == .dark ? field.defaultDark : mode == .light ? field.defaultLight : nil
    let raw = fallback ?? field.defaultValue?.stringValue
    return (parseColorValue(raw.map(JSONValue.string), field.format), false)
  }

  // MARK: Applying a patch

  /// One batched patch on `styleSettings`: an empty or missing value removes its key.
  public static func apply(_ patch: [(key: String, value: JSONValue?)], to settings: JSONObject) -> JSONObject {
    var next = settings
    for (key, value) in patch {
      if value == nil || value == .string("") { next[key] = nil } else { next[key] = value }
    }
    return next
  }

  // MARK: The form

  /// The fields worth a control: no unsupported ones, a class toggle only when the port ships its CSS.
  public static func usable(_ fields: [Field], shippedClassKeys: Set<String>) -> [Field] {
    fields.filter { field in
      if field.kind == "unsupported" { return false }
      if field.kind == "class-toggle" { return shippedClassKeys.contains(field.id) }
      return true
    }
  }

  /// A search keeps every heading, and the fields whose title, id or description holds it.
  public static func filter(_ fields: [Field], query: String) -> [Field] {
    let q = JS.trim(query).lowercased()
    guard !q.isEmpty else { return fields }
    return fields.filter { field in
      field.kind == "heading" || field.title.lowercased().contains(q) || field.id.lowercased().contains(q)
        || (field.description?.lowercased().contains(q) ?? false)
    }
  }

  public final class Group: Identifiable {
    public let heading: Field?
    public internal(set) var fields: [Field] = []
    public internal(set) var children: [Group] = []
    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(heading: Field?) { self.heading = heading }

    /// Recursive: a search that empties a section leaves sub-groups that are empty themselves.
    public var hasAnyField: Bool { !fields.isEmpty || children.contains { $0.hasAnyField } }
  }

  /// The theme author's headings and their levels are the grouping, as Style Settings renders it.
  public static func groups(_ fields: [Field]) -> [Group] {
    let root = Group(heading: nil)
    var stack: [(level: Double, group: Group)] = [(0, root)]
    for field in fields {
      if field.kind == "heading" {
        let level = field.level ?? 1
        while stack.count > 1 && stack[stack.count - 1].level >= level { stack.removeLast() }
        let group = Group(heading: field)
        stack[stack.count - 1].group.children.append(group)
        stack.append((level, group))
      } else {
        stack[stack.count - 1].group.fields.append(field)
      }
    }
    return root.children.isEmpty && root.fields.isEmpty ? [] : [root]
  }
}
