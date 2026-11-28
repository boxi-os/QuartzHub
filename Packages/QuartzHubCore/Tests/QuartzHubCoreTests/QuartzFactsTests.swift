import Foundation
import Testing
@testable import QuartzHubCore

/// The helper `quartz-facts` against Quartz's own files: `Fixtures/quartz-facts/<version>` holds
/// `quartz/plugins/builtins/{index,links,frontmatter,contentIndex,fonts}.ts` and
/// `quartz/plugins/loader/conditions.ts` of the release tags v5.2.2 and v5.3.1, unchanged. Each is
/// copied into a folder with „Gärten-Ü“ first, as a project would be.
@Suite(.enabled(if: HelperRuntime.available && FileManager.default.fileExists(atPath: "\(HelperRuntime.runtime.helpers)/quartz-facts.cjs"),
                "Runtime/ oder Helpers/dist/quartz-facts.cjs fehlt: scripts/fetch-runtime.sh, scripts/build-helpers.sh"))
struct QuartzFactsTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/quartz-facts").path

  static func project(_ version: String, in scratch: HostPathTests.Scratch) throws -> String {
    let project = "\(scratch.path)/\(version)"
    try TreeCopy.copy(from: "\(fixtures)/\(version)", to: project, verbatimSymlinks: true)
    return project
  }

  static func facts(_ project: String) async throws -> QuartzFacts {
    try await QuartzFacts.read(project: project, runtime: HelperRuntime.runtime)
  }

  /// QuartzHub's constants were ported from 5.2: on 5.2.2 Quartz's own answer is the same.
  @Test func quartz522SaysWhatTheConstantsSay() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let facts = try await Self.facts(try Self.project("5.2.2", in: scratch))
    #expect(facts.problems.isEmpty)
    for builtin in BuiltinProcessing.Builtin.allCases {
      #expect(facts.defaults(builtin) == builtin.defaults, "\(builtin)")
      #expect(facts.order(builtin) == builtin.defaultOrder, "\(builtin)")
      #expect(facts.absorbedDefaults(builtin) == builtin.absorbedDefaults, "\(builtin)")
      #expect(facts.builtin(builtin)?.absorbs == builtin.absorbs, "\(builtin)")
    }
    #expect(facts.builtin(.fonts)?.undefinedKeys == ["title", "body", "header", "code", "interface", "h1", "h2", "h3", "h4", "h5", "h6"])
    #expect(facts.conditionNames == LayoutBoard.builtinConditions)
    #expect(!facts.negatesAnyCondition)
  }

  /// 5.3 turned broken-link marking on and added two conditions and `not-<any>`.
  @Test func quartz531SaysWhatChanged() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let facts = try await Self.facts(try Self.project("5.3.1", in: scratch))
    #expect(facts.problems.isEmpty)
    #expect(facts.defaults(.links)["disableBrokenWikilinks"] == .bool(true))
    #expect(BuiltinProcessing.Builtin.links.defaults["disableBrokenWikilinks"] == .bool(false))  // the constant, for contrast
    #expect(facts.conditionNames == ["is-index", "not-index", "is-folder-index", "has-tags", "has-backlinks", "has-toc"])
    #expect(facts.negatesAnyCondition)
  }

  /// A Quartz without the files (5.0, or no Quartz): nothing to report, the constants.
  @Test func missingFilesAreTheConstants() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let facts = try await Self.facts(scratch.path)
    #expect(facts.builtins == .missing && facts.conditions == .missing)
    #expect(facts.problems.isEmpty)
    #expect(facts.defaults(.links) == BuiltinProcessing.Builtin.links.defaults)
    #expect(facts.conditionNames == LayoutBoard.builtinConditions)
  }

  /// A shape the helper does not know is a problem, never an empty answer: the page keeps the
  /// constants, `qh-check quartz-facts` says what was not read. Gegenprobe of each kind.
  @Test func whatIsNotReadIsNamed() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let project = try Self.project("5.3.1", in: scratch)
    let links = "\(project)/quartz/plugins/builtins/links.ts"
    let text = String(decoding: try Posix.read(links), as: UTF8.self)
    try Posix.write(links, Data(text.replacingOccurrences(of: "  prettyLinks: true,", with: "  prettyLinks: computed(),", options: .literal).utf8))
    let conditions = "\(project)/quartz/plugins/loader/conditions.ts"
    try Posix.write(conditions, Data("export const builtinConditions = makeConditions()\n".utf8))

    let facts = try await Self.facts(project)
    #expect(facts.builtin(.links)?.unresolved == ["prettyLinks"])
    // The key that was no literal is QuartzHub's, the others Quartz's.
    #expect(facts.defaults(.links)["prettyLinks"] == .bool(true))
    #expect(facts.defaults(.links)["disableBrokenWikilinks"] == .bool(true))
    guard case .unknown(let reason) = facts.conditions else { Issue.record("conditions: \(facts.conditions)"); return }
    #expect(reason.contains("builtinConditions"))
    #expect(facts.conditionNames == LayoutBoard.builtinConditions)
    #expect(facts.problems == ["builtins.links: prettyLinks", "conditions: \(reason)"])
  }

  /// The answer is kept while the files stay as they are, and asked again when one changes.
  @Test func aChangedFileIsReadAgain() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let project = try Self.project("5.2.2", in: scratch)
    let before = QuartzFacts.fingerprint(project)
    #expect(before == QuartzFacts.fingerprint(project))
    #expect(try await Self.facts(project).conditionNames.count == 4)
    try Posix.write("\(project)/quartz/plugins/loader/conditions.ts",
                    try Posix.read("\(Self.fixtures)/5.3.1/quartz/plugins/loader/conditions.ts"))
    #expect(QuartzFacts.fingerprint(project) != before)
    #expect(try await Self.facts(project).conditionNames.count == 6)
  }
}
