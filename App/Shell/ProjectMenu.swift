import QuartzHubCore
import SwiftUI

/// Projekt: what the frontmost window's project can do from any page, so the toolbar's actions
/// are menu commands too (HIG, Toolbars). Server and build use what Vorschau & Build holds for
/// the project (its options, its output folder), so the menu does what that page's buttons do.
struct ProjectMenu: Commands {
  @FocusedValue(\.projectActions) private var actions

  var body: some Commands {
    let _ = AppAppearance.shared.revision
    CommandMenu(L10n.t("shell.menu.project")) {
      Button(L10n.t("shell.menu.startServer")) { actions?.startServer() }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(actions?.canStart != true)
      Button(L10n.t("shell.menu.stopServer")) { actions?.stopServer() }
        .keyboardShortcut(".", modifiers: .command)
        .disabled(actions?.canStop != true)
      Divider()
      Button(L10n.t("shell.menu.runBuild")) { actions?.build() }
        .keyboardShortcut("b", modifiers: .command)
        .disabled(actions == nil)
      Divider()
      Button(L10n.t("shell.menu.revealProject")) { actions?.reveal() }
        .disabled(actions == nil)
    }
  }
}

struct ProjectActions {
  let project: ProjectContext
  let state: BuildService.ServerStatus.State

  var canStart: Bool { state == .stopped || state == .error }
  var canStop: Bool { state == .running || state == .starting }

  @MainActor func startServer() {
    let project = project, options = BuildServerMemory.shared[project.id].options
    Task { _ = await AppServices.shared.builds.startServer(projectId: project.id, project: project.path, options: options) }
  }

  @MainActor func stopServer() {
    let id = project.id
    Task { await AppServices.shared.builds.stopServer(id) }
  }

  @MainActor func build() {
    let project = project
    Task { _ = await BuildServerModel.build(project, outputDir: ProjectPrefsStore.read(project: project.path).outputDir) }
  }

  @MainActor func reveal() { ExternalOpen.openFolder(project.path) }
}

extension FocusedValues {
  @Entry var projectActions: ProjectActions?
}
