import Foundation

/// The book's content in the form a reader takes (`BookContent`), shared by the ePub and the
/// offline HTML: chapters as XHTML bodies, the navigation, and every picture (the site's own, the
/// drawn formulas and diagrams, the cover) as bytes under the name the chapters use. Made in the
/// export window (`prepareBookContent`, 9b); packed here.
public struct BookContent: Sendable {
  public struct Chapter: Equatable, Sendable {
    public var file: String
    public var title: String
    public var body: String
    public var hasMath: Bool
    public var hasSvg: Bool
    public init(file: String, title: String, body: String, hasMath: Bool, hasSvg: Bool) {
      self.file = file
      self.title = title
      self.body = body
      self.hasMath = hasMath
      self.hasSvg = hasSvg
    }
  }

  public struct NavEntry: Equatable, Sendable {
    public var href: String
    public var title: String
    public var level: Int
    public init(href: String, title: String, level: Int) {
      self.href = href
      self.title = title
      self.level = level
    }
  }

  public struct Asset: Equatable, Sendable {
    public var data: Data
    public var type: String
    public init(data: Data, type: String) {
      self.data = data
      self.type = type
    }
  }

  public struct Counts: Equatable, Sendable {
    public var externalImages = 0, unsupportedImages = 0, unresolvedLinks = 0, footnotes = 0, formulas = 0, diagrams = 0
    public init() {}
  }

  public var chapters: [Chapter]
  public var nav: [NavEntry]
  /// `images/…` → bytes and media type, in the order they were found.
  public var assets: [(name: String, asset: Asset)]
  public var cover: (name: String, asset: Asset)?
  /// How many of `assets` are drawn formulas and diagrams, not pictures of the site.
  public var drawings: (formulas: Int, diagrams: Int)
  public var counts: Counts

  public init(chapters: [Chapter], nav: [NavEntry], assets: [(name: String, asset: Asset)], cover: (name: String, asset: Asset)?,
              drawings: (formulas: Int, diagrams: Int), counts: Counts) {
    self.chapters = chapters
    self.nav = nav
    self.assets = assets
    self.cover = cover
    self.drawings = drawings
    self.counts = counts
  }
}

/// What the ePub and the HTML say about the book (`EpubParts`, the fields the packers read).
public struct BookParts: Sendable {
  public var lang: String
  public var title: String
  public var subtitle: String
  public var author: String
  /// A stable `urn:uuid:` for this book (`ExportExtras.bookIdentifier`).
  public var identifier: String
  public var modified: Date

  public init(lang: String, title: String, subtitle: String, author: String, identifier: String, modified: Date) {
    self.lang = lang
    self.title = title
    self.subtitle = subtitle
    self.author = author
    self.identifier = identifier
    self.modified = modified
  }
}

/// The ePub 3 package (`packEpub` in writeEpub.ts): one XHTML file per page, a navigation
/// document from the book's order, the pictures, a stylesheet of its own, and the package
/// document with accessibility metadata. Zipped with `mimetype` first and stored. One difference:
/// the generator QuartzHub names is itself.
public enum EpubPack {
  public struct Result: Sendable {
    public var bytes: Data
    public var chapters: Int
    public var images: Int
    public var counts: BookContent.Counts
  }

