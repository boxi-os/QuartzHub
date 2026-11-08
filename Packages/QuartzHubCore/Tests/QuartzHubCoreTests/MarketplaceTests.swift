import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Answers every request of a test's session from a queue and notes what was asked. One queue for
/// the whole process, so the suite runs serialized.
final class StubHTTP: URLProtocol, @unchecked Sendable {
  struct Answer: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    var fails = false
    var hangs = false
    /// Head and this many bytes of the body, then silence.
    var stallsAfter: Int?
  }

  struct Lane {
    var queue: [Answer] = []
    var requests: [URLRequest] = []
  }

  static let lane = Mutex(Lane())

  static func serve(_ answers: [Answer]) {
    lane.withLock { $0 = Lane(queue: answers) }
  }

  static func taken() -> (requests: [URLRequest], left: Int) {
    lane.withLock { ($0.requests, $0.queue.count) }
  }

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubHTTP.self]
    return configuration
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let answer: Answer? = Self.lane.withLock { lane in
      lane.requests.append(request)
      return lane.queue.isEmpty ? nil : lane.queue.removeFirst()
    }
    guard let answer, !answer.fails else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    if answer.hangs { return }
    let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    var offset = 0
    if let stallsAfter = answer.stallsAfter {
      client?.urlProtocol(self, didLoad: answer.body.prefix(stallsAfter))
      return
    }
    while offset < answer.body.count {
      client?.urlProtocol(self, didLoad: answer.body.subdata(in: offset..<min(offset + 1000, answer.body.count)))
      offset += 1000
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

/// Against QuartzControl's own marketplaceService.ts: `scripts/marketplace-golden.mjs` ran each
/// scenario of `Fixtures/marketplace/scenarios.json` against a fetch that answered from the same
/// queue and a clock the scenario set, and recorded the requests and answers of every step.
@Suite(.serialized) struct MarketplaceTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/marketplace")
  static var scenarios: [JSONValue] {
    (try? JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("scenarios.json"))).arrayValue) ?? []
  }
  static var names: [String] { scenarios.compactMap { $0["name"]?.stringValue } }

  static func bytes(_ body: JSONValue?) -> Data {
    switch body {
    case .string(let text)?: return Data(text.utf8)
    case .object(let spec)?:
      var data = Data((spec["before"]?.stringValue ?? "").utf8)
      if let fill = spec["fill"]?.numberValue {
        data += Data(String(repeating: spec["char"]?.stringValue ?? "x", count: Int(fill)).utf8)
      }
      data += Data((spec["bytes"]?.arrayValue ?? []).compactMap { $0.numberValue.map { UInt8($0) } })
      data += Data((spec["after"]?.stringValue ?? "").utf8)
      return data
    default: return Data()
    }
  }

  static func answer(_ spec: JSONValue) -> StubHTTP.Answer {
    var answer = StubHTTP.Answer()
    answer.fails = spec["fails"] == .bool(true)
    answer.status = Int(spec["status"]?.numberValue ?? 200)
    for key in spec["headers"]?.objectValue?.keys ?? [] { answer.headers[key] = spec["headers"]![key]!.stringValue }
    answer.body = bytes(spec["body"])
    return answer
  }

  static func json(_ result: MarketplaceResult) -> JSONValue {
    .object(JSONObject([
      ("plugins", .array(result.plugins.map { plugin in
        var object = JSONObject([("name", .string(plugin.name)), ("fullName", .string(plugin.fullName))])
        if let description = plugin.description { object["description"] = .string(description) }
        if let stars = plugin.stars { object["stars"] = .number(Double(stars)) }
        object["url"] = .string(plugin.url)
        if let topics = plugin.topics { object["topics"] = .array(topics.map(JSONValue.string)) }
        if let archived = plugin.archived { object["archived"] = .bool(archived) }
        return .object(object)
      })),
      ("unavailable", .bool(result.unavailable))
    ]))
  }

  /// As the golden script kept a text longer than 200 UTF-16 units: length, digest and ends.
  static func json(_ readme: MarketplaceReadme) -> JSONValue {
    switch readme {
    case .missing: return .object(JSONObject([("status", .string("missing"))]))
    case .unavailable: return .object(JSONObject([("status", .string("unavailable"))]))
    case .ok(let text, let truncated):
      let units = Array(text.utf16)
      let shown: JSONValue = units.count <= 200 ? .string(text) : .object(JSONObject([
        ("length", .number(Double(units.count))),
        ("sha256", .string(SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined())),
        ("head", .string(String(decoding: units.prefix(20), as: UTF16.self))),
        ("tail", .string(String(decoding: units.suffix(20), as: UTF16.self)))
      ]))
      return .object(JSONObject([("status", .string("ok")), ("text", shown), ("truncated", .bool(truncated))]))
    }
  }

  static func asked(_ requests: [URLRequest]) -> JSONValue {
    .array(requests.map { request in
      .object(JSONObject([
        ("url", .string(request.url!.absoluteString)),
        ("accept", request.value(forHTTPHeaderField: "Accept").map(JSONValue.string) ?? .null),
        ("authorization", request.value(forHTTPHeaderField: "Authorization").map(JSONValue.string) ?? .null)
      ]))
    })
  }

  @Test func thereAreScenarios() {
    #expect(Self.scenarios.count >= 19, "scripts/marketplace-golden.mjs")
  }

  @Test(arguments: names)
  func sameAsQuartzControl(_ name: String) async throws {
    let scenario = try #require(Self.scenarios.first { $0["name"] == .string(name) })
    let clock = Mutex(Date(timeIntervalSince1970: 0))
    let token = scenario["token"]?.stringValue
    let market = Marketplace(configuration: StubHTTP.configuration, now: { clock.withLock { $0 } },
                             // "throws": a token that cannot be read, which leaves the request anonymous.
                             token: { token == "throws" ? nil : token })
    for (index, step) in scenario["steps"]!.arrayValue!.enumerated() {
      if let at = step["at"]?.numberValue { clock.withLock { $0 = Date(timeIntervalSince1970: at / 1000) } }
      StubHTTP.serve((step["answers"]?.arrayValue ?? []).map(Self.answer))
      let results: [JSONValue]
      switch step["op"]!.stringValue! {
      case "refresh":
        await market.invalidate()
        results = [.null]
      case "list" where step["parallel"] != nil:
        async let first = market.list()
        async let second = market.list()
        results = [Self.json(await first), Self.json(await second)]
      case "list":
        results = [Self.json(await market.list())]
      default:
        results = [Self.json(await market.readme(step["fullName"]!.stringValue!))]
      }
      let (requests, left) = StubHTTP.taken()
      let expected = step["expected"]!
      let expectedRequests = JSONValue.array(expected["requests"]!.arrayValue!.map { request in
        .object(JSONObject([("url", request["url"]!), ("accept", request["accept"]!), ("authorization", request["authorization"]!)]))
      })
      #expect(JSJSON.stringify(Self.asked(requests)) == JSJSON.stringify(expectedRequests), "step \(index)")
      #expect(JSJSON.stringify(.array(results)) == JSJSON.stringify(expected["results"]!), "step \(index)")
      #expect(left == 0, "step \(index)")
    }
  }

  @Test func theRepositoryNameRuleIsQuartzControls() throws {
    let names = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("names.json"))).arrayValue!
    #expect(names.count >= 30)
    for entry in names {
      let name = entry["name"]!.stringValue!
      #expect(Marketplace.isRepositoryName(name) == (entry["accepted"] == .bool(true)), "\(JSJSON.stringify(.string(name)))")
    }
  }

  // MARK: beyond QuartzControl's answers

  @Test func aNameThatIsNoRepositoryIsNeverAsked() async {
    StubHTTP.serve([])
    let market = Marketplace(configuration: StubHTTP.configuration)
    #expect(await market.readme("a/../../user") == .unavailable)
    #expect(StubHTTP.taken().requests.isEmpty)
  }

  @Test func aStalledAnswerEndsAtTheDeadline() async {
    let market = Marketplace(configuration: StubHTTP.configuration, deadline: .milliseconds(300))
    let start = ContinuousClock.now
    StubHTTP.serve([StubHTTP.Answer(hangs: true)])
    #expect(await market.list() == MarketplaceResult(plugins: Marketplace.fallback, unavailable: true))
    StubHTTP.serve([StubHTTP.Answer(hangs: true)])
    #expect(await market.readme("a/b") == .unavailable)
    // A body that stops halfway: the deadline is the whole request, not the silence before the head.
    StubHTTP.serve([StubHTTP.Answer(body: Data("[{\"name\":".utf8), stallsAfter: 5)])
    #expect(await market.list().unavailable)
    StubHTTP.serve([StubHTTP.Answer(body: Data("# Title".utf8), stallsAfter: 3)])
    #expect(await market.readme("a/b") == .unavailable)
    #expect(ContinuousClock.now - start < .seconds(6))
  }

  static func page(_ names: [String], next: String? = nil) -> StubHTTP.Answer {
    let repos = names.map { #"{"name":"\#($0)","full_name":"quartz-community/\#($0)","html_url":"https://github.com/quartz-community/\#($0)"}"# }
    return StubHTTP.Answer(headers: next.map { ["Link": #"<\#($0)>; rel="next", <https://api.github.com/x?page=9>; rel="last""#] } ?? [:],
                           body: Data("[\(repos.joined(separator: ","))]".utf8))
  }

  @Test func theCatalogFollowsTheNextPage() async {
    let market = Marketplace(configuration: StubHTTP.configuration, token: { "t" })
    let second = "https://api.github.com/organizations/1/repos?per_page=100&page=2"
    StubHTTP.serve([Self.page(["a", "b"], next: second), Self.page(["c"])])
    #expect(await market.list().plugins.map(\.name) == ["a", "b", "c"])
    let requests = StubHTTP.taken().requests
    #expect(requests.map(\.url?.absoluteString) == ["https://api.github.com/orgs/quartz-community/repos?per_page=100", second])
    #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer t", "Bearer t"])
  }

  @Test func aNextPageElsewhereIsNotFollowed() async {
    let market = Marketplace(configuration: StubHTTP.configuration, token: { "t" })
    StubHTTP.serve([Self.page(["a"], next: "https://api.github.com.example/repos?page=2")])
    #expect(await market.list().plugins.map(\.name) == ["a"])
    #expect(StubHTTP.taken().requests.count == 1, "the token does not travel to another host")
  }

  @Test func aFailedPageIsAFailedCatalog() async {
    let market = Marketplace(configuration: StubHTTP.configuration)
    StubHTTP.serve([Self.page(["a"], next: "https://api.github.com/page2"), StubHTTP.Answer(status: 403)])
    #expect(await market.list() == MarketplaceResult(plugins: Marketplace.fallback, unavailable: true))
  }

  @Test func theCatalogEndsAfterTenPages() async {
    let market = Marketplace(configuration: StubHTTP.configuration)
    StubHTTP.serve((0..<11).map { Self.page(["p\($0)"], next: "https://api.github.com/page\($0 + 1)") })
    #expect(await market.list().plugins.count == Marketplace.pageLimit)
    #expect(StubHTTP.taken().left == 1)
  }

  @Test func anEntryWithHolesIsLeftOut() async {
    let market = Marketplace(configuration: StubHTTP.configuration)
    StubHTTP.serve([StubHTTP.Answer(body: Data(#"[{"name":"a"},{"name":"b","full_name":"x/b","html_url":"u","stargazers_count":1.5}]"#.utf8))])
    let result = await market.list()
    #expect(result.plugins == [MarketplacePlugin(name: "b", fullName: "x/b", url: "u")])
    #expect(!result.unavailable)
    StubHTTP.serve([StubHTTP.Answer(body: Data(#"[{"name":"a"}]"#.utf8))])
    await market.invalidate()
    #expect(await market.list().unavailable, "nothing usable is no catalog")
  }

  /// The real API, anonymous: three GET requests. Only on request:
  /// `QH_NETWORK_TESTS=1 swift test --filter theRealCatalog`.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["QH_NETWORK_TESTS"] == "1"))
  func theRealCatalog() async {
    let market = Marketplace()
    let result = await market.list()
    #expect(!result.unavailable)
    #expect(result.plugins.count >= 40)
    let explorer = result.plugins.first { $0.fullName == "quartz-community/explorer" }
    #expect(explorer?.topics?.contains("quartz-plugin") == true)
    #expect(result.plugins.allSatisfy { Marketplace.isRepositoryName($0.fullName) })
    print("catalog: \(result.plugins.count) repositories, \(result.plugins.filter { $0.topics?.contains("quartz-plugin") == true }.count) with quartz-plugin, \(result.plugins.filter { $0.archived == true }.count) archived")
    guard case .ok(let text, false) = await market.readme("quartz-community/explorer") else { Issue.record("explorer README"); return }
    print("explorer README: \(text.utf8.count) bytes, starts \(text.prefix(30).debugDescription)")
    #expect(await market.readme("quartz-community/qh-no-such-repository") == .missing)
  }
}

/// The page's two lists (QuartzControl's `useMemo` in Marketplace.tsx, read by hand: it lives
/// inside the component).
@Suite struct MarketplaceSplitTests {
  static func plugin(_ name: String, stars: Int?, topics: [String]? = ["quartz-plugin"], archived: Bool? = false,
                     description: String? = nil) -> MarketplacePlugin {
    MarketplacePlugin(name: name, fullName: "quartz-community/\(name)", description: description, stars: stars,
                      url: "https://github.com/quartz-community/\(name)", topics: topics, archived: archived)
  }

  static let catalog = MarketplaceResult(plugins: [
    plugin("explorer", stars: 5, description: "Enhanced file explorer"),
    plugin("graph", stars: 9),
    plugin("v5", stars: 900, archived: true),
    plugin("awesome", stars: 9, topics: nil),
    plugin("search", stars: nil),
    plugin("backlinks", stars: 5),
    plugin("Über-Plugin", stars: 1, topics: ["quartz-plugin", "x"])
  ], unavailable: false)

  @Test func pluginsAndOtherByStarsStable() {
    let (plugins, other) = Self.catalog.split(query: "")
    #expect(plugins.map(\.name) == ["graph", "explorer", "backlinks", "Über-Plugin", "search"])
    #expect(other.map(\.name) == ["v5", "awesome"])
  }

  @Test func searchIsASubstringIgnoringCaseAndSpace() {
    #expect(Self.catalog.split(query: "  EXPLORER\u{00A0}").plugins.map(\.name) == ["explorer"])
    #expect(Self.catalog.split(query: "file EXP").plugins.map(\.name) == ["explorer"])
    #expect(Self.catalog.split(query: "community/gra").plugins.map(\.name) == ["graph"])
    #expect(Self.catalog.split(query: "über").plugins.map(\.name) == ["Über-Plugin"])
    let none = Self.catalog.split(query: "nothing")
    #expect(none.plugins.isEmpty && none.other.isEmpty)
  }
}
