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
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

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

  /// The `css-vars` rules in 1.3's form: QuartzHub's only change to what QuartzControl writes there
  /// is the `body` half of each head (decided 2026-11-23, `VariableOverrides`), checked on its own
  /// (`theBodyHalf…`). Only inside the block, only the exact heads `render` writes.
  static func cssVarsAsQuartzControl(_ text: String) -> String {
    var out = text
    for span in ManagedBlocks.findBlocks(text, "css-vars").reversed() {
      let block = JSText.replaceAll(JSText.slice(out, span.from, span.to),
                                    #"(:root(?:\[saved-theme="dark"\]|:not\(\[saved-theme="dark"\]\))?),\n\1 body \{"#, template: "$1 {")
      out = JSText.slice(out, 0, span.from) + block + JSText.slice(out, span.to)
    }
    return out
  }

  @Test func renderAsQuartzControl() throws {
    let start = ManagedBlocks.markers("css-vars").0, end = ManagedBlocks.markers("css-vars").1
    for entry in try Self.pure()["renders"]?.arrayValue ?? [] {
      let overrides = (entry["overrides"]?.arrayValue ?? []).map(Self.override)
      let rendered = VariableOverrides.render(overrides)
      let asQuartzControl = Self.cssVarsAsQuartzControl("\(start)\n\(rendered)\n\(end)")
      #expect(asQuartzControl == "\(start)\n\(entry["rendered"]?.stringValue ?? "")\n\(end)", "\(entry["overrides"]!)")
      // Every rule has its body half, and reads back as it was written.
      #expect(!VariableOverrides.hasPlainRules(rendered))
      #expect(VariableOverrides.parse(rendered) == VariableOverrides.parse(entry["rendered"]?.stringValue ?? ""))
    }
  }

  /// The build door: a moved project without its `@use` line gets it back, and the font URLs of
  /// its fonts block become relative; both are said in the console. A second run says nothing.
  @Test func theBuildDoorRepairsTheStyles() async throws {
    let project = "\(scratch.path)/door"
    let styles = StyleSheets.stylesDirectory(project)
    try Posix.mkdirs(styles)
    let (start, end) = ManagedBlocks.markers("fonts")
    try Posix.write(StyleSheets.managedScss(project), Data("// head\n\(start)\n@font-face { src: url(\"/static/fonts/a.woff2\"); }\n\(end)\n".utf8))
    try Posix.write(StyleSheets.customScss(project), Data("@use \"./variables.scss\" as *;\n.x {}\n".utf8))
    func run() async -> [String] {
      let said = Mutex<[String]>([])
      for step in BuildService.preparation { await step(project) { stream, text in said.withLock { $0.append("\(stream) \(text)") } } }
      return said.withLock { $0 }
    }
    #expect(await run() == ["stdout \(L10n.t("main.managedUseRestored"))\n", "stdout \(L10n.t("main.fontUrlsMigrated"))\n"])
    #expect(ManagedBlocks.hasManagedUse(String(decoding: try Posix.read(StyleSheets.customScss(project)), as: UTF8.self)))
    #expect(String(decoding: try Posix.read(StyleSheets.managedScss(project)), as: UTF8.self).contains("url(\"static/fonts/a.woff2\")"))
    #expect(await run() == [])
  }

  // MARK: the body half of css-vars (2026-11-23)

  static let plainBlock = """
    :root {
      --a: 1px;
    }

    /* kept */
    :root[saved-theme='dark']{
      --a: 2px;
    }
    .other { color: red; }
      :root:not([saved-theme=dark]) {
      --l: green;
    }
    """

  @Test func theBodyHalfIsWrittenAndRead() {
    let rendered = VariableOverrides.render([
      VariableOverride(key: "a", light: "1px", dark: "2px"),
      VariableOverride(key: "l", light: "green", lightOnly: true)
    ])
    #expect(rendered == """
      :root,
      :root body {
        --a: 1px;
      }

      :root[saved-theme="dark"],
      :root[saved-theme="dark"] body {
        --a: 2px;
      }

      :root:not([saved-theme="dark"]),
      :root:not([saved-theme="dark"]) body {
        --l: green;
      }
      """)
    // Both forms read the same, a list written by hand too.
    let expected = [VariableOverride(key: "a", light: "1px", dark: "2px"), VariableOverride(key: "l", light: "green", lightOnly: true)]
    #expect(VariableOverrides.parse(rendered) == expected)
    #expect(VariableOverrides.parse(Self.plainBlock) == expected)
    #expect(VariableOverrides.parse(":root , :root  body{--a:1px;}\n:root[saved-theme=dark],:root[saved-theme=dark]\nbody{--a:2px;}") ==
            [VariableOverride(key: "a", light: "1px", dark: "2px")])
    // A rule for body alone is not one of the block's.
    #expect(VariableOverrides.parse(":root body { --a: 1px; }") == [])
  }

  @Test func plainRulesGetTheirBodyHalf() {
    let upgraded = VariableOverrides.upgradeSelectors(Self.plainBlock)
    #expect(upgraded == """
      :root,
      :root body {
        --a: 1px;
      }

      /* kept */
      :root[saved-theme='dark'],
      :root[saved-theme='dark'] body {
        --a: 2px;
      }
      .other { color: red; }
        :root:not([saved-theme=dark]),
        :root:not([saved-theme=dark]) body {
        --l: green;
      }
      """)
    #expect(VariableOverrides.hasPlainRules(Self.plainBlock))
    #expect(!VariableOverrides.hasPlainRules(upgraded))
    #expect(VariableOverrides.upgradeSelectors(upgraded) == upgraded)
    #expect(VariableOverrides.parse(upgraded) == VariableOverrides.parse(Self.plainBlock))
  }

  /// Before every build: a block in 1.3's form, in either file, gets its body half; said once.
  @Test func theBuildDoorUpgradesTheVariables() async throws {
    let project = "\(scratch.path)/vars"
    let styles = StyleSheets.stylesDirectory(project)
    try Posix.mkdirs(styles)
    let (start, end) = ManagedBlocks.markers("css-vars")
    let custom = "@use \"./quartzcontrol\";\n:root { --mine: 1; }\n"
    try Posix.write(StyleSheets.customScss(project), Data(custom.utf8))
    try Posix.write(StyleSheets.managedScss(project), Data("// head\n\(start)\n\(Self.plainBlock)\n\(end)\n".utf8))
    func run() async -> [String] {
      let said = Mutex<[String]>([])
      for step in BuildService.preparation { await step(project) { stream, text in said.withLock { $0.append("\(stream) \(text)") } } }
      return said.withLock { $0 }
    }
    #expect(await run() == ["stdout \(L10n.t("main.variableSelectorsMigrated"))\n"])
    let managed = String(decoding: try Posix.read(StyleSheets.managedScss(project)), as: UTF8.self)
    #expect(managed == "// head\n\(start)\n\(VariableOverrides.upgradeSelectors(Self.plainBlock))\n\(end)\n")
    // The user's own `:root` outside the block stays as it is.
    #expect(String(decoding: try Posix.read(StyleSheets.customScss(project)), as: UTF8.self) == custom)
    #expect(await run() == [])
  }

  /// Against the new form a plain `:root` of the user's reaches `html` only; a rule with the body
  /// half at the same specificity comes later and wins. Against 1.3's form, as before.
  @Test func collisionsKnowTheBodyHalf() {
    let body = VariableOverrides.render([
      VariableOverride(key: "a", light: "1"), VariableOverride(key: "d", light: "1", dark: "2"), VariableOverride(key: "l", light: "1", lightOnly: true)
    ])
    let (start, end) = ManagedBlocks.markers("css-vars")
    func hits(_ custom: String, block: String = body) -> [String] {
      VariableOverrides.collisions(StyleSheets.Sources(custom: custom, managed: "\(start)\n\(block)\n\(end)\n", managedExists: true))
    }
    #expect(hits(":root { --a: 9; --d: 9; --l: 9; }") == [])
    #expect(hits(":root,\n:root body { --a: 9; --l: 9; }") == ["a"])
    #expect(hits(":root[saved-theme='dark'] body { --d: 9; }\n:root:not([saved-theme=\"dark\"]) body { --l: 9; }") == ["d", "l"])
    #expect(hits(":root { --a: 9; }", block: ":root {\n  --a: 1;\n}") == ["a"])
  }

  // MARK: steps

  @Test(arguments: stepCases)
  func stepsAsQuartzControl(_ file: String) async throws {
    let golden = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps/\(file).json")))
    let project = "\(scratch.path)/\(file)"
    let styles = StyleSheets.stylesDirectory(project)
    try Posix.mkdirs(styles)
    let tree = golden["tree"]?.objectValue ?? JSONObject()
    for path in tree.keys {
      let url = "\(styles)/\(path)"
      try Posix.mkdirs(NodePath.dirname(url))
      try Posix.write(url, Data(tree[path]!.stringValue!.utf8))
    }
    var before = Self.files(styles).mapValues(Self.cssVarsAsQuartzControl)
    for step in golden["steps"]?.arrayValue ?? [] {
      let call = step["call"]!.stringValue!
      let args = step["args"]?.arrayValue ?? []
      var result: JSONValue
      do {
        result = try await Self.run(call, args, project)
      } catch {
        result = .object(JSONObject([("threw", .string(String(describing: error)))]))
      }
      #expect(Self.mask(result, scratch.path) == Self.deviation(file, call, args) ?? step["result"], "\(file): \(call)")
      let after = Self.files(styles).mapValues(Self.cssVarsAsQuartzControl)
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

  /// Where QuartzHub answers differently from QuartzControl on purpose. gui-test-moved: the user's
  /// `:root { --new-one: green; }` reaches `html` only once the block has its `body` half, and the
  /// page's value is what the site shows below it, so it is no collision (`VariableOverrides.collisions`).
  static func deviation(_ file: String, _ call: String, _ args: [JSONValue]) -> JSONValue? {
    file == "gui-test-moved" && call == "variableCollisions" ? .array([]) : nil
  }

  static func run(_ call: String, _ args: [JSONValue], _ project: String) async throws -> JSONValue {
    switch call {
    case "getVariableOverrides": return .array(try StyleSheets.variableOverrides(project: project).map(\.json))
    case "variableCollisions": return .array(try StyleSheets.variableCollisions(project: project).map { .string($0) })
    case "currentOrder": return .array(try StyleSheets.currentOrder(project: project).map { .string($0) })
    case "loadedStylesheetsLastFirst": return .array(try StyleSheets.loadedStylesheetsLastFirst(project: project).map { .string($0) })
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
      // The golden asks without a snapshot (a project just created); with one is asked below.
      #expect(args[0]["snapshot"] == .bool(false))
      let migration = try await StyleSheets.migrate(project: project, snapshot: nil)
      return .object(JSONObject([("moved", .bool(migration.moved)), ("snapshotId", migration.snapshotId.map { .string($0) } ?? .null)]))
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
    case .string(let text): return .string(text.replacingOccurrences(of: root, with: "@P@", options: .literal))
    case .array(let items): return .array(items.map { mask($0, root) })
    default: return value
    }
  }

  static func files(_ root: String) -> [String: String] {
    var result: [String: String] = [:]
    guard let walker = FileManager.default.enumerator(atPath: root) else { return [:] }
    while let relative = walker.nextObject() as? String {
      var isDirectory: ObjCBool = false
      let full = "\(root)/\(relative)"
      guard FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
      result[relative] = (try? Posix.read(full)).map { String(decoding: $0, as: UTF8.self) }
    }
    return result
  }

  /// From the Styles page the move takes a snapshot first, before the file is written, and answers
  /// its id; one that fails leaves the project as it was. A moved project takes none.
  @Test func theMoveWithASnapshot() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let project = "\(scratch.path)/p"
    let custom = StyleSheets.customScss(project)
    try Posix.mkdirs(NodePath.dirname(custom))
    try Posix.write(custom, Data("@use \"./base.scss\";\n".utf8))
    let managed = StyleSheets.managedScss(project)

    struct NoWayBack: Error {}
    await #expect(throws: NoWayBack.self) { _ = try await StyleSheets.migrate(project: project, snapshot: { _, _ in throw NoWayBack() }) }
    #expect(!FileManager.default.fileExists(atPath: managed))

    let calls = SnapshotCalls()
    let take = calls.take { _ in #expect(!FileManager.default.fileExists(atPath: managed), "the snapshot comes first") }
    let first = try await StyleSheets.migrate(project: project, snapshot: StyleFiles.snapshot(take))
    #expect(first == StyleSheets.Migration(moved: true, snapshotId: "snap-styleMigration"))
    #expect(FileManager.default.fileExists(atPath: managed))
    let second = try await StyleSheets.migrate(project: project, snapshot: StyleFiles.snapshot(take))
    #expect(second == StyleSheets.Migration(moved: false, snapshotId: nil))
    #expect(calls.all == [["styleMigration", ""]])
  }
}
