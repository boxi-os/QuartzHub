import Foundation
import Testing
@testable import QuartzHubCore

/// The helper `theme-fetch` against a stand-in core 3 (`Fixtures/theme-fetch/core3`): its
/// `resolveTheme` reports spec, working folder and options in `source`, so each test sees what the
/// helper made of the entry's options, the way core 3.1.1's `QuartzTheme` makes them. Against the
/// real core 3.1.1 it was run by hand (decisions/phase-5-gleichstand.md, „themes-core 3“).
@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt: scripts/fetch-runtime.sh, scripts/build-helpers.sh"))
struct ThemeFetchTests {
  static let core3 = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/theme-fetch/core3")

  let scratch: HostPathTests.Scratch
  var project: String { scratch.path }
  var core: String { "\(project)/node_modules/@quartz-themes/core" }

  init() throws {
    scratch = try HostPathTests.Scratch(umlaut: true)
    try Posix.write("\(project)/package.json", Data(#"{"name":"@jackyzha0/quartz","version":"5.2.2"}"#.utf8))
  }

  func installStandIn() throws {
    try Posix.mkdirs("\(project)/node_modules/@quartz-themes")
    try TestFolder.copy(Self.core3, to: core)
  }

  func fetch(_ options: [(String, JSONValue)], offline: Bool = false) async throws -> ThemeFetch.Answer {
    try await ThemeFetch.fetch(project: project, options: JSONObject(options), offline: offline, runtime: HelperRuntime.runtime)
  }

  /// The stand-in's report of the call; `cwd` as Node sees it, with symlinks resolved.
  func call(_ answer: ThemeFetch.Answer) throws -> (theme: ThemeFetch.Theme, report: JSONObject) {
    guard case .loaded(let theme) = answer.outcome else { throw Mismatch("not loaded: \(answer.outcome)") }
    guard case .object(let report) = try JSJSON.parse(theme.source) else { throw Mismatch("source is no report") }
    return (theme, report)
  }

  struct Mismatch: Error { let text: String; init(_ text: String) { self.text = text } }

  var realProject: String {
    guard let resolved = realpath(project, nil) else { return project }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  @Test func theBuildsOptionsReachCore() async throws {
    try installStandIn()
    let answer = try await fetch([("theme", .string("Minimal")), ("version", .string("9.1.4")), ("cacheHours", .number(2)), ("mode", .string("dark"))])
    #expect(answer.coreVersion == "3.9.9")
    let (theme, report) = try call(answer)
    #expect(theme.name == "Minimal" && theme.version == "9.1.4" && theme.css == "body{color:red}")
    #expect(theme.modes == nil && theme.preset == nil)
    #expect(report["spec"] == .string("Minimal"))
    #expect(report["version"] == .string("9.1.4"))
    #expect(report["cacheTtl"] == .number(2 * 60 * 60 * 1000))
    #expect(report["cacheDir"] == .null)
    #expect(report["fetchFailed"] == .null)
    // In the project folder, as the build runs: core's default cache is the project's.
    #expect(report["cwd"]?.stringValue.map { Array($0.utf8) == Array(realProject.utf8) } == true)
    #expect(Posix.exists("\(project)/.quartz-cache/quartz-themes/stand-in.theme.css"))
  }

  @Test func withoutAThemeCoreTakesItsDefault() async throws {
    try installStandIn()
    let (_, report) = try call(try await fetch([]))
    #expect(report["spec"] == .string("Tokyo Night"))
    #expect(report["cacheTtl"] == .number(24 * 60 * 60 * 1000))
  }

  @Test func aVariationJoinsTheThemeAndBringsItsPreset() async throws {
    try installStandIn()
    let (theme, report) = try call(try await fetch([("theme", .string("catppuccin")), ("variation", .string("frappe"))]))
    #expect(report["spec"] == .string("catppuccin.frappe"))
    #expect(theme.preset == JSONObject([("theme-settings@@variant", .string("frappe"))]))
  }

  @Test func aRelativeCacheFolderIsTheProjects() async throws {
    try installStandIn()
    let (_, report) = try call(try await fetch([("theme", .string("Void")), ("cacheDir", .string("cache/themes"))]))
    #expect(report["cacheDir"] == .string("cache/themes"))
    #expect(Posix.exists("\(project)/cache/themes/stand-in.theme.css"))
  }

  @Test func singleModeComesThrough() async throws {
    try installStandIn()
    let (theme, _) = try call(try await fetch([("theme", .string("Void"))]))
    #expect(theme.modes == ["dark"])
  }

  /// `-QHOffline`: core gets a fetch that fails like a closed network, and answers from its cache.
  @Test func offlineCoreGetsAFetchThatFails() async throws {
    try installStandIn()
    let (_, report) = try call(try await fetch([("theme", .string("Nord"))], offline: true))
    #expect(report["fetchFailed"] == .bool(true))
  }

  @Test func coresOwnSentenceWhenItCannotLoad() async throws {
    try installStandIn()
    let answer = try await fetch([("theme", .string("Minmal"))])
    #expect(answer.outcome == .notLoaded(#"theme "Minmal" is not in Obsidian's community theme registry. Did you mean: "Minimal", "Mia", "Mimir"?"#))
  }

  @Test func noCoreInstalled() async throws {
    await #expect(throws: ThemeFetch.Failure.coreMissing) { try await fetch([("theme", .string("Minimal"))]) }
  }

  /// core 2.0.1's exports: `resolveThemeId`, no `resolveTheme`.
  @Test func core2IsOld() async throws {
    try Posix.mkdirs("\(core)/dist")
    try Posix.write("\(core)/package.json", Data(#"{"name":"@quartz-themes/core","version":"2.0.1","type":"module","exports":{".":{"import":"./dist/index.js"},"./package.json":"./package.json"}}"#.utf8))
    try Posix.write("\(core)/dist/index.js", Data("export function resolveThemeId(theme, variation) { return theme }\n".utf8))
    await #expect(throws: ThemeFetch.Failure.coreOld(version: "2.0.1")) { try await fetch([("theme", .string("minimal"))]) }
  }

  @Test func aCoreThatDoesNotLoadIsBroken() async throws {
    try installStandIn()
    try Posix.write("\(core)/dist/index.js", Data("throw new Error(\"boom\")\n".utf8))
    await #expect(throws: ThemeFetch.Failure.coreBroken("boom")) { try await fetch([("theme", .string("Minimal"))]) }
  }

  @Test func notTriedWhileNpmUnpacks() async throws {
    try Posix.mkdirs(core)
    await #expect(throws: ThemeFetch.Failure.unpacking("@quartz-themes/core")) { try await fetch([("theme", .string("Minimal"))]) }
  }
}
