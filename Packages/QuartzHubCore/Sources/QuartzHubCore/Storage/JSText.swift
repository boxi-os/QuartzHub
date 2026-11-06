import Foundation
import Synchronization

/// JavaScript's string operations, for ports that cut and search text the way QuartzControl did:
/// offsets in UTF-16 code units (`indexOf`, `slice`), and regular expressions written so that ICU
/// matches what V8 matches.
///
/// Swift's own `String` searches by Character, and "\r\n" is one Character: a search for "\n" in a
/// file with Windows line ends finds nothing there, where JavaScript finds every one. NSString
/// works in UTF-16 like JavaScript. The patterns passed to `regex` are written in ICU syntax with
/// JavaScript's meaning: `JSText.space` for `\s`, ASCII classes for `\w` and `\d`, `\z` for an
/// unflagged `$`, `lineStart` for `^` under the `m` flag (ICU would also break lines at U+0085).
enum JSText {
  /// JavaScript's `\s`, as the inside of a character class.
  static let space = #"\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}"#
  /// `^` with the `m` flag: the start of the text or after \n, \r, U+2028, U+2029.
  static let lineStart = #"(?:\A|(?<=[\n\r\x{2028}\x{2029}]))"#
  /// `\w`.
  static let word = "A-Za-z0-9_"

  static func length(_ text: String) -> Int { text.utf16.count }

  static func indexOf(_ text: String, _ needle: String, from: Int = 0) -> Int? {
    let ns = text as NSString
    guard from <= ns.length else { return nil }
    let found = ns.range(of: needle, options: .literal, range: NSRange(location: from, length: ns.length - from))
    return found.location == NSNotFound ? nil : found.location
  }

  /// `text.slice(from, to)` for offsets inside the text.
  static func slice(_ text: String, _ from: Int, _ to: Int? = nil) -> String {
    let ns = text as NSString
    let start = max(0, min(from, ns.length)), end = max(start, min(to ?? ns.length, ns.length))
    return ns.substring(with: NSRange(location: start, length: end - start))
  }

  private static let cache = Mutex<[String: NSRegularExpression]>([:])

  static func regex(_ pattern: String) -> NSRegularExpression {
    if let cached = cache.withLock({ $0[pattern] }) { return cached }
    let compiled = try! NSRegularExpression(pattern: pattern)
    cache.withLock { $0[pattern] = compiled }
    return compiled
  }

  static func test(_ text: String, _ pattern: String) -> Bool {
    regex(pattern).firstMatch(in: text, range: NSRange(location: 0, length: length(text))) != nil
  }

  /// `text.replace(/pattern/g, replacement)` with a literal replacement.
  static func replaceAll(_ text: String, _ pattern: String, with replacement: String) -> String {
    regex(pattern).stringByReplacingMatches(in: text, range: NSRange(location: 0, length: length(text)),
                                            withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
  }

  /// `text.replace(/pattern/g, template)` where the template uses `$1`.
  static func replaceAll(_ text: String, _ pattern: String, template: String) -> String {
    regex(pattern).stringByReplacingMatches(in: text, range: NSRange(location: 0, length: length(text)), withTemplate: template)
  }

  struct Match {
    let range: NSRange
    /// Group 0 is the whole match; nil for a group that did not take part.
    let groups: [String?]
    var index: Int { range.location }
    var end: Int { range.location + range.length }
  }

  static func matches(_ text: String, _ pattern: String) -> [Match] {
    let ns = text as NSString
    return regex(pattern).matches(in: text, range: NSRange(location: 0, length: ns.length)).map { result in
      Match(range: result.range, groups: (0..<result.numberOfRanges).map { index in
        let range = result.range(at: index)
        return range.location == NSNotFound ? nil : ns.substring(with: range)
      })
    }
  }

  static func firstMatch(_ text: String, _ pattern: String) -> Match? {
    let ns = text as NSString
    guard let result = regex(pattern).firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return Match(range: result.range, groups: (0..<result.numberOfRanges).map { index in
      let range = result.range(at: index)
      return range.location == NSNotFound ? nil : ns.substring(with: range)
    })
  }

  /// `text.includes(needle)`, in UTF-16 (Swift's `contains` compares Characters: "/" followed by
  /// a combining mark is no "/" there).
  static func includes(_ text: String, _ needle: String) -> Bool { indexOf(text, needle) != nil }

  /// `text.startsWith(prefix)` and `endsWith`, in UTF-16.
  static func startsWith(_ text: String, _ prefix: String) -> Bool { Array(text.utf16).starts(with: prefix.utf16) }
  static func endsWith(_ text: String, _ suffix: String) -> Bool { Array(text.utf16).reversed().starts(with: Array(suffix.utf16).reversed()) }

  /// `text.split(separator)` with a string separator, in UTF-16.
  static func split(_ text: String, _ separator: String) -> [String] {
    (text as NSString).components(separatedBy: separator)
  }
}
