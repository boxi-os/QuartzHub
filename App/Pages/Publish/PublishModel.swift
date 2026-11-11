import AppKit
import QuartzHubCore
import SwiftUI

/// What Veröffentlichen reads and runs (QuartzControl's `Publish/index.tsx`): the project's
/// targets, the app's connections, the diff of the selected target and a deploy.
///
/// One model per project for the whole app, as Updates and Vorlagen: an upload or a document
/// export runs for minutes and belongs to the project, so the page opened again shows it going or
/// how it ended. The diff is the selected target's and is taken again by hand: it is a picture of
/// the build output, and for rsync it asks the server.
@MainActor @Observable
final class PublishModel {
  private static var models: [String: PublishModel] = [:]

  static func shared(_ project: ProjectContext) -> PublishModel {
    if let model = models[project.path] { return model }
    let model = PublishModel(project: project)
    models[project.path] = model
    return model
  }

  struct Run: Equatable {
    var targetId: String
    var processed = 0
    var total = 0
    var file: String?
  }

  let project: ProjectContext
  private var path: String { project.path }

  private(set) var connections: [Connection] = []
  private(set) var targets: [PublishTarget] = []
  private(set) var books: [Book] = []
  /// nil until the config was read: before that there is nothing to warn about.
  private(set) var baseUrl: String?
  /// nil until asked; only the rsync transfer needs it.
  private(set) var rsyncAvailable: Bool?

  /// `project-prefs.json`'s `outputDir`, the same field as on Vorschau & Build; written when settled.
  var outputDir = ""
  private var savedOutputDir = ""
  var outputDirError: String?

  /// The target the diff and the result below are about.
  private(set) var selectedId: String?
  private(set) var diff: [DeployDiffEntry]?
  /// Paths left out of this one run, by their bytes.
  private(set) var excluded: Set<[UInt8]> = []
  private(set) var diffing = false
  private(set) var diffError: String?
  private(set) var building = false
  private(set) var buildError: String?
  /// How the last "Jetzt bauen" ended, in Vorschau & Build's words.
  private(set) var buildLine: (success: Bool, text: String)?
  private(set) var forgetting = false
  private(set) var run: Run?
  /// Whether a deploy runs, apart from its progress: the file rows read this one, so a progress
  /// line does not redraw hundreds of them (measured: the page lagged a folder deploy by half a
  /// minute while every event redrew 474 rows).
  private(set) var running = false
  private(set) var runningTarget: String?
  private(set) var result: (targetId: String, value: DeployResult)?
  var failure: String?

  private init(project: ProjectContext) {
    self.project = project
  }

  var selected: PublishTarget? { targets.first { $0.id == selectedId } }

  func connection(of target: PublishTarget) -> Connection? {
    target.connectionId.flatMap { id in connections.first { $0.id == id } }
  }

  // MARK: Reading

  func appear() async {
    reloadConnections()
    reloadTargets()
    books = (try? Books(project: path).list().books) ?? []
    outputDir = ProjectPrefsStore.read(project: path).outputDir
    savedOutputDir = outputDir
    let environment = await AppServices.current()
    rsyncAvailable = ProcessRunner.resolve("rsync", path: environment.variables["PATH"]) != nil
    if let config = try? await ConfigFile.read(project: path) {
      baseUrl = config.configuration["baseUrl"]?.stringValue ?? ""
    }
  }

  func reloadConnections() {
    connections = AppDeploy.connections().list()
  }

  func reloadTargets() {
    targets = PublishTargets(project: path).list()
  }

  var baseUrlWarning: Bool {
    guard let baseUrl else { return false }
    return baseUrl.isEmpty || baseUrl == "localhost"
  }

  /// Everything below the list describes one target; left standing across a switch, the previous
  /// target's diff and result read as statements about the new one. A run keeps going and keeps
  /// its own target.
  func select(_ id: String?) {
    guard id != selectedId else { return }
    selectedId = id
    diff = nil
    excluded = []
    diffError = nil
    buildError = nil
    buildLine = nil
    if !running { result = nil }
  }

  /// After the target sheet saved: an edit keeps its id, so a diff taken before it would keep
  /// describing the old path or exclusions.
  func saved(_ id: String) {
    reloadTargets()
    selectedId = nil
    select(id)
  }

