import AppKit
import QuartzHubCore

/// What the app holds for its whole life: the console buffer and the one `BuildService`, with the
/// server record in QuartzHub's profile (`-QHProfileDir` moves it, as everything else).
@MainActor
final class AppServices {
  static let shared = AppServices()

  let logs = LogBuffer()
  let store = RunningServersStore(profile: AppProfile.own)
  let builds: BuildService
  /// The tools for every command the app runs, resolved once (the login shell is asked for PATH)
  /// and again when the Node setting changes: a running server keeps the environment it was
  /// started with, everything started afterwards gets the new one.
  private(set) var environment: Task<ToolEnvironment, Never>

  private init() {
    environment = Self.resolve()
    // States and activity go to the pages through one stream, so they arrive in the order the
    // service sent them; log lines stay in `logs`.
    let (events, feed) = AsyncStream.makeStream(of: BuildService.Event.self)
    // Through `current()`, not the task of this moment: a build started after the Node setting
    // changed takes the new environment.
    builds = BuildService(logs: logs, environment: { await AppServices.current() }, store: store, onEvent: { event in
      if case .log = event { return }
      feed.yield(event)
    })
    Task { @MainActor in
      for await event in events { BuildMonitor.shared.apply(event) }
    }
  }

  private static func resolve() -> Task<ToolEnvironment, Never> {
    let mode = SettingsStore.read(AppProfile.own).nodeRuntime == .system ? ToolEnvironment.NodeMode.system : .embedded
    return Task { await ToolEnvironment.resolve(nodeMode: mode) }
  }

  /// After "Node-Laufzeit" changed.
  func reloadEnvironment() {
    environment = Self.resolve()
  }

  nonisolated static func current() async -> ToolEnvironment {
    await MainActor.run { shared.environment }.value
  }

  /// Templates with the real commands: npm, `quartz plugin add`, git, the snapshot store.
  func templates() async -> TemplatePackage {
    let environment = await environment.value
    let snapshots = SnapshotStore.live(environment: environment)
    let read: LayoutFrames.ReadConfig = { try await ConfigFile.read(project: $0, runtime: environment.runtime) }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    return TemplatePackage.live(
      environment: environment, locales: LocaleFiles(environment: environment),
      frames: LayoutFrames(readConfig: read, plugins: .cli(environment: { environment }, snapshot: snapshots.take)),
      fonts: FontService(readConfig: read), snapshots: snapshots, appVersion: version)
  }
}

/// The two questions about dev servers that only the app can ask (QuartzControl's
/// `promptForOrphanedServers` and its `before-quit` handler, docs/decisions/phase-3-dienste.md):
///
/// - **At the start**, after the window: servers a previous run left behind (crash, force quit,
///   "Weiterlaufen lassen"). The safe answer is the first button and Return: keep them
///   (QuartzControl put "Beenden" there; conventions, "Ja/Nein-Bestätigungen": die sichere Antwort
///   zuerst).
/// - **At quit**, when servers run: "Abbrechen" (first, Return and Escape), "Weiterlaufen lassen",
///   "Server beenden"; "Nicht mehr fragen" remembers the answer that was clicked, in
///   `settings.json` (`serversOnQuit`), which also skips the question.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var quitDecided = false
  private var quitAsking = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppAppearance.shared.applyTheme(SettingsStore.read(AppProfile.own).theme)
    #if DEBUG
    // For the UI test of these questions: a dev server of the project at that path, started as
    // the server page will start it.
    if let path = UserDefaults.standard.string(forKey: "QHStartServerFor"),
       let entry = try? ProjectStore(profile: AppProfile.own).add(path: path) {
      Task { _ = await AppServices.shared.builds.startServer(projectId: entry.id, project: path) }
    }
    #endif
    // After the window: the question runs code that signals processes, and nothing of that is
    // worth losing the window over.
    DispatchQueue.main.async { self.askAboutOrphans() }
  }

  private func askAboutOrphans() {
    let orphans = OrphanedServers.detect(store: AppServices.shared.store)
    guard !orphans.isEmpty else { return }
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = L10n.t("main.orphanTitle")
    alert.informativeText = L10n.t("main.orphanMessage") + "\n" + entries(orphans.map { ($0.projectId, $0.port) })
    alert.addButton(withTitle: L10n.t("main.orphanKeepRunning"))
    alert.addButton(withTitle: L10n.t("main.orphanQuit"))
    if alert.runModal() == .alertSecondButtonReturn { OrphanedServers.stop(orphans) }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitDecided { return .terminateNow }
    // A second Cmd+Q while the question is up opens no second one.
    if quitAsking { return .terminateCancel }
    quitAsking = true
    Task {
      let quit = await settleRunningServers()
      quitAsking = false
      quitDecided = quit
      sender.reply(toApplicationShouldTerminate: quit)
    }
    return .terminateLater
  }

  /// true: quit (with whatever had to happen to the servers done).
  private func settleRunningServers() async -> Bool {
    let builds = AppServices.shared.builds
    let running = await builds.runningServerSummaries()
    guard !running.isEmpty else { return true }
    // Read now, not at the start: switching the question back on takes effect without a restart.
    var decision = settings().serversOnQuit
    if decision == .ask {
      guard let answer = askAboutRunning(running) else { return false }
      decision = answer
    }
    if decision == .stop { await builds.stopAllServers() }
    return true
  }

  /// nil: cancelled, nothing decided, nothing remembered.
  private func askAboutRunning(_ running: [(projectId: String, port: Int)]) -> SettingsFile.ServersOnQuit? {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.t("main.quitMessage")
    alert.informativeText = entries(running) + "\n\n" + L10n.t("main.quitDetail")
    alert.addButton(withTitle: L10n.t("main.confirmCancel"))
    alert.addButton(withTitle: L10n.t("main.orphanKeepRunning"))
    alert.addButton(withTitle: L10n.t("main.quitStopServers"))
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = L10n.t("main.quitDontAskAgain")
    let answer: SettingsFile.ServersOnQuit
    switch alert.runModal() {
    case .alertSecondButtonReturn: answer = .keep
    case .alertThirdButtonReturn: answer = .stop
    default: return nil
    }
    // The answer clicked, not "never ask": ticked beside "Weiterlaufen lassen" it means something
    // else than beside "Server beenden". Read-modify-write, the other settings stay.
    if alert.suppressionButton?.state == .on {
      _ = try? SettingsStore.update(AppProfile.own) { $0.serversOnQuit = answer }
    }
    return answer
  }

  private func settings() -> SettingsFile { SettingsStore.read(AppProfile.own) }

  /// One line per server: the project's name (its id when the list does not know it) and port.
  private func entries(_ servers: [(projectId: String, port: Int)]) -> String {
    let store = ProjectStore(profile: AppProfile.own)
    return servers.map { server in
      L10n.t("main.orphanEntry", ["name": store.project(id: server.projectId)?.name ?? server.projectId, "port": String(server.port)])
    }.joined(separator: "\n")
  }
}
