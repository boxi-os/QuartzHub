import Foundation
import Testing
@testable import QuartzHubCore

/// The start page's list: the order and the search against QuartzControl's own expressions from
/// `Home.tsx`, run in Node (`scripts/project-overview-golden.mjs`), and the rows `read` makes for
/// the states QuartzControl's `projectOverviewService` marks.
@Suite struct ProjectOverviewTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/project-overview/golden.json")))

  static var rows: [ProjectOverview] {
    golden["rows"]!.arrayValue!.map { value in
      let object = value.objectValue!
      return ProjectOverview(entry: ProjectEntry(object: object), missing: false, isQuartzProject: true,
                             siteTitle: object["siteTitle"]?.stringValue)
    }
  }

  @Test func orderAsHome() {
    let expected = Self.golden["order"]!.arrayValue!.map { $0.stringValue! }
    #expect(ProjectOverviews.sorted(Self.rows).map(\.id) == expected)
  }

  @Test func searchAsHome() {
    let sorted = ProjectOverviews.sorted(Self.rows)
    for item in Self.golden["search"]!.arrayValue! {
      let query = item["query"]!.stringValue!
      let expected = item["ids"]!.arrayValue!.map { $0.stringValue! }
      #expect(ProjectOverviews.filter(sorted, query: query).map(\.id) == expected, "\(query)")
    }
  }

  /// The one difference on purpose: a decomposed path is found with a composed query.
  @Test func searchFindsDecomposedPaths() {
    let entry = ProjectEntry(object: JSONObject([("id", .string("d")), ("name", .string("site")), ("path", .string("/Volumes/Ga\u{308}rten/site"))]))
    let row = ProjectOverview(entry: entry, missing: false, isQuartzProject: true)
    #expect(ProjectOverviews.filter([row], query: "G\u{E4}rten").count == 1)
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  @Test(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt"))
  func rowsForEachState() async throws {
    let store = ProjectStore(profile: ProfileDirectory("\(scratch.path)/Profil"))
    let site = "\(scratch.path)/Gärten-Ü"
    try Posix.mkdirs(site)
    try Posix.write(ConfigFile.path(project: site), Data("configuration:\n  pageTitle: Über Gärten\n  baseUrl: example.com/gärten\n".utf8))
    let broken = "\(scratch.path)/Kaputt"
    try Posix.mkdirs(broken)
    try Posix.write(ConfigFile.path(project: broken), Data("configuration: [\n".utf8))
    let plain = "\(scratch.path)/Ordner"
    try Posix.mkdirs(plain)
    let gone = "\(scratch.path)/Weg"
    try Posix.mkdirs(gone)
    let ids = try [site, broken, plain, gone].map { try store.add(path: $0).id }
    try FileManager.default.removeItem(atPath: gone)

    let servers: [String: Int?] = [ids[0]: 8080, ids[2]: nil]
    let rows = await ProjectOverviews.read(store: store, relaySecrets: [ids[1]], servers: servers, runtime: HelperRuntime.runtime)
    #expect(rows.map(\.id) == ids)
    #expect(rows[0].isQuartzProject && !rows[0].missing)
    #expect(rows[0].siteTitle == "Über Gärten" && rows[0].baseUrl == "example.com/gärten")
    #expect(rows[0].serverRunning && rows[0].serverPort == 8080 && !rows[0].relaySecrets)
    // A malformed config keeps its row, without the title.
    #expect(rows[1].isQuartzProject && rows[1].siteTitle == nil && rows[1].relaySecrets)
    // A folder without quartz.config.yaml, its server running on a port nobody recorded.
    #expect(!rows[2].isQuartzProject && !rows[2].missing && rows[2].serverRunning && rows[2].serverPort == nil)
    #expect(rows[3].missing && !rows[3].isQuartzProject && !rows[3].serverRunning)
    #expect(rows.allSatisfy { $0.icon == nil })
  }
}
