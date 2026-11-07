import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own formsService.ts (`scripts/forms-cli-golden.mjs`): 52 calls of check,
/// texts, inspectKey and importKeyFile, the plugin's command line being Fixtures/forms/fake-cli.mjs,
/// each with its answer, the arguments and QF_* variables the command line got, and the key folder
/// afterwards. One deviation: an answer `null`, where QuartzControl threw a TypeError.
@Suite(.enabled(if: ToolEnvironmentTests.hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
struct FormsCLITests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/forms")
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("cli-steps.json")))
  static let source = PluginSource(.string("github:boxi-os/quartz-forms"))!

  static func report(_ r: FormsKeyReport) -> JSONValue {
    var o = JSONObject([("name", .string(r.name)), ("fingerprint", .string(r.fingerprint)), ("userIds", .array(r.userIds.map { .string($0) }))])
    if let v = r.expires { o["expires"] = .string(v) }
    if let v = r.problem { o["problem"] = .string(v) }
    if let v = r.notice { o["notice"] = .string(v) }
    return .object(o)
  }

  static func keys(_ project: String) -> JSONValue {
    let dir = "\(project)/quartz-forms/keys"
    guard Posix.exists(dir), let entries = Posix.entries(dir) else { return .null }
    var found = JSONObject()
    for entry in entries {
      let full = "\(dir)/\(entry.name)"
      switch Posix.kind(full) {
      case .file:
        let text = String(decoding: (try? Posix.read(full)) ?? Data(), as: UTF8.self)
        found[entry.name] = .string(JSText.length(text) > 2000 ? "\(JSText.length(text)): \(JSText.slice(text, 0, 60))" : text)
      case .link: found[entry.name] = .string("link")
      default: found[entry.name] = .string("folder")
      }
    }
    return .object(found)
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let work = TestFolder.make("qh-forms")
    defer { _ = try? FileManager.default.removeItem(atPath: work) }
    let project = "\(work)/Gärten-Ü"
    let plugin = "\(project)/.quartz/plugins/quartz-forms"
    try Posix.mkdirs(project)
    let W = { (p: String) in p.replacingOccurrences(of: "@W@", with: work) }
    let cli = FormsCLI(project: project, source: Self.source, environment: ToolEnvironmentTests.environment(.embedded))
    let fake = try Posix.read(Self.fixtures.appendingPathComponent("fake-cli.mjs").path)
    var compared = 0
    for step in Self.golden["steps"]?.arrayValue ?? [] {
      let name = step["name"]?.stringValue ?? ""
      for a in step["setup"]?.arrayValue ?? [] {
        if let w = a["write"]?.arrayValue {
          let path = W(w[0].stringValue!)
          try Posix.mkdirs(NodePath.dirname(path))
          try Posix.write(path, Data(w[1].stringValue!.utf8))
        }
        if let f = a["fill"]?.arrayValue {
          let prefix = f[1].stringValue!
          try Posix.write(W(f[0].stringValue!), Data((prefix + String(repeating: "x", count: Int(f[2].numberValue!) - JSText.length(prefix))).utf8))
        }
        if let m = a["mkdir"]?.stringValue { try Posix.mkdirs(W(m)) }
        if let r = a["rm"]?.stringValue { _ = try? FileManager.default.removeItem(atPath: W(r)) }
        if let c = a["chmod"]?.arrayValue { chmod(W(c[0].stringValue!), mode_t(c[1].stringValue!, radix: 8)!) }
        if let l = a["symlink"]?.arrayValue {
          try Posix.mkdirs(NodePath.dirname(W(l[1].stringValue!)))
          try Posix.symlink(W(l[0].stringValue!), W(l[1].stringValue!))
        }
        if let extra = a["cli"]?.stringValue {
          try Posix.mkdirs("\(plugin)/dist")
          try Posix.write("\(plugin)/dist/cli.js", fake + Data(extra.utf8))
        }
        if let version = a["version"]?.stringValue {
          try Posix.mkdirs(plugin)
          try Posix.write("\(plugin)/package.json", Data(JSJSON.compact(.object(JSONObject([("name", .string("quartz-forms")), ("type", .string("module")), ("version", .string(version))]))).utf8))
        }
        if let scenario = a["scenario"] { try Posix.write("\(project)/fake-cli.json", Data(JSJSON.compact(scenario).utf8)) }
      }
      _ = try? Posix.unlink("\(project)/fake-cli.log")
      let args = step["args"]?.arrayValue ?? []
      var result: JSONValue
      switch step["op"]?.stringValue {
      case "check":
        switch await cli.check() {
        case .checked(let problems, let hints, let keys):
          result = .object(JSONObject([("ok", .object(JSONObject([("state", .string("checked")), ("problems", .array(problems.map { .string($0) })),
                                                                   ("hints", .array(hints.map { .string($0) })), ("keys", .array(keys.map(Self.report)))])))]))
        case .unavailable(let reason):
          result = .object(JSONObject([("ok", .object(JSONObject([("state", .string("unavailable")), ("reason", .string(reason))])))]))
        }
      case "texts":
        switch await cli.texts() {
        case .read(let locales):
          result = .object(JSONObject([("ok", .object(JSONObject([("state", .string("read")), ("locales", .object(locales))])))]))
        case .unavailable(let reason):
          result = .object(JSONObject([("ok", .object(JSONObject([("state", .string("unavailable")), ("reason", .string(reason))])))]))
        }
      case "inspectKey":
        switch await cli.inspectKey(args[0].stringValue!) {
        case .key(let report, let armored):
          var o = JSONObject([("key", Self.report(report))])
          if let armored { o["armored"] = .string(armored) }
          result = .object(JSONObject([("ok", .object(o))]))
        case .unavailable(let reason):
          result = .object(JSONObject([("ok", .object(JSONObject([("unavailable", .string(reason))])))]))
        }
      default:
        do {
          switch try FormsCLI.importKeyFile(project: project, from: W(args[0].stringValue!), name: args[1].stringValue!, overwrite: args[2] == .bool(true)) {
          case .file(let f): result = .object(JSONObject([("ok", .object(JSONObject([("file", .string(f))])))]))
          case .exists(let f): result = .object(JSONObject([("ok", .object(JSONObject([("exists", .string(f))])))]))
          }
        } catch {
          result = .object(JSONObject([("error", .string("Error: \(error.message)"))]))
        }
      }
      let unmask = { (text: String) in W(text).replacingOccurrences(of: ".tmp-@PID@", with: ".tmp-\(getpid())").replacingOccurrences(of: "@LANG@", with: L10n.language) }
      func unmasked(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let s): return .string(unmask(s))
        case .array(let items): return .array(items.map(unmasked))
        case .object(let o):
          var copy = JSONObject()
          for key in o.keys { copy[unmask(key)] = unmasked(o[key]!) }
          return .object(copy)
        default: return value
        }
      }
      var expected = GoldenText.localize(unmasked(step["result"]!))
      if name == "JSON null" {
        // QuartzControl threw "TypeError: Cannot read properties of null (reading 'ok')".
        expected = .object(JSONObject([("ok", .object(JSONObject([("state", .string("unavailable")), ("reason", .string(L10n.t("main.formsCliOutput", ["output": "null"])))])))]))
      }
      #expect(result == expected, "\(name)\n\(JSJSON.compact(result))\n\(JSJSON.compact(expected))")
      let logText = (try? Posix.read("\(project)/fake-cli.log")).map { String(decoding: $0, as: UTF8.self) } ?? ""
      let log = JSText.split(JS.trim(logText), "\n").filter { !$0.isEmpty }.compactMap { try? JSJSON.parse(Data($0.utf8)) }
      #expect(JSONValue.array(log) == unmasked(step["log"]!), "\(name): log \(logText)")
      #expect(Self.keys(project) == unmasked(step["keys"]!), "\(name): keys")
      compared += 1
    }
    #expect(compared == 52)
  }

  @Test func semverAsQuartzControl() {
    #expect(SemVer.isNewer("1.0.0", than: "1.0.0-beta.2"))
    #expect(SemVer.isNewer("1.0.0-beta.10", than: "1.0.0-beta.9"))
    #expect(!SemVer.isNewer("1.0.0-beta.1", than: "1.0.0-beta.1.2"))
    #expect(SemVer.isNewer("1.0.0-beta.1.2", than: "1.0.0-beta.1"))
    #expect(SemVer.isNewer("1.0.0-beta", than: "1.0.0-alpha"))
    #expect(SemVer.isNewer("1.0.0-alpha.b", than: "1.0.0-alpha.1"))
    #expect(!SemVer.isNewer("v1.0.0", than: "0.1.0"))
    #expect(SemVer.isNewer(" 0.10.0 ", than: "0.9.9"))
    #expect(!SemVer.isNewer("0.3.0", than: "0.3.0"))
  }
}
