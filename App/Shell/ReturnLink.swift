import QuartzHubCore
import SwiftUI

/// The way back after QuartzHub sent the user somewhere else: "Auf der Bühne zeigen", "Alle
/// Optionen in der Plugin-Liste", "Snapshot öffnen" (QuartzControl's `state/returnLink.ts`; user,
/// 2026-11-09). One link for all of them, drawn by `PageScaffold` above the page, so no page has
/// to know it exists; a jump only says where it leads.
///
/// A place is a page and, on the four pages with tabs, the tab. The window does not know a page's
/// tab (a second `@SceneStorage` of the page's key in the same scene undoes the page's writes), so
/// each tabbed page reports it with `.returnTab(page:tab:)` and takes the tab it is sent back to
/// from here.
///
/// Lifetime as in QuartzControl: the link stands while the user stays on the target, across its
/// tabs; after a jump within one page, only on the tab it led to. Going anywhere else ends it. Not
/// kept over a restart. The overview sets none: there the sidebar is the way back (Phase 4,
/// docs/decisions/phase-4-oberflaeche.md, Übersicht).
@MainActor @Observable
final class ReturnLink {
  struct Place: Equatable {
    var page: ProjectPage
    var tab: String?
  }

  private(set) var from: Place?
  private(set) var to: Place?
  /// The tab each tabbed page showed last, as it reported it.
  private var tabs: [ProjectPage: String] = [:]
  /// A tab a page is to switch to: going back, or a link that names the tab it leads to.
  private(set) var pendingTab: [ProjectPage: String] = [:]

  /// After a jump from `page` to another page has happened.
  func markPage(from page: ProjectPage, to target: Place) {
    guard page != .overview else { return }
    from = Place(page: page, tab: tabs[page])
    to = target
  }

  /// Before a jump to another tab of the page shown.
  func markTab(_ page: ProjectPage, to tab: String) {
    from = Place(page: page, tab: tabs[page])
    to = Place(page: page, tab: tab)
  }

  var inPage: Bool { from != nil && from?.page == to?.page }

  /// The window shows `page` now.
  func notePage(_ page: ProjectPage) {
    if let to, to.page != page { clear() }
  }

  /// A tabbed page shows `tab` now.
  func noteTab(_ page: ProjectPage, _ tab: String) {
    tabs[page] = tab
    if inPage, to?.page == page, to?.tab != tab { clear() }
  }

  func clear() {
    from = nil
    to = nil
  }

  func send(_ page: ProjectPage, tab: String) { pendingTab[page] = tab }

  func takePendingTab(_ page: ProjectPage) -> String? { pendingTab.removeValue(forKey: page) }

  /// "Plugins › Zusätzliche Inhalte": the sidebar's name, and the tab's where there is one.
  static func label(_ place: Place) -> String {
    guard let tab = place.tab else { return place.page.title }
    let name: String? = switch place.page {
    case .plugins: PluginsPage.Tab(rawValue: tab)?.title
    case .layout: LayoutModel.Tab(rawValue: tab)?.title
    case .config: ConfigPage.Tab(rawValue: tab)?.title
    case .styles: StylesModel.Tab(rawValue: tab)?.title
    default: nil
    }
    return name.map { "\(place.page.title) › \($0)" } ?? place.page.title
  }
}

extension EnvironmentValues {
  @Entry var returnLink: ReturnLink?
}

extension View {
  /// A tabbed page tells the way back which tab it shows, and switches when it is sent back.
  func returnTab(page: ProjectPage, tab: Binding<String>) -> some View {
    modifier(ReturnTab(page: page, tab: tab))
  }
}

private struct ReturnTab: ViewModifier {
  let page: ProjectPage
  @Binding var tab: String
  @Environment(\.returnLink) private var link

  func body(content: Content) -> some View {
    content
      .onAppear {
        take()
        link?.noteTab(page, tab)
      }
      .onChange(of: link?.pendingTab[page]) { take() }
      .onChange(of: tab) { _, new in link?.noteTab(page, new) }
  }

  private func take() {
    if let next = link?.takePendingTab(page), next != tab { tab = next }
  }
}

/// "‹ Zurück zu „Plugins › Zusätzliche Inhalte“", above the page while the user is on the target.
/// Within a page it is a tab switch, which asks nothing; out of it, the sidebar's question.
struct ReturnLinkBar: View {
  let link: ReturnLink
  let current: ProjectPage
  let go: GoToPageAction

  var body: some View {
    if let from = link.from, let to = link.to, to.page == current {
      HStack {
        Button {
          if link.inPage {
            link.clear()
            if let tab = from.tab { link.send(from.page, tab: tab) }
          } else {
            go(from.page) {
              link.clear()
              if let tab = from.tab { link.send(from.page, tab: tab) }
            }
          }
        } label: {
          Label(L10n.t("projectLayout.returnTo", ["place": ReturnLink.label(from)]), systemImage: "chevron.backward")
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("returnLink")
        Spacer(minLength: 0)
      }
      .font(.callout)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .background(.bar)
      .overlay(alignment: .bottom) { Divider() }
    }
  }
}
