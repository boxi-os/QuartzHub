import AppKit
import Foundation
import PDFKit

/// What the PDF says about itself (`PdfMeta`).
public struct PdfMeta: Sendable {
  public var title: String
  public var subtitle: String
  public var author: String
  public var keywords: [String]
  public var lang: String

  public init(title: String, subtitle: String, author: String, keywords: [String], lang: String) {
    self.title = title
    self.subtitle = subtitle
    self.author = author
    self.keywords = keywords
    self.lang = lang
  }
}

/// `PdfResult`.
public struct PdfResult: Sendable {
  public var bytes: Data
  public var pages: Int
  /// Bookmarks per level, read from the PDF itself.
  public var outline: [Int]
  public var passes: Int
  public var links: Int
  public var images: Int
}

/// The PDF writer (`writePdf.ts`) on WebKit: the book set into one document (`DocumentHTML`),
/// checked at print width under print media, printed with `NSPrintOperation`, then finished with
/// PDFKit. What Chromium's `printToPDF` gave and WebKit's print does not (measured 2026-11-08 on
/// Example against Chrome printing the same document, `docs/decisions/phase-3-dienste.md`, 9c):
///
/// - **No margin boxes:** the footer (title left, "page / pages" right, not on the cover) is
///   drawn onto each page after the print, as text.
/// - **No outline and no named destinations:** but every link carries its target's page and
///   point. Before the print, one invisible 1 px link per heading (and per target of a page
///   number) goes onto the cover; their destinations are where the headings landed, read by
///   position and removed again. The outline nests the headings by level as Chrome's did
///   (9/46/252/260/16/7 on Example in both), titled with their rendered text.
/// - **No `/Lang`, no "show the title in the window bar":** PDFKit cannot set them; an
///   incremental update of the catalog does (`PDFFinish.patchCatalog`).
/// - **Not tagged.** Accepted (plan, decision of 2026-11-06).
///
/// Page numbers in the contents and the register take two passes as in QuartzControl: the first
/// print gives each target's page, they are written in, the document printed again and checked
/// that no numbered target moved; a third pass corrects, else the run fails.
@MainActor
public enum PDFWrite {
  static let maxPasses = 3
  static let imageTimeoutMs = 60_000

  /// One invisible link per heading and per target of a page number, on the cover, in document
  /// order. Answers `[[id, level (0: no heading), label]]`; headings without a box (hidden) are
  /// left out, as they have no place in the print.
  static let marksScript = """
    const shown = (el) => el.getClientRects().length > 0;
    const heads = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].filter(shown);
    heads.forEach((h, i) => { if (!h.id) h.id = 'qh-h-' + i; });
    const out = heads.map((h) => [h.id, Number(h.tagName[1]), h.innerText.replace(/\\s+/g, ' ').trim()]);
    const seen = new Set(out.map((m) => m[0]));
    for (const n of document.querySelectorAll('.n[data-anchor]')) {
      const id = n.dataset.anchor;
      if (seen.has(id)) continue;
      seen.add(id);
      const target = document.getElementById(id);
      if (target && shown(target)) out.push([id, 0, '']);
    }
    const box = document.createElement('div');
    box.setAttribute('aria-hidden', 'true');
    box.style.cssText = 'position:absolute;left:0;top:0;width:100%;font-size:0;line-height:0';
    for (const [id] of out) {
      const a = document.createElement('a');
      a.href = '#' + id;
      a.style.cssText = 'display:inline-block;width:1px;height:1px;vertical-align:top';
      box.appendChild(a);
    }
    (document.querySelector('.cover') || document.body).appendChild(box);
    return out;
    """

