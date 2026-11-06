import Foundation
import Testing
@testable import QuartzHubCore

/// Node, git and the children's environment against the real `Runtime/` of the repository, and the
/// failure branches against fake bundles.
@Suite struct ToolEnvironmentTests {
  static let runtime = RuntimeLocation.repository
  static let hasRuntime = FileManager.default.isExecutableFile(atPath: "\(runtime.nodeBin)/node")
    && FileManager.default.isExecutableFile(atPath: "\(runtime.git)/bin/git")
  /// A PATH without any node or Homebrew git, like an app started from the Dock.
  static let launchd = HostPath(entries: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"], source: .inherited, added: [])
  static let base = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

  static func environment(_ mode: ToolEnvironment.NodeMode, git: GitRuntime? = nil) -> ToolEnvironment {
    ToolEnvironment(base: base, hostPath: launchd, nodeMode: mode, runtime: runtime, git: git, bundledGitFailure: nil)
  }

  static func bundledGit() -> GitRuntime {
    GitRuntime(source: .bundled, path: "\(runtime.git)/bin/git", version: "git version 2.53.0", variables: [
      "GIT_EXEC_PATH": "\(runtime.git)/libexec/git-core",
      "GIT_TEMPLATE_DIR": "\(runtime.git)/share/git-core/templates"
    ])
  }

  @Test func pathPutsNodeThenBundledGitInFront() {
    let bundled = Self.bundledGit()
    let embedded = Self.environment(.embedded, git: bundled)
    #expect(embedded.path == [Self.runtime.nodeBin, "\(Self.runtime.git)/bin"] + Self.launchd.entries)
    #expect(embedded.variables["GIT_EXEC_PATH"] == bundled.variables["GIT_EXEC_PATH"])
    #expect(embedded.variables["HOME"] == NSHomeDirectory())
    let system = embedded.with(nodeMode: .system)
    #expect(system.path == ["\(Self.runtime.git)/bin"] + Self.launchd.entries)
    let host = Self.environment(.embedded, git: GitRuntime(source: .host, path: "/usr/bin/git", version: "x", variables: [:]))
    #expect(host.path == [Self.runtime.nodeBin] + Self.launchd.entries)
    #expect(host.variables["GIT_EXEC_PATH"] == nil)
  }

  @Test(.enabled(if: hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
  func embeddedNodeServesNpmWithoutAnyOtherNode() async {
    let environment = Self.environment(.embedded)
    #expect(Self.launchd.find("node") == nil, "this test needs a PATH without node")
    let node = await ProcessRunner.run(environment.command("node", ["-p", "process.execPath + ' ' + process.version"]))
    #expect(node.stdout == "\(Self.runtime.nodeBin)/node" + " v24.22.2\n")
    // npm is `#!/usr/bin/env node`: it only starts because our node is first on PATH.
    let npm = await ProcessRunner.run(environment.command("npm", ["--version"]))
    #expect(npm.success, "\(npm.output)")
    #expect(npm.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == Self.runtime.npmVersion)
    // Counter-check: the same in "system" mode finds no node at all on this PATH.
    let system = await ProcessRunner.run(environment.with(nodeMode: .system).command("npm", ["--version"]))
    #expect(system.termination == .couldNotStart(.notFound))
  }

  @Test(.enabled(if: hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
  func bundledGitIsChosenWhenTheHostHasOnlyTheStub() async throws {
    let scratch = try HostPathTests.Scratch()
    let noTools = try scratch.script("xcode-select", "exit 2")
    let resolved = await GitRuntime.resolve(hostPath: Self.launchd, bundle: Self.runtime.git, base: Self.base, xcodeSelect: noTools)
    let git = try #require(resolved.runtime)
    #expect(git.source == .bundled)
    #expect(git.version == "git version 2.53.0")
    #expect(resolved.failure == nil)

    // With the real xcode-select this Mac's /usr/bin/git answers and wins.
    let host = await GitRuntime.resolve(hostPath: Self.launchd, bundle: Self.runtime.git, base: Self.base)
    #expect(host.runtime?.source == .host)
    #expect(host.runtime?.path == "/usr/bin/git")
  }

  @Test(.enabled(if: hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
  func bundledGitFindsItsTemplates() async throws {
    let scratch = try HostPathTests.Scratch()
    // The git that resolve chose, with the variables resolve set.
    let noTools = try scratch.script("xcode-select", "exit 2")
    let resolved = await GitRuntime.resolve(hostPath: Self.launchd, bundle: Self.runtime.git, base: Self.base, xcodeSelect: noTools)
    let environment = Self.environment(.embedded, git: try #require(resolved.runtime))
    let repo = scratch.url.appendingPathComponent("repo")
    let result = await ProcessRunner.run(environment.command("git", ["init", "-q", "--", repo.path]))
    #expect(result.success)
    #expect(!result.output.contains("templates not found"), "\(result.output)")
    #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git/hooks").path))
    // Counter-check: without GIT_TEMPLATE_DIR the bundled git looks under "/" (Phase 1).
    var bare = environment.command("git", ["init", "-q", "--", scratch.url.appendingPathComponent("bare").path])
    bare.environment["GIT_TEMPLATE_DIR"] = nil
    let without = await ProcessRunner.run(bare)
    #expect(without.output.contains("templates not found"), "\(without.output)")
  }

  @Test func brokenAndIncompatibleBundlesAreTold() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let noTools = try scratch.script("xcode-select", "exit 2")
    let empty = HostPath(entries: [try scratch.dir("empty")], source: .inherited, added: [])

    try scratch.script("broken/bin/git", "echo 'fatal: something' >&2; exit 1")
    let broken = await GitRuntime.resolve(hostPath: empty, bundle: "\(scratch.path)/broken", base: [:], xcodeSelect: noTools)
    #expect(broken.runtime == nil)
    #expect(broken.failure?.reason == .broken)

    try scratch.script("loader/bin/git", "echo 'dyld[1]: Library not loaded: /usr/lib/libfoo.dylib' >&2; exit 134")
    let loader = await GitRuntime.resolve(hostPath: empty, bundle: "\(scratch.path)/loader", base: [:], xcodeSelect: noTools)
    #expect(loader.failure?.reason == .incompatible)

    // Answers --version, but its https helper cannot be loaded.
    try scratch.script("nohttps/bin/git", "echo 'git version 9'")
    try scratch.script("nohttps/libexec/git-core/git-remote-https", "exit 127")
    let nohttps = await GitRuntime.resolve(hostPath: empty, bundle: "\(scratch.path)/nohttps", base: [:], xcodeSelect: noTools)
    #expect(nohttps.failure?.reason == .incompatible)

    try scratch.script("fine/bin/git", "echo 'git version 9'")
    try scratch.script("fine/libexec/git-core/git-remote-https", "echo 'usage: git remote-https <remote> [<url>]' >&2; exit 1")
    let fine = await GitRuntime.resolve(hostPath: empty, bundle: "\(scratch.path)/fine", base: [:], xcodeSelect: noTools)
    #expect(fine.runtime?.version == "git version 9")
    // The variables name the bundle with the bytes it has on disk.
    #expect(fine.runtime.map { Array(($0.variables["GIT_EXEC_PATH"] ?? "").utf8) } == Array("\(scratch.path)/fine/libexec/git-core".utf8))

    let none = await GitRuntime.resolve(hostPath: empty, bundle: "\(scratch.path)/nothing", base: [:], xcodeSelect: noTools)
    #expect(none.runtime == nil && none.failure == nil)
  }

  @Test func gitTextVariables() {
    #expect(GitRuntime.textVariables([:]) == ["LC_MESSAGES": "C", "LANGUAGE": ""])
    #expect(GitRuntime.textVariables(["LC_ALL": ""]) == ["LC_MESSAGES": "C", "LANGUAGE": ""])
    #expect(GitRuntime.textVariables(["LC_ALL": "de_DE.UTF-8"]) == ["LC_MESSAGES": "C", "LANGUAGE": "", "LC_ALL": "", "LC_CTYPE": "de_DE.UTF-8"])
  }

  @Test(.enabled(if: hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
  func reportNamesWhatRuns() async throws {
    let embedded = await EnvironmentReport.probe(Self.environment(.embedded, git: Self.bundledGit()))
    #expect(embedded.ok)
    #expect(embedded.tools.map(\.name) == ["node", "npm", "git"])
    #expect(embedded.tools[0].version == "v24.22.2" && embedded.tools[0].source == .embedded)
    #expect(embedded.tools[2].source == .bundled && embedded.tools[2].version == "git version 2.53.0")
    #expect(embedded.hostNodeVersion == nil) // no node on the launchd PATH
    #expect(embedded.rsyncAvailable) // /usr/bin/rsync

    let system = await EnvironmentReport.probe(Self.environment(.system, git: Self.bundledGit()))
    #expect(!system.ok)
    #expect(system.tools[0].path == nil && system.tools[0].source == .host)

    var failed = Self.environment(.embedded)
    failed.bundledGitFailure = BundledGitFailure(path: "/x/bin/git", reason: .incompatible)
    failed.hostPath = HostPath(entries: ["/bin"], source: .inherited, added: [])
    let report = await EnvironmentReport.probe(failed)
    #expect(report.tools[2] == .init(name: "git", source: .bundled, path: "/x/bin/git", version: nil, incompatible: true))
  }
}
