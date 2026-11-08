import AppKit
import Foundation
import PDFKit
import Testing
@testable import QuartzHubCore

/// The PDF writer's work after WebKit's print, on PDFs made here: the marks read in document order,
/// the outline nested by level, the footer as text, the metadata, and the catalog's `/Lang` read
/// back by Core Graphics (another reader than the one that wrote it). The print itself is measured
/// with `qh-check export-book --pdf` and QuartzControl's `check:export -- --files`.
@Suite struct PDFFinishTests {
  /// A PDF of `pages` A4 pages, each with its number as text, made as WebKit's print makes it
  /// (Core Graphics with named destinations, which it writes as links to explicit targets). With
  /// `marks`, the cover has a 0.8 pt link per (page index, y) in document order, one line after
  /// another and drawn in reverse, so only their place orders them; and a link of the site, which
  /// is no mark.
  static func printed(pages: Int, marks: [(page: Int, y: CGFloat)] = [], perLine: Int = 3) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    for i in 0..<pages {
      context.beginPDFPage(nil)
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
      NSAttributedString(string: "Seite \(i + 1)", attributes: [.font: NSFont.systemFont(ofSize: 12)]).draw(at: CGPoint(x: 72, y: 700))
      if i == 0 && !marks.isEmpty {
        for (n, _) in marks.enumerated().reversed() {
          context.setDestination("m\(n)" as CFString, for: CGRect(x: 51 + CGFloat(n % perLine) * 0.8, y: 783.9 - CGFloat(n / perLine) * 0.8, width: 0.8, height: 0.8))
        }
        context.setDestination("site" as CFString, for: CGRect(x: 51, y: 400, width: 120, height: 14))
      }
      for (n, mark) in marks.enumerated() where mark.page == i { context.addDestination("m\(n)" as CFString, at: CGPoint(x: 51, y: mark.y)) }
      if i == 1 { context.addDestination("site" as CFString, at: CGPoint(x: 51, y: 700)) }
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }

  /// `/Lang` and `/ViewerPreferences /DisplayDocTitle` as Core Graphics reads them (the catalog
  /// lives as long as its document).
  static func catalog(_ data: Data) -> (lang: String?, showsTitle: Bool) {
    guard let doc = CGPDFDocument(CGDataProvider(data: data as CFData)!), let catalog = doc.catalog else { return (nil, false) }
    var value: CGPDFStringRef?
    let lang = CGPDFDictionaryGetString(catalog, "Lang", &value) ? value.flatMap { CGPDFStringCopyTextString($0) as String? } : nil
    var prefs: CGPDFDictionaryRef?
    var shown: CGPDFBoolean = 0
    let showsTitle = CGPDFDictionaryGetDictionary(catalog, "ViewerPreferences", &prefs) && prefs.map { CGPDFDictionaryGetBoolean($0, "DisplayDocTitle", &shown) } == true && shown != 0
    return withExtendedLifetime(doc) { (lang, showsTitle) }
  }

  @Test func marksInDocumentOrder() throws {
    let data = Self.printed(pages: 4, marks: [(1, 800), (2, 500), (2, 300), (3, 800), (1, 200)])
    let doc = try #require(PDFFinish.open(data))
    #expect(PDFFinish.markLinks(doc).count == 5)
    let marks = ["a", "b", "c", "d", "e"].map { PDFFinish.Mark(id: $0, level: 1, label: $0) }
    #expect(PDFFinish.pages(doc, marks) == ["a": 2, "b": 3, "c": 3, "d": 4, "e": 2])
  }

