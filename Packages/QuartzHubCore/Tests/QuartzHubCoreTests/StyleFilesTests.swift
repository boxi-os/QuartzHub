import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own styleService.ts and stylesheetConsolidation.ts:
/// `scripts/style-files-golden.mjs` took the template's 31 stylesheets of 1.0 out of QuartzControl's
/// git history and recorded the consolidation plan for 14 orders and five sequences of file calls.
@Suite struct StyleFilesTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/style-files")
  static var stepCases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.appendingPathComponent("steps").path)) ?? [])
      .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  static func legacy(_ name: String) throws -> String {
    try String(contentsOf: fixtures.appendingPathComponent("legacy/\(name).scss"), encoding: .utf8)
  }

  static func text(_ value: JSONValue) throws -> String {
    if let name = value["legacy"]?.stringValue { return try legacy(name) }
    return value.stringValue!
  }

  static func strings(_ list: [String]) -> JSONValue { .array(list.map { .string($0) }) }

  static func sha1(_ text: String) -> String { Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

  @Test func plansAsQuartzControl() throws {
    let pure = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("pure.json")))
    let plans = pure["plans"]?.arrayValue ?? []
    #expect(plans.count >= 14)
    for entry in plans {
      let name = entry["name"]!.stringValue!
      let order = (entry["order"]?.arrayValue ?? []).compactMap(\.stringValue)
      let onDisk = (entry["onDisk"]?.arrayValue ?? []).compactMap(\.stringValue)
      var files: [String: String] = [:]
      let given = entry["files"]?.objectValue ?? JSONObject()
      for key in given.keys { files[key] = try Self.text(given[key]!) }
      let plan = StylesheetConsolidation.plan(order, files, onDisk)
      let expected = entry["plan"]!
      let write = expected["write"]?.objectValue ?? JSONObject()
      #expect(plan.write.map(\.path) == write.keys, "\(name) write paths")
      for (path, content) in plan.write {
        if let text = write[path]?.stringValue {
          if content != text { Issue.record("\(name): \(path)\n\(firstDifference(content, text))") }
        } else {
          #expect(Self.sha1(content) == write[path]?["sha1"]?.stringValue && Double(content.utf16.count) == write[path]?["length"]?.numberValue, "\(name): \(path)")
        }
      }
      #expect(Self.strings(plan.remove) == expected["remove"], "\(name) remove")
      let rename = expected["rename"]?.objectValue ?? JSONObject()
      #expect(plan.rename.map(\.from) == rename.keys && plan.rename.map { JSONValue.string($0.to) } == rename.keys.map { rename[$0]! }, "\(name) rename")
      #expect(Self.strings(plan.order) == expected["order"], "\(name) order")
      let was = StylesheetConsolidation.wasConsolidated(files, order)
      #expect(.bool(was) == entry["was"] && .bool(StylesheetConsolidation.canConsolidate(order, consolidated: was)) == entry["can"], "\(name) was/can")
      #expect(.number(Double(StylesheetConsolidation.legacyCount(order, consolidated: was))) == entry["count"], "\(name) count")
      #expect(.bool(StylesheetConsolidation.isConsolidatedOrder(order)) == entry["consolidatedOrder"], "\(name) consolidated order")
    }
    for entry in pure["predicates"]?.arrayValue ?? [] {
      let path = entry["path"]!.stringValue!
      #expect(.bool(StylesheetConsolidation.isLegacyOnly(path)) == entry["legacyOnly"] && .bool(StylesheetConsolidation.isConsolidatedOnly(path)) == entry["consolidatedOnly"], "\(path)")
    }
    for entry in pure["markers"]?.arrayValue ?? [] {
      #expect(.string(StylesheetConsolidation.sectionMarker(entry["name"]!.stringValue!)) == entry["marker"])
    }
  }

  @Test(arguments: stepCases)
  func stepsAsQuartzControl(_ file: String) async throws {
    let golden = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps/\(file).json")))
    let project = scratch.url.appendingPathComponent(file)
    let styles = StyleSheets.stylesDirectory(project)
    try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
    let tree = golden["tree"]?.objectValue ?? JSONObject()
    for path in tree.keys {
      let full = path.hasPrefix("../") ? project.appendingPathComponent(String(path.dropFirst(3)))
        : path.hasPrefix("in/") ? project.appendingPathComponent(path) : styles.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: full.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(try Self.text(tree[path]!).utf8).write(to: full)
    }
    let snapshots = Mutex<[String]>([])
    let snapshot: StyleFiles.Snapshot = { _, kind in snapshots.withLock { $0.append(kind) }; return "snap-1" }
    var before = ManagedStylesTests.files(styles)
    for step in golden["steps"]?.arrayValue ?? [] {
      let call = step["call"]!.stringValue!
      var args = (step["args"]?.arrayValue ?? []).map { arg -> JSONValue in
        if case .string(let text) = arg { return .string(text.replacingOccurrences(of: "@IN@", with: project.appendingPathComponent("in").path)) }
        return arg
      }
      if args.first == .string("@ORDER+nav-darkmode") {
        let loaded = try StyleFiles.list(project: project).files.filter(\.imported).map(\.relativePath)
        args = [Self.strings(loaded + ["custom/nav-darkmode.scss"])]
      }
      snapshots.withLock { $0 = [] }
      var result: JSONValue
      do {
        result = try await Self.run(call, args, project, snapshot)
      } catch {
        result = .object(JSONObject([("threw", .string(String(describing: error)))]))
      }
      let expected = ManagedStylesTests.mask(Self.rendered(step["result"] ?? .null), "")
      #expect(Self.masked(result, project.path) == expected, "\(file): \(call)")
      #expect(Self.strings(snapshots.withLock { $0 }) == step["snapshots"], "\(file): \(call) snapshots")
      let after = ManagedStylesTests.files(styles)
      var changed: [String: String?] = [:]
      for path in Set(before.keys).union(after.keys) where before[path] != after[path] { changed[path] = .some(after[path]) }
      let expectedChanged = step["changed"]?.objectValue ?? JSONObject()
      #expect(Set(changed.keys) == Set(expectedChanged.keys), "\(file): \(call) changed files")
      for path in expectedChanged.keys where changed[path] != .some(expectedChanged[path]?.stringValue) {
        Issue.record("\(file): \(call) wrote \(path) differently\n\(firstDifference(changed[path].flatMap { $0 } ?? "<none>", expectedChanged[path]?.stringValue ?? "<removed>"))")
      }
      before = after
    }
  }

  static func rendered(_ value: JSONValue) -> JSONValue { FontServiceTests.rendered(value) }

  static func masked(_ value: JSONValue, _ project: String) -> JSONValue {
    switch value {
    case .string(let text): return .string(text.replacingOccurrences(of: project, with: "@P@"))
    case .array(let items): return .array(items.map { masked($0, project) })
    case .object(let object):
      var out = JSONObject()
      for key in object.keys { out[key] = masked(object[key]!, project) }
      return .object(out)
    default: return value
    }
  }

  static func fileJSON(_ file: StyleFiles.File) -> JSONValue {
    .object(JSONObject([("relativePath", .string(file.relativePath)), ("path", .string(file.path.path)), ("name", .string(file.name)), ("imported", .bool(file.imported))]))
  }

  static func run(_ call: String, _ args: [JSONValue], _ project: URL, _ snapshot: @escaping StyleFiles.Snapshot) async throws -> JSONValue {
    switch call {
    case "listStyleFiles":
      let set = try StyleFiles.list(project: project)
      let managed: JSONValue = set.main.managed.map { .object(JSONObject([("path", .string($0.path.path)), ("content", .string($0.content))])) } ?? .null
      let main = JSONValue.object(JSONObject([("path", .string(set.main.path.path)), ("content", .string(set.main.content)), ("managed", managed), ("moved", .bool(set.main.moved))]))
      return .object(JSONObject([("main", main), ("files", .array(set.files.map(fileJSON))), ("consolidated", .bool(set.consolidated))]))
    case "consolidateStylesheets":
      let r = try await StyleFiles.consolidate(project: project, snapshot: snapshot)
      return .object(JSONObject([("consolidated", .bool(r.consolidated)), ("snapshotId", r.snapshotId.map { .string($0) } ?? .null), ("written", strings(r.written)),
                                 ("merged", .number(Double(r.merged))),
                                 ("renamed", .array(r.renamed.map { .object(JSONObject([("from", .string($0.from)), ("to", .string($0.to))])) }))]))
    case "setImportOrder":
      try await StyleSheets.setImportOrder((args[0].arrayValue ?? []).compactMap(\.stringValue), project: project)
      return .null
    case "createStyleFile": return fileJSON(try await StyleFiles.create(args[0].stringValue!, project: project))
    case "renameStyleFile": return fileJSON(try await StyleFiles.rename(args[0].stringValue!, to: args[1].stringValue!, project: project))
    case "writeStyleFile":
      try await StyleFiles.write(args[0].stringValue!, args[1].stringValue!, project: project)
      return .null
    case "readStyleFile": return .string(try StyleFiles.read(args[0].stringValue!, project: project))
    case "deleteStyleFile":
      try await StyleFiles.delete(args[0].stringValue!, project: project)
      return .null
    case "importStyleFile":
      let r = try await StyleFiles.importFile(URL(fileURLWithPath: args[0].stringValue!), project: project)
      return .object(JSONObject([("importLine", .string(r.importLine)), ("relativePath", .string(r.relativePath))]))
    case "getStyleReferences":
      return .array(try StyleFiles.references(plugin: args[0].stringValue!, project: project).map {
        .object(JSONObject([("label", .string($0.label)), ("path", .string($0.path)), ("content", .string($0.content))]))
      })
    default:
      Issue.record("unknown call \(call)")
      return .null
    }
  }

  /// What QuartzControl's IPC schemas refused, the service refuses: a path out of the two
  /// directories, a dot file, a name with a separator.
  @Test func theDoorChecksTheNames() async throws {
    let project = scratch.url.appendingPathComponent("door")
    try FileManager.default.createDirectory(at: StyleSheets.stylesDirectory(project), withIntermediateDirectories: true)
    for path in ["../custom.scss", "custom/../../x.scss", "base.scss", "custom/.hidden.scss", "custom/a.txt", "other/a.scss", "custom/sub/a.scss"] {
      await #expect(throws: StyleFiles.InvalidName.self, "\(path)") { try await StyleFiles.write(path, "x", project: project) }
      await #expect(throws: StyleFiles.InvalidName.self, "\(path)") { try await StyleFiles.delete(path, project: project) }
    }
    for name in ["", "../x", "a/b", ".hidden", "-x", String(repeating: "a", count: 97)] {
      await #expect(throws: StyleFiles.InvalidName.self, "\(name)") { _ = try await StyleFiles.create(name, project: project) }
    }
    #expect(try StyleFiles.read("_quartzcontrol.scss", project: project) == "")
    #expect(throws: StyleFiles.InvalidName.self) { _ = try StyleFiles.references(plugin: "../x", project: project) }
  }

  /// A snapshot that fails leaves no way back, and the run stops before anything moves.
  @Test func noConsolidationWithoutASnapshot() async throws {
    let golden = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps/consolidate-the-31.json")))
    let project = scratch.url.appendingPathComponent("nosnap")
    let styles = StyleSheets.stylesDirectory(project)
    let tree = golden["tree"]?.objectValue ?? JSONObject()
    for path in tree.keys {
      let full = styles.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: full.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(try Self.text(tree[path]!).utf8).write(to: full)
    }
    let before = ManagedStylesTests.files(styles)
    struct NoWayBack: Error {}
    await #expect(throws: NoWayBack.self) { _ = try await StyleFiles.consolidate(project: project, snapshot: { _, _ in throw NoWayBack() }) }
    #expect(ManagedStylesTests.files(styles) == before)
  }
}
