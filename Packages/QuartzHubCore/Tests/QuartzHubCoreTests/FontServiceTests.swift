import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own fontService.ts and its helpers: `scripts/fonts-golden.mjs` ran them
/// against a scripted Google (`google.json`, CSS answers and font files by URL) and recorded every
/// answer, every changed file and every request. Here the same script answers FontService.
@Suite struct FontServiceTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
  static let fonts = fixtures.appendingPathComponent("fonts")
  static var stepCases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fonts.appendingPathComponent("steps").path)) ?? [])
      .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  static func json(_ name: String) throws -> JSONValue {
    try JSJSON.parse(Data(contentsOf: fonts.appendingPathComponent(name)))
  }

  @Test func thereAreCases() { #expect(Self.stepCases.count >= 11) }

  @Test func facesUrlsAndRequestsAsQuartzControl() throws {
    let pure = try Self.json("pure.json")
    for entry in pure["faces"]?.arrayValue ?? [] {
      #expect(JSONValue.array(FontFaces.parse(entry["text"]!.stringValue!).map(\.json)) == entry["faces"], "\(entry["text"]!)")
    }
    for entry in pure["fileIn"]?.arrayValue ?? [] {
      let file = FontFaces.fileIn("/D", entry["url"]?.stringValue)
      #expect(file.map { JSONValue.string($0) } ?? .null == entry["file"], "\(entry["url"]!)")
    }
    for entry in pure["css2"]?.arrayValue ?? [] {
      let typography = entry["typography"]?.objectValue ?? JSONObject()
      #expect(GoogleFontRequest.css2Url(typography).map { JSONValue.string($0) } ?? .null == entry["url"], "\(entry["typography"]!)")
      let requests = GoogleFontRequest.roles.map { GoogleFontRequest.request($0, typography[$0])?.json ?? .null }
      #expect(JSONValue.array(requests) == entry["requests"], "\(entry["typography"]!) requests")
    }
  }

  struct ConfigBroke: LocalizedError {
    let text: String
    var errorDescription: String? { text }
  }

  final class Box: @unchecked Sendable {
    let lock = Mutex<(config: JSONValue, requests: [JSONValue])>((.null, []))
  }

  static func config(_ value: JSONValue) throws -> QuartzConfig {
    if let error = value["error"]?.stringValue { throw ConfigBroke(text: error) }
    return QuartzConfig(configuration: value["configuration"]?.objectValue ?? JSONObject(), theme: value["theme"]?.objectValue ?? JSONObject())
  }

  /// The scripted Google of the golden script.
  static func fake(_ google: JSONObject, _ box: Box) -> FontService.Fetch {
    { url, userAgent, _ throws(FontService.FetchFailure) in
      box.lock.withLock { $0.requests.append(.object(JSONObject([("url", .string(url)), ("userAgent", userAgent.map { .string($0) } ?? .null)]))) }
      guard let answer = google[url], answer["fail"] != .bool(true) else { throw .unreachable }
      let body: Data
      if let bytes = answer["bytes"] {
        body = Data(repeating: UInt8(bytes["fill"]!.numberValue!), count: Int(bytes["size"]!.numberValue!))
      } else {
        body = Data((answer["text"]?.stringValue ?? "").utf8)
      }
      var headers: [String: String] = ["content-length": String(body.count)]
      if let given = answer["headers"]?.objectValue {
        headers = [:]
        for key in given.keys { headers[key.lowercased()] = given[key]?.stringValue }
      }
      return FontService.Response(status: Int(answer["status"]?.numberValue ?? 200), headers: headers, body: body)
    }
  }

  @Test(arguments: stepCases)
  func stepsAsQuartzControl(_ file: String) async throws {
    let golden = try Self.json("steps/\(file).json")
    let google = try Self.json("google.json").objectValue ?? JSONObject()
    let project = scratch.url.appendingPathComponent(file)
    let tree = golden["tree"]?.objectValue ?? JSONObject()
    for path in tree.keys {
      let url = project.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let text = tree[path]?.stringValue { try Data(text.utf8).write(to: url) }
      else { try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(tree[path]!["fixture"]!.stringValue!), to: url) }
    }
    try FileManager.default.createDirectory(at: project.appendingPathComponent("quartz/styles"), withIntermediateDirectories: true)
    let box = Box()
    box.lock.withLock { $0.config = golden["config"] ?? .null }
    let service = FontService(fetch: Self.fake(google, box), readConfig: { _ in try Self.config(box.lock.withLock { $0.config }) })
    var before = Self.files(project)
    for step in golden["steps"]?.arrayValue ?? [] {
      let call = step["call"]!.stringValue!
      let args = (step["args"]?.arrayValue ?? []).map { arg -> JSONValue in
        if case .string(let text) = arg { return .string(text.replacingOccurrences(of: "@IN@", with: project.appendingPathComponent("in").path)) }
        return arg
      }
      box.lock.withLock { $0.requests = [] }
      let result: JSONValue
      do {
        result = try await Self.run(call, args, service, project, box)
      } catch {
        result = .object(JSONObject([("threw", .string((error as? FontService.Failure)?.message ?? String(describing: error)))]))
      }
      #expect(result == Self.rendered(step["result"] ?? .null), "\(file): \(call)")
      #expect(JSONValue.array(box.lock.withLock { $0.requests }) == step["requests"], "\(file): \(call) requests")
      let after = Self.files(project)
      var changed = JSONObject()
      for path in Set(before.keys).union(after.keys).sorted() where before[path] != after[path] { changed[path] = after[path] ?? .null }
      let expected = step["changed"]?.objectValue ?? JSONObject()
      #expect(Set(changed.keys) == Set(expected.keys), "\(file): \(call) changed files")
      for path in expected.keys where changed[path] != expected[path] {
        Issue.record("\(file): \(call) wrote \(path) differently\n\(firstDifference(JS.string(changed[path]), JS.string(expected[path])))")
      }
      before = after
    }
  }

  /// The build door with the real config reader and without the network: every family the
  /// typography names is the project's own, so the block becomes "nothing from Google" and the
  /// Google file goes; both are said. The second run says nothing.
  @Test(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt"))
  func theBuildDoorRefreshesTheGoogleFonts() async throws {
    let golden = try Self.json("steps/refresh-every-family-own.json")
    let project = scratch.url.appendingPathComponent("door")
    let tree = golden["tree"]?.objectValue ?? JSONObject()
    for path in tree.keys {
      let url = project.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(tree[path]!.stringValue!.utf8).write(to: url)
    }
    try Data("configuration:\n  pageTitle: door\n  theme:\n    fontOrigin: local\n    typography:\n      header: Inter\nplugins: []\n".utf8)
      .write(to: project.appendingPathComponent("quartz.config.yaml"))
    func run() async -> [String] {
      let said = Mutex<[String]>([])
      for step in BuildService.preparation { await step(project) { stream, text in said.withLock { $0.append("\(stream) \(text)") } } }
      return said.withLock { $0 }
    }
    let expected = L10n.t("main.googleFontsRefreshOwn", ["families": "Inter"]) + " " + L10n.t("main.googleFontsRefreshRemoved", ["count": "1"])
    #expect(await run() == ["stdout \(expected)\n"])
    #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent("quartz/static/fonts/g-inter.woff2").path))
    #expect(await run() == [])
  }

  /// The golden answers with QuartzControl's texts rendered from the catalog.
  static func rendered(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string(let text): return .string(QC.render(text, mask: ""))
    case .array(let items): return .array(items.map(rendered))
    case .object(let object):
      var out = JSONObject()
      for key in object.keys { out[key] = rendered(object[key]!) }
      return .object(out)
    default: return value
    }
  }

  static func strings(_ list: [String]) -> JSONValue { .array(list.map { .string($0) }) }

  static func run(_ call: String, _ args: [JSONValue], _ service: FontService, _ project: URL, _ box: Box) async throws -> JSONValue {
    switch call {
    case "setConfig":
      box.lock.withLock { $0.config = args[0] }
      return .null
    case "write":
      let url = project.appendingPathComponent(args[0].stringValue!)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(args[1].stringValue!.utf8).write(to: url)
      return .null
    case "importFontFile":
      let imported = try await service.importFontFile(URL(fileURLWithPath: args[0].stringValue!), family: args[1].stringValue!, project: project)
      var pairs: [(String, JSONValue)] = [("fileName", .string(imported.fileName))]
      if let face = imported.face { pairs += [("weight", .string(face.weight)), ("italic", .bool(face.italic))] }
      return .object(JSONObject(pairs))
    case "unusedImportedFonts":
      let unused = try await service.unusedImportedFonts(project: project, draftFamilies: (args[0].arrayValue ?? []).compactMap(\.stringValue))
      return .array(unused.map { .object(JSONObject([("family", .string($0.family)), ("files", strings($0.files))])) })
    case "removeImportedFont":
      return .object(JSONObject([("removedFiles", strings(try await service.removeImportedFont(args[0].stringValue!, project: project)))]))
    case "fontFilesReplacedRulesWouldRemove":
      return strings(try service.fontFilesReplacedRulesWouldRemove(previous: args[0].stringValue!, incoming: args[1].stringValue!, project: project))
    case "deleteFontFilesOfReplacedRules":
      return strings(try await service.deleteFontFilesOfReplacedRules(args[0].stringValue!, project: project))
    case "fetchGoogleFonts":
      let r = try await service.fetchGoogleFonts(args[0].objectValue ?? JSONObject(), project: project)
      return .object(JSONObject([("changed", .bool(r.changed)), ("files", strings(r.files)), ("removedFiles", strings(r.removedFiles)),
                                 ("removedFamilies", strings(r.removedFamilies)), ("missingFamilies", strings(r.missingFamilies)),
                                 ("ownFamilies", strings(r.ownFamilies)), ("coveredFamilies", strings(r.coveredFamilies))]))
    case "dropGoogleFonts":
      let r = try await service.dropGoogleFonts(project: project)
      return .object(JSONObject([("dropped", .bool(r.dropped)), ("removedFiles", strings(r.removedFiles)), ("removedFamilies", strings(r.removedFamilies))]))
    case "refreshGoogleFonts":
      guard let r = await service.refreshGoogleFonts(project: project) else { return .null }
      return .object(JSONObject([("failed", .bool(r.failed)), ("text", .string(r.text))]))
    default:
      Issue.record("unknown call \(call)")
      return .null
    }
  }

  /// Every file under quartz/, a font file as its size and SHA-1 (as the golden script wrote it).
  static func files(_ project: URL) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    let root = project.appendingPathComponent("quartz")
    guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [:] }
    while let relative = walker.nextObject() as? String {
      var isDirectory: ObjCBool = false
      let full = root.appendingPathComponent(relative)
      guard FileManager.default.fileExists(atPath: full.path, isDirectory: &isDirectory), !isDirectory.boolValue,
            let data = try? Data(contentsOf: full) else { continue }
      let printable = data.allSatisfy { $0 == 0x09 || $0 == 0x0A || (0x20...0x7E).contains($0) }
      if JSText.test(relative, #"\.(woff2?|ttf|otf|TTF)\z"#) && !printable {
        let sha = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        result["quartz/\(relative)"] = .object(JSONObject([("size", .number(Double(data.count))), ("sha1", .string(sha))]))
      } else {
        result["quartz/\(relative)"] = .string(String(decoding: data, as: UTF8.self))
      }
    }
    return result
  }
}
