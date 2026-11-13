import Darwin
import Foundation

extension ContentFolder {
  public enum SourceStrategy: String, Sendable { case copy, symlink }

  /// `createSnapshot(project, kind, label)`, before the switch.
  public typealias Snapshot = @Sendable (_ project: String, _ kind: String, _ label: String) async throws -> Void
  /// After each file the copy took: done so far, the files there are, the file's path. Counted as
  /// the total is (`countFiles`: visible files, no folders), and never past it; QuartzControl
  /// counted every entry, hidden ones and folders too, and showed „350 / 200“ (review 2026-11-13,
  /// handbook, N13). A linked folder the total followed and the copy keeps as a link may leave the
  /// count short of the total; the copy's end says it is done.
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
      let path = relative.isEmpty ? source : NodePath.join(source, relative)
      var info = stat()
      let isFolder = stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
      if !relative.isEmpty, !isFolder, !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
        processed = min(processed + 1, total)
        progress?(processed, total, path)
      }
      return true
    }
  }

  /// `relative()` rather than a prefix: /notes-old is no child of /notes.
  static func contains(_ parent: String, _ child: String) -> Bool {
    parent == child || child.hasPrefix(parent == "/" ? "/" : parent + "/")
  }
}
