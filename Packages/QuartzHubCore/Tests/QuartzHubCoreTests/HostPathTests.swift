import Foundation
import Testing
@testable import QuartzHubCore

/// `HostPath` against fake shells, fake gits and a fake `xcode-select`, so each branch of
/// `ensureToolPath` is taken on purpose. One test asks the real login shell.
@Suite struct HostPathTests {
  /// A scratch folder with executable scripts in it.
  final class Scratch {
    /// With the bytes on disk; `url.path` is the same folder decomposed, as Foundation hands it on.
    let path: String
    var url: URL { URL(fileURLWithPath: path) }

    /// `umlaut`: a name with a composed "ä" and "Ü" (`TestFolder`), for the tests of services that
    /// take string paths; the others follow as their service moves (NFD pass, until it is the only kind).
    init(umlaut: Bool = false) throws { path = TestFolder.make("qh-scratch", umlaut: umlaut) }
    deinit { try? FileManager.default.removeItem(atPath: path) }

    @discardableResult
    func script(_ relative: String, _ body: String) throws -> String {
      let file = url.appendingPathComponent(relative)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try "#!/bin/sh\n\(body)\n".write(to: file, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
      return file.path
    }

    func dir(_ relative: String) throws -> String {
      let directory = url.appendingPathComponent(relative)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory.path
    }
  }

  @Test func inheritedPathWithGitIsKept() async throws {
    let scratch = try Scratch()
    try scratch.script("tools/git", "echo 'git version 9'")
    let shell = try scratch.script("shell", "echo should-not-run > \(scratch.url.path)/ran")
    let path = await HostPath.resolve(["PATH": scratch.url.path + "/tools", "SHELL": shell], candidates: [])
    #expect(path.source == .inherited)
    #expect(path.added.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: scratch.url.path + "/ran"))
  }

  @Test func loginShellFillsTheGap() async throws {
    let scratch = try Scratch()
    let tools = try scratch.dir("tools")
    try scratch.script("tools/git", "echo 'git version 9'")
    let other = try scratch.dir("other")
    // Greeting noise, the marker line, a doubled directory, and one that does not exist.
    let shell = try scratch.script("shell", #"echo "Welcome!"; printf "__QH_PATH__%s\n" "/bin:\#(other):\#(tools):\#(other):/does/not/exist""#)
    let path = await HostPath.resolve(["PATH": "/bin:/sbin", "SHELL": shell], candidates: [])
    #expect(path.source == .loginShell)
    #expect(path.added == [other, tools])
    #expect(path.entries == ["/bin", "/sbin", other, tools])
    #expect(path.find("git") == tools + "/git")
  }

  @Test func candidatesComeLastAndSayProbed() async throws {
    let scratch = try Scratch()
    let brew = try scratch.dir("brew")
    try scratch.script("brew/git", "echo 'git version 9'")
    let shell = try scratch.script("shell", "exit 1")
    let path = await HostPath.resolve(["PATH": "/bin", "SHELL": shell], candidates: ["/does/not/exist", brew])
    #expect(path.source == .probed)
    #expect(path.added == [brew])
  }

  @Test func nothingFoundStaysInherited() async throws {
    let scratch = try Scratch()
    let empty = try scratch.dir("empty")
    let shell = try scratch.script("shell", "sleep 30") // the 5 s deadline ends it
    let clock = ContinuousClock(), start = clock.now
    let path = await HostPath.resolve(["PATH": "/bin", "SHELL": shell], candidates: [empty])
    #expect(clock.now - start < .seconds(8))
    #expect(path.source == .inherited)
    #expect(path.added == [empty])
  }

  @Test func theStubIsNotGit() async throws {
    let scratch = try Scratch()
    let noTools = try scratch.script("xcode-select-missing", "exit 2")
    let tools = try scratch.script("xcode-select-ok", "echo /Library/Developer/CommandLineTools")
    #expect(await HostPath.isCommandLineToolsStub("/usr/bin/git", xcodeSelect: noTools))
    #expect(!(await HostPath.isCommandLineToolsStub("/usr/bin/git", xcodeSelect: tools)))
    // Only /usr/bin/git is the stub; a Homebrew git is never asked about.
    #expect(!(await HostPath.isCommandLineToolsStub("/opt/homebrew/bin/git", xcodeSelect: noTools)))

    // The stub first on PATH hides every later git, as in QuartzControl: children call git by
    // name and would get the stub. The search still adds what it found; gitRuntime then takes
    // the bundled git and puts it in front.
    let brew = try scratch.dir("brew")
    try scratch.script("brew/git", "echo 'git version 9'")
    let shell = try scratch.script("shell", #"printf "__QH_PATH__%s\n" "\#(brew)""#)
    let path = await HostPath.resolve(["PATH": "/usr/bin:/bin", "SHELL": shell], xcodeSelect: noTools, candidates: [])
    #expect(path.source == .inherited)
    #expect(path.added == [brew])
    #expect(await path.usableGit(xcodeSelect: noTools) == nil)
    let real = await HostPath.resolve(["PATH": "/usr/bin:/bin", "SHELL": shell], xcodeSelect: tools, candidates: [])
    #expect(real.source == .inherited && real.added.isEmpty)
  }

  @Test func findSkipsOneDirectory() async throws {
    let scratch = try Scratch()
    let ours = try scratch.dir("ours"), theirs = try scratch.dir("theirs")
    try scratch.script("ours/node", "echo ours")
    try scratch.script("theirs/node", "echo theirs")
    let path = HostPath(entries: [ours, theirs], source: .inherited, added: [])
    #expect(path.find("node") == ours + "/node")
    #expect(path.find("node", skipping: ours) == theirs + "/node")
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["SHELL"] != nil))
  func theRealLoginShellAnswers() async {
    let entries = await HostPath.loginShellPath(ProcessInfo.processInfo.environment)
    #expect(entries.contains("/usr/bin"), "\(entries)")
  }
}
