import Darwin
import Foundation

/// "Does it stay inside" and "does the way there lead through a link": a port of `containedPath`
/// and `writableTarget` in `templatePackage/shared.ts`, for every name a form or a template package
/// hands in (the snippets now, the template import with point 6).
public enum PackagePaths {
  /// `resolve(dir, name)` when that lies strictly inside `dir`; nil for `dir` itself, anything above
  /// it and an absolute name elsewhere.
  public static func contained(_ dir: String, _ name: String) -> String? {
    let target = JSText.startsWith(name, "/") ? NodePath.normalize(name) : NodePath.join(NodePath.normalize(dir), name)
    let relative = NodePath.relative(NodePath.normalize(dir), target)
    if relative.isEmpty || JSText.startsWith(relative, "..") || JSText.startsWith(relative, "/") { return nil }
    return trimTrailingSlash(target)
  }

  static func trimTrailingSlash(_ path: String) -> String {
    path.count > 1 && JSText.endsWith(path, "/") ? JSText.slice(path, 0, JSText.length(path) - 1) : path
  }

  /// `contained`, and no segment on the way (the file included) is a link: `content/notizen` →
  /// ~/Obsidian/Vault would turn a write into one into that vault. A segment that does not exist yet
  /// is fine, mkdir then makes a real folder.
  public static func writable(_ dir: String, _ name: String) -> String? {
    guard let target = contained(dir, name) else { return nil }
    var current = NodePath.normalize(dir)
    for segment in JSText.split(NodePath.relative(NodePath.normalize(dir), target), "/") {
      current = NodePath.join(current, segment)
      var info = stat()
      if lstat(current, &info) != 0 { return target }
      if (info.st_mode & S_IFMT) == S_IFLNK { return nil }
    }
    return target
  }
}

/// Node's error for a failed file call, as `String(err)` prints it: `Error: ENOENT: no such file or
/// directory, stat '/x'`. Only the codes the ports meet. Without a path where Node names none
/// (`readFileSync` on a folder: `EISDIR: illegal operation on a directory, read`).
/// `LocalizedError`: shown through `localizedDescription`, as the app shows any error, it read
/// „(QuartzHubCore.NodeFileError-Fehler 1.)“ instead of Node's text, which QuartzControl shows
/// (measured 2026-11-09 with quartz/static/images a file).
struct NodeFileError: Error, CustomStringConvertible, LocalizedError {
  var errorDescription: String? { description }

  let code: Int32
  let syscall: String
  var path: String?

  var description: String {
    let (name, text): (String, String) = switch code {
    case ENOENT: ("ENOENT", "no such file or directory")
    case EACCES: ("EACCES", "permission denied")
    case EISDIR: ("EISDIR", "illegal operation on a directory")
    case ENOTDIR: ("ENOTDIR", "not a directory")
    case EEXIST: ("EEXIST", "file already exists")
    case EPERM: ("EPERM", "operation not permitted")
    case ENOTEMPTY: ("ENOTEMPTY", "directory not empty")
    default: ("E\(code)", String(cString: strerror(code)).lowercased())
    }
    return "Error: \(name): \(text), \(syscall)" + (path.map { " '\($0)'" } ?? "")
  }

  /// `fs.stat`: follows links.
  static func statFollowing(_ path: String) throws -> Darwin.stat {
    var info = Darwin.stat()
    guard stat(path, &info) == 0 else { throw NodeFileError(code: errno, syscall: "stat", path: path) }
    return info
  }
}
