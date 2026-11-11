import QuartzHubCore
import SwiftUI

/// What the Übersicht reads (QuartzControl's `ProjectDashboard.tsx`). Every read is local, starts at
/// once and swallows its own failure, so one unreadable file cannot blank the page. The update
/// check is the page's only network read, started apart and awaited by nothing else: a slow remote
/// costs the Updates section its "Prüfe…" and nothing more.
@MainActor @Observable
final class OverviewModel {
  let project: ProjectContext

  var attention = ProjectAttention.Reads()
  var snapshots: [SnapshotStore.Snapshot]?
  var frameCount: Int?
  var stylesheetCount: Int?
  var targets: [PublishTarget]?
  /// nil while reading; a failure is the folder that could not be listed.
  var build: Result<BuildOutput.Info, BuildOutput.Unreadable>?
  var core: CoreUpdate.Status?
  var pluginUpdates: [PluginUpdates.Status]?
  var updatesPending = true

  enum Busy: Hashable { case build, snapshot, install }
  var busy: Set<Busy> = []
  /// "Build fertig." or why not, under the Build section until the next build.
  var buildMessage: String?
  /// What an action could not do; shown as an alert.
  var failure: String?

  init(project: ProjectContext) {
    self.project = project
  }

  private var path: String { project.path }

  /// For the UI test and for looking at the page without the network (DEBUG only): the update
  /// check is skipped and the section says "Nicht prüfbar".
  private var updateCheckOff: Bool {
    #if DEBUG
    LaunchArgument.flag("QHNoUpdateCheck")
    #else
    false
    #endif
  }

  func load() async {
    let environment = await AppServices.shared.environment.value
    let path = path
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await BuildMonitor.shared.refresh(self.project.id, from: AppServices.shared.builds) }
      group.addTask {
        let config = try? await ConfigFile.read(project: path, runtime: environment.runtime)
        await MainActor.run { self.attention.config = config }
      }
      group.addTask {
        let content = try? ContentFolder.status(project: path)
        await MainActor.run { self.attention.content = content }
      }
      group.addTask {
        let git = await GitStatus.read(project: path, environment: environment)
        await MainActor.run { self.attention.git = git }
      }
      group.addTask {
        let scss = await ScssCheck.check(project: path, runtime: environment.runtime)
        await MainActor.run { self.attention.scss = scss }
      }
      group.addTask { await self.loadSnapshots() }
      group.addTask { await self.loadBuild() }
      group.addTask { await self.loadDependencies() }
      group.addTask {
        let frames = LayoutFrames.listFrames(project: path).count
        let sheets = (try? StyleFiles.list(project: path))?.files.count
        let targets = PublishTargets(project: path).list()
        await MainActor.run {
          self.frameCount = frames
          self.stylesheetCount = sheets
          self.targets = targets
        }
      }
    }
  }

  func checkUpdates() async {
    updatesPending = true
    defer { updatesPending = false }
    guard !updateCheckOff else { return }
    let environment = await AppServices.shared.environment.value
    let snapshots = SnapshotStore.live(environment: environment)
    let updater = CoreUpdate(environment: environment, snapshot: snapshots.take)
    async let core = updater.status(project: path)
    async let plugins = PluginUpdates.status(project: path, core: updater)
    let (coreStatus, pluginStatus) = await (core, plugins)
    self.core = coreStatus
    attention.core = coreStatus
    pluginUpdates = pluginStatus
  }

  func loadSnapshots() async {
    let environment = await AppServices.shared.environment.value
    snapshots = await SnapshotStore.live(environment: environment).list(project: path)
  }

  func loadBuild() async {
    let path = path
    let info = await Task.detached { Result { () throws(BuildOutput.Unreadable) in try BuildOutput.info(project: path) } }.value
    build = info
  }

  func loadDependencies() async {
    let path = path
    let environment = await AppServices.shared.environment.value
    let packages = await Task.detached { ProjectDependencies.missingDependencies(project: path) }.value
    let frames = await ProjectDependencies.missingAuthoredFrames(project: path, runtime: environment.runtime)
    attention.missingPackages = packages.map { .done($0) } ?? .failed(nil)
    attention.missingFrames = frames
    // An install started before this page opened (here, or on Plugins ▸ Wartung): joined, so the
    // band says "werden installiert" until it ends; whoever started it reports how it went.
    if PluginCommands.shared.isInstallingFromLock(project: path), !busy.contains(.install) {
      Task { await installDependencies(join: true) }
    }
  }

  func reloadScss() async {
    let environment = await AppServices.shared.environment.value
    attention.scss = await ScssCheck.check(project: path, runtime: environment.runtime)
  }

  // MARK: Actions

  func startServer() {
    let project = project
    Task { _ = await AppServices.shared.builds.startServer(projectId: project.id, project: project.path) }
  }

  func stopServer() {
    let id = project.id
    Task { await AppServices.shared.builds.stopServer(id) }
  }

  func restartServer() {
    let project = project
    Task { _ = await AppServices.shared.builds.restartServer(projectId: project.id, project: project.path) }
  }

  func runBuild() async {
    busy.insert(.build)
    defer { busy.remove(.build) }
    buildMessage = nil
    switch await BuildAction.run(projectId: project.id, project: path) {
    case .finished(let result):
      buildMessage = result.success ? L10n.t("dashboard.build.done") : L10n.t("dashboard.build.failed")
      Announce.post(buildMessage!)
      await loadBuild()
    case .refused(let message):
      failure = message
    case .cancelled:
      break
    }
  }

  /// npm install, then the plugins from quartz.lock.json: what a fresh clone lacks.
  func installDependencies(join: Bool = false) async {
    busy.insert(.install)
    attention.installing = true
    defer {
      busy.remove(.install)
      attention.installing = false
    }
    let environment = await AppServices.shared.environment.value
    let result = await PluginCommands.shared.installFromLock(project: path, environment: environment) { project in
      Task { await AppServices.shared.builds.forgetDependencyErrors(project: project) }
    }
    await loadDependencies()
    // Without node_modules there is no sass, and the check said "unavailable".
    await reloadScss()
    guard !join else { return }
    if !result.success {
      failure = String(result.output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(600))
    } else if let failed = result.failed, !failed.isEmpty {
      failure = L10n.t("pluginsInstalled.installPartial", ["count": String(failed.count), "names": failed.joined(separator: ", ")],
                       count: failed.count)
    }
  }

  func takeSnapshot() async {
    busy.insert(.snapshot)
    defer { busy.remove(.snapshot) }
    let environment = await AppServices.shared.environment.value
    do {
      _ = try await SnapshotStore.live(environment: environment).create(project: path, kind: "manual")
    } catch {
      failure = String(describing: error)
    }
    await loadSnapshots()
  }
}

/// Says something to VoiceOver that appeared without the user moving there (conventions, „Was
/// ohne Zutun erscheint, wird angesagt“).
enum Announce {
  static func post(_ text: String) {
    AccessibilityNotification.Announcement(text).post()
  }
}