  /// The reader stylesheet, also the offline HTML's. No background that assumes a light page: a
  /// reader's dark theme changes the text colour but not every background (Calibre 9.17 set the
  /// callouts' text light grey on #f5f5f5); a translucent grey works on either.
  public static let style = """

body { margin: 0 4%; line-height: 1.5; }
h1, h2, h3, h4, h5, h6 { line-height: 1.25; page-break-after: avoid; break-after: avoid; }
h1 { font-size: 1.6em; margin: 0 0 0.8em; }
h2 { font-size: 1.35em; margin: 1.4em 0 0.6em; }
h3 { font-size: 1.15em; margin: 1.2em 0 0.5em; }
img, svg { max-width: 100%; height: auto; }
figure { margin: 1em 0; }
figure.qc-diagram { text-align: center; }
img.qc-diagram-picture { background: #fff; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; font-size: 0.85em; padding: 0.6em; border: 1px solid #ddd; border-radius: 4px; }
code { font-family: monospace; font-size: 0.92em; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; }
th, td { border: 1px solid #ccc; padding: 0.3em 0.5em; text-align: left; vertical-align: top; }
blockquote { margin: 1em 0; padding: 0.2em 1em; border-left: 3px solid #999; }
blockquote.callout { border-left-width: 4px; background: rgba(128, 128, 128, 0.12); }
.callout-title { font-weight: bold; }
.callout-icon, .callout-fold { display: none; }
.qc-replaced { font-style: italic; }
.qc-backlinks { margin-top: 1.5em; padding-top: 0.5em; border-top: 1px solid #ccc; font-size: 0.9em; }
.qc-backlinks-title { font-weight: bold; margin: 0 0 0.3em; }
.qc-backlinks-title, .qc-register dt, .index-heading { page-break-after: avoid; break-after: avoid; }
.qc-register dt { font-weight: bold; margin-top: 0.6em; }
.qc-register dd { margin-left: 1.2em; }
.qc-register-entry { display: block; }
.index-heading { font-weight: bold; margin-top: 1.2em; }
math[display="block"] { display: block; margin: 0.8em auto; }
.qc-formula-block { text-align: center; margin: 0.8em 0; }
aside.footnote, section.footnotes aside { font-size: 0.9em; margin: 0.4em 0; }
nav ol { list-style: none; padding-left: 1.2em; }
.cover { text-align: center; margin-top: 20%; }
.cover img { max-width: 40%; }
.cover .title { font-size: 2em; font-weight: bold; margin: 0.6em 0 0.2em; }
.cover .subtitle { font-size: 1.2em; }

"""

  static let generator = "QuartzHub"

  static func esc(_ text: String) -> String { DocumentHTML.esc(text) }

  static func xhtml(_ lang: String, _ title: String, _ body: String, _ extraHead: String = "") -> String {
    """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(esc(lang))" lang="\(esc(lang))">
<head><meta charset="UTF-8"/><title>\(esc(title))</title><link rel="stylesheet" type="text/css" href="../style.css"/>\(extraHead)</head>
<body>\(body)</body>
</html>

"""
  }

  /// `2026-11-05T21:04:00Z`: the one form `dcterms:modified` accepts.
  static func epubDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  /// `navList`: the navigation list, nested by level - a level deeper opens a list inside the
  /// previous item.
  public static func navList(_ entries: [BookContent.NavEntry]) -> String {
    var out = ""
    var stack: [Int] = []
    for e in entries {
      if stack.isEmpty {
        out += "<ol>"
        stack.append(e.level)
      } else if e.level > stack.last! {
        out += "<ol>"
        stack.append(e.level)
      } else {
        out += "</li>"
        while stack.count > 1 && e.level < stack.last! {
          out += "</ol></li>"
          stack.removeLast()
        }
      }
      out += "<li><a href=\"\(esc(e.href))\">\(esc(e.title))</a>"
    }
    while !stack.isEmpty {
      out += "</li></ol>"
      stack.removeLast()
    }
    return out
  }

