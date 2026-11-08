import Foundation

/// A repository's README read into blocks the Marktplatz shows natively, never as HTML
/// (QuartzControl's `components/ReadmeText.tsx`, measured against it in ReadmeTextTests).
///
/// The text comes from GitHub, written by whoever owns the repository: so this reads the few
/// Markdown forms a plugin README is made of (headings, paragraphs, lists, fenced code, tables,
/// inline code, bold and links) and drops what it does not read. Raw HTML tags lose their
/// brackets, an image says its alt text.
///
/// Matched as JavaScript matches: UTF-16 offsets, JavaScript's `\s` and `.` spelled out (ICU's
/// differ on U+000B, U+FEFF and U+0085), and `$` as the end of the line only.
public enum ReadmeText {
  public indirect enum Inline: Sendable, Equatable {
    case text(String)
    case code(String)
    case strong(String)
    /// An image: its alt text, shown in brackets. An image without alt text is dropped.
    case image(String)
    /// `href` nil: a link to an anchor or another scheme, shown as its words only.
    case link(href: String?, [Inline])
  }

  public enum Block: Sendable, Equatable {
    case paragraph([Inline])
    case heading(level: Int, [Inline])
    case code(String)
    /// A table as its rows, without the separator row, shown as monospaced text.
    case table(String)
    case list(ordered: Bool, [[Inline]])
  }

  /// Longer than this (UTF-16 units), a paragraph is plain text. Each `[` can make the link pattern
  /// read to the end of the paragraph, so a paragraph of unclosed links costs its length squared
  /// (QuartzControl measured 120 KB at over a second).
  public static let inlineLimit = 4000

  // JavaScript's `\s` and `.`, for ICU.
  private static let wsChars = #"\t\n\u000B\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF"#
  private static let ws = "[\(wsChars)]"
  private static let dot = #"[^\n\r\u2028\u2029]"#
  private static let end = #"(?![\s\S])"#

