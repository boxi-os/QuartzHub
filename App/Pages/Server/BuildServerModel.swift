import QuartzHubCore
import SwiftUI

/// What Vorschau & Build keeps while QuartzHub runs, per project (QuartzControl's `useStickyState`):
/// a page is torn down when the sidebar moves on, and a port typed a moment ago should still be
/// there. In memory only, as there: a draft, not a setting.
@MainActor
final class BuildServerMemory {
  static let shared = BuildServerMemory()

  struct State {
    var options = BuildService.ServerOptions()
    var optionsOpen = false
    var previewOpen = true
    var previewMode = PreviewWidth.Mode.desktop
  }

  private var states: [String: State] = [:]

  subscript(projectId: String) -> State {
    get { states[projectId] ?? State() }
    set { states[projectId] = newValue }
  }
}

/// Vorschau & Build (QuartzControl's `BuildServer.tsx`): the dev server with its address, options,
/// live preview and console; the one-off build with the output folder it writes to.
@MainActor @Observable
final class BuildServerModel {
  let project: ProjectContext

  /// The options the form holds, which are what the next start asks for; a running server's real
  /// ones (a port moved to the next free one) are shown instead while it is active, not copied in.
  var options: BuildService.ServerOptions { didSet { remember { $0.options = options } } }
  var optionsOpen: Bool { didSet { remember { $0.optionsOpen = optionsOpen } } }
  var previewOpen: Bool { didSet { remember { $0.previewOpen = previewOpen } } }
  var previewMode: PreviewWidth.Mode { didSet { remember { $0.previewMode = previewMode } } }
  /// Remounts the preview ("Vorschau neu laden") without changing the address it shows.
  var previewNonce = 0
  var breakpoints = (tablet: FrameBreakpointWidths.defaults.tablet, mobile: FrameBreakpointWidths.defaults.mobile)

  /// True only once the content folder was read and has no index.md: a failed read says nothing.
  var missingIndex = false

  /// `project-prefs.json`'s `outputDir`, shared with Veröffentlichen; written when settled.
  var outputDir = ""
  /// What the file holds: leaving the field unchanged writes nothing (and creates no `.quartz-gui/`).
  private var savedOutputDir = ""
  var outputDirError: String?
  var output: Result<BuildOutput.Info, BuildOutput.Unreadable>?
  var buildResult: BuildService.Result?
  /// Between the click and the service reporting the build.
  var clicked = false

  init(project: ProjectContext) {
    self.project = project
    let state = BuildServerMemory.shared[project.id]
    options = state.options
    optionsOpen = state.optionsOpen
    previewOpen = state.previewOpen
    previewMode = state.previewMode
  }

  private func remember(_ change: (inout BuildServerMemory.State) -> Void) {
    change(&BuildServerMemory.shared[project.id])
  }

  func load() async {
    let path = project.path
    await BuildMonitor.shared.refresh(project.id, from: AppServices.shared.builds)
    outputDir = ProjectPrefsStore.read(project: path).outputDir
    savedOutputDir = outputDir
    let widths = LayoutFrames.widths(project: path)
    breakpoints = (widths.tablet, widths.mobile)
    missingIndex = (try? ContentFolder.status(project: path))?.hasIndex == false
    await refreshOutput()
  }

  func refreshOutput() async {
    let path = project.path
    let dir = outputDir.isEmpty ? nil : outputDir
    output = await Task.detached { Result { () throws(BuildOutput.Unreadable) in try BuildOutput.info(project: path, outputDir: dir) } }.value
  }

  // MARK: Server

  // No state is set from the answers: the monitor carries every transition, and a start that
  // waits for a build answers only after it, by when its answer is older than what the page shows.

  func start() {
    let project = project, options = options
    Task { _ = await AppServices.shared.builds.startServer(projectId: project.id, project: project.path, options: options) }
  }

  func stop() {
    let id = project.id
    Task { await AppServices.shared.builds.stopServer(id) }
  }

  func restart() {
    let project = project, options = options
    Task { _ = await AppServices.shared.builds.restartServer(projectId: project.id, project: project.path, options: options) }
  }

  // MARK: Build

  func runBuild() async {
    clicked = true
    buildResult = nil
    defer { clicked = false }
    switch await BuildAction.run(projectId: project.id, project: project.path, outputDir: outputDir.isEmpty ? nil : outputDir) {
    case .finished(let result):
      buildResult = result
      Announce.post(resultLine(result))
    case .refused(let message):
      // Into the build console, where the reader is already looking (QuartzControl's choice here).
      BuildMonitor.shared.logs(project.id).append(.build, LogLine(projectId: project.id, stream: .stderr, text: message))
      Announce.post(message)
    case .cancelled:
      break
    }
    await refreshOutput()
  }

  func resultLine(_ result: BuildService.Result) -> String {
    let seconds = Double(result.duration.components.seconds) + Double(result.duration.components.attoseconds) / 1e18
    return L10n.t("buildServer.resultLine", [
      "status": result.success ? L10n.t("buildServer.success") : L10n.t("buildServer.failed"),
      "seconds": seconds.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: L10n.language)))
    ])
  }

  /// Written when the value is settled (Return, focus gone, picker, reset), never per keystroke.
  func commitOutputDir(_ next: String) async {
    outputDir = next
    if let problem = ProjectPrefs.outputDirProblem(next) {
      outputDirError = problem
      return
    }
    outputDirError = nil
    guard next != savedOutputDir else { return }
    do {
      try ProjectPrefsStore.update(project: project.path) { $0.outputDir = next }
      savedOutputDir = next
    } catch {
      outputDirError = String(describing: error)
    }
    await refreshOutput()
  }
}
