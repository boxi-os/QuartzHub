import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own configService.ts: `scripts/config-golden.mjs` ran its readConfig,
/// the edits and its writeConfig on each input in `Fixtures/config/<case>/`; here ConfigFile does
/// the same and has to arrive at the same object and the same bytes.
enum HelperRuntime {
  static let runtime = RuntimeLocation.repository
  static let available = ToolEnvironmentTests.hasRuntime
    && FileManager.default.fileExists(atPath: runtime.helpers.appendingPathComponent("yaml-edit.cjs").path)
}

@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt: scripts/fetch-runtime.sh, scripts/build-helpers.sh"))
struct ConfigFileTests {
  static let runtime = HelperRuntime.runtime
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/config")
  static var cases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  func project(_ text: String?, name: String = "projekt") throws -> URL {
    let project = scratch.url.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    if let text { try Data(text.utf8).write(to: ConfigFile.path(project: project)) }
    return project
  }

  func read(_ project: URL) async throws -> QuartzConfig {
    try await ConfigFile.read(project: project, runtime: Self.runtime)
  }

  func write(_ config: QuartzConfig, _ project: URL) async throws {
    try await ConfigFile.write(config, project: project, runtime: Self.runtime)
  }

  func fileText(_ project: URL) throws -> String {
    try String(contentsOf: ConfigFile.path(project: project), encoding: .utf8)
  }

  // MARK: golden

  @Test func thereAreCases() {
    #expect(Self.cases.count >= 15, "scripts/config-golden.mjs")
  }

  @Test(arguments: cases)
  func sameAsQuartzControl(_ name: String) async throws {
    let dir = Self.fixtures.appendingPathComponent(name)
    func fixture(_ file: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(file)) }
    let project = try project(String(decoding: fixture("input.yaml")!, as: UTF8.self))
    let spec = try JSJSON.parse(fixture("edits.json")!)
    let error = try fixture("error.json").map { try JSJSON.parse($0) }

    let config: QuartzConfig
    do {
      config = try await read(project)
    } catch let failure as ConfigFile.Failure {
      #expect(error?["during"] == .string("read"), "\(failure)")
      #expect(Self.describe(failure) == error.map(Self.describe), "\(name)")
      return
    }
    #expect(error?["during"] != .string("read"), "QuartzControl refused to read \(name)")
    #expect(config.jsonValue == (try JSJSON.parse(fixture("read.json")!)), "read of \(name)")

