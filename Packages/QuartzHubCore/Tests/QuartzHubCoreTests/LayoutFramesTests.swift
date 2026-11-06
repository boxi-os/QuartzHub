import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own layoutFrameService.ts and gridFrameCss.ts: `scripts/layout-frames-
/// golden.mjs` ran them on real frames (gui-test, Example) and made-up edges and recorded what they
/// wrote and answered. Here the same inputs go through LayoutFrames, byte for byte.
@Suite struct LayoutFramesTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/layout-frames")
  static var writeCases: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixtures.appendingPathComponent("write").path)) ?? [])
      .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
  }

  static func fixture(_ name: String) throws -> JSONValue {
    try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent(name)))
  }

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  @Test func thereAreCases() {
    #expect(Self.writeCases.count >= 15, "scripts/layout-frames-golden.mjs")
  }

  // MARK: writeAllFrames

  @Test(arguments: writeCases)
  func writesWhatQuartzControlWrote(_ name: String) async throws {
    let golden = try Self.fixture("write/\(name).json")
    let project = scratch.url.appendingPathComponent("p")
    try Self.layOut(golden, at: project)
    let frames = LayoutFrames(readConfig: Self.config(golden["config"]!))
    let problems = await frames.writeAllFrames(project: project)
    #expect(problems == (golden["problems"]?.arrayValue ?? []).map { QC.render($0.stringValue!, mask: project.path) }, "\(name)")
    let written = Self.files(project.appendingPathComponent(".quartz-gui"), mask: project.path)
    let expected = Self.normalize(golden["files"]!.objectValue!)
    #expect(written.keys.sorted() == expected.keys.sorted(), "\(name)")
    for key in expected.keys.sorted() where written[key] != expected[key] {
      Issue.record("\(name): \(key) differs\n\(firstDifference(written[key] ?? "", expected[key]!))")
    }
  }

  /// A frame whose module cannot be made keeps its old files and gets no temporary ones; the
  /// frames after it in the list are not written (QuartzControl's loop stopped there too).
  @Test func aBrokenFrameLeavesNoTemporaryFiles() async throws {
    let golden = try Self.fixture("write/shape-breaks-the-write.json")
    let project = scratch.url.appendingPathComponent("p")
    try Self.layOut(golden, at: project)
    _ = await LayoutFrames(readConfig: Self.config(golden["config"]!)).writeAllFrames(project: project)
    let all = Self.files(project.appendingPathComponent(".quartz-gui"), mask: project.path, keepTemporary: true)
    #expect(all.keys.sorted() == ["authored-frames/frame-bad/frame.json", "authored-frames/frame-made/frame.json"])
  }

  /// A span of a million rows is the same cells as a span of one: the loops skip what cannot land.
  @Test func aHugeSpanDoesNotHang() throws {
    let def = try JSJSON.parse(#"{"frameName":"x","areas":[{"id":"a","name":"n"}],"breakpoints":{"desktop":{"rows":1,"cols":1,"placements":{"a":{"row":-1e9,"col":1,"rowSpan":2e9,"colSpan":1e12}}},"tablet":{"rows":1,"cols":1,"placements":{}},"mobile":{"rows":1,"cols":1,"placements":{}}}}"#)
    let css = try GridFrameCss.frameCss(def, widths: FrameBreakpointWidths.defaults)
    #expect(css.contains("\"n\""))
  }

  /// The build door: the second preparation step rewrites the frames with the real config reader,
  /// and says in the console that it could not read the groups (here: no quartz.config.yaml).
  @Test func theBuildDoorRewritesTheFrames() async throws {
    let golden = try Self.fixture("write/made-default-widths.json")
    let project = scratch.url.appendingPathComponent("door")
    try Self.layOut(golden, at: project)
    let said = Mutex<[String]>([])
    for step in BuildService.preparation {
      await step(project) { stream, text in said.withLock { $0.append("\(stream) \(text)") } }
    }
    let module = project.appendingPathComponent(".quartz-gui/authored-frames/frame-made/dist/frames.js")
    #expect(FileManager.default.fileExists(atPath: module.path))
    let expected = L10n.t("main.frameGroupsUnreadable", ["error": "Error: " + L10n.t("main.configMissing")])
    #expect(said.withLock { $0 } == ["warn \(expected)\n"])
  }

  // MARK: save, delete, widths

  @Test func saveAndDeleteAsQuartzControl() async throws {
    let golden = try Self.fixture("save.json")
    let project = scratch.url.appendingPathComponent("save")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let made = try Self.fixture("write/made-default-widths.json")
    let calls = Mutex<[[String]]>([])
    let answer = Mutex(PluginCommands.Result(success: true, output: "cli says ok"))
    let frames = LayoutFrames(readConfig: Self.config(made["config"]!), plugins: LayoutFrames.Plugins(
      add: { source, _, snapshot in calls.withLock { $0.append([snapshot ? "add" : "install", source]) }; return answer.withLock { $0 } },
      remove: { name, _ in calls.withLock { $0.append(["remove", name]) }; return answer.withLock { $0 } }))
    let def = try JSJSON.parse(made["frames"]!["frame-made"]!.stringValue!)
    func with(_ key: String, _ value: JSONValue) -> JSONValue {
      var object = def.objectValue!
      object[key] = value
      return .object(object)
    }
    let legacy = try JSJSON.parse(#"{"id":"frame-old","frameName":"old","rows":1,"cols":1,"gap":"0","areas":[{"id":"x","name":"only","slot":"pageBody","row":1,"col":1,"rowSpan":1,"colSpan":1}]}"#)
    let steps: [(String, () async throws -> PluginCommands.Result?)] = [
      ("new frame registers", { try await frames.saveFrame(def, project: project) }),
      ("existing frame only rewrites", { try await frames.saveFrame(with("frameName", .string("renamed")), project: project) }),
      ("new frame without snapshot installs", { try await frames.saveFrame(with("id", .string("frame-two")), project: project, snapshot: false) }),
      ("legacy definition is migrated", { try await frames.saveFrame(legacy, project: project) }),
      ("a problem writes nothing", { try await frames.saveFrame(with("id", .string("frame-three")).replacingAreas(
        #"[{"id":"a","name":"twice"},{"id":"b","name":"twice"}]"#), project: project) }),
      ("widths rewrite every frame", { try await frames.saveWidths((tablet: 1000, mobile: 600), project: project); return nil }),
      ("delete", { try await frames.deleteFrame(id: "frame-two", project: project) }),
      ("delete with a bad id throws", { try await frames.deleteFrame(id: "../x", project: project) }),
      ("a failing add keeps the files", {
        answer.withLock { $0 = PluginCommands.Result(success: false, output: "cli failed") }
        return try await frames.saveFrame(with("id", .string("frame-four")), project: project)
      })
    ]
    let expected = golden.arrayValue ?? []
    #expect(expected.count == steps.count)
    for (index, (label, run)) in steps.enumerated() {
      let step = expected[index]
      #expect(step["label"] == .string(label))
      calls.withLock { $0 = [] }
      do {
        let result = try await run()
        #expect(result?.success == step["result"]?["success"]?.boolValue, "\(label)")
        #expect(result?.output == step["result"]?["output"]?.stringValue.map { QC.render($0, mask: "") }, "\(label)")
      } catch {
        let threw = step["result"]?["threw"]?.stringValue.map { QC.render($0, mask: project.path) }
        #expect(LayoutFrames.errorText(error) == threw, "\(label)")
      }
      // The golden script masked the folder the project sits in.
      let made = calls.withLock { $0 }.map { JSONValue.array($0.map { .string(QC.mask($0, scratch.url.path)) }) }
      #expect(.array(made) == step["calls"], "\(label)")
      let written = Self.files(project.appendingPathComponent(".quartz-gui"), mask: project.path)
      #expect(written == Self.normalize(step["files"]!.objectValue!), "\(label)")
    }
  }

  @Test func widthsAsQuartzControlReadsThem() throws {
    for entry in try Self.fixture("widths.json").arrayValue ?? [] {
      let project = scratch.url.appendingPathComponent("w-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: project.appendingPathComponent(".quartz-gui"), withIntermediateDirectories: true)
      if let text = entry["file"]?.stringValue {
        try Data(text.utf8).write(to: project.appendingPathComponent(".quartz-gui/layout-breakpoints.json"))
      }
      let widths = LayoutFrames.widths(project: project)
      #expect(.number(widths.tablet) == entry["widths"]?["tablet"] && .number(widths.mobile) == entry["widths"]?["mobile"], "\(entry["file"] ?? .null)")
    }
  }

  // MARK: the check and the orderings

  @Test func problemsAsQuartzControl() throws {
    let cases = try Self.fixture("problems.json").arrayValue ?? []
    #expect(cases.count > 50)
    for entry in cases {
      let expected = entry["problem"]?.stringValue.map { QC.render($0, mask: "") }
      #expect(LayoutFrames.problem(entry["input"]) == expected, "\(entry["label"]!)")
    }
  }

  @Test func candidatesAsQuartzControl() throws {
    for entry in try Self.fixture("candidates.json").arrayValue ?? [] {
      let config = entry["config"]!
      let plugins = (config["plugins"]?.arrayValue ?? []).compactMap(\.objectValue)
      let found = try GroupLayouts.candidates(plugins: plugins, layout: config["layout"]?.objectValue, frameName: entry["frameName"])
      #expect(JSONValue.array(found.map(\.json)) == entry["candidates"], "\(entry["label"]!)")
    }
  }

  // MARK: helpers

  static func config(_ value: JSONValue) -> LayoutFrames.ReadConfig {
    if let error = value["error"]?.stringValue {
      return { _ in throw Failure(text: String(error.dropFirst("Error: ".count))) }
    }
    let object = value.objectValue ?? JSONObject()
    let config = QuartzConfig(
      configuration: object["configuration"]?.objectValue ?? JSONObject(), theme: object["theme"]?.objectValue ?? JSONObject(),
      plugins: (object["plugins"]?.arrayValue ?? []).compactMap(\.objectValue).map(PluginEntry.init(object:)),
      layout: object["layout"]?.objectValue)
    return { _ in config }
  }

  struct Failure: Error, CustomStringConvertible {
    let text: String
    var description: String { text }
  }

  static func layOut(_ golden: JSONValue, at project: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: project, withIntermediateDirectories: true)
    let frames = golden["frames"]?.objectValue ?? JSONObject()
    for id in frames.keys {
      let dir = project.appendingPathComponent(".quartz-gui/authored-frames/\(id)")
      try manager.createDirectory(at: dir, withIntermediateDirectories: true)
      try Data(frames[id]!.stringValue!.utf8).write(to: dir.appendingPathComponent("frame.json"))
    }
    let extra = golden["extraFiles"]?.objectValue ?? JSONObject()
    for path in extra.keys {
      let url = project.appendingPathComponent(path)
      try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(extra[path]!.stringValue!.utf8).write(to: url)
    }
    if let text = golden["breakpoints"]?.stringValue {
      try manager.createDirectory(at: project.appendingPathComponent(".quartz-gui"), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: project.appendingPathComponent(".quartz-gui/layout-breakpoints.json"))
    }
  }

  /// Every file under `root`, by relative path; temporary files of an atomic write left out, the
  /// time in a quarantined file's name masked.
  static func files(_ root: URL, mask: String, keepTemporary: Bool = false) -> [String: String] {
    var result: [String: String] = [:]
    let base = root.resolvingSymlinksInPath().path
    guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [:] }
    while let relative = walker.nextObject() as? String {
      var isDirectory: ObjCBool = false
      let full = root.appendingPathComponent(relative)
      guard FileManager.default.fileExists(atPath: full.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
      if !keepTemporary && relative.contains(".tmp-") { continue }
      let text = (try? String(contentsOf: full, encoding: .utf8)) ?? "<binary>"
      result[normalizeName(relative)] = QC.mask(QC.mask(text, base.replacingOccurrences(of: "/.quartz-gui", with: "", options: .literal)), mask)
    }
    return result
  }

  static func normalize(_ files: JSONObject) -> [String: String] {
    var result: [String: String] = [:]
    for key in files.keys where !key.contains(".tmp-") { result[normalizeName(key)] = files[key]!.stringValue! }
    return result
  }

  static func normalizeName(_ name: String) -> String {
    guard let at = name.range(of: ".corrupt-") else { return name }
    return String(name[..<at.upperBound]) + "*"
  }
}

private extension JSONValue {
  func replacingAreas(_ json: String) -> JSONValue {
    var object = objectValue!
    object["areas"] = try! JSJSON.parse(json)
    return .object(object)
  }
}

func firstDifference(_ a: String, _ b: String) -> String {
  let x = Array(a), y = Array(b)
  var index = 0
  while index < min(x.count, y.count) && x[index] == y[index] { index += 1 }
  let from = max(0, index - 80)
  return "at \(index):\n  got      …\(String(x[from..<min(x.count, index + 80)]))\n  expected …\(String(y[from..<min(y.count, index + 80)]))"
}

/// QuartzControl's texts as the golden scripts recorded them: the `mainT` stand-in answers
/// `{"key":…,"args":…}`, here rendered with the catalog (`main.` + key), arguments too, so a
/// sentence inside a sentence comes out as the app would write it.
enum QC {
  static func render(_ text: String, mask project: String) -> String {
    let units = Array(text.utf16)
    var out = "", index = 0
    while let start = JSText.indexOf(text, "{\"key\":", from: index) {
      out += JSText.slice(text, index, start)
      // The end of this object: braces outside strings, counted.
      var depth = 0, inString = false, escaped = false, end = start
      for i in start..<units.count {
        let unit = units[i]
        if inString {
          if escaped { escaped = false } else if unit == 0x5C { escaped = true } else if unit == 0x22 { inString = false }
          continue
        }
        if unit == 0x22 { inString = true } else if unit == 0x7B { depth += 1 } else if unit == 0x7D {
          depth -= 1
          if depth == 0 { end = i + 1; break }
        }
      }
      guard end > start, let stub = try? JSJSON.parse(JSText.slice(text, start, end)), let key = stub["key"]?.stringValue else {
        return out + JSText.slice(text, start)
      }
      var args: [String: String] = [:]
      let given = stub["args"]?.objectValue ?? JSONObject()
      for name in given.keys { args[name] = render(JS.string(given[name]!), mask: project) }
      out += L10n.t("main.\(key)", args)
      index = end
    }
    return out + JSText.slice(text, index)
  }

  static func mask(_ text: String, _ path: String) -> String {
    path.isEmpty ? text : text.replacingOccurrences(of: path, with: "@P@", options: .literal)
  }
}
