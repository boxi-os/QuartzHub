import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// `ContentIndexPage` against QuartzControl's `createIndexPage` (`scripts/content-index-golden.mjs`):
/// the same projects built again under a folder with "Gärten-Ü", the answer and the index.md
/// compared. The globby scenarios link gui-test's node_modules in, as the golden did; without
/// gui-test they cannot run and say so.
@Suite struct ContentIndexPageTests {
  struct Answer: Decodable {
    let path: String?
    let listSource: String?
    let index: String?
    let error: String?
  }

  struct Scenario: Decodable {
    let id: String
    let files: [String: String]?
    let config: String
    let globby: Bool?
    let link: String?
    let vault: [String: String]?
    let title: String
    let answer: Answer
  }

  struct Fixture: Decodable {
    let locale: String
    let scenarios: [Scenario]
  }

  static let fixture: Fixture? = {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/content-index/cases.json")
    return try? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
  }()

  static let guiTestModules = "\(NSHomeDirectory())/Documents/QuartzProjekte/gui-test/node_modules"

  static func key(_ failure: ContentIndexPage.Failure) -> String {
    switch failure {
    case .noContent: "indexPageNoContent"
    case .exists: "indexPageExists"
    case .unpacking: "indexPageGlobbyUnpacking"
    case .globbyBroken: "indexPageGlobbyBroken"
    case .helper(let reason): "helper: \(reason)"
    case .write(let reason): "write: \(reason)"
    }
  }

  static func write(_ root: String, _ files: [String: String]) throws {
    for (relative, text) in files {
      let path = "\(root)/\(relative)"
      try Posix.mkdirs(NodePath.dirname(path))
      try Posix.write(path, Data(text.utf8))
    }
  }

  @Test func theFixtureIsThere() throws {
    let fixture = try #require(Self.fixture)
    #expect(fixture.scenarios.count == 15)
    #expect(fixture.locale == "de-DE")
    #expect(Set(fixture.scenarios.compactMap(\.answer.listSource)) == ["quartz", "fallback"])
  }

  @Test(arguments: (fixture?.scenarios ?? []).map(\.id))
  func sameAsQuartzControl(_ id: String) async throws {
    let scenario = try #require(Self.fixture?.scenarios.first { $0.id == id })
    if scenario.globby == true, !FileManager.default.fileExists(atPath: "\(Self.guiTestModules)/globby") {
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
    if scenario.globby == true { try Posix.symlink(Self.guiTestModules, "\(project)/node_modules") }
    if let vault = scenario.vault { try Self.write("\(base)/vault", vault) }
    if let link = scenario.link {
      try Posix.symlink(link, "\(project)/content")
    } else if let files = scenario.files {
      try Posix.mkdirs("\(project)/content")
      try Self.write("\(project)/content", files)
    }

    let created: ContentIndexPage.Created
    do {
      created = try await ContentIndexPage.create(project: project, title: scenario.title)
    } catch {
      #expect(Self.key(error) == scenario.answer.error)
      return
    }
    #expect(scenario.answer.error == nil, "QuartzControl refused: \(scenario.answer.error ?? "")")
    #expect(Array(created.path.replacingOccurrences(of: work, with: "@W@").utf8) == Array((scenario.answer.path ?? "").utf8))
    #expect(created.listSource.rawValue == scenario.answer.listSource)
    let written = String(decoding: try Posix.read(created.path), as: UTF8.self)
    #expect(Array(written.utf8) == Array((scenario.answer.index ?? "").utf8), "\(written)")
  }

  /// Written once and never again: a second call finds the first one's file.
  @Test func neverOverwrites() async throws {
    let scratch = try HostPathTests.Scratch()
    let project = try scratch.dir("p")
    try Self.write("\(project)/content", ["a.md": "a"])
    try Posix.write("\(project)/quartz.config.yaml", Data("configuration: {}\n".utf8))
    let first = try await ContentIndexPage.create(project: project, title: "Eins")
    await #expect(throws: ContentIndexPage.Failure.exists) {
      try await ContentIndexPage.create(project: project, title: "Zwei")
    }
    #expect(String(decoding: try Posix.read(first.path), as: UTF8.self).contains("Eins"))
  }

  /// npm still unpacking globby: not loaded, and the sentence says so instead of "npm install".
  @Test func aHalfUnpackedGlobbyIsNotTried() async throws {
    let scratch = try HostPathTests.Scratch()
    let project = try scratch.dir("p")
    try Self.write("\(project)/content", ["a.md": "a"])
    try Posix.write("\(project)/quartz.config.yaml", Data("configuration: {}\n".utf8))
    try Posix.mkdirs("\(project)/node_modules/globby")
    await #expect(throws: ContentIndexPage.Failure.unpacking("globby")) {
      try await ContentIndexPage.create(project: project, title: "T")
    }
    #expect(!FileManager.default.fileExists(atPath: "\(project)/content/index.md"))
  }
}
