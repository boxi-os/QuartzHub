import Foundation

/// `qh-check handbook`: what the handbook quotes from QuartzHub, against the catalog, in the
/// language of the page. Successor of QuartzControl's `check:handbook`, which checked block quotes;
/// this handbook quotes inline instead, so three things are looked at:
///
/// 1. Quotes, „…“ on a German page and “…” on an English one. Each must be a text of the catalog,
///    a sentence or part of one, or else stand in the vault's exception list with its reason (a
///    text of macOS, of Quartz or of a plugin; an example value). A quote that QuartzHub no longer
///    says is worse than none: it looks like evidence.
/// 2. Paths with ▸ in bold (**Projekt ▸ Snapshot anlegen**): every step a text of the catalog,
///    or excepted.
/// 3. Any other bold, which is a button's name as often as emphasis: only a near miss counts, bold
///    that is almost a text of the catalog but not quite (**In den Vorrat ziehen** where the button
///    says „In den Vorrat legen“). That is what a renamed button leaves behind.
///
/// Compared after normalising as QuartzControl did: without placeholders, numbers, quotation marks,
/// emphasis, punctuation and case, because a quote may shorten and fill in example values. A quote
/// may also leave a gap with „…“ or <…>. An exception that matches nothing any more is a finding
/// too, so the list does not hide a quote that later becomes wrong.
public struct HandbookQuoteCheck: Sendable {
  public enum Kind: String, Sendable { case quote, path, nearMiss, staleException }

  public struct Finding: Sendable, Equatable {
    public var file: String
    public var line: Int
    public var kind: Kind
    public var language: String
    public var text: String
    /// For a near miss: the catalog's text it resembles.
    public var resembles: String?
  }

  public struct Report: Sendable {
    public var findings: [Finding] = []
    public var quotes = 0
    public var paths = 0
    public var bold = 0
    public var files = 0
  }

  /// One excepted text per line: language, a space, the text as the handbook has it, then
  /// optionally " # " and the reason. Lines starting with # are comments.
  public struct Exception: Sendable, Equatable {
    public var language: String
    public var text: String
    public var line: Int
  }

  public static let exceptionsFile = "private/zitat-ausnahmen.txt"
  /// Not part of the site (the project's ignorePatterns), so not part of the check either.
  static let skippedFolders: Set<String> = ["private", "templates", "assets"]
  /// A bold text this close to a catalog text, and not equal, is a near miss.
  static let nearMissRatio = 0.85

  // MARK: - Running

  public static func run(catalog: StringCatalog, vault: String) throws -> Report {
    let matchers = Dictionary(uniqueKeysWithValues: ["de", "en"].map { ($0, Matcher(texts: texts(catalog, $0))) })
    let exceptionsPath = "\(vault)/\(exceptionsFile)"
    let exceptions = FileManager.default.fileExists(atPath: exceptionsPath)
      ? parseExceptions(String(decoding: try Posix.read(exceptionsPath), as: UTF8.self)) : []
    var used = Set<Int>()
    var report = Report()
    for relative in markdownFiles(vault) {
      let language = relative.hasPrefix("en/") ? "en" : "de"
      let text = String(decoding: try Posix.read("\(vault)/\(relative)"), as: UTF8.self)
      report.files += 1
      for item in extract(text, language: language) {
        let matcher = matchers[language]!
        let excepted = exceptions.firstIndex { $0.language == language && normalize($0.text) == normalize(item.text) }
        switch item.kind {
        case .quote:
          report.quotes += 1
          if matcher.says(item.text) { continue }
          if let excepted { used.insert(excepted); continue }
          report.findings.append(Finding(file: relative, line: item.line, kind: .quote, language: language, text: item.text))
        case .path:
          report.paths += 1
          let steps = item.text.components(separatedBy: "▸").map { $0.trimmingCharacters(in: .whitespaces) }
          var bad = false
          for step in steps where !matcher.says(step) {
            if let index = exceptions.firstIndex(where: { $0.language == language && normalize($0.text) == normalize(step) }) {
              used.insert(index)
            } else {
              bad = true
            }
          }
          if bad { report.findings.append(Finding(file: relative, line: item.line, kind: .path, language: language, text: item.text)) }
        case .nearMiss, .staleException:
          report.bold += 1
          if matcher.says(item.text) { continue }
          guard let near = matcher.nearMiss(item.text) else { continue }
          if let excepted { used.insert(excepted); continue }
          report.findings.append(Finding(file: relative, line: item.line, kind: .nearMiss, language: language, text: item.text, resembles: near))
        }
      }
    }
    for (index, exception) in exceptions.enumerated() where !used.contains(index) {
      report.findings.append(Finding(file: exceptionsFile, line: exception.line, kind: .staleException,
                                     language: exception.language, text: exception.text))
    }
    return report
  }

