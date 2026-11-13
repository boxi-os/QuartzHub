import QuartzHubCore
import SwiftUI

/// The dev servers' states and what Quartz is doing, per project, for the pages to watch: QuartzControl's
/// `server.onStatus` subscription and `useBuildActivity`. Fed by `BuildService`'s events in their
/// order (one stream, one reader on the main actor), so a page shows a build started on another
/// page or in another window too.
@MainActor @Observable
final class BuildMonitor {
  static let shared = BuildMonitor()

  private(set) var statuses: [String: BuildService.ServerStatus] = [:]
  private(set) var activities: [String: BuildActivity] = [:]
  /// Counts the events per project, so a first read that comes back after one does not undo it.
  private var versions: [String: Int] = [:]
  /// Each server of any project that came to rest (stopped, running, failed), for the list of
  /// servers on the machine: it changes then without the window losing focus.
  private(set) var settledServers = 0
  private(set) var lastSettled: BuildService.ServerStatus.State?
  /// The consoles, per project: not observed as a whole, so a line of one project redraws only
  /// that project's console.
  @ObservationIgnored private var logs: [String: ProjectLogs] = [:]
  /// The last one-off build per project, for the line on Vorschau & Build.
  private var buildResults: [String: BuildService.Result] = [:]

  func buildResult(_ projectId: String) -> BuildService.Result? { buildResults[projectId] }
  func setBuildResult(_ projectId: String, _ result: BuildService.Result?) { buildResults[projectId] = result }

  func status(_ projectId: String) -> BuildService.ServerStatus {
    statuses[projectId] ?? BuildService.ServerStatus(state: .stopped)
  }

  func activity(_ projectId: String) -> BuildActivity? { activities[projectId] }

  func apply(_ event: BuildService.Event) {
    switch event {
    case .status(let projectId, let status):
      statuses[projectId] = status
      versions[projectId, default: 0] += 1
      if [.stopped, .running, .error].contains(status.state) {
        lastSettled = status.state
        settledServers += 1
      }
    case .activity(let projectId, let activity):
      activities[projectId] = activity
      versions[projectId, default: 0] += 1
    case .log(let kind, let line):
      logs(line.projectId).append(kind, line)
    }
  }

  /// QuartzControl's `useLogStore`: this monitor reads the service's events from QuartzHub's start,
  /// so it is the one subscriber that is always there, and nothing printed while another page was
  /// open is lost. Kept in memory only.
  func logs(_ projectId: String) -> ProjectLogs {
    if let existing = logs[projectId] { return existing }
    let created = ProjectLogs()
    logs[projectId] = created
    return created
  }

  /// "Ausgabe leeren": the service's buffer too, so it is not read back later.
  func clearLog(_ projectId: String, _ kind: LogBuffer.Kind) {
    AppServices.shared.logs.clear(projectId, kind)
    logs(projectId).clear(kind)
  }

  /// The state as the service holds it, for a page that opens before any event of its project.
  func refresh(_ projectId: String, from builds: BuildService) async {
    let version = versions[projectId, default: 0]
    let status = await builds.serverStatus(projectId)
    let activity = await builds.activity(projectId)
    guard versions[projectId, default: 0] == version else { return }
    statuses[projectId] = status
    activities[projectId] = activity
  }
}

/// One project's two consoles. `total` counts every line ever appended and `generation` every
/// clear, so a console can append what is new instead of drawing 999 lines again.
@MainActor @Observable
final class ProjectLogs {
  struct Lines: Equatable {
    var lines: [LogLine] = []
    var total = 0
    var generation = 0
  }

  private(set) var server = Lines()
  private(set) var build = Lines()

  func lines(_ kind: LogBuffer.Kind) -> Lines { kind == .server ? server : build }

  func append(_ kind: LogBuffer.Kind, _ line: LogLine) {
    change(kind) { stream in
      stream.lines.append(line)
      if stream.lines.count > LogBuffer.maxLines { stream.lines.removeFirst(stream.lines.count - LogBuffer.maxLines) }
      stream.total += 1
    }
  }

  func clear(_ kind: LogBuffer.Kind) {
    change(kind) { stream in
      stream.lines = []
      stream.generation += 1
    }
  }

  private func change(_ kind: LogBuffer.Kind, _ body: (inout Lines) -> Void) {
    if kind == .server { body(&server) } else { body(&build) }
  }
}
