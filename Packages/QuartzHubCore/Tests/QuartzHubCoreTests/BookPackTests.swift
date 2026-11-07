import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own export/writeEpub.ts and writeHtml.ts (`scripts/epub-golden.mjs`):
/// 8 books packed as ePub and offline HTML, 5 navigation lists, the HTML's ceiling. An ePub is
/// compared byte for byte: the entries QuartzControl zipped, with the catalog's texts filled in,
/// zipped again with ZipArchive (measured against QuartzControl's createZip in zip-golden.mjs).
/// One difference, on purpose: the generator is QuartzHub.
@Suite struct BookPackTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/epub/golden.json")))

  static func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: iso)!
  }

  /// The catalog's texts for `@@<lang>:<key>@@`, and QuartzHub's name as the generator.
  static func expected(_ text: String) -> String {
    DocumentHTMLTests.texts(text).replacingOccurrences(of: "content=\"QuartzControl\"", with: "content=\"QuartzHub\"")
  }

  static func content(_ value: JSONValue) -> BookContent {
    let asset = { (v: JSONValue) in BookContent.Asset(data: Data(base64Encoded: v["data"]!.stringValue!)!, type: v["type"]!.stringValue!) }
    var counts = BookContent.Counts()
    let c = value["counts"]!
    counts.externalImages = Int(c["externalImages"]!.numberValue!)
    counts.unsupportedImages = Int(c["unsupportedImages"]!.numberValue!)
    counts.unresolvedLinks = Int(c["unresolvedLinks"]!.numberValue!)
    counts.footnotes = Int(c["footnotes"]!.numberValue!)
    counts.formulas = Int(c["formulas"]!.numberValue!)
    counts.diagrams = Int(c["diagrams"]!.numberValue!)
    return BookContent(
      chapters: value["chapters"]!.arrayValue!.map {
        BookContent.Chapter(file: $0["file"]!.stringValue!, title: $0["title"]!.stringValue!, body: $0["body"]!.stringValue!,
                            hasMath: $0["hasMath"]!.boolValue!, hasSvg: $0["hasSvg"]!.boolValue!)
      },
      nav: value["nav"]!.arrayValue!.map { BookContent.NavEntry(href: $0["href"]!.stringValue!, title: $0["title"]!.stringValue!, level: Int($0["level"]!.numberValue!)) },
      assets: value["assets"]!.arrayValue!.map { ($0.arrayValue![0].stringValue!, asset($0.arrayValue![1])) },
      cover: value["cover"]!.objectValue.map { ($0["name"]!.stringValue!, asset(.object($0))) },
      drawings: (Int(value["drawings"]!["formulas"]!.numberValue!), Int(value["drawings"]!["diagrams"]!.numberValue!)),
      counts: counts)
  }

  static func parts(_ value: JSONValue) -> BookParts {
    BookParts(lang: value["lang"]!.stringValue!, title: value["title"]!.stringValue!, subtitle: value["subtitle"]!.stringValue!,
              author: value["author"]!.stringValue!, identifier: value["identifier"]!.stringValue!, modified: date(value["modified"]!.stringValue!))
  }

  @Test func packsAsQuartzControl() throws {
    #expect(Self.golden["style"]!.stringValue! == EpubPack.style)
    let results = Self.golden["results"]!.arrayValue!
    #expect(results.count == 8)
    for result in results {
      let name = result["name"]!.stringValue!
      let content = Self.content(result["content"]!), parts = Self.parts(result["parts"]!)
      let epub = try EpubPack.pack(content, parts)
      let e = result["epub"]!
      #expect(Double(epub.chapters) == e["chapters"]!.numberValue! && Double(epub.images) == e["images"]!.numberValue!, "\(name)")
      let zip = e["zip"]!
      let entries = zip["entries"]!.arrayValue!.map { entry -> ZipArchive.Entry in
        var data = Data(base64Encoded: entry["data"]!.stringValue!)!
        if let text = String(data: data, encoding: .utf8), entry["name"]!.stringValue!.hasSuffix(".xhtml") || entry["name"]!.stringValue!.hasSuffix(".opf") {
          data = Data(Self.expected(text).utf8)
        }
        return ZipArchive.Entry(name: entry["name"]!.stringValue!, data: data, store: entry["store"]!.boolValue!)
      }
      #expect(Self.date(zip["modified"]!.stringValue!) == parts.modified)
      let expected = try ZipArchive.create(entries, modified: parts.modified)
      if epub.bytes != expected {
        let actual = try ZipArchive.read(epub.bytes)
        #expect(actual.names == entries.map(\.name), "\(name): names")
        for entry in entries where actual[entry.name] != entry.data {
          Issue.record("\(name): \(entry.name)\n\(String(decoding: actual[entry.name] ?? Data(), as: UTF8.self))\n---\n\(String(decoding: entry.data, as: UTF8.self))")
        }
        Issue.record("\(name): bytes differ")
      }
      let html = try HtmlPack.pack(content, parts)
      let h = result["html"]!
      #expect(Double(html.chapters) == h["chapters"]!.numberValue! && Double(html.pictures) == h["pictures"]!.numberValue!, "\(name)")
      #expect(String(decoding: html.bytes, as: UTF8.self) == Self.expected(h["text"]!.stringValue!), "\(name): html")
    }
  }

  @Test func nestsNavigationAsQuartzControl() {
    for list in Self.golden["navLists"]!.arrayValue! {
      let entries = list["entries"]!.arrayValue!.map { BookContent.NavEntry(href: $0["href"]!.stringValue!, title: $0["title"]!.stringValue!, level: Int($0["level"]!.numberValue!)) }
      #expect(EpubPack.navList(entries) == list["result"]!.stringValue!)
    }
  }

  @Test func refusesAnOversizedHTMLAsQuartzControl() throws {
    #expect(Double(HtmlPack.maxBytes) == Self.golden["maxBytes"]!.numberValue!)
    let base = Self.content(Self.golden["results"]!.arrayValue![0]["content"]!)
    let parts = Self.parts(Self.golden["results"]!.arrayValue![0]["parts"]!)
    var big = base
    big.assets = [("images/big.png", BookContent.Asset(data: Data(repeating: 1, count: 3000), type: "image/png"))]
    #expect(throws: PublishFailure(GoldenText.localize(Self.golden["tooLarge"]!["error"]!.stringValue!))) { try HtmlPack.pack(big, parts, maxBytes: 2048) }
    var fits = base
    fits.chapters = []
    fits.nav = []
    fits.cover = nil
    fits.assets = [("images/x.png", BookContent.Asset(data: Data(repeating: 2, count: 1500), type: "image/png"))]
    #expect(String(decoding: try HtmlPack.pack(fits, parts, maxBytes: 2048).bytes, as: UTF8.self) == Self.expected(Self.golden["justFits"]!["ok"]!.stringValue!))
    let limits = Self.golden["limits"]!.arrayValue!
    #expect(limits.count == 7)
    for limit in limits {
      let content = Self.content(limit["content"]!)
      do {
        _ = try HtmlPack.pack(content, parts, maxBytes: 2048)
        #expect(limit["result"]!["ok"] == .bool(true), "\(limit["name"]!)")
      } catch {
        #expect(error.message == GoldenText.localize(limit["result"]!["error"]?.stringValue ?? "ok"), "\(limit["name"]!)")
      }
    }
  }
}
