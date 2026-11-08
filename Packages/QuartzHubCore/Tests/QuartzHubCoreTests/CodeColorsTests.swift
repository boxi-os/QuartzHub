import Foundation
import Testing
@testable import QuartzHubCore

/// What the code editor colours in HTML and Markdown snippets, and what one keystroke costs.
@Suite struct CodeColorsTests {
  /// The coloured pieces of a line as "role:text", in rule order.
  static func pieces(_ text: String, _ language: CodeColors.Language) -> [String] {
    let ns = text as NSString
    return CodeColors.spans(text, in: NSRange(location: 0, length: ns.length), language: language)
      .map { "\($0.role.rawValue):\(ns.substring(with: $0.range))" }
  }

  @Test func html() {
    let line = #"<p class="hint" data-x='1'>Grüße &amp; {{root}}/static/a.png</p><!-- note -->"#
    let found = Self.pieces(line, .html)
    #expect(found.contains("tag:<p"))
    #expect(found.contains("tag:</p"))
    #expect(found.contains("attribute:class"))
    #expect(found.contains("attribute:data-x"))
    #expect(found.contains(#"string:"hint""#))
    #expect(found.contains("string:'1'"))
    #expect(found.contains("entity:&amp;"))
    #expect(found.contains("placeholder:{{root}}"))
    #expect(found.contains("comment:<!-- note -->"))
    // A comment's two ends on lines of their own are coloured where they stand.
    #expect(Self.pieces("<!-- open", .html) == ["comment:<!-- open"])
    #expect(Self.pieces("still -->", .html) == ["comment:still -->"])
    #expect(Self.pieces("plain text, no tag", .html).isEmpty)
  }

  @Test func markdown() {
    #expect(Self.pieces("## Über uns", .markdown) == ["heading:## Über uns"])
    #expect(Self.pieces("#hashtag", .markdown).isEmpty)
    #expect(Self.pieces("- item with `code`", .markdown) == ["marker:-", "code:`code`"])
    #expect(Self.pieces("1. first", .markdown) == ["marker:1."])
    #expect(Self.pieces("> quoted", .markdown) == ["comment:> quoted"])
    #expect(Self.pieces("a *soft* and **bold** word", .markdown) == ["emphasis:*soft*", "strong:**bold**"])
    #expect(Self.pieces("snake_case_name stays", .markdown).isEmpty)
    #expect(Self.pieces("![](<{{root}}/static/images/a.png>)", .markdown) == ["link:![](<{{root}}/static/images/a.png>)", "placeholder:{{root}}"])
    #expect(Self.pieces("[Start](https://example.org)", .markdown) == ["link:[Start](https://example.org)"])
    #expect(Self.pieces("```html", .markdown) == ["code:```html"])
    #expect(Self.pieces("<b>raw</b>", .markdown).contains("tag:<b"))
  }

  /// One keystroke recolours its line. Measured on a long snippet: the line in the middle of
  /// 5,000 lines, 2,000 times. The bound is far above the measurement, so a busy machine passes;
  /// what it catches is a rule that runs over the whole document.
  @Test func oneLineCostsLittle() {
    let line = #"<p class="x">Text mit **fett** und [Link](https://example.org) {{root}}/static/a.png &amp; `code`</p>"#
    let text = Array(repeating: line, count: 5000).joined(separator: "\n")
    let ns = text as NSString
    let middle = ns.paragraphRange(for: NSRange(location: ns.length / 2, length: 0))
    for language in [CodeColors.Language.html, .markdown] {
      let start = ContinuousClock.now
      var count = 0
      for _ in 0..<2000 { count += CodeColors.spans(text, in: middle, language: language).count }
      let each = (ContinuousClock.now - start) / 2000
      #expect(count > 0)
      #expect(each < .milliseconds(5), "\(language): \(each)")
    }
  }
}
