import CryptoKit
import Darwin
import Foundation

/// One page of the site as the export collected it (`CollectedPage`): its article made to stand
/// in one document with every other page, and what was replaced or dropped on the way.
public struct CollectedPage: Equatable, Sendable {
  public struct Counts: Equatable, Sendable {
    public var outsideLinks = 0, textLinks = 0, forms = 0, frames = 0, media = 0, canvases = 0, unrenderedDiagrams = 0
    public init() {}

    static let keys = ["outsideLinks", "textLinks", "forms", "frames", "media", "canvases", "unrenderedDiagrams"]
    var values: [Int] { [outsideLinks, textLinks, forms, frames, media, canvases, unrenderedDiagrams] }
  }

  public var slug: String
  public var title: String
  public var lang: String
  public var html: String
  public var images: [String]
  public var level: Int
  public var counts: Counts

  public init(slug: String, title: String, lang: String, html: String, images: [String] = [], level: Int, counts: Counts = Counts()) {
    self.slug = slug
    self.title = title
    self.lang = lang
    self.html = html
    self.images = images
    self.level = level
    self.counts = counts
  }

  public var json: JSONValue {
    .object(JSONObject([
      ("slug", .string(slug)), ("title", .string(title)), ("lang", .string(lang)), ("html", .string(html)),
      ("images", .array(images.map(JSONValue.string))), ("level", .number(Double(level))),
      ("counts", .object(JSONObject(zip(Counts.keys, counts.values).map { ($0, .number(Double($1))) })))
    ]))
  }
}

/// The one HTML document every page of a book is set into, for printing (`documentHtml.ts`). The
/// site's own stylesheets come along, so callouts, code and tables look as they do on the website;
/// on top of them the print rules, generalised from the handbook script's PRINT_CSS. The margin
/// boxes (`@bottom-left`, `@bottom-right`) stay in the rules as QuartzControl wrote them; WebKit
/// leaves them out, and the footer comes after the print (9c).
public enum DocumentHTML {
  /// Paper sizes in millimetres, portrait.
  static let paperMM: [String: (w: Double, h: Double)] = ["A4": (210, 297), "A5": (148, 210), "Letter": (215.9, 279.4)]
  /// The margins of the handbook script, kept: they are what its 129 pages were measured with.
  static let marginMM = (top: 20.0, bottom: 20.0, left: 18.0, right: 18.0)
  /// Where a page number stands until the second pass knows it. Fixed width, so the real numbers
  /// do not move a single line.
  public static let pagePlaceholder = "000"

  static func paper(_ size: String) -> (w: Double, h: Double) { paperMM[size] ?? paperMM["A4"]! }

  /// `printWidthPx`: the printable width in CSS pixels, the export window's width.
  public static func printWidthPx(_ size: String, landscape: Bool) -> Int {
    let p = paper(size)
    let width = landscape ? p.h : p.w
    return Int(JS.round(((width - marginMM.left - marginMM.right) / 25.4) * 96))
  }

  static func esc(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }

