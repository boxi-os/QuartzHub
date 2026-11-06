import Darwin
import Foundation

/// Dev servers a previous run of QuartzHub left behind: a crash, a force quit, "Weiterlaufen
/// lassen" at quit (QuartzControl's `detectOrphanedServers` and `killOrphanedServers`). Found
/// once at the start and asked about; never stopped without the user's answer, since a server may
/// have been left running on purpose. A server QuartzControl started is never one of these: it is
/// in QuartzControl's file, which `Coexistence` reads.
public enum OrphanedServers {
  public struct Orphan: Sendable, Equatable {
    public var projectId: String
    public var pid: Int32
    public var port: Int
  }

  /// The recorded servers that are still running, and the file emptied whatever the answer will
  /// be: one the user keeps is not asked about again. A pid counts only if it lives and is still a
  /// quartz server; the system hands numbers out again.
  public static func detect(store: RunningServersStore, isRunning: (Int32) -> Bool = ServerScan.isQuartzServer) -> [Orphan] {
    guard let entries = try? store.takeAll() else { return [] }
    return entries.keys.compactMap { id in
      guard let server = entries[id], let pid = server.pid, let port = server.port, isRunning(pid) else { return nil }
      return Orphan(projectId: id, pid: pid, port: port)
    }
  }

  /// SIGTERM to each orphan's process group (QuartzHub starts every server as a group leader, so
  /// npx's node goes too). Asked again right before the signal: between the question and the
  /// answer the number may have changed hands. Answers the pids that were signalled.
  @discardableResult
  public static func stop(_ orphans: [Orphan], isRunning: (Int32) -> Bool = ServerScan.isQuartzServer) -> [Int32] {
    orphans.compactMap { orphan in
      guard isRunning(orphan.pid) else { return nil }
      let signalled = getpgid(orphan.pid) == orphan.pid ? killpg(orphan.pid, SIGTERM) : kill(orphan.pid, SIGTERM)
      return signalled == 0 ? orphan.pid : nil
    }
  }
}
