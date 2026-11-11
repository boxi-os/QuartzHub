import AppKit
import QuartzHubCore
import SwiftUI

/// What the Updates page reads and runs (QuartzControl's `Updates.tsx`).
///
/// One model per project for the whole app, not one per page: a core update runs for minutes
/// (merge, `npm install`, warm-up build), and QuartzControl's page lost its output and its busy
/// state the moment it was left. Here the run belongs to the model, so the page opened again shows
/// it still going, or how it ended. The checks are read again on every opening.
@MainActor @Observable
final class UpdatesModel {
  private static var models: [String: UpdatesModel] = [:]

  static func shared(_ project: ProjectContext) -> UpdatesModel {
    if let model = models[project.path] { return model }
    let model = UpdatesModel(project: project)
    models[project.path] = model
    return model
  }

  /// What a run, an abort or a plugin update answered.
  struct Outcome: Equatable {
    /// QuartzHub's sentence above git's and npm's text; nil when the text speaks for itself.
    var title: String?
    var success: Bool
    var output: String
    var snapshotId: String?
    var conflicts: [String] = []
  }

  enum PluginRun: Equatable { case all, one(String) }

  let project: ProjectContext
  var core: CoreUpdate.Status?
  var plugins: [PluginUpdates.Status]?
  var git: GitStatus?
  /// Checks in flight; only the newest one's answer is kept.
  private var checks = 0
  private var round = 0
  var checking: Bool { checks > 0 }

  /// package.json's version at HEAD and at the newest upstream commit.
  var versions: CoreUpdate.Versions?
  /// While behind: the release notes between the two, from upstream's CHANGELOG.md.
  var notesAhead: [ReleaseNotes.Section] = []
  /// After a run that changed the version: what came with it (`npx quartz upgrade` shows the same).
  var notesDone: [ReleaseNotes.Section] = []
  /// After a run on a Quartz with `plugin doctor` (5.1): its check, read only.
  var doctorAfter: String?
  /// The config's entries beside it, for which duplicates are intended.
  var doctorPlugins: [PluginEntry] = []
  var pendingMigrations: [String] = []
  var markdownOrderProblem = false

  /// `quartz info` (Quartz 5.1): the text for a bug report, read on request.
  var info: String?
  var infoRunning = false
  /// Read with the checks: `quartz info` came with 5.1.
  var hasInfo = false

  var coreBusy = false
  var coreResult: Outcome?
  var pluginRun: PluginRun?
  var pluginResult: Outcome?

  private init(project: ProjectContext) {
    self.project = project
  }

  private var path: String { project.path }

  /// The app's environment. For the UI test and for looking at the page without the network
  /// (DEBUG only, `-QHNoUpdateCheck YES`), git may only reach `file://` here: the checks answer
  /// "Nicht prüfbar" at once, and a run stops at its fetch.
  private func environment() async -> ToolEnvironment {
    var environment = await AppServices.shared.environment.value
    #if DEBUG
    if LaunchArgument.flag("QHNoUpdateCheck") { environment.base["GIT_ALLOW_PROTOCOL"] = "file" }
    #endif
    return environment
  }

  private func updater(_ environment: ToolEnvironment) -> CoreUpdate {
    CoreUpdate(environment: environment, snapshot: SnapshotStore.live(environment: environment).take)
  }

  // MARK: Reading

  /// Core, plugins and git at once. The core may fetch here to name the installed upstream commit
  /// (`resolveInstalled`); the Übersicht, which reads the same status, may not.
  func reload() async {
    round += 1
    let mine = round
    checks += 1
    defer { checks -= 1 }
    let environment = await environment()
    let updater = updater(environment)
    let path = path
    async let core = updater.status(project: path, resolveInstalled: true)
    async let plugins = PluginUpdates.status(project: path, core: updater)
    async let git = GitStatus.read(project: path, environment: environment)
    let answers = await (core, plugins, git)
    guard mine == round else { return }
    (self.core, self.plugins, self.git) = answers
    let latest = answers.0.latestCommit
    let versions = await updater.versions(project: path, latestCommit: latest)
    var ahead: [ReleaseNotes.Section] = []
    if answers.0.state == .behind, let installed = versions.installed, let newest = versions.latest, installed != newest {
      ahead = await updater.releaseNotes(project: path, revision: latest, from: installed, to: newest)
    }
    let features = await Task.detached { QuartzFeatures.read(project: path) }.value
    guard mine == round else { return }
    (self.versions, notesAhead, hasInfo) = (versions, ahead, features.builtins)
  }

