import QuartzHubCore
import SwiftUI

/// Every page of a project: content in the middle, the inspector on the right.
///
/// The inspector replaces every right-hand column QuartzControl had: the detail panel next to a
/// list (`DetailLayout`) and the second column of card grids. Its rule (docs/conventions.md,
/// „Inspektor“): with a selection it shows that item, its settings and its actions; without one it
/// shows the page's context (status, hints, handbook). The middle stays one column.
///
/// Visibility is one setting per window, not per page, like Xcode: whoever hides it wants it gone
/// everywhere. It is toggled by the toolbar button and by View ▸ Show/Hide Inspector, ⌃⌘I
/// (`InspectorCommand`, which reads the binding published here).
struct PageScaffold<Content: View, Inspector: View>: View {
  let page: ProjectPage
  @ViewBuilder var content: () -> Content
  @ViewBuilder var inspector: () -> Inspector

  @SceneStorage("inspector.presented") private var inspectorPresented = true
  @Environment(\.project) private var project
  @Environment(\.returnLink) private var returnLink
  @Environment(\.goToPage) private var goToPage

  var body: some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // Back where it was left (ScrollMemory), per project and page.
      .background(ScrollMemory(key: "\(project?.path ?? "")|\(page.rawValue)"))
      // The way back after a link (ReturnLink), above the middle column only: put around the
      // whole page in the window, the page and the inspector both laid out under it (measured).
      .safeAreaInset(edge: .top, spacing: 0) {
        if let returnLink { ReturnLinkBar(link: returnLink, current: page, go: goToPage) }
      }
      // The window's title is the project's name (ProjectWindow); the page is its subtitle.
      .navigationSubtitle(page.title)
      .inspectorColumn(isPresented: $inspectorPresented, content: inspector)
  }
}

/// What the inspector shows when nothing on the page is selected: what the page is, and whatever
/// the page adds about its state.
struct InspectorPageContext<Extra: View>: View {
  let page: ProjectPage
  @ViewBuilder var extra: () -> Extra

  var body: some View {
    Form {
      Section {
        LabeledContent(L10n.t("shell.inspector.thisPage")) {
          Label(page.title, systemImage: page.symbol)
        }
        // On the row, not on the Form: a Form's identifier does not reach the accessibility tree
        // (measured with XCUITest, 2026-11-06).
        .accessibilityIdentifier("inspector.pageContext")
        if let group = page.group.title {
          Text(L10n.t("shell.inspector.group", ["group": group]))
            .foregroundStyle(.secondary)
        }
      }
      extra()
    }
    .formStyle(.grouped)
  }
}

extension InspectorPageContext where Extra == EmptyView {
  init(page: ProjectPage) {
    self.init(page: page) { EmptyView() }
  }
}