  /// `packEpub(content, parts)`.
  public static func pack(_ content: BookContent, _ parts: BookParts) throws -> Result {
    var entries: [ZipArchive.Entry] = [
      ZipArchive.Entry(name: "mimetype", data: Data("application/epub+zip".utf8), store: true),
      ZipArchive.Entry(name: "META-INF/container.xml", data: Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>\n".utf8)),
      ZipArchive.Entry(name: "OEBPS/style.css", data: Data(style.utf8))
    ]
    var manifest = ["<item id=\"style\" href=\"style.css\" media-type=\"text/css\"/>"]
    var spine: [String] = []
    for (n, item) in content.assets.enumerated() {
      entries.append(ZipArchive.Entry(name: "OEBPS/\(item.name)", data: item.asset.data))
      manifest.append("<item id=\"img\(n + 1)\" href=\"\(esc(item.name))\" media-type=\"\(item.asset.type)\"/>")
    }
    var coverPicture = ""
    if let cover = content.cover {
      entries.append(ZipArchive.Entry(name: "OEBPS/\(cover.name)", data: cover.asset.data))
      manifest.append("<item id=\"cover-image\" href=\"\(esc(cover.name))\" media-type=\"\(cover.asset.type)\" properties=\"cover-image\"/>")
      coverPicture = "<img src=\"../\(esc(cover.name))\" alt=\"\"/>"
    }
    let coverBody = "<section class=\"cover\" epub:type=\"cover\">\(coverPicture)<p class=\"title\">\(esc(parts.title))</p>"
      + (parts.subtitle.isEmpty ? "" : "<p class=\"subtitle\">\(esc(parts.subtitle))</p>")
      + (parts.author.isEmpty ? "" : "<p class=\"author\">\(esc(parts.author))</p>") + "</section>"
    entries.append(ZipArchive.Entry(name: "OEBPS/text/cover.xhtml", data: Data(xhtml(parts.lang, parts.title, coverBody).utf8)))
    manifest.append("<item id=\"cover\" href=\"text/cover.xhtml\" media-type=\"application/xhtml+xml\"/>")
    spine.append("<itemref idref=\"cover\"/>")

    let contents = L10n.t(in: parts.lang, "main.docContents")
    let navEntries = content.nav.map { BookContent.NavEntry(href: JSText.replaceAll($0.href, "^text/", with: ""), title: $0.title, level: $0.level) }
    let nav = "<nav epub:type=\"toc\" id=\"toc\"><h1>\(esc(contents))</h1>\(navList(navEntries))</nav>"
    entries.append(ZipArchive.Entry(name: "OEBPS/text/nav.xhtml", data: Data(xhtml(parts.lang, contents, nav).utf8)))
    manifest.append("<item id=\"nav\" href=\"text/nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")
    spine.append("<itemref idref=\"nav\"/>")

    for (i, c) in content.chapters.enumerated() {
      let id = "c\(i + 1)"
      entries.append(ZipArchive.Entry(name: "OEBPS/\(c.file)", data: Data(xhtml(parts.lang, c.title, c.body).utf8)))
      let props = [c.hasMath ? "mathml" : "", c.hasSvg ? "svg" : ""].filter { !$0.isEmpty }.joined(separator: " ")
      manifest.append("<item id=\"\(id)\" href=\"\(c.file)\" media-type=\"application/xhtml+xml\"\(props.isEmpty ? "" : " properties=\"\(props)\"")/>")
      spine.append("<itemref idref=\"\(id)\"/>")
    }

    let hasMath = content.chapters.contains { $0.hasMath }
    let visual = !content.assets.isEmpty || content.chapters.contains { $0.hasSvg }
    let features = ["structuralNavigation", "tableOfContents", "readingOrder"] + (hasMath ? ["MathML"] : [])
    let date = epubDate(parts.modified)
    let opf = """
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="\(esc(parts.lang))">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="book-id">\(esc(parts.identifier))</dc:identifier>
<dc:title>\(esc(parts.title))</dc:title>
<dc:language>\(esc(parts.lang))</dc:language>
\(parts.author.isEmpty ? "" : "<dc:creator>\(esc(parts.author))</dc:creator>")
\(parts.subtitle.isEmpty ? "" : "<dc:description>\(esc(parts.subtitle))</dc:description>")
<dc:date>\(JSText.slice(date, 0, 10))</dc:date>
<meta property="dcterms:modified">\(date)</meta>
<meta property="schema:accessMode">textual</meta>
\(visual ? "<meta property=\"schema:accessMode\">visual</meta>" : "")
<meta property="schema:accessModeSufficient">\(visual ? "textual,visual" : "textual")</meta>
\(features.map { "<meta property=\"schema:accessibilityFeature\">\($0)</meta>" }.joined(separator: "\n"))
<meta property="schema:accessibilityHazard">unknown</meta>
<meta property="schema:accessibilitySummary">\(esc(L10n.t(in: parts.lang, "main.docAccessibilitySummary")))</meta>
<meta name="generator" content="\(generator)"/>
</metadata>
<manifest>
\(manifest.joined(separator: "\n"))
</manifest>
<spine>
\(spine.joined(separator: "\n"))
</spine>
</package>

"""
    entries.append(ZipArchive.Entry(name: "OEBPS/content.opf", data: Data(opf.utf8)))
    return Result(bytes: try ZipArchive.create(entries, modified: parts.modified), chapters: content.chapters.count,
                  images: content.assets.count - content.drawings.formulas - content.drawings.diagrams, counts: content.counts)
  }
}

/// The offline HTML (`packHtml` in writeHtml.ts): the whole book in one file that opens in any
/// browser without a network - the ePub's content with every picture as a `data:` URI, the
/// navigation at the top, links between chapters made links within the page. No script. A file
/// past `maxBytes`, estimated before anything is encoded, is refused.
public enum HtmlPack {
  public static let maxBytes = 200 * 1024 * 1024

