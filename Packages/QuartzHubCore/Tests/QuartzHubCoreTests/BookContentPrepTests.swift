import Foundation
import Testing
@testable import QuartzHubCore

/// The parts of `prepareBookContent` that run without WebKit: a picture written into a page as a
/// data: URL, and a picture read from the copy of the build by its address. The cases are Node's
/// answers to QuartzControl's `dataUrlBytes` (Node 24.22.2, 2026-11-08). The window's part is
/// measured with `qh-check export-book`.
@Suite struct BookContentPrepTests {
  @Test(arguments: [
    ("data:image/png;base64,aGk=", "6869"),
    // Buffer.from(…, 'base64') needs no padding, skips spaces and line ends, takes the URL alphabet.
    ("data:;base64,aGk", "6869"),
    ("data:;base64,aG k=\n", "6869"),
    ("data:;base64,-_8", "fbff"),
    ("data:;base64,+/8=", "fbff"),
    ("data:;base64,aGVsbG8gd29ybGQ", "68656c6c6f20776f726c64"),
    ("data:;base64,a", ""),
    ("data:image/svg+xml,%3Csvg%3E", "3c7376673e"),
    ("data:text/plain,a,b", "612c62"),
    ("data:,%E0%A4%A", nil),
    ("nodata", nil)
  ] as [(String, String?)])
  func dataURLAsNode(url: String, hex: String?) {
    #expect(BookContentPrep.dataURLBytes(url).map { $0.map { String(format: "%02x", $0) }.joined() } == hex)
  }

  @Test func readsPicturesOfTheCopyOnly() throws {
    let work = TestFolder.make("qh-book-content")
    defer { try? FileManager.default.removeItem(atPath: work) }
    let root = "\(work)/kopie"
    try Posix.mkdirs("\(root)/Bilder")
    try Posix.write("\(root)/Bilder/\u{DC}bersicht.png", Data("bild".utf8))
    try Posix.write("\(work)/geheim.txt", Data("geheim".utf8))
    #expect(BookContentPrep.readSiteFile(root, "http://127.0.0.1:1234/Bilder/%C3%9Cbersicht.png") == Data("bild".utf8))
    #expect(BookContentPrep.readSiteFile(root, "http://127.0.0.1:1234/Bilder/%C3%9Cbersicht.png?v=1#x") == Data("bild".utf8))
    // Out of the copy by an escaped "..": refused; WHATWG resolves a written one within the copy.
    #expect(BookContentPrep.readSiteFile(root, "http://127.0.0.1:1234/Bilder/..%2f..%2fgeheim.txt") == nil)
    #expect(BookContentPrep.readSiteFile(root, "http://127.0.0.1:1234/../geheim.txt") == nil)
    #expect(BookContentPrep.readSiteFile(root, "http://127.0.0.1:1234/Bilder/fehlt.png") == nil)
    #expect(BookContentPrep.readSiteFile(root, "http://127.0.0.1:1234/%E0%A4%A") == nil)
  }

  @Test func extractedPageAsCollected() {
    let value = try! JSJSON.parse(#"{"slug":"a/b","title":"B","lang":"de","html":"<p>x</p>","images":["http://h/i.png"],"counts":{"outsideLinks":2,"textLinks":1,"forms":0,"frames":3,"media":0,"canvases":0,"unrenderedDiagrams":4}}"#)
    let page = ExportCollect.collected(value, level: 3)
    var counts = CollectedPage.Counts()
    counts.outsideLinks = 2
    counts.textLinks = 1
    counts.frames = 3
    counts.unrenderedDiagrams = 4
    #expect(page == CollectedPage(slug: "a/b", title: "B", lang: "de", html: "<p>x</p>", images: ["http://h/i.png"], level: 3, counts: counts))
    #expect(JSJSON.compact(page.json) == #"{"slug":"a/b","title":"B","lang":"de","html":"<p>x</p>","images":["http://h/i.png"],"level":3,"counts":{"outsideLinks":2,"textLinks":1,"forms":0,"frames":3,"media":0,"canvases":0,"unrenderedDiagrams":4}}"#)
  }
}
