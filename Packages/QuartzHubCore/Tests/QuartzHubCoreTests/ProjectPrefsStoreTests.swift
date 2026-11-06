import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct ProjectPrefsStoreTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  var project: URL { scratch.url }
  var file: URL { QuartzGuiDirectory(project: project).projectPrefs }

  func put(_ text: String) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  @Test func readingCreatesNothing() {
    #expect(ProjectPrefsStore.read(project: project).outputDir == "")
    #expect(!FileManager.default.fileExists(atPath: QuartzGuiDirectory(project: project).url.path))
  }

  @Test func theFixtureRoundTripsByteForByte() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/quartz-gui/gui-test/project-prefs.json")
    let bytes = try Data(contentsOf: fixture)
    try put(String(decoding: bytes, as: UTF8.self))
    try ProjectPrefsStore.write(ProjectPrefsStore.read(project: project), project: project)
    #expect(try Data(contentsOf: file) == bytes)
  }

  @Test func anOutputDirThatIsNoStringIsEmptyAndAListIsMovedAside() throws {
    try put("{\"outputDir\": 3}")
    #expect(ProjectPrefsStore.read(project: project).outputDir == "")
    try put("[\"out\"]")
    #expect(ProjectPrefsStore.read(project: project).outputDir == "")
    let names = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
    #expect(names.contains { $0.hasPrefix("project-prefs.json.corrupt-") }, "\(names)")
  }

  @Test func updateKeepsWhatItDoesNotKnowAndIgnoresTheFolder() throws {
    _ = try scratch.dir(".git")
    try put("{\n  \"later\": [1],\n  \"outputDir\": \"\"\n}")
    try ProjectPrefsStore.update(project: project) { $0.outputDir = "/Users/x/Export" }
    #expect(try String(contentsOf: file, encoding: .utf8) == "{\n  \"later\": [\n    1\n  ],\n  \"outputDir\": \"/Users/x/Export\"\n}")
    #expect(try String(contentsOf: project.appendingPathComponent(".gitignore"), encoding: .utf8).hasSuffix("\n.quartz-gui/\n"))
  }

  /// Node's `resolveBuildDir('/p/proj', outputDir)`, trailing slash dropped (URL does).
  @Test(arguments: [
    ("", "/p/proj/public"), ("out", "/p/proj/out"), ("../site", "/p/site"), ("./a/./b", "/p/proj/a/b"),
    ("out/", "/p/proj/out"), ("/abs/x", "/abs/x"), ("/abs/../y", "/abs/../y")
  ])
  func buildDirectoryIsResolveBuildDir(outputDir: String, node: String) {
    var prefs = ProjectPrefs(object: JSONObject())
    prefs.outputDir = outputDir
    #expect(prefs.buildDirectory(project: URL(fileURLWithPath: "/p/proj")).path == node)
  }
}
