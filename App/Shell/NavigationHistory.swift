import QuartzHubCore
import SwiftUI

/// Back and forward through the places of one project window, like a browser or Finder
/// (decisions/ui-ueberarbeitung.md, Verlauf). It replaces the one-step "‹ Zurück zu …" bar of
/// QuartzControl's `state/returnLink.ts`: a link to another page is now an ordinary step, and so
/// is the way back from it.
///
/// A place is a page and, on the four pages with tabs, the tab. The window does not know a page's
/// tab (a second `@SceneStorage` of the page's key in the same scene undoes the page's writes), so
/// each tabbed page reports it with `.historyTab(page:tab:)` and takes the tab it is sent to from
/// here. A step is recorded when the page changes or a page's tab changes; the first tab a page
/// reports after it appeared only completes the place. Not kept over a restart.
@MainActor @Observable
final class NavigationHistory {
  struct Place: Equatable {
    var page: ProjectPage
    var tab: String?
  }

  enum Step { case back, forward }

  /// Enough for an afternoon; the oldest steps go first.
  static let limit = 50

  private(set) var back: [Place] = []
  private(set) var forward: [Place] = []
  private(set) var current: Place?
  /// The tab each tabbed page showed last, as it reported it.
  private var tabs: [ProjectPage: String] = [:]
  /// A tab a page is to switch to: a step back or forward, or a link that names the tab.
  private(set) var pendingTab: [ProjectPage: String] = [:]

  func target(_ step: Step) -> Place? { step == .back ? back.last : forward.last }

  /// The window shows `page` now. A step, unless the window got there by `commit`.
  func notePage(_ page: ProjectPage) {
    guard current?.page != page else { return }
    if let current { record(current) }
    current = Place(page: page, tab: pendingTab[page] ?? tabs[page])
  }

  /// A tabbed page shows `tab` now.
  func noteTab(_ page: ProjectPage, _ tab: String) {
    tabs[page] = tab
    guard let place = current, place.page == page, place.tab != tab else { return }
    if place.tab != nil { record(place) }
    current = Place(page: page, tab: tab)
  }

  /// Once the window has gone to `target(step)`'s page (or is on it): that place is the current
  /// one, the page is sent its tab.
  func commit(_ step: Step) {
    guard let place = current else { return }
    switch step {
    case .back:
      guard let next = back.popLast() else { return }
      forward.append(place)
      current = next
    case .forward:
      guard let next = forward.popLast() else { return }
      back.append(place)
      current = next
    }
    if let current, let tab = current.tab { pendingTab[current.page] = tab }
  }

  func send(_ page: ProjectPage, tab: String) { pendingTab[page] = tab }

  func takePendingTab(_ page: ProjectPage) -> String? { pendingTab.removeValue(forKey: page) }

  private func record(_ place: Place) {
    back.append(place)
    if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
    forward.removeAll()
  }

  /// "Plugins › Zusätzliche Inhalte": the sidebar's name, and the tab's where there is one.
  static func label(_ place: Place) -> String {
    guard let tab = tabTitle(place) else { return place.page.title }
    return "\(place.page.title) › \(tab)"
  }

  /// The tab's name, for the window's subtitle.
  static func tabTitle(_ place: Place) -> String? {
    guard let tab = place.tab else { return nil }
    return switch place.page {
    case .plugins: PluginsPage.Tab(rawValue: tab)?.title
    case .layout: LayoutModel.Tab(rawValue: tab)?.title
    case .config: ConfigPage.Tab(rawValue: tab)?.title
    case .styles: StylesModel.Tab(rawValue: tab)?.title
    default: nil
    }
  }
}

extension EnvironmentValues {
  @Entry var history: NavigationHistory?
}

extension View {
  /// A tabbed page tells the history which tab it shows, and switches when it is sent to another.
  func historyTab(page: ProjectPage, tab: Binding<String>) -> some View {
    modifier(HistoryTab(page: page, tab: tab))
  }
}

private struct HistoryTab: ViewModifier {
  let page: ProjectPage
  @Binding var tab: String
  @Environment(\.history) private var history

  func body(content: Content) -> some View {
    content
      .onAppear {
        // A tab taken here is reported by `onChange(of: tab)`: read back in the same closure, the
        // scene storage can still give the old one, which would record a step that never was.
        if !take() { history?.noteTab(page, tab) }
      }
      .onChange(of: history?.pendingTab[page]) { take() }
      .onChange(of: tab) { _, new in history?.noteTab(page, new) }
  }

  @discardableResult private func take() -> Bool {
    guard let next = history?.takePendingTab(page), next != tab else { return false }
    tab = next
    return true
  }
}

/// Back and forward for the toolbar and the Go menu, published by the frontmost project window.
struct WindowNavigation {
  let backTitle: String?
  let forwardTitle: String?
  let step: (NavigationHistory.Step) -> Void
  let open: (ProjectPage) -> Void
  let current: ProjectPage
}

extension FocusedValues {
  @Entry var windowNavigation: WindowNavigation?
}

/// The two buttons at the toolbar's leading edge, after the sidebar's: one group, like Finder's.
struct HistoryButtons: ToolbarContent {
  let history: NavigationHistory
  let step: (NavigationHistory.Step) -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button { step(.back) } label: {
        Label(L10n.t("shell.history.back"), systemImage: "chevron.backward")
      }
      .help(history.back.last.map { L10n.t("projectLayout.returnTo", ["place": NavigationHistory.label($0)]) } ?? L10n.t("shell.history.back"))
      .disabled(history.back.isEmpty)
      .accessibilityIdentifier("history.back")
      Button { step(.forward) } label: {
        Label(L10n.t("shell.history.forward"), systemImage: "chevron.forward")
      }
      .help(history.forward.last.map { L10n.t("shell.history.forwardTo", ["place": NavigationHistory.label($0)]) } ?? L10n.t("shell.history.forward"))
      .disabled(history.forward.isEmpty)
      .accessibilityIdentifier("history.forward")
    }
  }
}

/// Gehe zu: back, forward (⌘[ ⌘], as in Finder and Safari) and every page of the window.
struct GoCommands: Commands {
  @FocusedValue(\.windowNavigation) private var navigation

  var body: some Commands {
    let _ = AppAppearance.shared.revision
    CommandMenu(L10n.t("shell.menu.go")) {
      Button(L10n.t("shell.history.back")) { navigation?.step(.back) }
        .keyboardShortcut("[", modifiers: .command)
        .disabled(navigation?.backTitle == nil)
      Button(L10n.t("shell.history.forward")) { navigation?.step(.forward) }
        .keyboardShortcut("]", modifiers: .command)
        .disabled(navigation?.forwardTitle == nil)
      Divider()
      ForEach(ProjectPage.allCases) { page in
        Toggle(isOn: Binding(get: { navigation?.current == page }, set: { _ in navigation?.open(page) })) {
          Label(page.title, systemImage: page.symbol)
        }
        .disabled(navigation == nil)
      }
    }
  }
}
