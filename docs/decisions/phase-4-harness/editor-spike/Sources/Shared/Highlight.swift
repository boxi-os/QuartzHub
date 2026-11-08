import AppKit

/// Spike highlighter: regexes over a range, colours as attributes. Order matters: later wins.
public enum SCSSHighlight {
  nonisolated(unsafe) static let rules: [(NSRegularExpression, NSColor)] = ([
    (#"[.#&]?[a-zA-Z_-][\w-]*(?=[^{};]*\{)"#, .systemPurple),     // selector-ish
    (#"[a-zA-Z-]+(?=\s*:[^:])"#, .systemBlue),                     // property
    (#"@[\w-]+"#, .systemPink),                                    // at-rule
    (#"\$[\w-]+"#, .systemTeal),                                   // variable
    (#"-?\d*\.?\d+(px|rem|em|%|vh|vw|s|ms|deg)?\b"#, .systemOrange),
    (#"#[0-9a-fA-F]{3,8}\b"#, .systemOrange),
    (#""[^"\n]*"|'[^'\n]*'"#, .systemRed),
    (#"//[^\n]*|/\*[\s\S]*?\*/"#, .secondaryLabelColor),
  ] as [(String, NSColor)]).map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

  /// Paragraph range of `range`, widened to whole lines; block comments across lines are not
  /// handled incrementally in the spike.
  public static func apply(to storage: NSTextStorage, range: NSRange) {
    let text = storage.string as NSString
    let r = text.paragraphRange(for: range)
    storage.beginEditing()
    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: r)
    for (regex, color) in rules {
      regex.enumerateMatches(in: storage.string, range: r) { m, _, _ in
        if let m { storage.addAttribute(.foregroundColor, value: color, range: m.range) }
      }
    }
    storage.endEditing()
  }

  public static func spans(_ string: String, range: NSRange) -> [(NSRange, NSColor)] {
    var out: [(NSRange, NSColor)] = []
    for (regex, color) in rules {
      regex.enumerateMatches(in: string, range: range) { m, _, _ in if let m { out.append((m.range, color)) } }
    }
    return out
  }
}

public func ms(_ start: ContinuousClock.Instant) -> String {
  let d = ContinuousClock.now - start
  return String(format: "%.1f ms", Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000)
}
