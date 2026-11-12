import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own export/documentHtml.ts and the window-free parts of
/// exportService.ts (`scripts/document-golden.mjs`): print widths and rules for every paper size,
/// 16 documents, backlinks and register in three languages, keywords, identifiers, megabytes and 16
/// cover pictures from files in a project folder. `@@<lang>:<key>@@` in the golden is QuartzControl's
/// `mainTIn`; the test fills in the catalog's text in that language.
@Suite struct DocumentHTMLTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/document/golden.json")))

  static func texts(_ text: String) -> String {
    var out = text
    for match in JSText.matches(text, #"@@([^:@]*):([A-Za-z0-9_]+)@@"#).reversed() {
      let replacement = L10n.t(in: match.groups[1] ?? "", "main.\(match.groups[2] ?? "")")
      out = (out as NSString).replacingCharacters(in: match.range, with: replacement)
    }
    return out
  }

  static func texts(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string(let text): return .string(texts(text))
    case .array(let items): return .array(items.map(texts))
    case .object(let object):
      var copy = JSONObject()
      for key in object.keys { copy[key] = texts(object[key]!) }
      return .object(copy)
    default: return value
    }
  }

  static func item(_ value: JSONValue) -> DocItem {
    value["kind"] == .string("heading") ? .heading(text: value["text"]!.stringValue!)
      : .page(slug: value["slug"]!.stringValue!, level: Int(value["level"]!.numberValue!))
  }

  static func page(_ value: JSONValue) -> CollectedPage {
    CollectedPage(slug: value["slug"]!.stringValue!, title: value["title"]!.stringValue!, lang: value["lang"]!.stringValue!,
                  html: value["html"]!.stringValue!, images: value["images"]!.arrayValue!.map { $0.stringValue! },
                  level: Int(value["level"]!.numberValue!))
  }

  static func parts(_ value: JSONValue) -> DocumentHTML.Parts {
    DocumentHTML.Parts(lang: value["lang"]!.stringValue!, title: value["title"]!.stringValue!, subtitle: value["subtitle"]!.stringValue!,
                       author: value["author"]!.stringValue!, meta: value["meta"]!.stringValue!, coverImage: value["coverImage"]?.stringValue,
                       stylesheets: value["stylesheets"]!.arrayValue!.map { $0.stringValue! }, items: value["items"]!.arrayValue!.map(item),
                       pages: value["pages"]!.arrayValue!.map(page), toc: value["toc"]!.boolValue!, pageSize: value["pageSize"]!.stringValue!,
                       landscape: value["landscape"]!.boolValue!)
  }

  static func facts(_ value: JSONValue) -> SiteFacts {
    var facts = SiteFacts(slugs: [], pages: [:], languages: [], defaultLanguage: "", langOf: [:], langOrder: [])
    for pair in value.arrayValue! {
      let slug = pair.arrayValue![0].stringValue!, p = pair.arrayValue![1]
      facts.slugs.append(slug)
      facts.pages[slug] = SiteFacts.Page(title: p["title"]?.stringValue ?? slug, filePath: nil, tags: p["tags"]!.arrayValue!.map { $0.stringValue! },
                                         links: p["links"]?.arrayValue?.map { $0.stringValue! } ?? [])
    }
    return facts
  }

  /// QuartzControl's output with QuartzHub's one deviation: the cover's height follows the paper
  /// (`DocumentHTML.coverHeightMM`). A4 portrait is left as QuartzControl wrote it.
  static func ownCover(_ qc: String, _ size: String, _ landscape: Bool) -> String {
    let img = "body.pdf img { max-width: 100% !important; height: auto !important; break-inside: avoid; }\n"
    let webKit = qc.replacingOccurrences(of: img, with: img + DocumentHTML.webKitPrintRules + "\n")
    if size == "A4" && !landscape { return webKit }
    let own = JSJSON.numberToString(DocumentHTML.coverHeightMM(size, landscape: landscape))
    return webKit.replacingOccurrences(of: ".cover { height: 230mm;", with: ".cover { height: \(own)mm;")
  }

  /// The one rule WebKit needs beyond QuartzControl's (`webKitPrintRules`), once in every document.
  @Test func printsSkippedContent() {
    let css = DocumentHTML.printCss(pageSize: "A4", landscape: false, title: "T")
    #expect(css.components(separatedBy: DocumentHTML.webKitPrintRules).count == 2)
  }

  /// The text area less QuartzControl's 27 mm: A4 portrait is its 230 mm, the others fit their page
  /// (measured: in A5 landscape a 230 mm cover ran onto a second page).
  @Test func coverFitsItsPaper() {
    #expect(DocumentHTML.coverHeightMM("A4", landscape: false) == 230)
    #expect(DocumentHTML.coverHeightMM("A4", landscape: true) == 143)
    #expect(DocumentHTML.coverHeightMM("A5", landscape: false) == 143)
    #expect(DocumentHTML.coverHeightMM("A5", landscape: true) == 81)
    #expect(DocumentHTML.coverHeightMM("Letter", landscape: false) == 212.4)
    #expect(DocumentHTML.coverHeightMM("Letter", landscape: true) == 148.9)
    #expect(DocumentHTML.printCss(pageSize: "A5", landscape: true, title: "T").contains(".cover { height: 81mm;"))
    #expect(DocumentHTML.printCss(pageSize: "A4", landscape: false, title: "T").contains(".cover { height: 230mm;"))
  }

  @Test func printsAsQuartzControl() {
    for w in Self.golden["widths"]!.arrayValue! {
      #expect(DocumentHTML.printWidthPx(w["size"]!.stringValue!, landscape: w["landscape"]!.boolValue!) == Int(w["result"]!.numberValue!))
    }
    for c in Self.golden["css"]!.arrayValue! {
      let size = c["pageSize"]!.stringValue!, landscape = c["landscape"]!.boolValue!
      let css = DocumentHTML.printCss(pageSize: size, landscape: landscape, title: c["title"]!.stringValue!)
      #expect(css == Self.ownCover(c["result"]!.stringValue!, size, landscape), "\(c["title"]!) \(c["pageSize"]!)")
    }
    let constants = Self.golden["constants"]!
    #expect(constants["PAGE_PLACEHOLDER"] == .string(DocumentHTML.pagePlaceholder))
    #expect(constants["headingAnchors"] == .array([0, 4, 12].map { .string(DocumentHTML.headingAnchor($0)) }))
    #expect(constants["MARGIN_MM"]!["left"]!.numberValue! == DocumentHTML.marginMM.left && constants["MARGIN_MM"]!["top"]!.numberValue! == DocumentHTML.marginMM.top)
    for size in ["A4", "A5", "Letter"] {
      #expect(constants["PAGE_MM"]![size]!["w"]!.numberValue! == DocumentHTML.paper(size).w && constants["PAGE_MM"]![size]!["h"]!.numberValue! == DocumentHTML.paper(size).h)
    }
  }

  @Test func setsDocumentsAsQuartzControl() {
    let base = Self.golden["documents"]!["base"]!.objectValue!
    let variants = Self.golden["documents"]!["variants"]!.arrayValue!
    #expect(variants.count == 16)
    for variant in variants {
      var input = base
      let patch = variant["patch"]!.objectValue!
      for key in patch.keys { input[key] = patch[key]! }
      let html = DocumentHTML.document(Self.parts(.object(input)))
      let expected = Self.ownCover(Self.texts(variant["result"]!.stringValue!), input["pageSize"]!.stringValue!, input["landscape"]!.boolValue!)
      #expect(html == expected, "\(JSJSON.compact(.object(patch)))")
    }
  }

  @Test func addsBacklinksRegisterAndKeywordsAsQuartzControl() {
    let base = Self.golden["documents"]!["base"]!
    let facts = Self.facts(Self.golden["factsPages"]!)
    let extras = Self.golden["extras"]!.arrayValue!
    #expect(extras.count == 13)
    for extra in extras {
      var pages = base["pages"]!.arrayValue!.map(Self.page)
      var items = base["items"]!.arrayValue!.map(Self.item)
      let book = extra["book"]!, lang = extra["lang"]!.stringValue!
      let result = ExportExtras.addBacklinksAndRegister(&pages, &items, backlinks: book["backlinks"]!.boolValue!, tagIndex: book["tagIndex"]!.boolValue!,
                                                        facts: extra["facts"] == .string("empty") ? Self.facts(.array([])) : facts, lang: lang)
      let name = "\(JSJSON.compact(book)) \(lang)"
      #expect(Double(result.backlinks) == extra["result"]!["backlinks"]!.numberValue! && Double(result.tags) == extra["result"]!["tags"]!.numberValue!, "\(name)")
      #expect(JSJSON.compact(.array(pages.map(\.json))) == JSJSON.compact(Self.texts(extra["pages"]!)), "\(name): pages")
      #expect(JSJSON.compact(.array(items.map(\.json))) == JSJSON.compact(extra["items"]!), "\(name): items")
    }
    let keywordFacts = Self.facts(.array(Self.golden["keywordFacts"]!.arrayValue!.map { pair in
      .array([pair.arrayValue![0], .object(JSONObject([("tags", pair.arrayValue![1]["tags"]!)]))])
    }))
    for k in Self.golden["keywords"]!.arrayValue! {
      let items = k["items"]!.arrayValue!.map { $0["kind"] == .string("heading") ? DocItem.heading(text: $0["text"]!.stringValue!) : .page(slug: $0["slug"]!.stringValue!, level: 1) }
      #expect(ExportExtras.bookKeywords(items, facts: keywordFacts) == k["result"]!.arrayValue!.map { $0.stringValue! })
    }
  }

  @Test func namesAndCountsAsQuartzControl() {
    for i in Self.golden["identifiers"]!.arrayValue! {
      #expect(ExportExtras.bookIdentifier(site: i["site"]!.stringValue!, bookId: i["id"]!.stringValue!) == i["result"]!.stringValue!)
    }
    for m in Self.golden["megabytes"]!.arrayValue! {
      #expect(ExportExtras.mb(Int(m["bytes"]!.numberValue!)) == m["result"]!.stringValue!, "\(m["bytes"]!)")
    }
    // Node 24's answers.
    for (value, digits, expected) in [(0.25, 1, "0.3"), (0.35, 1, "0.3"), (1.005, 2, "1.00"), (-0.04, 1, "-0.0"), (2.5, 0, "3"), (999.95, 1, "1000.0"),
                                      (0.05, 1, "0.1"), (-0.0, 1, "0.0"), (1e20, 1, "100000000000000000000.0"), (0.000001, 3, "0.000")] as [(Double, Int, String)] {
      #expect(JS.toFixed(value, digits) == expected, "\(value)")
    }
  }

  @Test func findsCoversAsQuartzControl() throws {
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-document-covers"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let project = "\(work)/Gärten-Ü", build = "\(work)/kopie"
    func write(_ path: String, _ text: String) throws {
      try Posix.mkdirs(NodePath.dirname(path))
      try Posix.write(path, Data(text.utf8))
    }
    try write("\(project)/static/cover.png", "png-bytes")
    try write("\(project)/static/cover.JPG", "jpg-bytes")
    try write("\(project)/static/cover.bmp", "bmp-bytes")
    try write("\(project)/static/vektor.svg", "<svg/>")
    try Posix.mkdirs("\(project)/static/ordner.png")
    try write("\(work)/draussen.png", "outside")
    try Posix.symlink("\(work)/draussen.png", "\(project)/static/link.png")
    try write("\(build)/static/icon.png", "icon-bytes")
    let covers = Self.golden["covers"]!.arrayValue!
    #expect(covers.count == 16)
    for cover in covers {
      if cover["withIcon"] == .bool(false) { try? FileManager.default.removeItem(atPath: "\(build)/static/icon.png") }
      let image = cover["coverImage"]!.stringValue!.replacingOccurrences(of: "@W@", with: work)
      let actual: JSONValue
      do {
        let found = try ExportExtras.coverPicture(project: project, buildRoot: build, coverImage: image)
        actual = .object(JSONObject([
          ("ownMissing", .bool(found.ownMissing)),
          ("picture", found.picture.map { .object(JSONObject([("type", .string($0.type)), ("text", .string(String(decoding: $0.data, as: UTF8.self)))])) } ?? .null)
        ]))
      } catch {
        actual = .object(JSONObject([("error", .string(error.message.replacingOccurrences(of: work, with: "@W@")))]))
      }
      #expect(JSJSON.compact(actual) == JSJSON.compact(cover["result"]!), "\(image)")
    }
  }
}
