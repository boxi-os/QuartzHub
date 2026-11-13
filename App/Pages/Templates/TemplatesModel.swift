import AppKit
import QuartzHubCore
import SwiftUI
import UniformTypeIdentifiers

/// What the Vorlagen page reads and runs (QuartzControl's `Templates.tsx`): writing this project's
/// look into a `.qtpl`, and applying one to it.
///
/// One model per project for the whole app, not one per page, as QuartzControl kept the form in
/// `useStickyState` (the renderer's lifetime, per project). An import runs for minutes where it
/// installs packages; it belongs to the model, so the page opened again shows it still going, or
/// how it ended, where QuartzControl's page lost both.
@MainActor @Observable
final class TemplatesModel {
  private static var models: [String: TemplatesModel] = [:]

  static func shared(_ project: ProjectContext) -> TemplatesModel {
    if let model = models[project.path] { return model }
    let model = TemplatesModel(project: project)
    models[project.path] = model
    return model
  }

  struct Message: Equatable {
    var ok: Bool
    var text: String
  }

  struct Progress: Equatable {
    var partId: String?
    var message: String
    var done: Int
    var total: Int
  }

  /// The parts the built-in package brings for the look of a site, as opposed to its workings
  /// (plugins, layout, translations, presets) and its sample pages. QuartzControl ticked all of it
  /// at first, and one click replaced the user's navigation and switched plugins (its forty-fifth
  /// review); the rest is one tick away.
  static let designParts = ["appearance", "cssVariables", "theme", "styles", "fonts", "static", "frames"]

  /// Reading order for the user, which is not the order the parts are applied in: what the site
  /// looks like first, what it is built from after; the notes first of all.
  static let displayOrder = ["content", "appearance", "theme", "cssVariables", "styles", "fonts", "static", "layout", "frames", "plugins",
                             "translations", "presets"]

  /// The parts "Projekt gewinnt" leaves out whole (TemplatePackage's applyAppearance/applyLayout).
  static let skippedWhenProjectWins: Set<String> = ["appearance", "layout"]

  /// What the import will apply: the ticked parts, less those the strategy skips.
  var appliedParts: [String] {
    strategy == .projectWins ? importSelected.filter { !Self.skippedWhenProjectWins.contains($0) } : importSelected
  }

  static func sortedForDisplay<T>(_ items: [T], id: (T) -> String) -> [T] {
    items.sorted { (displayOrder.firstIndex(of: id($0)) ?? displayOrder.count) < (displayOrder.firstIndex(of: id($1)) ?? displayOrder.count) }
  }

  let project: ProjectContext
  private var path: String { project.path }

  // MARK: Export

  var name: String
  var description = ""
  /// nil until the project was read the first time: then everything it has is ticked.
  var available: [TemplatePackage.Summary]?
  var exportSelected: [String]?
  /// Parts the project has that a template cannot take, with the reason (too large).
  var refused: [String: String] = [:]
  /// Every part seen so far: a part that appears later is ticked like the first ones were.
  private var seenParts: Set<String> = []
  var scope: TemplatePackage.TranslationScope = .changed
  var exporting = false
  var exportResult: Message?

  // MARK: Import

  var packagePath: String?
  /// Where the package came from when it is the built-in one: its path is the profile's cache or
  /// the app's resources, which says nothing to anyone.
  var builtinSource: BuiltinTemplate.Source?
  /// The built-in package is the app's own although GitHub answered: its copy was not newer.
  var builtinDownloadNotNewer = false
  var plan: TemplatePackage.Plan?
  var unreadable = false
  var importSelected: [String] = []
  var strategy: TemplatePackage.Strategy = .packageWins
  /// A real dry run reads the package and the project, long enough that the page says so.
  var planning = false
  var progress: Progress?
  var warnings: [String]?
  var failure: String?
  var running: Bool { progress != nil }

  private init(project: ProjectContext) {
    self.project = project
    name = project.name
  }

  private func templates() async -> TemplatePackage {
    await AppServices.shared.templates()
  }

