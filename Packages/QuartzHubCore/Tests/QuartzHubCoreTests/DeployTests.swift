import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// QuartzControl's mainT stand-in answered `{"key":…,"args":{…}}`; this puts the catalog's text in
/// its place (arguments first, they can hold such a text themselves), so an expected output reads
/// as QuartzHub's.
enum GoldenText {
  static func localize(_ text: String) -> String {
    let scalars = Array(text.unicodeScalars)
    var out = String.UnicodeScalarView()
    var i = 0
    let opener = Array(#"{"key":""#.unicodeScalars)
    while i < scalars.count {
      if scalars[i] == "{", i + opener.count <= scalars.count, Array(scalars[i..<(i + opener.count)]) == opener,
         let end = objectEnd(scalars, from: i),
         let value = try? JSJSON.parse(Data(String(String.UnicodeScalarView(scalars[i...end])).utf8)),
         let key = value["key"]?.stringValue, let args = value["args"]?.objectValue {
        var strings: [String: String] = [:]
        for name in args.keys { strings[name] = localize(JS.string(args[name])) }
        out.append(contentsOf: L10n.t("main.\(key)", strings).unicodeScalars)
        i = end + 1
      } else {
        out.append(scalars[i])
        i += 1
      }
    }
    return String(out)
  }

  /// `localize` on every string in a value.
  static func localize(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string(let text): return .string(localize(text))
    case .array(let items): return .array(items.map(localize))
    case .object(let object):
      var copy = JSONObject()
      for key in object.keys { copy[key] = localize(object[key]!) }
      return .object(copy)
    default: return value
    }
  }

  /// The closing brace of the JSON object starting at `from`, strings respected.
  static func objectEnd(_ s: [Unicode.Scalar], from: Int) -> Int? {
    var depth = 0, inString = false, escaped = false
    for j in from..<s.count {
      let c = s[j]
      if inString {
        if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        continue
      }
      if c == "\"" { inString = true } else if c == "{" { depth += 1 } else if c == "}" {
        depth -= 1
        if depth == 0 { return j }
      }
    }
    return nil
  }
}

