import Foundation
import QuartzHubCore

/// `qh-check export-document <build> <ordner> --config <quartz.config.yaml> [--formats pdf,epub,html]
/// [--cancel-after <s>]`:
/// the export the way "Publish now" runs it, as QuartzControl's `check:export` does through the
/// app: a throwaway project (the config copied, the build cloned into `public/`), the book editor's
/// page list (`ExportBook.sitePages`), a book over the whole site with contents, register and
/// backlinks, a target "Dokument" into <ordner>, `Deploy.run`. The files are then QuartzControl's
/// `npm run check:export -- --files <ordner> --book <id>` to check. Nothing is written into a
/// real project; the throwaway one is removed at the end. `--cancel-after` stops the run as the
/// page's cancel button would (`ExportBook.cancel`). Without network: what the rule lets in
/// from outside is refused too (use a copy from `scripts/cdn-build.mjs` for Mermaid and KaTeX).
@MainActor
func runExportDocumentCheck(build: String, out: String, config: String, formats: [String], cancelAfter: Double? = nil) async -> Int32 {
  let work = NSTemporaryDirectory() + "quartzhub-export-document-\(UUID().uuidString.lowercased())"
  let project = "\(work)/Gärten-Ü"
  defer { try? FileManager.default.removeItem(atPath: work) }
  do {
    try Posix.mkdirs(project)
    for (from, to) in [(config, "\(project)/quartz.config.yaml"), (build, "\(project)/public")] {
      let clone = Process()
      clone.executableURL = URL(fileURLWithPath: "/bin/cp") // path boundary
      clone.arguments = ["-cR", from, to]
      try clone.run()
      clone.waitUntilExit()
      guard clone.terminationStatus == 0 else { print("Nicht kopierbar: \(from)"); return 2 }
    }
  } catch {
    print("Wegwerf-Projekt nicht anlegbar: \(error)")
    return 2
  }
  do {
    let started = Date()
    let site = try await ExportBook.sitePages(project: project, root: "", language: "")
    print("Seitenliste: \(site.pages.count) Seiten, Reihenfolge aus \(site.source), Sprache \(site.defaultLanguage.isEmpty ? "–" : site.defaultLanguage)")
    var input = BookFile.empty(title: "check:export")
    input["author"] = .string("QuartzHub")
    input["language"] = .string(site.defaultLanguage)
    input["tagIndex"] = .bool(true)
    input["backlinks"] = .bool(true)
    let book = try Books(project: project).save(input)
    let target = try PublishTargets(project: project).save(SavePublishTargetInput(name: "check:export", destination: JSONObject([
      ("type", .string("document")), ("path", .string(out)), ("bookId", .string(book.id)), ("formats", .array(formats.map(JSONValue.string)))
    ])))
    let deploy = Deploy(project: project, connections: Connections(profile: ProfileDirectory("\(work)/profil"), secrets: MemorySecrets()),
                        adapters: ["document": DocumentAdapter(outside: false)])
    let preview = try await deploy.preview(target.id)
    print("Vorschau: \(preview.map { "\($0.path) (\($0.status.rawValue))" }.joined(separator: ", "))")
    if let cancelAfter {
      let id = target.id
      _ = Task { @MainActor in
        try await Task.sleep(for: .seconds(cancelAfter))
        print("Abbruch nach \(cancelAfter) s: \(ExportBook.cancel(targetId: id))")
      }
    }
    let result = await deploy.run(target.id)
    print(result.output)
    print("\(result.success ? "Fertig" : "Gescheitert") in \(String(format: "%.1f s", Date().timeIntervalSince(started))); Buch \(book.id)")
    return result.success ? 0 : 1
  } catch {
    print("Lauf abgebrochen: \(error)")
    return 3
  }
}
