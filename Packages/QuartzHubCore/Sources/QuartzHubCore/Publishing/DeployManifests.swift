import CryptoKit
import Foundation

/// One line of a deploy's diff (`DeployDiffEntry`).
public struct DeployDiffEntry: Equatable, Sendable {
  public enum Status: String, Sendable { case added, changed, removed }
  public var path: String
  public var status: Status

  public init(path: String, status: Status) {
    self.path = path
    self.status = status
  }

  public var json: JSONValue { .object(JSONObject([("path", .string(path)), ("status", .string(status.rawValue))])) }
}

/// What QuartzHub last sent to one target (`deploy/manifest.ts`): `.quartz-gui/deploy-manifest-
/// <targetId>.json`, path relative to the build → sha-256 hex. Per target, because after a deploy
/// to A a shared record already matched the build, and B got nothing. There is no cheap way to ask
/// a server what it holds (rsync is the exception and keeps none), so "what was sent there" is the
/// best answer.
///
/// QuartzControl's form: written with a plain write, read with a bare parse; one that cannot be
/// read means "upload everything". Read paths never create `.quartz-gui/`.
public struct DeployManifests: Sendable {
  public let project: String
  let now: @Sendable () -> Date

  public init(project: String, now: @escaping @Sendable () -> Date = { Date() }) {
    self.project = project
    self.now = now
  }

  var directory: QuartzGuiDirectory { QuartzGuiDirectory(project: project) }
  var legacy: String { directory.file("deploy-manifest.json") }

  static func parse(_ path: String) -> DeployManifest? {
    guard let data = try? Posix.read(path), let value = try? JSJSON.parse(data) else { return nil }
    return DeployManifest(value)
  }

  /// `readManifest`. The one manifest from before targets existed is adopted by whichever target
  /// asks first, and renamed in the process, so the second starts from a full upload.
  public func read(_ targetId: String) -> DeployManifest {
    let path = directory.deployManifest(targetId)
    if let manifest = Self.parse(path) { return manifest }
    guard Posix.exists(legacy) else { return DeployManifest(.object(JSONObject())) }
    try? Posix.rename(legacy, path)
    return Self.parse(path) ?? DeployManifest(.object(JSONObject()))
  }

  func write(_ targetId: String, _ manifest: DeployManifest) throws {
    try directory.create()
    try Posix.write(directory.deployManifest(targetId), Data(JSJSON.stringify(manifest.json).utf8))
  }

  /// Throws the record away, so the next diff offers the whole build: when a target is pointed
  /// elsewhere, and as "Alles neu hochladen" for what QuartzHub cannot see (a file removed on the
  /// server by hand, a half-finished transfer, a restore from the provider's backup).
  public func forget(_ targetId: String) {
    try? Posix.unlink(directory.deployManifest(targetId))
  }

  // The two one-time passes of 1.1.1, beside the manifest and named like it.
  func modesMarker(_ targetId: String) -> String { directory.file("deploy-manifest-\(targetId).modes.json") }
  func tildeMarker(_ targetId: String) -> String { directory.file("deploy-manifest-\(targetId).tilde.json") }

  /// Whether the files sent over SFTP before 1.1.1 have had their mode set to 0644.
  public func modesSettled(_ targetId: String) -> Bool { Posix.exists(modesMarker(targetId)) }

  public func settleModes(_ targetId: String) throws {
    try directory.create()
    let marker = JSONObject([("mode", .string("0644")), ("at", .string(JS.isoString(now())))])
    try Posix.write(modesMarker(targetId), Data(JSJSON.stringify(.object(marker)).utf8))
  }

  /// Before 1.1.1, "~/blog" over SFTP against OpenSSH went into a folder "~" in the login
  /// directory, so a manifest from then describes another folder than the path names now. Once
  /// per target every hash is cleared: everything goes up again, and what was published can still
  /// be deleted.
  public func reanchorTilde(_ targetId: String) throws {
    if Posix.exists(tildeMarker(targetId)) { return }
    let manifest = read(targetId)
    if !manifest.paths.isEmpty {
      try write(targetId, DeployManifest(.object(JSONObject(manifest.paths.map { ($0, .string("")) }))))
    }
    try directory.create()
    try Posix.write(tildeMarker(targetId), Data(JSJSON.stringify(.object(JSONObject([("at", .string(JS.isoString(now())))]))).utf8))
  }