  static func text(_ error: Error) -> String {
    (error as? TemplateFailure)?.message ?? (error as? ZipArchive.Failure)?.message ?? (error as? SnapshotStore.Failure)?.message
      ?? String(describing: error)
  }

  // MARK: Reading

  /// The page opened: the project is read again (another page may have changed it), and a package
  /// that is loaded is planned again against it.
  func appear() async {
    await inspect()
    if packagePath != nil, !running, !planning { await replan() }
  }

  func inspect() async {
    let inspection = await templates().inspection(project: path)
    let parts = inspection.parts
    available = parts
    refused = inspection.refused
    // Everything the project has is ticked: a template is normally "all of it". Translations are
    // the exception: the part is offered even when no change was found (so "Alle Texte" can be
    // reached), and ticking it there would put an empty part in every package.
    // Again on every read, not once: a part the project gained later stayed unticked, and one it
    // lost stayed ticked, counted ("12 von 11") and exported (review 2026-11-13, nebenbei).
    let ids = parts.map(\.id)
    let fresh = parts.filter { !seenParts.contains($0.id) && ($0.id != "translations" || ($0.stats["entries"]?.numberValue ?? 0) > 0) }.map(\.id)
    exportSelected = (exportSelected ?? []).filter { ids.contains($0) } + fresh
    seenParts.formUnion(ids)
  }

  func toggleExport(_ id: String) {
    var list = exportSelected ?? []
    if let index = list.firstIndex(of: id) { list.remove(at: index) } else { list.append(id) }
    exportSelected = list
  }

  // MARK: Export

  var canExport: Bool { !(exportSelected ?? []).isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !exporting }

