import Foundation

/// Builds and dev servers of all projects (QuartzControl's `buildService.ts`). One per app: it
/// holds what runs, so every page asks it instead of keeping its own idea of "building".
///
/// This part: the one-off build. Until 2026-09-13 only QuartzControl's page that started a build
/// knew it ran; back on the page, the button said "Jetzt bauen" again, and a second click built
/// into the same folder beside the first (measured there: two pids, 40 s instead of 19).
public actor BuildService {
  public enum Event: Sendable, Equatable {
    case log(LogBuffer.Kind, LogLine)
    case activity(projectId: String, BuildActivity?)
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

    public var message: String {
      switch self {
      case .anotherBuildRuns(let running, let wanted): L10n.t("main.buildDirBusy", ["running": running, "dir": wanted])
      }
    }
  }

  /// One thing done to a project before every build and server start, reporting into the build's
  /// console. What runs there is `preparation`.
  public typealias PreparationStep = @Sendable (_ project: URL, _ report: @Sendable (LogLine.Stream, String) -> Void) async -> Void

  /// What QuartzControl does before every build and start (`refreshAuthoredFrames`,
  /// `refreshGoogleFonts`), as far as QuartzHub has it: the paths to the project's own frames are
  /// pointed back into this project (a copy made outside the app names the original's). Writing
  /// the frames, repairing the managed style blocks and refreshing the Google fonts come with
  /// point 5 of phase 3 (layoutFrameService, styleService, fontService), here.
  public static let preparation: [PreparationStep] = [
    { project, report in
      do {
        try await ProjectPaths.repointAuthoredFrames(project: project)
      } catch {
        report(.warn, L10n.t("main.frameRefreshFailed", ["error": String(describing: error)]) + "\n")
      }
    }
  ]

  private let logs: LogBuffer
  private let environment: @Sendable () async -> ToolEnvironment
  private let steps: [PreparationStep]
  private let onEvent: @Sendable (Event) -> Void

  private var trackers: [String: BuildActivityTracker] = [:]
  private var runningBuilds: [String: (directory: String, task: Task<Result, Never>)] = [:]

  /// `environment` is asked at each start: the Node setting may have changed since.
  public init(logs: LogBuffer, environment: @escaping @Sendable () async -> ToolEnvironment,
              preparation: [PreparationStep] = BuildService.preparation, onEvent: @escaping @Sendable (Event) -> Void = { _ in }) {
    self.logs = logs
    self.environment = environment
    self.steps = preparation
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
    await prepare(projectId: projectId, project: project)

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

  /// The preparation steps in order; what they report goes into the build's console.
  private func prepare(projectId: String, project: URL) async {
    let (reports, feed) = AsyncStream.makeStream(of: (LogLine.Stream, String).self)
    let consumer = Task {
      for await (stream, text) in reports { self.log(.build, projectId, stream, text) }
    }
    for step in steps { await step(project) { feed.yield(($0, $1)) } }
    feed.finish()
    await consumer.value
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