  /// A string for a CSS `content:` value.
  static func cssString(_ text: String) -> String {
    "\"" + JSText.replaceAll(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""), "[\\n\\r]", with: " ") + "\""
  }

  /// `headingAnchor`: the id an interposed heading gets, so the table of contents can point at it.
  public static func headingAnchor(_ index: Int) -> String { "h-\(index)" }

  public struct Parts: Sendable {
    public var lang: String
    public var title: String
    public var subtitle: String
    public var author: String
    /// A line under the author: date and the like.
    public var meta: String
    public var coverImage: String?
    public var stylesheets: [String]
    public var items: [DocItem]
    public var pages: [CollectedPage]
    /// A table of contents after the cover, titled in the document's language.
    public var toc: Bool
    public var pageSize: String
    public var landscape: Bool

    public init(lang: String, title: String, subtitle: String, author: String, meta: String, coverImage: String?, stylesheets: [String],
                items: [DocItem], pages: [CollectedPage], toc: Bool, pageSize: String, landscape: Bool) {
      self.lang = lang
      self.title = title
      self.subtitle = subtitle
      self.author = author
      self.meta = meta
      self.coverImage = coverImage
      self.stylesheets = stylesheets
      self.items = items
      self.pages = pages
      self.toc = toc
      self.pageSize = pageSize
      self.landscape = landscape
    }
  }

  /// The cover's height. QuartzControl sets 230 mm for every paper, which is the A4 portrait text
  /// area (257 mm) less 27 mm. In A5 landscape (108 mm) the cover then ran onto a second page: the
  /// picture cut off at the foot of the first, title and date on the second, under a footer
  /// (measured 2026-11-10; A4 landscape, A5 portrait and Letter landscape overflow too). The same
  /// 27 mm come off each paper's text area instead, so A4 portrait stays QuartzControl's 230 mm.
  /// A decision against QuartzControl, in decisions/phase-5-gleichstand.md.
  public static func coverHeightMM(_ pageSize: String, landscape: Bool) -> Double {
    let p = paper(pageSize)
    let height = landscape ? p.w : p.h
    return JS.round((height - marginMM.top - marginMM.bottom - 27) * 10) / 10
  }

  public static func printCss(pageSize: String, landscape: Bool, title: String) -> String {
    let p = paper(pageSize)
    let (w, h) = landscape ? (p.h, p.w) : (p.w, p.h)
    let n = JSJSON.numberToString
    return """

@page {
  size: \(n(w))mm \(n(h))mm;
  margin: \(n(marginMM.top))mm \(n(marginMM.right))mm \(n(marginMM.bottom))mm \(n(marginMM.left))mm;
  @bottom-left { content: \(cssString(title)); font: 8pt -apple-system, Helvetica, Arial, sans-serif; color: #777; }
  @bottom-right { content: counter(page) " / " counter(pages); font: 8pt -apple-system, Helvetica, Arial, sans-serif; color: #777; }
}
@page :first { @bottom-left { content: none; } @bottom-right { content: none; } }
html, body.pdf { height: auto !important; overflow: visible !important; background: #fff !important; }
body.pdf { display: block !important; margin: 0 !important; padding: 0 !important; max-width: none !important; font-size: 10.5pt; line-height: 1.5; }
body.pdf .doc-page, body.pdf .doc-part { display: block; max-width: none; }
body.pdf h1.page-title, body.pdf .doc-page[data-level="2"] > h2.page-title, body.pdf .qc-toc { break-before: page; }
body.pdf h1.page-title { font-size: 24pt; margin: 0 0 0.6em; }
body.pdf h2.page-title { font-size: 17pt; margin: 0 0 0.6em; }
body.pdf h3 { font-size: 13pt; margin-top: 1.3em; }
body.pdf h4 { font-size: 11.5pt; margin-top: 1.1em; }
body.pdf h1, body.pdf h2, body.pdf h3, body.pdf h4, body.pdf .index-heading { break-after: avoid; }
body.pdf .index-heading { font-size: 13pt; font-weight: 600; margin: 1.3em 0 0.5em; }
body.pdf img { max-width: 100% !important; height: auto !important; break-inside: avoid; }
body.pdf p:has(> img), body.pdf blockquote.callout, body.pdf pre, body.pdf tr, body.pdf figure { break-inside: avoid; }
body.pdf a { text-decoration: none; }
/* In der Website rollt der Tabellen-Container; auf Papier wird umbrochen. Der Außenabstand kommt
   aus der Vorlage und schob jede Tabelle um 16 px über den Rand. */
body.pdf .table-container { overflow: visible !important; }
body.pdf table { width: 100% !important; max-width: 100% !important; margin-left: 0 !important; margin-right: 0 !important; table-layout: auto; }
body.pdf td, body.pdf th { overflow-wrap: anywhere; }
body.pdf td code, body.pdf th code { white-space: normal !important; overflow-wrap: anywhere; }
/* Die Diagramme aus Rahmenzeichen passen erst in 8,5 pt in die Druckbreite */
body.pdf pre, body.pdf pre code { font-size: 8.5pt !important; max-width: 100% !important; }
body.pdf pre code, body.pdf pre code * { white-space: pre-wrap !important; overflow-wrap: anywhere; }
/* Example's template sets code blocks to a grid with min-width: max-content (for horizontal
   scrolling on the website), and then no line wraps: five blocks stood 7-75 px past the edge. */
body.pdf pre code { display: block !important; min-width: 0 !important; width: auto !important; }
body.pdf pre code > [data-line] { display: block !important; min-width: 0 !important; }
body.pdf .qc-diagram { margin: 1em 0; text-align: center; }
/* A Mermaid diagram brings its natural width as an inline max-width and width="100%"; forcing
   max-width here stretched every small diagram to the full line. Only one without its own limit
   is held to the line. */
body.pdf .qc-diagram svg { height: auto; }
body.pdf .qc-diagram svg:not([style*="max-width"]) { max-width: 100%; }
body.pdf .qc-replaced { font-style: italic; color: #555; }
body.pdf .qc-unlinked { color: inherit; }
.cover { height: \(n(coverHeightMM(pageSize, landscape: landscape)))mm; display: flex; flex-direction: column; justify-content: center; align-items: flex-start; }
.cover img { width: 28mm; height: 28mm; object-fit: contain; margin-bottom: 10mm; }
.cover p { margin: 0; }
.cover-title { font-size: 34pt; font-weight: 700; line-height: 1.1; margin: 0 0 4mm !important; }
.cover-subtitle { font-size: 15pt; color: #444; margin-bottom: 8mm !important; }
.cover-meta { font-size: 11pt; color: #555; }
.qc-toc-title { font-size: 24pt; font-weight: 700; margin: 0 0 0.8em; }
.qc-toc ol { list-style: none; margin: 0; padding: 0; }
.qc-toc li { margin: 0.15em 0; }
.qc-toc li.lvl-1 { font-weight: 600; margin-top: 0.7em; }
.qc-toc li.lvl-2 { padding-left: 1.2em; }
.qc-toc a { display: flex; align-items: baseline; gap: 0.4em; color: inherit; }
.qc-toc .t { flex: 1 1 auto; }
.qc-toc .n { flex: 0 0 auto; min-width: 3ch; text-align: right; font-variant-numeric: tabular-nums; }
.qc-backlinks { margin-top: 1.6em; padding-top: 0.6em; border-top: 1px solid #ddd; font-size: 9.5pt; }
.qc-backlinks-title { font-weight: 600; margin: 0 0 0.3em; break-after: avoid; }
.qc-backlinks ul { margin: 0; padding-left: 1.2em; }
.qc-register dt { font-weight: 600; margin-top: 0.6em; break-after: avoid; }
.qc-register dd { margin: 0 0 0 1.2em; }
.qc-register-entry { display: flex; gap: 0.4em; }
.qc-register-entry a { flex: 1 1 auto; color: inherit; }
.qc-register .n { min-width: 3ch; text-align: right; font-variant-numeric: tabular-nums; }

"""
  }

  /// The table of contents: the interposed headings and the pages of the two top levels, each a
  /// link to its anchor - the second pass reads the page numbers from these links.
  static func tocHtml(_ parts: Parts) -> String {
    var titles: [String: String] = [:]
    for page in parts.pages { titles[page.slug] = page.title }
    var rows: [String] = []
    for (index, item) in parts.items.enumerated() {
      switch item {
      case .heading(let text):
        let a = headingAnchor(index)
        rows.append("<li class=\"lvl-1\"><a href=\"#\(a)\"><span class=\"t\">\(esc(text))</span><span class=\"n\" data-anchor=\"\(a)\">\(pagePlaceholder)</span></a></li>")
      case .page(let slug, let level) where level <= 2:
        let a = ExportModel.anchor(slug)
        rows.append("<li class=\"lvl-\(level)\"><a href=\"#\(a)\"><span class=\"t\">\(esc(titles[slug] ?? slug))</span><span class=\"n\" data-anchor=\"\(a)\">\(pagePlaceholder)</span></a></li>")
      default: break
      }
    }
    return "<nav class=\"qc-toc\"><p class=\"qc-toc-title\">\(esc(L10n.t(in: parts.lang, "main.docContents")))</p><ol>\(rows.joined())</ol></nav>"
  }

  /// `documentHtml(parts)`.
  public static func document(_ parts: Parts) -> String {
    var bySlug: [String: CollectedPage] = [:]
    for page in parts.pages { bySlug[page.slug] = page }
    let body = parts.items.enumerated().map { index, item -> String in
      switch item {
      case .heading(let text): return "<h1 class=\"page-title\" id=\"\(headingAnchor(index))\">\(esc(text))</h1>"
      case .page(let slug, _):
        guard let p = bySlug[slug] else { return "" }
        return "<section class=\"doc-page\" data-level=\"\(p.level)\"><h\(p.level) class=\"page-title\" id=\"\(ExportModel.anchor(p.slug))\">\(esc(p.title))</h\(p.level)>\(p.html)</section>"
      }
    }.joined(separator: "\n")
    let cover = [
      parts.coverImage.map { $0.isEmpty ? "" : "<img src=\"\(esc($0))\" alt=\"\">" } ?? "",
      "<p class=\"cover-title\">\(esc(parts.title))</p>",
      parts.subtitle.isEmpty ? "" : "<p class=\"cover-subtitle\">\(esc(parts.subtitle))</p>",
      "<p class=\"cover-meta\">\(esc([parts.author, parts.meta].filter { !$0.isEmpty }.joined(separator: " · ")))</p>"
    ].joined()
    return """
<!doctype html><html lang="\(esc(parts.lang))" saved-theme="light"><head><meta charset="utf-8">
<title>\(esc(parts.title))</title>
\(parts.stylesheets.map { "<link rel=\"stylesheet\" href=\"\(esc($0))\">" }.joined(separator: "\n"))
<style>\(printCss(pageSize: parts.pageSize, landscape: parts.landscape, title: parts.title))</style></head><body class="pdf">
<div class="cover">\(cover)</div>
\(parts.toc ? tocHtml(parts) : "")
<div class="doc-part">\(body)</div>
</body></html>
"""
  }
}

