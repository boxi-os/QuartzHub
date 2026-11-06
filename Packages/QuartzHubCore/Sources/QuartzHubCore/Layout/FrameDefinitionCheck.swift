import Foundation

/// Why a frame definition cannot be written, or nil: a port of `frameDefinitionProblem` in
/// `layoutFrameService.ts`, with the zod schema it asked (`gridFrameDefinition` in
/// `electron/main/ipc/schemas.ts`, zod 4.4.3) written out as code.
///
/// This is the door every definition passes on its way to files, also one from a `.qtpl` that no
/// editor saw. An unchecked area name goes verbatim into `grid-template-areas`, a class name and
/// the module; an unchecked slot indexes the frame's `bySlot`. The answer is the *first* issue zod
/// reported, in the app's words: the path (each segment cut at 40 characters, because a key from
/// the file can be any length), a phrase per issue code and the number or list it carries. Then
/// the two checks no schema expresses: two areas with one name (CSS drops the whole
/// `grid-template-areas`) and two areas holding one group on one slot (rendered twice).
///
/// zod's order, measured with `scripts/layout-frames-golden.mjs`: an object's keys in the schema's
/// order; a string's type, then its checks as declared (`max` before `regex`); a number's type,
/// then "integer" (reported as a type issue), then the safe range, `min`, `max`; an array's
/// elements before its own `max`; a record's keys in JavaScript's order, a failing key reported as
/// `invalid_key` and its value then not looked at, `__proto__` skipped.
public enum FrameDefinitionCheck {
  public static func problem(_ raw: JSONValue?) -> String? {
    let def: JSONValue?
    do {
      def = try raw.map { try GridFrameCss.migrate($0) }
    } catch {
      return L10n.t("main.frameShapeInvalid", ["detail": String(describing: error)])
    }
    if let issue = first(def) {
      return L10n.t("main.frameShapeInvalid", ["detail": issue.sentence])
    }
    var names: Set<String> = [], groups: Set<String> = []
    for area in def?["areas"]?.arrayValue ?? [] {
      let name = area["name"]?.stringValue ?? ""
      if names.contains(name) { return L10n.t("main.frameAreaNameDuplicate", ["name": name]) }
      names.insert(name)
      guard let slot = area["slot"]?.stringValue, !slot.isEmpty, let group = area["group"]?.stringValue, !group.isEmpty else { continue }
      if !groups.insert("\(slot)\u{0}\(group)").inserted { return L10n.t("main.frameAreaGroupDuplicate", ["name": group]) }
    }
    return nil
  }

  // MARK: the issue

  struct Issue: Equatable {
    enum Code: Equatable { case type, tooBig(String), tooSmall(String), value([String]), format, key }
    var path: [String]
    var code: Code

    var sentence: String {
      let short = path.map { segment -> String in
        let units = Array(segment.utf16)
        return units.count > 40 ? String(decoding: units[..<40], as: UTF16.self) + "\u{2026}" : segment
      }
      let joined = short.joined(separator: ".")
      let at = joined.isEmpty ? "frame" : joined
      switch code {
      case .type: return L10n.t("main.frameIssueType", ["where": at])
      case .tooBig(let limit): return L10n.t("main.frameIssueTooBig", ["where": at, "limit": limit])
      case .tooSmall(let limit): return L10n.t("main.frameIssueTooSmall", ["where": at, "limit": limit])
      case .value(let values): return L10n.t("main.frameIssueValue", ["where": at, "values": values.joined(separator: ", ")])
      case .format: return L10n.t("main.frameIssueFormat", ["where": at])
      case .key: return L10n.t("main.frameIssueKey", ["where": at])
      }
    }

    func under(_ segment: String) -> Issue { Issue(path: [segment] + path, code: code) }
  }

  typealias Check = @Sendable (JSONValue?) -> Issue?

  static func first(_ def: JSONValue?) -> Issue? { frame(def) }

  // MARK: the schema

  static let positions = ["header", "left", "right", "beforeBody", "afterBody", "footer"]
  static let frameId = string(pattern: "^[A-Za-z0-9][A-Za-z0-9-]{0,63}$")
  static let cssIdent = string(pattern: "^[A-Za-z_][A-Za-z0-9_-]{0,63}$")
  static let track = string(max: 40, pattern: "^[A-Za-z0-9.%\(space)()+*/\\[\\]_-]*$")
  static let gap = string(max: 40, pattern: "^[A-Za-z0-9.%\(space)()+*/-]*$")
  static let lineName = string(pattern: "^[A-Za-z0-9_-]{1,40}$")
  static let count = integer(min: 1, max: 50)

  static let placement = object([
    ("row", count), ("col", count), ("rowSpan", count), ("colSpan", count), ("hidden", optional(boolean))
  ])