  @Test func finishedFile() throws {
    let data = Self.printed(pages: 3, marks: [(1, 800), (1, 600), (1, 400), (2, 800), (2, 600), (2, 300), (1, 100)])
    let doc = try #require(PDFFinish.open(data))
    let marks: [PDFFinish.Mark] = [
      .init(id: "a", level: 1, label: "Erste Seite"), .init(id: "b", level: 2, label: "Abschnitt"), .init(id: "c", level: 3, label: "Unterabschnitt"),
      .init(id: "d", level: 1, label: "Zweite Seite"), .init(id: "e", level: 3, label: "Tief"), .init(id: "f", level: 2, label: "Flacher"),
      .init(id: "g", level: 0, label: "")
    ]
    let bytes = try PDFFinish.finish(doc, marks: marks, footer: "Gärten-Ü", PdfMeta(title: "Gärten-Ü", subtitle: "Unter", author: "A. Autor",
                                                                                   keywords: ["eins", "zwei drei"], lang: "de"))
    let final = try #require(PDFDocument(data: bytes))
    // Nested by level; a level-3 heading right under a level 1 goes under it, the 2 after it too.
    #expect(PDFFinish.outlineLevels(final) == [2, 3, 1])
    let root = try #require(final.outlineRoot)
    #expect(root.child(at: 0)?.label == "Erste Seite")
    #expect(root.child(at: 1)?.child(at: 0)?.label == "Tief")
    #expect(root.child(at: 1)?.child(at: 1)?.label == "Flacher")
    #expect(root.child(at: 1)?.destination?.page.map { final.index(for: $0) } == 2)
    // The marks are gone, the site's link stays.
    #expect(final.page(at: 0)?.annotations.count == 1)
    // The footer is text on every page but the cover.
    #expect(final.page(at: 0)?.string?.contains("/ 3") == false)
    #expect(final.page(at: 1)?.string?.contains("2 / 3") == true)
    #expect(final.page(at: 2)?.string?.contains("Gärten-Ü") == true)
    #expect(final.page(at: 2)?.string?.contains("Seite 3") == true)
    let attributes = final.documentAttributes ?? [:]
    #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Gärten-Ü")
    #expect(attributes[PDFDocumentAttribute.subjectAttribute] as? String == "Unter")
    #expect(attributes[PDFDocumentAttribute.authorAttribute] as? String == "A. Autor")
    #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == "QuartzHub")
    #expect((attributes[PDFDocumentAttribute.keywordsAttribute] as? [String])?.joined(separator: ",") == "eins zwei drei")
    // Patched onto PDFKit's own output, with its outline in the catalog.
    #expect(Self.catalog(bytes).lang == "de")
    #expect(Self.catalog(bytes).showsTitle)
  }

  @Test(arguments: [("de-DE", "de-DE"), ("a(b)\\c", "a(b)\\c"), ("zh-Hänt", "zh-Hänt")])
  func catalogLanguage(lang: String, read: String) throws {
    let data = Self.printed(pages: 1)
    #expect(Self.catalog(data).lang == nil)
    let patched = try #require(PDFFinish.patchCatalog(data, lang: lang))
    #expect(Self.catalog(patched).lang == read)
    #expect(Self.catalog(patched).showsTitle)
    #expect(PDFDocument(data: patched)?.pageCount == 1)
    // Once more: the keys are there, nothing is added.
    #expect(PDFFinish.patchCatalog(patched, lang: "en") == patched)
  }

  @Test func notAPDF() {
    #expect(PDFFinish.patchCatalog(Data("%PDF-1.4\nkaputt".utf8), lang: "de") == nil)
    #expect(PDFFinish.patchCatalog(Data(), lang: "de") == nil)
  }

  @Test func problemText() {
    let problems = try! JSJSON.parse(#"{"overflow":["A: <pre> 12 px"],"deadLinks":[],"brokenImages":["B: x.png","C: y.png"],"counted":{"links":3,"images":2}}"#)
    #expect(PDFWrite.problemText(problems) == """
      \(L10n.t("main.exportProblemOverflow")) (1):
        A: <pre> 12 px
      \(L10n.t("main.exportProblemImages")) (2):
        B: x.png
        C: y.png
      """)
    #expect(PDFWrite.problemText(try! JSJSON.parse(#"{"overflow":[],"deadLinks":[],"brokenImages":[]}"#)) == nil)
  }
}