/// The parts of `exportService.ts` that work on collected pages without the export window.
public enum ExportExtras {
  /// `addBacklinksAndRegister`: "Links to this page" at the end of each page that has any (from
  /// Quartz's own record of links, counted within the book), and the register of tags as one more
  /// page at the end, its page numbers in `.qc-pageno` spans the PDF's second pass fills. Written
  /// into the collected pages before any writer sees them, so PDF, ePub and HTML get them alike.
  public static func addBacklinksAndRegister(_ pages: inout [CollectedPage], _ items: inout [DocItem], backlinks: Bool, tagIndex: Bool,
                                             facts: SiteFacts, lang: String) -> (backlinks: Int, tags: Int) {
    let slugs = pages.map(\.slug)
    var titleOf: [String: String] = [:]
    for page in pages { titleOf[page.slug] = page.title }
    func link(_ slug: String) -> String { "<a href=\"#\(ExportModel.anchor(slug))\">\(DocumentHTML.esc(titleOf[slug] ?? slug))</a>" }
    var backlinkCount = 0
    if backlinks {
      let refs = Dictionary(ExportModel.backlinksInBook(slugs) { facts.pages[$0]?.links ?? [] }.map { ($0.slug, $0.from) }, uniquingKeysWith: { a, _ in a })
      for i in pages.indices {
        let from = refs[pages[i].slug] ?? []
        if from.isEmpty { continue }
        backlinkCount += from.count
        pages[i].html += "<aside class=\"qc-backlinks\"><p class=\"qc-backlinks-title\">\(DocumentHTML.esc(L10n.t(in: lang, "main.docBacklinks")))</p><ul>"
          + from.map { "<li>\(link($0))</li>" }.joined() + "</ul></aside>"
      }
    }
    var tags = 0
    if tagIndex {
      let register = ExportModel.tagRegister(slugs, tagsOf: { facts.pages[$0]?.tags ?? [] }, locale: lang)
      tags = register.count
      if !register.isEmpty {
        let html = "<dl class=\"qc-register\">" + register.map { r in
          "<dt>\(DocumentHTML.esc(r.tag))</dt><dd>" + r.pages.map { s in
            "<span class=\"qc-register-entry\">\(link(s))<span class=\"qc-pageno n\" data-anchor=\"\(ExportModel.anchor(s))\">000</span></span>"
          }.joined() + "</dd>"
        }.joined() + "</dl>"
        pages.append(CollectedPage(slug: ExportModel.registerSlug, title: L10n.t(in: lang, "main.docRegister"), lang: lang, html: html, level: 1))
        items.append(.page(slug: ExportModel.registerSlug, level: 1))
      }
    }
    return (backlinkCount, tags)
  }

