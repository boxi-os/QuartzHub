import QuartzHubCore
import SwiftUI

/// The window: sidebar of pages, the selected page, its inspector.
struct RootView: View {
  /// "Where was I" survives switching pages, not a relaunch's lost window
  /// (docs/conventions.md, Sticky-State). Stored by stable identifier.
  @SceneStorage("page") private var pageID = ProjectPage.overview.rawValue

  private var selection: Binding<ProjectPage?> {
    Binding(
      get: { ProjectPage(rawValue: pageID) ?? .overview },
      set: { pageID = ($0 ?? .overview).rawValue }
    )
  }

  var body: some View {
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
  }

  private func rows(_ group: ProjectPage.Group) -> some View {
    ForEach(group.pages) { page in
      Label(page.title, systemImage: page.symbol)
        .tag(page)
        .accessibilityIdentifier("sidebar.\(page.rawValue)")
    }
  }
}