    var edited = config.jsonValue
    for edit in spec["edits"]?.arrayValue ?? [] { Self.apply(edit, to: &edited) }
    let changed = try #require(QuartzConfig(jsonValue: edited))
    if case .string(let replacement)? = spec["replaceBeforeWrite"] {
      try Data(replacement.utf8).write(to: ConfigFile.path(project: project))
    }
    do {
      try await write(changed, project)
      #expect(error == nil, "QuartzControl refused to write \(name)")
      let written = try Data(contentsOf: ConfigFile.path(project: project))
      #expect(written == fixture("expected.yaml"), "\(name)")
    } catch let failure as ConfigFile.Failure {
      #expect(error?["during"] == .string("write"), "\(failure)")
      #expect(Self.describe(failure) == error.map(Self.describe), "\(name)")
    }
  }

  /// The key and arguments of a failure, in the form the golden script recorded mainT's call.
  static func describe(_ failure: ConfigFile.Failure) -> String {
    switch failure {
    case .missing: "configMissing"
    case .notParseable(let reason): "configNotParseable \(reason)"
    case .notAMapping: "configNotAMapping"
    case .pluginsNotAList: "configPluginsNotAList"
    case .pluginEntryInvalid(let index): "configPluginEntryInvalid \(index)"
    }
  }

  static func describe(_ error: JSONValue) -> String {
    let key = error["key"]?.stringValue ?? "?"
    guard let reason = error["args"]?["reason"]?.stringValue else { return key }
    return "\(key) \(reason)"
  }

  /// The golden script's `apply`: set (creating what is missing on the way), delete, move.
  static func apply(_ edit: JSONValue, to config: inout JSONValue) {
    if let move = edit["move"]?.arrayValue, case .number(let from) = move[0], case .number(let to) = move[1],
       var plugins = config["plugins"]?.arrayValue {
      let entry = plugins.remove(at: Int(from))
      plugins.insert(entry, at: Int(to))
      set(&config, [.string("plugins")], .array(plugins))
      return
    }
    if let path = edit["set"]?.arrayValue { set(&config, path, edit["value"]!) }
    if let path = edit["delete"]?.arrayValue { set(&config, path, nil) }
  }

  static func set(_ node: inout JSONValue, _ path: [JSONValue], _ value: JSONValue?) {
    guard let first = path.first else {
      if let value { node = value }
      return
    }
    let rest = Array(path.dropFirst())
    switch (node, first) {
    case (.array(var items), .number(let index)):
      if rest.isEmpty, value == nil {
        items.remove(at: Int(index))
      } else {
        set(&items[Int(index)], rest, value)
      }
      node = .array(items)
    case (.object(var object), .string(let key)):
      if rest.isEmpty {
        object[key] = value
      } else {
        var child = object[key].flatMap { $0.isNull ? nil : $0 } ?? .object(JSONObject())
        set(&child, rest, value)
        object[key] = child
      }
      node = .object(object)
    default:
      Issue.record("path \(path) does not fit \(node)")
    }
  }

  // MARK: what the golden files cannot show

  @Test func aMissingFileSaysSo() async throws {
    let project = try project(nil)
    await #expect(throws: ConfigFile.Failure.missing) { try await read(project) }
  }

  @Test func anEntryThatNamesNoPluginIsSaidWithItsNumber() async throws {
    // QuartzControl: "Cannot read properties of undefined (reading 'name')".
    for (text, index) in [("plugins:\n  - source: a\n  - options: {}\n", 2), ("plugins:\n  - just-a-string\n", 1),
                          ("plugins:\n  - source: a\n  - source: 5\n", 2),
                          ("plugins:\n  - source:\n      subdir: x\n", 1)] {
      let project = try project(text)
      await #expect(throws: ConfigFile.Failure.pluginEntryInvalid(index: index)) { try await read(project) }
    }
    #expect(ConfigFile.Failure.pluginEntryInvalid(index: 2).message.contains("2"))
  }

  @Test func aKeyOfTheWrongKindReadsAsAbsentAndStaysInTheFile() async throws {
    // QuartzControl threw on the first (`null.groups`) and could not save the second
    // (`setIn` under a string).
    let text = "configuration: nur ein Satz\nplugins: []\nlayout:\n"
    let project = try project(text)
    var config = try await read(project)
    #expect(config.configuration.isEmpty && config.layout == nil)
    try await write(config, project)
    #expect(try fileText(project) == text)

    config.configuration["pageTitle"] = .string("x")
    await #expect(throws: Helper.Failure.self) { try await write(config, project) }
    #expect(try fileText(project) == text, "a refused write leaves the file")
  }

  /// The other half of `special-*` and `anchors-*`: there an unchanged `.inf` survives the trip
  /// through JSON; here a changed one is written as it comes.
  @Test func aValueJSONCannotHoldIsReadAsNullAndReplacedWhenChanged() async throws {
    let project = try project("configuration:\n  pageTitle: a\n  ratio: .inf\nplugins: []\n")
    var config = try await read(project)
    #expect(config.configuration["ratio"] == .null)
    config.configuration["ratio"] = .number(2)
    try await write(config, project)
    #expect(try fileText(project) == "configuration:\n  pageTitle: a\n  ratio: 2\nplugins: []\n")
  }

  @Test func aSaveNamesThisProjectsFrames() async throws {
    let project = try project("plugins:\n  - source: /Users/else/Original/.quartz-gui/authored-frames/frame-a\n    enabled: true\n" +
                              "  - source: /Users/else/Original/.quartz-gui/authored-frames/frame-b\n    enabled: true\n")
    try FileManager.default.createDirectory(at: project.appendingPathComponent(".quartz-gui/authored-frames/frame-a"),
                                            withIntermediateDirectories: true)
    let config = try await read(project)
    try await write(config, project)
    let text = try fileText(project)
    #expect(text.contains("- source: \(project.path)/.quartz-gui/authored-frames/frame-a\n"))
    #expect(text.contains("- source: /Users/else/Original/.quartz-gui/authored-frames/frame-b\n"), "no frame-b here")
  }

  @Test func aHolderOfTheConfigLockCanSave() async throws {
    // projectPaths reads and writes under the lock and saves through write(): reentrant.
    let project = try project("configuration:\n  pageTitle: a\nplugins: []\n")
    try await ProjectLock.config.run(project.path) {
      var config = try await read(project)
      config.configuration["pageTitle"] = .string("b")
      try await write(config, project)
    }
    #expect(try fileText(project).contains("pageTitle: b"))
  }

  @Test func aHelperThatIsNotThereIsBrokenNotRefused() async throws {
    let project = try project("plugins: []\n")
    var runtime = Self.runtime
    runtime.helpers = scratch.url
    await #expect {
      try await ConfigFile.read(project: project, runtime: runtime)
    } throws: { error in
      guard case Helper.Failure.broken(let report)? = error as? Helper.Failure else { return false }
      return report.contains("yaml-edit.cjs")
    }
  }

  // MARK: pieces

  @Test func namesAreDerivedAsDeriveNameDoes() {
    let cases: [(JSONValue?, String?)] = [
      (.string("@quartz-community/explorer"), "explorer"),
      (.string("github:quartz-community/explorer#v2"), "explorer"),
      (.string("git+https://example.org/a/b.git"), "b.git"),
      (.string("github:git+x/y"), "y"),
      (.string("/abs/path/"), "/abs/path/"),
      (.string("#ref"), ""),
      (.object(JSONObject([("repo", .string("https://github.com/a/b.git"))])), "b"),
      (.object(JSONObject([("repo", .string("x")), ("name", .string("Benannt"))])), "Benannt"),
      (.object(JSONObject([("repo", .string("x/")), ("name", .string(""))])), ""),
      (.object(JSONObject([("subdir", .string("x"))])), nil),
      (.number(5), nil), (nil, nil)
    ]
    for (source, name) in cases { #expect(PluginEntry.derivedName(source) == name, "\(String(describing: source))") }
  }

  @Test func yamlReasonIsTheFirstLineWithoutItsColon() {
    #expect(ConfigFile.yamlReason("Missing closing \"quote at line 5, column 1:\n\n  baseUrl\n  ^\n") == "Missing closing \"quote at line 5, column 1")
    #expect(ConfigFile.yamlReason("Nested mappings are not allowed in compact mappings at line 3, column 18: \n") == "Nested mappings are not allowed in compact mappings at line 3, column 18")
  }

  @Test func ownFramePathIsFramePathsTs() throws {
    let project = try project(nil, name: "Kopie")
    try FileManager.default.createDirectory(at: project.appendingPathComponent(".quartz-gui/authored-frames/frame-x"),
                                            withIntermediateDirectories: true)
    let own = "\(project.path)/.quartz-gui/authored-frames/frame-x"
    #expect(FramePaths.ownFramePath(project: project, "/Users/a/Original/.quartz-gui/authored-frames/frame-x") == own)
    #expect(FramePaths.ownFramePath(project: project, "/Users/a/Original/.quartz-gui/authored-frames/frame-x/") == own)
    #expect(FramePaths.ownFramePath(project: project, "/Users/a/b/../Original/.quartz-gui/authored-frames/frame-x") == own)
    #expect(FramePaths.ownFramePath(project: project, "/Users/a/Original/.quartz-gui/authored-frames/frame-y") == nil, "not here")
    #expect(FramePaths.ownFramePath(project: project, own) == nil, "already ours")
    #expect(FramePaths.ownFramePath(project: project, "\(project.path)/./.quartz-gui/authored-frames/frame-x") == nil)
    #expect(FramePaths.ownFramePath(project: project, ".quartz-gui/authored-frames/frame-x") == nil, "relative")
    #expect(FramePaths.ownFramePath(project: project, "/Users/a/Original/frames/frame-x") == nil)
  }
}