  static func texts(_ catalog: StringCatalog, _ language: String) -> [String] {
    catalog.entries.values.flatMap { byLanguage -> [String] in
      switch byLanguage[language] {
      case .text(let text): [text]
      case .plural(let forms): Array(forms.values)
      case nil: []
      }
    }
  }

  static func markdownFiles(_ vault: String) -> [String] {
    let all = (try? FileManager.default.subpathsOfDirectory(atPath: vault)) ?? []
    return all.filter { path in
      path.hasSuffix(".md") && !path.split(separator: "/").contains { $0.hasPrefix(".") || skippedFolders.contains(String($0)) }
    }.sorted()
  }

  static func parseExceptions(_ text: String) -> [Exception] {
    text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, raw in
      var line = String(raw)
      if let hash = line.range(of: " # ") { line = String(line[..<hash.lowerBound]) }
      line = line.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#"), let space = line.firstIndex(of: " ") else { return nil }
      let language = String(line[..<space])
      guard language == "de" || language == "en" else { return nil }
      return Exception(language: language, text: String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces),
                       line: index + 1)
    }
  }

  // MARK: - Reading the handbook

  struct Item: Equatable {
    var kind: Kind  // .quote, .path, or .nearMiss for any other bold
    var text: String
    var line: Int
  }

  /// Quotes and bold of one page, without frontmatter, code and links.
  static func extract(_ markdown: String, language: String) -> [Item] {
    var items: [Item] = []
    var inFence = false
    var inFrontmatter = false
    let (open, close): (Character, Character) = language == "de" ? ("„", "“") : ("“", "”")
    for (index, raw) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      if index == 0, trimmed == "---" { inFrontmatter = true; continue }
      if inFrontmatter { if trimmed == "---" { inFrontmatter = false }; continue }
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
      if inFence { continue }
      let line = clean(String(raw))
      // Bold first; quotes inside bold belong to it.
      var boldRanges: [Range<String.Index>] = []
      var search = line.startIndex
      while let start = line.range(of: "**", range: search ..< line.endIndex),
            let end = line.range(of: "**", range: start.upperBound ..< line.endIndex) {
        let inner = String(line[start.upperBound ..< end.lowerBound])
        if !inner.trimmingCharacters(in: .whitespaces).isEmpty {
          items.append(Item(kind: inner.contains("▸") ? .path : .nearMiss, text: inner, line: index + 1))
        }
        boldRanges.append(start.lowerBound ..< end.upperBound)
        search = end.upperBound
      }
      var position = line.startIndex
      while let start = line[position...].firstIndex(of: open),
            let end = line[line.index(after: start)...].firstIndex(of: close) {
        let inner = String(line[line.index(after: start) ..< end])
        if !boldRanges.contains(where: { $0.contains(start) }), !inner.isEmpty {
          items.append(Item(kind: .quote, text: inner, line: index + 1))
        }
        position = line.index(after: end)
      }
    }
    return items
  }

  /// Inline code, wikilinks, embeds and Markdown links go: they are names and addresses, not text
  /// of the app.
  static func clean(_ line: String) -> String {
    var out = line
    for pattern in [#"`[^`]*`"#, #"!?\[\[[^\]]*\]\]"#, #"\]\([^)]*\)"#] {
      out = out.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }
    return out
  }

  // MARK: - Comparing

  /// Placeholders and gaps become this, so they survive normalising.
  static let gap = "\u{E000}"

  static func normalize(_ text: String) -> String {
    var s = text
    s = s.replacingOccurrences(of: #"\{\{[^}]+\}\}|<[^>]+>|…|\.\.\."#, with: gap, options: .regularExpression)
    s = s.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: "[„“”\"‘’'«»‚]", with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: "[–—]", with: "-", options: .regularExpression)
    s = s.replacingOccurrences(of: #"[0-9]+"#, with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: #"[.,:;!?()\[\]+→←]"#, with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: " ?\(gap) ?", with: gap, options: .regularExpression)
    return s.trimmingCharacters(in: .whitespaces).lowercased()
  }

  /// The catalog of one language, ready to answer whether it says a text.
  struct Matcher {
    /// Whole texts and their parts (sentences, the text before a parenthesis, the pieces between
    /// placeholders, the steps of a path), normalised, without gaps.
    let parts: Set<String>
    /// Whole texts and sentences with a gap where a placeholder was, as anchored patterns.
    let patterns: [(literal: String, regex: NSRegularExpression)]
    /// Every text, normalised, for a long quote taken from the middle of one.
    let wholes: [String]
    /// The parts by length, for near misses.
    let shortParts: [String]

    init(texts: [String]) {
      var parts = Set<String>()
      var patterns: [(String, NSRegularExpression)] = []
      var wholes: [String] = []
      for text in texts {
        let whole = HandbookQuoteCheck.normalize(text)
        wholes.append(whole)
        let sentences = text.replacingOccurrences(of: #"(?<=[.!?:])\s+|\s\(|\s[–—]\s|·|▸"#, with: "\n", options: .regularExpression)
          .components(separatedBy: "\n")
        for piece in [text] + sentences {
          let normal = HandbookQuoteCheck.normalize(piece)
          // A text that is mostly placeholder ("{{name}}", "{{count}} s") would match anything.
          let literal = normal.replacingOccurrences(of: HandbookQuoteCheck.gap, with: "").replacingOccurrences(of: " ", with: "")
          if normal.contains(HandbookQuoteCheck.gap), literal.count >= 4 {
            let pattern = "^" + NSRegularExpression.escapedPattern(for: normal)
              .replacingOccurrences(of: HandbookQuoteCheck.gap, with: ".*") + "$"
            if let regex = try? NSRegularExpression(pattern: pattern) {
              let literal = normal.components(separatedBy: HandbookQuoteCheck.gap).max { $0.count < $1.count } ?? ""
              patterns.append((literal.trimmingCharacters(in: .whitespaces), regex))
            }
          }
          for bit in normal.components(separatedBy: HandbookQuoteCheck.gap) {
            let bit = bit.trimmingCharacters(in: .whitespaces)
            if !bit.isEmpty { parts.insert(bit) }
          }
        }
      }
      self.parts = parts
      self.patterns = patterns
      self.wholes = wholes
      shortParts = parts.filter { $0.count <= 60 }.sorted()
    }

    func says(_ text: String) -> Bool {
      let quote = HandbookQuoteCheck.normalize(text)
      if quote.isEmpty || parts.contains(quote) { return true }
      if quote.contains(HandbookQuoteCheck.gap) {
        // The handbook left a gap: its pieces, in order, in one text.
        let pieces = quote.components(separatedBy: HandbookQuoteCheck.gap).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return true }
        return wholes.contains { whole in
          var rest = whole[...]
          for piece in pieces {
            guard let found = rest.range(of: piece) else { return false }
            rest = rest[found.upperBound...]
          }
          return true
        }
      }
      let range = NSRange(quote.startIndex..., in: quote)
      for (literal, regex) in patterns where quote.contains(literal) {
        if regex.firstMatch(in: quote, range: range) != nil { return true }
      }
      // A long quote may come from the middle of a text.
      return quote.count >= 25 && wholes.contains { $0.replacingOccurrences(of: HandbookQuoteCheck.gap, with: " ").contains(quote) }
    }

    /// The catalog part a bold text almost is, if there is one.
    func nearMiss(_ text: String) -> String? {
      let bold = HandbookQuoteCheck.normalize(text)
      guard bold.count >= 8, bold.count <= 60, !bold.contains(HandbookQuoteCheck.gap) else { return nil }
      let a = Array(bold)
      var best: (distance: Int, part: String)?
      for part in shortParts where abs(part.count - a.count) <= a.count / 4 + 1 {
        let d = HandbookQuoteCheck.distance(a, Array(part))
        if d > 0, d < (best?.distance ?? .max) { best = (d, part) }
      }
      guard let best else { return nil }
      let ratio = 1 - Double(best.distance) / Double(max(a.count, best.part.count))
      return ratio >= HandbookQuoteCheck.nearMissRatio ? best.part : nil
    }
  }

  static func distance(_ a: [Character], _ b: [Character]) -> Int {
    var previous = Array(0 ... b.count)
    for i in 1 ... max(a.count, 1) where !a.isEmpty {
      var current = [i] + Array(repeating: 0, count: b.count)
      for j in stride(from: 1, through: b.count, by: 1) {
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
      }
      previous = current
    }
    return a.isEmpty ? b.count : previous[b.count]
  }
}
