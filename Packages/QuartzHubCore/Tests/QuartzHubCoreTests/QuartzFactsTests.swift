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

  /// What Konfiguration ▸ Verarbeitung shows comes from the plan: with 5.3.1's facts a file that
  /// says nothing marks broken links, one that says `false` does not, and an old crawl-links entry
  /// still brings its own defaults. Without facts, the constants (5.2's answer).
  @Test func thePlanTakesTheProjectsDefaults() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    var features = QuartzFeatures.quartz521
    features.facts = try await Self.facts(try Self.project("5.3.1", in: scratch))
    let silent = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [], features: features)
    #expect(silent[.links].options["disableBrokenWikilinks"] == .bool(true))
    #expect(BuiltinProcessing.plan(configuration: JSONObject(), plugins: [], features: .quartz521)[.links].options["disableBrokenWikilinks"] == .bool(false))
    let off = JSONObject([("links", .object(JSONObject([("disableBrokenWikilinks", .bool(false))])))])
    #expect(BuiltinProcessing.plan(configuration: off, plugins: [], features: features)[.links].options["disableBrokenWikilinks"] == .bool(false))
    let crawl = PluginEntry(object: JSONObject([("source", .string("github:quartz-community/crawl-links")), ("enabled", .bool(true))]))
    let legacy = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [crawl], features: features)[.links]
    #expect(legacy.options["markdownLinkResolution"] == .string("absolute"))
    #expect(legacy.order == .number(60))
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

/// How the inspector reads a `condition`, without the helper: the facts as 5.2.2 and 5.3.1 give them.
struct ConditionChoiceTests {
  static let quartz522 = QuartzFacts(builtins: .missing, conditions: .read(.init(names: LayoutBoard.builtinConditions, negation: false)))
  static let quartz531 = QuartzFacts(builtins: .missing, conditions: .read(.init(
    names: ["is-index", "not-index", "is-folder-index", "has-tags", "has-backlinks", "has-toc"], negation: true)))

  @Test func namesNegationsAndTheRest() {
    typealias C = LayoutBoard.ConditionChoice
    #expect(LayoutBoard.conditionChoice("", facts: Self.quartz531) == C.always)
    #expect(LayoutBoard.conditionChoice("has-tags", facts: Self.quartz531) == C.known("has-tags", negated: false))
    #expect(LayoutBoard.conditionChoice("not-has-tags", facts: Self.quartz531) == C.known("has-tags", negated: true))
    // Its own built-in, not the negation of a condition "index".
    #expect(LayoutBoard.conditionChoice("not-index", facts: Self.quartz531) == C.known("not-index", negated: false))
    #expect(LayoutBoard.conditionChoice("not-is-folder-index", facts: Self.quartz531) == C.known("is-folder-index", negated: true))
    #expect(LayoutBoard.conditionChoice("is-draft", facts: Self.quartz531) == C.custom("is-draft"))
    #expect(LayoutBoard.conditionChoice("not-is-draft", facts: Self.quartz531) == C.custom("not-is-draft"))
    // 5.2 knows no negation and no is-index: both are names QuartzHub cannot place.
    #expect(LayoutBoard.conditionChoice("not-has-tags", facts: Self.quartz522) == C.custom("not-has-tags"))
    #expect(LayoutBoard.conditionChoice("is-index", facts: Self.quartz522) == C.custom("is-index"))
    // Without any facts, the constants.
    #expect(LayoutBoard.conditionChoice("has-toc", facts: QuartzFacts()) == C.known("has-toc", negated: false))
    for choice in [C.always, .known("has-tags", negated: true), .known("not-index", negated: false), .custom("x")] {
      #expect(LayoutBoard.conditionChoice(LayoutBoard.condition(choice), facts: Self.quartz531) == (choice == .custom("x") ? .custom("x") : choice))
    }
  }
}

/// „Weitere Einstellungen“ from Quartz's own schema files of v5.2.2 and v5.3.1 (in the same fixtures).
struct QuartzConfigSchemaTests {
  static let fixtures = QuartzFactsTests.fixtures

  /// 5.2.2 describes nothing QuartzHub lacks a field for; 5.3.1 adds `slugs`, as an object with one
  /// boolean that defaults to false and carries Quartz's description.
  @Test func onlyWhatQuartzHubHasNoFieldFor() throws {
    let old = try #require(QuartzConfigSchema.moreSettings(project: "\(Self.fixtures)/5.2.2"))
    #expect(old.fields.isEmpty && old.notes.isEmpty)
    let new = try #require(QuartzConfigSchema.moreSettings(project: "\(Self.fixtures)/5.3.1"))
    #expect(new.fields.map(\.key) == ["slugs"])
    #expect(new.notes.isEmpty)
    guard case .object(let fields, _) = new.fields[0].node else { Issue.record("\(new.fields[0].node)"); return }
    #expect(fields.map(\.key) == ["stripDiacritics"])
    #expect(fields[0].node == .boolean && fields[0].defaultValue == .bool(false))
    #expect(fields[0].description?.hasPrefix("Strip accents") == true)
    // Gegenprobe: without the filter, every top-level key of Quartz's schema.
    #expect(QuartzConfigSchema.ownKeys.isSubset(of: Set(["fonts"] + OptionSchema.normalize(
      jsonSchema: try JSJSON.parse(try Posix.read(QuartzConfigSchema.path(project: "\(Self.fixtures)/5.3.1")))["properties"]!["configuration"]!,
      source: .configSchema).fields.map(\.key))))
  }

  @Test func noSchemaNoSection() {
    #expect(QuartzConfigSchema.moreSettings(project: "/nowhere-Ü") == nil)
  }

  /// The section edits only its keys, in place; QuartzHub's own stay as they are.
  @Test func applyingKeepsOrderAndOwnKeys() {
    let configuration = JSONObject([("pageTitle", .string("T")), ("slugs", .object(JSONObject([("stripDiacritics", .bool(true))]))),
                                    ("custom", .number(1)), ("baseUrl", .string("x"))])
    #expect(QuartzConfigSchema.values(configuration).keys == ["slugs", "custom"])
    let off = QuartzConfigSchema.applying(JSONObject([("slugs", .object(JSONObject([("stripDiacritics", .bool(false))]))), ("custom", .number(1))]),
                                          to: configuration)
    #expect(off.keys == ["pageTitle", "slugs", "custom", "baseUrl"])
    #expect(off["slugs"]?.objectValue?["stripDiacritics"] == .bool(false))
    let cleared = QuartzConfigSchema.applying(nil, to: configuration)
    #expect(cleared.keys == ["pageTitle", "baseUrl"])
    // A key of QuartzHub's own in `next` is not the section's to write.
    #expect(QuartzConfigSchema.applying(JSONObject([("pageTitle", .string("other"))]), to: configuration)["pageTitle"] == .string("T"))
  }
}

/// The hint on Updates: a release newer than the checked one, nothing for it or an older one.
struct TestedQuartzTests {
  @Test func onlyNewerReleasesAreUntested() {
    #expect(CoreUpdate.untested(nil) == nil)
    #expect(CoreUpdate.untested(CoreUpdate.testedQuartz) == nil)
    #expect(CoreUpdate.untested("5.1.0") == nil)
    #expect(CoreUpdate.untested("99.0.0") == "99.0.0")
    #expect(CoreUpdate.untested("not a version") == nil)
  }
}
