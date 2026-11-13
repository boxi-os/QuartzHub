import Foundation
import Synchronization

/// The Quartz CLI's plugin commands, a port of `pluginService.ts`. Only these four go through the
/// CLI: `enable`/`disable`/`config --set` do nothing (exit 0, no change) for every built-in
/// `@quartz-community/x` entry, so switching and options are config writes (`ConfigFile`), and an
/// entry is addressed by index, never by name (plugins-and-config.md, "Two config-mutation paths").
///
/// - **A snapshot before `add` and `remove`** (`pluginChange`, the source or name as its label)
///   when the caller hands one over; the template import adds without, it takes one for the whole
///   import. A snapshot that fails stops the command; here that is a failed answer with its
///   sentence, where QuartzControl rejected the call.
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

  /// `quartz plugin add <source>`: with `snapshot` QuartzControl's `addPlugin`, without it
  /// `installPluginSource`, for the template import (48 plugins would leave 48 snapshots behind).
  public func add(source: String, project: String, environment: ToolEnvironment, deadlines: Deadlines = Deadlines(),
                  snapshot: SnapshotStore.Take? = nil) async -> Result {
    // The source goes to the CLI as an argument: one starting with "-" would be read as an option
    // (docs/conventions.md, „Was aus einer Datei kommt …“; review 2026-11-13, handbook, N1: the
    // marketplace's own field passed it unchecked). PluginSource is the rule QuartzControl had.
    guard PluginSource(.string(source)) != nil else {
      return Result(success: false, output: L10n.t("main.pluginSourceInvalid", ["source": String(source.prefix(80))]))
    }
    if let failure = await Self.snapshotFirst(snapshot, project, source) { return failure }
    return await quartz(["plugin", "add", source], project, environment, deadlines.network)
  }

  public func remove(name: String, project: String, environment: ToolEnvironment, deadlines: Deadlines = Deadlines(),
                     snapshot: SnapshotStore.Take? = nil) async -> Result {
    if let failure = await Self.snapshotFirst(snapshot, project, name) { return failure }
    return await quartz(["plugin", "remove", name], project, environment, deadlines.local)
  }

  static func snapshotFirst(_ snapshot: SnapshotStore.Take?, _ project: String, _ label: String) async -> Result? {
    guard let snapshot else { return nil }
    do {
      _ = try await snapshot(project, "pluginChange", label)
      return nil
    } catch {
      return Result(success: false, output: "\(error)")
    }
  }

  /// Drops the directories under `.quartz/plugins` that no config entry points at any more.
  public func prune(project: String, environment: ToolEnvironment, deadlines: Deadlines = Deadlines()) async -> Result {
    await quartz(["plugin", "prune"], project, environment, deadlines.local)
  }

  // MARK: Quartz 5.1: doctor and info

  /// `quartz plugin doctor`: Quartz's own check of quartz.config.yaml, quartz.lock.json and the
  /// installed plugins. It ends with 1 when it found errors, so `success` is "nothing wrong", not
  /// "it ran"; the output says which. With `fix` it moves the entries of the plugins that are part
  /// of Quartz since 5.1 to `configuration.*` and drops their lockfile pins
  /// (`BuiltinProcessing.pendingMigrations`), comments kept; a snapshot first when one is handed over.
  public func doctor(project: String, fix: Bool, environment: ToolEnvironment, deadlines: Deadlines = Deadlines(),
                     snapshot: SnapshotStore.Take? = nil) async -> Result {
    if fix, let failure = await Self.snapshotFirst(snapshot, project, "plugin doctor --fix") { return failure }
    return await quartz(["plugin", "doctor"] + (fix ? ["--fix"] : []), project, environment, deadlines.local)
  }

  /// `quartz info`: Quartz, Node, the plugins and the config in one text, for a bug report.
  public func info(project: String, environment: ToolEnvironment, deadlines: Deadlines = Deadlines()) async -> Result {
    await quartz(["info"], project, environment, deadlines.local)
  }

  private func quartz(_ arguments: [String], _ project: String, _ environment: ToolEnvironment, _ timeout: Duration) async -> Result {
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
  public func installFromLock(project: String, environment: ToolEnvironment, deadlines: Deadlines = Deadlines(),
                              afterPackagesInstalled: @escaping @Sendable (String) -> Void = { _ in }) async -> Result {
    let key = ProjectLock.key(project)
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

  public func isInstallingFromLock(project: String) -> Bool {
    installs.withLock { $0[ProjectLock.key(project)] != nil }
  }

  private static func installFromLockNow(_ project: String, _ environment: ToolEnvironment, _ deadlines: Deadlines,
                                         _ afterPackagesInstalled: @Sendable (String) -> Void) async -> Result {
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
  public static func readLockfile(project: String) throws -> JSONValue? {
    let path = "\(project)/quartz.lock.json"
    guard Posix.exists(path) else { return nil }
    return try JSJSON.parse(Posix.read(path))
  }
}
