import Darwin
import Foundation
import Synchronization

/// A lock per project that waits rather than refusing, with its own queue. A port of
/// `electron/main/services/projectLock.ts` (and `styleLock.ts`, which builds the styles lock).
///
/// - **Per project through `realpath`:** two spellings of one folder are one key. A path that does
///   not resolve keys on its standardized absolute form, as Node's `resolve` would.
/// - **Reentrant:** the writers call one another (a template import saves the variables, a rename
///   sets the import order); a caller that already holds the lock for this project just runs.
///   Holding is a task-local value, the counterpart of Node's `AsyncLocalStorage`.
/// - **A predecessor's failure is not the next caller's:** the queue goes on either way.
/// - **Nothing under the lock may start what outlives it.** A `Task { }` started inside inherits
///   the task-local and counts as a holder after the release, so it would run past the next
///   writer in line (QuartzControl measured exactly this with a timer). `Task.detached` does not
///   inherit it, and is not a holder either: it waits in the queue like anyone else.
///
/// Three exist, and no holder of one takes another: `styles`, `config` and `frames`. A fourth queue
/// per project is the snapshot store's (`SnapshotStore.lock`), and that one is ordered: a restore
/// holds it and takes the config lock at its end, so nothing holding the config lock waits on it.
public final class ProjectLock: Sendable {
  /// One writer at a time for a project's stylesheets and its font folder (`styleLock.ts`: the
  /// font writers, the variables, the import order, a template import). Not covered: a snapshot
  /// restore, `quartz sync --pull`, the core update's merge and the user's own editor.
  public static let styles = ProjectLock(name: "styles")
  /// One writer at a time for `quartz.config.yaml` (`configService.whileHoldingConfig`).
  public static let config = ProjectLock(name: "config")
  /// One writer at a time for a project's authored frames (`serialised` in
  /// `layoutFrameService.ts`: saving a frame, the breakpoint widths, the refresh before a build).
  /// QuartzControl keyed that queue by the path as given; here by `realpath`, like the others.
  public static let frames = ProjectLock(name: "frames")

  public let name: String
  private let queues = Mutex<[String: Task<Void, Never>]>([:])

  @TaskLocal private static var held: Set<String> = []

  public init(name: String) {
    self.name = name
  }

  /// Runs `body` once every earlier caller for the same project is done.
  public func run<T>(_ projectPath: String, _ body: () async throws -> T) async rethrows -> T {
    let key = Self.key(projectPath)
    let token = "\(ObjectIdentifier(self).hashValue):\(key)"
    if Self.held.contains(token) { return try await body() }

    let (done, finish) = AsyncStream<Never>.makeStream()
    let (previous, queued) = queues.withLock { queues -> (Task<Void, Never>?, Task<Void, Never>) in
      let previous = queues[key]
      // Ends when the predecessor has ended and this caller has: the next one chains onto it.
      let queued = Task.detached {
        await previous?.value
        for await _ in done {}
      }
      queues[key] = queued
      return (previous, queued)
    }
    await previous?.value
    defer {
      finish.finish()
      // Cleared only while it is still this run's: a later caller has chained onto it and owns
      // the key otherwise.
      queues.withLock { queues in
        if queues[key] == queued { queues[key] = nil }
      }
    }
    return try await Self.$held.withValue(Self.held.union([token])) { try await body() }
  }

  /// The number of projects with a queue, for the tests.
  var queuedProjects: Int { queues.withLock { $0.count } }

  static func key(_ path: String) -> String {
    if let resolved = realpath(path, nil) {
      defer { free(resolved) }
      return String(cString: resolved)
    }
    let absolute = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
    return URL(fileURLWithPath: absolute).standardizedFileURL.path
  }
}
