import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own styleService.ts: `scripts/managed-styles-golden.mjs` ran its text
/// functions on 29 texts and its file functions through 15 sequences on stylesheets of gui-test and
/// Example (and made-up ones), recording every answer and every file a step changed.
@Suite struct ManagedStylesTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/managed-styles")
  static var stepCases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.appendingPathComponent("steps").path)) ?? [])
      .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  static func pure() throws -> JSONValue {
    try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("pure.json")))
  }

  @Test func thereAreCases() throws {
    #expect(Self.stepCases.count >= 15)
    #expect((try Self.pure()["texts"]?.arrayValue?.count ?? 0) >= 29)
  }

  static func same(_ expected: JSONValue?, _ text: String) -> String? {
    if expected?["same"] == .bool(true) { return text }
    return expected?.stringValue
  }

  static func optional(_ value: String?) -> JSONValue { value.map { .string($0) } ?? .null }

  @Test func textFunctionsAsQuartzControl() throws {
    for entry in try Self.pure()["texts"]?.arrayValue ?? [] {
      let name = entry["name"]!.stringValue!, text = entry["text"]!.stringValue!
      for id in ["imports", "fonts", "google-fonts", "css-vars", "imported-styles"] {
        #expect(Self.optional(ManagedBlocks.body(text, id)) == entry["get"]?[id], "\(name) get \(id)")
        #expect(ManagedBlocks.strip(text, id) == Self.same(entry["strip"]?[id], text), "\(name) strip \(id)")
        #expect(ManagedBlocks.upsert(text, id, "BODY") == Self.same(entry["upsert"]?[id], text), "\(name) upsert \(id)")
        #expect(ManagedBlocks.upsert(text, id, "") == Self.same(entry["emptyUpsert"]?[id], text), "\(name) empty upsert \(id)")
        let spans = JSONValue.array(ManagedBlocks.findBlocks(text, id).map { .object(JSONObject([("from", .number(Double($0.from))), ("to", .number(Double($0.to)))])) })
        #expect(spans == entry["spans"]?[id], "\(name) spans \(id)")
      }
      #expect(.bool(ManagedBlocks.hasManagedUse(text)) == entry["hasUse"], "\(name) hasUse")
      #expect(ManagedBlocks.stripManagedUse(text) == Self.same(entry["stripUse"], text), "\(name) stripUse")
      #expect(ManagedBlocks.ensureManagedUse(text) == Self.same(entry["ensureUse"], text), "\(name) ensureUse")
      #expect(ManagedBlocks.renameLegacyMarkers(text) == Self.same(entry["rename"], text), "\(name) rename")
      #expect(ManagedBlocks.migrateOnWrite(text) == Self.same(entry["migrate"], text), "\(name) migrate")
      #expect(ManagedBlocks.relativeFontUrls(text) == Self.same(entry["relativeUrls"], text), "\(name) relativeUrls")
      #expect(JSONValue.array(ManagedBlocks.splitRules(text).map { .string($0) }) == entry["split"], "\(name) split")
      #expect(ManagedBlocks.joinUniqueRules([text, text]) == Self.same(entry["joinTwice"], text), "\(name) join")
      #expect(ManagedBlocks.insertBeforeRules(text, "INSERTED") == Self.same(entry["insert"], text), "\(name) insert")
      #expect(ManagedBlocks.upsertImportBlock(text, #"@use "./custom/z";"#) == Self.same(entry["importBlock"], text), "\(name) importBlock")
      #expect(ManagedBlocks.upsertImportBlock(text, "") == Self.same(entry["importBlockEmpty"], text), "\(name) importBlock empty")
      #expect(JSONValue.array(VariableOverrides.parse(text).map(\.json)) == entry["overrides"], "\(name) overrides")
      let sources = StyleSheets.Sources(custom: text, managed: text, managedExists: true)
      #expect(Self.optional(StyleSheets.managedBody(sources, "css-vars")) == entry["sources"], "\(name) managedBody")
      #expect(StyleSheets.sourcesWithout(StyleSheets.Sources(custom: text, managed: "", managedExists: false), "fonts") == entry["without"]?.stringValue, "\(name) without")
    }
  }

  static func override(_ value: JSONValue) -> VariableOverride {
    VariableOverride(key: value["key"]?.stringValue ?? "", light: value["light"]?.stringValue ?? "",
                     dark: value["dark"]?.stringValue, lightOnly: value["lightOnly"] == .bool(true))
  }

  @Test func renderAsQuartzControl() throws {
    for entry in try Self.pure()["renders"]?.arrayValue ?? [] {
      let overrides = (entry["overrides"]?.arrayValue ?? []).map(Self.override)
      #expect(VariableOverrides.render(overrides) == entry["rendered"]?.stringValue, "\(entry["overrides"]!)")
    }
  }

  /// The build door: a moved project without its `@use` line gets it back, and the font URLs of
  /// its fonts block become relative; both are said in the console. A second run says nothing.
  @Test func theBuildDoorRepairsTheStyles() async throws {
    let project = scratch.url.appendingPathComponent("door")
    let styles = StyleSheets.stylesDirectory(project)
    try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
    let (start, end) = ManagedBlocks.markers("fonts")
    try Data("// head\n\(start)\n@font-face { src: url(\"/static/fonts/a.woff2\"); }\n\(end)\n".utf8).write(to: StyleSheets.managedScss(project))
    try Data("@use \"./variables.scss\" as *;\n.x {}\n".utf8).write(to: StyleSheets.customScss(project))
    func run() async -> [String] {
      let said = Mutex<[String]>([])
      for step in BuildService.preparation { await step(project) { stream, text in said.withLock { $0.append("\(stream) \(text)") } } }
      return said.withLock { $0 }
    }
    #expect(await run() == ["stdout \(L10n.t("main.managedUseRestored"))\n", "stdout \(L10n.t("main.fontUrlsMigrated"))\n"])
    #expect(ManagedBlocks.hasManagedUse(try String(contentsOf: StyleSheets.customScss(project), encoding: .utf8)))
    #expect(try String(contentsOf: StyleSheets.managedScss(project), encoding: .utf8).contains("url(\"static/fonts/a.woff2\")"))
    #expect(await run() == [])
  }

  // MARK: steps

  @Test(arguments: stepCases)
  func stepsAsQuartzControl(_ file: String) async throws {
    let golden = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps/\(file).json")))
    let project = scratch.url.appendingPathComponent(file)
    let styles = StyleSheets.stylesDirectory(project)
    try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
    let tree = golden["tree"]?.objectValue ?? JSONObject()
    for path in tree.keys {
      let url = styles.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(tree[path]!.stringValue!.utf8).write(to: url)
    }
    var before = Self.files(styles)
    for step in golden["steps"]?.arrayValue ?? [] {
      let call = step["call"]!.stringValue!
      let args = step["args"]?.arrayValue ?? []
      var result: JSONValue
      do {
        result = try await Self.run(call, args, project)
      } catch {
        result = .object(JSONObject([("threw", .string(String(describing: error)))]))
      }
      #expect(Self.mask(result, scratch.url.path) == step["result"], "\(file): \(call)")
      let after = Self.files(styles)
      var changed: [String: String?] = [:]
      for path in Set(before.keys).union(after.keys) where before[path] != after[path] { changed[path] = .some(after[path]) }
      let expected = step["changed"]?.objectValue ?? JSONObject()
      #expect(Set(changed.keys) == Set(expected.keys), "\(file): \(call) changed")
      for path in expected.keys where changed[path] != .some(expected[path]?.stringValue) {
        Issue.record("\(file): \(call) wrote \(path) differently\n\(firstDifference(changed[path].flatMap { $0 } ?? "<none>", expected[path]?.stringValue ?? "<removed>"))")
      }
      before = after
    }
  }

  static func run(_ call: String, _ args: [JSONValue], _ project: URL) async throws -> JSONValue {
    switch call {
    case "getVariableOverrides": return .array(try StyleSheets.variableOverrides(project: project).map(\.json))
    case "variableCollisions": return .array(try StyleSheets.variableCollisions(project: project).map { .string($0) })
    case "currentOrder": return .array(try StyleSheets.currentOrder(project: project).map { .string($0) })
    case "loadedStylesheetsLastFirst": return .array(try StyleSheets.loadedStylesheetsLastFirst(project: project).map { .string($0.path) })
    case "saveVariableOverrides":
      try await StyleSheets.saveVariableOverrides((args[0].arrayValue ?? []).map(override), project: project)
      return .null
    case "setImportOrder":
      try await StyleSheets.setImportOrder((args[0].arrayValue ?? []).compactMap(\.stringValue), project: project)
      return .null
    case "repairManagedUse": return try await StyleSheets.repairManagedUse(project: project).map { .string($0.rawValue) } ?? .null
    case "migrateFontUrls": return .bool(try await StyleSheets.migrateFontUrls(project: project))
    case "saveCustomScss":
      let restored = try await StyleSheets.saveCustom(args[0].stringValue!, project: project)
      return .object(JSONObject([("managedUseRestored", .bool(restored))]))
    case "writeManagedBlocks":
      let object = args[0].objectValue ?? JSONObject()
      var changes: [String: String?] = [:]
      for key in object.keys { changes[key] = .some(object[key]?.stringValue) }
      try StyleSheets.writeManagedBlocksNow(changes, project: project)
      return .null
    case "migrateManagedStyles":
      let moved = try await StyleSheets.migrate(project: project, snapshot: args[0]["snapshot"] == .bool(true))
      return .object(JSONObject([("moved", .bool(moved)), ("snapshotId", .null)]))
    case "replaceCustomBody":
      try StyleSheets.replaceCustomBodyNow(args[0].stringValue!, project: project)
      return .null
    default:
      Issue.record("unknown call \(call)")
      return .null
    }
  }

  static func mask(_ value: JSONValue, _ root: String) -> JSONValue {
    switch value {
    case .string(let text): return .string(text.replacingOccurrences(of: root, with: "@P@"))
    case .array(let items): return .array(items.map { mask($0, root) })
    default: return value
    }
  }

  static func files(_ root: URL) -> [String: String] {
    var result: [String: String] = [:]
    guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [:] }
    while let relative = walker.nextObject() as? String {
      var isDirectory: ObjCBool = false
      let full = root.appendingPathComponent(relative)
      guard FileManager.default.fileExists(atPath: full.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
      result[relative] = (try? Data(contentsOf: full)).map { String(decoding: $0, as: UTF8.self) }
    }
    return result
  }
}
