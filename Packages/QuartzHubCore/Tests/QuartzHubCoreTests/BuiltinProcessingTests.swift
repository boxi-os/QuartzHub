import Foundation
import Testing
@testable import QuartzHubCore

/// `BuiltinProcessing` against the `planBuiltins` cases of Quartz 5.1.0
/// (`quartz/plugins/builtins/builtins.test.ts`), and `QuartzFeatures` against a 5.0 and a 5.1 tree.
@Suite struct BuiltinProcessingTests {
  static func entry(_ source: String, enabled: Bool = true, _ extra: [(String, JSONValue)] = []) -> PluginEntry {
    var object = JSONObject([("source", .string(source)), ("enabled", .bool(enabled))])
    for (key, value) in extra { object[key] = value }
    object["name"] = .string(PluginEntry.derivedName(.string(source)) ?? "")
    return PluginEntry(object: object)
  }

  static func object(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(JSONObject(pairs)) }

  @Test func officialNamesAreQuartzCommunitysOnly() {
    #expect(BuiltinProcessing.officialPluginName(.string("@quartz-community/crawl-links")) == "crawl-links")
    #expect(BuiltinProcessing.officialPluginName(.string("github:quartz-community/remove-draft")) == "remove-draft")
    #expect(BuiltinProcessing.officialPluginName(.string("https://github.com/quartz-community/content-index.git#v1")) == "content-index")
    #expect(BuiltinProcessing.officialPluginName(Self.object([("repo", .string("github:quartz-community/crawl-links"))])) == "crawl-links")
    #expect(BuiltinProcessing.officialPluginName(.string("github:someone/crawl-links")) == nil)
    #expect(BuiltinProcessing.officialPluginName(.string("./plugins/crawl-links")) == nil)
    #expect(BuiltinProcessing.officialPluginName(.string("@someone/crawl-links")) == nil)
  }

