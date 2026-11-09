import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// `FormUsages` against QuartzControl's `quartzSlug`, `pageFormUse` and `contentService.formUsages`
/// (`scripts/form-usages-golden.mjs`). The pages' front matter goes through the `content-files`
/// helper, as in the scan; the projects are built again under a folder with "Gärten-Ü". The globby
/// scenarios link gui-test's node_modules in, as the golden did.
@Suite struct FormUsagesTests {
  struct Slug: Decodable {
    let path: String
    let slug: String
    let slugPath: String
  }

  struct Use: Decodable {
    let forms: [String]
    let hidesLayout: Bool
    let title: String?
    let draft: Bool
    let publish: Bool
  }

  struct UseCase: Decodable {
    let id: String
    let text: String
    let codeBlockLang: String
    let frontmatterKey: String
    let answer: Use
  }

  struct Page: Decodable {
    let file: String
    let slug: String
    let title: String?
    let forms: [String]
    let hidesLayout: Bool
    let unbuilt: String?
  }

  struct Answer: Decodable {
    let pages: [Page]?
    let slugs: [String]?
    let listSource: String?
    let unreadable: Int?
    let noContent: Bool?
    let error: String?
  }

  struct Scenario: Decodable {
    let id: String
    let files: [[String]]?
    let config: String
    let globby: Bool?
    let link: String?
    let vault: [[String]]?
    let unreadable: [String]?
    let codeBlockLang: String
    let frontmatterKey: String
    let answer: Answer
  }

  struct Fixture: Decodable {
    let locale: String
    let slugs: [Slug]
    let uses: [UseCase]
    let scenarios: [Scenario]
  }

  static let fixture: Fixture? = {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/form-usages/cases.json")
    return try? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
  }()

  static func bytes(_ text: String?) -> [UInt8]? { text.map { Array($0.utf8) } }
  static func bytes(_ texts: [String]) -> [[UInt8]] { texts.map { Array($0.utf8) } }

  @Test func theFixtureIsThere() throws {
    let fixture = try #require(Self.fixture)
    #expect(fixture.locale == "de-DE")
    #expect(fixture.slugs.count == 31)
    #expect(fixture.uses.count == 50)
    #expect(fixture.scenarios.count == 12)
  }

  @Test func slugsAsQuartz() throws {
    for c in try #require(Self.fixture).slugs {
      #expect(Array(FormUsages.slug(c.path).utf8) == Array(c.slug.utf8), "\(c.path)")
      #expect(Array(FormUsages.slugPath(c.slug).utf8) == Array(c.slugPath.utf8), "\(c.path)")
    }
  }

  @Test func pagesAsQuartzControlReadsThem() async throws {
    let cases = try #require(Self.fixture).uses
    let yamls = cases.compactMap { FormUsages.frontmatter($0.text)?.yaml }
    let answer = try await Helper.call("content-files", JSONObject([("op", .string("parse")), ("texts", .array(yamls.map(JSONValue.string)))]))
    let values = try #require(answer["values"]?.arrayValue)
    try #require(values.count == yamls.count)
    let parsed = Dictionary(zip(yamls.map { Array($0.utf16) }, values), uniquingKeysWith: { a, _ in a })
    for c in cases {
      let use = FormUsages.use(c.text, codeBlockLang: c.codeBlockLang, frontmatterKey: c.frontmatterKey) { parsed[Array($0.utf16)] }
      #expect(Self.bytes(use.forms) == Self.bytes(c.answer.forms), "\(c.id)")
      #expect(use.hidesLayout == c.answer.hidesLayout, "\(c.id)")
      #expect(Self.bytes(use.title) == Self.bytes(c.answer.title), "\(c.id)")
      #expect(use.draft == c.answer.draft, "\(c.id)")
      #expect(use.publish == c.answer.publish, "\(c.id)")
    }
  }

  static func write(_ root: String, _ files: [[String]]) throws {
    for pair in files {
      let path = "\(root)/\(pair[0])"
      try Posix.mkdirs(NodePath.dirname(path))
      try Posix.write(path, Data(pair[1].utf8))
    }
  }

  @Test(arguments: (fixture?.scenarios ?? []).map(\.id))
  func sitesAsQuartzControlScansThem(_ id: String) async throws {
    let scenario = try #require(Self.fixture?.scenarios.first { $0.id == id })
    if scenario.globby == true, !FileManager.default.fileExists(atPath: "\(ContentIndexPageTests.guiTestModules)/globby") {
      Issue.record("gui-test with node_modules is needed for \(id)")
      return
    }
    let scratch = try HostPathTests.Scratch()
    let work = try #require(realpath(scratch.path, nil).map { pointer in
      defer { free(pointer) }
      return String(cString: pointer)
    })
    let base = "\(work)/\(id)"
    let project = "\(base)/projekt"
    try Posix.mkdirs(project)
    try Posix.write("\(project)/quartz.config.yaml", Data(scenario.config.utf8))
    if scenario.globby == true { try Posix.symlink(ContentIndexPageTests.guiTestModules, "\(project)/node_modules") }
    if let vault = scenario.vault { try Self.write("\(base)/vault", vault) }
    if let link = scenario.link {
      try Posix.symlink(link, "\(project)/content")
    } else if let files = scenario.files {
      try Posix.mkdirs("\(project)/content")
      try Self.write("\(project)/content", files)
    }
    for file in scenario.unreadable ?? [] { chmod("\(project)/content/\(file)", 0o000) }
    defer { for file in scenario.unreadable ?? [] { chmod("\(project)/content/\(file)", 0o644) } }

    let result = try await FormUsages.scan(project: project, codeBlockLang: scenario.codeBlockLang, frontmatterKey: scenario.frontmatterKey)
    let expected = scenario.answer
    #expect(expected.error == nil)
    #expect(result.noContent == (expected.noContent ?? false))
    #expect(result.listSource.rawValue == expected.listSource)
    #expect(result.unreadable == expected.unreadable)
    #expect(Self.bytes(result.slugs) == Self.bytes(expected.slugs ?? []))
    let pages = expected.pages ?? []
    try #require(result.pages.count == pages.count, "\(result.pages.map(\.file))")
    for (got, want) in zip(result.pages, pages) {
      #expect(Array(got.file.utf8) == Array(want.file.utf8))
      #expect(Array(got.slug.utf8) == Array(want.slug.utf8))
      #expect(Self.bytes(got.title) == Self.bytes(want.title), "\(want.file)")
      #expect(Self.bytes(got.forms) == Self.bytes(want.forms), "\(want.file)")
      #expect(got.hidesLayout == want.hidesLayout, "\(want.file)")
      #expect(got.unbuilt?.rawValue == want.unbuilt, "\(want.file)")
    }
  }
}
