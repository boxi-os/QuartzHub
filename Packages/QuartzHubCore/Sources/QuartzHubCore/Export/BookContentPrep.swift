import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `prepareBookContent` and `drawPictures` (`writeEpub.ts`): the book in the form a reader takes,
/// shared by the ePub and the offline HTML - chapters as XHTML bodies (epubChapters in the export
/// window), the navigation, every picture of the site as bytes, and each formula and diagram drawn
/// as a PNG with the size it had on the website in em. Packed by `EpubPack` and `HtmlPack`.
@MainActor
public enum BookContentPrep {
  /// EPUB 3.3 core media types for pictures (`IMAGE_TYPES`).
  static let imageTypes: [(ext: String, type: String)] = [
    (".png", "image/png"), (".jpg", "image/jpeg"), (".jpeg", "image/jpeg"), (".gif", "image/gif"), (".svg", "image/svg+xml"), (".webp", "image/webp")
  ]
  /// How much larger than CSS pixels a picture is drawn: sharp on paper-like screens.
  static let zoom = ["formula": 3.0, "diagram": 2.0]
  /// The window the pictures are drawn in; what lies outside it is not drawn.
  public static let drawWidth = 3000, drawHeight = 3000
  /// The reader's base size the em sizes are relative to.
  static let basePx = 16.0

  public struct Input: Sendable {
    public var lang: String
    public var items: [DocItem]
    public var pages: [CollectedPage]
    /// The site's stylesheets, to draw formulas with KaTeX's CSS and fonts and diagrams in the site's fonts.
    public var stylesheets: [String]
    public var cover: (data: Data, type: String)?

    public init(lang: String, items: [DocItem], pages: [CollectedPage], stylesheets: [String], cover: (data: Data, type: String)?) {
      self.lang = lang
      self.items = items
      self.pages = pages
      self.stylesheets = stylesheets
      self.cover = cover
    }
  }

  public static func prepare(_ window: ExportWindow, server: SiteServer, _ input: Input) async throws -> BookContent {
    var byslug: [String: CollectedPage] = [:]
    for page in input.pages { byslug[page.slug] = page }
    var inputs: [JSONValue] = []
    var titles: [String] = []
    var nav: [BookContent.NavEntry] = []
    for (index, item) in input.items.enumerated() {
      let file = "text/c\(String(format: "%04d", inputs.count + 1)).xhtml"
      switch item {
      case .heading(let text):
        let anchor = DocumentHTML.headingAnchor(index)
        inputs.append(.object(JSONObject([("file", .string(file)), ("anchor", .string(anchor)), ("level", .number(1)), ("title", .string(text)), ("html", .string(""))])))
        titles.append(text)
        nav.append(.init(href: "\(file)#\(anchor)", title: text, level: 1))
      case .page(let slug, _):
        guard let page = byslug[slug] else { continue }
        let anchor = ExportModel.anchor(page.slug)
        inputs.append(.object(JSONObject([
          ("file", .string(file)), ("slug", .string(page.slug)), ("anchor", .string(anchor)), ("level", .number(Double(page.level))),
          ("title", .string(page.title)), ("html", .string(page.html))
        ])))
        titles.append(page.title)
        nav.append(.init(href: "\(file)#\(anchor)", title: page.title, level: page.level))
      }
    }

    // A page of the site's own, so that relative addresses in the chapters resolve against it.
    try await window.load(server.origin + server.copy.setDocument("epub.html", "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>"))
    try Task.checkCancellation()
    let result = try await window.run("epubChapters", [.object(JSONObject([
      ("chapters", .array(inputs)), ("imageNames", .object(JSONObject())),
      ("imageExtensions", .array(imageTypes.map { .string(JSText.slice($0.ext, 1)) })),
      ("formulaAlt", .string(L10n.t(in: input.lang, "main.docFormulaAlt"))), ("diagramAlt", .string(L10n.t(in: input.lang, "main.docDiagramAlt")))
    ]))])
    let chapters = result["chapters"]?.arrayValue ?? []
    let broken = chapters.filter { ($0["parseError"]?.stringValue ?? "").isEmpty == false }
    if !broken.isEmpty {
      throw PublishFailure(L10n.t("main.exportEpubNotWellFormed", ["files": broken.prefix(5).map { "\($0["file"]?.stringValue ?? ""): \($0["parseError"]?.stringValue ?? "")" }.joined(separator: "\n")]))
    }

    var assets: [(name: String, asset: BookContent.Asset)] = []
    func setAsset(_ name: String, _ asset: BookContent.Asset) {
      if let i = assets.firstIndex(where: { $0.name == name }) { assets[i].asset = asset } else { assets.append((name, asset)) }
    }
    var images: [(name: String, url: String)] = []
    for chapter in chapters {
      for image in chapter["images"]?.arrayValue ?? [] {
        guard let name = image["name"]?.stringValue, let url = image["url"]?.stringValue else { continue }
        if let i = images.firstIndex(where: { $0.name == name }) { images[i].url = url } else { images.append((name, url)) }
      }
    }
    for (name, url) in images {
      let type = imageTypes.first { $0.ext == NodePath.extname(name).lowercased() }?.type
      let data = JSText.startsWith(url, "data:") ? dataURLBytes(url) : readSiteFile(server.copy.root, url)
      // The page showed this picture from the build, so it is in the copy; one that is not means the
      // copy and the pages disagree, and the book would carry a reference to nothing.
      guard let data, let type else {
        throw PublishFailure(L10n.t("main.exportEpubImageMissing", ["url": JSText.startsWith(url, "data:") ? JSText.slice(url, 0, 40) : WebURL(url).parts?.pathname ?? url]))
      }
      setAsset(name, .init(data: data, type: type))
    }

    var bodies = chapters.map { $0["body"]?.stringValue ?? "" }
    let drawings = (result["drawings"]?.arrayValue ?? []).map(Drawing.init)
    if !drawings.isEmpty {
      let drawn = try await drawPictures(window, server: server, stylesheets: input.stylesheets, drawings)
      for (name, picture) in drawn { setAsset(name, .init(data: picture.data, type: "image/png")) }
      bodies = bodies.map { body in
        var out = ""
        var last = 0
        for m in JSText.matches(body, #"data-qc-drawing="([^"]+)""#) {
          out += JSText.slice(body, last, m.index)
          if let picture = drawn.first(where: { $0.name == m.groups[1] })?.picture { out += "style=\"\(picture.style)\"" }
          last = m.end
        }
        return out + JSText.slice(body, last)
      }
    }

    let coverExt = input.cover.flatMap { cover in imageTypes.first { $0.type == cover.type }?.ext }
    let cover = input.cover.flatMap { c in coverExt.map { (name: "images/cover\($0)", asset: BookContent.Asset(data: c.data, type: c.type)) } }

    var counts = BookContent.Counts()
    let c = result["counts"]
    let n = { (key: String) in Int(c?[key]?.numberValue ?? 0) }
    counts.externalImages = n("externalImages")
    counts.unsupportedImages = n("unsupportedImages")
    counts.unresolvedLinks = n("unresolvedLinks")
    counts.footnotes = n("footnotes")
    counts.formulas = n("formulas")
    counts.diagrams = n("diagrams")
    return BookContent(
      chapters: chapters.enumerated().map { i, chapter in
        .init(file: chapter["file"]?.stringValue ?? "", title: titles[i], body: bodies[i], hasMath: chapter["hasMath"] == .bool(true), hasSvg: chapter["hasSvg"] == .bool(true))
      },
      nav: nav, assets: assets, cover: cover,
      drawings: (drawings.filter { $0.kind == "formula" }.count, drawings.filter { $0.kind == "diagram" }.count),
      counts: counts)
  }

