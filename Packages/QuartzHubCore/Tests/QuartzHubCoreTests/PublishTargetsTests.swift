import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own publishTargetsService.ts and deploy/manifest.ts
/// (`scripts/targets-golden.mjs`): 43 calls in a project folder with umlauts, each with its answer
/// and every file under .quartz-gui/ afterwards; partitionDiff over 8 cases; the input rules
/// against the zod schema over 44 inputs.
@Suite struct PublishTargetsTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/targets/steps.json")))

  static func input(_ value: JSONValue) -> SavePublishTargetInput {
    SavePublishTargetInput(id: value["id"]?.stringValue, name: value["name"]!.stringValue!, connectionId: value["connectionId"]?.stringValue,
                           destination: value["destination"]?.objectValue ?? JSONObject(),
                           excludes: value["excludes"]?.arrayValue?.map { $0.stringValue! },
                           withDocuments: value["withDocuments"]?.arrayValue?.map { $0.stringValue! })
  }

  /// Every file under .quartz-gui/ and the .gitignore, as the golden lists them.
  static func files(_ project: String) -> [String: String] {
    var found: [String: String] = [:]
    func walk(_ dir: String, _ rel: String) {
      for entry in Posix.entries(dir) ?? [] {
        let path = "\(dir)/\(entry.name)", name = "\(rel)/\(entry.name)"
        if entry.kind == .directory { walk(path, name); continue }
        found[JSText.replaceAll(name, #"corrupt-[^/]*\z"#, with: "corrupt-*")] = String(decoding: (try? Posix.read(path)) ?? Data(), as: UTF8.self)
      }
    }
    walk("\(project)/.quartz-gui", ".quartz-gui")
    if let ignore = try? Posix.read("\(project)/.gitignore") { found[".gitignore"] = String(decoding: ignore, as: UTF8.self) }
    return found
  }

  /// A manifest by its entries, whatever their order: QuartzControl wrote them as its hashes finished.
  static func entries(_ text: String) -> [[UInt8]: JSONValue]? {
    guard let object = (try? JSJSON.parse(Data(text.utf8)))?.objectValue else { return nil }
    return Dictionary(uniqueKeysWithValues: object.keys.map { (Array($0.utf8), object[$0]!) })
  }

  @Test func replaysQuartzControlsSteps() throws {
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 43)
    let root = TestFolder.make("qh-targets")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let project = "\(root)/Gärten-Ü"
    try Posix.mkdirs("\(project)/.git")
    let ids = Mutex(0)
    let now = Mutex(Date(timeIntervalSince1970: 1_793_008_800))
    let targets = PublishTargets(project: project, makeID: { "00000000-0000-4000-8000-" + String(format: "%012d", ids.withLock { $0 += 1; return $0 }) })
    let manifests = DeployManifests(project: project, now: { now.withLock { $0 } })
    var manifestsCleared = false

    for step in steps {
      let name = step["name"]!.stringValue!
      if step["op"]!.stringValue!.hasPrefix("manifest:") && !manifestsCleared {
        try? FileManager.default.removeItem(atPath: "\(project)/.quartz-gui")
        manifestsCleared = true
      }
      for action in step["setup"]!.arrayValue! {
        if let write = action["write"]?.arrayValue {
          let path = "\(project)/\(write[0].stringValue!)"
          try Posix.mkdirs(NodePath.dirname(path))
          try Posix.write(path, Data(write[1].stringValue!.utf8))
        }
        if let rm = action["rm"]?.stringValue { try? FileManager.default.removeItem(atPath: "\(project)/\(rm)") }
        if let clock = action["clock"]?.stringValue {
          now.withLock { $0 = ISO8601DateFormatter().date(from: clock.replacingOccurrences(of: ".000Z", with: "Z", options: .literal))! }
        }
      }
      let args = step["args"]!.arrayValue!
      let actual: JSONValue
      do {
        switch step["op"]!.stringValue! {
        case "targets:list": actual = .array(targets.list().map(\.json))
        case "targets:get": actual = targets.get(args[0].stringValue!)?.json ?? .null
        case "targets:save": actual = try targets.save(Self.input(args[0])).json
        case "targets:delete":
          try targets.delete(args[0].stringValue!)
          actual = .null
        case "targets:using": actual = .array(targets.using(connection: args[0].stringValue!).map(\.json))
        case "manifest:read": actual = manifests.read(args[0].stringValue!).json
        case "manifest:diff": actual = .array(try manifests.diff(args[0].stringValue!, buildDir: "\(project)/\(args[1].stringValue!)").map(\.json))
        case "manifest:commit":
          try manifests.commit(args[0].stringValue!, buildDir: "\(project)/\(args[1].stringValue!)",
                               excluding: args[2].arrayValue!.map { $0.stringValue! })
          actual = .null
        case "manifest:modesSettled": actual = .bool(manifests.modesSettled(args[0].stringValue!))
        case "manifest:settleModes":
          try manifests.settleModes(args[0].stringValue!)
          actual = .null
        case "manifest:reanchor":
          try manifests.reanchorTilde(args[0].stringValue!)
          actual = .null
        case "manifest:forget":
          manifests.forget(args[0].stringValue!)
          actual = .null
        default:
          Issue.record("unknown op"); continue
        }
        let expected = step["result"]!["ok"]
        #expect(expected != nil, "\(name): QuartzControl failed with \(step["result"]!)")
        #expect(JSJSON.compact(actual).utf8.elementsEqual(JSJSON.compact(expected ?? .null).utf8),
                "\(name): \(JSJSON.compact(actual)) vs \(JSJSON.compact(expected ?? .null))")
      } catch {
        let message = PublishFailure.message(of: error).replacingOccurrences(of: project, with: "@P@", options: .literal)
        #expect(step["result"]!["error"] == .string(message), "\(name): \(message) vs \(step["result"]!)")
      }

      let have = Self.files(project)
      let want = step["files"]!.objectValue!
      #expect(Set(have.keys) == Set(want.keys), "\(name): files \(have.keys.sorted()) vs \(want.keys.sorted())")
      for key in want.keys {
        // The golden's mainT answered key and arguments; the comment line is QuartzHub's text.
        let expected = want[key]!.stringValue!.replacingOccurrences(of: #"{"key":"gitignoreComment","args":{}}"#,
                                                                  with: L10n.t("main.gitignoreComment"), options: .literal)
        guard let text = have[key] else { continue }
        if JSText.test(key, #"deploy-manifest-[^/.]*\.json\z"#) && !key.hasSuffix("deploy-manifest.json") {
          #expect(Self.entries(text) == Self.entries(expected) && (Self.entries(expected) != nil || text == expected), "\(name): \(key)\n\(text)")
        } else {
          #expect(Array(text.utf8) == Array(expected.utf8), "\(name): \(key)\n\(text)\nvs\n\(expected)")
        }
      }
    }
  }

  @Test func partitionsAsQuartzControl() {
    let cases = Self.golden["partitions"]!.arrayValue!
    #expect(cases.count == 8)
    for item in cases {
      let args = item["args"]!.arrayValue!
      let diff = args[0].arrayValue!.map { DeployDiffEntry(path: $0["path"]!.stringValue!, status: .init(rawValue: $0["status"]!.stringValue!)!) }
      let p = DeployManifests.partition(diff, excluding: args[1].arrayValue!.map { $0.stringValue! }, deleteRemoved: args[2].boolValue!)
      let strings = { (items: [String]) in JSONValue.array(items.map(JSONValue.string)) }
      let actual = JSONValue.object(JSONObject([("toUpload", strings(p.toUpload)), ("toDelete", strings(p.toDelete)), ("manifestExcludes", strings(p.manifestExcludes))]))
      #expect(JSJSON.compact(actual) == JSJSON.compact(item["result"]!), "\(JSJSON.compact(.array(args)))")
    }
  }

  @Test func checksInputsAsTheSchema() {
    let rules = Self.golden["rules"]!.arrayValue!
    #expect(rules.count == 44)
    for rule in rules {
      let input = Self.input(rule["input"]!)
      #expect((input.problem == nil) == (rule["valid"] == .bool(true)), "\(JSJSON.compact(rule["input"]!)): \(input.problem ?? "valid")")
    }
  }

  /// A key in the manifest is a path by its bytes: "ä" written two ways is two files, as in Node.
  @Test func aManifestComparesPathsByBytes() throws {
    let root = TestFolder.make("qh-manifest-bytes")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let build = "\(root)/public"
    try Posix.mkdirs(build)
    try Posix.write("\(build)/a\u{308}.html", Data("x".utf8))
    let manifests = DeployManifests(project: root)
    try manifests.directoryForTests()
    try Posix.write("\(root)/.quartz-gui/deploy-manifest-t.json", Data("{\"\u{E4}.html\": \"\(try DeployManifests.hash("\(build)/a\u{308}.html"))\"}".utf8))
    let diff = try manifests.diff("t", buildDir: build)
    #expect(diff.map(\.status) == [.added, .removed] || diff.map(\.status) == [.removed, .added], "\(diff)")
  }

  /// A record is replaced, never rewritten in place: a crash halfway leaves the old manifest, not
  /// half of the new one (review 2026-11-11, nebenbei 1). A second hard link shows the difference,
  /// since an in-place write changes it too.
  @Test func aManifestIsReplacedNotRewritten() throws {
    let root = TestFolder.make("qh-manifest-atomic")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let manifests = DeployManifests(project: root)
    try manifests.write("t", DeployManifest(.object(JSONObject([("a.html", .string("old"))]))))
    let path = "\(root)/.quartz-gui/deploy-manifest-t.json", held = "\(root)/held.json"
    #expect(link(path, held) == 0)
    try manifests.write("t", DeployManifest(.object(JSONObject([("a.html", .string("new"))]))))
    #expect(manifests.read("t").paths == ["a.html"])
    #expect(String(decoding: try Posix.read(held), as: UTF8.self).contains("old"))
    #expect(String(decoding: try Posix.read(path), as: UTF8.self).contains("new"))
    #expect((Posix.entries("\(root)/.quartz-gui") ?? []).allSatisfy { !$0.name.contains(".tmp-") })
  }
}