  /// The target is chosen here, in a save panel, as QuartzControl chose it in the main process.
  func export(window: NSWindow?) async {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = TemplatePackage.slugifyFileName(name, fallback: L10n.t("templates.fileNameFallback"))
    if let type = UTType(filenameExtension: "qtpl") { panel.allowedContentTypes = [type] }
    let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
    // A closed panel needs no sentence; "Abgebrochen." stood there in the green of a success.
    guard response == .OK, let url = panel.url else { return }
    exporting = true
    exportResult = nil
    defer { exporting = false }
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      let written = try await templates().export(project: path, to: Posix.path(url), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  description: trimmed.isEmpty ? nil : trimmed, parts: exportSelected ?? [], scope: scope)
      let text = L10n.t("templates.exportSuccess", ["path": written.file, "size": Formats.bytes(written.bytes)])
      exportResult = Message(ok: true, text: text)
      Announce.post(text)
    } catch {
      exportResult = Message(ok: false, text: Self.text(error))
    }
  }

  // MARK: Import

  /// A `.qtpl`, or a folder: packages written before the single-file format are folders, and they
  /// stay importable.
  func pick(window: NSWindow?) async {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    if let type = UTType(filenameExtension: "qtpl") { panel.allowedContentTypes = [type, .folder] }
    let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
    guard response == .OK, let url = panel.url else { return }
    await load(Posix.path(url), source: nil)
  }

  /// The package every new project is offered: the published one (downloaded or cached).
  func pickBuiltin() async {
    reset(nil, source: nil)
    planning = true
    defer { planning = false }
    if let found = await BuiltinTemplate.app().find() {
      await load(found.path, source: found.source)
      builtinDownloadNotNewer = found.downloadNotNewer
    } else {
      failure = L10n.t("templates.builtinMissing")
    }
  }

  private func reset(_ path: String?, source: BuiltinTemplate.Source?) {
    packagePath = path
    builtinSource = source
    builtinDownloadNotNewer = false
    warnings = nil
    failure = nil
    progress = nil
    plan = nil
    unreadable = false
  }

  private func load(_ path: String, source: BuiltinTemplate.Source?) async {
    reset(path, source: source)
    planning = true
    defer { planning = false }
    do {
      let result = try await templates().plan(project: self.path, package: path)
      plan = result
      unreadable = result == nil
      let parts = result?.parts.map(\.id) ?? []
      importSelected = source != nil ? parts.filter { Self.designParts.contains($0) } : parts
    } catch {
      failure = Self.text(error)
    }
  }

  /// The same package planned against the project as it is now; the ticks stay where they were.
  private func replan() async {
    guard let packagePath else { return }
    planning = true
    defer { planning = false }
    guard let result = try? await templates().plan(project: path, package: packagePath) else { return }
    plan = result
    let ids = result.parts.map(\.id)
    importSelected = importSelected.filter { ids.contains($0) }
  }

  func toggleImport(_ id: String) {
    if let index = importSelected.firstIndex(of: id) { importSelected.remove(at: index) } else { importSelected.append(id) }
  }

  /// The packages the selected parts would install, and the plugins `quartz plugin add` would
  /// clone and build (the plan's `cliInstall:` notes).
  var missingPackages: [String] {
    var seen: [String] = []
    for part in plan?.parts ?? [] where appliedParts.contains(part.id) {
      for name in part.missingPackages.map(\.name) where !seen.contains(name) { seen.append(name) }
    }
    return seen
  }

  var clonedPlugins: [String] {
    var seen: [String] = []
    for part in plan?.parts ?? [] where appliedParts.contains(part.id) {
      for note in part.notes where note.hasPrefix("cliInstall:") {
        let name = String(note.dropFirst("cliInstall:".count))
        if !seen.contains(name) { seen.append(name) }
      }
    }
    return seen
  }

  func runImport(window: NSWindow?) async {
    guard let packagePath, !importSelected.isEmpty, !running else { return }
    let text = strategy == .packageWins ? L10n.t("templates.confirmOverwrite", count: importSelected.count)
      : L10n.t("templates.confirmMerge", count: importSelected.count)
    // The catalog's sentence is the question and what it does, in one: the question is the alert's title.
    let question = text.firstIndex(of: "?").map { String(text[...$0]) } ?? text
    let detail = text.firstIndex(of: "?").map { String(text[text.index(after: $0)...]).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard await Confirm.ask(question, detail: detail?.isEmpty == false ? detail : nil, confirm: L10n.t("templates.confirmImportAction"),
                            destructive: strategy == .packageWins, window: window) else { return }
    warnings = nil
    failure = nil
    progress = Progress(partId: nil, message: "", done: 0, total: importSelected.count)
    // In the order the service sent them, through one stream.
    let (events, feed) = AsyncStream.makeStream(of: Progress.self)
    let listener = Task { @MainActor [weak self] in
      for await event in events { if self?.progress != nil { self?.progress = event } }
    }
    let selected = importSelected
    let strategy = strategy
    let project = path
    do {
      let result = try await templates().importPackage(project: project, package: packagePath, parts: selected, strategy: strategy) { id, message, done, total in
        feed.yield(Progress(partId: id, message: message, done: done, total: total))
      }
      warnings = result.warnings
    } catch {
      failure = Self.text(error)
    }
    feed.finish()
    await listener.value
    progress = nil
    let lines = warnings.map { $0.isEmpty ? [L10n.t("templates.importSuccessNoWarnings")] : ImportWarnings.lines($0) } ?? []
    Announce.post(failure ?? lines.first ?? "")
    // What the project has now: the export's counts and the plan's.
    await inspect()
    await replan()
  }
}

extension BuiltinTemplate {
  /// The finder for QuartzHub's profile, for the Templates page and the create wizard: the
  /// published package only. Without the network when looking at the app (DEBUG,
  /// `-QHNoUpdateCheck YES`): the repository's copy, since a profile without a fresh download
  /// would otherwise fetch the package from GitHub.
  static func app() -> BuiltinTemplate {
    guard AppDeploy.offline else { return BuiltinTemplate(profile: AppProfile.own) }
    return BuiltinTemplate(profile: AppProfile.own, bundled: BuiltinTemplate.developmentCopy,
                           fetch: { _, _, _ throws(FontService.FetchFailure) in throw .unreachable })
  }
}
