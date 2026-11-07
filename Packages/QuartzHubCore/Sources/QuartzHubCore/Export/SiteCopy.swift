import Darwin
import Foundation
import Synchronization

/// The built site, served to the export window from a copy (`siteServer.ts`).
///
/// A copy, because the build folder has a writer of its own: `quartz build --serve` rewrites
/// public/ on every change, and an export that read page 30 of one build and page 31 of the next
/// would print a document no build ever was. On APFS the copy is a clone and costs next to
/// nothing. Without the links in the build: Quartz writes none, and one that is there may point
/// anywhere on this disk (QuartzControl's review of 2026-11-06, M1: a script of the site read a
/// file outside the build through /static/<link>).
///
/// Paths resolve like a static host: `/a` is `a.html`, `/a/` is `a/index.html`. Documents the
/// export assembles itself are answered from memory under `/__quartzcontrol/`, before any file is
/// looked at. How the answers reach the window is 9b's; `answer(pathname:)` is the same for any
/// transport. One difference: the copies are named `quartzhub-export-…`, so QuartzHub sweeps its
/// own and not QuartzControl's.
public final class SiteCopy: Sendable {
  public static let ownPrefix = "/__quartzcontrol/"
  public static let tempPrefix = "quartzhub-export-"

  static let types: [String: String] = [
    ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp", ".avif": "image/avif", ".ico": "image/x-icon", ".woff": "font/woff",
    ".woff2": "font/woff2", ".ttf": "font/ttf", ".otf": "font/otf", ".mp4": "video/mp4", ".webm": "video/webm", ".mp3": "audio/mpeg",
    ".pdf": "application/pdf", ".xml": "application/xml", ".txt": "text/plain; charset=utf-8"
  ]

  /// The copy the answers are read from.
  public let root: String
  private let documents = Mutex<[String: String]>([:])

  init(root: String) { self.root = root }

  /// Copies `buildDir` into a new folder under `tempRoot`, links left out.
  public static func make(from buildDir: String, tempRoot: String = NSTemporaryDirectory()) throws -> SiteCopy {
    var template = Array(NodePath.join(tempRoot, "\(tempPrefix)XXXXXX").utf8CString)
    guard let made = mkdtemp(&template) else { throw NodeFileError(code: errno, syscall: "mkdtemp", path: tempRoot) }
    let root = String(cString: made)
    do {
      try TreeCopy.copy(from: buildDir, to: root, verbatimSymlinks: true) { relative in
        guard !relative.isEmpty else { return true }
        var info = stat()
        return lstat(NodePath.join(buildDir, relative), &info) == 0 && (info.st_mode & S_IFMT) != S_IFLNK
      }
    } catch {
      try? FileManager.default.removeItem(atPath: root)
      throw error
    }
    return SiteCopy(root: root)
  }

  /// Serves `html` at `/__quartzcontrol/<name>` until replaced; the path is the answer.
  public func setDocument(_ name: String, _ html: String) -> String {
    documents.withLock { $0[name] = html }
    return Self.ownPrefix + name
  }

  public struct Answer: Equatable, Sendable {
    public var status: Int
    /// nil with a 404, which carries no type.
    public var type: String?
    public var body: Data
  }

  /// What the server answers for a URL path as the request carries it (escaped, no query).
  public func answer(pathname: String) -> Answer {
    if JSText.startsWith(pathname, Self.ownPrefix) {
      guard let html = documents.withLock({ $0[JSText.slice(pathname, JSText.length(Self.ownPrefix))] }) else { return Answer(status: 404, type: nil, body: Data()) }
      return Answer(status: 200, type: Self.types[".html"], body: Data(html.utf8))
    }
    guard let file = Self.resolveFile(root, pathname) else { return Answer(status: 404, type: nil, body: Data()) }
    guard let data = try? Posix.read(file) else { return Answer(status: 500, type: nil, body: Data()) }
    return Answer(status: 200, type: Self.types[NodePath.extname(file).lowercased()] ?? "application/octet-stream", body: data)
  }

  /// `resolveFile(root, pathname)`: the file a path names inside the copy, or nil - a broken
  /// escape, a way out of the copy (`..`), or nothing there.
  static func resolveFile(_ root: String, _ pathname: String) -> String? {
    guard let decoded = try? JSURI.decodeComponent(pathname) else { return nil }
    let base = NodePath.join(root, decoded)
    let rel = NodePath.relative(root, base)
    if JSText.startsWith(rel, "..") || JSText.startsWith(rel, "/") { return nil }
    let candidates = JSText.endsWith(decoded, "/") ? [NodePath.join(base, "index.html")] : [base, "\(base).html", NodePath.join(base, "index.html")]
    for candidate in candidates {
      var info = stat()
      if stat(candidate, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG { return candidate }
    }
    return nil
  }

  /// Removes the copy.
  public func close() { try? FileManager.default.removeItem(atPath: root) }

  /// `sweepExportTempDirs`: copies an earlier run left behind (an app that quit or crashed
  /// mid-export), older than an hour - a running export's own copy is younger. At startup, like
  /// the relay's sweep. A link of that name to a folder is removed as a link.
  @discardableResult
  public static func sweep(now: Date = Date(), tempRoot: String = NSTemporaryDirectory()) -> [String] {
    var removed: [String] = []
    for entry in Posix.entries(tempRoot) ?? [] where JSText.startsWith(entry.name, tempPrefix) {
      let dir = NodePath.join(tempRoot, entry.name)
      var info = stat()
      guard stat(dir, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
      let modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
      if now.timeIntervalSince1970 - modified < 3600 { continue }
      try? FileManager.default.removeItem(atPath: dir)
      removed.append(dir)
    }
    return removed
  }
}
