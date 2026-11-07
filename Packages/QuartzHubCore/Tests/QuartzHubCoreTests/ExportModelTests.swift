import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own shared/exportModel.ts (`scripts/export-model-golden.mjs`): 392
/// calls, each with its arguments and answer, compared by UTF-8 bytes of the compact JSON.
@Suite struct ExportModelTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/export-model/cases.json")))

  static func strings(_ value: JSONValue) -> [String] { value.arrayValue!.map { $0.stringValue! } }

  static func entries(_ value: JSONValue?) -> [BookEntry]? {
    value?.arrayValue?.map { entry in entry["slug"]?.stringValue.map(BookEntry.page) ?? .heading(entry["heading"]!.stringValue!) }
  }

  static func answer(_ fn: String, _ args: [JSONValue]) -> JSONValue? {
    let s = { (i: Int) in args[i].stringValue! }
    switch fn {
    case "slugFromPathname": return .string(ExportModel.slug(fromPathname: s(0)))
    case "anchorFor": return .string(ExportModel.anchor(s(0), args.count > 1 ? s(1) : nil))
    case "folderOf": return .string(ExportModel.folder(of: s(0)))
    case "isFolderIndex": return .bool(ExportModel.isFolderIndex(s(0)))
    case "insideRoot": return .bool(ExportModel.insideRoot(s(0), s(1)))
    case "pageDepth": return .number(Double(ExportModel.pageDepth(s(0), s(1))))
    case "explorerOrder":
      let pages = args[0].arrayValue!.map {
        ExportModel.ExplorerPage(slug: $0["slug"]!.stringValue!, title: $0["title"]!.stringValue!, filePath: $0["filePath"]?.stringValue)
      }
      return .array(ExportModel.explorerOrder(pages).map(JSONValue.string))
    case "resolveOrder":
      let book = args[0]
      return ExportModel.resolveOrder(order: entries(book["order"]), excluded: strings(book["excluded"]!), root: book["root"]!.stringValue!,
                                      navigation: strings(args[1]), available: Set(strings(args[2]))).json
    case "outsideUrl":
      return ExportModel.outsideURL(baseUrl: args[0].stringValue, slug: s(1), hash: s(2)).map(JSONValue.string) ?? .null
    case "linkSlug": return .string(ExportModel.linkSlug(s(0)))
    case "backlinksInBook":
      let links = args[1].objectValue!
      return .array(ExportModel.backlinksInBook(strings(args[0])) { links[$0].map(strings) ?? [] }
        .map { .array([.string($0.slug), .array($0.from.map(JSONValue.string))]) })
    case "tagRegister":
      let tags = args[1].objectValue!
      return .array(ExportModel.tagRegister(strings(args[0]), tagsOf: { tags[$0].map(strings) ?? [] }, locale: s(2))
        .map { .object(JSONObject([("tag", .string($0.tag)), ("pages", .array($0.pages.map(JSONValue.string)))])) })
    case "REGISTER_SLUG": return .string(ExportModel.registerSlug)
    default: return nil
    }
  }

  @Test func answersAsQuartzControl() {
    let cases = Self.golden["cases"]!.arrayValue!
    #expect(cases.count == 392)
    for item in cases {
      let fn = item["fn"]!.stringValue!
      // `undefined` for a missing baseUrl: the JSON holds null.
      let args = item["args"]!.arrayValue!
      guard let actual = Self.answer(fn, args) else {
        Issue.record("unknown fn \(fn)")
        continue
      }
      #expect(JSJSON.compact(actual) == JSJSON.compact(item["result"]!), "\(fn)(\(JSJSON.compact(.array(args)).prefix(240))): \(JSJSON.compact(actual).prefix(300))")
    }
  }
}
