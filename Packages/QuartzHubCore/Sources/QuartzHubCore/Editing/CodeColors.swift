import Foundation

/// What the code editor colours, as roles over ranges; the app maps roles to system colours. In the
/// core because colouring, not the editor, is what costs per keystroke (4b) and is measured here
/// (CodeColorsTests).
///
/// Line by line: the editor recolours the paragraph it was typed in, so a rule never reaches over a
/// line break. An HTML comment or a fenced code block across lines is coloured line by line only
/// where its marks stand; CodeMirror, which QuartzControl's snippet editor used, parsed the whole
/// document. Later rules win over earlier ones.
public enum CodeColors {
  public enum Language: String, Sendable { case html, markdown }

  public enum Role: String, Sendable, CaseIterable {
    case tag, attribute, string, entity, comment, heading, strong, emphasis, code, link, marker, placeholder
  }

  public struct Span: Sendable, Equatable {
    public var range: NSRange
    public var role: Role
  }

  private struct Rule {
    var regex: NSRegularExpression
    var role: Role
    /// The capture group that is coloured; 0 for the whole match.
    var group = 0
  }

  private static func rule(_ pattern: String, _ role: Role, group: Int = 0) -> Rule {
    // swiftlint:disable:next force_try
    Rule(regex: try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]), role: role, group: group)
  }

  private static let tags: [Rule] = [
    // The closing ">" only after an opening on the same line: in prose a ">" is a ">".
    rule(#"</?[A-Za-z][\w:-]*|(?<=<[A-Za-z/][^<>\n]{0,500})/?>"#, .tag),
    rule(#"(?<=\s)[A-Za-z_:@][\w:.-]*(?=\s*=)"#, .attribute),
    rule(#"=\s*("[^"\n]*"|'[^'\n]*')"#, .string, group: 1),
    rule(#"&(?:#\d+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);"#, .entity),
    rule(#"<!--.*?(?:-->|$)|^(?:(?!<!--).)*?-->"#, .comment)
  ]

  /// layout-box's `{{…}}` tokens, last: they stand inside strings and links too.
  private static let placeholder = rule(#"\{\{[^{}\n]*\}\}"#, .placeholder)

  private static let rules: [Language: [Rule]] = [
    .html: tags + [placeholder],
    .markdown: [
      rule(#"^\s{0,3}(?:[-*+]|\d{1,9}[.)])(?=\s)"#, .marker),
      rule(#"^\s{0,3}>.*$"#, .comment),
      rule(#"(?<![*\w])\*(?!\s)[^*\n]+(?<!\s)\*(?!\*)|(?<![_\w])_(?!\s)[^_\n]+(?<!\s)_(?![_\w])"#, .emphasis),
      rule(#"\*\*(?!\s)[^*\n]+(?<!\s)\*\*|__(?!\s)[^_\n]+(?<!\s)__"#, .strong),
      rule(#"!?\[[^\]\n]*\]\([^)\n]*\)|<https?://[^>\s]*>"#, .link),
    ] + tags + [
      rule(#"`[^`\n]+`|^\s{0,3}(?:```|~~~).*$"#, .code),
      rule(#"^\s{0,3}#{1,6}(?:\s.*)?$"#, .heading),
      placeholder
    ]
  ]

  /// The spans in `range` of `text` (UTF-16 offsets, as NSTextStorage counts), widened by the
  /// caller to whole lines.
  public static func spans(_ text: String, in range: NSRange, language: Language) -> [Span] {
    var out: [Span] = []
    for rule in rules[language] ?? [] {
      rule.regex.enumerateMatches(in: text, range: range) { match, _, _ in
        guard let match else { return }
        let found = match.range(at: rule.group)
        if found.location != NSNotFound, found.length > 0 { out.append(Span(range: found, role: rule.role)) }
      }
    }
    return out
  }
}