/// Against QuartzControl's own deploy/index.ts with its folder adapter, staging and relayGuard
/// (`scripts/deploy-golden.mjs`): 61 calls through the dispatcher, each with its answer, the
/// progress events and the whole work folder afterwards (every folder's mode, every file's mode
/// and text). QuartzControl threw where a run had no target or no adapter; QuartzHub answers a
/// failed run with the same sentence.
@Suite struct DeployTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/deploy/steps.json")))

  static func tree(_ root: String) -> [String: String] {
    var found: [String: String] = [:]
    func walk(_ dir: String, _ rel: String) {
      for entry in Posix.entries(dir) ?? [] {
        let full = "\(dir)/\(entry.name)", r = rel.isEmpty ? entry.name : "\(rel)/\(entry.name)"
        if r == "Gärten-Ü/.git" { continue }
        var info = stat()
        lstat(full, &info)
        let mode = String(info.st_mode & 0o7777, radix: 8)
        if info.st_mode & S_IFMT == S_IFDIR {
          found["\(r)/"] = mode
          if info.st_mode & 0o400 != 0 { walk(full, r) }
        } else {
          let text = String(decoding: (try? Posix.read(full)) ?? Data(), as: UTF8.self)
          found[r] = "\(mode) \(text.replacingOccurrences(of: root, with: "@W@", options: .literal))"
        }
      }
    }
    walk(root, "")
    return found
  }

  static func manifestEntries(_ text: String) -> [[UInt8]: JSONValue]? {
    let body = String(text.drop { $0 != " " }.dropFirst())
    guard let object = (try? JSJSON.parse(Data(body.utf8)))?.objectValue else { return nil }
    return Dictionary(uniqueKeysWithValues: object.keys.map { (Array($0.utf8), object[$0]!) })
  }

  final class Events: Sendable {
    let items = Mutex<[JSONValue]>([])
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 61)
    let root = TestFolder.make("qh-deploy")
    let profile = TestFolder.make("qh-deploy-profile")
    defer {
      _ = chmod("\(root)/Ziel3/sub", 0o755)
      try? FileManager.default.removeItem(atPath: root)
      try? FileManager.default.removeItem(atPath: profile)
    }
    let W = { (text: String) in text.replacingOccurrences(of: "@W@", with: root, options: .literal) }
    let project = "\(root)/Gärten-Ü"
    try Posix.mkdirs("\(project)/.git")
    let ids = Mutex(0)
    let targets = PublishTargets(project: project, makeID: { "00000000-0000-4000-8000-" + String(format: "%012d", ids.withLock { $0 += 1; return $0 }) })
    let events = Events()
    let deploy = Deploy(project: project, connections: Connections(profile: ProfileDirectory(profile), secrets: MemorySecrets()),
                        adapters: ["folder": FolderAdapter()]) { target, processed, total, file in
      events.items.withLock {
        $0.append(.object(JSONObject([("targetId", .string(target)), ("processed", .number(Double(processed))), ("total", .number(Double(total))),
                                      ("currentFile", file.map(JSONValue.string) ?? .null)])))
      }
    }

    for step in steps {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! {
        if let write = action["write"]?.arrayValue {
          let path = W(write[0].stringValue!)
          try Posix.mkdirs(NodePath.dirname(path))
          try Posix.write(path, Data(write[1].stringValue!.utf8))
        }
        if let dir = action["mkdir"]?.stringValue { try Posix.mkdirs(W(dir)) }
        if let rm = action["rm"]?.stringValue { try? FileManager.default.removeItem(atPath: W(rm)) }
        if let change = action["chmod"]?.arrayValue { _ = chmod(W(change[0].stringValue!), mode_t(change[1].stringValue!, radix: 8)!) }
        if let times = action["utimes"]?.arrayValue {
          let seconds = Int(times[1].numberValue!)
          var spec = [timespec(tv_sec: seconds, tv_nsec: 0), timespec(tv_sec: seconds, tv_nsec: 0)]
          _ = utimensat(AT_FDCWD, W(times[0].stringValue!), &spec, 0)
        }
      }
      events.items.withLock { $0 = [] }
      let args = step["args"]!.arrayValue!
      let text = { (i: Int) in args[i].stringValue.map(W) }
      let strings = { (i: Int) in args[i].arrayValue?.map { $0.stringValue! } }
      var actual: JSONValue = .null
      var failure: String?
      func result(_ r: DeployResult) -> JSONValue {
        .object(JSONObject([("success", .bool(r.success)), ("output", .string(r.output.replacingOccurrences(of: root, with: "@W@", options: .literal)))]))
      }
      switch step["op"]!.stringValue! {
      case "save":
        let input = try JSJSON.parse(Data(W(JSJSON.compact(args[0])).utf8))
        do {
          actual = try targets.save(PublishTargetsTests.input(input)).json
        } catch {
          failure = error.message
        }
      case "preview":
        do {
          actual = .array(try await deploy.preview(args[0].stringValue!, outputDir: text(1)).map(\.json))
        } catch {
          failure = error.message
        }
      case "run": actual = result(await deploy.run(args[0].stringValue!, outputDir: text(1), excluding: strings(2) ?? []))
      case "upload":
        actual = result(await deploy.directoryUpload(targetId: args[0].stringValue!, localDir: text(1)!, subdir: args[2].stringValue!,
                                                    manifestKey: args[3].stringValue!, remove: strings(4), ownGeneration: args[5].stringValue))
      default: Issue.record("unknown op")
      }
      if let failure { actual = .object(JSONObject([("error", .string(failure.replacingOccurrences(of: root, with: "@W@", options: .literal)))])) }

      var expected = step["result"]!
      if let error = expected["error"]?.stringValue {
        // A run QuartzControl threw out of is a failed run here.
        expected = step["op"] == .string("preview") ? .object(JSONObject([("error", .string(error))]))
          : .object(JSONObject([("success", .bool(false)), ("output", .string(error))]))
      } else {
        expected = expected["ok"]!
      }
      let want = JSJSON.compact(GoldenText.localize(expected))
      let got = JSJSON.compact(actual).replacingOccurrences(of: root, with: "@W@", options: .literal)
      #expect(got.utf8.elementsEqual(want.utf8), "\(name): \(got)\nvs \(want)")
      let gotEvents = events.items.withLock { $0 }
      #expect(JSJSON.compact(.array(gotEvents)).replacingOccurrences(of: root, with: "@W@", options: .literal) == JSJSON.compact(step["events"]!), "\(name): events \(JSJSON.compact(.array(gotEvents)))")

      let have = Self.tree(root)
      let wantTree = step["tree"]!.objectValue!
      let unexpected = Set(have.keys).subtracting(wantTree.keys).filter { !$0.hasPrefix("Gärten-Ü/.quartz-gui/staging") }
      let missing = Set(wantTree.keys).subtracting(have.keys).filter { !$0.hasPrefix("Gärten-Ü/.quartz-gui/staging") }
      #expect(unexpected.isEmpty && missing.isEmpty, "\(name): extra \(unexpected.sorted()), missing \(missing.sorted())")
      for key in wantTree.keys {
        guard let got = have[key] else { continue }
        let expectedEntry = GoldenText.localize(wantTree[key]!.stringValue!)
        if JSText.test(key, #"/deploy-manifest-[^/]*[0-9a-f]\.json\z"#) {
          #expect(Self.manifestEntries(got) == Self.manifestEntries(expectedEntry) && got.prefix(4) == expectedEntry.prefix(4), "\(name): \(key)\n\(got)")
        } else {
          #expect(Array(got.utf8) == Array(expectedEntry.utf8), "\(name): \(key)\n\(got)\nvs\n\(expectedEntry)")
        }
      }
    }
  }
}