  static let lineNames = optional(record(key: string(pattern: "^[0-9]{1,3}$"), value: array(lineName, max: 8)))

  static let layout = object([
    ("rows", count), ("cols", count),
    ("columnSizes", optional(array(track, max: 50))), ("rowSizes", optional(array(track, max: 50))),
    ("rowGap", gap), ("columnGap", gap),
    ("maxWidth", optional(gap)), ("align", optional(enumeration(["left", "center", "right"]))),
    ("paddingBlock", optional(gap)), ("paddingInline", optional(gap)),
    ("columnLineNames", lineNames), ("rowLineNames", lineNames),
    ("placements", record(key: string(max: 128), value: placement))
  ])

  static let frame = object([
    ("id", frameId),
    ("frameName", string(min: 1, max: 120)),
    ("areas", array(object([
      ("id", string(max: 128)), ("name", cssIdent),
      ("slot", optional(enumeration(positions + ["pageBody"]))), ("group", optional(cssIdent))
    ]), max: 200)),
    ("breakpoints", object([("desktop", layout), ("tablet", layout), ("mobile", layout)]))
  ])

  // MARK: the parts zod is made of

  static func optional(_ check: @escaping Check) -> Check {
    { value in value == nil ? nil : check(value) }
  }

  static func object(_ shape: [(String, Check)]) -> Check {
    { value in
      guard case .object(let object)? = value else { return Issue(path: [], code: .type) }
      for (key, check) in shape {
        if let issue = check(object[key]) { return issue.under(key) }
      }
      return nil
    }
  }

  static func array(_ element: @escaping Check, max: Int) -> Check {
    { value in
      guard case .array(let items)? = value else { return Issue(path: [], code: .type) }
      for (index, item) in items.enumerated() {
        if let issue = element(item) { return issue.under(String(index)) }
      }
      return items.count > max ? Issue(path: [], code: .tooBig(String(max))) : nil
    }
  }

  static func record(key keyCheck: @escaping Check, value valueCheck: @escaping Check) -> Check {
    { value in
      guard case .object(let object)? = value else { return Issue(path: [], code: .type) }
      for key in object.keys where key != "__proto__" {
        if keyCheck(.string(key)) != nil { return Issue(path: [key], code: .key) }
        if let issue = valueCheck(object[key]) { return issue.under(key) }
      }
      return nil
    }
  }

  /// JavaScript's `\s`, spelled out: ICU's differs (no U+000B, no U+FEFF).
  static let space = #"\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}"#

  /// A JavaScript pattern without flags. Its `$` is the end of the input; ICU's `$` also matches
  /// before a final line break, so it becomes `\z`. Classes are spelled in ASCII (`[0-9]`, not
  /// `\d`, which ICU reads as every script's digits; no case folding, which in ICU would let the
  /// Kelvin sign through `[a-z]`).
  static func string(min: Int? = nil, max: Int? = nil, pattern: String? = nil) -> Check {
    let regex = pattern.map { pattern -> NSRegularExpression in
      let icu = pattern.hasSuffix("$") ? String(pattern.dropLast()) + #"\z"# : pattern
      return try! NSRegularExpression(pattern: icu)
    }
    return { value in
      guard case .string(let text)? = value else { return Issue(path: [], code: .type) }
      let length = text.utf16.count
      if let min, length < min { return Issue(path: [], code: .tooSmall(String(min))) }
      if let max, length > max { return Issue(path: [], code: .tooBig(String(max))) }
      if let regex, regex.firstMatch(in: text, range: NSRange(location: 0, length: length)) == nil {
        return Issue(path: [], code: .format)
      }
      return nil
    }
  }

  static func integer(min: Double, max: Double) -> Check {
    { value in
      guard case .number(let number)? = value, number.isFinite else { return Issue(path: [], code: .type) }
      guard number == number.rounded() else { return Issue(path: [], code: .type) }
      let safe = 9_007_199_254_740_991.0
      if number > safe { return Issue(path: [], code: .tooBig("9007199254740991")) }
      if number < -safe { return Issue(path: [], code: .tooSmall("-9007199254740991")) }
      if number < min { return Issue(path: [], code: .tooSmall(JSJSON.numberToString(min))) }
      if number > max { return Issue(path: [], code: .tooBig(JSJSON.numberToString(max))) }
      return nil
    }
  }

  static let boolean: Check = { value in
    if case .bool? = value { return nil }
    return Issue(path: [], code: .type)
  }

  static func enumeration(_ values: [String]) -> Check {
    { value in
      if case .string(let text)? = value, values.contains(text) { return nil }
      return Issue(path: [], code: .value(values))
    }
  }
}
