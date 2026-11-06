import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct QuartzGuiWriterTests {
  /// One per test (Swift Testing makes a suite instance for each), so the folder lives as long
  /// as the test does. A scratch bound to `_` is released, and its folder deleted, at once.
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  func project(_ name: String = "Gr\u{FC}ner Garten", git: Bool = true, gitignore: Data? = nil) throws -> QuartzGuiDirectory {
    let path = try scratch.dir(name)
    if git { _ = try scratch.dir("\(name)/.git") }
    if let gitignore { try Posix.write("\(path)/.gitignore", gitignore) }
    return QuartzGuiDirectory(project: path)
  }

  static func gitignore(_ dir: QuartzGuiDirectory) -> Data? { try? Posix.read("\(dir.project)/.gitignore") }

  static var block: String { "\n# \(L10n.t("main.gitignoreComment"))\n.quartz-gui/\n" }

  @Test func createsTheFolderAndTheRuleOnce() throws {
    let dir = try project()
    let logs = try dir.create("logs", "\u{DC}bersicht")
    #expect(Array(logs.utf8) == Array("\(scratch.path)/Gr\u{FC}ner Garten/.quartz-gui/logs/\u{DC}bersicht".utf8))
    #expect(Posix.entries("\(dir.path)/logs")?.map { Array($0.name.utf8) } == [Array("\u{DC}bersicht".utf8)], "made composed")
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
    try Posix.write("\(worktree.project)/.git", Data("gitdir: /x/.git/worktrees/y\n".utf8))
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
    let shared = "\(scratch.path)/geteilte-\u{C4}nderung"
    try Posix.write(shared, Data("public\n".utf8))
    try Posix.symlink(shared, "\(dir.project)/.gitignore")
    try dir.create()
    #expect(Array(try Posix.readlink("\(dir.project)/.gitignore").utf8) == Array(shared.utf8))
    #expect(try Posix.read(shared) == Data(("public\n" + Self.block).utf8))
  }
}
