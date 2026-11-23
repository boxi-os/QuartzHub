import Foundation
import Testing
@testable import QuartzHubCore

/// `BuiltinProcessing` against the `planBuiltins` cases of Quartz 5.1.0 and 5.2.0
/// (`quartz/plugins/builtins/builtins.test.ts`), and `QuartzFeatures` against a 5.0, 5.1 and 5.2 tree.
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
    #expect(plan.builtins.map(\.builtin) == [.frontmatter, .links, .drafts, .contentIndex], "5.1 has no fonts built-in")
    #expect(plan.planned(.fonts) == nil)
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

  /// Quartz takes the entry's `order` whenever the key is there (`!== undefined`), null included.
  @Test func aNullOrderOfTheEntryIsTakenAsQuartzTakesIt() {
    let crawl = Self.entry("@quartz-community/crawl-links", [("order", .null)])
    #expect(BuiltinProcessing.plan(configuration: JSONObject(), plugins: [crawl])[.links].order == .null)
    let without = Self.entry("@quartz-community/crawl-links", [])
    #expect(BuiltinProcessing.plan(configuration: JSONObject(), plugins: [without])[.links].order != .null)
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

  /// 5.1 needs GitHubFlavoredMarkdown first; gui-test and QuartzControl's basic template had 30/40
  /// the other way round.
  @Test func theMarkdownOrderOf50IsFound() {
    let old = [Self.entry("@quartz-community/obsidian-flavored-markdown", [("order", .number(30))]),
               Self.entry("github:quartz-community/github-flavored-markdown", [("order", .number(40))])]
    let problem = BuiltinProcessing.markdownOrderProblem(old)
    #expect(problem?.gfm == 1 && problem?.ofm == 0)
    #expect(BuiltinProcessing.fixedMarkdownOrder(old, gfm: 1, ofm: 0) == (30, 40))
    // 5.1's own order, defaults without `order`, and a pair with one switched off are fine.
    let new = [Self.entry("@quartz-community/github-flavored-markdown", [("order", .number(30))]),
               Self.entry("@quartz-community/obsidian-flavored-markdown", [("order", .number(40))])]
    #expect(BuiltinProcessing.markdownOrderProblem(new) == nil)
    #expect(BuiltinProcessing.markdownOrderProblem([Self.entry("@quartz-community/obsidian-flavored-markdown"),
                                                    Self.entry("@quartz-community/github-flavored-markdown")]) == nil)
    #expect(BuiltinProcessing.markdownOrderProblem([old[0], Self.entry("github:quartz-community/github-flavored-markdown", enabled: false, [("order", .number(40))])]) == nil)
    // Equal orders leave it to the file's order, which Quartz does not promise: 30 and 40.
    let tie = [Self.entry("@quartz-community/obsidian-flavored-markdown", [("order", .number(35))]),
               Self.entry("@quartz-community/github-flavored-markdown", [("order", .number(35))])]
    #expect(BuiltinProcessing.markdownOrderProblem(tie) != nil)
    #expect(BuiltinProcessing.fixedMarkdownOrder(tie, gfm: 1, ofm: 0) == (30, 40))
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
      export type Analytics = { provider: "posthog"; apiHost?: string }
      export interface FullPageLayout {
        sidebars?: SidebarModes
      }
      """.utf8))
    try Posix.write("\(project)/package.json", Data(#"{"version":"5.1.0"}"#.utf8))
    #expect(QuartzFeatures.read(project: project) == .quartz51)
    // 5.2: the fonts built-in.
    try Posix.write("\(project)/quartz/plugins/builtins/fonts.ts", Data())
    try Posix.write("\(project)/package.json", Data(#"{"version":"5.2.0"}"#.utf8))
    #expect(QuartzFeatures.read(project: project) == .quartz52)
    // 5.2.0's declaration, then 5.2.1's: the built-in loads the interface and heading fonts.
    try Posix.write("\(project)/quartz/plugins/builtins/fonts.ts",
                    Data(#"type FontRole = "title" | "header" | "body" | "code"\#n// "interface" in a comment"#.utf8))
    #expect(QuartzFeatures.read(project: project) == .quartz52)
    try Posix.write("\(project)/quartz/plugins/builtins/fonts.ts",
                    Data(#"type FontRole = "title" | "header" | "body" | "code" | "interface"\#n"#.utf8))
    try Posix.write("\(project)/package.json", Data(#"{"version":"5.2.1"}"#.utf8))
    var without = QuartzFeatures.quartz521
    without.themesCore3 = false
    #expect(QuartzFeatures.read(project: project) == without)
    // The installed core: 2.0.1's declaration has resolveThemeId, 3.x's resolveTheme.
    _ = try scratch.dir("node_modules/@quartz-themes/core/dist")
    let types = "\(project)/node_modules/@quartz-themes/core/dist/index.d.ts"
    try Posix.write(types, Data("declare function resolveThemeId(theme: string, variation?: string): string;\n".utf8))
    #expect(QuartzFeatures.read(project: project) == without)
    try Posix.write(types, Data("declare function resolveTheme(spec: string, opts?: SourceOptions): Promise<ResolvedTheme>;\n".utf8))
    #expect(QuartzFeatures.read(project: project) == .quartz521)
  }

  // MARK: Quartz 5.2's fonts

  @Test func fontsAreOnByDefaultIn52() {
    let plan = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [], features: .quartz52)
    #expect(plan.builtins.map(\.builtin) == BuiltinProcessing.Builtin.allCases)
    let fonts = plan.planned(.fonts)
    #expect(fonts?.enabled == true)
    #expect(fonts?.order == .number(60))
    #expect(fonts?.options["fontOrigin"] == .string("googleFonts"))
    #expect(fonts?.options["useThemeFonts"] == .bool(true))
  }

  /// "absorbs a @quartz-community/quartz-fonts entry with its options"
  @Test func aQuartzFontsEntryCarriesOverIn52() {
    let fonts = Self.entry("@quartz-community/quartz-fonts", [("options", Self.object([("h1", .string("Lora")), ("fontOrigin", .string("local"))]))])
    let plan = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [fonts], features: .quartz52)
    #expect(plan.planned(.fonts)?.enabled == true)
    #expect(plan.planned(.fonts)?.options["h1"] == .string("Lora"))
    #expect(plan.planned(.fonts)?.options["fontOrigin"] == .string("local"))
    #expect(plan.absorbedEntries == [0])
    // The entry named "fonts" too.
    #expect(BuiltinProcessing.absorbing(Self.entry("github:quartz-community/fonts"), features: .quartz52) == .fonts)
  }

  /// "a disabled plugin entry turns the built-in off"; measured on gui-test, 2026-11-22.
  @Test func aDisabledQuartzFontsEntryTurnsItOffIn52() {
    let plan = BuiltinProcessing.plan(configuration: JSONObject(), plugins: [Self.entry("@quartz-community/quartz-fonts", enabled: false)],
                                      features: .quartz52)
    #expect(plan.planned(.fonts)?.enabled == false)
    #expect(plan.planned(.fonts)?.note == .disabledByEntry(plugin: "quartz-fonts"))
  }

  /// On 5.1 the quartz-fonts entry is a plugin: not absorbed, nothing for doctor to move.
  @Test func on51QuartzFontsIsAPlugin() {
    let entries = [Self.entry("@quartz-community/quartz-fonts"), Self.entry("@quartz-community/crawl-links")]
    #expect(BuiltinProcessing.absorbing(entries[0]) == nil)
    #expect(BuiltinProcessing.pendingMigrations(entries) == [1])
    #expect(BuiltinProcessing.pendingMigrations(entries, features: .quartz52) == [0, 1])
    #expect(BuiltinProcessing.plan(configuration: JSONObject(), plugins: entries).absorbedEntries == [1])
  }

  @Test func aMarketplaceRepositoryIsBuiltInByTheProjectsQuartz() {
    #expect(BuiltinProcessing.absorbing(repository: "quartz-community/quartz-fonts", features: .quartz52) == .fonts)
    #expect(BuiltinProcessing.absorbing(repository: "quartz-community/quartz-fonts", features: .quartz51) == nil)
    #expect(BuiltinProcessing.absorbing(repository: "Quartz-Community/crawl-links", features: .quartz51) == .links)
    #expect(BuiltinProcessing.absorbing(repository: "quartz-community/crawl-links", features: QuartzFeatures(version: "5.0.0")) == nil)
    #expect(BuiltinProcessing.absorbing(repository: "someone/quartz-fonts", features: .quartz52) == nil)
  }
}
