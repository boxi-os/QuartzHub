import Foundation

/// A new Quartz project from nothing, a port of `createService.ts`. There is no single command for
/// it: `quartz` is a package nobody publishes, and `quartz create` only runs inside a cloned and
/// installed copy. So: clone the upstream, cut it loose from it, `npm install`, then the wizard
/// with every answer given, then one build.
///
/// - **Not `--depth 1`.** A shallow clone cannot be pushed anywhere (git refuses it against a local
///   remote, GitHub with "did not receive expected object"), and pushing the project to the user's
///   repository is what Git-Sync and every git-branch target are for.
/// - **`origin` goes**, so a later push never targets jackyzha0/quartz.
/// - **Every wizard question is answered.** stdin is closed, so a question without its flag ends
///   the wizard with exit 0 and no `quartz.config.yaml` (measured in QuartzControl for `-l` and
///   `-b`); success is the file, not the exit code.
/// - **The warm-up build** takes the one-time failure of templates whose plugins install a package
///   on first build and then cannot load it in the same process ("obsidian", measured there).
/// - **Deadlines, which QuartzControl did not set.** A clone over a stalled connection waited there
///   forever; here each step has one, generous enough for a slow line (`Deadlines`).
public enum ProjectCreator {
  public static let templateRepository = "https://github.com/jackyzha0/quartz.git"

  /// `quartz create -t`; `docs` since Quartz 5.1 (sidebars that scroll away with the page), and a
  /// project is created from the default branch, which is 5.1.
  public enum Template: String, Sendable, CaseIterable { case `default`, obsidian, ttrpg, blog, docs }
  /// `-X`: what `quartz create` does with `-s`.
  public enum Strategy: String, Sendable { case new, copy, symlink }
  public enum LinkResolution: String, Sendable { case absolute, shortest, relative }

  public struct Options: Sendable, Equatable {
    public var targetDirectory: String
    public var template: Template = .default
    /// The content to take over, for `copy` and `symlink`.
    public var source: String?
    public var strategy: Strategy = .new
    public var linkResolution: LinkResolution = .shortest
    /// `-b` is asked whenever it is missing or empty; the config editor changes it later.
    public var baseUrl: String = ""

    public init(targetDirectory: String) { self.targetDirectory = targetDirectory }

    /// The wizard's arguments after `npx`, in QuartzControl's order.
    var wizardArguments: [String] {
      var arguments = ["quartz", "create", "-t", template.rawValue, "-X", strategy.rawValue,
                       "-l", linkResolution.rawValue, "-b", baseUrl.isEmpty ? "localhost" : baseUrl]
      if let source { arguments += ["-s", source] }
      return arguments
    }
  }

  public struct Deadlines: Sendable, Equatable {
    public var clone: Duration = .seconds(15 * 60)
    public var install: Duration = .seconds(20 * 60)
    public var wizard: Duration = .seconds(5 * 60)
    public var build: Duration = .seconds(10 * 60)
    public var local: Duration = .seconds(30)
    public init() {}
  }

  public struct Result: Sendable, Equatable {
    public var success: Bool
    /// Everything the steps printed, with a sentence before the one that failed.
    public var output: String
  }

  public static func create(
    _ options: Options,
    environment: ToolEnvironment,
    repository: String = templateRepository,
    deadlines: Deadlines = Deadlines()
  ) async -> Result {
    let target = options.targetDirectory
    // git clone refuses a folder with something in it, with a sentence about a "destination path"
    // that names no field; the wizard builds this path from a parent and a typed name, so a
    // collision is a typo, and it gets a sentence with the path.
    if let names = try? FileManager.default.contentsOfDirectory(atPath: target), !names.isEmpty {
      return Result(success: false, output: L10n.t("main.createTargetExists", ["path": target]))
    }

    func run(_ executable: String, _ arguments: [String], in directory: String?, _ timeout: Duration) async -> (Bool, String) {
      let command = environment.command(executable, arguments, in: directory, timeout: timeout)
      let result = await ProcessRunner.run(command)
      return (result.success, result.report(for: command))
    }

    let (cloned, cloneOutput) = await run("git", ["clone", "--", repository, target], in: nil, deadlines.clone)
    guard cloned else {
      return Result(success: false, output: "\(L10n.t("main.createCloneFailed"))\n\(cloneOutput)")
    }
    _ = await run("git", ["remote", "remove", "origin"], in: target, deadlines.local)

    let (installed, installOutput) = await run("npm", ["install"], in: target, deadlines.install)
    guard installed else {
      return Result(success: false, output: "\(cloneOutput)\n\n\(L10n.t("main.createInstallFailed"))\n\(installOutput)")
    }

    let (created, createOutput) = await run("npx", options.wizardArguments, in: target, deadlines.wizard)
    let configWritten = FileManager.default.fileExists(atPath: "\(target)/quartz.config.yaml")

    var warmup = ""
    if created && configWritten {
      let (built, buildOutput) = await run("npx", ["quartz", "build"], in: target, deadlines.build)
      if !built { warmup = "\n\n\(L10n.t("main.warmupBuild"))\n\(buildOutput)" }
    }
    let noConfig = created && !configWritten ? L10n.t("main.createNoConfig") : ""
    return Result(success: created && configWritten,
                  output: "\(cloneOutput)\n\(installOutput)\n\(createOutput)\(warmup)\(noConfig)")
  }
}