  /// Every file below the build, relative, in the walk's order (each folder's names by their
  /// bytes, as Node's readdir). A link counts as a file and is hashed through, as
  /// `createReadStream` follows it.
  static func walk(_ dir: String, base: String = "") throws -> [String] {
    guard let entries = Posix.entries(dir) else { throw Posix.error("scandir", dir) }
    var files: [String] = []
    for entry in entries {
      let relative = base.isEmpty ? entry.name : "\(base)/\(entry.name)"
      if entry.kind == .directory {
        files += try walk("\(dir)/\(entry.name)", base: relative)
      } else {
        files.append(relative)
      }
    }
    return files
  }

  static func hash(_ path: String) throws -> String {
    let fd = open(path, O_RDONLY | O_CLOEXEC)
    guard fd >= 0 else { throw Posix.error("open", path) }
    defer { close(fd) }
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
      if count < 0 {
        if errno == EINTR { continue }
        throw Posix.error("read", path)
      }
      if count == 0 { break }
      hasher.update(data: buffer[..<count])
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// `buildCurrentManifest`: one file at a time, streamed. QuartzControl hashed 32 at once and
  /// wrote the keys in the order the hashes finished; here they are in the walk's order.
  public static func current(_ buildDir: String) throws -> DeployManifest {
    var object = JSONObject()
    for file in try walk(buildDir) { object[file] = .string(try hash("\(buildDir)/\(file)")) }
    return DeployManifest(.object(object))
  }

  /// A manifest's entries by the bytes of their path: `path in previous` is exact in JavaScript,
  /// where a Swift dictionary takes "ä" and "a\u{308}" for one key.
  static func byBytes(_ manifest: DeployManifest) -> [[UInt8]: JSONValue] {
    var map: [[UInt8]: JSONValue] = [:]
    for path in manifest.paths { map[Array(path.utf8)] = manifest.object[path] }
    return map
  }

  /// `diffAgainstManifest`, sorted as `localeCompare`.
  public func diff(_ targetId: String, buildDir: String) throws -> [DeployDiffEntry] {
    let previous = read(targetId), current = try Self.current(buildDir)
    let before = Self.byBytes(previous), now = Self.byBytes(current)
    var entries: [DeployDiffEntry] = []
    for path in current.paths {
      guard let old = before[Array(path.utf8)] else {
        entries.append(.init(path: path, status: .added))
        continue
      }
      if old != now[Array(path.utf8)] { entries.append(.init(path: path, status: .changed)) }
    }
    for path in previous.paths where now[Array(path.utf8)] == nil { entries.append(.init(path: path, status: .removed)) }
    JS.sort(&entries) { JS.localeCompare($0.path, $1.path) }
    return entries
  }

  /// `commitManifest`: the build as sent, except what was not acted on. An excluded file keeps its
  /// previous entry, or has none when it never went up; an excluded removal stays known, so a
  /// later run still offers it.
  public func commit(_ targetId: String, buildDir: String, excluding excludePaths: [String]) throws {
    let current = try Self.current(buildDir)
    let excluded = Set(excludePaths.map { Array($0.utf8) })
    let previous = read(targetId)
    let before = Self.byBytes(previous), now = Self.byBytes(current)
    var next = JSONObject()
    for path in current.paths {
      if excluded.contains(Array(path.utf8)) {
        if let old = before[Array(path.utf8)] { next[path] = old }
        continue
      }
      next[path] = now[Array(path.utf8)]
    }
    for path in previous.paths where now[Array(path.utf8)] == nil && excluded.contains(Array(path.utf8)) {
      next[path] = before[Array(path.utf8)]
    }
    try write(targetId, DeployManifest(.object(next)))
  }

  public struct Partition: Equatable, Sendable {
    public var toUpload: [String]
    public var toDelete: [String]
    /// What has to count as not acted on when the manifest is committed.
    public var manifestExcludes: [String]
  }

  /// `partitionDiff`. Two ways a removal does not happen, and both must stay in the manifest: the
  /// user unticked it, or the target does not delete. Without the third list a file that vanished
  /// locally dropped out as though deleted remotely, and no later run offered it again.
  public static func partition(_ diff: [DeployDiffEntry], excluding excludePaths: [String], deleteRemoved: Bool) -> Partition {
    let excluded = Set(excludePaths.map { Array($0.utf8) })
    let removable = diff.filter { $0.status == .removed && !excluded.contains(Array($0.path.utf8)) }.map(\.path)
    return Partition(toUpload: diff.filter { $0.status != .removed && !excluded.contains(Array($0.path.utf8)) }.map(\.path),
                     toDelete: deleteRemoved ? removable : [],
                     manifestExcludes: deleteRemoved ? excludePaths : excludePaths + removable)
  }
}
