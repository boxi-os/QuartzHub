import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own templatePackage/ with the real services underneath:
/// `scripts/templates-golden.mjs` built twelve projects (recorded in `initial.json`, binary files
/// once in `blobs.json`), exported the source, and planned and imported four packages into the
/// others with both strategies: the source's export, qc-basic.qtpl, a folder of the format before
/// 1 and a hostile one. Each step's answer, the files it changed, the commands and the snapshots
/// are compared. Here the packages imported are QuartzHub's own exports, so the round trip counts.
@Suite(.serialized, .enabled(if: HelperRuntime.available && FileManager.default.fileExists(atPath: "\(HelperRuntime.runtime.helpers)/locale-edit.cjs"),
                             "Runtime/ oder Helpers/dist fehlt: scripts/fetch-runtime.sh, scripts/build-helpers.sh"))
struct TemplatePackageTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/templates")
  static let basic = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../Resources/templates/qc-basic.qtpl").standardizedFileURL

  final class Recorder: Sendable {
    struct State {
      var commands: [[String]] = []
      var snapshots: [[JSONValue]] = []
    }
    let state = Mutex(State())
    func command(_ words: [String]) { state.withLock { $0.commands.append(words) } }
  }

  static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

  /// The golden's `describeFile` and `brief` in one: short UTF-8 text as text, else sha and length.
  static func brief(_ data: Data, mask: (String) -> String) -> JSONValue {
    if let text = String(data: data, encoding: .utf8), !text.contains("\0"), data.count <= 200_000 {
      let masked = mask(text)
      if masked.utf16.count > 4000 { return .object(JSONObject([("sha256", .string(sha(Data(masked.utf8)))), ("length", .number(Double(masked.utf8.count)))])) }
      return .object(JSONObject([("text", .string(masked))]))
    }
    return .object(JSONObject([("sha256", .string(sha(data))), ("length", .number(Double(data.count)))]))
  }

  static func tree(_ root: URL, mask: (String) -> String) -> [String: JSONValue] {
    var out: [String: JSONValue] = [:]
    func walk(_ dir: URL, _ prefix: String) {
      for entry in LayoutFrames.directoryEntriesWithKind(dir.path) where entry.name != ".git" {
        let full = dir.appendingPathComponent(entry.name)
        let rel = prefix + entry.name
        switch entry.kind {
        case .link: out[rel] = .object(JSONObject([("link", .string(mask((try? FileManager.default.destinationOfSymbolicLink(atPath: full.path)) ?? "")))]))
        case .directory:
          out[rel] = .object(JSONObject([("dir", .bool(true))]))
          walk(full, rel + "/")
        default: out[rel] = brief(FileManager.default.contents(atPath: full.path) ?? Data(), mask: mask)
        }
      }
    }
    walk(root, "")
    return out
  }

  static func build(_ root: URL, _ files: JSONObject, blobs: JSONObject, work: String) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for path in files.keys {
      let spec = files[path]!
      let url = root.appendingPathComponent(path)
      if spec["dir"] != nil {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      } else if let link = spec["link"]?.stringValue {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: link.replacingOccurrences(of: "@W@", with: work, options: .literal))
      } else {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = if let text = spec["text"]?.stringValue { Data(text.replacingOccurrences(of: "@W@", with: work, options: .literal).utf8) }
          else { Data(base64Encoded: blobs[spec["blob"]!.stringValue!]!.stringValue!)! }
        try data.write(to: url)
      }
    }
  }

  /// Every string with QuartzControl's `mainT` stand-ins as the sentences they stand for.
  static func rendered(_ value: JSONValue) -> JSONValue { FontServiceTests.rendered(value) }

  static func masked(_ value: JSONValue, _ work: String) -> JSONValue {
    switch value {
    case .string(let text): .string(text.replacingOccurrences(of: work, with: "@W@", options: .literal))
    case .array(let items): .array(items.map { masked($0, work) })
    case .object(let object): .object(JSONObject(object.keys.map { ($0, masked(object[$0]!, work)) }))
    default: value
    }
  }

  static func unpacked(_ file: URL, mask: (String) -> String) throws -> JSONValue {
    let files = try ZipArchive.read(contentsOf: file)
    var out = JSONObject()
    for name in files.names {
      let data = files[name]!
      if JSText.endsWith(name, ".json") {
        var value = try JSJSON.parse(data)
        if name == "manifest.json", case .object(var manifest) = value {
          manifest["createdAt"] = .string("@DATE@")
          manifest["createdBy"] = .string("@APP@")
          value = .object(manifest)
        }
        out[name] = name == "manifest.json" ? .object(JSONObject([("json", value)])) : .object(JSONObject([("json", value), ("raw", brief(data, mask: mask))]))
      } else {
        out[name] = brief(data, mask: mask)
      }
    }
    return .object(JSONObject([("names", .array(files.names.map(JSONValue.string))), ("files", .object(out))]))
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let scratch = try HostPathTests.Scratch()
    // The golden's work folder was a realpath; links and config entries carry it.
    let work = Self.realpath(scratch.url.path)
    let mask = { (text: String) in text.replacingOccurrences(of: work, with: "@W@", options: .literal) }
    let initial = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("initial.json"))).objectValue!
    let blobs = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("blobs.json"))).objectValue!
    var roots: [String: URL] = [:]
    for name in initial.keys {
      let root = URL(fileURLWithPath: work).appendingPathComponent(name)
      try Self.build(root, initial[name]!.objectValue!, blobs: blobs, work: work)
      roots[name] = root
    }

    let recorder = Recorder()
    let environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    let read: LayoutFrames.ReadConfig = { try await ConfigFile.read(project: $0, runtime: .repository) }
    let plugins = LayoutFrames.Plugins(add: { source, _, _ in
      recorder.command(["quartz", "plugin", "add", source])
      return PluginCommands.Result(success: true, output: "")
    }, remove: { name, _ in
      recorder.command(["quartz", "plugin", "remove", name])
      return PluginCommands.Result(success: true, output: "")
    })
    let templates = TemplatePackage(
      runtime: .repository, locales: LocaleFiles(environment: environment), frames: LayoutFrames(readConfig: read, plugins: plugins),
      fonts: FontService(readConfig: read),
      npm: { arguments, project in
        recorder.command(["npm"] + arguments)
        for name in arguments.dropFirst() {
          let dir = project.appendingPathComponent("node_modules").appendingPathComponent(name)
          try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          try? Data((JSJSON.compact(.object(JSONObject([("name", .string(name)), ("version", .string("0.0.0-stub"))]))) + "\n").utf8).write(to: dir.appendingPathComponent("package.json"))
        }
        return PluginCommands.Result(success: true, output: "added \(arguments.count - 1) packages")
      },
      addPlugin: { source, project in
        recorder.command(["quartz", "plugin", "add", source])
        // The real CLI appends a bare entry of its own, as the golden's does.
        if var config = try? await ConfigFile.read(project: project, runtime: .repository) {
          config.plugins.append(PluginEntry(object: JSONObject([("source", .string(source)), ("enabled", .bool(true))])))
          try? await ConfigFile.write(config, project: project, runtime: .repository)
        }
        return PluginCommands.Result(success: true, output: "")
      },
      head: { project in
        let result = await ProcessRunner.run(environment.command("git", ["rev-parse", "--short", "HEAD"], in: project, timeout: .seconds(30)))
        return result.success ? JS.trim(result.output) : nil
      },
      snapshot: { _, kind, label in recorder.state.withLock { $0.snapshots.append([.string(kind), .string(label)]) } },
      app: ("QuartzHub", "0.0.0-test"))

    var before: [String: [String: JSONValue]] = [:]
    for (name, root) in roots { before[name] = Self.tree(root, mask: mask) }
    let steps = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps.json"))).arrayValue ?? []
    #expect(steps.count == 31)
    for (index, step) in steps.enumerated() {
      let on = step["on"]!.stringValue!, call = step["call"]!.stringValue!
      let args = step["args"]?.arrayValue ?? []
      let label = "\(index) \(on) \(call) \(args.first.map { JSJSON.compact($0) } ?? "")"
      let root = roots[on]!
      recorder.state.withLock { $0 = Recorder.State() }
      func packagePath(_ value: JSONValue) -> URL {
        let text = value.stringValue!
        if text == "@BASIC@" { return Self.basic }
        if text.hasPrefix("@W@") { return URL(fileURLWithPath: text.replacingOccurrences(of: "@W@", with: work, options: .literal)) }
        return roots["packages"]!.appendingPathComponent(text)
      }
      var got: JSONValue = .null
      do {
        switch call {
        case "inspectProject": got = .array(await templates.inspect(project: root).map(\.json))
        case "exportPackage":
          let options = args[2]
          let file = roots["packages"]!.appendingPathComponent(args[1].stringValue!)
          let exported = try await templates.export(project: roots[args[0].stringValue!]!, to: file, name: options["name"]!.stringValue!,
                                                    description: options["description"]?.stringValue, parts: options["parts"]!.arrayValue!.compactMap(\.stringValue),
                                                    scope: TemplatePackage.TranslationScope(rawValue: options["translationScope"]!.stringValue!)!)
          got = .object(JSONObject([("parts", .array(exported.parts.map(\.json))), ("unpacked", try Self.unpacked(file, mask: mask))]))
        case "planImport":
          if let plan = try await templates.plan(project: root, package: packagePath(args[0])) {
            var manifest = plan.manifest
            let name = args[0].stringValue!
            if !name.hasPrefix("@"), case .object(var object) = manifest, ["Quelle", "Teil", "Leer"].contains(object["name"]?.stringValue ?? "") {
              object["createdAt"] = .string("@DATE@")
              object["createdBy"] = .string("@APP@")
              manifest = .object(object)
            }
            got = .object(JSONObject([("manifest", manifest), ("parts", .array(plan.parts.map(\.json))), ("unknownParts", .array(plan.unknownParts)),
                                      ("legacy", .bool(plan.legacy))]))
          }
        case "importPackage":
          let result = try await templates.importPackage(project: root, package: packagePath(args[0]), parts: args[1].arrayValue!.compactMap(\.stringValue),
                                                         strategy: TemplatePackage.Strategy(rawValue: args[2].stringValue!)!)
          got = .object(JSONObject([("success", .bool(result.success)), ("warnings", .array(result.warnings.map(JSONValue.string)))]))
        case "slugifyFileName":
          got = .array([" Mein Paket: Ä/ö ", "", "---", "Basis-Template 2", "ÄÖÜ"].map { .string(TemplatePackage.slugifyFileName($0)) })
        default: Issue.record("\(label): unbekannter Schritt")
        }
      } catch {
        got = .object(JSONObject([("threw", .string(TemplatePackage.message(error)))]))
      }
      got = Self.masked(got, work)
      let expected = Self.rendered(step["result"] ?? .null)
      #expect(JSJSON.compact(got) == JSJSON.compact(expected), "\(label): \(firstDifference(JSJSON.compact(got), JSJSON.compact(expected)))")

      let after = Self.tree(root, mask: mask)
      var changed: [String: JSONValue] = [:]
      for path in Set(before[on]!.keys).union(after.keys) where before[on]![path] != after[path] {
        changed[path] = JSText.endsWith(path, ".qtpl") && after[path] != nil ? .object(JSONObject([("package", .bool(true))])) : (after[path] ?? .null)
      }
      before[on] = after
      var wanted: [String: JSONValue] = [:]
      if case .object(let files)? = step["changed"] { for key in files.keys { wanted[key] = Self.rendered(files[key]!) } }
      for path in Set(changed.keys).union(wanted.keys).sorted() where changed[path] != wanted[path] {
        Issue.record("\(label): \(path): \(changed[path].map { JSJSON.compact($0) }?.prefix(300) ?? "fehlt") statt \(wanted[path].map { JSJSON.compact($0) }?.prefix(300) ?? "fehlt")")
      }
      let commands = recorder.state.withLock { $0.commands }.map { $0.map(mask) }
      #expect(JSONValue.array(commands.map { .array($0.map(JSONValue.string)) }) == step["commands"], "\(label): Befehle \(commands)")
      let snapshots = recorder.state.withLock { $0.snapshots }
      #expect(JSONValue.array(snapshots.map(JSONValue.array)) == step["snapshots"], "\(label): Snapshots")
    }
  }

  static func realpath(_ path: String) -> String {
    guard let resolved = Darwin.realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  /// The live import takes its snapshot from the store, and one that cannot be taken (no git
  /// here) stops it before it writes anything: only the store's own folder is there afterwards.
  @Test func anImportWhoseSnapshotFailsWritesNothing() async throws {
    let scratch = try HostPathTests.Scratch()
    var environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    environment.git = nil
    environment.hostPath = HostPath(entries: ["/nonexistent"], source: .inherited, added: [])
    let templates = TemplatePackage.live(environment: environment, locales: LocaleFiles(environment: environment), frames: LayoutFrames(), fonts: FontService(),
                                         snapshots: .live(environment: environment), appVersion: "0")
    await #expect(throws: SnapshotStore.Failure.self) {
      _ = try await templates.importPackage(project: scratch.url, package: Self.basic, parts: TemplatePackage.partIds, strategy: .packageWins)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path) == [".quartz-gui"])
  }
}
