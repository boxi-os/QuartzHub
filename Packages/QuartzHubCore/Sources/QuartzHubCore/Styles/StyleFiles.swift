import Foundation

/// The additional stylesheets under quartz/styles/custom and quartz/styles/imported: a port of the
/// file half of `styleService.ts` (list, read, write, create, rename, delete, import, the
/// read-only references of a plugin, and "Zusammenlegen"). Every writer holds `ProjectLock.styles`.
///
/// **The door checks the names.** QuartzControl's IPC schemas did (`styleFileSubPath`,
/// `styleEditablePath`, `styleFileName`): the value is joined onto the project and then written,
/// renamed and deleted. Here there is no IPC, so the same rules stand at the service, and a name
/// outside them is refused with `InvalidName` (a bug in the caller, so the text is English).
public enum StyleFiles {
  public struct InvalidName: Error, Equatable, CustomStringConvertible {
    public let value: String
    public var description: String { "not a valid stylesheet path or name: \(value)" }
  }

  /// `custom/<file>.scss|css` or `imported/…`, the file not starting with a dot.
  static func checkSubPath(_ path: String) throws {
    guard JSText.length(path) <= 1024, JSText.test(path, #"\A(custom|imported)/[A-Za-z0-9._-]+\.(scss|css)\z"#),
          !JSText.startsWith(JSText.split(path, "/")[1], ".") else { throw InvalidName(value: path) }
  }

  /// A sub path, or `_quartzcontrol.scss` (the CSS tab shows it, only to read and save).
  static func checkEditable(_ path: String) throws {
    if path == ManagedBlocks.managedFile { return }
    try checkSubPath(path)
  }

  /// One segment for a new or renamed stylesheet; the service appends `.scss`.
  static func checkName(_ name: String) throws {
    guard (1...96).contains(JSText.length(name)), JSText.test(name, #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#) else { throw InvalidName(value: name) }
  }

  public struct File: Equatable, Sendable {
    public var relativePath: String
    public var path: URL
    public var name: String
    public var imported: Bool
  }

  public struct FileSet: Equatable, Sendable {
    public var main: StyleSheets.Info
    /// The load order first, then what exists and is not loaded (a real state: the file is there
    /// and does nothing).
    public var files: [File]
    public var consolidated: Bool
  }

  static func file(_ project: URL, _ relativePath: String, imported: Bool) -> File {
    File(relativePath: relativePath, path: StyleSheets.styleFile(project, relativePath),
         name: JSText.split(relativePath, "/").dropFirst().joined(separator: "/"), imported: imported)
  }

  static func filesOnDisk(_ dir: URL) -> [String] {
    LayoutFrames.directoryEntriesWithKind(dir).filter { $0.kind == .file && JSText.test($0.name, #"\.(scss|css)\z"#) }.map(\.name)
  }

  public static func list(project: URL) throws -> FileSet {
    let main = try StyleSheets.readCustom(project: project)
    let order = StyleSheets.importOrder(project, StyleSheets.Sources(custom: main.content, managed: main.managed?.content ?? "", managedExists: main.managed != nil))
    var onDisk: [String] = []
    for dir in StyleSheets.styleDirectories {
      let full = StyleSheets.stylesDirectory(project).appendingPathComponent(dir)
      guard FileManager.default.fileExists(atPath: full.path) else { continue }
      onDisk += filesOnDisk(full).map { "\(dir)/\($0)" }
    }
    onDisk.sort { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    let ordered = order.filter(onDisk.contains)
    let orphans = onDisk.filter { !ordered.contains($0) }
    return FileSet(main: main, files: ordered.map { file(project, $0, imported: true) } + orphans.map { file(project, $0, imported: false) },
                   consolidated: StylesheetConsolidation.wasConsolidated(try consolidatedFiles(project), order))
  }

  public static func read(_ relativePath: String, project: URL) throws -> String {
    try checkEditable(relativePath)
    let path = StyleSheets.styleFile(project, relativePath)
    return FileManager.default.fileExists(atPath: path.path) ? try StyleSheets.readText(path) : ""
  }

  public static func write(_ relativePath: String, _ content: String, project: URL) async throws {
    try checkEditable(relativePath)
    try await ProjectLock.styles.run(project.path) { try writeNow(relativePath, content, project: project) }
  }

  /// Atomic, like custom.scss: the dev server imports this file on its own schedule.
  static func writeNow(_ relativePath: String, _ content: String, project: URL) throws {
    let path = StyleSheets.styleFile(project, relativePath)
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try StyleSheets.writeText(content, to: path)
  }

  struct Exists: Error, CustomStringConvertible {
    let name: String
    var description: String { "Error: " + L10n.t("main.styleFileExists", ["name": name]) }
  }

  static func fileName(_ name: String) -> String {
    JSText.test(name, #"\.(scss|css)\z"#) ? name : "\(name).scss"
  }

  /// A new stylesheet in custom/, switched on at the end of the load order.
  public static func create(_ name: String, project: URL) async throws -> File {
    try checkName(name)
    return try await ProjectLock.styles.run(project.path) {
      let fileName = fileName(name)
      let relativePath = "custom/\(fileName)"
      let path = StyleSheets.styleFile(project, relativePath)
      if FileManager.default.fileExists(atPath: path.path) { throw Exists(name: fileName) }
      try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("// \(fileName)\n".utf8).write(to: path)
      try StyleSheets.setImportOrderNow(try StyleSheets.currentOrder(project: project) + [relativePath], project: project)
      return File(relativePath: relativePath, path: path, name: fileName, imported: true)
    }
  }

  /// Renames within its directory and carries the place in the load order. The order is read
  /// *before* the rename: it is resolved against the disk, and afterwards the old name would no
  /// longer resolve and the file would drop out of it.
  public static func rename(_ relativePath: String, to newName: String, project: URL) async throws -> File {
    try checkSubPath(relativePath)
    try checkName(newName)
    return try await ProjectLock.styles.run(project.path) {
      let dir = JSText.split(relativePath, "/")[0]
      let fileName = fileName(newName)
      let next = "\(dir)/\(fileName)"
      if next == relativePath { return File(relativePath: relativePath, path: StyleSheets.styleFile(project, relativePath), name: fileName, imported: true) }
      let target = StyleSheets.styleFile(project, next)
      if FileManager.default.fileExists(atPath: target.path) { throw Exists(name: fileName) }
      let order = try StyleSheets.currentOrder(project: project).map { $0 == relativePath ? next : $0 }
      try FileManager.default.moveItem(at: StyleSheets.styleFile(project, relativePath), to: target)
      try StyleSheets.setImportOrderNow(order, project: project)
      return File(relativePath: next, path: target, name: fileName, imported: order.contains(next))
    }
  }

  /// The order first: a file left in the block after its deletion breaks the build, which is worse
  /// than a file left on disk after a failed unlink.
  public static func delete(_ relativePath: String, project: URL) async throws {
    try checkSubPath(relativePath)
    try await ProjectLock.styles.run(project.path) {
      try StyleSheets.setImportOrderNow(try StyleSheets.currentOrder(project: project).filter { $0 != relativePath }, project: project)
      let path = StyleSheets.styleFile(project, relativePath)
      if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
  }

  /// Copies a stylesheet into imported/ and answers the `@use` line for it.
  public static func importFile(_ source: URL, project: URL) async throws -> (importLine: String, relativePath: String) {
    try await ProjectLock.styles.run(project.path) {
      let dir = StyleSheets.stylesDirectory(project).appendingPathComponent("imported", isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let fileName = NodePath.basename(source.path)
      let target = dir.appendingPathComponent(fileName)
      if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
      try FileManager.default.copyItem(at: source, to: target)
      let specifier = "./imported/" + JSText.replaceAll(fileName, #"\.(scss|css)\z"#, with: "")
      return ("@use \"\(specifier)\";", "imported/\(fileName)")
    }
  }

  public struct Reference: Equatable, Sendable {
    public var label: String
    public var path: String
    public var content: String
  }

  static let ignoredDirectories: Set<String> = ["node_modules", ".git", "dist", ".changeset"]

  /// A CLI-installed plugin's own .scss files, read only, so the user sees the selectors they
  /// override; at most 20. Built-in plugins have no source on disk.
  public static func references(plugin: String, project: URL) throws -> [Reference] {
    guard !plugin.isEmpty, !JSText.includes(plugin, "/"), plugin != ".", plugin != ".." else { throw InvalidName(value: plugin) }
    let dir = NodePath.join(project.path, ".quartz/plugins", plugin)
    guard FileManager.default.fileExists(atPath: dir) else { return [] }
    var found: [String] = []
    func walk(_ current: String, _ depth: Int) {
      if depth > 6 { return }
      for entry in LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: current)) where !ignoredDirectories.contains(entry.name) {
        let full = NodePath.join(current, entry.name)
        if entry.kind == .directory { walk(full, depth + 1) } else if JSText.endsWith(entry.name, ".scss") { found.append(full) }
      }
    }
    walk(dir, 0)
    return try found.prefix(20).map { path in
      Reference(label: String(path.dropFirst(dir.count + 1)), path: path, content: try StyleSheets.readText(URL(fileURLWithPath: path)))
    }
  }

  // MARK: putting the 31 together

  /// The twelve names on disk with their content: `wasConsolidated` reads the header line a run
  /// wrote, where the load order names the file.
  static func consolidatedFiles(_ project: URL) throws -> [String: String] {
    var files: [String: String] = [:]
    for name in StylesheetConsolidation.order {
      let path = StyleSheets.styleFile(project, "custom/\(name).scss")
      if FileManager.default.fileExists(atPath: path.path) { files["custom/\(name).scss"] = try StyleSheets.readText(path) }
    }
    return files
  }

  public struct Consolidated: Equatable, Sendable {
    public var consolidated: Bool
    public var snapshotId: String?
    public var written: [String]
    public var merged: Int
    public var renamed: [(from: String, to: String)]

    public static func == (a: Consolidated, b: Consolidated) -> Bool {
      a.consolidated == b.consolidated && a.snapshotId == b.snapshotId && a.written == b.written && a.merged == b.merged
        && a.renamed.map(\.from) == b.renamed.map(\.from) && a.renamed.map(\.to) == b.renamed.map(\.to)
    }
  }

  /// A snapshot of the project, of the kind the thinning keeps (`styleMigration`); answers its id.
  /// One that fails stops the run before anything moves.
  public typealias Snapshot = @Sendable (_ project: URL, _ kind: String) async throws -> String?

  /// `SnapshotStore.take` in this shape.
  public static func snapshot(_ take: @escaping SnapshotStore.Take) -> Snapshot { { project, kind in try await take(project, kind, "") } }

  /// Puts the 31 together, asked for on the Styles page, never by a writer: it renames and removes
  /// files the user may have open. A snapshot first, as the way back. The order is read before
  /// anything moves, the new files are written before the order names them, the old ones go last,
  /// so every state in between builds.
  public static func consolidate(project: URL, snapshot: Snapshot) async throws -> Consolidated {
    try await ProjectLock.styles.run(project.path) {
      let order = try StyleSheets.currentOrder(project: project)
      let done = try consolidatedFiles(project)
      guard StylesheetConsolidation.canConsolidate(order, consolidated: StylesheetConsolidation.wasConsolidated(done, order)) else {
        return Consolidated(consolidated: false, snapshotId: nil, written: [], merged: 0, renamed: [])
      }
      let customDir = StyleSheets.stylesDirectory(project).appendingPathComponent("custom")
      let onDisk = filesOnDisk(customDir).map { "custom/\($0)" }
      var files = done
      for path in order where onDisk.contains(path) { files[path] = try StyleSheets.readText(StyleSheets.styleFile(project, path)) }
      let plan = StylesheetConsolidation.plan(order, files, onDisk)

      let snapshotId = try await snapshot(project, "styleMigration")
      for (from, to) in plan.rename { try FileManager.default.moveItem(at: StyleSheets.styleFile(project, from), to: StyleSheets.styleFile(project, to)) }
      for (path, content) in plan.write { try writeNow(path, content, project: project) }
      try StyleSheets.setImportOrderNow(plan.order, project: project)
      for path in plan.remove {
        let url = StyleSheets.styleFile(project, path)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
      }
      return Consolidated(consolidated: true, snapshotId: snapshotId, written: plan.write.map { String($0.path.dropFirst("custom/".count)) },
                          merged: StylesheetConsolidation.legacyCount(order, consolidated: false),
                          renamed: plan.rename.map { (String($0.from.dropFirst(7)), String($0.to.dropFirst(7))) })
    }
  }
}
