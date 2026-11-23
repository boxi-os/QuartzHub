import Foundation

/// Whether a selector of a core 3 theme sheet sets a variable for the whole page, and how strongly.
///
/// core 3 rewrites an Obsidian theme for Quartz and keeps its specificity (`convertObsidianCss`,
/// `:not(.qt-0)` as padding), so the variable table is not one `:root` rule as in core 2's
/// `theme.json` but rules like `body`, `:where(body)` and `:where(body):is([saved-theme=dark] *)`,
/// in that order of strength. Which value a page gets is the cascade on `<body>` (where the theme
/// declares) and, for what body does not declare, the inherited one of `<html>`.
///
/// This models just those two elements: `html` carries `saved-theme` and is `:root`, `body` is its
/// child, neither has a class or id. A selector using anything else (another pseudo-class, a
/// sibling combinator, another attribute) is not modelled and counts as matching nothing, so a rule
/// is counted only where the answer is certain.
enum ThemeSelector {
  enum Element { case html, body }

  /// (ids, classes/attributes/pseudo-classes, types), compared in that order.
  struct Specificity: Comparable, Equatable {
    var a = 0, b = 0, c = 0
    static func < (l: Specificity, r: Specificity) -> Bool { (l.a, l.b, l.c) < (r.a, r.b, r.c) }
    static func + (l: Specificity, r: Specificity) -> Specificity { Specificity(a: l.a + r.a, b: l.b + r.b, c: l.c + r.c) }
  }

  /// The specificity of the most specific selector of `list` that matches `element` in `mode`, or
  /// nil when none does.
  static func match(_ list: String, _ element: Element, mode: String) -> Specificity? {
    match(parse(list), element, mode: mode)
  }

  /// A selector list once, for asking it about both elements in both modes.
  static func parse(_ list: String) -> [[Part]] { splitTopLevel(list, ",").compactMap(parseComplex) }

  static func match(_ parsed: [[Part]], _ element: Element, mode: String) -> Specificity? {
    var best: Specificity?
    for complex in parsed where evaluate(complex, element, mode) == true {
      let s = specificity(complex)
      if best == nil || best! < s { best = s }
    }
    return best
  }

  // MARK: Parsing

  indirect enum Simple {
    case type(String), universal, cls(String), id(String)
    case attribute(name: String, value: String?, plain: Bool)
    case pseudo(String)
    case function(String, [[Part]])
    case pseudoElement
  }

  enum Part {
    case compound([Simple])
    case descendant, child, sibling
  }

