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

  /// Where the Layout page is to open, handed over from the Plugins page. Not the page's own
  /// `@SceneStorage` keys: two properties of one key in one scene undo each other's writes
  /// (measured: the Layout page's tab picker stopped switching).
  @State private var layoutHandOver = LayoutHandOver()
  /// Back and forward through the window's pages and tabs (⌘[ ⌘]).
  @State private var history = NavigationHistory()
  /// What putting back a vault link an interrupted run had parked found to say (review 2026-11-11, M1).
  @State private var contentLinkNote: String?

  private var current: ProjectPage { ProjectPage(rawValue: pageID) ?? .overview }

  /// Every way to another page goes through here, so an edited page asks before it is left.
  /// `done` runs once the page has changed, not when the question was answered with Abbrechen.
  private func go(to page: ProjectPage, done: @escaping () -> Void = {}) {
    guard page.rawValue != pageID else { return }
    guard unsaved.dirty else {
      pageID = page.rawValue
      done()
      return
    }
    Task {
      if await unsaved.confirmLeave() {
        pageID = page.rawValue
        done()
      } else {
        highlighted = current
      }
    }
  }

  /// A link on a page: to `page`, on `tab` when it names one. The way back is the history's.
  private func follow(to page: ProjectPage, tab: String?) {
    go(to: page) {
      if let tab { history.send(page, tab: tab) }
    }
  }

  /// A step back or forward: to another page through the leave question, or a tab of this one.
  private func travel(_ step: NavigationHistory.Step) {
    guard let target = history.target(step) else { return }
    if target.page == current {
      history.commit(step)
    } else {
      go(to: target.page) { history.commit(step) }
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
    .task(id: projectId.flatMap(model.row)?.path) {
      if let path = projectId.flatMap(model.row)?.path { contentLinkNote = Self.recoverContentLink(path) }
    }
    .alert(L10n.t("shell.contentLink.title"), isPresented: Binding(get: { contentLinkNote != nil }, set: { if !$0 { contentLinkNote = nil } })) {
      Button(L10n.t("shell.alert.ok"), role: .cancel) {}
    } message: {
      Text(contentLinkNote ?? "")
    }
  }

  /// Before any page reads content/: a link a run had parked when QuartzHub quit or crashed.
  static func recoverContentLink(_ project: String) -> String? {
    do {
      switch try ContentFolder.recoverParkedLink(project: project) {
      case .relinked(let target)?: return L10n.t("shell.contentLink.relinked", ["target": target])
      case .relinkedAfterMovingAside(let target, _)?: return L10n.t("shell.contentLink.relinkedMovedAside", ["target": target])
      case nil: return nil
      }
    } catch {
      return L10n.t("shell.contentLink.failed", ["error": PublishFailure.message(of: error)])
    }
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
      // QuartzControl's card above the navigation: which project this window is, with its picture
      // and where it lives. The name is in the title bar as well; the path is nowhere else but the
      // overview's inspector.
      .safeAreaInset(edge: .top, spacing: 0) { SidebarProjectHeader(row: row) }
      .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
      .accessibilityLabel(L10n.t("projectLayout.navLabel"))
      .accessibilityIdentifier("sidebar")
    } detail: {
      // Above the page, not a safe-area inset over it: the band appears after the page has laid
      // out, and an inset then left the page's first row under it, showing through.
      VStack(spacing: 0) {
        CoexistenceBand(projectPath: row.path)
        page(current, ProjectContext(id: row.id, name: row.name, path: row.path))
          .id(pageID)
      }
    }
    // The place, not the project: its name is at the top of the sidebar (Apple: "Don't title
    // windows with your app name"). The tab is the page's subtitle (PageScaffold); the Window menu
    // still names the project (WindowMenuTitle).
    .navigationTitle(current.title)
    .toolbar { HistoryButtons(history: history, step: travel) }
    .focusedSceneValue(\.windowNavigation, WindowNavigation(
      backTitle: history.back.last.map(NavigationHistory.label),
      forwardTitle: history.forward.last.map(NavigationHistory.label),
      step: travel,
      open: { go(to: $0) },
      current: current))
    .focusedSceneValue(\.projectActions, ProjectActions(
      project: ProjectContext(id: row.id, name: row.name, path: row.path),
      state: BuildMonitor.shared.status(row.id).state))
    .environment(\.project, ProjectContext(id: row.id, name: row.name, path: row.path))
    .environment(\.openPage, OpenPageAction { follow(to: $0, tab: $1) })
    .environment(\.layoutHandOver, layoutHandOver)
    .environment(\.openLayout, OpenLayoutAction { target in
      layoutHandOver.target = target
      go(to: .layout) {
        let tab: LayoutModel.Tab = switch target {
        case .component: .global
        case .frame: .frames
        }
        history.send(.layout, tab: tab.rawValue)
      }
    })
    .environment(\.history, history)
    .environment(\.unsavedGuard, unsaved)
    .onChange(of: highlighted) { _, page in
      if let page { go(to: page) }
    }
    .onChange(of: pageID, initial: true) {
      highlighted = current
      history.notePage(current)
    }
    .background(UnsavedWindowHook(unsaved: unsaved))
    .background(WindowMenuTitle(title: "\(row.name) – \(history.current.map(NavigationHistory.label) ?? current.title)"))
  }

  /// Every page of the project, each a `PageScaffold` of its own.
  @ViewBuilder private func page(_ page: ProjectPage, _ project: ProjectContext) -> some View {
    switch page {
    case .overview: OverviewPage(project: project)
    case .config: ConfigPage(project: project)
    case .plugins: PluginsPage(project: project)
    case .server: BuildServerPage(project: project)
    case .sync: GitSyncPage(project: project)
    case .updates: UpdatesPage(project: project)
    case .backups: SnapshotsPage(project: project)
    case .styles: StylesPage(project: project)
    case .layout: LayoutPage(project: project)
    case .templates: TemplatesPage(project: project)
    case .publish: PublishPage(project: project)
    case .documents: DocumentsPage(project: project)
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

/// The project window's entry in the Window menu: the title bar names only the place, and two
/// project windows on the same page would read the same there.
struct WindowMenuTitle: NSViewRepresentable {
  let title: String

  func makeNSView(context: Context) -> NSView { TitleView() }

  func updateNSView(_ view: NSView, context: Context) {
    (view as? TitleView)?.title = title
  }

  final class TitleView: NSView {
    var title = "" { didSet { apply() } }
    private var observations: [NSKeyValueObservation] = []

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      observations = []
      guard let window else { return }
      // AppKit writes the menu entry again whenever SwiftUI sets the title or the subtitle, so it
      // is put back after each of them.
      observations = [
        // On the main thread: SwiftUI sets both there, and the entry has to be back before AppKit
        // draws the menu.
        window.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.apply() } },
        window.observe(\.subtitle) { [weak self] _, _ in MainActor.assumeIsolated { self?.apply() } },
      ]
      apply()
    }

    private func apply() {
      guard let window, !title.isEmpty else { return }
      DispatchQueue.main.async { [title] in NSApp.changeWindowsItem(window, title: title, filename: false) }
    }
  }
}

