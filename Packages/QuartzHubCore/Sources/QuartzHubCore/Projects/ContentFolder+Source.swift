import Darwin
import Foundation

extension ContentFolder {
  public enum SourceStrategy: String, Sendable { case copy, symlink }

  /// `createSnapshot(project, kind, label)`, before the switch.
  public typealias Snapshot = @Sendable (_ project: String, _ kind: String, _ label: String) async throws -> Void
  /// After each entry the copy took: done so far, the files there are, the entry's path. The
  /// count runs past the total: it counts every entry, hidden ones and folders too, the total only
  /// what Quartz reads (`countFiles`), as in QuartzControl.
  public typealias Progress = (_ processed: Int, _ total: Int, _ path: String) -> Void

  /// `changeContentSource`: content/ becomes a copy of `source` or a link to it. Two nets first:
  /// a snapshot of the project as it is, and the old content folder moved aside (a linked vault is
  /// not in the snapshot). `source` stays a string, written into a link as it was given.
  public static func changeSource(project: String, source: String, strategy: SourceStrategy, snapshot: Snapshot,
                                  now: Date = Date(), progress: Progress? = nil) async throws {
    guard Posix.exists(source) else {
      throw ContentBackups.Failure(message: L10n.t("main.contentSourceMissing", ["path": source]))
    }
    let target = "\(project)/content"
    let from = FramePaths.resolve(source.hasPrefix("/") ? source : FileManager.default.currentDirectoryPath + "/" + source)
    let to = FramePaths.resolve(target)
    if contains(to, from) { throw ContentBackups.Failure(message: L10n.t("main.contentSourceInsideTarget", ["target": target])) }
    if contains(from, to) { throw ContentBackups.Failure(message: L10n.t("main.contentTargetInsideSource", ["target": target])) }

    try await snapshot(project, "contentChange", "")
    try ContentBackups.moveAside(project: project, content: target, now: now)

    if strategy == .symlink {
      try Posix.symlink(source, target)
      return
    }
    let total = try countFiles(source)
    var processed = 0
    try Posix.mkdirs(target)
    try TreeCopy.copy(from: source, to: target, verbatimSymlinks: false) { relative in
      processed += 1
      progress?(processed, total, relative.isEmpty ? source : NodePath.join(source, relative))
      return true
    }
  }

  /// `relative()` rather than a prefix: /notes-old is no child of /notes.
  static func contains(_ parent: String, _ child: String) -> Bool {
    parent == child || child.hasPrefix(parent == "/" ? "/" : parent + "/")
  }
}