  // MARK: The output folder

  func commitOutputDir(_ next: String) {
    outputDir = next
    if let problem = ProjectPrefs.outputDirProblem(next) {
      outputDirError = problem
      return
    }
    outputDirError = nil
    guard next != savedOutputDir else { return }
    do {
      try ProjectPrefsStore.update(project: path) { $0.outputDir = next }
      savedOutputDir = next
    } catch {
      outputDirError = String(describing: error)
    }
  }

  private var outputDirArgument: String? { savedOutputDir.isEmpty ? nil : savedOutputDir }

  private func deploy(progress: @escaping @Sendable (String, Int, Int, String?) -> Void = { _, _, _, _ in }) async -> Deploy {
    AppDeploy.make(project: path, environment: await AppServices.current(), progress: progress)
  }

  // MARK: The diff

  /// A deploy that worked refreshes the diff itself, and keeps its result: clearing it there wiped
  /// the very lines that say what was published.
  func refreshDiff(keepResult: Bool = false) async {
    guard let target = selected else { return }
    if !keepResult, !running { result = nil }
    diffing = true
    defer { diffing = false }
    do {
      let entries = try await deploy().preview(target.id, outputDir: outputDirArgument)
      guard selectedId == target.id else { return }
      diff = entries
      excluded = []
      diffError = nil
    } catch {
      if selectedId == target.id { diffError = error.message }
    }
  }

