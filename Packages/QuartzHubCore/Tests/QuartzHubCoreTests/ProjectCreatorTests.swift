import Foundation
import Testing
@testable import QuartzHubCore

/// Against a local upstream and stand-ins for npm and npx that note their arguments; the real
/// clone from GitHub with the real wizard is a measurement in decisions/phase-3-dienste.md.
@Suite struct ProjectCreatorTests {
  let scratch: HostPathTests.Scratch
  let upstream: URL
  let log: URL

  init() throws {
    scratch = try HostPathTests.Scratch()
    upstream = scratch.url.appendingPathComponent("upstream")
    log = scratch.url.appendingPathComponent("calls.log")
  }

  /// An upstream with two commits (a shallow clone would have one) and the stand-ins. Not in
  /// `init`, which cannot await.
  func prepare(npm: String = "exit 0", wizard: String = "touch quartz.config.yaml", build: String = "exit 0") async throws -> ToolEnvironment {
    let env = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null"]
    for script in ["git init -q -b v5 upstream", "cd upstream && echo a > a && git add a && git commit -qm one",
                   "cd upstream && echo b > b && git add b && git commit -qm two"] {
      let result = await ProcessRunner.run(Command("/bin/sh", ["-c", script], in: scratch.url, environment: env))
      try #require(result.success, "\(result.output)")
    }
    let quoted = log.path
    try scratch.script("bin/npm", "echo \"npm $*\" >> '\(quoted)'\n\(npm)")
    try scratch.script("bin/npx", """
      echo "npx $*" >> '\(quoted)'
      case "$2" in
        create) \(wizard) ;;
        build) \(build) ;;
      esac
      """)
    let hostPath = HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"], source: .inherited, added: [])
    return ToolEnvironment(base: env, hostPath: hostPath, nodeMode: .system, runtime: .repository,
                           git: GitRuntime(source: .host, path: "/usr/bin/git", version: "x", variables: GitRuntime.textVariables([:])),
                           bundledGitFailure: nil)
  }

  var target: URL { scratch.url.appendingPathComponent("Neues Projekt") }
  var calls: [String] { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

  func git(_ args: String...) async -> String {
    await ProcessRunner.run(Command("/usr/bin/git", ["-C", target.path] + args, environment: ["PATH": "/usr/bin:/bin"])).stdout
  }

  @Test func theWholeWayWithEveryAnswerGiven() async throws {
    let environment = try await prepare()
    var options = ProjectCreator.Options(targetDirectory: target)
    options.template = .obsidian
    options.strategy = .symlink
    options.source = "/Users/x/Vault mit Leerzeichen"
    let result = await ProjectCreator.create(options, environment: environment, repository: upstream.path)
    #expect(result.success, "\(result.output)")
    #expect(calls == [
      "npm install",
      "npx quartz create -t obsidian -X symlink -l shortest -b localhost -s /Users/x/Vault mit Leerzeichen",
      "npx quartz build"
    ])
    // A full clone, cut loose from the upstream.
    #expect(await git("rev-list", "--count", "HEAD") == "2\n")
    #expect(await git("remote") == "")
    #expect(!result.output.contains(L10n.t("main.warmupBuild")))
  }

  @Test func aFolderWithSomethingInItIsRefusedBeforeAnythingRuns() async throws {
    let environment = try await prepare()
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try Data().write(to: target.appendingPathComponent(".DS_Store"))
    let result = await ProjectCreator.create(.init(targetDirectory: target), environment: environment, repository: upstream.path)
    #expect(!result.success)
    #expect(result.output == L10n.t("main.createTargetExists", ["path": target.path]))
    #expect(calls.isEmpty)
    // An empty folder is fine: git clone takes it.
    try FileManager.default.removeItem(at: target.appendingPathComponent(".DS_Store"))
    #expect(await ProjectCreator.create(.init(targetDirectory: target), environment: environment, repository: upstream.path).success)
  }

  @Test func eachFailureSaysWhichStep() async throws {
    let environment = try await prepare(npm: "echo 'ERR! network' >&2; exit 1")
    let clone = await ProjectCreator.create(.init(targetDirectory: target), environment: environment,
                                            repository: scratch.url.appendingPathComponent("nowhere").path)
    #expect(!clone.success && clone.output.hasPrefix(L10n.t("main.createCloneFailed") + "\n"))
    #expect(calls.isEmpty)

    let install = await ProjectCreator.create(.init(targetDirectory: target), environment: environment, repository: upstream.path)
    #expect(!install.success)
    #expect(install.output.contains("\n\n\(L10n.t("main.createInstallFailed"))\nERR! network"), "\(install.output)")
    #expect(calls == ["npm install"])
  }

  @Test func aWizardThatWritesNoConfigIsNoSuccess() async throws {
    // What the real wizard does when a question has no flag: exit 0, nothing written.
    let environment = try await prepare(wizard: "exit 0")
    let result = await ProjectCreator.create(.init(targetDirectory: target), environment: environment, repository: upstream.path)
    #expect(!result.success)
    #expect(result.output.hasSuffix(L10n.t("main.createNoConfig")))
    #expect(!calls.contains("npx quartz build"), "built without a config")
  }

  @Test func aFailedWarmUpIsToldButNoFailure() async throws {
    let environment = try await prepare(build: "echo 'Cannot find module x'; exit 1")
    var options = ProjectCreator.Options(targetDirectory: target)
    options.baseUrl = "example.org/garten"
    let result = await ProjectCreator.create(options, environment: environment, repository: upstream.path)
    #expect(result.success)
    #expect(result.output.hasSuffix("\n\n\(L10n.t("main.warmupBuild"))\nCannot find module x\n"), "\(result.output)")
    #expect(calls[1].hasSuffix("-b example.org/garten"))
  }

  /// The real thing: GitHub, npm's registry, the embedded Node, the wizard. Minutes and the
  /// network, so only on request: `QH_NETWORK_TESTS=1 swift test --filter realQuartz`.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["QH_NETWORK_TESTS"] == "1" && ToolEnvironmentTests.hasRuntime),
        .timeLimit(.minutes(20)))
  func realQuartzFromGitHub() async throws {
    let environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    let started = ContinuousClock.now
    let result = await ProjectCreator.create(.init(targetDirectory: target), environment: environment)
    print("create took \(ContinuousClock.now - started), git \(environment.git?.source.rawValue ?? "none")")
    #expect(result.success, "\(result.output.suffix(2000))")
    #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("quartz.config.yaml").path))
    #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("public/index.html").path), "no warm-up build")
    #expect(await git("remote") == "")
    let commits = Int(await git("rev-list", "--count", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    #expect(commits > 100, "\(commits) commits: shallow?")
    #expect(!result.output.contains(L10n.t("main.warmupBuild")), "\(result.output.suffix(2000))")
  }

  @Test func aStepThatHangsEndsAtItsDeadline() async throws {
    let environment = try await prepare(npm: "sleep 30")
    var deadlines = ProjectCreator.Deadlines()
    deadlines.install = .milliseconds(300)
    let started = ContinuousClock.now
    let result = await ProjectCreator.create(.init(targetDirectory: target), environment: environment,
                                             repository: upstream.path, deadlines: deadlines)
    #expect(!result.success)
    #expect(ContinuousClock.now - started < .seconds(10))
    #expect(result.output.contains(L10n.t("main.commandTimeout", ["ms": "300", "command": "npm install"])), "\(result.output)")
  }
}
