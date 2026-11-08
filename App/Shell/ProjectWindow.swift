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
  /// Edits on the page that are not saved: switching pages, a link and closing ask first.
  @State private var unsaved = UnsavedGuard()

  /// The sidebar's highlight, its own state: a page change the leave question cancels has to
  /// move it back, and a binding onto `pageID` left the list on the row clicked (measured).
  @State private var highlighted: ProjectPage?

  private var current: ProjectPage { ProjectPage(rawValue: pageID) ?? .overview }

  /// Every way to another page goes through here, so an edited page asks before it is left.
  private func go(to page: ProjectPage) {
    guard page.rawValue != pageID else { return }
    guard unsaved.dirty else {
      pageID = page.rawValue
      return
    }
    Task {
      if await unsaved.confirmLeave() {
        pageID = page.rawValue
      } else {
        highlighted = current
      }
    }
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
      List(selection: $highlighted) {
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
      page(current, ProjectContext(id: row.id, name: row.name, path: row.path))
        .id(pageID)
        .safeAreaInset(edge: .top, spacing: 0) { CoexistenceBand(projectPath: row.path) }
    }
    .navigationTitle(row.name)
    .environment(\.project, ProjectContext(id: row.id, name: row.name, path: row.path))
    .environment(\.openPage, OpenPageAction { go(to: $0) })
    .environment(\.unsavedGuard, unsaved)
    .onChange(of: highlighted) { _, page in
      if let page { go(to: page) }
    }
    .onChange(of: pageID, initial: true) { highlighted = current }
    .background(UnsavedWindowHook(unsaved: unsaved))
  }

  /// The ported pages; the others are placeholders until Phase 4 reaches them.
  @ViewBuilder private func page(_ page: ProjectPage, _ project: ProjectContext) -> some View {
    switch page {
    case .overview: OverviewPage(project: project)
    case .config: ConfigPage(project: project)
    case .server: BuildServerPage(project: project)
    default: PendingPage(page: page)
    }
  }

  private func rows(_ group: ProjectPage.Group) -> some View {
    ForEach(group.pages) { page in
      Label(page.title, systemImage: page.symbol)
        .tag(page)
        .accessibilityIdentifier("sidebar.\(page.rawValue)")
    }
  }
}

/// Moves the window to another page, for a link on a page (the overview's "Plugins ›").
struct OpenPageAction {
  let open: (ProjectPage) -> Void
  func callAsFunction(_ page: ProjectPage) { open(page) }
}

extension EnvironmentValues {
  @Entry var openPage = OpenPageAction { _ in }
}