  public static func write(_ window: ExportWindow, server: SiteServer, _ parts: DocumentHTML.Parts, _ meta: PdfMeta,
                           otherFormats: Bool = false) async throws -> PdfResult {
    window.window.setContentSize(NSSize(width: DocumentHTML.printWidthPx(parts.pageSize, landscape: parts.landscape), height: 1000))
    // Measured at print media, as Electron's emulation did: the site's @media print rules apply,
    // and the widths the check sees are the ones that are printed.
    window.webView.mediaType = "print"
    window.webView.configuration.preferences.shouldPrintBackgrounds = true
    defer { window.webView.mediaType = nil }
    try await window.load(server.origin + server.copy.setDocument("document.html", DocumentHTML.document(parts)))
    let unloaded = Int(try await window.run("imagesSettled", [.number(Double(imageTimeoutMs))]).numberValue ?? 0)
    try Task.checkCancellation()
    let problems = try await window.run("findDocumentProblems", [])
    if let text = problemText(problems) {
      let onlyEdge = (problems["deadLinks"]?.arrayValue ?? []).isEmpty && (problems["brokenImages"]?.arrayValue ?? []).isEmpty
      throw PublishFailure(L10n.t("main.exportProblems", ["problems": text]) + (onlyEdge && otherFormats ? "\n" + L10n.t("main.exportEdgePdfOnly") : ""))
    }
    if unloaded > 0 { throw PublishFailure(L10n.t("main.exportImagesPending", ["count": String(unloaded)])) }

    let marks = (try await window.evaluate(marksScript).arrayValue ?? []).map { (value: JSONValue) -> PDFFinish.Mark in
      let m = value.arrayValue ?? []
      return PDFFinish.Mark(id: m.first?.stringValue ?? "", level: Int(m.count > 1 ? m[1].numberValue ?? 0 : 0), label: m.count > 2 ? m[2].stringValue ?? "" : "")
    }
    let paper = DocumentHTML.paper(parts.pageSize)
    let size = CGSize(width: paper.w / 25.4 * 72, height: paper.h / 25.4 * 72)
    var doc = try await printed(window, size, parts.landscape, marks.count)
    var passes = 1
    // Page numbers stand in the contents and in the register of tags.
    if parts.toc || parts.pages.contains(where: { $0.slug == ExportModel.registerSlug }) {
      let numbered = Set(try await window.evaluate("return [...document.querySelectorAll('.n[data-anchor]')].map((n) => n.dataset.anchor);")
        .arrayValue?.compactMap(\.stringValue) ?? [])
      var numbers = PDFFinish.pages(doc, marks).filter { numbered.contains($0.key) }
      while true {
        try Task.checkCancellation()
        _ = try await window.run("fillPageNumbers", [.object(JSONObject(numbers.sorted { $0.key < $1.key }.map { (key, page) -> (String, JSONValue) in (key, .number(Double(page))) }))])
        doc = try await printed(window, size, parts.landscape, marks.count)
        passes += 1
        let now = PDFFinish.pages(doc, marks).filter { numbered.contains($0.key) }
        let moved = now != numbers
        numbers = now
        if !moved || passes >= maxPasses {
          if moved { throw PublishFailure(L10n.t("main.exportTocUnstable")) }
          break
        }
      }
    }
    let bytes = try PDFFinish.finish(doc, marks: marks, footer: parts.title, meta)
    guard let final = PDFDocument(data: bytes) else { throw PublishFailure(L10n.t("main.exportPdfNotWritten")) }
    return PdfResult(bytes: bytes, pages: final.pageCount, outline: PDFFinish.outlineLevels(final), passes: passes,
                     links: Int(problems["counted"]?["links"]?.numberValue ?? 0), images: Int(problems["counted"]?["images"]?.numberValue ?? 0))
  }

  /// One print, read with the footer pages, its marks checked.
  static func printed(_ window: ExportWindow, _ paper: CGSize, _ landscape: Bool, _ marks: Int) async throws -> PDFDocument {
    let data = try await window.printPDF(paper: paper, landscape: landscape)
    let doc = PDFFinish.open(data)
    guard let doc, PDFFinish.markLinks(doc).count == marks else { throw PublishFailure(L10n.t("main.exportPdfNotWritten")) }
    return doc
  }