/// Moves the window to another page, for a link on a page (the overview's "Plugins ›"), on the
/// tab the link names if it names one.
struct OpenPageAction {
  let open: (ProjectPage, String?) -> Void
  func callAsFunction(_ page: ProjectPage, tab: String? = nil) { open(page, tab) }
}

extension EnvironmentValues {
  @Entry var openPage = OpenPageAction { _, _ in }
  @Entry var openLayout = OpenLayoutAction { _ in }
  @Entry var layoutHandOver: LayoutHandOver?
}

/// The Layout page's next place, until the page takes it.
@MainActor @Observable
final class LayoutHandOver {
  var target: OpenLayoutAction.Target?
}

/// Opens the Layout page on a component of the stage ("Auf der Bühne zeigen") or on an own frame
/// in the frame editor ("Im Layout-Editor").
struct OpenLayoutAction {
  enum Target {
    case component([PluginEntry], Int)
    case frame(String)
  }

  let open: (Target) -> Void
  func callAsFunction(_ target: Target) { open(target) }
}

/// The project at the top of the sidebar: picture, name, path (QuartzControl's `ProjectLayout`).
/// The path is cut in the middle, where a long one differs least, and is selectable in full.
struct SidebarProjectHeader: View {
  let row: ProjectOverview

  var body: some View {
    HStack(spacing: 10) {
      ProjectAvatar(row: row, size: 32)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.name).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
        Text(row.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
          .help(row.path)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("sidebar.project")
  }
}
