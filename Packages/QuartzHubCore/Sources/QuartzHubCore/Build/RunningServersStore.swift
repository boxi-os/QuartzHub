import Foundation
import Synchronization

/// The dev servers QuartzHub started, so that one left behind by a crash or a force quit is found
/// at the next start: `running-servers.json` in QuartzHub's profile, in
/// QuartzControl's form (`runningServersStore.ts`, measured in RunningServersStoreTests). Not
/// "this server should be running": there is no such intent across a restart, only leftovers.
///
/// Beyond QuartzControl:
/// - Every change reads, changes and writes under one lock. QuartzControl fired its writes with
///   `void` and let them interleave between their awaits; a record right after a remove could be
///   overwritten by the remove's older read.
/// - `remove` can be told whose entry it may take: a pid. A server that ends removes its entry,
///   and a second start of the same project may have written its own there in the meantime
///   (QuartzControl's `forgetServer` guarded the map; the store wrote whatever came last).
public final class RunningServersStore: Sendable {
  public let profile: ProfileDirectory
  private let serial = Mutex<Void>(())

  public init(profile: ProfileDirectory = .quartzHub) {
    self.profile = profile
  }

  /// What the file holds, without emptying it.
  public func peek() -> JSONMap<TrackedServer> {
    serial.withLock { _ in JSONMap(JSONStore.read(profile.runningServers, orEmpty: .object)) }
  }

  public func record(projectId: String, server: TrackedServer) throws {
    try change { map in
      map[projectId] = server
      return true
    }
  }

  /// Takes the entry of `projectId` out; with `pid` only if it is still that process's.
  public func remove(projectId: String, pid: Int32? = nil) throws {
    try change { map in
      guard map.object[projectId] != nil else { return false }
      if let pid, map[projectId]?.pid != pid { return false }
      map.object[projectId] = nil
      return true
    }
  }

  /// Everything in the file, and the file emptied: what was there is asked about once, and a
  /// server the user chose to leave running is not asked about again (QuartzControl's
  /// `detectOrphanedServers`). Written as `{}` even when it was empty, as there.
  public func takeAll() throws -> JSONMap<TrackedServer> {
    var taken = JSONMap<TrackedServer>(.object(JSONObject()))
    try change { map in
      taken = map
      map = JSONMap(.object(JSONObject()))
      return true
    }
    return taken
  }

  private func change(_ body: (inout JSONMap<TrackedServer>) -> Bool) throws {
    try serial.withLock { _ in
      var map = JSONMap<TrackedServer>(JSONStore.read(profile.runningServers, orEmpty: .object))
      guard body(&map) else { return }
      try Posix.mkdirs(profile.path)
      try JSONStore.write(map.json, to: profile.runningServers)
    }
  }
}
