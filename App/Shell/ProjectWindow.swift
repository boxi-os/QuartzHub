import QuartzHubCore
import SwiftUI

/// One project's window: the sidebar of pages, the selected page, its inspector. Opened from the
/// Projects window by the project's id; SwiftUI keeps one window per id, so opening a project that
/// is open already brings its window to the front.
struct ProjectWindow: View {
  static let sceneID = "project"

  let projectId: String?

  @State private var model = ProjectsModel.shared
  @Environment(\.openWindow) private var openWindow
  /// "Where was I" per window, by stable identifier (docs/conventions.md, Sticky-State).
  @SceneStorage("page") private var pageID = ProjectPage.overview.rawValue

  private var selection: Binding<ProjectPage?> {
    Binding(
      get: { ProjectPage(rawValue: pageID) ?? .overview },
      set: { pageID = ($0 ?? .overview).rawValue }
    )
  }

  var body: some View {
    Group {
      if let row = projectId.flatMap(model.row) {
        pages(row)
      } else if model.loaded {
        // Removed from the list while its window was open, or a restored window of a project that
        // is gone: say so, offer the list.
        ContentUnavailableView {
          Label(L10n.t("shell.projects.notInList"), systemImage: "questionmark.folder")
        } actions: {
          Button(L10n.t("shell.projects.show")) { openWindow(id: ProjectsWindow.sceneID) }
        }
        .accessibilityIdentifier("project.notInList")
      } else {
        ProgressView(L10n.t("common.loading"))
      }
    }
    .frame(minWidth: 900, minHeight: 560)
    .task { if !model.loaded { await model.reload() } }
  }

  private func pages(_ row: ProjectOverview) -> some View {
    NavigationSplitView {
      List(selection: selection) {
        ForEach(ProjectPage.Group.allCases, id: \.self) { group in
          if let title = group.title {
            Section(title) { rows(group) }
          } else {
            rows(group)
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
      .accessibilityLabel(L10n.t("projectLayout.navLabel"))
      .accessibilityIdentifier("sidebar")
    } detail: {
      PendingPage(page: selection.wrappedValue ?? .overview)
        .id(pageID)
    }
    .navigationTitle(row.name)
    .environment(\.project, ProjectContext(id: row.id, name: row.name, path: row.path))
  }

  private func rows(_ group: ProjectPage.Group) -> some View {
    ForEach(group.pages) { page in
      Label(page.title, systemImage: page.symbol)
        .tag(page)
        .accessibilityIdentifier("sidebar.\(page.rawValue)")
    }
  }
}
