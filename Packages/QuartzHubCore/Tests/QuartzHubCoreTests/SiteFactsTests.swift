import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own export/collect.ts and the tail of exportService.ts
/// (`scripts/site-facts-golden.mjs`): 15 built sites (contentIndex.json and multilanguage.json
/// broken, missing, of the wrong shape), the languages and roots of each, 30 navigation orders
/// and 90 page lists for the book editor. The export window was a stand-in there; what it read is
/// handed in here the same way. A reason from V8's JSON.parse is compared as "a parse error".
@Suite struct SiteFactsTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/site-facts/golden.json")))
  static let origin = "http://127.0.0.1:1"

  static func build(_ name: String, in work: String) throws -> String {
    let root = "\(work)/\(name)"
    try Posix.mkdirs(root)
    let files = golden["sites"]![name]!.objectValue!
    for path in files.keys {
      try Posix.mkdirs(NodePath.dirname("\(root)/\(path)"))
      try Posix.write("\(root)/\(path)", Data(files[path]!.stringValue!.utf8))
    }
    return root
  }

  static func navigation(_ nav: JSONValue, _ facts: SiteFacts) -> NavigationOrder {
    let hrefs = (nav["hrefs"]?.arrayValue ?? []).map { href -> String in
      let h = href.stringValue!
      return JSText.startsWith(h, "/") ? origin + h : h
    }
    return NavigationOrder(source: nav["source"]!.stringValue!, hrefs: hrefs, complete: nav["complete"]?.boolValue ?? true, facts: facts)
  }

  /// A JSON.parse reason inside a localized sentence, made comparable.
  static func parseReason(_ text: String) -> String {
    JSText.replaceAll(text, #"\((Unexpected|Expected)[^)]*\)"#, with: "(<parse>)")
  }

  @Test func readsSitesAsQuartzControl() throws {
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-site-facts"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let entries = Self.golden["facts"]!.arrayValue!
    #expect(entries.count == 15)
    for entry in entries {
      let name = entry["site"]!.stringValue!
      let root = try Self.build(name, in: work)
      let expected = GoldenText.localize(entry["result"]!)
      do {
        let facts = try SiteFacts.read(root: root)
        #expect(JSJSON.compact(facts.json) == JSJSON.compact(expected["ok"] ?? .null), "\(name)")
        for call in entry["calls"]!.arrayValue! {
          let language = call["language"]!.stringValue!
          let actual: JSONValue
          switch call["fn"]!.stringValue! {
          case "pagesInLanguage": actual = .array(facts.pages(inLanguage: language).map(JSONValue.string))
          case "languageHome": actual = .string(facts.languageHome(language))
          default: actual = .string(facts.effectiveRoot(call["root"]!.stringValue!, language: language))
          }
          #expect(JSJSON.compact(actual) == JSJSON.compact(call["result"]!), "\(name) \(call["fn"]!) \(language)")
        }
      } catch {
        let message = PublishFailure.message(of: error).replacingOccurrences(of: work, with: "@W@")
        #expect(Self.parseReason(message) == Self.parseReason(expected["error"]?.stringValue ?? "ok"), "\(name): \(message)")
      }
    }
  }

  @Test func ordersAsQuartzControl() throws {
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-site-orders"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let orders = Self.golden["orders"]!.arrayValue!
    #expect(orders.count == 30)
    for order in orders {
      let site = order["site"]!.stringValue!
      let facts = try SiteFacts.read(root: try Self.build(site, in: work))
      let language = order["language"]!.stringValue!
      #expect(order["loads"] == .array([.string("/" + facts.languageHome(language))]))
      let actual = Self.navigation(order["nav"]!, facts)
      #expect(JSJSON.compact(actual.json) == JSJSON.compact(order["result"]!["ok"]!), "\(site) \(order["nav"]!["source"]!) \(language)")
    }
  }

  @Test func listsPagesAsQuartzControl() throws {
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-site-pages"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let lists = Self.golden["sitePages"]!.arrayValue!
    #expect(lists.count == 90)
    var cache: [String: SiteFacts] = [:]
    for list in lists {
      let site = list["site"]!.stringValue!
      let facts = try cache[site] ?? SiteFacts.read(root: try Self.build(site, in: work))
      cache[site] = facts
      let language = list["language"]!.stringValue!, root = list["root"]!.stringValue!
      #expect(list["loads"] == .array([.string("/" + facts.languageHome(language))]))
      let actual = SitePages(facts: facts, navigation: Self.navigation(list["nav"]!, facts), root: root, language: language)
      #expect(JSJSON.compact(actual.json) == JSJSON.compact(list["result"]!["ok"]!), "\(site) \(list["nav"]!["source"]!) root \(root) \(language)")
    }
  }
}