  /// Quartz's check after the update, and what QuartzHub offers from it: the move of the built-in
  /// plugins' entries and the Markdown order (both also on the Plugins page).
  func checkAfterUpdate() async {
    let path = path
    guard QuartzFeatures.read(project: path).builtins else {
      (doctorAfter, pendingMigrations, markdownOrderProblem) = (nil, [], false)
      return
    }
    let environment = await environment()
    let doctor = await PluginCommands.shared.doctor(project: path, fix: false, environment: environment)
    doctorAfter = doctor.output
    doctorPlugins = []
    if let config = try? await ConfigFile.read(project: path, runtime: environment.runtime) {
      doctorPlugins = config.plugins
      pendingMigrations = BuiltinProcessing.pendingMigrations(config.plugins).map { config.plugins[$0].name }
      markdownOrderProblem = BuiltinProcessing.markdownOrderProblem(config.plugins) != nil
    }
  }

  func readInfo() async {
    infoRunning = true
    defer { infoRunning = false }
    let result = await PluginCommands.shared.info(project: path, environment: await environment())
    info = result.output
  }

  // MARK: The core

  /// Every action resets its busy flag on every way out: these are the longest-running actions in
  /// the app, and QuartzControl once left the button disabled after a rejected call.
  func runCore(window: NSWindow?) async {
    let (question, detail) = Confirm.split(L10n.t("updates.core.confirm"))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("updates.core.runUpdate"), window: window) else { return }
    coreBusy = true
    coreResult = nil
    (notesDone, doctorAfter, pendingMigrations, markdownOrderProblem) = ([], nil, [], false)
    let updater = updater(await environment())
    let fromVersion = await updater.versions(project: path, latestCommit: "").installed
    do {
      let result = try await updater.run(project: path)
      if result.success, let from = fromVersion, let to = await updater.versions(project: path, latestCommit: "").installed, from != to {
        notesDone = await updater.releaseNotes(project: path, revision: "HEAD", from: from, to: to)
      }
      if result.success { await checkAfterUpdate() }
      coreResult = Outcome(title: result.success ? L10n.t("updates.core.done") : L10n.t("updates.core.failed"), success: result.success,
                           output: result.output, snapshotId: result.snapshotId, conflicts: result.conflicts ?? [])
    } catch {
      // The core's errors carry their sentence as `description`; `localizedDescription` gave
      // "Der Vorgang konnte nicht abgeschlossen werden. (…SnapshotStore.Failure-Fehler 1.)" (measured).
      coreResult = Outcome(title: L10n.t("updates.core.failed"), success: false, output: String(describing: error))
    }
    coreBusy = false
    if let title = coreResult?.title { Announce.post(title) }
    await reload()
  }

  /// The abort answers with a sentence, not a throw (QuartzControl's `abortMerge`). Only a plain
  /// success stays quiet, and that is also the one that may clear an old box. What is said is
  /// QuartzHub's sentences, not git's text.
  func abortMerge() async {
    coreBusy = true
    let updater = updater(await environment())
    do {
      let result = try await updater.abort(project: path)
      let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
      coreResult = !result.success || !output.isEmpty ? Outcome(success: result.success, output: result.output) : nil
      let said = result.sentences.isEmpty
        ? output.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        : result.sentences.joined(separator: " ")
      if !said.isEmpty { Announce.post(said) }
    } catch {
      coreResult = Outcome(success: false, output: String(describing: error))
    }
    coreBusy = false
    await reload()
  }

  // MARK: Plugins

  /// "Nicht prüfbar" counts as something to do: a check that never reached the remote says nothing
  /// about whether the update works.
  var actionablePlugins: [PluginUpdates.Status] {
    (plugins ?? []).filter { $0.state == .behind || $0.state == .unknown }
  }

  func updatePlugin(_ name: String?) async {
    pluginRun = name.map { .one($0) } ?? .all
    pluginResult = nil
    let environment = await environment()
    let result = await PluginUpdates.update(project: path, name: name, environment: environment,
                                            snapshot: SnapshotStore.live(environment: environment).take)
    pluginResult = Outcome(success: result.success, output: String(result.output.suffix(2000)))
    pluginRun = nil
    Announce.post(L10n.t("updates.plugins.finished"))
    plugins = await PluginUpdates.status(project: path, core: updater(environment))
  }
}
