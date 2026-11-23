import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// `ThemeLegacy`: what core 2 left behind, found and cleared with one snapshot. The options are
/// core 3.1.1's `DEPRECATED`, the colours what it logs as unknown Style Settings keys
/// (decisions/phase-5-gleichstand.md, „Aufräumen und Vorlagen“).
@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt"))
struct ThemeLegacyTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  static let schema = StyleSettingsSchema.schema(of: StyleSettingsCoreTests.theme([
    StyleSettingsCoreTests.block(.string("t"), [
      StyleSettingsCoreTests.setting([("id", .string("acc")), ("type", .string("variable-color")), ("format", .string("hsl-split")),
                                      ("default", .string("#ffffff"))]),
      StyleSettingsCoreTests.setting([("id", .string("acc2")), ("type", .string("variable-themed-color")), ("format", .string("hsl-split")),
                                      ("default-light", .string("#ffffff")), ("default-dark", .string("#000000"))]),
      StyleSettingsCoreTests.setting([("id", .string("hex")), ("type", .string("variable-color")), ("format", .string("hex"))])
    ])
  ]))

  static let config = """
    configuration:
      pageTitle: Test
    plugins:
      - source: "@quartz-themes/core"
        enabled: true
        options:
          theme: catppuccin.frappe
          aspects: [a]
          calloutStyle: x
          fonts: null
          styleSettings:
            t@@acc-h: 0
            t@@acc-s: 100%
            t@@acc-l: 50%
            t@@acc2@@light: "#00ff00"
            t@@acc2-h@@light: 10
            t@@acc2-h@@dark: 240
            t@@acc2-s@@dark: 100%
            t@@acc2-l@@dark: 50%
            t@@hex-h: 5
            t@@other: keep
      - source: "@quartz-community/explorer"
        enabled: true
        options:
          fonts: mine

    """

  static let packageJson = """
    {"name": "x", "dependencies": {"@quartz-themes/core": "^3.1.0", "@quartz-themes/minimal": "^1.0.1", "@quartz-themes-x/y": "1"},
     "devDependencies": {"@quartz-themes/tokyo-night": "1"}}
    """

  func project(_ config: String = Self.config, packageJson: String = Self.packageJson) throws -> String {
    let project = "\(scratch.path)/Projekt-\u{DC}ber"
    try Posix.mkdirs(project)
    try Posix.write(ConfigFile.path(project: project), Data(config.utf8))
    try Posix.write("\(project)/package.json", Data(packageJson.utf8))
    return project
  }

  @Test func findsWhatCore3PassesOver() async throws {
    let project = try project()
    let config = try await ConfigFile.read(project: project, runtime: HelperRuntime.runtime)
    let found = ThemeLegacy.find(project: project, config: config, schema: Self.schema)
    #expect(found.packages == ["@quartz-themes/minimal", "@quartz-themes/tokyo-night"])
    #expect(found.options == ["aspects", "calloutStyle", "fonts"])
    #expect(found.colors == 2)
    // Without the theme's schema a key ending in -h is not certainly a part.
    let blind = ThemeLegacy.find(project: project, config: config)
    #expect(blind.styleSettingsPatch.isEmpty && blind.colors == 0 && blind.options == found.options)
  }

  @Test func coloursTakeCoresForm() {
    let settings = JSONObject([("t@@acc-h", .number(0)), ("t@@acc-s", .string("100%")), ("t@@acc-l", .string("50%")),
                               ("t@@acc2@@light", .string("#00ff00")), ("t@@acc2-h@@light", .number(10)),
                               ("t@@acc2-h@@dark", .number(240)), ("t@@acc2-s@@dark", .string("100%")), ("t@@acc2-l@@dark", .string("50%")),
                               ("t@@hex-h", .number(5)), ("t@@other", .string("keep"))])
    let (colors, patch) = ThemeLegacy.colorPatch(settings: settings, schema: Self.schema)
    #expect(colors == 2)
    let after = StyleSettingsValues.apply(patch.map { ($0.key, $0.value) }, to: settings)
    #expect(after == JSONObject([("t@@acc2@@light", .string("#00ff00")), ("t@@hex-h", .number(5)), ("t@@other", .string("keep")),
                                 ("t@@acc", .string("#ff0000")), ("t@@acc2@@dark", .string("#0000ff"))]))
    // In core's form already: nothing to do.
    #expect(ThemeLegacy.colorPatch(settings: after, schema: Self.schema).patch.isEmpty)
  }

  @Test func cleanTakesOneSnapshotThenWritesAndUninstalls() async throws {
    let project = try project()
    let calls = Mutex<[String]>([])
    let npm: TemplatePackage.Npm = { arguments, _ in
      calls.withLock { $0.append("npm " + arguments.joined(separator: " ")) }
      return PluginCommands.Result(success: true, output: "")
    }
    let snapshot: SnapshotStore.Take = { _, kind, label in
      calls.withLock { $0.append("snapshot \(kind) \(label)") }
      return "id"
    }
    let outcome = try await ThemeLegacy.clean(project: project, schema: Self.schema, runtime: HelperRuntime.runtime, npm: npm, snapshot: snapshot)
    #expect(outcome.npmFailure == nil)
    #expect(calls.withLock { $0 } == ["snapshot pluginChange \(L10n.t("themeLegacy.snapshotLabel"))",
                                      "npm uninstall @quartz-themes/minimal @quartz-themes/tokyo-night"])
    let config = try await ConfigFile.read(project: project, runtime: HelperRuntime.runtime)
    let options = config.plugins[0].object["options"]?.objectValue
    #expect(options?.keys == ["theme", "styleSettings"])
    #expect(options?["theme"] == .string("catppuccin.frappe"))
    #expect(options?["styleSettings"]?["t@@acc"] == .string("#ff0000"))
    #expect(options?["styleSettings"]?["t@@acc-h"] == nil)
    // Another plugin's option of the same name is its own.
    #expect(config.plugins[1].object["options"]?["fonts"] == .string("mine"))
    // The package.json is npm's to change; the mock left it. Nothing else to do but packages now.
    let again = ThemeLegacy.find(project: project, config: config, schema: Self.schema)
    #expect(again.options.isEmpty && again.styleSettingsPatch.isEmpty && again.packages.count == 2)
  }

  @Test func nothingFoundNothingTouched() async throws {
    let clean = """
      plugins:
        - source: "@quartz-themes/core"
          enabled: true
          options:
            theme: default

      """
    let project = try project(clean, packageJson: #"{"dependencies": {"@quartz-themes/core": "^3.1.0"}}"#)
    let calls = Mutex<Int>(0)
    let outcome = try await ThemeLegacy.clean(project: project, schema: Self.schema, runtime: HelperRuntime.runtime,
                                              npm: { _, _ in calls.withLock { $0 += 1 }; return PluginCommands.Result(success: true, output: "") },
                                              snapshot: { _, _, _ in calls.withLock { $0 += 1 }; return nil })
    #expect(outcome.findings.isEmpty)
    #expect(calls.withLock { $0 } == 0)
    #expect(String(decoding: try Posix.read(ConfigFile.path(project: project)), as: UTF8.self) == clean)
  }

  /// A snapshot that fails stops the clean before anything is written.
  @Test func aFailedSnapshotStops() async throws {
    let project = try project()
    struct Refused: Error {}
    await #expect(throws: Refused.self) {
      _ = try await ThemeLegacy.clean(project: project, schema: Self.schema, runtime: HelperRuntime.runtime,
                                      npm: { _, _ in Issue.record("npm ran"); return PluginCommands.Result(success: true, output: "") },
                                      snapshot: { _, _, _ in throw Refused() })
    }
    #expect(String(decoding: try Posix.read(ConfigFile.path(project: project)), as: UTF8.self) == Self.config)
  }
}
