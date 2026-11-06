import Foundation

/// `quartz sync` for Git-Sync: commit, pull and push in one, through the Quartz CLI. A port of
/// `syncService.ts`, measured against it with an npx stand-in and real git (`scripts/git-golden.mjs`).
///
/// - **A direction is the other one switched off**: `--push`/`--pull` are both on by default
///   (yargs booleans), so "push" is `--no-pull`.
/// - **`--commit` is on by default as well**: every run stages and commits the whole working tree.
///   Without commit `--no-commit`; with it a message, trimmed, as `-m`.
/// - **A shallow history is completed before a push**, because git does not push one: projects
///   cloned with `--depth 1` failed their first push ("shallow update not allowed"). The objects
///   come from Quartz upstream (`quartz-upstream`, which the core update keeps, or the template
///   repository), not from origin, which is empty on a first push. A failure here is said and the
///   push still tried: its own error says more.
/// - **The GitHub token through `GitAuth`**, for every direction, as in QuartzControl.
/// - **A failure the CLI reports in prose is a failure**: `quartz sync` prints "An error occurred
///   while pushing to remote origin." and exits 0 (`quartz/cli/handlers.js`, read in gui-test).
/// - **Deadlines, which QuartzControl did not set**, generous as in `PluginCommands`: both talk to
///   another host, and a stalled connection would leave the page waiting forever.
public enum Sync {
  public enum Direction: String, Sendable { case push, pull, both }

  public struct Options: Sendable, Equatable {
    public var commit: Bool
    public var message: String?
    public init(commit: Bool = true, message: String? = nil) {
      self.commit = commit
      self.message = message
    }
  }

  public struct Result: Sendable, Equatable {
    public var success: Bool
    public var output: String
  }

  public struct Deadlines: Sendable, Equatable {
    public var fetch: Duration = .seconds(10 * 60)
    public var sync: Duration = .seconds(30 * 60)
    public init() {}
  }

  public static func run(project: URL, direction: Direction = .both, options: Options = Options(), environment: ToolEnvironment,
                         token: GitAuth.Token, templateRepository: String = ProjectCreator.templateRepository,
                         deadlines: Deadlines = Deadlines()) async -> Result {
    var arguments = ["quartz", "sync"]
    if direction == .push { arguments.append("--no-pull") }
    if direction == .pull { arguments.append("--no-push") }
    if !options.commit {
      arguments.append("--no-commit")
    } else if let message = options.message.map(JS.trim), !message.isEmpty {
      arguments += ["-m", message]
    }

    let prelude = direction == .pull ? "" : await completeHistory(project, environment, templateRepository, deadlines.fetch)
    let auth: GitAuth
    do {
      auth = try await GitAuth.forOrigin(project: project, environment: environment, token: token)
    } catch {
      return Result(success: false, output: prelude + "\(error)")
    }
    defer { auth.cleanup() }
    let command = environment.command("npx", arguments, in: project, timeout: deadlines.sync).adding(auth.variables)
    let result = await ProcessRunner.run(command)
    let output = result.report(for: command)
    let reportedInProse = result.success && JSText.test(output, "An error occurred while")
    return Result(success: result.success && !reportedInProse, output: prelude + output)
  }

  /// One `rev-parse` for every project that is not shallow.
  static func completeHistory(_ project: URL, _ environment: ToolEnvironment, _ templateRepository: String,
                              _ timeout: Duration) async -> String {
    let shallow = await ProcessRunner.run(environment.command("git", ["rev-parse", "--is-shallow-repository"], in: project))
    guard shallow.success, JS.trim(shallow.stdout) == "true" else { return "" }
    let configured = await ProcessRunner.run(environment.command("git", ["remote", "get-url", "quartz-upstream"], in: project))
    let upstream = JS.trim(configured.stdout)
    let source = configured.success && !upstream.isEmpty ? upstream : templateRepository
    let command = environment.command("git", ["fetch", "--unshallow", "--", source], in: project, timeout: timeout)
    let fetched = await ProcessRunner.run(command)
    return fetched.success
      ? "\(L10n.t("main.syncHistoryCompleted"))\n\n"
      : "\(L10n.t("main.syncHistoryIncomplete"))\n\(fetched.report(for: command))\n\n"
  }
}
