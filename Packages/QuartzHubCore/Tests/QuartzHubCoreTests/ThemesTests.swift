import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Answers by URL from `Fixtures/themes/net.json`, as the golden script's fetch did; a URL it does
/// not know, or one marked `fail`, is a network error.
final class ThemeNet: URLProtocol, @unchecked Sendable {
  struct State {
    var net: [String: JSONValue] = [:]
    var requests: [JSONValue] = []
  }

  static let state = Mutex(State())

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ThemeNet.self]
    return configuration
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!.absoluteString
    let headers = request.allHTTPHeaderFields ?? [:]
    let answer: JSONValue? = Self.state.withLock { state in
      state.requests.append(.object(JSONObject([("url", .string(url)), ("authorization", headers["Authorization"].map { .string($0) } ?? .null),
                                                ("accept", headers["Accept"].map { .string($0) } ?? .null)])))
      return state.net[url]
    }
    guard let answer, answer[safe: "fail"] != .bool(true) else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let body: String = if let json = answer[safe: "json"] { JSJSON.compact(json) } else { answer[safe: "text"]?.stringValue ?? "" }
    var fields: [String: String] = [:]
    if case .object(let given)? = answer[safe: "headers"] { for key in given.keys { fields[key] = given[key]?.stringValue } }
    let response = HTTPURLResponse(url: request.url!, statusCode: Int(answer[safe: "status"]?.numberValue ?? 200), httpVersion: "HTTP/1.1", headerFields: fields)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