  /// `problemText`: up to ten of each kind, under its label.
  public nonisolated static func problemText(_ problems: JSONValue) -> String? {
    let kinds: [(String, [String])] = [
      (L10n.t("main.exportProblemOverflow"), problems["overflow"]?.arrayValue?.compactMap(\.stringValue) ?? []),
      (L10n.t("main.exportProblemDeadLinks"), problems["deadLinks"]?.arrayValue?.compactMap(\.stringValue) ?? []),
      (L10n.t("main.exportProblemImages"), problems["brokenImages"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    ].filter { !$0.1.isEmpty }
    if kinds.isEmpty { return nil }
    return kinds.map { label, list in "\(label) (\(list.count)):\n" + list.prefix(10).map { "  \($0)" }.joined(separator: "\n") }.joined(separator: "\n")
  }
}

/// The work on the printed PDF, without WebKit: reading the marks, the footer, the outline, the
/// metadata and the catalog.
public enum PDFFinish {
  public struct Mark: Equatable, Sendable {
    public var id: String
    /// 1-6 for a heading, 0 for a target of a page number that is no heading.
    public var level: Int
    public var label: String

    public init(id: String, level: Int, label: String) {
      self.id = id
      self.level = level
      self.label = label
    }
  }

  /// Mark links are 1 px (0.75 pt) square; nothing else on the cover is that small.
  static let markSize: CGFloat = 1.5

  /// A document whose pages draw the footer.
  static func open(_ data: Data) -> PDFDocument? {
    guard let doc = PDFDocument(data: data) else { return nil }
    let pages = FooterPages()
    doc.delegate = pages
    objc_setAssociatedObject(doc, &FooterPages.key, pages, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return doc
  }

  static func target(_ link: PDFAnnotation) -> PDFDestination? {
    link.destination ?? (link.action as? PDFActionGoTo)?.destination
  }

  /// The cover's mark links in document order: the box is one line after another, left to right.
  static func markLinks(_ doc: PDFDocument) -> [PDFAnnotation] {
    guard doc.pageCount > 0, let cover = doc.page(at: 0) else { return [] }
    let round = { (v: CGFloat) in (v * 100).rounded() }
    return cover.annotations
      .filter { $0.url == nil && target($0) != nil && $0.bounds.width <= markSize && $0.bounds.height <= markSize }
      .sorted { a, b in
        round(a.bounds.maxY) != round(b.bounds.maxY) ? round(a.bounds.maxY) > round(b.bounds.maxY) : round(a.bounds.minX) < round(b.bounds.minX)
      }
  }

  /// The page (from 1) each mark's target landed on.
  static func pages(_ doc: PDFDocument, _ marks: [Mark]) -> [String: Int] {
    var out: [String: Int] = [:]
    for (link, mark) in zip(markLinks(doc), marks) {
      if let page = target(link)?.page { out[mark.id] = doc.index(for: page) + 1 }
    }
    return out
  }

  /// The headings as bookmarks, nested by level: a heading goes under the nearest one before it
  /// of a lower level.
  static func outline(_ entries: [(level: Int, label: String, destination: PDFDestination)]) -> PDFOutline {
    let root = PDFOutline()
    var stack: [(level: Int, node: PDFOutline)] = [(0, root)]
    for entry in entries {
      let item = PDFOutline()
      item.label = entry.label
      item.destination = entry.destination
      while let last = stack.last, last.level >= entry.level { stack.removeLast() }
      let parent = stack.last!.node
      parent.insertChild(item, at: parent.numberOfChildren)
      stack.append((entry.level, item))
    }
    return root
  }

  /// `outlineLevels`: bookmarks per depth.
  public static func outlineLevels(_ doc: PDFDocument) -> [Int] {
    var levels: [Int] = []
    func walk(_ node: PDFOutline, _ depth: Int) {
      for i in 0..<node.numberOfChildren {
        guard let child = node.child(at: i) else { continue }
        if levels.count <= depth { levels.append(0) }
        levels[depth] += 1
        walk(child, depth + 1)
      }
    }
    if let root = doc.outlineRoot { walk(root, 0) }
    return levels
  }

  /// The finished file: marks out, bookmarks in, footer on every page but the cover, metadata as
  /// QuartzControl set it with pdf-lib, then `/Lang` and the title in the window bar.
  static func finish(_ doc: PDFDocument, marks: [Mark], footer title: String, _ meta: PdfMeta) throws -> Data {
    let links = markLinks(doc)
    var entries: [(level: Int, label: String, destination: PDFDestination)] = []
    for (link, mark) in zip(links, marks) {
      if mark.level > 0, let destination = target(link) { entries.append((mark.level, mark.label, destination)) }
      link.page?.removeAnnotation(link)
    }
    doc.outlineRoot = outline(entries)
    let total = doc.pageCount
    for i in 1..<max(total, 1) { (doc.page(at: i) as? FooterPage)?.footer = (title, "\(i + 1) / \(total)") }
    var attributes: [AnyHashable: Any] = [PDFDocumentAttribute.titleAttribute: meta.title, PDFDocumentAttribute.creatorAttribute: "QuartzHub"]
    if !meta.subtitle.isEmpty { attributes[PDFDocumentAttribute.subjectAttribute] = meta.subtitle }
    if !meta.author.isEmpty { attributes[PDFDocumentAttribute.authorAttribute] = meta.author }
    // pdf-lib's setKeywords joins with a space; PDFKit would join an array with ", ".
    if !meta.keywords.isEmpty { attributes[PDFDocumentAttribute.keywordsAttribute] = [meta.keywords.joined(separator: " ")] }
    doc.documentAttributes = attributes
    guard let data = doc.dataRepresentation() else { throw PublishFailure(L10n.t("main.exportPdfNotWritten")) }
    return patchCatalog(data, lang: meta.lang) ?? data
  }

  // MARK: The catalog

  /// `/Lang` and `/ViewerPreferences << /DisplayDocTitle true >>` (pdf-lib's `setLanguage` and
  /// `setTitle(…, { showInWindowTitleBar: true })`) as an incremental update: the catalog once
  /// more with the two keys, a cross-reference section for it and a trailer pointing back. For
  /// the classic cross-reference table PDFKit writes (measured: PDF 1.4, no object streams); nil
  /// for anything else, which leaves the PDF as it was - without the two keys, not broken.
  public static func patchCatalog(_ data: Data, lang: String) -> Data? {
    let bytes = [UInt8](data)
    guard let startxref = lastRange(of: Array("startxref".utf8), in: bytes),
          let xrefOffset = Int(token(bytes, after: startxref.upperBound)),
          xrefOffset >= 0, xrefOffset < bytes.count, starts(bytes, at: xrefOffset, with: "xref"),
          let trailerAt = range(of: Array("trailer".utf8), in: bytes, from: xrefOffset),
          let trailer = dictionary(bytes, from: trailerAt.upperBound),
          let rootMatch = JSText.firstMatch(trailer.text, #"/Root\s+([0-9]+)\s+([0-9]+)\s+R"#),
          let root = Int(rootMatch.groups[1] ?? ""), let generation = Int(rootMatch.groups[2] ?? ""),
          let objectAt = xrefEntry(bytes, from: xrefOffset, upTo: trailerAt.lowerBound, object: root),
          starts(bytes, at: objectAt, with: "\(root) \(generation) obj"),
          let catalog = dictionary(bytes, from: objectAt + "\(root) \(generation) obj".utf8.count)
    else { return nil }
    var added = ""
    if !JSText.test(catalog.text, #"/Lang[\s(<]"#) { added += " /Lang \(pdfString(lang))" }
    if !JSText.test(catalog.text, #"/ViewerPreferences[\s<]"#) { added += " /ViewerPreferences << /DisplayDocTitle true >>" }
    if added.isEmpty { return data }
    let newCatalog = "<<" + added + String(catalog.text.dropFirst(2))
    var out = bytes
    if out.last != 0x0A { out += Array("\n".utf8) }
    let newObjectAt = out.count
    out += Array("\(root) \(generation) obj\n\(newCatalog)\nendobj\n".utf8)
    let newXref = out.count
    let offset = String(newObjectAt)
    let generationText = String(generation)
    out += Array("xref\n\(root) 1\n\(String(repeating: "0", count: 10 - offset.count))\(offset) \(String(repeating: "0", count: 5 - generationText.count))\(generationText) n \n".utf8)
    let inner = JSText.replaceAll(String(trailer.text.dropFirst(2).dropLast(2)), #"/Prev\s+[0-9]+"#, with: "")
    out += Array("trailer\n<<\(inner) /Prev \(xrefOffset) >>\nstartxref\n\(newXref)\n%%EOF\n".utf8)
    return Data(out)
  }

  /// A PDF text string: literal for printable ASCII, else UTF-16BE with its mark, as hex.
  static func pdfString(_ text: String) -> String {
    if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) {
      return "(" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)") + ")"
    }
    return "<FEFF" + text.utf16.map { String(format: "%04X", $0) }.joined() + ">"
  }

  static func starts(_ bytes: [UInt8], at index: Int, with text: String) -> Bool {
    let t = Array(text.utf8)
    return index + t.count <= bytes.count && Array(bytes[index..<(index + t.count)]) == t
  }

  static func range(of needle: [UInt8], in bytes: [UInt8], from start: Int) -> Range<Int>? {
    guard !needle.isEmpty, bytes.count >= needle.count, start <= bytes.count - needle.count else { return nil }
    for i in start...(bytes.count - needle.count) where bytes[i] == needle[0] && Array(bytes[i..<(i + needle.count)]) == needle {
      return i..<(i + needle.count)
    }
    return nil
  }

  static func lastRange(of needle: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
    guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
    for i in stride(from: bytes.count - needle.count, through: 0, by: -1) where bytes[i] == needle[0] && Array(bytes[i..<(i + needle.count)]) == needle {
      return i..<(i + needle.count)
    }
    return nil
  }

  static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 || b == 0x0C || b == 0x00 }

  /// The next token after `index`, skipping white space.
  static func token(_ bytes: [UInt8], after index: Int) -> String {
    var i = index
    while i < bytes.count && isSpace(bytes[i]) { i += 1 }
    var j = i
    while j < bytes.count && !isSpace(bytes[j]) { j += 1 }
    return String(decoding: bytes[i..<j], as: UTF8.self)
  }

  /// The dictionary `<< … >>` that starts after white space at `index`, with nested dictionaries,
  /// literal strings (escapes, balanced parentheses) and hex strings skipped over.
  static func dictionary(_ bytes: [UInt8], from index: Int) -> (text: String, end: Int)? {
    var i = index
    while i < bytes.count && isSpace(bytes[i]) { i += 1 }
    guard i + 1 < bytes.count, bytes[i] == 0x3C, bytes[i + 1] == 0x3C else { return nil }
    let start = i
    var depth = 0
    while i < bytes.count {
      switch bytes[i] {
      case 0x3C where i + 1 < bytes.count && bytes[i + 1] == 0x3C:
        depth += 1
        i += 2
      case 0x3E where i + 1 < bytes.count && bytes[i + 1] == 0x3E:
        depth -= 1
        i += 2
        if depth == 0 { return (String(decoding: bytes[start..<i], as: UTF8.self), i) }
      case 0x3C:
        while i < bytes.count && bytes[i] != 0x3E { i += 1 }
        i += 1
      case 0x28:
        var nest = 0
        while i < bytes.count {
          if bytes[i] == 0x5C { i += 2; continue }
          if bytes[i] == 0x28 { nest += 1 } else if bytes[i] == 0x29 { nest -= 1; if nest == 0 { break } }
          i += 1
        }
        i += 1
      default:
        i += 1
      }
    }
    return nil
  }

  /// The offset of an object in a classic cross-reference section (`xref`, then subsections of
  /// `first count` with 20-byte entries).
  static func xrefEntry(_ bytes: [UInt8], from xref: Int, upTo end: Int, object: Int) -> Int? {
    let text = String(decoding: bytes[(xref + 4)..<end], as: UTF8.self)
    var lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map { $0.trimmingCharacters(in: .whitespaces) }[...]
    while let header = lines.first {
      lines = lines.dropFirst()
      let parts = header.split(separator: " ")
      guard parts.count == 2, let first = Int(parts[0]), let count = Int(parts[1]), lines.count >= count else { return nil }
      if object >= first && object < first + count {
        let entry = lines[lines.startIndex + object - first].split(separator: " ")
        guard entry.count == 3, entry[2] == "n", let offset = Int(entry[0]) else { return nil }
        return offset
      }
      lines = lines.dropFirst(count)
    }
    return nil
  }
}

/// Gives every page of a document the footer's class.
final class FooterPages: NSObject, PDFDocumentDelegate {
  nonisolated(unsafe) static var key: UInt8 = 0
  func classForPage() -> AnyClass { FooterPage.self }
}

/// A printed page with QuartzControl's `@bottom-left` and `@bottom-right`: 8 pt system font in
/// #777, in the line of the side margins, centred in the bottom margin (Chrome's footer stood
/// 1 pt lower, measured with `pdftotext -bbox`). Drawing a page of one's own class makes PDFKit
/// paint the whole page anew when it writes: on Example 2.4 MB became 3.6 MB with the text
/// unchanged (Chrome's tagged PDF of the same document: 9.1 MB).
final class FooterPage: PDFPage {
  var footer: (left: String, right: String)?

  override func draw(with box: PDFDisplayBox, to context: CGContext) {
    super.draw(with: box, to: context)
    guard let footer else { return }
    let bounds = self.bounds(for: box)
    let mm = 72 / 25.4
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor(white: 0x77 / 255, alpha: 1)]
    let right = NSAttributedString(string: footer.right, attributes: attributes)
    let rightSize = right.size()
    let y = bounds.minY + (DocumentHTML.marginMM.bottom * mm - rightSize.height) / 2
    let leftX = bounds.minX + DocumentHTML.marginMM.left * mm
    let rightX = bounds.maxX - DocumentHTML.marginMM.right * mm - rightSize.width
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSAttributedString(string: footer.left, attributes: attributes)
      .draw(with: CGRect(x: leftX, y: y, width: max(0, rightX - leftX - 12), height: rightSize.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    right.draw(at: CGPoint(x: rightX, y: y))
    NSGraphicsContext.restoreGraphicsState()
  }
}
