import Foundation

/// The `@font-face` rules of a stylesheet and the files they point at: a port of
/// `parseFontFaces`, `fontFileIn`, `projectFontsDir` and `allStylesheets` in `styleService.ts`.
public enum FontFaces {
  public struct Face: Equatable, Sendable {
    public var family: String
    public var weight: String
    public var style: String
    public var unicodeRange: String?
    /// The first url() of the rule, verbatim.
    public var url: String? { urls.first }
    /// Every url() of the whole body: a hand-written rule lists two or three formats, and the old
    /// "bulletproof" spelling writes two `src` declarations; asking only the first deleted a file
    /// the second was using.
    public var urls: [String]

    public var json: JSONValue {
      var pairs: [(String, JSONValue)] = [("family", .string(family)), ("weight", .string(weight)), ("style", .string(style))]
      if let unicodeRange { pairs.append(("unicodeRange", .string(unicodeRange))) }
      if let url { pairs.append(("url", .string(url))) }
      pairs.append(("urls", .array(urls.map { .string($0) })))
      return .object(JSONObject(pairs))
    }
  }

  /// A Sass interpolation `#{…}` inside the body is skipped over, so a `}` in it does not end the
  /// rule; each position matches exactly one branch, nothing to backtrack over.
  static let rulePattern = "@font-face[\(JSText.space)]*\\{((?:[^#}]|#(?!\\{)|#\\{[^}]*\\})*)\\}"

  /// `[fF][oO]…`: JavaScript's `i` flag on an ASCII word, which ICU's case folding would widen
  /// (U+017F long s matches "s" there).
  static func caseless(_ word: String) -> String {
    word.map { character -> String in
      let lower = character.lowercased(), upper = character.uppercased()
      if character.isASCII && character.isLetter && lower != upper { return "[\(lower)\(upper)]" }
      return NSRegularExpression.escapedPattern(for: String(character))
    }.joined()
  }

  static func declaration(_ body: String, _ property: String) -> String? {
    guard let match = JSText.firstMatch(body, "(?:\\A|;)[\(JSText.space)]*\(caseless(property))[\(JSText.space)]*:[\(JSText.space)]*([^;]+)"),
          let value = match.groups[1] else { return nil }
    return JSText.replaceAll(JS.trim(value), #"\A["']|["']\z"#, with: "")
  }

  public static func parse(_ content: String) -> [Face] {
    JSText.matches(content, rulePattern).compactMap { match in
      let body = match.groups[1] ?? ""
      guard let family = declaration(body, "font-family"), !family.isEmpty else { return nil }
      let urls = JSText.matches(body, "url\\([\(JSText.space)]*[\"']?([^\"')]+)[\"']?[\(JSText.space)]*\\)").map { $0.groups[1]! }
      return Face(family: family, weight: declaration(body, "font-weight") ?? "400", style: declaration(body, "font-style") ?? "normal",
                  unicodeRange: declaration(body, "unicode-range"), urls: urls)
    }
  }

  /// The families of a stylesheet, each once, in order.
  static func families(_ css: String) -> [String] {
    var out: [String] = []
    for face in parse(css) where !out.contains(face.family) { out.append(face.family) }
    return out
  }

  /// `quartz/static/fonts`: Quartz copies quartz/static/ into the build's static/.
  public static func projectFontsDirectory(_ project: String) -> String {
    "\(project)/quartz/static/fonts"
  }

  /// A face's file in `dir`, for the one URL shape both sources write, `…static/fonts/<file>`
  /// (the app relative, Quartz absolute on the baseUrl). Only a bare file name, so the answer
  /// cannot leave `dir`.
  public static func fileIn(_ dir: String, _ url: String?) -> String? {
    guard let url, !url.isEmpty,
          let match = JSText.firstMatch(url, #"(?:\A|/)static/fonts/([^/?#]+)(?:[?#][^\n\r\x{2028}\x{2029}]*)?\z"#),
          let encoded = match.groups[1], let name = try? JSURI.decodeComponent(encoded) else { return nil }
    if name != NodePath.basename(name) || JSText.startsWith(name, ".") || JSText.includes(name, "\\") { return nil }
    return NodePath.join(dir, name)
  }

  /// Every .scss/.css under quartz/styles, quartz/components/styles and quartz/static, at any
  /// depth up to six, through links: for "does a rule still point at this file" and "does
  /// anything still name this family", where finding too much is the safe side.
  public static func allStylesheets(project: String) -> [String] {
    var out: [String] = []
    func walk(_ dir: String, _ depth: Int) {
      guard depth <= 6, FileManager.default.fileExists(atPath: dir) else { return }
      for entry in LayoutFrames.directoryEntriesWithKind(dir) {
        let full = NodePath.join(dir, entry.name)
        var kind = entry.kind
        if kind == .link {
          var isDirectory: ObjCBool = false
          kind = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory) ? (isDirectory.boolValue ? .directory : .file) : .other
        }
        if kind == .directory { walk(full, depth + 1) }
        else if kind == .file && JSText.test(entry.name, #"\.(scss|css)\z"#) { out.append(full) }
      }
    }
    let root = project
    walk(NodePath.join(root, "quartz/styles"), 0)
    walk(NodePath.join(root, "quartz/components/styles"), 0)
    walk(NodePath.join(root, "quartz/static"), 0)
    return out
  }
}

/// JavaScript's `encodeURIComponent` and `decodeURIComponent`.
enum JSURI {
  struct Malformed: Error, CustomStringConvertible { var description: String { "URI malformed" } }

  static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()".utf8)

  static func encodeComponent(_ text: String) -> String {
    var out = ""
    for byte in text.utf8 {
      if unreserved.contains(byte) { out.unicodeScalars.append(Unicode.Scalar(byte)) } else { out += String(format: "%%%02X", byte) }
    }
    return out
  }

  /// Every escape decoded (also of reserved characters); a `%` without two hex digits, or bytes
  /// that are no UTF-8, throw as JavaScript's URIError does.
  static func decodeComponent(_ text: String) throws -> String {
    let units = Array(text.utf16)
    var out: [UInt16] = []
    var i = 0
    func hexByte(_ at: Int) throws -> UInt8 {
      guard at + 2 < units.count, units[at] == 0x25, let high = hex(units[at + 1]), let low = hex(units[at + 2]) else { throw Malformed() }
      return high << 4 | low
    }
    while i < units.count {
      guard units[i] == 0x25 else { out.append(units[i]); i += 1; continue }
      let first = try hexByte(i)
      i += 3
      if first < 0x80 { out.append(UInt16(first)); continue }
      let count: Int
      switch first {
      case 0xC0...0xDF: count = 2
      case 0xE0...0xEF: count = 3
      case 0xF0...0xF7: count = 4
      default: throw Malformed()
      }
      var bytes = [first]
      for _ in 1..<count {
        let next = try hexByte(i)
        guard next & 0xC0 == 0x80 else { throw Malformed() }
        bytes.append(next)
        i += 3
      }
      guard let scalar = String(validating: bytes, as: UTF8.self)?.unicodeScalars.first, String(scalar).utf8.count == count else { throw Malformed() }
      out.append(contentsOf: String(scalar).utf16)
    }
    return String(decoding: out, as: UTF16.self)
  }

  static func hex(_ unit: UInt16) -> UInt8? {
    switch unit {
    case 0x30...0x39: UInt8(unit - 0x30)
    case 0x41...0x46: UInt8(unit - 0x41 + 10)
    case 0x61...0x66: UInt8(unit - 0x61 + 10)
    default: nil
    }
  }
}
