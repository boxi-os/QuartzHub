import Darwin
import Foundation

/// The files a layout box renders (quartz-layout-box: `dir` + `file`) and the pictures they show
/// (quartz/static/images): a port of `snippetService.ts`. Both are written from a form, and every
/// name and folder is resolved here against the project: nothing is written outside it, through a
/// link, or into a folder that belongs to a tool (`.git`, `node_modules`, `.quartz`,
/// `.quartz-gui`, the build output). Reading through a link is allowed, as layout-box and the build
/// read through one.
public struct Snippets: Sendable {
  public typealias Trash = @Sendable (URL) throws -> Void

  /// The system's trash, not a delete: a file in quartz/static is in no snapshot unless one was made
  /// before, and the trash is the way back that needs no foresight.
  public static let systemTrash: Trash = { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }

  let trash: Trash
  public init(trash: @escaping Trash = Snippets.systemTrash) { self.trash = trash }

  static let snippetExtensions = [".html", ".htm", ".md"]
  static let imageExtensions = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".avif"]
  /// A snippet is a few paragraphs, a picture a few hundred kilobytes; both caps are far above that
  /// and far below what makes a public repository a problem.
  static let snippetMaxBytes = 2 * 1024 * 1024
  static let imageMaxBytes = 20 * 1024 * 1024
  static let reserved: Set<String> = [".git", "node_modules", ".quartz", ".quartz-gui"]
  public static let imagesDirectory = "quartz/static/images"

  public struct Failure: Error, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { "Error: " + message }
  }

  public enum DirectoryState: String, Sendable { case ok, link, missing, outside, reserved }

  enum DirectoryCheck {
    case ok(abs: String, viaLink: Bool)
    case refused(DirectoryState)
  }

  /// Where `dir` (relative to the project, as layout-box reads it) leads, or why it may not be used.
  static func check(_ project: URL, _ dir: String) -> DirectoryCheck {
    let root = NodePath.normalize(project.path)
    if JSText.startsWith(dir, "/") { return .refused(.outside) }
    // `.` is the project itself, an odd place for snippets, but inside.
    let abs: String
    if NodePath.relative(root, NodePath.join(root, dir)).isEmpty { abs = root } else {
      guard let contained = PackagePaths.contained(root, dir) else { return .refused(.outside) }
      abs = contained
    }
    // Without regard to case: APFS takes `.GIT` for `.git`.
    if JSText.split(NodePath.relative(root, abs), "/").contains(where: { reserved.contains($0.lowercased()) }) { return .refused(.reserved) }
    // The build output is emptied by every build; a snippet there is gone with the next one.
    let output = ProjectPrefsStore.read(project: project).buildDirectory(project: project).path
    let relative = NodePath.relative(NodePath.normalize(output), abs)
    if relative.isEmpty || !JSText.startsWith(relative, "..") { return .refused(.reserved) }
    let viaLink = abs != root && PackagePaths.writable(root, NodePath.relative(root, abs)) == nil
    return .ok(abs: abs, viaLink: viaLink)
  }

  static func refusal(_ state: DirectoryState, _ dir: String) -> Failure {
    state == .outside ? Failure(message: L10n.t("main.snippetDirOutside", ["dir": dir])) : Failure(message: L10n.t("main.snippetDirReserved", ["dir": dir]))
  }

  /// One segment, not hidden, with an allowed extension. Subfolders are left to the config itself.
  static func checkName(_ name: String, _ allowed: [String]) throws -> String {
    let trimmed = JS.trim(name)
    if trimmed.isEmpty || JSText.length(trimmed) > 200 || JSText.test(trimmed, "[/\\\\:\\x{0}]") || JSText.startsWith(trimmed, ".") {
      throw Failure(message: L10n.t("main.snippetNameInvalid", ["name": name]))
    }
    guard allowed.contains(NodePath.extname(trimmed).lowercased()) else {
      throw Failure(message: L10n.t("main.snippetExtensionInvalid", ["name": trimmed, "allowed": allowed.joined(separator: ", ")]))
    }
    return trimmed
  }

  static func lstatInfo(_ path: String) -> Darwin.stat? {
    var info = Darwin.stat()
    return lstat(path, &info) == 0 ? info : nil
  }

  static func isFile(_ info: Darwin.stat) -> Bool { (info.st_mode & S_IFMT) == S_IFREG }

  public struct Listing: Equatable, Sendable {
    public var state: DirectoryState
    public var files: [String]
  }

  /// JavaScript's `a.localeCompare(b, undefined, { numeric: true })`: ICU collation, numbers by value.
  static func localeOrder(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.numeric], range: nil, locale: Locale(identifier: "de")) == .orderedAscending
  }

  func list(_ project: URL, _ dir: String, _ allowed: [String]) throws -> Listing {
    guard case .ok(let abs, let viaLink) = Self.check(project, dir) else {
      if case .refused(let state) = Self.check(project, dir) { return Listing(state: state, files: []) }
      return Listing(state: .outside, files: [])
    }
    guard let stream = opendir(abs) else {
      if errno == ENOENT { return Listing(state: .missing, files: []) }
      throw NodeFileError(code: errno, syscall: "scandir", path: abs)
    }
    closedir(stream)
    var files: [String] = []
    for entry in LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: abs)) {
      guard allowed.contains(NodePath.extname(entry.name).lowercased()), !JSText.startsWith(entry.name, ".") else { continue }
      // A link to a file counts as a file.
      if entry.kind == .file { files.append(entry.name); continue }
      if entry.kind == .link, let target = try? NodeFileError.statFollowing(NodePath.join(abs, entry.name)), Self.isFile(target) { files.append(entry.name) }
    }
    files.sort(by: Self.localeOrder)
    return Listing(state: viaLink ? .link : .ok, files: files)
  }

  public func listSnippets(project: URL, dir: String) throws -> Listing { try list(project, dir, Self.snippetExtensions) }

  /// The pictures in quartz/static/images, the folder "Bild einfügen…" copies into.
  public func listImages(project: URL) throws -> Listing { try list(project, Self.imagesDirectory, Self.imageExtensions) }

  public func readSnippet(project: URL, dir: String, file: String) throws -> String {
    let abs: String
    switch Self.check(project, dir) {
    case .refused(let state): throw Self.refusal(state, dir)
    case .ok(let found, _): abs = found
    }
    guard let path = PackagePaths.contained(abs, file), Self.snippetExtensions.contains(NodePath.extname(path).lowercased()) else {
      throw Failure(message: L10n.t("main.snippetNameInvalid", ["name": file]))
    }
    // What layout-box asks before it reads: a link inside the folder may point anywhere, so both
    // sides are resolved again. The folder itself may be a link.
    let realDir = try Self.realPath(abs), realFile = try Self.realPath(path)
    if PackagePaths.contained(realDir, NodePath.relative(realDir, realFile)) == nil {
      throw Failure(message: L10n.t("main.snippetDirOutside", ["dir": file]))
    }
    if Int(try NodeFileError.statFollowing(path).st_size) > Self.snippetMaxBytes {
      throw Failure(message: L10n.t("main.snippetTooLarge", ["name": file, "limit": "2"]))
    }
    return try StyleSheets.readText(URL(fileURLWithPath: path))
  }

  static func realPath(_ path: String) throws -> String {
    guard let resolved = realpath(path, nil) else { throw NodeFileError(code: errno, syscall: "realpath", path: path) }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  /// Where a new file may go in a checked folder, or the sentence why not.
  func writablePath(_ project: URL, _ dir: String, _ name: String, _ allowed: [String]) throws -> (abs: String, name: String) {
    let root = NodePath.normalize(project.path)
    let abs: String
    switch Self.check(project, dir) {
    case .refused(let state): throw Self.refusal(state, dir)
    case .ok(let found, _): abs = found
    }
    let clean = try Self.checkName(name, allowed)
    guard let target = PackagePaths.writable(root, NodePath.join(NodePath.relative(root, abs), clean)) else {
      throw Failure(message: L10n.t("main.snippetDirLink", ["dir": NodePath.join(dir, clean)]))
    }
    return (target, clean)
  }

  public enum Written: Equatable, Sendable {
    case written(String)
    /// The name is taken and was not touched; the page asks and calls again with `overwrite`.
    case exists(String)
  }

  public func writeSnippet(project: URL, dir: String, file: String, content: String, overwrite: Bool) throws -> Written {
    if content.utf8.count > Self.snippetMaxBytes { throw Failure(message: L10n.t("main.snippetTooLarge", ["name": file, "limit": "2"])) }
    let (abs, name) = try writablePath(project, dir, file, Self.snippetExtensions)
    if !overwrite && Self.lstatInfo(abs) != nil { return .exists(name) }
    try FileManager.default.createDirectory(atPath: (abs as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try JSONStore.writeAtomic(Data(content.utf8), to: URL(fileURLWithPath: abs))
    return .written(name)
  }

  /// Copies through a temporary name beside the target, so a reader never sees half of it.
  static func copyAtomic(_ source: String, _ target: String) throws {
    let temp = "\(target).tmp-\(getpid())-\(UUID().uuidString.lowercased().prefix(8))"
    do {
      try FileManager.default.copyItem(atPath: source, toPath: temp)
      let fd = open(temp, O_RDWR)
      if fd >= 0 { fsync(fd); close(fd) }
      if Darwin.rename(temp, target) != 0 { throw NodeFileError(code: errno, syscall: "rename", path: temp) }
    } catch {
      try? FileManager.default.removeItem(atPath: temp)
      throw error
    }
  }

  /// The source too, not only the name it gets: with a name from the form, any file could come in
  /// under an allowed name (`~/.ssh/id_ed25519` as `key.md`) and travel on with the next sync.
  func importFile(_ project: URL, _ dir: String, _ source: String, _ name: String?, _ overwrite: Bool, _ allowed: [String], _ maxBytes: Int) throws -> Written {
    let (abs, clean) = try writablePath(project, dir, name ?? NodePath.basename(source), allowed)
    guard allowed.contains(NodePath.extname(source).lowercased()) else {
      throw Failure(message: L10n.t("main.snippetExtensionInvalid", ["name": NodePath.basename(source), "allowed": allowed.joined(separator: ", ")]))
    }
    let info = try NodeFileError.statFollowing(source)
    guard Self.isFile(info) else { throw Failure(message: L10n.t("main.snippetNameInvalid", ["name": NodePath.basename(source)])) }
    if Int(info.st_size) > maxBytes {
      throw Failure(message: L10n.t("main.snippetTooLarge", ["name": clean, "limit": JSJSON.numberToString(FontFile.jsRound(Double(maxBytes) / 1024 / 1024))]))
    }
    if !overwrite && Self.lstatInfo(abs) != nil { return .exists(clean) }
    try FileManager.default.createDirectory(atPath: (abs as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try Self.copyAtomic(source, abs)
    return .written(clean)
  }

  public func importSnippet(project: URL, dir: String, source: String, name: String?, overwrite: Bool) throws -> Written {
    try importFile(project, dir, source, name, overwrite, Self.snippetExtensions, Self.snippetMaxBytes)
  }

  /// A picture into quartz/static/images, which Quartz publishes as static/images/: a snippet
  /// reaches it as `{{root}}/static/images/<name>` on every page depth. The answer is
  /// `images/<name>`.
  public func importImage(project: URL, source: String, name: String?, overwrite: Bool) throws -> Written {
    switch try importFile(project, Self.imagesDirectory, source, name, overwrite, Self.imageExtensions, Self.imageMaxBytes) {
    case .written(let name): .written("images/\(name)")
    case .exists(let name): .exists("images/\(name)")
    }
  }

  /// An SVG file's text, for "Bild einfügen" as code: a regular `.svg` file, no larger than a
  /// snippet may be. What the markup may not contain is `InlineSvg`'s to take out.
  public static func svgSource(_ source: String) throws -> String {
    let name = try checkName(NodePath.basename(source), [".svg"])
    let info = try NodeFileError.statFollowing(source)
    guard isFile(info) else { throw Failure(message: L10n.t("main.snippetNameInvalid", ["name": name])) }
    if Int(info.st_size) > snippetMaxBytes { throw Failure(message: L10n.t("main.snippetTooLarge", ["name": name, "limit": "2"])) }
    return try StyleSheets.readText(URL(fileURLWithPath: source))
  }

  public enum Kind: String, Sendable { case snippet, image }

  /// A snippet lives in its box's `dir`, a picture in quartz/static/images.
  static func place(_ kind: Kind, _ dir: String?) throws -> (dir: String, allowed: [String]) {
    if kind == .image { return (imagesDirectory, imageExtensions) }
    guard let dir, !dir.isEmpty else { throw Failure(message: L10n.t("main.snippetDirOutside", ["dir": ""])) }
    return (dir, snippetExtensions)
  }

  /// A file that is there, as a file of this kind, and not reached through a link.
  func existing(_ project: URL, _ dir: String, _ name: String, _ allowed: [String]) throws -> (abs: String, name: String) {
    let target = try writablePath(project, dir, name, allowed)
    guard let info = Self.lstatInfo(target.abs), Self.isFile(info) else { throw Failure(message: L10n.t("main.staticFileMissing", ["name": target.name])) }
    return target
  }

  /// Renames within its folder. A taken name is not overwritten: renaming over another file is a
  /// delete in disguise. A rename that only changes case finds itself on APFS, which is not "taken".
  public func rename(project: URL, kind: Kind, dir: String?, from: String, to: String) throws -> Written {
    let place = try Self.place(kind, dir)
    let source = try existing(project, place.dir, from, place.allowed)
    let target = try writablePath(project, place.dir, to, place.allowed)
    if target.abs == source.abs { return .written(target.name) }
    if Self.lstatInfo(target.abs) != nil, (try? Self.realPath(target.abs)) != (try? Self.realPath(source.abs)) { return .exists(target.name) }
    if Darwin.rename(source.abs, target.abs) != 0 { throw NodeFileError(code: errno, syscall: "rename", path: source.abs) }
    return .written(target.name)
  }

  /// To the trash. The system's reason comes after a sentence that says the file is untouched.
  public func moveToTrash(project: URL, kind: Kind, dir: String?, file: String) throws {
    let place = try Self.place(kind, dir)
    let (abs, _) = try existing(project, place.dir, file, place.allowed)
    do {
      try trash(URL(fileURLWithPath: abs))
    } catch {
      throw Failure(message: L10n.t("main.staticFileTrashFailed", ["name": file, "reason": error.localizedDescription]))
    }
  }
}
