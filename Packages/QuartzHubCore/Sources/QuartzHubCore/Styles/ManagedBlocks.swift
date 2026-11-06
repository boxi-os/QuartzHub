import Foundation

/// The blocks QuartzControl keeps in a project's stylesheets, between marker comments: a port of
/// the text half of `styleService.ts` (the load order `imports`, `fonts`, `google-fonts`,
/// `css-vars`, and the template's `imported-styles`). Every offset is a UTF-16 offset and every
/// search literal (`JSText`), because the texts are cut exactly where QuartzControl cut them.
///
/// The marker names are a format both apps read: `QuartzControl` is written, `Quartz-GUI` (the
/// working title until 2026-09-18) is read too. Where both copies of a block stand, both are read
/// in file order and the later one wins, as in the browser; the next write puts the union where the
/// first copy stood and removes the others. A build from before the rename sees none of the
/// renamed blocks; QuartzControl accepted that price (styles-and-fonts.md, `MARKER_NAMES`).
public enum ManagedBlocks {
  static let names = ["QuartzControl", "Quartz-GUI"]
  /// The blocks that moved to `_quartzcontrol.scss` in 1.1, in the order they are written there.
  public static let movedMarkers = ["imports", "fonts", "google-fonts", "css-vars"]

  public static func markers(_ id: String, name: String = "QuartzControl") -> (start: String, end: String) {
    ("/* --- \(name):managed:\(id):start --- */", "/* --- \(name):managed:\(id):end --- */")
  }

  struct Span: Equatable {
    /// Where the start marker begins and where the end marker ends (UTF-16).
    var from: Int
    var to: Int
    var body: String
  }

  /// A block under one of `names`, the current name first; an unterminated start is no block.
  static func findBlock(_ content: String, _ id: String, names: [String] = names, from offset: Int = 0) -> Span? {
    for name in names {
      let (start, end) = markers(id, name: name)
      guard let startAt = JSText.indexOf(content, start, from: offset) else { continue }
      guard let endAt = JSText.indexOf(content, end, from: startAt) else { continue }
      return Span(from: startAt, to: endAt + JSText.length(end),
                  body: JSText.slice(content, startAt + JSText.length(start), endAt))
    }
    return nil
  }

  /// Every copy under one name. A copy nested in one of the same name is no copy: the outer start
  /// pairs with the inner end, and the outer end is left over (a merge artefact one write heals).
  static func copies(_ content: String, _ id: String, _ name: String) -> [Span] {
    var spans: [Span] = []
    var from = 0
    while let span = findBlock(content, id, names: [name], from: from) {
      spans.append(span)
      from = span.to
    }
    return spans
  }

  /// Every copy of a block in file order; one nested in another is part of that one's body (where
  /// beta.2 put its imports block inside QuartzControl's).
  static func findBlocks(_ content: String, _ id: String) -> [Span] {
    let spans = names.flatMap { copies(content, id, $0) }
    let outer = spans.enumerated().filter { index, span in
      !spans.enumerated().contains { other, candidate in other != index && candidate.from < span.from && span.to <= candidate.to }
    }.map(\.element)
    var sorted = outer
    JS.sort(&sorted) { Double($0.from - $1.from) }
    return sorted
  }

