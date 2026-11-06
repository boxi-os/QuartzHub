import QuartzHubCore
import SwiftUI

/// A page that is not ported yet (Phase 4 replaces each with the real one). It already uses the
/// scaffold, so every page has the inspector from the first day.
struct PendingPage: View {
  let page: ProjectPage

  var body: some View {
    PageScaffold(page: page) {
      ContentUnavailableView {
        Label(page.title, systemImage: page.symbol)
      } description: {
        Text(L10n.t("shell.page.pending"))
      }
      .accessibilityIdentifier("page.\(page.rawValue)")
    } inspector: {
      InspectorPageContext(page: page)
    }
  }
}
