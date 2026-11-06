import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct ProjectPrefsStoreTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  var project: String { scratch.path }
  var file: String { QuartzGuiDirectory(project: project).projectPrefs }

  func put(_ text: String) throws {
    try Posix.mkdirs(NodePath.dirname(file))
    try Posix.write(file, Data(text.utf8))
  }

  @Test func readingCreatesNothing() {
    #expect(ProjectPrefsStore.read(project: project).outputDir == "")
    #expect(!Posix.exists(QuartzGuiDirectory(project: project).path))
  }

  @Test func theFixtureRoundTripsByteForByte() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/quartz-gui/gui-test/project-prefs.json")
    let bytes = try Data(contentsOf: fixture)
    try put(String(decoding: bytes, as: UTF8.self))
    try ProjectPrefsStore.write(ProjectPrefsStore.read(project: project), project: project)
    #expect(try Posix.read(file) == bytes)
  }

  @Test func anOutputDirThatIsNoStringIsEmptyAndAListIsMovedAside() throws {
    try put("{\"outputDir\": 3}")
    #expect(ProjectPrefsStore.read(project: project).outputDir == "")
    try put("[\"out\"]")
    #expect(ProjectPrefsStore.read(project: project).outputDir == "")
    let names = try FileManager.default.contentsOfDirectory(atPath: NodePath.dirname(file))
    #expect(names.contains { $0.hasPrefix("project-prefs.json.corrupt-") }, "\(names)")
  }

  @Test func updateKeepsWhatItDoesNotKnowAndIgnoresTheFolder() throws {
    _ = try scratch.dir(".git")
    try put("{\n  \"later\": [1],\n  \"outputDir\": \"\"\n}")
    try ProjectPrefsStore.update(project: project) { $0.outputDir = "/Users/x/Export" }
    #expect(String(decoding: try Posix.read(file), as: UTF8.self) == "{\n  \"later\": [\n    1\n  ],\n  \"outputDir\": \"/Users/x/Export\"\n}")
    #expect(String(decoding: try Posix.read("\(project)/.gitignore"), as: UTF8.self).hasSuffix("\n.quartz-gui/\n"))
  }

  /// Node's `resolveBuildDir('/p/proj', outputDir)`, trailing slash dropped (`BuildOutputGuard.resolve`).
  @Test(arguments: [
    ("", "/p/proj/public"), ("out", "/p/proj/out"), ("../site", "/p/site"), ("./a/./b", "/p/proj/a/b"),
    ("out/", "/p/proj/out"), ("/abs/x", "/abs/x"), ("/abs/../y", "/abs/../y")
  ])
  func buildDirectoryIsResolveBuildDir(outputDir: String, node: String) {
    var prefs = ProjectPrefs(object: JSONObject())
    prefs.outputDir = outputDir
    #expect(prefs.buildDirectory(project: "/p/proj") == node)
  }
}
