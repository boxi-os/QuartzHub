import Darwin
import Foundation
import Synchronization

/// A vault link that a parked run never put back (review 2026-11-11, M1). QuartzControl 1.3 kept the
/// target only in memory; QuartzHub writes it before the link goes and reads it when the project is
/// opened again.
extension ContentFolder {
  /// Projects whose link this process holds parked right now: their record is not a leftover.
  static let parked = Mutex<Set<String>>([])

  static func parkedRecord(_ project: String) -> String { QuartzGuiDirectory(project: project).file("content-link.json") }

  public enum Recovery: Equatable, Sendable {
    /// The link is back where the record said.
    case relinked(target: String)
    /// Also that, and what git had put in its place was moved aside first (as a content-source
    /// switch does, under `content-backups/`), never deleted.
    case relinkedAfterMovingAside(target: String, backupId: String)
  }

  /// A record without a run means the link was lost: put it back. A link that is there again is
  /// left alone (one to the same target or one the user set since), so is a record without a
  /// target. The record goes in every case but a failure. Nothing to do: nil, without writing.
  public static func recoverParkedLink(project: String, now: Date = Date()) throws -> Recovery? {
    let record = parkedRecord(project)
    guard Posix.exists(record), !parked.withLock({ $0.contains(project) }) else { return nil }
    guard let data = try? Posix.read(record), let target = (try? JSJSON.parse(data))?["target"]?.stringValue, !target.isEmpty else {
      unlink(record)
      return nil
    }
    let content = path(project: project)
    var info = stat()
    var outcome: Recovery?
    if lstat(content, &info) != 0 {
      try Posix.symlink(target, content)
      outcome = .relinked(target: target)
    } else if (info.st_mode & S_IFMT) == S_IFDIR {
      let entry = try ContentBackups.moveAside(project: project, content: content, now: now)
      try Posix.symlink(target, content)
      outcome = entry.map { .relinkedAfterMovingAside(target: target, backupId: $0.id) } ?? .relinked(target: target)
    }
    unlink(record)
    return outcome
  }
}
