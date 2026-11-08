import Foundation

/// What QuartzControl's `projects:*` handlers (`electron/main/ipc/handlers.ts`) did around the
/// store: the steps that have to happen together when a project enters, moves or leaves the list.
public struct ProjectList: Sendable {
  public let store: ProjectStore
  public let builds: BuildService
  public let connections: Connections
  public let runtime: RuntimeLocation

  public init(store: ProjectStore, builds: BuildService, connections: Connections, runtime: RuntimeLocation = .current) {
    self.store = store
    self.builds = builds
    self.connections = connections
    self.runtime = runtime
  }

  /// `projects:add`. A folder copied outside the app names the original's frames by absolute
  /// path; that is repaired before anything else of the copy is read. A repair that fails is no
  /// reason to refuse the folder: the build says it.
  public func add(path: String) async throws -> ProjectEntry {
    try? await ProjectPaths.repointAuthoredFrames(project: path, runtime: runtime)
    return try store.add(path: path)
  }

  /// `projects:relocate`. The recorded paths inside the project are repaired before the entry
  /// moves: a failure leaves the list as it was, with the message, rather than a moved entry
  /// pointing at a half-fixed project.
  @discardableResult
  public func relocate(id: String, to path: String) async throws -> ProjectEntry? {
    if let before = store.project(id: id), FramePaths.resolve(before.path) != FramePaths.resolve(path) {
      try await ProjectPaths.repointProjectPaths(from: before.path, to: path, runtime: runtime)
    }
    return try store.relocate(id: id, to: path)
  }

  /// `projects:open`: the entry, stamped as opened now.
  public func open(id: String, now: Date = Date()) throws -> ProjectEntry? {
    try store.touch(id: id, now: now)
    return store.project(id: id)
  }

  /// `projects:remove`. The last moment the app can reach the project's dev server (tracked by
  /// id): it is stopped first. The relay's secrets are keyed by the id too; with the entry gone
  /// nothing could reach them again. The folder stays.
  public func remove(id: String) async throws {
    await builds.stopServer(id)
    try store.remove(id: id)
    try connections.deleteRelaySecrets(id)
  }
}
