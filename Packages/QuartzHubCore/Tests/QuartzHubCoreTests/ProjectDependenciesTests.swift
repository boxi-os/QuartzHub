import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own projectDependencies.ts: `scripts/deps-golden.mjs` laid out each
/// project of `Fixtures/dependencies/<case>/case.json` and recorded the answers to its questions.
@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt"))
struct ProjectDependenciesTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/dependencies")
  static var cases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 7, "scripts/deps-golden.mjs")
  }

  @Test(arguments: cases)
  func sameAsQuartzControl(_ name: String) async throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("\(name)/case.json")))
    let w = "\(scratch.path)/w"
    let project = "\(w)/P"
    try ProjectDuplicatorTests.layOut(spec["tree"]!, at: URL(fileURLWithPath: project)) { $0.replacingOccurrences(of: "@W@", with: w, options: .literal) }

    let strings = { (list: [String]?) in list.map { JSONValue.array($0.map(JSONValue.string)) } ?? .null }
    for (index, question) in (spec["ask"]?.arrayValue ?? []).enumerated() {
      let ask = question.arrayValue!.compactMap(\.stringValue)
      let answer: JSONValue = switch ask[0] {
      case "missingDependencies": strings(ProjectDependencies.missingDependencies(project: project))
      case "halfUnpackedModule": ProjectDependencies.halfUnpackedModule(project: project, ask[1]).map(JSONValue.string) ?? .null
      default: strings(await ProjectDependencies.missingAuthoredFrames(project: project, runtime: HelperRuntime.runtime))
      }
      // By bytes: a name the answer took through Foundation would come back decomposed.
      #expect(Array(JSJSON.compact(answer).utf8) == Array(JSJSON.compact(spec["answers"]?.arrayValue?[index] ?? .null).utf8),
              "\(name): \(ask.joined(separator: " "))")
    }
  }
}