  /// `bookKeywords`: the PDF's keywords, the tags of the book's pages, most used first, at most 30.
  public static func bookKeywords(_ items: [DocItem], facts: SiteFacts) -> [String] {
    var order: [String] = []
    var count: [String: Int] = [:]
    for item in items {
      guard let slug = item.slug else { continue }
      for tag in facts.pages[slug]?.tags ?? [] {
        if count[tag] == nil { order.append(tag) }
        count[tag, default: 0] += 1
      }
    }
    JS.sort(&order) { a, b in
      let byCount = Double(count[b]! - count[a]!)
      return byCount != 0 ? byCount : JS.collate(a, b, locale: "", numeric: false, base: false)
    }
    return Array(order.prefix(30))
  }

  /// `bookIdentifier`: a stable `urn:uuid:` (version 5 form) per book and site, so a reader takes
  /// a new edition for the same book. The hashed prefix stays QuartzControl's, so an ePub from
  /// QuartzHub is the same book as one from QuartzControl.
  public static func bookIdentifier(site: String, bookId: String) -> String {
    let h = Insecure.SHA1.hash(data: Data("quartzcontrol-book\0\(site)\0\(bookId)".utf8)).map { String(format: "%02x", $0) }.joined()
    let chars = Array(h)
    func s(_ a: Int, _ b: Int) -> String { String(chars[a..<b]) }
    let variant = String((Int(String(chars[16]), radix: 16)! & 0x3) | 0x8, radix: 16)
    return "urn:uuid:\(s(0, 8))-\(s(8, 12))-5\(s(13, 16))-\(variant)\(s(17, 20))-\(s(20, 32))"
  }

