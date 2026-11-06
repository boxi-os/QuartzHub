import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own fontFile.ts: `scripts/font-file-golden.mjs` made fonts in all three
/// containers with their edges (truncated, lying lengths, decompression bombs, axes, both italic
/// bits) and took four real WOFF2 of gui-test, and recorded `readFontFace` for each.
@Suite struct FontFileTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/font-file")

  @Test func facesAsQuartzControl() throws {
    let cases = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("faces.json"))).arrayValue ?? []
    #expect(cases.count >= 40)
    for entry in cases {
      let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("files").appendingPathComponent(entry["file"]!.stringValue!))
      let face = FontFile.face(data).map { JSONValue.object(JSONObject([("weight", .string($0.weight)), ("italic", .bool($0.italic))])) } ?? .null
      #expect(face == entry["face"], "\(entry["name"]!)")
    }
  }

  /// The bombs end at the ceiling, not at 80 MiB: the decoder holds no more than the limit.
  @Test func aBombStopsAtTheCeiling() throws {
    let bomb = try Data(contentsOf: Self.fixtures.appendingPathComponent("files/woff2-bomb.bin"))
    let clock = ContinuousClock()
    let took = clock.measure { #expect(FontFile.face(bomb) == nil) }
    #expect(took < .seconds(2))
  }
}