  /// A formula or diagram epubChapters set aside to be drawn.
  struct Drawing: Sendable {
    var name: String
    var html: String
    /// "formula" or "diagram".
    var kind: String
    /// A formula set as its own block; a diagram is always one.
    var display: Bool

    init(_ value: JSONValue) {
      name = value["name"]?.stringValue ?? ""
      html = value["html"]?.stringValue ?? ""
      kind = value["kind"]?.stringValue ?? ""
      display = value["display"] == .bool(true)
    }
  }

  public struct Picture: Equatable, Sendable {
    public var data: Data
    /// The size it had on the website in em, so it grows with the reader's font size.
    public var style: String
    public var pixels: (width: Int, height: Int)

    public static func == (a: Picture, b: Picture) -> Bool { a.data == b.data && a.style == b.style && a.pixels == b.pixels }
  }

  /// `drawPictures`: every formula and diagram as a PNG, in a window of its own at 3000 x 3000 (the
  /// export window keeps the print width). A diagram is drawn at the width Mermaid gave it (its
  /// max-width, else its viewBox), not at a column's; a wide one at a smaller zoom rather than cut
  /// off. What that window refused and fetched is added to the export window's.
  static func drawPictures(_ window: ExportWindow, server: SiteServer, stylesheets: [String], _ drawings: [Drawing]) async throws -> [(name: String, picture: Picture)] {
    let draw = window.sibling(size: CGSize(width: drawWidth, height: drawHeight))
    defer {
      window.absorb(draw)
      draw.close()
    }
    try await draw.prepare()
    let head = stylesheets.map { "<link rel=\"stylesheet\" href=\"\(DocumentHTML.esc($0))\">" }.joined()
    try await draw.load(server.origin + server.copy.setDocument("drawing.html", """
      <!doctype html><html saved-theme="light"><head><meta charset="utf-8">\(head)<style>html,body{margin:0!important;padding:0!important;background:#fff!important}#f{display:inline-block;padding:1px 2px;background:#fff}#f .katex-display{margin:0!important}#f.diagram{display:block;width:max-content;padding:4px}#f.diagram>svg{display:block;max-width:none!important;height:auto}</style></head><body><div id="f"></div></body></html>
      """))
    var out: [(name: String, picture: Picture)] = []
    for d in drawings {
      try Task.checkCancellation()
      _ = try await draw.evaluate("""
        const box = document.getElementById('f');
        box.className = diagram ? 'diagram' : '';
        box.innerHTML = html;
        const svg = diagram ? box.querySelector('svg') : null;
        if (svg) {
          const max = parseFloat(svg.style.maxWidth);
          const width = Number.isFinite(max) && max > 0 ? max : (svg.viewBox.baseVal && svg.viewBox.baseVal.width) || svg.getBoundingClientRect().width;
          svg.style.width = `${width}px`;
        }
        """, arguments: ["html": .string(d.html), "diagram": .bool(d.kind == "diagram")])
      // Fonts loaded, then measured (which lays out). QuartzControl waited for two animation frames
      // as well, because capturePage takes the frame last painted; takeSnapshot paints anew, and in
      // a window at alpha 0 requestAnimationFrame never fires (measured 2026-11-08: WebKit takes it
      // for hidden, a probe of 2 s timed out in every export window).
      let r = try await draw.evaluate("""
        await document.fonts.ready;
        const r = document.getElementById('f').getBoundingClientRect();
        return { x: r.x, y: r.y, width: r.width, height: r.height };
        """)
      let x = r["x"]?.numberValue ?? 0, y = r["y"]?.numberValue ?? 0
      let width = r["width"]?.numberValue ?? 0, height = r["height"]?.numberValue ?? 0
      let zoom = min(zoom[d.kind] ?? 2, Double(drawWidth) / (x + width), Double(drawHeight) / (y + height))
      let left = (x * zoom).rounded(.down), top = (y * zoom).rounded(.down)
      let pixelsWide = Int((width * zoom).rounded(.up)), pixelsHigh = Int((height * zoom).rounded(.up))
      let notDrawn = PublishFailure(d.kind == "formula" ? L10n.t("main.exportFormulaNotDrawn") : L10n.t("main.exportDiagramNotDrawn"))
      guard width > 0, height > 0 else { throw notDrawn }
      // Electron drew one larger than the window at a zoom below 1, where the page had room for it;
      // here the zoom is the picture's size only, so the view grows to hold it.
      draw.makeRoom(CGSize(width: (x + width).rounded(.up), height: (y + height).rounded(.up)))
      let rect = CGRect(x: left / zoom, y: top / zoom, width: Double(pixelsWide) / zoom, height: Double(pixelsHigh) / zoom)
      guard let image = try await draw.snapshot(rect, pixels: pixelsWide, pixelsHigh), let png = pngData(image) else { throw notDrawn }
      let em = { (px: Double) in "\(JS.toFixed(px / basePx, 3))em" }
      out.append((d.name, Picture(data: png, style: d.display ? "width:\(em(width));max-width:100%" : "height:\(em(height));vertical-align:middle",
                                  pixels: (pixelsWide, pixelsHigh))))
    }
    return out
  }

