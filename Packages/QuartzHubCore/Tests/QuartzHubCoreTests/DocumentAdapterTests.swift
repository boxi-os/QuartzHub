import Foundation
import Testing
@testable import QuartzHubCore

/// The document target up to the export: its preview and every refusal before it. What it writes
/// after the export is measured with `qh-check export-document` (the files land under a scratch
/// name and are renamed) and checked with QuartzControl's `check:export -- --files`.
@Suite struct DocumentAdapterTests {

  struct Setup {
    let work: String
    let project: String
    let build: String
    let deploy: Deploy
    let targets: PublishTargets
    let bookId: String
  }

  static func setup() throws -> Setup {
    let work = TestFolder.make("qh-document")
    let project = "\(work)/Gärten-Ü"
    let build = "\(project)/public"
    try Posix.mkdirs(build)
    try Posix.write("\(build)/index.html", Data("<html></html>".utf8))
    let book = try Books(project: project).save(BookFile.empty(title: "Handbuch"))
    let deploy = Deploy(project: project, connections: Connections(profile: ProfileDirectory("\(work)/profil"), secrets: MemorySecrets()),
                        adapters: ["document": DocumentAdapter()])
    return Setup(work: work, project: project, build: build, deploy: deploy, targets: PublishTargets(project: project), bookId: book.id)
  }

  static func target(_ setup: Setup, path: String, bookId: String? = nil, formats: [String]) throws -> String {
    try setup.targets.save(SavePublishTargetInput(name: "Dokument", destination: JSONObject([
      ("type", .string("document")), ("path", .string(path)), ("bookId", .string(bookId ?? setup.bookId)), ("formats", .array(formats.map(JSONValue.string)))
    ]))).id
  }

  @Test func previewNamesTheFiles() async throws {
    let s = try Self.setup()
    defer { try? FileManager.default.removeItem(atPath: s.work) }
    let out = "\(s.work)/Dokumente-Ü"
    try Posix.mkdirs(out)
    try Posix.write("\(out)/handbuch.pdf", Data("alt".utf8))
    // In the order pdf, epub, html, whatever order the target names them in.
    let id = try Self.target(s, path: out, formats: ["html", "pdf"])
    let diff = try await s.deploy.preview(id)
    #expect(diff == [DeployDiffEntry(path: "handbuch.pdf", status: .changed), DeployDiffEntry(path: "handbuch.html", status: .added)])
  }

  @Test func refusalsBeforeTheExport() async throws {
    let s = try Self.setup()
    defer { try? FileManager.default.removeItem(atPath: s.work) }
    // Into the build, the build into it, the project itself.
    for path in ["\(s.build)/docs", s.project + "/..", "\(s.project)/../Gärten-Ü"] {
      let id = try Self.target(s, path: path, formats: ["pdf"])
      let result = await s.deploy.run(id)
      #expect(!result.success)
      let overlap = L10n.t("main.folderOverlapsBuild", ["dest": path, "build": s.build])
      #expect(result.output == overlap || result.output == L10n.t("main.folderIsProject"), "\(path): \(result.output)")
    }
    // A book that is gone.
    let gone = try Self.target(s, path: "\(s.work)/out", bookId: "weg", formats: ["pdf"])
    #expect(await s.deploy.run(gone) == DeployResult(success: false, output: L10n.t("main.exportBookMissing", ["id": "weg"])))
    // The folder above the target is missing: a drive not connected.
    let detached = "\(s.work)/Volumes/Platte/Dokumente"
    let parent = try Self.target(s, path: detached, formats: ["epub"])
    #expect(await s.deploy.run(parent) == DeployResult(success: false, output: L10n.t("main.exportFolderParentMissing",
                                                                                      ["path": detached, "parent": "\(s.work)/Volumes/Platte"])))
    #expect(!Posix.exists("\(s.work)/Volumes"))
  }

  @Test func noBuildNoExport() async throws {
    let s = try Self.setup()
    defer { try? FileManager.default.removeItem(atPath: s.work) }
    try FileManager.default.removeItem(atPath: s.build)
    let id = try Self.target(s, path: "\(s.work)/out", formats: ["pdf"])
    #expect(await s.deploy.run(id) == DeployResult(success: false, output: L10n.t("main.deployNoBuild", ["dir": s.build])))
  }
}
