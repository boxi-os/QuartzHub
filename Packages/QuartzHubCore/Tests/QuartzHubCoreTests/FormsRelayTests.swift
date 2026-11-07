import Darwin
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own formsService.ts (`scripts/relay-golden.mjs`): 82 calls of the
/// relay's state, settings, upload, export, removal and exclusion, with the real connections,
/// targets, deploy dispatcher and folder adapter on both sides, Fixtures/forms/fake-cli.mjs as the
/// plugin's command line and Fixtures/forms/relay-server.mjs behind the probe. Each step: its
/// answer, the command line's arguments and QF_* variables, the requests the server saw,
/// forms-relay.json, publish-targets.json and the target and export folders (modes and texts).
/// One deviation: excluding the relay's folder keeps the site target's `withDocuments`.
@Suite(.serialized, .enabled(if: ToolEnvironmentTests.hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
struct FormsRelayTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/forms")
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("relay-steps.json")))

  final class Counters: Sendable {
    let ids = Mutex(0)
    let bytes = Mutex(0)
  }

  static func tree(_ root: String, mask: (String) -> String) -> JSONValue {
    guard Posix.kind(root) == .directory else { return .null }
    var found = JSONObject()
    var entries: [(String, String)] = []
    func walk(_ dir: String, _ rel: String) {
      for entry in Posix.entries(dir) ?? [] {
        let full = "\(dir)/\(entry.name)", r = rel.isEmpty ? entry.name : "\(rel)/\(entry.name)"
        var info = stat()
        lstat(full, &info)
        let mode = String(info.st_mode & 0o7777, radix: 8)
        if entry.kind == .directory {
          entries.append(("\(r)/", mode))
          walk(full, r)
        } else {
          entries.append((r, "\(mode) \(mask(String(decoding: (try? Posix.read(full)) ?? Data(), as: UTF8.self)))"))
        }
      }
    }
    walk(root, "")
    // The golden's keys in JavaScript's order: sorted by UTF-16 as readdirSync().sort() per folder.
    for (key, value) in entries { found[key] = .string(value) }
    return .object(found)
  }

  static func checkJSON(_ check: RelayCheck) -> JSONValue {
    var json = RelayProbeTests.json(check)
    if case .relayError(_, _, _, _, let origin?) = check, var object = json.objectValue {
      let listed: JSONValue = switch origin.listed {
      case .yes: .bool(true)
      case .no: .bool(false)
      case .any: .string("any")
      }
      object["origin"] = .object(JSONObject([("sent", .string(origin.sent)), ("listed", listed)]))
      json = .object(object)
    }
    return json
  }

  static func stateJSON(_ s: RelayState) -> JSONValue {
    var o = JSONObject()
    o["settings"] = .object(s.settings)
    o["lastUpload"] = s.lastUpload.map { .object($0) } ?? .null
    if let removedAt = s.removedAt { o["removedAt"] = .string(removedAt) }
    o["secrets"] = .object(JSONObject([("stored", .bool(s.secrets.stored)), ("recipients", .array(s.secrets.recipients.map { .string($0) })),
                                       ("captchaSecret", .bool(s.secrets.captchaSecret)), ("captchaSecrets", .array(s.secrets.captchaSecrets.map { .string($0) })),
                                       ("storageAvailable", .bool(s.secrets.storageAvailable))]))
    o["targets"] = .array(s.targets.map { t in
      .object(JSONObject([("id", .string(t.id)), ("name", .string(t.name)), ("type", .string(t.type)), ("where", .string(t.where)), ("rsync", .bool(t.rsync))]))
    })
    o["conflict"] = s.conflict.map { .object(JSONObject([("targetId", .string($0.targetId)), ("targetName", .string($0.targetName)), ("exclude", .string($0.exclude))])) } ?? .null
    o["currentHash"] = s.currentHash.map { .string($0) } ?? .null
    o["siteOrigin"] = s.siteOrigin.map { .string($0) } ?? .null
    o["relayForms"] = .array(s.relayForms.map { .string($0) })
    o["recipientNames"] = .array(s.recipientNames.map { .string($0) })
    if let problem = s.hashProblem { o["hashProblem"] = .string(problem) }
    if let moved = s.moved { o["moved"] = .bool(moved) }
    if s.configModeChanged { o["configModeChanged"] = .bool(true) }
    if s.operatorChanged { o["operatorChanged"] = .bool(true) }
    return .object(o)
  }

  static func uploadJSON(_ r: RelayUploadResult) -> JSONValue {
    var o = JSONObject([("success", .bool(r.success)), ("output", .string(r.output))])
    if let readable = r.configReadable { o["configReadable"] = .bool(readable) }
    if let check = r.check { o["check"] = checkJSON(check) }
    if let open = r.countersOpen { o["countersOpen"] = .string(open) }
    return .object(o)
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let (server, port, closed) = try await RelayProbeTests.startServer()
    defer { _ = server.signal(SIGKILL) }
    let work = TestFolder.make("qh-relay")
    defer { _ = try? FileManager.default.removeItem(atPath: work) }
    let project = "\(work)/Gärten-Ü"
    let plugin = "\(project)/.quartz/plugins/quartz-forms"
    try Posix.mkdirs("\(plugin)/dist")
    try Posix.write("\(plugin)/dist/cli.js", try Posix.read(Self.fixtures.appendingPathComponent("fake-cli.mjs").path))
    try Posix.write("\(plugin)/package.json", Data(#"{"name":"quartz-forms","type":"module","version":"0.6.0"}"#.utf8))

    let counters = Counters()
    let makeID: @Sendable () -> String = {
      let n = counters.ids.withLock { $0 += 1; return $0 }
      return "00000000-0000-4000-8000-" + String(repeating: "0", count: 12 - String(n).count) + String(n)
    }
    let golden = Self.golden
    let fixed = Date(timeIntervalSince1970: 1_794_043_800)  // 2026-11-07T09:30:00.000Z
    let connections = Connections(profile: ProfileDirectory("\(work)/profile"), secrets: MemorySecrets(), makeID: makeID,
                                  randomBytes: { n in let b = counters.bytes.withLock { $0 += 1; return $0 }; return [UInt8](repeating: UInt8(b), count: n) },
                                  now: { fixed })
    let targets = PublishTargets(project: project, makeID: makeID)
    let deploy = Deploy(project: project, connections: connections, adapters: ["folder": FolderAdapter()])
    let cli = FormsCLI(project: project, source: FormsCLITests.source, environment: ToolEnvironmentTests.environment(.embedded))
    let relay = FormsRelay(projectId: "p-1", cli: cli, connections: connections, deploy: deploy, probe: RelayProbeTests.probe(port: port), now: { fixed })

    let W = { (p: String) in p.replacingOccurrences(of: "@W@", with: work).replacingOccurrences(of: "@PORT@", with: String(port)).replacingOccurrences(of: "@CLOSED@", with: String(closed)) }
    let temp = FormsRelay.tempRoot
    let mask = { (text: String) -> String in
      let masked = text.replacingOccurrences(of: work, with: "@W@").replacingOccurrences(of: ":\(port)", with: ":@PORT@").replacingOccurrences(of: ":\(closed)", with: ":@CLOSED@")
      return JSText.replaceAll(masked, NSRegularExpression.escapedPattern(for: temp) + "/qh-relay-[A-Za-z0-9]{6}", with: "@TMP@")
    }
    func unmasked(_ value: JSONValue) -> JSONValue {
      switch value {
      case .string(let s): return .string(s.replacingOccurrences(of: "@LANG@", with: L10n.language))
      case .array(let items): return .array(items.map(unmasked))
      case .object(let o):
        var copy = JSONObject()
        for key in o.keys { copy[key] = unmasked(o[key]!) }
        return .object(copy)
      default: return value
      }
    }
    var compared = 0
    for step in golden["steps"]?.arrayValue ?? [] {
      let name = step["name"]?.stringValue ?? ""
      for a in step["setup"]?.arrayValue ?? [] {
        if let w = a["write"]?.arrayValue {
          let path = W(w[0].stringValue!)
          try Posix.mkdirs(NodePath.dirname(path))
          try Posix.write(path, Data(W(w[1].stringValue!).utf8))
        }
        if let m = a["mkdir"]?.stringValue { try Posix.mkdirs(W(m)) }
        if let r = a["rm"]?.stringValue { _ = try? FileManager.default.removeItem(atPath: W(r)) }
        if let c = a["chmod"]?.arrayValue { chmod(W(c[0].stringValue!), mode_t(c[1].stringValue!, radix: 8)!) }
        if let scenario = a["scenario"] { try Posix.write("\(project)/fake-cli.json", Data(W(JSJSON.compact(scenario)).utf8)) }
        if let c = a["connection"] { _ = try connections.save(ConnectionsTests.input(c)) }
        if let id = a["deleteConnection"]?.stringValue { try connections.delete(id) }
        if let t = a["target"] {
          let o = try JSJSON.parse(Data(W(JSJSON.compact(t)).utf8))
          _ = try targets.save(SavePublishTargetInput(id: o["id"]?.stringValue, name: o["name"]!.stringValue!, connectionId: o["connectionId"]?.stringValue,
                                                      destination: o["destination"]!.objectValue!, excludes: o["excludes"]?.arrayValue?.compactMap(\.stringValue),
                                                      withDocuments: o["withDocuments"]?.arrayValue?.compactMap(\.stringValue)))
        }
        if let change = a["secrets"] { try connections.saveRelaySecrets("p-1", ConnectionsTests.change(change)) }
      }
      _ = try? Posix.unlink("\(project)/fake-cli.log")
      _ = try await URLSession(configuration: .ephemeral).data(from: URL(string: "http://127.0.0.1:\(port)/__reset")!)
      let args = step["args"]?.arrayValue ?? []
      var result: JSONValue
      switch step["op"]?.stringValue {
      case "state": result = .object(JSONObject([("ok", Self.stateJSON(await relay.state()))]))
      case "settings":
        try relay.saveSettings(args[0].objectValue!)
        result = .object(JSONObject([("ok", .null)]))
      case "upload":
        result = .object(JSONObject([("ok", Self.uploadJSON(await relay.upload(url: args[0].stringValue.map(W), form: args[1].stringValue)))]))
      case "export": result = .object(JSONObject([("ok", Self.uploadJSON(await relay.export(to: W(args[0].stringValue!))))]))
      case "remove":
        let r = await relay.remove()
        result = .object(JSONObject([("ok", .object(JSONObject([("success", .bool(r.success)), ("output", .string(r.output))])))]))
      default:
        do {
          try relay.excludeFromSite(targetId: args[0].stringValue!, path: args[1].stringValue!)
          result = .object(JSONObject([("ok", .null)]))
        } catch {
          result = .object(JSONObject([("error", .string(error.message))]))
        }
      }
      result = try JSJSON.parse(Data(mask(JSJSON.compact(result)).utf8))
      let expected = GoldenText.localize(step["result"]!)
      #expect(result == expected, "\(name)\n\(JSJSON.compact(result))\n\(JSJSON.compact(expected))")

      let logText = (try? Posix.read("\(project)/fake-cli.log")).map { String(decoding: $0, as: UTF8.self) } ?? ""
      let log = JSText.split(JS.trim(logText), "\n").filter { !$0.isEmpty }.compactMap { try? JSJSON.parse(Data(mask($0).utf8)) }
      #expect(JSONValue.array(log) == unmasked(step["log"]!), "\(name): log\n\(JSJSON.compact(.array(log)))\n\(JSJSON.compact(unmasked(step["log"]!)))")

      var requests = try await RelayProbeTests.serverLog(port).arrayValue ?? []
      requests.sort { Array(JS.string($0["path"]).utf16).lexicographicallyPrecedes(Array(JS.string($1["path"]).utf16)) }
      #expect(JSONValue.array(requests) == step["requests"]!, "\(name): requests \(JSJSON.compact(.array(requests)))")

      let relayFile = (try? Posix.read("\(project)/.quartz-gui/forms-relay.json")).map { JSONValue.string(mask(String(decoding: $0, as: UTF8.self))) } ?? .null
      #expect(relayFile == step["relayFile"]!, "\(name): forms-relay.json\n\(relayFile)")
      var targetsFile = (try? Posix.read("\(project)/.quartz-gui/publish-targets.json")).map { mask(String(decoding: $0, as: UTF8.self)) }
      // Until the next save of that target, which the step after next makes.
      if ["excluding keeps nothing but what it knows", "state without the conflict"].contains(name), let text = targetsFile {
        // QuartzHub keeps the site target's withDocuments, which QuartzControl dropped here.
        #expect(JSText.includes(text, "\"withDocuments\""), "\(name): withDocuments kept")
        var list = try JSJSON.parse(Data(text.utf8)).arrayValue ?? []
        for i in list.indices where list[i]["id"] == .string("00000000-0000-4000-8000-000000000003") {
          var o = list[i].objectValue!
          o["withDocuments"] = nil
          list[i] = .object(o)
        }
        targetsFile = JSJSON.stringify(.array(list))
      }
      #expect(targetsFile.map(JSONValue.string) ?? .null == step["targetsFile"]!, "\(name): publish-targets.json\n\(targetsFile ?? "")")
      #expect(Self.tree("\(work)/Web", mask: mask) == step["web"]!, "\(name): Web\n\(JSJSON.compact(Self.tree("\(work)/Web", mask: mask)))")
      #expect(Self.tree("\(work)/Export", mask: mask) == step["export"]!, "\(name): Export")
      compared += 1
    }
    #expect(compared == 82)
  }

  @Test func sweepTakesOnlyOldRelayFolders() throws {
    let root = TestFolder.make("qh-relay-sweep")
    defer { _ = try? FileManager.default.removeItem(atPath: root) }
    for name in ["qh-relay-alt123", "qh-relay-neu456", "qc-relay-fremd1", "anderes"] { try Posix.mkdirs("\(root)/\(name)") }
    try Posix.write("\(root)/qh-relay-datei1", Data())
    let now = Date()
    let old = timespec(tv_sec: Int(now.timeIntervalSince1970) - 3601, tv_nsec: 0)
    for name in ["qh-relay-alt123", "qc-relay-fremd1", "anderes", "qh-relay-datei1"] {
      var times = [old, old]
      utimensat(AT_FDCWD, "\(root)/\(name)", &times, 0)
    }
    let removed = FormsRelay.sweepTempDirs(now: now, root: root)
    #expect(removed == ["\(root)/qh-relay-alt123"])
    #expect(Posix.entries(root)?.map(\.name) == ["anderes", "qc-relay-fremd1", "qh-relay-datei1", "qh-relay-neu456"])
  }
}