  static let coverTypes = [".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif", ".svg": "image/svg+xml"]

  /// `coverPicture`: the book's own picture (a file in the project), else the build's
  /// static/icon.png - the project picture as the site shows it. An own picture that is missing,
  /// outside the project or of another type falls back to the project picture and says so.
  public static func coverPicture(project: String, buildRoot: String, coverImage: String) throws(PublishFailure)
    -> (picture: (data: Data, type: String)?, ownMissing: Bool) {
    let own = coverImage.isEmpty ? nil : PackagePaths.contained(project, coverImage)
    var candidates: [String?] = coverImage.isEmpty ? [] : [own]
    candidates.append(NodePath.join(buildRoot, "static", "icon.png"))
    for case let file? in candidates {
      var info = stat()
      guard stat(file, &info) == 0, let type = coverTypes[NodePath.extname(file).lowercased()] else { continue }
      do {
        return ((try Posix.read(file), type), !coverImage.isEmpty && file != own)
      } catch {
        var failure = (error as? NodeFileError) ?? NodeFileError(code: EIO, syscall: "read", path: nil)
        if failure.code == EISDIR { failure.path = nil }
        throw PublishFailure(JSText.slice(failure.description, 7))
      }
    }
    return (nil, !coverImage.isEmpty)
  }

  /// `mb(bytes)`: megabytes with one decimal, as `toFixed(1)`.
  public static func mb(_ bytes: Int) -> String { JS.toFixed(Double(bytes) / 1024 / 1024, 1) }
}

extension JS {
  /// `Number.prototype.toFixed(digits)` for a value below 1e21: the decimal nearest to the exact
  /// binary value, a tie going up (printf goes to the even digit).
  static func toFixed(_ value: Double, _ digits: Int) -> String {
    guard value.isFinite else { return value.isNaN ? "NaN" : (value < 0 ? "-Infinity" : "Infinity") }
    let negative = value < 0
    // The exact decimal expansion of the double (printf prints it digit for digit).
    let exact = String(format: "%.1100f", abs(value))
    let parts = exact.split(separator: ".", maxSplits: 1)
    var integer = Array(parts[0]).map { Int(String($0))! }
    let fraction = Array(parts.count > 1 ? parts[1] : "").map { Int(String($0))! }
    var kept = Array(fraction.prefix(digits))
    while kept.count < digits { kept.append(0) }
    let rest = fraction.dropFirst(digits)
    if let first = rest.first, first >= 5 {
      var all = integer + kept
      var i = all.count - 1
      while i >= 0 {
        if all[i] == 9 { all[i] = 0; i -= 1 } else { all[i] += 1; break }
      }
      if i < 0 { all.insert(1, at: 0) }
      integer = Array(all.prefix(all.count - digits))
      kept = Array(all.suffix(digits))
    }
    let text = integer.map(String.init).joined() + (digits > 0 ? "." + kept.map(String.init).joined() : "")
    // `x < 0` puts the sign first, also where the digits round to zero ("-0.0"); -0 is not below 0.
    return negative ? "-" + text : text
  }
}