  nonisolated static func pngData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  /// `dataUrlBytes`: the bytes of a picture written into a page as a data: URL (base64 or
  /// percent-encoded); nil when it does not decode.
  nonisolated static func dataURLBytes(_ url: String) -> Data? {
    guard let m = JSText.firstMatch(url, #"\Adata:[^,]*?(;base64)?,([\s\S]*)\z"#) else { return nil }
    let payload = m.groups[2] ?? ""
    if m.groups[1] != nil {
      // Node's Buffer.from(…, 'base64') skips what is not base64 and needs no padding.
      var clean = String(String.UnicodeScalarView(payload.unicodeScalars.filter {
        ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || "+/-_".unicodeScalars.contains($0)
      }))
      clean = clean.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
      if clean.count % 4 == 1 { clean.removeLast() }
      clean += String(repeating: "=", count: (4 - clean.count % 4) % 4)
      return Data(base64Encoded: clean)
    }
    guard let text = try? JSURI.decodeComponent(payload) else { return nil }
    return Data(text.utf8)
  }

  /// `readSiteFile`: a picture of the build, read from the served copy by its address; nil for an
  /// address that does not decode, leads out of the copy or names no readable file.
  nonisolated static func readSiteFile(_ root: String, _ url: String) -> Data? {
    guard let pathname = WebURL(url).parts?.pathname, let decoded = try? JSURI.decodeComponent(pathname) else { return nil }
    let file = NodePath.join(root, decoded)
    let rel = NodePath.relative(root, file)
    if JSText.startsWith(rel, "..") || JSText.startsWith(rel, "/") { return nil }
    return try? Posix.read(file)
  }
}