/// The staging for documents sees the build as the manifest's walk does (review 2026-11-11,
/// nebenbei 9): a link to a file is that file, a link to a folder fails in both.
@Suite struct DeployStagingTests {
  @Test func aLinkInTheBuildIsTheSameWithAndWithoutDocuments() throws {
    let root = TestFolder.make("qh-staging-links")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let build = "\(root)/public", staged = "\(root)/staged"
    try Posix.mkdirs("\(build)/sub")
    try Posix.mkdirs("\(root)/aside")
    try Posix.write("\(build)/index.html", Data("i".utf8))
    try Posix.write("\(build)/sub/b.html", Data("b".utf8))
    try Posix.write("\(root)/aside/über.html", Data("ü".utf8))
    #expect(symlink("../aside/über.html", "\(build)/linked.html") == 0)
    try DeployStaging.mirror(build, staged)
    let walked = try DeployManifests.walk(build)
    #expect(try DeployManifests.walk(staged) == walked && walked.contains("linked.html"))
    for path in walked { #expect(try DeployManifests.hash("\(staged)/\(path)") == DeployManifests.hash("\(build)/\(path)")) }
    #expect(Posix.kind("\(staged)/linked.html") == .file)

    #expect(symlink("../aside", "\(build)/folder") == 0)
    #expect(throws: (any Error).self) { for path in try DeployManifests.walk(build) { _ = try DeployManifests.hash("\(build)/\(path)") } }
    try? FileManager.default.removeItem(atPath: staged)
    #expect(throws: (any Error).self) { try DeployStaging.mirror(build, staged) }
  }
}

extension DeployManifests {
  func directoryForTests() throws { try directory.create() }
}
