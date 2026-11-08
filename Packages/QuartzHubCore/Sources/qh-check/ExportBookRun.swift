import AppKit
import Foundation
import QuartzHubCore

/// `qh-check export-book <build> <out> [--language <code>] [--offline]`: a whole build through the
/// export as far as the reader formats go - the navigation's order, every page collected,
/// epubChapters, every formula and diagram drawn - in WebKit, written to <out>: `content.json`
/// (chapters, navigation, counts, each picture's size and style, what was refused and fetched),
/// `pictures/` (the drawn PNGs) and `book.epub`. For looking at the pictures and for comparing
/// with the same steps in Chrome; the export itself is `exportBook` (9c). `--offline` refuses what
/// the rule lets in from outside (use a copy from `scripts/cdn-build.mjs` for Mermaid and KaTeX).
@MainActor
func runExportBookCheck(root: String, build: String, out: String, language: String, offline: Bool) async -> Int32 {
  let scripts: String
  do {
    scripts = try ExportWindow.pageScripts(location: RuntimeLocation(node: "", git: "", helpers: "\(root)/Helpers/dist"))
    try Posix.mkdirs("\(out)/pictures")
  } catch {
    print("page-scripts.js nicht lesbar oder Ziel nicht anlegbar: \(error)")
    return 2
  }
  let server: SiteServer
  let facts: SiteFacts
  do {
    server = try await SiteServer.start(try SiteCopy.make(from: build))
    facts = try SiteFacts.read(root: server.copy.root)
  } catch {
    print("Build nicht ausgeliefert oder nicht lesbar: \(error)")
    return 2
  }
  defer { server.close() }
  let window = ExportWindow(origin: server.origin, size: CGSize(width: DocumentHTML.printWidthPx("A4", landscape: false), height: 1000),
                            pageScripts: scripts, outside: !offline)
  defer { window.close() }
  do {
    let started = Date()
    try await window.prepare()
    let nav = try await ExportCollect.navigationOrder(window, origin: server.origin, facts: facts, language: language)
    let resolved = ExportModel.resolveOrder(order: nil, excluded: [], root: facts.effectiveRoot("", language: language), navigation: nav.slugs,
                                            available: Set(facts.pages(inLanguage: language)))
    print("Reihenfolge: \(nav.source), \(resolved.items.count) Einträge")
    let docLanguage = language.isEmpty ? (facts.defaultLanguage.isEmpty ? "en" : facts.defaultLanguage) : language
    let pages = try await ExportCollect.pages(window, origin: server.origin,
                                              .init(items: resolved.items, baseUrl: "quartzmac.example", outsideLinks: "site", language: docLanguage)) { done, total, _ in
      if done % 20 == 0 || done == total { print("  \(done)/\(total)") }
    }
    let stylesheets = try await window.evaluate("return [...document.querySelectorAll('head link[rel=\"stylesheet\"]')].map((l) => l.href);")
      .arrayValue?.compactMap(\.stringValue) ?? []
    let lang = pages.first?.lang ?? docLanguage
    let collected = Date()
    let content = try await BookContentPrep.prepare(window, server: server, .init(lang: lang, items: resolved.items, pages: pages, stylesheets: stylesheets, cover: nil))
    let drawn = Date()
    let epub = try EpubPack.pack(content, BookParts(lang: lang, title: "export-book", subtitle: "", author: "", identifier: "urn:uuid:00000000-0000-5000-8000-000000000000",
                                                     modified: Date(timeIntervalSince1970: 0)))
    try epub.bytes.write(to: URL(fileURLWithPath: "\(out)/book.epub")) // path boundary: a folder the caller names

    var pictures: [JSONValue] = []
    for (name, asset) in content.assets where asset.type == "image/png" && group(name, #"^images/([fd])[0-9]+\.png$"#) != nil {
      try asset.data.write(to: URL(fileURLWithPath: "\(out)/pictures/\(NodePath.basename(name))")) // path boundary
      let size = NSBitmapImageRep(data: asset.data).map { [$0.pixelsWide, $0.pixelsHigh] } ?? []
      let style = content.chapters.lazy.compactMap { chapter in
        group(chapter.body, #"src="\.\./\#(NSRegularExpression.escapedPattern(for: name))"[^>]*style="([^"]*)""#)
      }.first ?? ""
      pictures.append(.object(JSONObject([("name", .string(name)), ("pixels", .array(size.map { .number(Double($0)) })), ("style", .string(style))])))
    }
    let record = JSONObject([
      ("navigation", nav.json), ("items", .number(Double(resolved.items.count))), ("pages", .number(Double(pages.count))),
      ("unfinished", .array(window.unfinished.map(JSONValue.string))),
      ("refused", .object(JSONObject(window.refused.map { ($0.key, .number(Double($0.count))) }))),
      ("fetched", .object(JSONObject(window.fetched.map { ($0.host, .number(Double($0.count))) }))),
      ("counts", .object(JSONObject([
        ("externalImages", content.counts.externalImages), ("unsupportedImages", content.counts.unsupportedImages), ("unresolvedLinks", content.counts.unresolvedLinks),
        ("footnotes", content.counts.footnotes), ("formulas", content.counts.formulas), ("diagrams", content.counts.diagrams)
      ].map { ($0.0, .number(Double($0.1))) }))),
      ("pictures", .array(pictures)),
      ("chapters", .array(content.chapters.map { .object(JSONObject([("file", .string($0.file)), ("title", .string($0.title)), ("body", .string($0.body))])) }))
    ])
    try JSJSON.stringify(.object(record)).write(toFile: "\(out)/content.json", atomically: true, encoding: .utf8) // path boundary
    let secs = { (a: Date, b: Date) in String(format: "%.1f s", b.timeIntervalSince(a)) }
    print("Seiten: \(pages.count) in \(secs(started, collected)); Kapitel: \(content.chapters.count); Bilder: \(content.drawings.formulas) Formeln, \(content.drawings.diagrams) Diagramme in \(secs(collected, drawn)); ePub \(epub.bytes.count) Bytes")
    if !window.refused.isEmpty { print("Gesperrt: \(window.refused.map { "\($0.key) ×\($0.count)" }.joined(separator: ", "))") }
    if !window.fetched.isEmpty { print("Von außen: \(window.fetched.map { "\($0.host) ×\($0.count)" }.joined(separator: ", "))") }
    return 0
  } catch {
    print("Lauf abgebrochen: \(error)")
    return 3
  }
}

/// The first group of the first match, or nil.
func group(_ text: String, _ pattern: String) -> String? {
  guard let m = try? NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let r = Range(m.range(at: 1), in: text) else { return nil }
  return String(text[r])
}
