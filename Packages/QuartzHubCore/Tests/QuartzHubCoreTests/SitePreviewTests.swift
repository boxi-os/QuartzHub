import Foundation
import Testing
@testable import QuartzHubCore

/// `ComponentSelectors` and `PreviewMarks` against QuartzControl's own code
/// (`scripts/site-preview-golden.mjs`).
@Suite struct SitePreviewTests {
  static let golden: JSONValue? = {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/site-preview/cases.json")
    return (try? Data(contentsOf: file)).flatMap { try? JSJSON.parse($0) }
  }()

  @Test func selectorsFindTheEntry() throws {
    let cases = try #require(Self.golden?["entries"]?.arrayValue)
    let plugins = cases.compactMap { $0["entry"]?.objectValue.map(PluginEntry.init(object:)) }
    #expect(cases.count == 14)
    for (item, entry) in zip(cases, plugins) {
      let mine = ComponentSelectors.entry(entry, siblings: plugins)
      let encoded: JSONValue = mine.map {
        .object(JSONObject([("selector", .string($0.selector)), ("matches", .number(Double($0.matches))), ("ownClass", .bool($0.ownClass))]))
      } ?? .null
      #expect(encoded == item["result"], "\(JSJSON.compact(.object(entry.object)))")
    }
  }

  @Test func reportsAreCheckedFieldByField() throws {
    let cases = try #require(Self.golden?["reports"]?.arrayValue)
    for item in cases {
      let mine = PreviewMarks.report(item["data"])
      let encoded: JSONValue = mine.map { r in
        .object(JSONObject([
          ("source", .string("quartzcontrol-preview")), ("selector", r.selector.map(JSONValue.string) ?? .null),
          ("found", .number(Double(r.found))), ("visible", .number(Double(r.visible))),
          ("rect", r.rect.map { .object(JSONObject([("x", .number($0.x)), ("y", .number($0.y)), ("width", .number($0.width)), ("height", .number($0.height))])) } ?? .null),
          ("viewport", .object(JSONObject([("width", .number(r.viewport.width)), ("height", .number(r.viewport.height))])))
        ]))
      } ?? .null
      #expect(encoded == item["result"], "\(JSJSON.compact(item["data"] ?? .null))")
    }
  }

  @Test func zoomFramesTheElement() throws {
    let cases = try #require(Self.golden?["zooms"]?.arrayValue)
    #expect(cases.count == 40)
    func n(_ v: JSONValue?, _ k: String) -> Double { v?[k]?.numberValue ?? .nan }
    for item in cases {
      let r = item["rect"], f = item["frame"], b = item["box"]
      let z = PreviewMarks.zoom(onto: .init(x: n(r, "x"), y: n(r, "y"), width: n(r, "width"), height: n(r, "height")),
                                frame: (n(f, "width"), n(f, "height")), box: (n(b, "width"), n(b, "height")),
                                baseScale: item["base"]?.numberValue ?? 1)
      #expect(z.scale == n(item["result"], "scale") && z.x == n(item["result"], "x") && z.y == n(item["result"], "y"),
              "\(JSJSON.compact(item))")
    }
  }

  @Test func pagesAndSentences() throws {
    let golden = try #require(Self.golden)
    for item in golden["nearest"]?.arrayValue ?? [] {
      let list = (item["list"]?.arrayValue ?? []).compactMap(\.stringValue)
      #expect(PreviewMarks.nearestPage(list, to: item["page"]!.stringValue!).map(JSONValue.string) ?? .null == item["result"],
              "\(list) \(item["page"]!)")
    }
    for item in golden["same"]?.arrayValue ?? [] {
      #expect(PreviewMarks.samePage(item["a"]!.stringValue!, item["b"]!.stringValue!) == item["result"]?.boolValue)
    }
    let sentences = try #require(golden["sentences"]?.arrayValue)
    #expect(sentences.count == 48)
    for item in sentences {
      let found = Int(item["found"]!.numberValue!), visible = Int(item["visible"]!.numberValue!)
      let report = PreviewMarks.Report(selector: ".x", found: found, visible: visible, rect: nil, viewport: (1280, 640))
      let pages = item["pages"]?.arrayValue?.compactMap(\.stringValue)
      let sentence = PreviewMarks.sentence(report, matches: Int(item["matches"]!.numberValue!), ownClass: item["ownClass"]!.boolValue!,
                                           pages: pages, page: "/a/")
      let echo: String = switch sentence {
      case .notFound: OptionFormTextTests.echo("sitePreview.markNotFound", [("name", "Nav")])
      case .stale: OptionFormTextTests.echo("sitePreview.markStale", [("name", "Nav")])
      case .hidden: OptionFormTextTests.echo("sitePreview.markHidden", [("name", "Nav")])
      case .marked: OptionFormTextTests.echo("sitePreview.marked", [("name", "Nav")])
      case .shared(let count): OptionFormTextTests.echo("sitePreview.markShared", [("name", "Nav"), ("count", String(count))])
      case .noClass(let count): OptionFormTextTests.echo("sitePreview.markNoClass", [("name", "Nav"), ("count", String(count))])
      }
      #expect(echo == item["result"]?.stringValue, "\(JSJSON.compact(item))")
    }
  }

  @Test func scriptCallQuotesTheSelector() {
    #expect(PreviewScript.source.hasPrefix("function previewScript(selector, focus)"))
    #expect(PreviewScript.call(selector: ".a\"b", focus: true).hasSuffix(#")(".a\"b", true)"#))
    #expect(PreviewScript.call(selector: nil, focus: false).hasSuffix(")(null, false)"))
  }

  /// "Komponente wählen" on the CSS tab: QuartzControl's componentSelectors on the same entries.
  @Test func componentSelectorList() throws {
    let plugins = try #require(Self.golden?["listPlugins"]?.arrayValue).compactMap { $0.objectValue.map(PluginEntry.init) }
    let expected = try #require(Self.golden?["list"]?.arrayValue)
    let got = ComponentSelectors.list(plugins)
    #expect(got.count == expected.count)
    for (option, want) in zip(got, expected) {
      #expect(option.plugin == want["plugin"]?.stringValue)
      #expect(option.name == want["name"]?.stringValue)
      #expect(option.selector == want["selector"]?.stringValue)
      #expect(option.measured == (want["measured"] == .bool(true)))
      #expect(option.reach?.kind == want["reach"]?["kind"]?.stringValue)
      #expect(option.reach.map { Double($0.copies) } == want["reach"]?["copies"]?.numberValue)
    }
  }
}