  /// Cuts a span out and closes the gap there, and only there: a blank line elsewhere is the user's.
  static func cutSpan(_ content: String, from: Int, to: Int) -> String {
    let before = JSText.replaceAll(JSText.slice(content, 0, from), #"\n+\z"#, with: "")
    let after = JSText.replaceAll(JSText.slice(content, to), #"\A\n+"#, with: "")
    if before.isEmpty { return after }
    if after.isEmpty { return before + "\n" }
    return before + "\n\n" + after
  }

  /// `block` over the first copy, the others removed: the first is the one the file was arranged
  /// around. From the end backwards, so the earlier offsets hold.
  static func replaceBlocks(_ content: String, _ spans: [Span], _ block: String) -> String {
    var next = content
    for (index, span) in spans.enumerated().reversed() {
      next = index == 0
        ? JSText.slice(next, 0, span.from) + block + JSText.slice(next, span.to)
        : cutSpan(next, from: span.from, to: span.to)
    }
    return next
  }

  /// The old name on every block that has no copy under the new one; only the two marker comments
  /// change.
  static func renameLegacyMarkers(_ content: String) -> String {
    let current = names[0]
    var next = content
    for name in names.dropFirst() {
      let escaped = NSRegularExpression.escapedPattern(for: name)
      var ids: [String] = []
      for match in JSText.matches(next, #"/\* --- "# + escaped + #":managed:([A-Za-z0-9_-]+):start --- \*/"#) {
        if let id = match.groups[1], !ids.contains(id) { ids.append(id) }
      }
      for id in ids {
        guard findBlock(next, id, names: [name]) != nil, findBlock(next, id, names: [current]) == nil else { continue }
        let old = markers(id, name: name), renamed = markers(id, name: current)
        next = (next as NSString).replacingOccurrences(of: old.start, with: renamed.start, options: .literal, range: NSRange(location: 0, length: JSText.length(next)))
        next = (next as NSString).replacingOccurrences(of: old.end, with: renamed.end, options: .literal, range: NSRange(location: 0, length: JSText.length(next)))
      }
    }
    return next
  }

  // MARK: rules

  /// The rules of a rules-only block (the `@font-face` rules of `fonts`): everything up to a
  /// closing brace at depth 0, comments in front included, trimmed.
  public static func splitRules(_ body: String) -> [String] {
    let units = Array(body.utf16)
    var out: [String] = []
    func keep(_ from: Int, _ to: Int) {
      let trimmed = JS.trim(String(decoding: units[from..<to], as: UTF16.self))
      if !trimmed.isEmpty { out.append(trimmed) }
    }
    var depth = 0, start = 0
    for index in units.indices {
      if units[index] == 0x7B { depth += 1 }
      else if units[index] == 0x7D && depth > 0 {
        depth -= 1
        if depth == 0 {
          keep(start, index + 1)
          start = index + 1
        }
      }
    }
    keep(start, units.count)
    return out
  }

  /// The bodies of a rules-only block, each rule once (the same text up to whitespace).
  public static func joinUniqueRules(_ bodies: [String]) -> String {
    var seen: Set<String> = []
    var out: [String] = []
    for chunk in bodies.flatMap(splitRules) {
      let key = JSText.replaceAll(chunk, "[\(JSText.space)]+", with: " ")
      if seen.insert(key).inserted { out.append(chunk) }
    }
    return out.joined(separator: "\n\n")
  }

  /// A font under the site's own static/fonts, addressed relative to the stylesheet: Quartz
  /// compiles custom.scss into the one index.css at the root, so `static/fonts/x` finds the file on
  /// every page and under a sub-path, where `/static/fonts/x` found nothing (QuartzControl measured
  /// a 404 on its own handbook).
  public static func relativeFontUrls(_ css: String) -> String {
    JSText.replaceAll(css, #"url\(["# + JSText.space + #"]*(["']?)/static/fonts/"#, template: "url($1static/fonts/")
  }

  /// What every write does on the way: the new marker name, and relative font URLs in `fonts`.
  static func migrateOnWrite(_ content: String) -> String {
    var out = renameLegacyMarkers(content)
    for span in findBlocks(out, "fonts").reversed() {
      out = JSText.slice(out, 0, span.from) + relativeFontUrls(JSText.slice(out, span.from, span.to)) + JSText.slice(out, span.to)
    }
    return out
  }

  // MARK: one block

  /// Every copy's body, trimmed, the empty ones left out, joined; nil when there is no copy.
  public static func body(_ content: String, _ id: String) -> String? {
    let spans = findBlocks(content, id)
    guard !spans.isEmpty else { return nil }
    return spans.map { JS.trim($0.body) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  /// The block with a new body, where it stands, or appended at the end.
  public static func upsert(_ content: String, _ id: String, _ body: String) -> String {
    let (start, end) = markers(id)
    let block = "\(start)\n\(body)\n\(end)"
    let spans = findBlocks(content, id)
    if spans.isEmpty {
      let trimmed = JSText.replaceAll(content, "[\(JSText.space)]+\\z", with: "")
      return migrateOnWrite(trimmed.isEmpty ? "\(block)\n" : "\(trimmed)\n\n\(block)\n")
    }
    return migrateOnWrite(replaceBlocks(content, spans, block))
  }

  /// The text without the block, under either name, every copy.
  public static func strip(_ content: String, _ id: String) -> String {
    guard let span = findBlock(content, id) else { return content }
    return strip(cutSpan(content, from: span.from, to: span.to), id)
  }

  // MARK: the load order

  /// After the leading `@charset`/`@use`/`@forward` lines (Quartz's own `@use "./variables.scss"
  /// as *;` among them), because Sass refuses a `@use` after a rule; in a file without them, after
  /// the leading comments.
  static func insertBeforeRules(_ content: String, _ text: String) -> String {
    var lines = JSText.split(content, "\n")
    var cursor = 0, insertAt = 0, inComment = false
    for (index, raw) in lines.enumerated() {
      let line = JS.trim(raw)
      if inComment {
        if JSText.includes(line, "*/") { inComment = false }
        cursor = index + 1
        continue
      }
      if line.isEmpty || JSText.startsWith(line, "//") {
        cursor = index + 1
        continue
      }
      if JSText.startsWith(line, "/*") {
        inComment = !JSText.includes(line, "*/")
        cursor = index + 1
        continue
      }
      if JSText.test(line, #"\A@(charset|use|forward)(?![A-Za-z0-9_])"#) {
        cursor = index + 1
        insertAt = cursor
        continue
      }
      break
    }
    if insertAt == 0 { insertAt = cursor }
    lines.insert(contentsOf: ["", text], at: insertAt)
    return JSText.replaceAll(lines.joined(separator: "\n"), #"\n{3,}"#, with: "\n\n")
  }

  /// The load-order block: in place, removed when empty, or inserted before the first rule.
  static func upsertImportBlock(_ content: String, _ body: String) -> String {
    let (start, end) = markers("imports")
    let spans = findBlocks(content, "imports")
    if !spans.isEmpty {
      if body.isEmpty { return migrateOnWrite(strip(content, "imports")) }
      return migrateOnWrite(replaceBlocks(content, spans, "\(start)\n\(body)\n\(end)"))
    }
    if body.isEmpty { return content }
    return migrateOnWrite(insertBeforeRules(content, "\(start)\n\(body)\n\(end)"))
  }

  // MARK: the line that loads _quartzcontrol.scss

  public static let managedFile = "_quartzcontrol.scss"
  public static let managedUseLine = #"@use "./quartzcontrol";"#
  /// Any spelling Sass reads as the same module: with or without underscore and extension, either
  /// quote, with an `as` of its own.
  static let managedUsePattern = JSText.lineStart + "[ \\t]*@use[\(JSText.space)]+([\"'])\\./_?quartzcontrol(?:\\.scss)?\\1(?:[\(JSText.space)]+as[\(JSText.space)]+[A-Za-z0-9_*-]+)?[\(JSText.space)]*;"
  /// The head of a new `_quartzcontrol.scss`. Kept as QuartzControl wrote it: both apps read the
  /// file, and a header that changes with the app that wrote it would be a change on every switch.
  public static let managedFileHeader = """
    // Maintained by QuartzControl and loaded by custom.scss with `\(managedUseLine)`.
    // The blocks between QuartzControl markers are rewritten by the app (Styles page: load order,
    // fonts, variables). Text outside them is kept.

    """

  public static func hasManagedUse(_ custom: String) -> Bool {
    JSText.test(custom, managedUsePattern)
  }

  /// custom.scss without the line, for a template package: a 1.0.x app importing it would point at
  /// a file it never writes.
  public static func stripManagedUse(_ custom: String) -> String {
    guard let match = JSText.firstMatch(custom, managedUsePattern) else { return custom }
    return cutSpan(custom, from: match.index, to: match.end)
  }

  public static func ensureManagedUse(_ custom: String) -> String {
    hasManagedUse(custom) ? custom : insertBeforeRules(custom, managedUseLine)
  }
}
