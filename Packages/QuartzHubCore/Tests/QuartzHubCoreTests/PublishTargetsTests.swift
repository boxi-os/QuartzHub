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
}

extension DeployManifests {
  func directoryForTests() throws { try directory.create() }
}