  func buildNow() async {
    building = true
    buildError = nil
    buildLine = nil
    defer { building = false }
    switch await BuildAction.run(projectId: project.id, project: path, outputDir: outputDirArgument) {
    case .finished(let result):
      let seconds = Double(result.duration.components.seconds) + Double(result.duration.components.attoseconds) / 1e18
      buildLine = (result.success, L10n.t("buildServer.resultLine", [
        "status": result.success ? L10n.t("buildServer.success") : L10n.t("buildServer.failed"),
        "seconds": seconds.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: L10n.language))),
      ]))
      Announce.post(buildLine!.text)
    case .refused(let message):
      buildError = message
    case .cancelled:
      return
    }
    await refreshDiff()
  }

  /// "Alles neu hochladen": the record of what was last sent is thrown away, and the diff offers the
  /// whole build again with the usual checkboxes. For what QuartzHub cannot see from here.
  func forgetManifest() async {
    guard let target = selected else { return }
    forgetting = true
    defer { forgetting = false }
    DeployManifests(project: path).forget(target.id)
    await refreshDiff(keepResult: true)
  }

  func isExcluded(_ path: String) -> Bool { excluded.contains(Array(path.utf8)) }

  func toggleExcluded(_ path: String) {
    let key = Array(path.utf8)
    if excluded.contains(key) { excluded.remove(key) } else { excluded.insert(key) }
  }

  /// A file list exists for every target but a webhook, which only asks a provider to build.
  var hasFileDiff: Bool { selected.map { $0.destination["type"] != .string("webhook") } ?? false }

  /// A branch is replaced with one commit, so leaving a file out would delete it from the live
  /// site; a document's files are its formats. Both show the list read-only.
  var canExclude: Bool {
    guard let type = selected?.destination["type"]?.stringValue else { return false }
    return type != "git-branch" && type != "document"
  }

  var canDeploy: Bool { selected != nil && !running && (!hasFileDiff || diff != nil) }

  // MARK: Publishing

  /// Not reversible from inside QuartzHub: it force-pushes a branch, or uploads to and deletes on
  /// a server. So it asks, in the target's words; a document writes files named after its book
  /// into a chosen folder, deletes nothing and can be stopped, so it does not.
  func publish(window: NSWindow?) async {
    guard let target = selected, !running else { return }
    let d = target.destination
    switch d["type"]?.stringValue {
    case "git-branch":
      let (question, detail) = Confirm.split(L10n.t("publish.confirmDeployBranch", ["branch": d["branch"]?.stringValue ?? ""]))
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("publish.confirmDeployAction"), destructive: true, window: window) else { return }
    case "document":
      break
    case "webhook":
      let (question, detail) = Confirm.split(L10n.t("publish.confirmDeployWebhook", ["target": target.name]))
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("publish.confirmDeployAction"), window: window) else { return }
    default:
      let entries = (diff ?? []).filter { !isExcluded($0.path) }
      // Removed files are deleted only where the target says so, by the rule the run itself reads
      // (`DeployContext.deleteRemoved`). With deleting off, the question said "1 Datei(en) werden
      // auf dem Server gelöscht" in red, and the run then deleted nothing (measured 2026-11-10).
      let removed = entries.filter { $0.status == .removed }.count
      let deletions = d["deleteRemoved"] == .bool(true) ? removed : 0
      let (question, detail) = Confirm.split(L10n.t("publish.confirmDeployConnection", [
        "target": target.name, "uploads": String(entries.count - removed), "deletions": String(deletions),
      ]))
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("publish.confirmDeployAction"), destructive: deletions > 0,
                              window: window) else { return }
    }
    await start(target)
  }

  private func start(_ target: PublishTarget) async {
    run = Run(targetId: target.id)
    running = true
    runningTarget = target.id
    result = nil
    let excludedPaths = (diff ?? []).map(\.path).filter(isExcluded)
    // In the order the adapters sent them, through one stream.
    let (events, feed) = AsyncStream.makeStream(of: Run.self)
    // At most ten a second; the last one always.
    let listener = Task { @MainActor [weak self] in
      var shown = ContinuousClock.now - .seconds(1)
      var pending: Run?
      for await event in events {
        pending = event
        guard ContinuousClock.now - shown >= .milliseconds(100) || event.processed == event.total else { continue }
        if self?.run != nil { self?.run = event }
        shown = .now
        pending = nil
      }
      if let pending, self?.run != nil { self?.run = pending }
    }
    let id = target.id
    let deploy = await deploy { targetId, processed, total, file in
      if targetId == id { feed.yield(Run(targetId: targetId, processed: processed, total: total, file: file)) }
    }
    let outcome = await deploy.run(target.id, outputDir: outputDirArgument, excluding: excludedPaths)
    feed.finish()
    await listener.value
    // The progress line is the run's, not the result's.
    run = nil
    running = false
    runningTarget = nil
    result = (target.id, outcome)
    Announce.post(resultTitle(outcome, document: target.destination["type"] == .string("document")))
    // A deploy is where a host key gets pinned: the connection shown is stale the moment it ends.
    reloadConnections()
    if outcome.success, selectedId == target.id, hasFileDiff { await refreshDiff(keepResult: true) }
  }

  func cancelExport() {
    guard let run else { return }
    _ = ExportBook.cancel(targetId: run.targetId)
  }

  func resultTitle(_ result: DeployResult, document: Bool) -> String {
    if !result.success { return L10n.t("publish.deployFailed") }
    // Files the target would not delete are still live: not the plain "erfolgreich".
    if !result.kept.isEmpty { return L10n.t("publish.deployPartial", ["count": String(result.kept.count)], count: result.kept.count) }
    return document ? L10n.t("publish.exportSuccess") : L10n.t("publish.deploySuccess")
  }

  // MARK: Targets and connections

  func delete(_ target: PublishTarget, window: NSWindow?) async -> Bool {
    guard await Confirm.ask(L10n.t("publish.confirmDeleteTarget"), confirm: L10n.t("publish.confirmDeleteTargetAction"), destructive: true,
                            window: window) else { return false }
    do {
      try PublishTargets(project: path).delete(target.id)
      failure = nil
    } catch {
      failure = error.message
    }
    reloadTargets()
    if selectedId == target.id { select(nil) }
    return true
  }

  /// A separate, confirmed action rather than an answer in the mismatch dialog.
  func forgetHostKey(_ connection: Connection, window: NSWindow?) async {
    let (question, detail) = Confirm.split(L10n.t("publish.confirmForgetHostKey", ["host": connection.host]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("publish.confirmForgetHostKeyAction"), destructive: true,
                            window: window) else { return }
    do {
      try AppDeploy.connections().forgetHostKey(connection.id)
      failure = nil
    } catch {
      failure = error.message
    }
    AppDeploy.ConnectionsVersion.shared.bump()
    reloadConnections()
  }

  /// The settings window on its „Zugänge“ tab.
  static func openConnectionSettings(_ open: OpenSettingsAction) {
    SettingsTab.State.shared.selected = SettingsTab.connections.rawValue
    open()
  }
}
