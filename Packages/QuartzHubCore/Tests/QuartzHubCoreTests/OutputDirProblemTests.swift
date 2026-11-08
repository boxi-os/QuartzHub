import Foundation
import Testing
@testable import QuartzHubCore

/// `ProjectPrefs.outputDirProblem` against QuartzControl's `projectPrefs` schema
/// (`scripts/output-dir-golden.mjs`).
@Suite struct OutputDirProblemTests {
  struct Case: Decodable {
    let outputDir: String
    let ok: Bool
  }

  static let cases: [Case] = {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/output-dir/cases.json")
    return (try? JSONDecoder().decode([Case].self, from: Data(contentsOf: file))) ?? []
  }()

  @Test func theFixtureIsThere() {
    #expect(Self.cases.count == 37)
    #expect(Set(Self.cases.map(\.ok)) == [true, false])
  }

  @Test(arguments: cases.indices)
  func sameAsQuartzControl(_ index: Int) {
    let item = Self.cases[index]
    #expect((ProjectPrefs.outputDirProblem(item.outputDir) == nil) == item.ok, "\(item.outputDir.prefix(30)) (\(item.outputDir.utf16.count))")
  }
}
