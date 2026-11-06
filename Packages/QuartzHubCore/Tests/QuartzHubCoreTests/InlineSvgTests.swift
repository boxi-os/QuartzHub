import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own inlineSvg.ts running in Chrome: `scripts/inline-svg-golden.mjs`
/// recorded its answer for the corpus of check:inline-svg and the edges of the XML side.
@Suite struct InlineSvgTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/inline-svg")

  @Test func asQuartzControlInChrome() throws {
    let cases = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("cases.json"))).arrayValue ?? []
    #expect(cases.count >= 70)
    for entry in cases {
      let name = entry["name"]!.stringValue!
      let got = InlineSvg.clean(entry["text"]!.stringValue!, fileName: entry["file"]!.stringValue!)
      let expected = entry["result"]!
      guard expected["ok"] == .bool(true) else {
        #expect(got == nil, "\(name): should be refused")
        continue
      }
      guard let got else { Issue.record("\(name): refused, QuartzControl took it"); continue }
      if .string(got.markup) != expected["markup"] { Issue.record("\(name):\n\(firstDifference(got.markup, expected["markup"]!.stringValue!))") }
      #expect(.number(Double(got.removed)) == expected["removed"] && .bool(got.styled) == expected["styled"], "\(name): removed \(got.removed) styled \(got.styled)")
    }
  }
}

extension InlineSvgTests {
  /// Ten levels of ten references each would be 10¹⁰ texts: the expansion stops at its ceiling,
  /// and fast. An external entity is never read (the golden case "DOCTYPE mit externer Entity").
  @Test func billionLaughsEndAtTheCeiling() {
    var entities = "<!ENTITY l0 \"ha\">"
    for level in 1...10 { entities += "<!ENTITY l\(level) \"" + String(repeating: "&l\(level - 1);", count: 10) + "\">" }
    let text = "<?xml version=\"1.0\"?><!DOCTYPE svg [\(entities)]><svg xmlns=\"http://www.w3.org/2000/svg\"><text>&l10;</text></svg>"
    let clock = ContinuousClock()
    let took = clock.measure { #expect(InlineSvg.clean(text, fileName: "lol.svg") == nil) }
    #expect(took < .seconds(2))
  }
}
