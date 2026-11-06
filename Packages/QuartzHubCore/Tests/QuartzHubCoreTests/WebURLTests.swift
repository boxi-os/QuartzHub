import Foundation
import Testing
@testable import QuartzHubCore

/// Against Node's WHATWG `URL` (`scripts/web-url-golden.mjs`): 93 inputs, every part compared by
/// UTF-8 bytes; the inputs marked `beyond` are the ones WebURL answers `.unsupported` on purpose.
@Suite struct WebURLTests {
  static let cases: [JSONValue] = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/web-url/cases.json"))).arrayValue!

  @Test func partsAsNode() {
    #expect(Self.cases.count == 93)
    for item in Self.cases {
      let input = item["input"]!.stringValue!
      let url = WebURL(input)
      if item["beyond"] == .bool(true) {
        #expect(url == .unsupported, "\(input): \(url)")
        continue
      }
      if item["throws"] == .bool(true) {
        #expect(url == .invalid, "\(input): \(url)")
        continue
      }
      guard let parts = url.parts else {
        #expect(url == .other(protocol: item["protocol"]!.stringValue!), "\(input): \(url)")
        continue
      }
      let actual: [(String, JSONValue)] = [
        ("protocol", .string(parts.protocol)), ("username", .string(parts.username)), ("password", .string(parts.password)),
        ("hostname", .string(parts.hostname)), ("port", .string(parts.port)), ("pathname", .string(parts.pathname)),
        ("search", .string(parts.search)), ("hash", .string(parts.hash)), ("origin", .string(parts.origin)), ("href", .string(parts.href)),
        ("searchParams", .array(parts.searchParamValues.map(JSONValue.string)))
      ]
      for (key, value) in actual {
        #expect(JSJSON.compact(value).utf8.elementsEqual(JSJSON.compact(item[key]!).utf8),
                "\(input) \(key): \(JSJSON.compact(value)) vs \(JSJSON.compact(item[key]!))")
      }
    }
  }
}