extension Error {
  var message: String { PublishFailure.message(of: self) }
}

/// Targets the form never saw (review 2026-11-11, M2): `publish-targets.json` travels with the
/// project, so an entry written by hand or by another tool reaches the dispatcher as it is. An
/// empty rsync path became `user@host:/` with --delete.
@Suite struct DeployLocationTests {
  final class Recorder: DeployAdapter, @unchecked Sendable {
    let calls = Mutex<[String]>([])
    func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] {
      calls.withLock { $0.append("preview \(context.target.id)") }
      return []
    }
    func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
      calls.withLock { $0.append("run \(context.target.id)") }
      return DeployResult(success: true, output: "")
    }
  }

  @Test func aTargetFromTheFileIsCheckedBeforeAnAdapterSeesIt() async throws {
    let root = TestFolder.make("qh-deploy-location")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let project = "\(root)/Gärten-Ü"
    try Posix.mkdirs("\(project)/.quartz-gui")
    try Posix.mkdirs("\(project)/public")
    try Posix.write("\(project)/public/index.html", Data("<p>Start</p>\n".utf8))
    let targets = #"""
    [
      {"id":"leer","name":"Leer","destination":{"type":"sftp","transfer":"rsync","remotePath":"","deleteRemoved":true}},
      {"id":"blank","name":"Blank","destination":{"type":"ftp","remotePath":"  ","deleteRemoved":false}},
      {"id":"ohne","name":"Ohne","destination":{"type":"sftp","transfer":"sftp","deleteRemoved":true}},
      {"id":"hoch","name":"Hoch","destination":{"type":"sftp","transfer":"rsync","remotePath":"www/../..","deleteRemoved":false}},
      {"id":"wurzel","name":"Wurzel","destination":{"type":"sftp","transfer":"rsync","remotePath":"~/","deleteRemoved":true}},
      {"id":"relativ","name":"Relativ","destination":{"type":"folder","path":"site","deleteRemoved":true}},
      {"id":"zweig","name":"Zweig","destination":{"type":"git-branch","provider":"github","branch":"--upload-pack=touch pwned; false"}},
      {"id":"gut","name":"Gut","destination":{"type":"sftp","transfer":"rsync","remotePath":"httpdocs","deleteRemoved":true}},
      {"id":"ordner","name":"Ordner","destination":{"type":"folder","path":"/tmp/qh-nie","deleteRemoved":false}}
    ]
    """#
    try Posix.write("\(project)/.quartz-gui/publish-targets.json", Data(targets.utf8))
    let recorder = Recorder()
    let profile = TestFolder.make("qh-deploy-location-profile")
    defer { try? FileManager.default.removeItem(atPath: profile) }
    let deploy = Deploy(project: project, connections: Connections(profile: ProfileDirectory(profile), secrets: MemorySecrets()),
                        adapters: ["rsync": recorder, "sftp": recorder, "ftp": recorder, "folder": recorder, "git-branch": recorder])

    let refused = [
      "leer": L10n.t("main.deployEmptyPath"),
      "blank": L10n.t("main.deployEmptyPath"),
      "ohne": L10n.t("main.deployEmptyPath"),
      "hoch": L10n.t("main.deployTraversalPath", ["path": "www/../.."]),
      "wurzel": L10n.t("main.deployWholeRoot", ["path": "~/"]),
      "relativ": L10n.t("main.deployFolderPath", ["path": "site"]),
      "zweig": L10n.t("main.deployBadBranch", ["branch": "--upload-pack=touch pwned; false"]),
    ]
    for (id, message) in refused {
      await #expect(throws: PublishFailure(message), "\(id)") { try await deploy.preview(id) }
      let run = await deploy.run(id)
      #expect(!run.success && run.output == message, "\(id): \(run.output)")
    }
    #expect(recorder.calls.withLock { $0 } == [], "no adapter saw a refused target")

    // The counter-check: valid targets still reach their adapter.
    _ = try await deploy.preview("gut")
    _ = await deploy.run("ordner")
    #expect(recorder.calls.withLock { $0 } == ["preview gut", "run ordner"])
  }
}

/// Review 2026-11-11, N5: a run whose deletions the target refused said "Veröffentlichung
/// erfolgreich." while the files stayed live. The result now carries them.
@Suite struct DeployKeptTests {
  @Test func refusedDeletionsAreCarriedInTheResult() async throws {
    let root = TestFolder.make("qh-deploy-kept")
    let site = "\(root)/Ziel"
    defer {
      _ = chmod("\(site)/sub", 0o755)
      try? FileManager.default.removeItem(atPath: root)
    }
    let project = "\(root)/Gärten-Ü"
    try Posix.mkdirs("\(project)/.quartz-gui")
    try Posix.mkdirs("\(project)/public/sub")
    try Posix.write("\(project)/public/index.html", Data("a\n".utf8))
    try Posix.write("\(project)/public/sub/alt.html", Data("b\n".utf8))
    try Posix.write("\(project)/.quartz-gui/publish-targets.json", Data("""
      [{"id":"t","name":"T","destination":{"type":"folder","path":"\(site)","deleteRemoved":true}}]
      """.utf8))
    let profile = TestFolder.make("qh-deploy-kept-profile")
    defer { try? FileManager.default.removeItem(atPath: profile) }
    let deploy = Deploy(project: project, connections: Connections(profile: ProfileDirectory(profile), secrets: MemorySecrets()),
                        adapters: ["folder": FolderAdapter()])
    let first = await deploy.run("t")
    #expect(first.success && first.kept.isEmpty, "\(first.output)")

    // The page is gone from the build, and the target's folder will not let it go.
    try FileManager.default.removeItem(atPath: "\(project)/public/sub/alt.html")
    _ = chmod("\(site)/sub", 0o555)
    let second = await deploy.run("t")
    #expect(second.success && second.kept == ["sub/alt.html"], "\(second.output) \(second.kept)")
    #expect(FileManager.default.fileExists(atPath: "\(site)/sub/alt.html"))

    // The counter-check: allowed again, the deletion happens and nothing is kept.
    _ = chmod("\(site)/sub", 0o755)
    let third = await deploy.run("t")
    #expect(third.success && third.kept.isEmpty, "\(third.output)")
    #expect(!FileManager.default.fileExists(atPath: "\(site)/sub/alt.html"))
  }
}