  @Test func allAreOnByDefaultWithTheirDefaults() {
    let plan = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [])
    #expect(plan.builtins.map(\.builtin) == BuiltinProcessing.Builtin.allCases)
    #expect(plan.builtins.allSatisfy { $0.enabled })
    #expect(plan[.links].options["markdownLinkResolution"] == .string("shortest"))
    #expect(plan[.frontmatter].order == .number(0))
    #expect(plan[.links].order == .number(60))
    #expect(plan.removesDrafts)
  }

  @Test func configurationSetsOptionsAndTurnsOff() {
    let configuration = JSONObject([
      ("links", Self.object([("markdownLinkResolution", .string("relative")), ("lazyLoad", .bool(true))])),
      ("contentIndex", .bool(false)),
      ("drafts", Self.object([("enabled", .bool(false))])),
    ])
    let plan = BuiltinProcessing.plan(configuration: configuration, plugins: [])
    #expect(plan[.links].options["markdownLinkResolution"] == .string("relative"))
    #expect(plan[.links].options["lazyLoad"] == .bool(true))
    #expect(!plan[.contentIndex].enabled)
    #expect(plan[.contentIndex].note == .disabledInConfiguration)
    #expect(!plan[.drafts].enabled)
    #expect(!plan.removesDrafts)
  }

  @Test func anEnabledCrawlLinksEntryCarriesOver() {
    let crawl = Self.entry("@quartz-community/crawl-links", [("options", Self.object([("lazyLoad", .bool(true))])), ("order", .number(65))])
    let plan = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [crawl])
    #expect(plan[.links].enabled)
    // crawl-links defaulted to "absolute": a migrated entry keeps the old behaviour.
    #expect(plan[.links].options["markdownLinkResolution"] == .string("absolute"))
    #expect(plan[.links].options["lazyLoad"] == .bool(true))
    #expect(plan[.links].order == .number(65))
    #expect(plan[.links].absorbed == 0)
    #expect(plan.absorbedEntries == [0])
  }

  @Test func configurationWinsOverAnAbsorbedEntry() {
    let crawl = Self.entry("@quartz-community/crawl-links", [("options", Self.object([("markdownLinkResolution", .string("absolute"))]))])
    let configuration = JSONObject([("links", Self.object([("markdownLinkResolution", .string("shortest"))]))])
    let plan = BuiltinProcessing.plan(configuration: configuration, plugins: [crawl])
    #expect(plan[.links].options["markdownLinkResolution"] == .string("shortest"))
  }

  @Test func aDisabledLegacyEntryKeepsTheFeatureOff() {
    let off = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [Self.entry("github:quartz-community/remove-draft", enabled: false)])
    #expect(!off[.drafts].enabled)
    #expect(off[.drafts].note == .disabledByEntry(plugin: "remove-draft"))
    #expect(!off.removesDrafts)
    let forced = BuiltinProcessing.plan(configuration: JSONObject([("drafts", Self.object([("enabled", .bool(true))]))]),
                                        plugins: [Self.entry("github:quartz-community/remove-draft", enabled: false)])
    #expect(forced[.drafts].enabled)
    #expect(forced.removesDrafts)
    // The counter-case: an enabled entry and no configuration filters drafts, as 5.0 did.
    #expect(BuiltinProcessing.plan(configuration: JSONObject(), plugins: [Self.entry("github:quartz-community/remove-draft")]).removesDrafts)
  }

  @Test func publishTrueLetsDraftsThrough() {
    let plan = BuiltinProcessing.plan(configuration: JSONObject([("drafts", Self.object([("publish", .bool(true))]))]), plugins: [])
    #expect(plan[.drafts].enabled)
    #expect(!plan.removesDrafts)
  }

  @Test func itYieldsToAnEnabledProvider() {
    let provides: (PluginEntry) -> [String: [String]]? = { $0.object["source"] == .string("my-frontmatter") ? ["data": ["frontmatter"]] : nil }
    let plan = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [Self.entry("my-frontmatter")], providesOf: provides)
    #expect(!plan[.frontmatter].enabled)
    #expect(plan[.frontmatter].note == .replacedBy(plugin: "my-frontmatter"))
    // `enabled: true` runs both.
    let both = BuiltinProcessing.plan(configuration: JSONObject([("frontmatter", Self.object([("enabled", .bool(true))]))]),
                                      plugins: [Self.entry("my-frontmatter")], providesOf: provides)
    #expect(both[.frontmatter].enabled)
    // A disabled provider replaces nothing.
    let off = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [Self.entry("my-frontmatter", enabled: false)], providesOf: provides)
    #expect(off[.frontmatter].enabled)
  }

  @Test func notePropertiesDonatesDelimitersAndLanguage() {
    let notes = Self.entry("@quartz-community/note-properties", [("options", Self.object([
      ("delimiters", .string("+++")), ("language", .string("toml")), ("includeAll", .bool(true)),
    ]))])
    let plan = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [notes])
    #expect(plan[.frontmatter].options["delimiters"] == .string("+++"))
    #expect(plan[.frontmatter].options["language"] == .string("toml"))
    #expect(plan[.frontmatter].options["includeAll"] == nil)
    #expect(plan.absorbedEntries.isEmpty)
  }

  /// `findBuiltinMigrations`: the absorbed entries on or off, note-properties only with the two keys.
  @Test func pendingMigrationsAreWhatDoctorFixWouldChange() {
    let plugins = [
      Self.entry("github:quartz-community/explorer"),
      Self.entry("github:quartz-community/crawl-links", enabled: false),
      Self.entry("@quartz-community/note-properties", [("options", Self.object([("includeAll", .bool(true))]))]),
      Self.entry("@quartz-community/note-properties", enabled: false, [("options", Self.object([("language", .string("yaml"))]))]),
      Self.entry("github:someone/content-index"),
      Self.entry("@quartz-community/content-index"),
    ]
    #expect(BuiltinProcessing.pendingMigrations(plugins) == [1, 3, 5])
  }

  @Test func featuresAreReadFromTheProject() throws {
    let scratch = try HostPathTests.Scratch()
    let project = scratch.path
    // A 5.0 tree: none of it.
    try Posix.write("\(project)/package.json", Data(#"{"name":"@jackyzha0/quartz","version":"5.0.0"}"#.utf8))
    try scratch.dir("quartz")
    try Posix.write("\(project)/quartz/cfg.ts", Data("export interface GlobalConfiguration {\n  enableSPA: boolean\n}\n".utf8))
    #expect(QuartzFeatures.read(project: project) == QuartzFeatures(version: "5.0.0"))
    // 5.1: the built-ins folder and the declarations.
    try scratch.dir("quartz/plugins/builtins")
    try Posix.write("\(project)/quartz/plugins/builtins/index.ts", Data())
    try Posix.write("\(project)/quartz/cfg.ts", Data("""
      export interface GlobalConfiguration {
        prefetch?: "viewport" | "hover" | "off"
        publishAssets?: "all" | "referenced"
      }
      export interface FullPageLayout {
        sidebars?: SidebarModes
      }
      """.utf8))
    try Posix.write("\(project)/package.json", Data(#"{"version":"5.1.0"}"#.utf8))
    #expect(QuartzFeatures.read(project: project) == .quartz51)
  }
}
