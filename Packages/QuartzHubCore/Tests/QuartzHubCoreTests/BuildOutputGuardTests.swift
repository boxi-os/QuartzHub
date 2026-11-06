import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own buildOutputGuard.ts: `scripts/build-output-golden.mjs` laid out each
/// case under a fresh folder W (home W/home) and wrote what `assessOutputDir` answered.
@Suite struct BuildOutputGuardTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/build-output/cases.json")

  /// Where QuartzHub answers otherwise, and why: a spelling or a link that reaches a refused folder
  /// (BuildOutputGuard.assess). QuartzControl asked "n entries?" there.
  static let deviations: [String: OutputDirVerdict] = [
    "case Content": .refused(.protected("content")),
    "case NODE_MODULES/x": .refused(.protected("node_modules")),
    "case HOME": .refused(.home),
    "link to content": .refused(.protected("content")),
    "below a link to content": .refused(.protected("content")),
    "link to home": .refused(.home),
    "link to the project": .refused(.project)
  ]

  static func verdict(_ json: JSONValue) -> OutputDirVerdict? {
    switch json["kind"]?.stringValue {
    case "ok": return .ok
    case "confirm": return json["entryCount"]?.numberValue.map { .confirm(entryCount: Int($0)) }
    case "refused":
      switch json["reason"]?.stringValue {
      case "project": return .refused(.project)
      case "containsProject": return .refused(.containsProject)
      case "home": return .refused(.home)
      case "protected": return json["detail"]?.stringValue.map { .refused(.protected($0)) }
      default: return nil
      }
    default: return nil
    }
  }

  /// A fresh W, by its real path as the script took it.
  static func workspace() throws -> URL {
    let made = FileManager.default.temporaryDirectory.appendingPathComponent("qh-output-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
    return URL(fileURLWithPath: BuildOutputGuard.realPath(made.path))
  }

  static func cleanUp(_ w: URL, _ tree: JSONValue) {
    for key in tree.objectValue?.keys ?? [] where tree[key]?["dir"] != nil { chmod(w.appendingPathComponent(key).path, 0o755) }
    try? FileManager.default.removeItem(at: w)
  }

  @Test func sameAsQuartzControl() throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixture))
    let cases = try #require(spec["assess"]?.arrayValue)
    #expect(cases.count == 44, "scripts/build-output-golden.mjs")
    var deviated: Set<String> = []
    for item in cases {
      let name = item["name"]!.stringValue!
      let w = try Self.workspace()
      let tree = item["tree"]!
      let fill = { (text: String) in text.replacingOccurrences(of: "@W@", with: w.path) }
      try ProjectDuplicatorTests.layOut(spec["project"]!, at: w, fill)
      try ProjectDuplicatorTests.layOut(tree, at: w, fill)
      let verdict = BuildOutputGuard.assess(project: w.appendingPathComponent(item["project"]!.stringValue!).path,
                                            outputDir: item["outputDir"]?.stringValue.map(fill),
                                            home: w.appendingPathComponent("home").path)
      Self.cleanUp(w, tree)
      let quartzControl = try #require(Self.verdict(item["expected"]!), "\(name)")
      if let ours = Self.deviations[name] {
        deviated.insert(name)
        #expect(verdict == ours, "\(name)")
        #expect(quartzControl != ours, "\(name): QuartzControl answers the same now")
      } else {
        #expect(verdict == quartzControl, "\(name)")
      }
    }
    #expect(deviated == Set(Self.deviations.keys))
  }

  @Test func looksLikeABuildAsQuartzControl() throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixture))
    let cases = try #require(spec["looks"]?.arrayValue)
    #expect(cases.count == 6)
    for item in cases {
      let w = try Self.workspace()
      defer { try? FileManager.default.removeItem(at: w) }
      try ProjectDuplicatorTests.layOut(item["tree"]!, at: w.appendingPathComponent("d")) { $0 }
      #expect(BuildOutputGuard.looksLikeQuartzBuild(w.appendingPathComponent("d").path) == item["expected"]?.boolValue,
              "\(item["name"]!.stringValue!)")
    }
  }

  /// A folder that does not exist yet behind a link: the real path is the link's target plus the
  /// rest, so it is still inside `content`. Quartz's rm deletes nothing there, but its build then
  /// writes the site into the notes.
  @Test func aNewFolderBehindALinkIsStillInside() throws {
    let w = try Self.workspace()
    defer { try? FileManager.default.removeItem(at: w) }
    let project = w.appendingPathComponent("proj")
    try FileManager.default.createDirectory(at: project.appendingPathComponent("content"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: project.appendingPathComponent("site").path,
                                               withDestinationPath: project.appendingPathComponent("content").path)
    #expect(BuildOutputGuard.assess(project: project.path, outputDir: "site/new/deeper", home: w.path) == .refused(.protected("content")))
    #expect(BuildOutputGuard.assess(project: project.path, outputDir: "Site/new", home: w.path) == .refused(.protected("content")))
    #expect(BuildOutputGuard.assess(project: project.path, outputDir: "elsewhere/new", home: w.path) == .ok)
  }

  @Test func theBuildDirectoryIsResolveBuildDir() {
    #expect(BuildOutputGuard.buildDirectory(project: "/p/proj", outputDir: nil) == "/p/proj/public")
    #expect(BuildOutputGuard.buildDirectory(project: "/p/proj", outputDir: "") == "/p/proj/public")
    #expect(BuildOutputGuard.buildDirectory(project: "/p/proj", outputDir: "../site/") == "/p/site")
    #expect(BuildOutputGuard.buildDirectory(project: "/p/proj", outputDir: "/export") == "/export")
    #expect(BuildOutputGuard.realPath("/nowhere-\(UUID().uuidString)/a/b").hasSuffix("/a/b"))
  }
}
