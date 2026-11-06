import Darwin
import Foundation

/// The project's `content/`: what it is, how much is in it, and getting a link to a vault out of
/// git's way. The reading half of `contentService.ts` and all of `contentSymlink.ts`. Changing the
/// source, the start page and the form usages need the config, the snapshots and the project's
/// globby and come with those.
public enum ContentFolder {
  public struct Status: Equatable, Sendable {
    public var path: URL
    /// Something is there, a folder or a link (dangling or not).
    public var exists: Bool
    public var isSymlink: Bool
    /// The link's target as it is written, relative or not.
    public var symlinkTarget: String?
    public var targetExists: Bool?
    /// The entries that are not hidden, through links; nil for a link that leads nowhere.
    public var fileCount: Int?
    /// An `index.md` at the top, in any case: without it the site has no page at its own address.
    public var hasIndex: Bool?
  }

  public static func path(project: URL) -> URL {
    project.appendingPathComponent("content", isDirectory: true)
  }

  /// `getContentStatus`. Asked with `lstat`, not `fileExists`: the second follows the link, and a
  /// `content/` pointing at a drive that is not mounted would read as "no content folder", which
  /// every writer that asks first takes as "free to create one".
  public static func status(project: URL) throws -> Status {
    let content = path(project: project)
    var info = stat()
    guard lstat(content.path, &info) == 0 else {
      return Status(path: content, exists: false, isSymlink: false)
    }
    guard (info.st_mode & S_IFMT) == S_IFLNK else {
      return Status(path: content, exists: true, isSymlink: false,
                    fileCount: try countFiles(content), hasIndex: hasIndexPage(content))
    }
    let target = try FileManager.default.destinationOfSymbolicLink(atPath: content.path)
    // Relative to the link's own folder, not to whoever asks: QuartzControl once resolved it
    // against the working directory and called a working `../vault` broken.
    let resolved = target.hasPrefix("/") ? URL(fileURLWithPath: target)
      : project.appendingPathComponent(target).standardized
    let targetExists = FileManager.default.fileExists(atPath: resolved.path)
    return Status(path: content, exists: true, isSymlink: true, symlinkTarget: target, targetExists: targetExists,
                  fileCount: targetExists ? try countFiles(resolved) : nil,
                  hasIndex: targetExists ? hasIndexPage(resolved) : nil)
  }

  /// `countFiles`: hidden entries are not content (a vault's `.git` and `.obsidian` made 1392 of
  /// 273 in QuartzControl's measurement), links are followed and not counted as one file, a link
  /// back to a folder already seen is cut, and a dangling link counts as nothing.
  static func countFiles(_ dir: URL) throws -> Int {
    var visited: Set<String> = [realPath(dir.path) ?? dir.path]
    return try countFiles(dir, visited: &visited)
  }

  private static func countFiles(_ dir: URL, visited: inout Set<String>) throws -> Int {
    var count = 0
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where !name.hasPrefix(".") {
      let full = dir.appendingPathComponent(name)
      // stat follows a link, lstat does not; a link whose target is gone fails stat and is skipped.
      var info = stat()
      guard stat(full.path, &info) == 0 else { continue }
      guard (info.st_mode & S_IFMT) == S_IFDIR else {
        count += 1
        continue
      }
      guard let real = realPath(full.path), visited.insert(real).inserted else { continue }
      count += try countFiles(full, visited: &visited)
    }
    return count
  }

  /// `hasIndexPage`: Quartz lowercases every slug, so `Index.md` is the start page too.
  static func hasIndexPage(_ dir: URL) -> Bool {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
    return names.contains { $0.lowercased() == "index.md" }
  }

  /// `withContentSymlinkParked`: git cannot write through a symbolic link, so a merge, a stash or a
  /// reset that touches `content/` fails while it links to a vault ("'content/.gitkeep' is beyond
  /// a symbolic link"). The link is removed, never the vault; git may populate a real `content/`
  /// meanwhile, and afterwards that is thrown away and the link put back with its target as it
  /// was written. A failure to put it back wins over the body's, as a JavaScript `finally` that
  /// throws does.
  public static func withSymlinkParked<T>(project: URL, _ body: () async throws -> T) async throws -> T {
    let content = path(project: project)
    var info = stat()
    guard lstat(content.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK else { return try await body() }
    let target = try FileManager.default.destinationOfSymbolicLink(atPath: content.path)
    try FileManager.default.removeItem(at: content)  // the link itself

    let outcome: Result<T, Error>
    do { outcome = .success(try await body()) } catch { outcome = .failure(error) }

    // Whatever is there now is git's (removeItem on a link would take only the link).
    if lstat(content.path, &info) == 0 { try FileManager.default.removeItem(at: content) }
    try FileManager.default.createSymbolicLink(atPath: content.path, withDestinationPath: target)
    return try outcome.get()
  }

  static func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}