  private static func regex(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern)
  }

  private static let inlinePattern = regex(
    #"!\[([^\]]*)\]\([^)]*\)|`([^`]+)`|\[([^\]]+)\]\(([^)\#(wsChars)]+)(?:\#(ws)[^)]*)?\)|\*\*([^*]+)\*\*|__([^_]+)__"#)
  private static let fence = regex("^\(ws)*(```|~~~)")
  private static let heading = regex("^(#{1,6})\(ws)+(\(dot)*?)\(ws)*#*\(ws)*\(end)")
  private static let tableRow = regex(#"^\#(ws)*\|"#)
  private static let tableSeparator = regex(#"^\#(ws)*\|[\#(wsChars):|-]+\|?\#(ws)*\#(end)"#)
  private static let listItem = regex("^\(ws)*([-*+]|[0-9]+[.)])\(ws)+(\(dot)*)\(end)")
  private static let indented = regex("^\(ws){2,}")
  private static let rule = regex(#"^\#(ws)*([-*_])(?:\#(ws)*\1){2,}\#(ws)*\#(end)"#)
  private static let quote = regex(#"^\#(ws)*>\#(ws)?"#)
  private static let absolute = regex("^https?://", options: .caseInsensitive)
  private static let scheme = regex("^[a-z]+:", options: .caseInsensitive)

  private static func regex(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: options)
  }

  public static func blocks(_ text: String, repoUrl: String) -> [Block] {
    let cleaned = stripTags(stripComments(text))
      .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let lines = cleaned.components(separatedBy: "\n")
    var blocks: [Block] = []
    var paragraph: [String] = []
    func flush() {
      guard !paragraph.isEmpty else { return }
      blocks.append(.paragraph(inline(paragraph.joined(separator: " "), repoUrl: repoUrl)))
      paragraph = []
    }
    var i = 0
    while i < lines.count {
      let line = lines[i]
      if let match = first(fence, line) {
        flush()
        let marker = group(match, 1, line)!
        var code: [String] = []
        i += 1
        while i < lines.count, !trimStart(lines[i]).hasPrefix(marker) {
          code.append(lines[i])
          i += 1
        }
        i += 1
        blocks.append(.code(code.joined(separator: "\n")))
        continue
      }
      if let match = first(heading, line) {
        flush()
        let level = group(match, 1, line)!.utf16.count
        blocks.append(.heading(level: level, inline(group(match, 2, line) ?? "", repoUrl: repoUrl)))
        i += 1
        continue
      }
      if first(tableRow, line) != nil {
        flush()
        var rows: [String] = []
        while i < lines.count, first(tableRow, lines[i]) != nil {
          if first(tableSeparator, lines[i]) == nil { rows.append(trim(lines[i])) }
          i += 1
        }
        blocks.append(.table(rows.joined(separator: "\n")))
        continue
      }
      if let match = first(listItem, line) {
        flush()
        let ordered = group(match, 1, line)!.unicodeScalars.contains { ("0"..."9").contains($0) }
        var items: [String] = []
        while i < lines.count {
          let current = lines[i]
          if let next = first(listItem, current) {
            items.append(group(next, 2, current) ?? "")
          } else if !trim(current).isEmpty, first(indented, current) != nil, !items.isEmpty {
            items[items.count - 1] += " " + trim(current)
          } else {
            break
          }
          i += 1
        }
        blocks.append(.list(ordered: ordered, items.map { inline($0, repoUrl: repoUrl) }))
        continue
      }
      if first(rule, line) != nil || trim(line).isEmpty {
        flush()
        i += 1
        continue
      }
      let unquoted = quote.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: line.utf16.count), withTemplate: "")
      paragraph.append(trim(unquoted))
      i += 1
    }
    flush()
    return blocks
  }

  /// Images first (their alt text stays), then code, links and bold, left to right.
  public static func inline(_ text: String, repoUrl: String) -> [Inline] {
    let units = text.utf16.count
    if units > inlineLimit { return [.text(text)] }
    let ns = text as NSString
    var out: [Inline] = []
    var last = 0
    for match in inlinePattern.matches(in: text, range: NSRange(location: 0, length: units)) {
      if match.range.location > last { out.append(.text(ns.substring(with: NSRange(location: last, length: match.range.location - last)))) }
      if let alt = group(match, 1, text) {
        if !alt.isEmpty { out.append(.image(alt)) }
      } else if let code = group(match, 2, text) {
        out.append(.code(code))
      } else if let words = group(match, 3, text) {
        out.append(.link(href: resolveHref(group(match, 4, text) ?? "", repoUrl: repoUrl), inline(words, repoUrl: repoUrl)))
      } else {
        out.append(.strong(group(match, 5, text) ?? group(match, 6, text) ?? ""))
      }
      last = match.range.location + match.range.length
    }
    if last < units { out.append(.text(ns.substring(from: last))) }
    return out
  }

  /// Where a relative link points: the file in the repository on github.com. nil for an anchor or
  /// another scheme. Not a file path.
  public static func resolveHref(_ href: String, repoUrl: String) -> String? {
    if first(absolute, href) != nil { return href }
    if href.hasPrefix("#") || first(scheme, href) != nil { return nil }
    let base = repoUrl.hasSuffix("/") ? String(repoUrl.dropLast()) : repoUrl
    var path = href
    if path.hasPrefix("./") { path.removeFirst(2) } else if path.hasPrefix("/") { path.removeFirst() }
    return "\(base)/blob/HEAD/\(path)"
  }

  // MARK: HTML away

  /// `text.replace(/<!--[\s\S]*?-->/g, '')` in one pass: the regex read to the end once per
  /// unclosed `<!--`.
  public static func stripComments(_ text: String) -> String {
    let u = Array(text.utf16)
    var out: [UInt16] = []
    out.reserveCapacity(u.count)
    var i = 0
    while true {
      guard let open = find(u, Array("<!--".utf16), from: i), let close = find(u, Array("-->".utf16), from: open + 4) else { break }
      out += u[i..<open]
      i = close + 3
    }
    out += u[i...]
    return String(decoding: out, as: UTF16.self)
  }

  /// `text.replace(/<[^>\n]+>/g, '')` the same way: a `<` whose line has no `>` after it skips the line.
  public static func stripTags(_ text: String) -> String {
    let u = Array(text.utf16)
    let lt = UInt16(UInt8(ascii: "<")), gt = UInt16(UInt8(ascii: ">")), nl = UInt16(UInt8(ascii: "\n"))
    var out: [UInt16] = []
    out.reserveCapacity(u.count)
    var i = 0
    var close = -1
    while true {
      guard let open = u[i...].firstIndex(of: lt) else { break }
      if close <= open { close = u[(open + 1)...].firstIndex(of: gt) ?? -1 }
      if close < 0 { break }
      let eol = u[(open + 1)...].firstIndex(of: nl) ?? -1
      if eol >= 0, eol < close {
        out += u[i...eol]
        i = eol + 1
      } else if close == open + 1 {
        out += u[i...open]
        i = open + 1
      } else {
        out += u[i..<open]
        i = close + 1
      }
    }
    out += u[i...]
    return String(decoding: out, as: UTF16.self)
  }

  // MARK: plumbing

  private static func find(_ haystack: [UInt16], _ needle: [UInt16], from start: Int) -> Int? {
    guard start <= haystack.count - needle.count else { return nil }
    var i = start
    while i <= haystack.count - needle.count {
      if haystack[i] == needle[0], haystack[i..<(i + needle.count)].elementsEqual(needle) { return i }
      i += 1
    }
    return nil
  }

  private static func first(_ regex: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
    regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count))
  }

  private static func group(_ match: NSTextCheckingResult, _ index: Int, _ text: String) -> String? {
    let range = match.range(at: index)
    return range.location == NSNotFound ? nil : (text as NSString).substring(with: range)
  }

  /// JavaScript's whitespace and line terminators, which `trim()` takes away.
  private static func isSpace(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
    default: false
    }
  }

  static func trim(_ text: String) -> String {
    let u = Array(text.utf16)
    guard let start = u.firstIndex(where: { !isSpace($0) }) else { return "" }
    let stop = u.lastIndex(where: { !isSpace($0) })!
    return String(decoding: u[start...stop], as: UTF16.self)
  }

  static func trimStart(_ text: String) -> String {
    let u = Array(text.utf16)
    guard let start = u.firstIndex(where: { !isSpace($0) }) else { return "" }
    return String(decoding: u[start...], as: UTF16.self)
  }
}
