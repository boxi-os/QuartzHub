import QuartzHubCore
import SwiftUI

/// The window: sidebar of pages, the selected page, its inspector.
struct RootView: View {
  /// "Where was I" survives switching pages, not a relaunch's lost window
  /// (docs/conventions.md, Sticky-State). Stored by stable identifier.
  @SceneStorage("page") private var pageID = ProjectPage.overview.rawValue
  /// The takeover from QuartzControl, offered while QuartzHub has no project list of its own.
  @State private var migration: (source: ProfileDirectory, plan: ProfileMigration.Plan)? = RootView.pendingMigration()

  private static func pendingMigration() -> (source: ProfileDirectory, plan: ProfileMigration.Plan)? {
    guard let source = AppProfile.quartzControl,
          ProfileMigration.shouldOffer(source: source, target: AppProfile.own) else { return nil }
    let plan = ProfileMigration.plan(source: source)
    return plan.isEmpty ? nil : (source, plan)
  }

  private var migrationPresented: Binding<Bool> {
    Binding(get: { migration != nil }, set: { if !$0 { migration = nil } })
  }

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
    .sheet(isPresented: migrationPresented) {
      if let migration {
        MigrationSheet(source: migration.source, plan: migration.plan) { self.migration = nil }
          .interactiveDismissDisabled()
      }
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
