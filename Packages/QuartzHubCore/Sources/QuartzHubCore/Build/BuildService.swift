import Foundation
import Synchronization

/// Builds and dev servers of all projects (QuartzControl's `buildService.ts`). One per app: it
/// holds what runs, so every page asks it instead of keeping its own idea of "building".
///
/// The one-off build: until 2026-09-13 only QuartzControl's page that started a build knew it ran;
/// back on the page, the button said "Jetzt bauen" again, and a second click built into the same
/// folder beside the first (measured there: two pids, 40 s instead of 19).
///
/// The dev server: started with its own process group and its output in files (`ProcessRunner.launch`,
/// `ServerLogFiles`), so it can outlive QuartzHub; "running" once its page port answers and Quartz
/// has said so; recorded in `RunningServersStore` for the orphan question at the next start.
public actor BuildService {
  public enum Event: Sendable, Equatable {
    case log(LogBuffer.Kind, LogLine)
    case activity(projectId: String, BuildActivity?)
    case status(projectId: String, ServerStatus)
  }

  /// `host` is Quartz's `--remoteDevHost` (the address the browser's live reload uses behind a
  /// tunnel), not a bind address; empty locally.
  public struct ServerOptions: Sendable, Equatable {
    public var port: Int
    public var wsPort: Int
    public var host: String

    public init(port: Int = 8080, wsPort: Int = 3001, host: String = "") {
      self.port = port
      self.wsPort = wsPort
      self.host = host
    }
  }

  public struct ServerStatus: Sendable, Equatable {
    public enum State: String, Sendable {
      case stopped
      case starting
      case running
      case stopping
      case error
    }

    public var state: State
    public var options: ServerOptions?
    public var pid: Int32?
    /// The click while `starting`, the spawn once there is a process.
    public var startedAt: Date?
    /// A refusal in the user's language, or what the system said about a failed spawn.
    public var error: String?
    /// How it ended when it died on its own (a signal is no code, as Node's `null`).
    public var ended: CommandResult.Termination?

    public init(state: State, options: ServerOptions? = nil, pid: Int32? = nil, startedAt: Date? = nil,
                error: String? = nil, ended: CommandResult.Termination? = nil) {
      self.state = state
      self.options = options
      self.pid = pid
      self.startedAt = startedAt
      self.error = error
      self.ended = ended
    }
  }

  public struct Result: Sendable, Equatable {
    public var success: Bool
    public var duration: Duration
    /// nil when it never ran, or ended on a signal (Node's `code: null`).
    public var exitCode: Int32?
  }

  /// Why a build was refused before anything ran; each with the sentence the page shows.
  public enum Refusal: Error, Equatable {
    /// A build of this project into another folder is running.
    case anotherBuildRuns(running: String, wanted: String)
    /// The dev server of this project writes into that folder (or is about to).
    case serverWriting(directory: String)

    public var message: String {
      switch self {
      case .anotherBuildRuns(let running, let wanted): L10n.t("main.buildDirBusy", ["running": running, "dir": wanted])
      case .serverWriting(let directory): L10n.t("main.buildDirServerRunning", ["dir": directory])
      }
    }
  }

  /// One thing done to a project before every build and server start, reporting into the build's
  /// console. What runs there is `preparation`.
  public typealias PreparationStep = @Sendable (_ project: URL, _ report: @Sendable (LogLine.Stream, String) -> Void) async -> Void

  /// What QuartzControl does before every build and start (`refreshAuthoredFrames`,
  /// `refreshGoogleFonts`), as far as QuartzHub has it:
  ///
  /// 1. The paths to the project's own frames are pointed back into this project (a copy made
  ///    outside the app names the original's).
  /// 2. Every authored frame is rewritten against the config and the breakpoint widths as they
  ///    stand (`LayoutFrames.writeAllFrames`): its module carries copies of both, and the build is
  ///    the one place that copy is read. What went wrong goes into the console as a warning.
  ///
  /// 3. A moved project gets its `@use "./quartzcontrol";` line or its `_quartzcontrol.scss` back
  ///    when one half is missing, and the font URLs of the `fonts` block become relative
  ///    (`StyleSheets.repairManagedUse`, `migrateFontUrls`): the repair first, because the URL
  ///    migration reads the blocks through the line it restores. Each takes the styles lock, so a
  ///    save still writing custom.scss is waited for. What they did goes into the console.
  ///
  /// 4. A project that holds its Google fonts (`fontOrigin: local` and a `google-fonts` block) gets
  ///    them in line with the typography of the config (`FontService.refreshGoogleFonts`): the
  ///    config reaches the typography through more doors than the Basis tab. A failed fetch is a
  ///    warning; the build goes on with the files that are there.
  public static let preparation: [PreparationStep] = [
    { project, report in
      do {
        try await ProjectPaths.repointAuthoredFrames(project: project)
      } catch {
        report(.warn, L10n.t("main.frameRefreshFailed", ["error": String(describing: error)]) + "\n")
      }
    },
    { project, report in
      for problem in await LayoutFrames().writeAllFrames(project: project) { report(.warn, problem + "\n") }
    },
    { project, report in
      do {
        switch try await StyleSheets.repairManagedUse(project: project) {
        case .lineRestored?: report(.stdout, L10n.t("main.managedUseRestored") + "\n")
        case .fileCreated?: report(.stdout, L10n.t("main.managedFileCreated") + "\n")
        case nil: break
        }
        if try await StyleSheets.migrateFontUrls(project: project) { report(.stdout, L10n.t("main.fontUrlsMigrated") + "\n") }
      } catch {
        report(.warn, error.localizedDescription + "\n")
      }
    },
    { project, report in
      if let result = await FontService().refreshGoogleFonts(project: project) { report(result.failed ? .warn : .stdout, result.text + "\n") }
    }
  ]

  private let logs: LogBuffer
  private let environment: @Sendable () async -> ToolEnvironment
  private let steps: [PreparationStep]
  private let onEvent: @Sendable (Event) -> Void

  private let store: RunningServersStore?
  private let scanSystem: ServerScan.System
  private let stopGrace: Duration

  private var trackers: [String: BuildActivityTracker] = [:]
  private var runningBuilds: [String: (directory: String, task: Task<Result, Never>)] = [:]
  private var servers: [String: RunningServer] = [:]
  private var pendingStarts: [String: PendingStart] = [:]
  /// How a server ended, kept after its entry is gone: one that died on its own would otherwise
  /// read as cleanly stopped (QuartzControl's `lastTerminalStatus`).
  private var lastTerminal: [String: ServerStatus] = [:]
  /// Ends that only said "packages missing", with their project, so an install can take them back.
  private var dependencyErrors: [String: String] = [:]
  private var portQueue: Task<Void, Never>?

  /// `environment` is asked at each start: the Node setting may have changed since. `store` holds
  /// the servers for the orphan question (nil: not recorded). `stopGrace`: SIGTERM to SIGKILL.
  public init(logs: LogBuffer, environment: @escaping @Sendable () async -> ToolEnvironment,
              preparation: [PreparationStep] = BuildService.preparation, store: RunningServersStore? = RunningServersStore(),
              scan: ServerScan.System = .live, stopGrace: Duration = .seconds(5),
              onEvent: @escaping @Sendable (Event) -> Void = { _ in }) {
    self.logs = logs
    self.environment = environment
    self.steps = preparation
    self.store = store
    self.scanSystem = scan
    self.stopGrace = stopGrace
    self.onEvent = onEvent
  }

  public func activity(_ projectId: String) -> BuildActivity? {
    trackers[projectId]?.current
  }

  // MARK: build

  /// "Jetzt bauen". A second call for the same project and folder joins the running build; for
  /// another folder it is refused, naming the folder being built. The output folder has to have
  /// been judged by `BuildOutputGuard` before.
  public func build(projectId: String, project: URL, outputDir: String?) async throws(Refusal) -> Result {
    if let running = try joinRunningBuild(projectId: projectId, project: project, outputDir: outputDir) {
      return await running.value
    }
    try assertOutputFree(projectId: projectId, project: project, outputDir: outputDir)
    setActivity(projectId, BuildActivity(kind: .build, startedAt: Date(), phase: .preparing))
    let task = Task { await self.runBuild(projectId: projectId, project: project, outputDir: outputDir) }
    runningBuilds[projectId] = (BuildOutputGuard.resolve(BuildOutputGuard.buildDirectory(project: project.path, outputDir: outputDir)), task)
    let result = await task.value
    if runningBuilds[projectId]?.task == task { runningBuilds[projectId] = nil }
    if activity(projectId)?.kind == .build { setActivity(projectId, nil) }
    return result
  }

  /// The build running for this project, which a second "Jetzt bauen" joins, but only into the
  /// same folder: the Übersicht builds into `public/`, Vorschau & Build into the page's choice, and
  /// joining would report "Build fertig" for a folder nobody built.
  public func joinRunningBuild(projectId: String, project: URL, outputDir: String?) throws(Refusal) -> Task<Result, Never>? {
    guard let running = runningBuilds[projectId] else { return nil }
    let wanted = BuildOutputGuard.resolve(BuildOutputGuard.buildDirectory(project: project.path, outputDir: outputDir))
    guard running.directory == wanted else { throw .anotherBuildRuns(running: running.directory, wanted: wanted) }
    return running.task
  }

  private func runBuild(projectId: String, project: URL, outputDir: String?) async -> Result {
    if let missing = ProjectDependencies.missingDependencies(project: project), !missing.isEmpty {
      let names = missing.prefix(3).joined(separator: ", ") + (missing.count > 3 ? " …" : "")
      log(.build, projectId, .warn, L10n.t("main.dependenciesMissing", ["names": names]) + "\n")
      return Result(success: false, duration: .zero, exitCode: nil)
    }
    await prepare(projectId: projectId, project: project, into: .build)

    var arguments = ["quartz", "build"]
    if let outputDir, !outputDir.isEmpty { arguments += ["--output", outputDir] }
    let command = await environment().command("npx", arguments, in: project)
    // The pieces come from the supervising thread, in order; one consumer here keeps that order.
    let (pieces, feed) = AsyncStream.makeStream(of: (ProcessRunner.OutputStream, String).self)
    let consumer = Task {
      for await (stream, text) in pieces {
        self.log(.build, projectId, stream == .stdout ? .stdout : .stderr, text)
        if stream == .stdout { self.follow(projectId, text, from: .build) }
      }
      self.flush(projectId, .build)
    }
    let clock = ContinuousClock()
    let start = clock.now
    let result = await ProcessRunner.run(command) { feed.yield(($0, $1)) }
    feed.finish()
    await consumer.value
    let duration = clock.now - start
    switch result.termination {
    case .exited(let code):
      return Result(success: code == 0, duration: duration, exitCode: code)
    case .couldNotStart:
      log(.build, projectId, .stderr, result.report(for: command) + "\n")
      return Result(success: false, duration: duration, exitCode: nil)
    default:
      return Result(success: false, duration: duration, exitCode: nil)
    }
  }

  /// The preparation steps in order; what they report goes into the console of the run.
  private func prepare(projectId: String, project: URL, into kind: LogBuffer.Kind) async {
    let (reports, feed) = AsyncStream.makeStream(of: (LogLine.Stream, String).self)
    let consumer = Task {
      for await (stream, text) in reports { self.log(kind, projectId, stream, text) }
    }
    for step in steps { await step(project) { feed.yield(($0, $1)) } }
    feed.finish()
    await consumer.value
  }

  // MARK: server

  /// A start asked for that has no process yet: it may wait for a build (16 to 19 s on Example).
  /// Without it the page said "stopped" for that time and offered "Starten", and both clicks
  /// spawned (QuartzControl, sixteenth review).
  final class PendingStart {
    var status: ServerStatus
    let outputDir: String
    /// Set by `stopServer`: before there is a process, only the wait can be stopped.
    var aborted = false

    init(status: ServerStatus, outputDir: String) {
      self.status = status
      self.outputDir = outputDir
    }
  }

  final class RunningServer {
    let process: LaunchedProcess
    var status: ServerStatus
    /// `quartz build --serve` gets no `--output`: the project's `public/`.
    let outputDir: String
    var tails: [LogTail] = []
    var logFeed: AsyncStream<(LogLine.Stream, String)>.Continuation?
    var watcher: Task<Void, Never>?
    var heard = ""
    var announced = false
    var pageOpen = false

    init(process: LaunchedProcess, status: ServerStatus, outputDir: String) {
      self.process = process
      self.status = status
      self.outputDir = outputDir
    }
  }

  public func serverStatus(_ projectId: String) -> ServerStatus {
    servers[projectId]?.status ?? pendingStarts[projectId]?.status ?? lastTerminal[projectId] ?? ServerStatus(state: .stopped)
  }

  /// What runs now, for the question at quit: project and port.
  public func runningServerSummaries() -> [(projectId: String, port: Int)] {
    servers.map { ($0.key, $0.value.status.options?.port ?? ServerOptions().port) }.sorted { $0.projectId < $1.projectId }
  }

  /// pid → project for QuartzHub's own servers, so a scan tells them from a stranger's.
  public func ownedServerPids() -> [Int32: String] {
    var owned: [Int32: String] = [:]
    for (projectId, server) in servers { owned[server.process.pid] = projectId }
    return owned
  }

  /// After a successful npm install: a start that failed only for missing packages failed for
  /// nothing that is still true.
  public func forgetDependencyErrors(project: URL) {
    for (projectId, path) in dependencyErrors where path == project.path {
      dependencyErrors[projectId] = nil
      lastTerminal[projectId] = nil
      emitStatus(projectId)
    }
  }

  /// Refuses a build into the folder this project's dev server writes into. `quartz build` empties
  /// its folder and the server rebuilds on every change: QuartzControl measured 16 files of a
  /// rebuild landing in the middle of a build's "Emitting files". Only QuartzHub's own servers are
  /// known here; a stranger's is the scan's business.
  public func assertOutputFree(projectId: String, project: URL, outputDir: String?) throws(Refusal) {
    let directory = BuildOutputGuard.resolve(BuildOutputGuard.buildDirectory(project: project.path, outputDir: outputDir))
    // A start still waiting counts: it writes there as soon as it spawns.
    if let pending = pendingStarts[projectId] {
      if pending.outputDir == directory { throw .serverWriting(directory: directory) }
      return
    }
    // `stopping` is a signal sent, not a process gone.
    guard let server = servers[projectId], server.status.state != .stopped, server.status.state != .error,
          server.outputDir == directory else { return }
    throw .serverWriting(directory: directory)
  }

  /// Starts the dev server, or answers the status of the one there is. Waits for a build into the
  /// same folder (said in the console), prepares the project, then, in one turn of the port queue:
  /// refuses when a server of this project runs that QuartzHub did not start (a second would empty
  /// and rebuild the same `public/`), when packages are missing, or when a port behind a tunnel is
  /// taken; otherwise moves a taken port to the next free one and spawns.
  public func startServer(projectId: String, project: URL, options: ServerOptions = ServerOptions()) async -> ServerStatus {
    if let existing = servers[projectId] { return existing.status }
    if let waiting = pendingStarts[projectId] { return waiting.status }
    lastTerminal[projectId] = nil
    dependencyErrors[projectId] = nil

    let outputDir = BuildOutputGuard.resolve(BuildOutputGuard.buildDirectory(project: project.path, outputDir: nil))
    let pending = PendingStart(status: ServerStatus(state: .starting, options: options, startedAt: Date()), outputDir: outputDir)
    pendingStarts[projectId] = pending
    emitStatus(projectId)
    defer { if pendingStarts[projectId] === pending { pendingStarts[projectId] = nil } }

    if let build = runningBuilds[projectId], build.directory == outputDir {
      log(.server, projectId, .warn, L10n.t("main.serverWaitsForBuild", ["dir": build.directory]) + "\n")
      _ = await build.task.value
    }
    if pending.aborted { return serverStatus(projectId) }
    await prepare(projectId: projectId, project: project, into: .server)
    if pending.aborted { return serverStatus(projectId) }

    return await inPortQueue {
      let holder = await sameProjectServer(project)
      if pending.aborted { return serverStatus(projectId) }
      if let missing = ProjectDependencies.missingDependencies(project: project), !missing.isEmpty {
        let sentence = L10n.t("main.dependenciesMissing", ["names": missing.prefix(3).joined(separator: ", ") + (missing.count > 3 ? " …" : "")])
        dependencyErrors[projectId] = project.path
        return refuse(projectId, pending, sentence)
      }
      if let holder {
        return refuse(projectId, pending, L10n.t("main.serverAlreadyRunningOutside", ["port": String(holder.port), "pid": String(holder.pid)]))
      }
      // Behind a tunnel the ports are the ones it forwards: a server that moved would be one the
      // browser no longer reaches. Refused instead of moved.
      if !options.host.isEmpty {
        let own = portsOfOtherServers(projectId)
        var busy: [Int] = []
        for port in [options.port, options.wsPort] where own.contains(port) { busy.append(port) }
        for port in [options.port, options.wsPort] where !busy.contains(port) {
          if await ServerPorts.state(port) == .taken { busy.append(port) }
        }
        if pending.aborted { return serverStatus(projectId) }
        if !busy.isEmpty {
          return refuse(projectId, pending, L10n.t("main.serverPortTakenBehindTunnel", ["ports": busy.map(String.init).joined(separator: ", "), "host": options.host]))
        }
        return await spawnServer(projectId, project, pending)
      }
      let chosen = await choosePorts(projectId, options)
      if pending.aborted { return serverStatus(projectId) }
      if chosen.port != options.port {
        log(.server, projectId, .stdout, L10n.t("main.serverPortTaken", ["from": String(options.port), "to": String(chosen.port)]) + "\n")
      }
      if chosen.wsPort != options.wsPort {
        // The page port may have moved onto the very port asked for as the websocket one: then it
        // is not "in use" by anything else.
        let args = ["from": String(options.wsPort), "to": String(chosen.wsPort)]
        let sentence = options.wsPort == chosen.port ? L10n.t("main.serverWsPortIsHttpPort", args) : L10n.t("main.serverPortTaken", args)
        log(.server, projectId, .stdout, sentence + "\n")
      }
      pending.status.options = chosen
      return await spawnServer(projectId, project, pending)
    }
  }

  /// At quit: every waiting start called off, every server stopped, at most `deadline` in all (a
  /// stop that never answers must not keep the app from quitting). What survives stays in
  /// `running-servers.json` and is the next start's orphan question. `grace` is shorter than the
  /// deadline, so SIGKILL lands before it.
  public func stopAllServers(grace: Duration = .seconds(2), deadline: Duration = .seconds(3)) async {
    for (projectId, pending) in pendingStarts {
      pending.aborted = true
      pendingStarts[projectId] = nil
      emitStatus(projectId)
    }
    let ids = Array(servers.keys)
    guard !ids.isEmpty else { return }
    let work = Task {
      await withTaskGroup(of: Void.self) { group in
        for id in ids { group.addTask { await self.stopServer(id, grace: grace) } }
      }
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let once = Mutex(false)
      let finish: @Sendable () -> Void = {
        if once.withLock({ done in defer { done = true }; return !done }) { continuation.resume() }
      }
      Task { await work.value; finish() }
      Task { try? await Task.sleep(for: deadline); finish() }
    }
  }

  /// Stops the server: the wait of a start that has no process yet, or the process group (SIGTERM,
  /// SIGKILL to what is left after `stopGrace`). Answers when its end has been noted.
  public func stopServer(_ projectId: String) async {
    await stopServer(projectId, grace: stopGrace)
  }

  private func stopServer(_ projectId: String, grace: Duration) async {
    if let pending = pendingStarts[projectId] {
      pending.aborted = true
      pendingStarts[projectId] = nil
      emitStatus(projectId)
      return
    }
    guard let server = servers[projectId] else { return }
    server.status.state = .stopping
    emitStatus(projectId)
    _ = await server.process.stop(grace: grace)
    await server.watcher?.value
  }

  /// Stop and start with the options it had. The ports are waited for: npx's node can hold its
  /// sockets a moment longer, and a restart that found its own port taken would move.
  public func restartServer(projectId: String, project: URL, options: ServerOptions? = nil) async -> ServerStatus {
    let previous = servers[projectId]?.status.options ?? options ?? ServerOptions()
    await stopServer(projectId)
    await ServerPorts.waitUntilFree([previous.port, previous.wsPort], timeout: .seconds(3))
    return await startServer(projectId: projectId, project: project, options: previous)
  }

  private func refuse(_ projectId: String, _ pending: PendingStart, _ sentence: String) -> ServerStatus {
    log(.server, projectId, .warn, sentence + "\n")
    lastTerminal[projectId] = ServerStatus(state: .error, error: sentence)
    if pendingStarts[projectId] === pending { pendingStarts[projectId] = nil }
    emitStatus(projectId)
    return serverStatus(projectId)
  }

  private func spawnServer(_ projectId: String, _ project: URL, _ pending: PendingStart) async -> ServerStatus {
    let options = pending.status.options ?? ServerOptions()
    var arguments = ["quartz", "build", "--serve", "--port", String(options.port), "--wsPort", String(options.wsPort)]
    if !options.host.isEmpty { arguments += ["--remoteDevHost", options.host] }
    // No --watch: `--serve` sets it itself (quartz/cli/handlers.js).
    let command = await environment().command("npx", arguments, in: project)
    if pending.aborted { return serverStatus(projectId) }

    var files: ServerLogFiles?
    do {
      files = try ServerLogFiles.open(project: project.path)
    } catch {
      // `warn`: a sentence about a run that goes on.
      log(.server, projectId, .warn, L10n.t("main.serverLogUnavailable", ["reason": String(describing: error)]) + "\n")
    }
    let launched = ProcessRunner.launch(command, stdout: files?.stdoutFD, stderr: files?.stderrFD)
    // The child has its own copies; ours would be the last thing holding a write end.
    files?.closeOurs()
    let process: LaunchedProcess
    switch launched {
    case .failure(let failure):
      let message = CommandResult(termination: .couldNotStart(failure), output: "", stdout: "").report(for: command)
      log(.server, projectId, .stderr, message + "\n")
      lastTerminal[projectId] = ServerStatus(state: .error, error: message)
      if pendingStarts[projectId] === pending { pendingStarts[projectId] = nil }
      emitStatus(projectId)
      return serverStatus(projectId)
    case .success(let started):
      process = started
    }
    files?.adopt(process.pid)

    var status = pending.status
    status.pid = process.pid
    // The spawn, not the click: with a build in front they are a whole build apart.
    status.startedAt = Date()
    let server = RunningServer(process: process, status: status, outputDir: pending.outputDir)
    servers[projectId] = server
    pendingStarts[projectId] = nil
    emitStatus(projectId)
    try? store?.record(projectId: projectId, server: TrackedServer(pid: process.pid, port: options.port, startedAt: JS.isoString(status.startedAt!)))

    if let files {
      let (pieces, feed) = AsyncStream.makeStream(of: (LogLine.Stream, String).self)
      server.logFeed = feed
      server.tails = [LogTail(path: files.stdout) { feed.yield((.stdout, $0)) },
                      LogTail(path: files.stderr) { feed.yield((.stderr, $0)) }]
      Task {
        for await (stream, text) in pieces { self.serverSaid(projectId, server, stream, text) }
        self.flush(projectId, .server)
      }
    }
    server.watcher = Task {
      let termination = await process.exit()
      self.serverEnded(projectId, server, termination)
    }
    Task { await self.watchReadiness(projectId, server, options) }
    return status
  }

  /// "running" has to mean there is something to open: Quartz prints its banner while it still
  /// builds. Both proofs, because the page port alone is answered by whoever binds it first: the
  /// port open and Quartz's own line after its listen ("Started a Quartz server listening at
  /// http://localhost:<port>"), or, without that line, the websocket port too (QuartzControl,
  /// forty-sixth and forty-seventh review).
  private func watchReadiness(_ projectId: String, _ server: RunningServer, _ options: ServerOptions) async {
    let pid = server.process.pid
    let starting: @Sendable () async -> Bool = { await self.isStarting(projectId, pid) }
    guard await ServerPorts.waitForOpen(options.port, while: starting) else { return }
    server.pageOpen = true
    if server.announced { return markRunning(projectId, server) }
    Task {
      try? await Task.sleep(for: .seconds(5))
      if self.isStarting(projectId, pid) {
        self.log(.server, projectId, .warn,
                 L10n.t("main.serverWaitsForWsPort", ["port": String(options.port), "wsPort": String(options.wsPort)]) + "\n")
      }
    }
    if await ServerPorts.waitForOpen(options.wsPort, while: starting) { markRunning(projectId, server) }
  }

  private func isStarting(_ projectId: String, _ pid: Int32) -> Bool {
    guard let server = servers[projectId], server.process.pid == pid else { return false }
    return server.status.state == .starting
  }

  private func markRunning(_ projectId: String, _ server: RunningServer) {
    guard servers[projectId] === server, server.status.state == .starting else { return }
    server.status.state = .running
    emitStatus(projectId)
  }

  private func serverSaid(_ projectId: String, _ server: RunningServer, _ stream: LogLine.Stream, _ text: String) {
    log(.server, projectId, stream, text)
    // Both streams: Quartz writes "Rebuild failed:" with console.error.
    follow(projectId, text, from: .server)
    guard !server.announced, let port = server.status.options?.port else { return }
    let line = "Started a Quartz server listening at http://localhost:\(port)"
    server.heard = String((server.heard + text).suffix(2 * line.count))
    guard server.heard.contains(line) else { return }
    server.announced = true
    if server.pageOpen { markRunning(projectId, server) }
  }

  private func serverEnded(_ projectId: String, _ server: RunningServer, _ termination: CommandResult.Termination) {
    for tail in server.tails { tail.stop() }
    server.logFeed?.finish()
    let wasStopping = server.status.state == .stopping
    // Only if the entry is still this process's: two starts can overlap, and the loser's end used
    // to take the winner's entry and record with it (QuartzControl, sixteenth review).
    guard servers[projectId] === server else { return }
    servers[projectId] = nil
    try? store?.remove(projectId: projectId, pid: server.process.pid)
    lastTerminal[projectId] = wasStopping ? nil : ServerStatus(state: .error, ended: termination)
    emitStatus(projectId)
  }

  /// A Quartz server whose folder is this project and which QuartzHub did not start: a terminal,
  /// QuartzControl, one left running after a force quit. By real path on both sides. A scan that
  /// cannot read the process table finds nothing, and the start goes ahead.
  private func sameProjectServer(_ project: URL) async -> (port: Int, pid: Int32)? {
    let owned = ownedServerPids()
    let scan = await ServerScan.discover(projects: [], owned: owned, system: scanSystem)
    let here = BuildOutputGuard.realPath(project.path)
    for server in scan.servers where owned[server.pid] == nil {
      if let cwd = server.cwd, BuildOutputGuard.realPath(cwd) == here { return (server.port, server.pid) }
    }
    return nil
  }

  /// The ports of QuartzHub's other servers count as taken without asking.
  private func portsOfOtherServers(_ projectId: String) -> Set<Int> {
    var taken: Set<Int> = []
    for (id, server) in servers where id != projectId {
      if let options = server.status.options { taken.formUnion([options.port, options.wsPort]) }
    }
    return taken
  }

  private func choosePorts(_ projectId: String, _ requested: ServerOptions) async -> ServerOptions {
    var taken = portsOfOtherServers(projectId)
    var chosen = requested
    chosen.port = await ServerPorts.nextFree(from: requested.port, taken: taken) ?? requested.port
    taken.insert(chosen.port)
    chosen.wsPort = await ServerPorts.nextFree(from: requested.wsPort, taken: taken) ?? requested.wsPort
    return chosen
  }

  /// Choosing and spawning in one turn: the spawn enters `servers` at once, so the next start in
  /// line sees its ports as taken before the process has bound them.
  private func inPortQueue<T: Sendable>(_ body: () async -> T) async -> T {
    let previous = portQueue
    let (done, finish) = AsyncStream.makeStream(of: Void.self)
    portQueue = Task { for await _ in done {} }
    await previous?.value
    defer { finish.finish() }
    return await body()
  }

  /// The status event, and the activity that goes with it: the server's first build is part of
  /// its start and nothing of it outlives the process; a one-off build keeps its own.
  private func emitStatus(_ projectId: String) {
    let status = serverStatus(projectId)
    let current = activity(projectId)
    switch status.state {
    case .starting:
      if current == nil { setActivity(projectId, BuildActivity(kind: .serve, startedAt: Date(), phase: .preparing)) }
    case .running:
      if current?.kind == .serve { setActivity(projectId, nil) }
    default:
      if let current, current.kind != .build { setActivity(projectId, nil) }
    }
    onEvent(.status(projectId: projectId, status))
  }

  // MARK: plumbing

  private func log(_ kind: LogBuffer.Kind, _ projectId: String, _ stream: LogLine.Stream, _ text: String) {
    let line = LogLine(projectId: projectId, stream: stream, text: text)
    logs.record(kind, line)
    onEvent(.log(kind, line))
  }

  private func setActivity(_ projectId: String, _ next: BuildActivity?) {
    if trackers[projectId, default: BuildActivityTracker()].set(next) { onEvent(.activity(projectId: projectId, next)) }
  }

  private func follow(_ projectId: String, _ text: String, from source: BuildActivityTracker.Source) {
    for change in trackers[projectId, default: BuildActivityTracker()].follow(text, from: source, now: Date()) {
      onEvent(.activity(projectId: projectId, change))
    }
  }

  private func flush(_ projectId: String, _ source: BuildActivityTracker.Source) {
    for change in trackers[projectId, default: BuildActivityTracker()].flush(source, now: Date()) {
      onEvent(.activity(projectId: projectId, change))
    }
  }
}
