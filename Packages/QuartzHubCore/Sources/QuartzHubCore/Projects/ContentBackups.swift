import Darwin
import Foundation

/// A port of `electron/main/services/backupService.ts`: what a switch of the content source moves
/// aside, under `.quartz-gui/content-backups/<timestamp>/` (a folder as `content/`, a link as
/// `symlink.json` with its target, the vault behind it untouched), listed, restored and deleted.
/// Not a backup, and not in a snapshot either (the store skips this folder): the only copy.
///
/// Paths are strings here and names come from `readdir` as they are: Foundation decomposes a name
/// on its way to the disk ("Über" becomes U+0055 U+0308), and a folder moved aside and copied back
/// has to keep the bytes Node and Quartz read.
public enum ContentBackups {
  public struct Entry: Equatable, Sendable {
    public enum Kind: String, Sendable { case folder, link }
    public var id: String
    public var createdAt: String
    public var kind: Kind
    /// A folder's real cost, walked; a link costs nothing.
    public var sizeBytes: Int
    public var fileCount: Int
    /// Where a link pointed; nil when its record is unreadable.
    public var target: String?
  }

  public struct Failure: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var description: String { message }
  }

  static let idPattern = #"^(\d{4}-\d{2}-\d{2}T\d{2})-(\d{2})-(\d{2})-(\d{3})Z\z"#

  /// A read path: listing never creates the folder (QuartzControl measured an empty
  /// content-backups/ and an edited .gitignore in every project merely opened).
  static func root(_ project: URL) -> String { "\(project.path)/.quartz-gui/content-backups" }

  /// "2026-08-22T10-00-00-000Z" → "2026-08-22T10:00:00.000Z"; anything else as it is.
  static func idToIso(_ id: String) -> String {
    guard let match = JSText.matches(id, idPattern).first else { return id }
    let g = match.groups.map { $0 ?? "" }
    return "\(g[1]):\(g[2]):\(g[3]).\(g[4])Z"
  }

  /// `snapshotContent`: the current content folder aside. Nothing there (a dangling link counts as
  /// nothing, `existsSync` follows it), nothing to do.
  @discardableResult
  public static func moveAside(project: URL, content: String, now: Date) throws -> Entry? {
    guard Posix.exists(content) else { return nil }
    let id = JSONStore.quarantineStamp(now)
    let base = try QuartzGuiDirectory(project: project).create("content-backups")
    let dir = "\(base.path)/\(id)"
    try Posix.mkdirs(dir)
    if Posix.kind(content) == .link {
      // Only the link is recorded; its target is left as it is.
      let target = try Posix.readlink(content)
      try Posix.write("\(dir)/symlink.json", Data(JSJSON.stringify(.object(JSONObject([("target", .string(target))]))).utf8))
      try Posix.unlink(content)
      return Entry(id: id, createdAt: JS.isoString(now), kind: .link, sizeBytes: 0, fileCount: 0, target: target)
    }
    try Posix.rename(content, "\(dir)/content")
    let (size, count) = measure("\(dir)/content")
    return Entry(id: id, createdAt: JS.isoString(now), kind: .folder, sizeBytes: size, fileCount: count, target: nil)
  }

  /// What a folder costs, walked: links counted as the link, never followed into a vault.
  static func measure(_ dir: String) -> (size: Int, count: Int) {
    var size = 0, count = 0
    func walk(_ current: String) {
      guard let entries = Posix.entries(current) else { return }
      for entry in entries {
        let full = "\(current)/\(entry.name)"
        if entry.kind == .directory {
          walk(full)
        } else {
          count += 1
          var info = stat()
          if lstat(full, &info) == 0 { size += Int(info.st_size) }
        }
      }
    }
    walk(dir)
    return (size, count)
  }

  /// Newest first. Only folders named by a timestamp: a `.DS_Store` would be an entry without a
  /// date whose restore can only fail.
  public static func list(project: URL) -> [Entry] {
    let root = root(project)
    guard let entries = Posix.entries(root) else { return [] }
    return entries.filter { $0.kind == .directory && JSText.test($0.name, idPattern) }.map { entry in
      let dir = "\(root)/\(entry.name)"
      let marker = "\(dir)/symlink.json"
      if Posix.exists(marker) {
        // An unreadable record still describes a link, just not where it pointed.
        let target = (try? Posix.read(marker)).flatMap { try? JSJSON.parse($0) }?["target"]?.stringValue
        return Entry(id: entry.name, createdAt: idToIso(entry.name), kind: .link, sizeBytes: 0, fileCount: 0, target: target)
      }
      let (size, count) = measure("\(dir)/content")
      return Entry(id: entry.name, createdAt: idToIso(entry.name), kind: .folder, sizeBytes: size, fileCount: count, target: nil)
    }
    .sorted { $0.createdAt > $1.createdAt }
  }

  /// The only copy there is; a name that is no timestamp is no entry and stays.
  public static func delete(project: URL, id: String) throws {
    let dir = "\(root(project))/\(id)"
    guard JSText.test(id, idPattern), Posix.exists(dir) else { return }
    try FileManager.default.removeItem(atPath: dir)
  }

  /// The current folder goes aside first, so a restore can be undone too. A folder is copied, not
  /// moved: a rename emptied the entry, and its second restore failed.
  public static func restore(project: URL, content: String, id: String, now: Date) throws {
    let dir = "\(root(project))/\(id)"
    if Posix.exists(content) { try moveAside(project: project, content: content, now: now) }
    let marker = "\(dir)/symlink.json"
    if Posix.exists(marker) {
      let record: JSONValue
      do { record = try JSJSON.parse(try Posix.read(marker)) } catch { throw Failure(message: "\(error)") }
      guard let target = record["target"]?.stringValue else { throw Failure(message: "symlink.json without a target") }
      try Posix.symlink(target, content)
      return
    }
    let source = "\(dir)/content"
    guard Posix.kind(source) != nil else { throw NodeFileError(code: ENOENT, syscall: "lstat", path: source) }
    try TreeCopy.copy(from: source, to: content, verbatimSymlinks: false)
  }
}