/// Against QuartzControl's own themePresetsService.ts, styleSettingsSchemaService.ts and
/// themeMarketplaceService.ts: `scripts/themes-golden.mjs` ran the steps of `Fixtures/themes/steps.json`
/// against a scripted network, `npm` and a temporary userData, and recorded each step's answer, the
/// requests and commands it made and the files it changed. The services read YAML through the
/// helper, so this needs Runtime/ and Helpers/dist.
@Suite(.serialized, .enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt: scripts/fetch-runtime.sh, scripts/build-helpers.sh"))
struct ThemesTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/themes")

  final class Scratch {
    /// With a composed "ä" and "Ü"; `url` for the test's own file work only.
    let path = TestFolder.make("qh-themes")
    var url: URL { URL(fileURLWithPath: path) }
    init() throws {}
    deinit { try? FileManager.default.removeItem(atPath: path) }
  }

  /// What the scripted `npm` does: the next `npm search` answers this, every call is noted.
  final class FakeNpm: Sendable {
    struct State {
      var search: JSONValue = .null
      var commands: [JSONValue] = []
    }

    let state = Mutex(State())

    var search: ThemeMarketplace.Search {
      { [self] in
        state.withLock { state in
          state.commands.append(.array(["npm", "search", "@quartz-themes", "--json", "--searchlimit=250"].map { .string($0) }))
          return state.search[safe: "error"] == .bool(true) ? nil : state.search[safe: "stdout"]?.stringValue
        }
      }
    }

    var install: ThemeMarketplace.Install {
      { [self] arguments, _ in
        state.withLock { $0.commands.append(.array((["npm"] + arguments).map { .string($0) })) }
        return PluginCommands.Result(success: true, output: "added 2 packages")
      }
    }
  }

  static func object(_ pairs: [(String, JSONValue?)]) -> JSONValue {
    .object(JSONObject(pairs.compactMap { key, value in value.map { (key, $0) } }))
  }

  static func json(_ detail: ThemeDetail?) -> JSONValue {
    guard let detail else { return .null }
    let strings = { (list: [String]) in JSONValue.array(list.map { .string($0) }) }
    return object([("modes", strings(detail.modes)), ("variations", strings(detail.variations)), ("styleSettingsId", strings(detail.styleSettingsId)),
                   ("fonts", strings(detail.fonts))])
  }

  static func json(_ catalog: ThemeMarketplace.Catalog) -> JSONValue {
    let themes = catalog.themes.map { theme in
      object([("id", .string(theme.id)), ("description", theme.description.map { .string($0) }), ("stars", theme.stars.map { .number(Double($0)) }),
              ("topics", theme.topics.map { .array($0.map { .string($0) }) }), ("githubDescription", theme.githubDescription.map { .string($0) })])
    }
    return object([("themes", .array(themes)), ("unavailable", .bool(catalog.unavailable))])
  }

  /// Every file under the project's `.quartz-gui/` and the profile's `theme-docs/`, by the golden's names.
  static func files(project: URL, profile: URL) -> [String: String] {
    var result: [String: String] = [:]
    func walk(_ dir: URL, _ prefix: String) {
      for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
        let full = dir.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: full.path, isDirectory: &isDirectory)
        if isDirectory.boolValue { walk(full, "\(prefix)\(name)/") } else { result[prefix + name] = (try? String(contentsOf: full, encoding: .utf8)) ?? "" }
      }
    }
    walk(project.appendingPathComponent(".quartz-gui"), "project/.quartz-gui/")
    walk(profile.appendingPathComponent("theme-docs"), "theme-docs/")
    return result
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let scratch = try Scratch()
    let projectPath = "\(scratch.path)/project"
    let project = URL(fileURLWithPath: projectPath)
    let profile = scratch.url.appendingPathComponent("userData")
    let local = project.appendingPathComponent("node_modules/@quartz-themes/tokyo-night")
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    try #"{"meta":{"styleSettingsId":"tokyo-night-appearance","modes":["dark"],"variations":[],"fonts":["Inter"]},"classSettings":{}}"#
      .write(to: local.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)

    let network = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("net.json")))
    let registry = try #require(network[safe: "registry"]?.stringValue)
    guard case .object(let net)? = network[safe: "net"] else { Issue.record("net.json ohne net"); return }
    ThemeNet.state.withLock { state in
      state = ThemeNet.State()
      for key in net.keys { state.net[key] = net[key] }
    }
    let npm = FakeNpm()
    let settings = StyleSettingsSchema(profile: ProfileDirectory("\(scratch.path)/userData"), configuration: ThemeNet.configuration, readYaml: StyleSettingsSchema.helperYaml(runtime: HelperRuntime.runtime))
    let market = ThemeMarketplace(search: npm.search, install: npm.install, configuration: ThemeNet.configuration)

    guard case .array(let steps) = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps.json"))) else { Issue.record("steps.json ist keine Liste"); return }
    var before = Self.files(project: project, profile: profile)
    for (index, step) in steps.enumerated() {
      let service = step[safe: "service"]?.stringValue ?? "", call = step[safe: "call"]?.stringValue ?? ""
      let args = step[safe: "args"]?.arrayValue ?? []
      let label = "\(index) \(service).\(call) \(args.first.map { JSJSON.compact($0) } ?? "")"
      ThemeNet.state.withLock { $0.requests = [] }
      npm.state.withLock { $0.commands = [] }
      var got: JSONValue = .null
      do {
        switch (service, call) {
        case ("presets", "listPresets"): got = .array(ThemePresets.list(project: projectPath))
        case ("presets", "savePreset"): try ThemePresets.save(args[0], project: projectPath)
        case ("presets", "deletePreset"): try ThemePresets.delete(id: args[0].stringValue!, project: projectPath)
        case ("presets", "writeRaw"):
          try FileManager.default.createDirectory(at: project.appendingPathComponent(".quartz-gui"), withIntermediateDirectories: true)
          try args[0].stringValue!.write(to: project.appendingPathComponent(".quartz-gui/theme-presets.json"), atomically: true, encoding: .utf8)
        case ("settings", "getStyleSettingsSchema"): got = try await settings.schema(themeId: args[0].stringValue!)
        case ("settings", "themeDocsCacheStats"):
          let stats = await settings.cacheStats()
          got = Self.object([("entries", .number(Double(stats.entries))), ("bytes", .number(Double(stats.bytes)))])
        case ("settings", "clearStyleSettingsSchemaCache"): try await settings.clearCache(themeId: args[0].stringValue!)
        case ("settings", "clearThemeDocsCache"): got = .number(Double(await settings.clearCache()))
        case ("settings", "registryDown"): ThemeNet.state.withLock { $0.net[registry] = Self.object([("fail", .bool(true))]) }
        case ("market", "npm"): npm.state.withLock { $0.search = args[0] }
        case ("market", "listThemes"): got = Self.json(await market.list())
        case ("market", "getThemeDetail"): got = Self.json(try await market.detail(themeId: args[0].stringValue!, project: projectPath))
        case ("market", "installTheme"):
          let result = try await market.install(themeId: args[0].stringValue!, project: projectPath)
          got = Self.object([("success", .bool(result.success)), ("output", .string(result.output))])
        case ("market", "invalidateCache"): await market.invalidate()
        default: Issue.record("\(label): unbekannter Schritt")
        }
      } catch {
        got = Self.object([("threw", .string(String(describing: error)))])
      }
      let after = Self.files(project: project, profile: profile)
      var changed: [String: String?] = [:]
      for path in Set(before.keys).union(after.keys) where before[path] != after[path] {
        changed[JSText.replaceAll(path, #"corrupt-[^/]*\z"#, with: "corrupt-*")] = after[path]
      }
      before = after

      let expected = step[safe: "result"] ?? .null
      #expect(JSJSON.compact(got) == JSJSON.compact(expected), "\(label): \(firstDifference(JSJSON.compact(got), JSJSON.compact(expected)))")
      let requests = ThemeNet.state.withLock { $0.requests }
      #expect(JSJSON.compact(.array(requests)) == JSJSON.compact(step[safe: "requests"] ?? .array([])), "\(label): Anfragen")
      let commands = npm.state.withLock { $0.commands }
      #expect(JSJSON.compact(.array(commands)) == JSJSON.compact(step[safe: "commands"] ?? .array([])), "\(label): Befehle")
      var wanted: [String: String?] = [:]
      if case .object(let files)? = step[safe: "changed"] { for key in files.keys { wanted[key] = files[key]?.stringValue } }
      #expect(changed == wanted, "\(label): Dateien \(changed.keys.sorted()) statt \(wanted.keys.sorted())")
    }
  }

  /// The token from the connections raises the rate limit of the organisation's repo list; one
  /// that cannot be read leaves it anonymous.
  @Test func theRepoListCarriesTheToken() async throws {
    let npm = FakeNpm()
    let page = "https://api.github.com/orgs/quartz-themes/repos?per_page=100&page=1"
    for (token, expected) in [("ghp_t", JSONValue.string("Bearer ghp_t")), (nil, .null)] as [(String?, JSONValue)] {
      ThemeNet.state.withLock { $0 = ThemeNet.State(); $0.net[page] = Self.object([("json", .array([]))]) }
      let market = ThemeMarketplace(search: npm.search, install: npm.install, configuration: ThemeNet.configuration, token: { token })
      _ = await market.githubMetadata()
      let requests = ThemeNet.state.withLock { $0.requests }
      #expect(requests.count == 1 && requests[0][safe: "authorization"] == expected, "\(requests)")
    }
  }

  @Test func refusesThemeIdsThatAreNoPackageName() async throws {
    let npm = FakeNpm()
    let market = ThemeMarketplace(search: npm.search, install: npm.install, configuration: ThemeNet.configuration)
    for id in ["../core", "Tokyo", "", "-x", "a b", String(repeating: "a", count: 129)] {
      await #expect(throws: StyleSettingsSchema.InvalidThemeId.self) { try await market.install(themeId: id, project: "/nonexistent") }
    }
    #expect(npm.state.withLock { $0.commands }.isEmpty)
  }
}
