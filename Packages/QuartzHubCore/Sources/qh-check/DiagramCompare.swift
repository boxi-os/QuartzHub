import Foundation

/// Mermaid lays a diagram out by measuring its text in the engine, so its SVG cannot be the same in
/// WebKit and Chrome (measured 2026-11-08 on Example's six diagram pages: same elements in the same
/// order and the same text, coordinates up to a few hundred px apart where one measured label moves
/// the layout, numbers and CSS serialized each engine's way). Its id carries `Date.now()`
/// (`…-svg0-mermaid-1794156291286`). What `qh-check export-pages` compares there is the structure:
/// the elements in order and the text; everything outside a diagram stays character for character.
enum DiagramCompare {
  /// A Mermaid SVG: the only one with `aria-roledescription` on its root.
  static let diagram = try! NSRegularExpression(pattern: #"<svg(?=[^>]*aria-roledescription)[^>]*>[\s\S]*?</svg>"#)
  static let stamp = try! NSRegularExpression(pattern: #"mermaid-[0-9]{10,}"#)
  static let tag = try! NSRegularExpression(pattern: #"<[A-Za-z][\w:-]*"#)
  static let style = try! NSRegularExpression(pattern: #"<style[\s\S]*?</style>"#)
  static let markup = try! NSRegularExpression(pattern: #"<[^>]*>"#)

  struct Split: Equatable {
    /// The text with each diagram replaced by `<svg data-diagram/>` and Mermaid's time stamps fixed.
    var outside: String
    /// Each diagram as it was (stamps fixed).
    var diagrams: [String]
  }

  static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
    re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
  }

  static func split(_ html: String) -> Split {
    let text = replace(stamp, in: html, with: "mermaid-T")
    let found = diagram.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
    return Split(outside: replace(diagram, in: text, with: "<svg data-diagram/>"), diagrams: found)
  }

  /// What is the same in both engines: the elements in order and the text between them.
  static func shape(_ svg: String) -> String {
    let tags = tag.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)).map { String(svg[Range($0.range, in: svg)!]) }.joined(separator: ",")
    let text = replace(markup, in: replace(style, in: svg, with: ""), with: "|")
    return tags + "\n" + text.split(separator: "|", omittingEmptySubsequences: true).joined(separator: "|")
  }

  enum Outcome: Equatable {
    /// Character for character, after the stamps.
    case equal
    /// Outside the diagrams equal; every diagram the same in structure, `n` not in bytes.
    case sameShape(Int)
    case different
  }

  static func compare(_ a: String, _ b: String) -> Outcome {
    let x = split(a), y = split(b)
    if x == y { return .equal }
    guard x.outside == y.outside, x.diagrams.count == y.diagrams.count,
          zip(x.diagrams, y.diagrams).allSatisfy({ shape($0) == shape($1) }) else { return .different }
    return .sameShape(zip(x.diagrams, y.diagrams).filter { $0 != $1 }.count)
  }

  /// Where two texts that compare `.different` part: outside the diagrams by character, else the
  /// first diagram whose structure differs. nil when they compare alike.
  static func locate(_ a: String, _ b: String) -> String? {
    let x = split(a), y = split(b)
    if x.outside != y.outside {
      let n = at(x.outside, y.outside)
      return "außerhalb der Diagramme bei Zeichen \(n): WebKit …\(window(x.outside, n))… Chrome …\(window(y.outside, n))…"
    }
    if x.diagrams.count != y.diagrams.count { return "\(x.diagrams.count) Diagramme statt \(y.diagrams.count)" }
    for (i, (p, q)) in zip(x.diagrams, y.diagrams).enumerated() where shape(p) != shape(q) {
      let s = shape(p), t = shape(q)
      return "Diagramm \(i + 1) im Aufbau bei Zeichen \(at(s, t)): WebKit …\(window(s, at(s, t)))… Chrome …\(window(t, at(s, t)))…"
    }
    return nil
  }

  static func at(_ a: String, _ b: String) -> Int { zip(a, b).prefix { $0 == $1 }.count }
  static func window(_ text: String, _ at: Int) -> String { String(text.dropFirst(max(0, at - 60)).prefix(160)) }
}
