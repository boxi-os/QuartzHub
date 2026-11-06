import Foundation
import Synchronization

/// The Quartz CLI's plugin commands, a port of `pluginService.ts`. Only these four go through the
/// CLI: `enable`/`disable`/`config --set` do nothing (exit 0, no change) for every built-in
/// `@quartz-community/x` entry, so switching and options are config writes (`ConfigFile`), and an
/// entry is addressed by index, never by name (plugins-and-config.md, "Two config-mutation paths").
///
/// - **Not yet:** the snapshot before `add` and `remove` (`pluginChange`) comes with the snapshot
///   store (Phase 3 point 7).
/// - **Deadlines, which QuartzControl did not set**, generous as in `ProjectCreator`: `add` and
///   `install` clone from GitHub.
public final class PluginCommands: Sendable {
  public static let shared = PluginCommands()

  public struct Result: Sendable, Equatable {
    public var success: Bool
    public var output: String
    /// `installFromLock` only: the plugins `quartz plugin install` reported as failed.
    public var failed: [String]?
  }

  public struct Deadlines: Sendable, Equatable {
    public var network: Duration = .seconds(20 * 60)
    public var local: Duration = .seconds(5 * 60)
    public init() {}
  }

  private let installs = Mutex<[String: Task<Result, Never>]>([:])
  public init() {}

  // MARK: add, remove, prune

  /// `quartz plugin add <source>`, without a snapshot: the template import takes one for the whole
  /// import, and a package with 48 plugins would otherwise leave 48 behind (`installPluginSource`).
  public func add(source: String, project: URL, environment: ToolEnvironment, deadlines: Deadlines = Deadlines()) async -> Result {
    await quartz(["plugin", "add", source], project, environment, deadlines.network)
  }

  public func remove(name: String, project: URL, environment: ToolEnvironment, deadlines: Deadlines = Deadlines()) async -> Result {
    await quartz(["plugin", "remove", name], project, environment, deadlines.local)
  }

  /// Drops the directories under `.quartz/plugins` that no config entry points at any more.
  public func prune(project: URL, environment: ToolEnvironment, deadlines: Deadlines = Deadlines()) async -> Result {
    await quartz(["plugin", "prune"], project, environment, deadlines.local)
  }

  private func quartz(_ arguments: [String], _ project: URL, _ environment: ToolEnvironment, _ timeout: Duration) async -> Result {
    let command = environment.command("npx", ["quartz"] + arguments, in: project, timeout: timeout)
    let result = await ProcessRunner.run(command)
    return Result(success: result.success, output: result.report(for: command))
  }

  // MARK: install from the lockfile

  /// What a fresh clone needs: `npm install` first when packages are missing (otherwise `quartz
  /// plugin install` died on its own first import), then `quartz plugin install`. That one ends
  /// with 0 when single plugins fail, so their names go back with the result (alpha scenes
  /// 2026-10-17, findings 4.1 and 2.1).
  ///
  /// One run per project, held here and not in a page: a second call joins the running one instead
  /// of starting a second npm in the same folder (QuartzControl's forty-sixth review, Niedrig 4).
  /// `afterPackagesInstalled` runs when npm went through and nothing is missing any more: the build
  /// service forgets the starts that failed only for missing packages (`forgetDependencyErrors`).
  public func installFromLock(project: URL, environment: ToolEnvironment, deadlines: Deadlines = Deadlines(),
                              afterPackagesInstalled: @escaping @Sendable (URL) -> Void = { _ in }) async -> Result {
    let key = ProjectLock.key(project.path)
    let task = installs.withLock { installs -> Task<Result, Never> in
      if let running = installs[key] { return running }
      // The run clears its own entry, as QuartzControl's `finally` does: a call after the end
      // starts a new run instead of joining a finished one.
      let task = Task.detached { [self] in
        let result = await Self.installFromLockNow(project, environment, deadlines, afterPackagesInstalled)
        self.installs.withLock { $0[key] = nil }
        return result
      }
      installs[key] = task
      return task
    }
    return await task.value
  }

  public func isInstallingFromLock(project: URL) -> Bool {
    installs.withLock { $0[ProjectLock.key(project.path)] != nil }
  }

  private static func installFromLockNow(_ project: URL, _ environment: ToolEnvironment, _ deadlines: Deadlines,
                                         _ afterPackagesInstalled: @Sendable (URL) -> Void) async -> Result {
    var npmOutput = ""
    if let missing = ProjectDependencies.missingDependencies(project: project), !missing.isEmpty {
      let npm = environment.command("npm", ["install"], in: project, timeout: deadlines.network)
      let result = await ProcessRunner.run(npm)
      guard result.success else { return Result(success: false, output: result.report(for: npm)) }
      npmOutput = result.report(for: npm)
      if ProjectDependencies.missingDependencies(project: project)?.isEmpty == true { afterPackagesInstalled(project) }
    }
    let command = environment.command("npx", ["quartz", "plugin", "install"], in: project, timeout: deadlines.network)
    let plugins = await ProcessRunner.run(command)
    let output = plugins.report(for: command)
    return Result(success: plugins.success,
                  output: "\(npmOutput)\n\(output)".trimmingCharacters(in: .whitespacesAndNewlines),
                  failed: failedPlugins(output))
  }

  /// The names in "  ✗ <name>: <reason>" lines, colours stripped, each once.
  static func failedPlugins(_ output: String) -> [String] {
    let plain = output.replacing(/\x1b\[[0-9;]*m/, with: "")
    var names: [String] = []
    for match in plain.matches(of: #/^\s*✗ ([^\s:]+): /#.anchorsMatchLineEndings()) where !names.contains(String(match.1)) {
      names.append(String(match.1))
    }
    return names
  }

  // MARK: the lockfile

  /// `quartz.lock.json`, nil when it is not there. Quartz's file, read as JSON.parse reads it;
  /// nothing here moves it aside.
  public static func readLockfile(project: URL) throws -> JSONValue? {
    let url = project.appendingPathComponent("quartz.lock.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSJSON.parse(Data(contentsOf: url))
  }
}
