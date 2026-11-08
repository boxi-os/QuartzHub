import AppKit
import QuartzHubCore

/// "Build ausführen" from any page: QuartzControl's `build:run` handler. A build already running
/// into the same folder is joined, not asked about again. Then, before anything is read from disk,
/// the folder must not be the dev server's. Then `BuildOutputGuard`: a refused folder is said, a
/// folder holding something that is not a build is asked about, with the safe answer first.
@MainActor
enum BuildAction {
  enum Outcome {
    case finished(BuildService.Result)
    /// The user said no to emptying the folder: nothing was deleted, nothing built.
    case cancelled
    /// Refused before it started, in the user's language.
    case refused(String)
  }

  static func run(projectId: String, project: String, outputDir: String? = nil) async -> Outcome {
    let builds = AppServices.shared.builds
    do {
      if let running = try await builds.joinRunningBuild(projectId: projectId, project: project, outputDir: outputDir) {
        return .finished(await running.value)
      }
      try await builds.assertOutputFree(projectId: projectId, project: project, outputDir: outputDir)
    } catch {
      return .refused(error.message)
    }
    let dir = BuildOutputGuard.buildDirectory(project: project, outputDir: outputDir)
    switch BuildOutputGuard.assess(project: project, outputDir: outputDir) {
    case .refused(let refusal):
      return .refused(refusal.message(dir: dir))
    case .confirm(let count):
      guard confirmEmptying(dir: dir, entries: count) else { return .cancelled }
    case .ok:
      break
    }
    do {
      return .finished(try await builds.build(projectId: projectId, project: project, outputDir: outputDir))
    } catch {
      // Another build or the server got there between the question and the start.
      return .refused(error.message)
    }
  }

  /// QuartzControl put "Abbrechen" first because Electron ignored `defaultId`; here it is first
  /// for the convention (die sichere Antwort zuerst) and is the default button, so Return cancels.
  private static func confirmEmptying(dir: String, entries: Int) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.t("main.buildDirConfirmMessage", ["dir": dir])
    alert.informativeText = L10n.t("main.buildDirConfirmDetail", ["count": String(entries)])
    alert.addButton(withTitle: L10n.t("main.buildDirConfirmCancel"))
    let proceed = alert.addButton(withTitle: L10n.t("main.buildDirConfirmProceed"))
    proceed.hasDestructiveAction = true
    return alert.runModal() == .alertSecondButtonReturn
  }
}
