import Darwin
import Foundation

/// What lies in a build's output folder right now (QuartzControl's `getBuildOutput` in
/// `buildService.ts`, measured in BuildOutputTests against it). Nothing records that a build
/// happened, so the Übersicht and Vorschau & Build describe the folder as it is on disk: how many
/// files, how large, and the newest file's time as "when it was built".
public enum BuildOutput {
  public struct Info: Sendable, Equatable {
    /// As `BuildOutputGuard.buildDirectory` interprets the setting; may lie outside the project.
    public var dir: String
    /// At least one file: an empty folder (or one with only empty folders) is no build.
    public var exists: Bool
    /// The newest file's modification, as `toISOString` writes it; nil without files.
    public var builtAt: String?
    public var fileCount: Int
    public var sizeBytes: Int
    public var looksLikeBuild: Bool

    public init(dir: String, exists: Bool, builtAt: String? = nil, fileCount: Int = 0, sizeBytes: Int = 0, looksLikeBuild: Bool = false) {
      self.dir = dir
      self.exists = exists
      self.builtAt = builtAt
      self.fileCount = fileCount
      self.sizeBytes = sizeBytes
      self.looksLikeBuild = looksLikeBuild
    }

    /// `builtAt` as a date, for "vor 3 Minuten".
    public var builtDate: Date? { builtAt.flatMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0) } }
  }

  /// A folder below the output that could not be listed. QuartzControl's walk rejected then, and
  /// the tile waited for an answer that never came; here the caller gets an error it can show.
  public struct Unreadable: Error, Equatable {
    public var path: String
  }

  /// The walk as QuartzControl's: a folder (by the entry's own type, so a link to a folder is not
  /// entered) is walked, anything else is `stat`ed through its link and counted; an entry that
  /// vanished or dangles between listing and `stat` is skipped (a build running right now).
  public static func info(project: String, outputDir: String? = nil) throws(Unreadable) -> Info {
    let dir = BuildOutputGuard.buildDirectory(project: project, outputDir: outputDir)
    var top = stat()
    guard stat(dir, &top) == 0, top.st_mode & S_IFMT == S_IFDIR else { return Info(dir: dir, exists: false) }

    var count = 0, size = 0
    // Milliseconds as Node's `mtimeMs`; Date truncates them to whole ones.
    var newest = 0.0
    func walk(_ current: String) throws(Unreadable) {
      guard let entries = Posix.entries(current) else { throw Unreadable(path: current) }
      for entry in entries {
        let full = "\(current)/\(entry.name)"
        if entry.kind == .directory {
          try walk(full)
          continue
        }
        var info = stat()
        guard stat(full, &info) == 0 else { continue }
        count += 1
        size += Int(info.st_size)
        let modified = Double(info.st_mtimespec.tv_sec) * 1000 + Double(info.st_mtimespec.tv_nsec) / 1_000_000
        if modified > newest { newest = modified }
      }
    }
    try walk(dir)

    let builtAt = newest > 0 ? JS.isoString(Date(timeIntervalSince1970: newest.rounded(.towardZero) / 1000)) : nil
    return Info(dir: dir, exists: count > 0, builtAt: builtAt, fileCount: count, sizeBytes: size,
                looksLikeBuild: BuildOutputGuard.looksLikeQuartzBuild(dir))
  }
}
