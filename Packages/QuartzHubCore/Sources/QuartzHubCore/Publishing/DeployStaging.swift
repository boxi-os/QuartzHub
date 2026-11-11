import Foundation

/// A website target that takes documents along (`deploy/staging.ts`): the build plus the files of
/// the document targets it names, under `downloads/`, as one folder every adapter treats as the
/// build. Not the build folder itself: that one has a writer, and the next build empties it.
///
/// `.quartz-gui/staging/<targetId>`, made fresh for every preview and run: the build's files as
/// hard links (a copy where the build is on another volume), the documents as copies. The
/// documents are the files their target last wrote; one older than the build is said, not
/// exported again.
public struct DeployStaging: Sendable {
  public static let downloads = "downloads"
  static let extensions = ["pdf": "pdf", "epub": "epub", "html": "html"]

  public let dir: String
  /// Sentences for the run's output: a document missing, one older than the build.
  public let notes: [String]

  public func remove() { try? FileManager.default.removeItem(atPath: dir) }

  /// A link in the build is taken as the manifest's walk takes it (Quartz writes none, a user
  /// may): one to a file is that file, one to a folder or to nothing fails as hashing it does.
  /// Before, the staging dropped links, so the same target saw two builds with and without
  /// documents (review 2026-11-11, nebenbei 9; as QuartzControl).
  static func mirror(_ from: String, _ to: String) throws {
    try Posix.mkdirs(to)
    guard let entries = Posix.entries(from) else { throw Posix.error("scandir", from) }
    for entry in entries {
      let source = "\(from)/\(entry.name)", target = "\(to)/\(entry.name)"
      switch entry.kind {
      case .directory: try mirror(source, target)
      case .file:
        if link(source, target) != 0 { try Posix.copyFile(source, target) }
      case .link:
        var info = stat()
        guard stat(source, &info) == 0 else { throw Posix.error("open", source) }
        if info.st_mode & S_IFMT == S_IFDIR { throw NodeFileError(code: EISDIR, syscall: "read", path: source) }
        // copyfile follows the link; link(2) might link the link itself.
        try Posix.copyFile(source, target)
      case .other: break
      }
    }
  }

  static func modified(_ path: String) -> Double? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return Double(info.st_mtimespec.tv_sec) * 1000 + Double(info.st_mtimespec.tv_nsec) / 1_000_000
  }

  public static func stage(project: String, target: PublishTarget, buildDir: String) throws(PublishFailure) -> DeployStaging? {
    let ids = target.withDocuments
    if ids.isEmpty { return nil }
    do {
      let dir = try QuartzGuiDirectory(project: project).create("staging", target.id)
      try? FileManager.default.removeItem(atPath: dir)
      try mirror(buildDir, dir)
      var notes: [String] = []
      let builtAt = modified("\(buildDir)/index.html") ?? 0
      let targets = PublishTargets(project: project)
      for id in ids {
        guard let document = targets.get(id), document.destinationType == .document else {
          notes.append(L10n.t("main.stagingDocumentTargetMissing"))
          continue
        }
        let d = document.destination
        for format in d["formats"]?.arrayValue ?? [] {
          let name = "\(JS.string(d["bookId"])).\(extensions[JS.string(format)] ?? "undefined")"
          let file = NodePath.join(JS.string(d["path"]), name)
          guard let info = try? NodeFileError.statFollowing(file), info.st_mode & S_IFMT == S_IFREG else {
            notes.append(L10n.t("main.stagingDocumentMissing", ["name": name, "target": document.name]))
            continue
          }
          let time = Double(info.st_mtimespec.tv_sec) * 1000 + Double(info.st_mtimespec.tv_nsec) / 1_000_000
          if time < builtAt { notes.append(L10n.t("main.stagingDocumentOlder", ["name": name, "target": document.name])) }
          let destination = "\(dir)/\(downloads)/\(name)"
          if Posix.exists(destination) { notes.append(L10n.t("main.stagingDocumentReplaces", ["path": "\(downloads)/\(name)"])) }
          try Posix.mkdirs("\(dir)/\(downloads)")
          try? Posix.unlink(destination)
          try Posix.copyFile(file, destination)
        }
      }
      return DeployStaging(dir: dir, notes: notes)
    } catch let failure as PublishFailure {
      throw failure
    } catch {
      throw PublishFailure(PublishFailure.message(of: error))
    }
  }
}
