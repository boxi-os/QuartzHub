import Foundation

/// The document target (`deploy/document.ts`): a book of the site exported as PDF, ePub and/or
/// offline HTML into a folder (`ExportBook` does the export, this writes the files). It fits the
/// page's model of a target - preview, then run - with the files that will be written as the diff:
/// `added` for a new one, `changed` for one it replaces. There is no manifest and nothing is ever
/// deleted; a file of the same name is replaced under a scratch name and a rename, so whatever
/// watches the folder (a cloud client, a web server) never sees half a PDF.
public struct DocumentAdapter: DeployAdapter {
  let runtime: RuntimeLocation
  let outside: Bool
  let random: @Sendable () -> String

  /// `outside: false` for a measurement without network (`ExportBook.Request.outside`).
  public init(runtime: RuntimeLocation = .current, outside: Bool = true,
              random: @escaping @Sendable () -> String = { String(format: "%08x", UInt32.random(in: .min ... .max)) }) {
    self.runtime = runtime
    self.outside = outside
    self.random = random
  }

  static let formats = ["pdf", "epub", "html"]

  /// The destination, with the folder target's two refusals: the folder must be neither in the
  /// build (the next build would empty it) nor the project itself.
  static func destination(_ context: DeployContext) throws(PublishFailure) -> (path: String, bookId: String, formats: [String]) {
    let d = context.destination
    guard d["type"] == .string("document") else { throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "Dokument"])) }
    let path = JS.string(d["path"])
    if FolderAdapter.isInside(context.buildDir, path) || FolderAdapter.isInside(path, context.buildDir) {
      throw PublishFailure(L10n.t("main.folderOverlapsBuild", ["dest": path, "build": context.buildDir]))
    }
    if Array(FramePaths.resolve(path).utf8) == Array(FramePaths.resolve(context.project).utf8) { throw PublishFailure(L10n.t("main.folderIsProject")) }
    return (path, JS.string(d["bookId"]), (d["formats"]?.arrayValue ?? []).compactMap(\.stringValue))
  }

  static func exists(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0
  }

  public func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] {
    let d = try Self.destination(context)
    return Self.formats.filter(d.formats.contains).map { format in
      let name = "\(d.bookId).\(format)"
      return DeployDiffEntry(path: name, status: Self.exists(NodePath.join(d.path, name)) ? .changed : .added)
    }
  }

  public func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
    let d = try Self.destination(context)
    guard let book = try Books(project: context.project).read(d.bookId) else {
      return DeployResult(success: false, output: L10n.t("main.exportBookMissing", ["id": d.bookId]))
    }
    // The folder itself is created, the folders above it are not: on a disk or share that is not
    // connected the files would land in the bare mount point. Asked before the export, which can
    // take minutes.
    let parent = NodePath.dirname(FramePaths.resolve(d.path))
    if !Self.exists(d.path) && !Self.exists(parent) {
      return DeployResult(success: false, output: L10n.t("main.exportFolderParentMissing", ["path": d.path, "parent": parent]))
    }
    let report = context.progress
    let outcome = try await ExportBook.run(.init(targetId: context.target.id, project: context.project, buildDir: context.buildDir, book: book,
                                                 formats: d.formats, runtime: runtime, outside: outside)) { done, total, label in report(done, total, label) }
    if mkdir(d.path, 0o777) != 0 && errno != EEXIST { throw Posix.error("mkdir", d.path) }
    var info = stat()
    guard stat(d.path, &info) == 0 else { throw Posix.error("stat", d.path) }
    if info.st_mode & S_IFMT != S_IFDIR { throw PublishFailure(L10n.t("main.exportFolderNotFolder", ["path": d.path])) }
    var written: [String] = []
    for file in outcome.files {
      let target = NodePath.join(d.path, file.name)
      let scratch = "\(target).qh-\(random())"
      do {
        try Posix.write(scratch, file.bytes)
        if rename(scratch, target) != 0 { throw Posix.error("rename", scratch) }
      } catch {
        unlink(scratch)
        throw error
      }
      written.append("→ \(target)")
    }
    return DeployResult(success: true, output: (outcome.report + [""] + written).joined(separator: "\n"))
  }
}
