import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct QuartzGuiWriterTests {
  /// One per test (Swift Testing makes a suite instance for each), so the folder lives as long
  /// as the test does. A scratch bound to `_` is released, and its folder deleted, at once.
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  func project(_ name: String = "project", git: Bool = true, gitignore: Data? = nil) throws -> QuartzGuiDirectory {
    let url = URL(fileURLWithPath: try scratch.dir(name))
    if git { _ = try scratch.dir("\(name)/.git") }
    if let gitignore { try gitignore.write(to: url.appendingPathComponent(".gitignore")) }
    return QuartzGuiDirectory(project: url)
  }

  static func gitignore(_ dir: QuartzGuiDirectory) -> Data? {
    try? Data(contentsOf: dir.project.appendingPathComponent(".gitignore"))
  }

  static var block: String { "\n# \(L10n.t("main.gitignoreComment"))\n.quartz-gui/\n" }

  @Test func createsTheFolderAndTheRuleOnce() throws {
    let dir = try project()
    let logs = try dir.create("logs")
    #expect(logs.path == dir.url.appendingPathComponent("logs").path)
    #expect(FileManager.default.fileExists(atPath: logs.path))
    #expect(Self.gitignore(dir) == Data(Self.block.utf8))
    try dir.create()
    #expect(Self.gitignore(dir) == Data(Self.block.utf8), "the rule was written twice")
  }

  @Test func noRepositoryNoGitignore() throws {
    let dir = try project(git: false)
    try dir.create()
    #expect(Self.gitignore(dir) == nil)
    // A worktree's .git is a file, and it is a repository all the same.
    let worktree = try project("worktree", git: false)
    try Data("gitdir: /x/.git/worktrees/y\n".utf8).write(to: worktree.project.appendingPathComponent(".git"))
    try worktree.create()
    #expect(Self.gitignore(worktree) == Data(Self.block.utf8))
  }

  @Test(arguments: [".quartz-gui/", ".quartz-gui", "  .quartz-gui/\r", "\u{FEFF}.quartz-gui/"])
  func anExistingRuleCounts(line: String) throws {
    let original = Data("node_modules\n\(line)\npublic\n".utf8)
    let dir = try project(gitignore: original)
    try dir.create()
    #expect(Self.gitignore(dir) == original)
  }

  @Test(arguments: ["!.quartz-gui/keep", "# .quartz-gui/", ".quartz-gui/logs"])
  func aLineThatOnlyContainsTheNameDoesNot(line: String) throws {
    let original = Data("\(line)\n".utf8)
    let dir = try project(gitignore: original)
    try dir.create()
    #expect(Self.gitignore(dir) == original + Data(Self.block.utf8))
  }

  @Test func appendsAfterAMissingNewlineAndKeepsBytesThatAreNotText() throws {
    // "public" and a Latin-1 "ü" (0xFC), no final newline.
    let original = Data([0x70, 0x75, 0x62, 0x6C, 0x69, 0x63, 0x0A, 0xFC])
    let dir = try project(gitignore: original)
    try dir.create()
    #expect(Self.gitignore(dir) == original + Data(("\n" + Self.block).utf8))
  }

  @Test func aGitignoreThatIsALinkStaysOne() throws {
    let dir = try project()
    let shared = scratch.url.appendingPathComponent("shared-ignore")
    try Data("public\n".utf8).write(to: shared)
    try FileManager.default.createSymbolicLink(at: dir.project.appendingPathComponent(".gitignore"), withDestinationURL: shared)
    try dir.create()
    let link = try FileManager.default.destinationOfSymbolicLink(atPath: dir.project.appendingPathComponent(".gitignore").path)
    #expect(link == shared.path)
    #expect(try Data(contentsOf: shared) == Data(("public\n" + Self.block).utf8))
  }
}
