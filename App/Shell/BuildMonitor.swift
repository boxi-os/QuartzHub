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

  func status(_ projectId: String) -> BuildService.ServerStatus {
    statuses[projectId] ?? BuildService.ServerStatus(state: .stopped)
  }

  func activity(_ projectId: String) -> BuildActivity? { activities[projectId] }

  func apply(_ event: BuildService.Event) {
    switch event {
    case .status(let projectId, let status):
      statuses[projectId] = status
      versions[projectId, default: 0] += 1
    case .activity(let projectId, let activity):
      activities[projectId] = activity
      versions[projectId, default: 0] += 1
    case .log:
      break
    }
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
