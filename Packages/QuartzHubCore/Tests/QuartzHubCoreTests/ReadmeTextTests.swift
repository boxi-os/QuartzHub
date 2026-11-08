import Foundation
import Testing
@testable import QuartzHubCore

/// `ReadmeText` against QuartzControl's own `ReadmeText.tsx` (`scripts/readme-text-golden.mjs`):
/// gui-test's plugin READMEs, hand-made edges and 400 random strings, each as the blocks
/// QuartzControl put on screen.
@Suite struct ReadmeTextTests {
  static let golden: JSONValue? = {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/readme-text/cases.json")
    return (try? Data(contentsOf: file)).flatMap { try? JSJSON.parse($0) }
  }()

  /// The golden's neutral form. QuartzControl draws headings in two sizes (levels 1–2 and the rest).
  static func encode(_ blocks: [ReadmeText.Block]) -> JSONValue {
    .array(blocks.map { block in
      switch block {
      case .paragraph(let parts): object("paragraph", encode(parts))
      case .heading(let level, let parts):
        object("heading", .object(JSONObject([("big", .bool(level <= 2)), ("parts", encode(parts))])))
      case .code(let text): object("code", .string(text))
      case .table(let text): object("table", .string(text))
      case .list(let ordered, let items):
        object("list", .object(JSONObject([("ordered", .bool(ordered)), ("items", .array(items.map(encode)))])))
      }
    })
  }

  static func encode(_ parts: [ReadmeText.Inline]) -> JSONValue {
    .array(parts.map { part in
      switch part {
      case .text(let text): object("text", .string(text))
      case .code(let text): object("code", .string(text))
      case .strong(let text): object("strong", .string(text))
      case .image(let alt): object("image", .string(alt))
      case .link(let href, let inner):
        object("link", .object(JSONObject([("href", href.map(JSONValue.string) ?? .null), ("parts", encode(inner))])))
      }
    })
  }

  static func object(_ key: String, _ value: JSONValue) -> JSONValue { .object(JSONObject([(key, value)])) }

  @Test func blocksMatchQuartzControl() throws {
    let cases = try #require(Self.golden?["cases"]?.arrayValue)
    #expect(cases.filter { $0["id"]?.stringValue?.hasPrefix("real/") == true }.count >= 3)
    #expect(cases.count > 400)
    var mismatches: [String] = []
    for item in cases {
      let text = try #require(item["text"]?.stringValue)
      let repo = try #require(item["repoUrl"]?.stringValue)
      let mine = Self.encode(ReadmeText.blocks(text, repoUrl: repo))
      if mine != item["blocks"] {
        mismatches.append("\(item["id"]?.stringValue ?? "?"): \(JSJSON.compact(mine)) ≠ \(JSJSON.compact(item["blocks"] ?? .null))")
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) of \(cases.count):\n\(mismatches.prefix(5).joined(separator: "\n"))")
  }

  @Test func linksResolveAsInQuartzControl() throws {
    let hrefs = try #require(Self.golden?["hrefs"]?.arrayValue)
    for item in hrefs {
      let href = try #require(item["href"]?.stringValue)
      let repo = try #require(item["repoUrl"]?.stringValue)
      #expect(ReadmeText.resolveHref(href, repoUrl: repo).map(JSONValue.string) ?? .null == item["resolved"], "\(href)")
    }
  }

  /// The limit is what keeps a paragraph of unclosed links from holding the window: 120 KB of
  /// them in one paragraph is plain text in 9 ms; without the limit 22 s (debug build, each `[`
  /// reading to the end). The cost below the limit is in docs/decisions/phase-4-oberflaeche.md.
  @Test func overlongParagraphIsPlainText() {
    let text = String(repeating: "[a](b ", count: 20_000)
    let clock = ContinuousClock()
    var blocks: [ReadmeText.Block] = []
    let took = clock.measure { blocks = ReadmeText.blocks(text, repoUrl: "https://github.com/a/b") }
    #expect(blocks == [.paragraph([.text(ReadmeText.trim(text))])])
    #expect(took < .seconds(10), "\(took)")
  }
}
