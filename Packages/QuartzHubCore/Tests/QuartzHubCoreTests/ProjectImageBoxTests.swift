import Foundation
import Testing
@testable import QuartzHubCore

/// `ProjectImageBox` against QuartzControl's `shared/projectImageBox.ts`
/// (`scripts/project-image-box-golden.mjs`). The lists are compared as JSON.stringify writes them,
/// so key order counts.
@Suite struct ProjectImageBoxTests {
  struct With: Decodable {
    let hasDark: Bool
    let replaceIndex: Int?
    let result: String
  }

  struct Case: Decodable {
    let id: String
    let plugins: String
    let isLayoutBox: [Bool]
    let isFresh: [Bool]
    let findOwn: Int
    let findOther: Int
    let without: String
    let with: [With]
  }

  struct Fixture: Decodable {
    let source: String
    let className: String
    let html: [String: String]
    let cases: [Case]
  }

  static let fixture: Fixture? = {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/project-image-box/cases.json")
    return try? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
  }()

  static func plugins(_ json: String) throws -> [PluginEntry] {
    try (JSJSON.parse(json).arrayValue ?? []).map { PluginEntry(object: $0.objectValue ?? JSONObject()) }
  }

  static func text(_ plugins: [PluginEntry]) -> String {
    JSJSON.compact(.array(plugins.map { .object($0.object) }))
  }

  @Test func theFixtureIsThere() throws {
    let fixture = try #require(Self.fixture)
    #expect(fixture.cases.count == 18)
    #expect(fixture.source == ProjectImageBox.layoutBoxSource)
    #expect(fixture.className == ProjectImageBox.projectImageClass)
    #expect(fixture.html["light"] == ProjectImageBox.html(hasDark: false))
    #expect(fixture.html["dark"] == ProjectImageBox.html(hasDark: true))
  }

  @Test(arguments: (fixture?.cases ?? []).map(\.id))
  func sameAsQuartzControl(_ id: String) throws {
    let item = try #require(Self.fixture?.cases.first { $0.id == id })
    let plugins = try Self.plugins(item.plugins)
    #expect(Self.text(plugins) == item.plugins, "the input survives the round trip")
    #expect(plugins.map(ProjectImageBox.isLayoutBox) == item.isLayoutBox)
    #expect(plugins.map(ProjectImageBox.isFresh) == item.isFresh)
    #expect(ProjectImageBox.findOwn(plugins) ?? -1 == item.findOwn)
    #expect(ProjectImageBox.findOther(plugins) ?? -1 == item.findOther)
    #expect(Self.text(ProjectImageBox.without(plugins)) == item.without)
    for with in item.with {
      let result = ProjectImageBox.with(plugins, hasDark: with.hasDark, replaceIndex: with.replaceIndex)
      #expect(Self.text(result) == with.result, "hasDark \(with.hasDark), replaceIndex \(String(describing: with.replaceIndex))")
    }
  }
}
