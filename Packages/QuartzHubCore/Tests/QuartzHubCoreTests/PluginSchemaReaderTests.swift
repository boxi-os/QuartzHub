import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own pluginSchemaService.ts: `scripts/option-schema-golden.mjs` asked it
/// about a project of hand-made packages (`Fixtures/option-schema/handmade`) and about the plugins
/// gui-test uses (`Fixtures/option-schema/real`, package.json and .d.ts copied, four page-type
/// entry files), and wrote the canonical answers.
@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt: scripts/fetch-runtime.sh, scripts/build-helpers.sh"))
struct PluginSchemaReaderTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/option-schema")
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  /// QuartzControl's mainT stand-in wrote `{"key","args"}`; here the same text from the catalog.
  /// The reason of an unreadable package.json is the system's, not Node's: both sides compare as
  /// "unreadable, with some reason".
  static func sentence(_ value: JSONValue) -> JSONValue {
    guard case .string(let text) = value else { return value }
    if let call = try? JSJSON.parse(text), let key = call["key"]?.stringValue {
      if key == "pluginSchemaPackageUnreadable" || key == "pluginSchemaTypesUnreadable" { return .string("<\(key)>") }
      var args: [String: String] = [:]
      for name in call["args"]?.objectValue?.keys ?? [] { args[name] = OptionSchema.jsString(call["args"]![name]!) }
      return .string(L10n.t("main.\(key)", args))
    }
    for key in ["pluginSchemaPackageUnreadable", "pluginSchemaTypesUnreadable"] {
      let prefix = L10n.t("main.\(key)", ["reason": ""])
      if text.hasPrefix(prefix), text.count > prefix.count { return .string("<\(key)>") }
    }
    return value
  }

  static func comparable(_ result: JSONValue) -> String {
    guard case .object(var object) = result else { return JSJSON.stringify(result) }
    if let unreadable = object["unreadable"] { object["unreadable"] = sentence(unreadable) }
    return JSJSON.stringify(.object(object))
  }

  func check(project: URL, spec: JSONValue) async throws {
    let masked = { (text: String) in text.replacingOccurrences(of: project.path, with: "@P@", options: .literal) }
    let queries = spec["options"]!.arrayValue!
    let sources = try queries.map { try #require(PluginSource($0["source"]), "\(JSJSON.stringify($0["source"]!))") }
    let reader = PluginSchemaReader()
    let results = await reader.optionSchemas(project: project, sources: sources, runtime: HelperRuntime.runtime)
    for (query, result) in zip(queries, results) {
      let ours = try JSJSON.parse(masked(JSJSON.stringify(result.canonicalJSON)))
      #expect(Self.comparable(ours) == Self.comparable(query["expected"]!), "\(JSJSON.stringify(query["source"]!))")
    }

    if let frames = spec["frames"], frames != .null {
      let plugins = frames["plugins"]!.arrayValue!.map { (name: $0["name"]!.stringValue!, source: $0["source"]) }
      let found = await reader.pageTypeFrames(project: project, plugins: plugins, runtime: HelperRuntime.runtime)
      let expected = frames["expected"]!.objectValue!
      #expect(found == Dictionary(uniqueKeysWithValues: expected.keys.map { ($0, expected[$0]!.stringValue!) }))
    }

    for theme in spec["themes"]?.arrayValue ?? [] {
      let id = theme["id"]!.stringValue!
      let info = PluginSchemaReader.themeStyleSettings(project: project, themeId: id).map {
        JSONValue.object(JSONObject([("styleSettingsId", .array($0.styleSettingsId.map(JSONValue.string))),
                                     ("classSettingKeys", .array($0.classSettingKeys.map(JSONValue.string)))]))
      } ?? .null
      let detail = PluginSchemaReader.localThemeDetail(project: project, themeId: id).map {
        JSONValue.object(JSONObject([("modes", .array($0.modes.map(JSONValue.string))), ("variations", .array($0.variations.map(JSONValue.string))),
                                     ("styleSettingsId", .array($0.styleSettingsId.map(JSONValue.string))), ("fonts", .array($0.fonts.map(JSONValue.string)))]))
      } ?? .null
      #expect(info == theme["info"], "\(id)")
      #expect(detail == theme["detail"], "\(id)")
    }
  }

  @Test func handMadePackagesAsQuartzControl() async throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("handmade/case.json")))
    #expect((spec["options"]?.arrayValue?.count ?? 0) >= 40, "scripts/option-schema-golden.mjs")
    let project = scratch.url.appendingPathComponent("P")
    try ProjectDuplicatorTests.layOut(spec["tree"]!, at: project) { $0 }
    try await check(project: project, spec: spec)
  }

  @Test func theGuiTestPluginsAsQuartzControl() async throws {
    let project = Self.fixtures.appendingPathComponent("real")
    let spec = try JSJSON.parse(Data(contentsOf: project.appendingPathComponent("case.json")))
    #expect((spec["options"]?.arrayValue?.count ?? 0) >= 60, "scripts/option-schema-golden.mjs")
    try await check(project: project, spec: spec)
  }

  /// qh-check option-schema against QuartzControl's check:option-schema, which the golden script ran
  /// over the same project: the same table, the same sentences, line for line.
  @Test func theCheckSaysWhatQuartzControlsSays() async throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("handmade/case.json")))
    let project = scratch.url.appendingPathComponent("P")
    try ProjectDuplicatorTests.layOut(spec["tree"]!, at: project) { $0 }
    let expected = try String(contentsOf: Self.fixtures.appendingPathComponent("handmade/check.txt"), encoding: .utf8)
    let report = try await OptionSchemaCheck.run(project: project.path, runtime: HelperRuntime.runtime)
    #expect(report.text.replacingOccurrences(of: project.path, with: "@P@", options: .literal) == expected)
    #expect(report.unreadable == 4)
  }

  // MARK: beyond QuartzControl's answers

  /// A helper that notes each call in a log before it hands over to the real one.
  func countingRuntime() throws -> (RuntimeLocation, () -> Int) {
    let helpers = scratch.url.appendingPathComponent("helpers")
    let log = scratch.url.appendingPathComponent("helper.log")
    try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
    let real = HelperRuntime.runtime.helpers.appendingPathComponent("dts-schema.cjs").path
    try "require('fs').appendFileSync(\(JSJSON.stringify(.string(log.path))), 'call\\n')\nrequire(\(JSJSON.stringify(.string(real))))\n"
      .write(to: helpers.appendingPathComponent("dts-schema.cjs"), atomically: true, encoding: .utf8)
    var runtime = HelperRuntime.runtime
    runtime.helpers = helpers
    return (runtime, { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").count })
  }

  func plugin(_ project: URL, _ name: String, dts: String, package: String = "{}") throws {
    let dir = project.appendingPathComponent(".quartz/plugins/\(name)")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("dist"), withIntermediateDirectories: true)
    try package.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    try dts.write(to: dir.appendingPathComponent("dist/index.d.ts"), atomically: true, encoding: .utf8)
  }

  @Test func onePageIsOneHelperCallAndTheCacheFollowsTheFiles() async throws {
    let project = scratch.url.appendingPathComponent("P")
    for name in ["a", "b", "c"] { try plugin(project, name, dts: "export interface \(name.uppercased())Options { \(name): string }\n") }
    try plugin(project, "local", dts: "", package: #"{"quartz":{"optionSchema":{"x":{"type":"string"}}}}"#)
    let (runtime, calls) = try countingRuntime()
    let reader = PluginSchemaReader()
    let sources = ["a", "b", "c", "local"].map { PluginSource.string("github:x/\($0)") }

    let first = await reader.optionSchemas(project: project, sources: sources, runtime: runtime)
    #expect(first.map { $0.schema?.fields.map(\.key) ?? [] } == [["a"], ["b"], ["c"], ["x"]])
    #expect(calls() == 1)
    _ = await reader.optionSchemas(project: project, sources: sources, runtime: runtime)
    #expect(calls() == 1, "cached")

    // `quartz plugin update` writes new declarations: the next read sees them.
    try "export interface BOptions { b: string; added: boolean }\n"
      .write(to: project.appendingPathComponent(".quartz/plugins/b/dist/index.d.ts"), atomically: true, encoding: .utf8)
    let second = await reader.optionSchemas(project: project, sources: sources, runtime: runtime)
    #expect(second[1].schema?.fields.map(\.key) == ["b", "added"])
    #expect(calls() == 2)
  }

  @Test func aHelperThatDoesNotAnswerIsASentence() async throws {
    let project = scratch.url.appendingPathComponent("P")
    try plugin(project, "a", dts: "export interface AOptions { a: string }\n")
    try plugin(project, "local", dts: "", package: #"{"quartz":{"optionSchema":{"x":{"type":"string"}}}}"#)
    var broken = HelperRuntime.runtime
    broken.helpers = scratch.url.appendingPathComponent("no-helpers")
    let reader = PluginSchemaReader()
    let results = await reader.optionSchemas(project: project, sources: [.string("github:x/a"), .string("github:x/local")], runtime: broken)
    #expect(results[0].schema == nil)
    #expect(Self.sentence(.string(results[0].unreadable ?? "")) == .string("<pluginSchemaTypesUnreadable>"))
    #expect(results[1].schema?.fields.map(\.key) == ["x"], "a schema from package.json needs no helper")
    // Not cached: with the helper back, the answer comes.
    let again = await reader.optionSchemas(project: project, sources: [.string("github:x/a")], runtime: HelperRuntime.runtime)
    #expect(again[0].schema?.fields.map(\.key) == ["a"])
  }

  @Test func anUnreadableTypesFolderIsASentence() async throws {
    let project = scratch.url.appendingPathComponent("P")
    try plugin(project, "a", dts: "export interface AOptions { a: string }\n")
    let locked = project.appendingPathComponent(".quartz/plugins/a/dist/locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    chmod(locked.path, 0)
    defer { chmod(locked.path, 0o755) }
    let result = await PluginSchemaReader().optionSchema(project: project, source: .string("github:x/a"), runtime: HelperRuntime.runtime)
    #expect(Self.sentence(.string(result.unreadable ?? "")) == .string("<pluginSchemaTypesUnreadable>"), "\(String(describing: result.unreadable))")
  }

  @Test func theFrameCacheFollowsTheFiles() async throws {
    let project = scratch.url.appendingPathComponent("P")
    let dir = project.appendingPathComponent("node_modules/@quartz-community/pt")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #"{"main":"i.js","quartz":{"category":["pageType"]}}"#.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    try #"x = { match: 1, frame: "one" }"#.write(to: dir.appendingPathComponent("i.js"), atomically: true, encoding: .utf8)
    let reader = PluginSchemaReader()
    let plugins: [(name: String, source: JSONValue?)] = [("pt", .string("@quartz-community/pt")), ("same", .string("@quartz-community/pt"))]
    #expect(await reader.pageTypeFrames(project: project, plugins: plugins, runtime: HelperRuntime.runtime) == ["pt": "one", "same": "one"])
    try #"x = { match: 1, frame: "two!" }"#.write(to: dir.appendingPathComponent("i.js"), atomically: true, encoding: .utf8)
    #expect(await reader.pageTypeFrames(project: project, plugins: plugins, runtime: HelperRuntime.runtime) == ["pt": "two!", "same": "two!"])
  }
}