  /// Splits at `separator` outside parentheses, brackets and strings.
  static func splitTopLevel(_ text: String, _ separator: Character) -> [String] {
    var out: [String] = []
    var current = ""
    var depth = 0
    var quote: Character?
    for ch in text {
      if let q = quote {
        current.append(ch)
        if ch == q { quote = nil }
        continue
      }
      switch ch {
      case "\"", "'": quote = ch
      case "(", "[": depth += 1
      case ")", "]": depth -= 1
      default:
        if ch == separator && depth == 0 { out.append(current); current = ""; continue }
      }
      current.append(ch)
    }
    out.append(current)
    return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  static func isNameChar(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "\\" || !ch.isASCII }

  /// A complex selector as compounds and combinators; nil for syntax this reader does not know.
  static func parseComplex(_ text: String) -> [Part]? {
    let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !chars.isEmpty else { return nil }
    var parts: [Part] = []
    var compound: [Simple] = []
    var pendingSpace = false
    var i = 0
    func name() -> String {
      var out = ""
      while i < chars.count, isNameChar(chars[i]) {
        if chars[i] == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
        out.append(chars[i]); i += 1
      }
      return out
    }
    /// The text up to the parenthesis that closes the one at `i`, `i` moved past it.
    func group(_ open: Character, _ close: Character) -> String? {
      var depth = 0
      var quote: Character?
      let start = i + 1
      while i < chars.count {
        let ch = chars[i]
        if let q = quote { if ch == q { quote = nil } }
        else if ch == "\"" || ch == "'" { quote = ch }
        else if ch == open { depth += 1 }
        else if ch == close { depth -= 1; if depth == 0 { let inner = String(chars[start..<i]); i += 1; return inner } }
        i += 1
      }
      return nil
    }
    func flush() -> Bool {
      guard !compound.isEmpty else { return false }
      parts.append(.compound(compound))
      compound = []
      return true
    }
    while i < chars.count {
      let ch = chars[i]
      if ch.isWhitespace { pendingSpace = true; i += 1; continue }
      if ch == ">" || ch == "+" || ch == "~" {
        guard flush() || (parts.last.map { if case .compound = $0 { true } else { false } } ?? false) else { return nil }
        parts.append(ch == ">" ? .child : .sibling)
        pendingSpace = false
        i += 1
        continue
      }
      if pendingSpace {
        if !compound.isEmpty { _ = flush(); parts.append(.descendant) }
        pendingSpace = false
      }
      switch ch {
      case "*": compound.append(.universal); i += 1
      case ".": i += 1; let n = name(); guard !n.isEmpty else { return nil }; compound.append(.cls(n))
      case "#": i += 1; let n = name(); guard !n.isEmpty else { return nil }; compound.append(.id(n))
      case "[":
        guard let inner = group("[", "]") else { return nil }
        guard let attribute = parseAttribute(inner) else { return nil }
        compound.append(attribute)
      case ":":
        i += 1
        if i < chars.count, chars[i] == ":" { i += 1; _ = name(); compound.append(.pseudoElement); continue }
        let n = name().lowercased()
        guard !n.isEmpty else { return nil }
        if i < chars.count, chars[i] == "(" {
          guard let inner = group("(", ")") else { return nil }
          var arguments: [[Part]] = []
          for piece in splitTopLevel(inner, ",") {
            // `:is()` and `:where()` forgive what they cannot parse; a `:not()` with it is unknown.
            guard let parsed = parseComplex(piece) else {
              if n == "where" || n == "is" { continue }
              return nil
            }
            arguments.append(parsed)
          }
          compound.append(.function(n, arguments))
        } else {
          compound.append(.pseudo(n))
        }
      default:
        let n = name()
        guard !n.isEmpty else { return nil }
        compound.append(.type(n.lowercased()))
      }
    }
    if !flush() {
      // A trailing combinator.
      if let last = parts.last, case .compound = last {} else { return nil }
    }
    return parts.isEmpty ? nil : parts
  }

  /// `[saved-theme=dark]`, `[saved-theme="dark"]`, `[saved-theme]`; other operators are not modelled.
  static func parseAttribute(_ inner: String) -> Simple? {
    let text = inner.trimmingCharacters(in: .whitespaces)
    guard let eq = text.firstIndex(of: "=") else {
      return JSText.test(text, #"\A[A-Za-z_-][A-Za-z0-9_-]*\z"#) ? .attribute(name: text.lowercased(), value: nil, plain: true) : nil
    }
    let name = text[..<eq].trimmingCharacters(in: .whitespaces)
    guard JSText.test(name, #"\A[A-Za-z_-][A-Za-z0-9_-]*\z"#) else { return .attribute(name: "", value: nil, plain: false) }
    var value = text[text.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    if JSText.test(value, #"\s[iIsS]\z"#) { value = String(value.dropLast(2)).trimmingCharacters(in: .whitespaces) }
    if value.count >= 2, let first = value.first, (first == "\"" || first == "'"), value.last == first { value = String(value.dropFirst().dropLast()) }
    return .attribute(name: name.lowercased(), value: value, plain: true)
  }

  // MARK: Matching

  static func parent(_ element: Element) -> Element? { element == .body ? .html : nil }

  /// true, false, or nil for what is not modelled.
  static func evaluate(_ complex: [Part], _ element: Element, _ mode: String) -> Bool? {
    guard case .compound(let last)? = complex.last else { return nil }
    guard let here = evaluateCompound(last, element, mode) else { return nil }
    guard here else { return false }
    let rest = Array(complex.dropLast())
    guard let combinator = rest.last else { return true }
    let before = Array(rest.dropLast())
    switch combinator {
    case .child:
      guard let up = parent(element) else { return false }
      return evaluate(before, up, mode)
    case .descendant:
      var up = parent(element)
      var unknown = false
      while let ancestor = up {
        switch evaluate(before, ancestor, mode) {
        case true?: return true
        case nil: unknown = true
        default: break
        }
        up = parent(ancestor)
      }
      return unknown ? nil : false
    default:
      return nil
    }
  }

  static func evaluateCompound(_ simples: [Simple], _ element: Element, _ mode: String) -> Bool? {
    var result: Bool? = true
    for simple in simples {
      let one: Bool?
      switch simple {
      case .universal: one = true
      case .type(let name): one = (name == "html" && element == .html) || (name == "body" && element == .body)
      case .cls, .id: one = false
      case .pseudoElement: one = false
      case .attribute(let name, let value, let plain):
        guard plain, name == "saved-theme" else { one = nil; break }
        one = element == .html && (value == nil || value == mode)
      case .pseudo(let name): one = name == "root" ? element == .html : nil
      case .function(let name, let arguments):
        let answers = arguments.map { evaluate($0, element, mode) }
        switch name {
        case "where", "is", "matches", "-webkit-any":
          one = answers.contains(true) ? true : (answers.contains { $0 == nil } ? nil : false)
        case "not":
          one = answers.contains(true) ? false : (answers.contains { $0 == nil } ? nil : true)
        default:
          one = nil
        }
      }
      if one == false { return false }
      if one == nil { result = nil }
    }
    return result
  }

  // MARK: Specificity

  static func specificity(_ complex: [Part]) -> Specificity {
    var total = Specificity()
    for part in complex {
      guard case .compound(let simples) = part else { continue }
      for simple in simples { total = total + specificity(simple) }
    }
    return total
  }

  static func specificity(_ simple: Simple) -> Specificity {
    switch simple {
    case .universal: return Specificity()
    case .type, .pseudoElement: return Specificity(c: 1)
    case .id: return Specificity(a: 1)
    case .cls, .attribute, .pseudo: return Specificity(b: 1)
    case .function(let name, let arguments):
      if name == "where" { return Specificity() }
      if ["is", "not", "matches", "-webkit-any"].contains(name) { return arguments.map(specificity).max() ?? Specificity() }
      return Specificity(b: 1)
    }
  }
}