  static let screen = """

body { max-width: 46em; margin: 0 auto; padding: 1.5em 1.2em 4em; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; color: #1f1f1f; background: #fff; }
a { color: #1a5fb4; }
.qc-chapter { border-top: 1px solid #ddd; margin-top: 2.5em; padding-top: 1em; }
.cover { margin-top: 3em; }
.cover img { width: 6em; max-width: 30%; }
nav#toc { margin: 2em 0; }
@media (prefers-color-scheme: dark) {
  body { color: #e6e6e6; background: #1c1c1c; }
  a { color: #8ab4f8; }
  blockquote.callout { background: #262626; }
  pre { border-color: #444; }
  th, td { border-color: #444; }
  .qc-chapter { border-color: #333; }
  img.qc-formula, img.qc-diagram-picture, figure.qc-diagram svg { background: #fff; border-radius: 3px; }
}

"""

  public struct Result: Sendable {
    public var bytes: Data
    public var chapters: Int
    public var pictures: Int
  }

  static func dataURI(_ asset: BookContent.Asset) -> String { "data:\(asset.type);base64,\(asset.data.base64EncodedString())" }

  public static func pack(_ content: BookContent, _ parts: BookParts, maxBytes: Int = maxBytes) throws(PublishFailure) -> Result {
    let raw = content.assets.reduce(0) { $0 + $1.asset.data.count } + (content.cover?.asset.data.count ?? 0)
    let estimate = Int((Double(raw) * 4 / 3).rounded(.up)) + content.chapters.reduce(0) { $0 + JSText.length($1.body) }
    if estimate > maxBytes {
      let mb = { (bytes: Int) in JSJSON.numberToString(JS.round(Double(bytes) / 1024 / 1024)) }
      throw PublishFailure(L10n.t("main.exportHtmlTooLarge", ["mb": mb(estimate), "max": mb(maxBytes)]))
    }
    var uris: [String: String] = [:]
    for item in content.assets { uris[item.name] = dataURI(item.asset) }
    // `../images/x.png` (relative to a chapter file) becomes the picture itself; `c0012.xhtml#id`
    // becomes `#id` - ids are unique across the book, so one page can hold them all.
    func body(_ c: BookContent.Chapter) -> String {
      var text = c.body
      for match in JSText.matches(text, #"src="\.\./(images/[^"]+)""#).reversed() {
        guard let name = match.groups[1], let uri = uris[name] else { continue }
        text = (text as NSString).replacingCharacters(in: match.range, with: "src=\"\(uri)\"")
      }
      text = JSText.replaceAll(text, #"href="c\d{4}\.xhtml#"#, with: "href=\"#")
      text = text.replacingOccurrences(of: " xmlns=\"http://www.w3.org/1999/xhtml\"", with: "")
      return JSText.replaceAll(text, #" epub:type="[^"]*""#, with: "")
    }
    let cover = content.cover.map { "<img src=\"\(dataURI($0.asset))\" alt=\"\" />" } ?? ""
    let nav = EpubPack.navList(content.nav.map {
      let pieces = JSText.split($0.href, "#")
      return BookContent.NavEntry(href: "#" + (pieces.count > 1 ? pieces[1] : "undefined"), title: $0.title, level: $0.level)
    })
    let esc = DocumentHTML.esc
    let contents = esc(L10n.t(in: parts.lang, "main.docContents"))
    let html = """
<!doctype html>
<html lang="\(esc(parts.lang))">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="\(EpubPack.generator)">
\(parts.author.isEmpty ? "" : "<meta name=\"author\" content=\"\(esc(parts.author))\">")
<title>\(esc(parts.title))</title>
<style>\(EpubPack.style)\(screen)</style>
</head>
<body>
<header class="cover">\(cover)<p class="title">\(esc(parts.title))</p>\(parts.subtitle.isEmpty ? "" : "<p class=\"subtitle\">\(esc(parts.subtitle))</p>")\(parts.author.isEmpty ? "" : "<p class=\"author\">\(esc(parts.author))</p>")</header>
<nav id="toc" aria-label="\(contents)"><h2>\(contents)</h2>\(nav)</nav>
<main>
\(content.chapters.map { "<section class=\"qc-chapter\">\(body($0))</section>" }.joined(separator: "\n"))
</main>
</body>
</html>

"""
    return Result(bytes: Data(html.utf8), chapters: content.chapters.count, pictures: uris.count)
  }
}
