import QuartzHubCore

/// The pages of a project, in the sidebar's order: the groups of QuartzControl's
/// `ProjectLayout.tsx` (`NAV_GROUPS`), one page per task (docs/conventions.md, „Sidebar nach
/// Tätigkeit“). The raw value is the stable identifier for `@SceneStorage` and UI tests, never an
/// index.
enum ProjectPage: String, CaseIterable, Identifiable {
  case overview, config, plugins, layout, styles, templates, server, sync, documents, publish, updates, backups

  var id: String { rawValue }

  enum Group: String, CaseIterable {
    case top, setup, design, publish, maintenance

    var pages: [ProjectPage] { ProjectPage.allCases.filter { $0.group == self } }

    /// nil for the top group, which has no heading (only the overview).
    var title: String? {
      switch self {
      case .top: nil
      case .setup: L10n.t("projectLayout.groups.setup")
      case .design: L10n.t("projectLayout.groups.design")
      case .publish: L10n.t("projectLayout.groups.publish")
      case .maintenance: L10n.t("projectLayout.groups.maintenance")
      }
    }
  }

  var group: Group {
    switch self {
    case .overview: .top
    case .config, .plugins: .setup
    case .layout, .styles, .templates: .design
    case .server, .sync, .documents, .publish: .publish
    case .updates, .backups: .maintenance
    }
  }

  // Literal keys on purpose: qh-check i18n can only check what it can read.
  var title: String {
    switch self {
    case .overview: L10n.t("projectLayout.tabs.overview")
    case .config: L10n.t("projectLayout.tabs.config")
    case .plugins: L10n.t("projectLayout.tabs.plugins")
    case .layout: L10n.t("projectLayout.tabs.layout")
    case .styles: L10n.t("projectLayout.tabs.styles")
    case .templates: L10n.t("projectLayout.tabs.templates")
    case .server: L10n.t("projectLayout.tabs.server")
    case .sync: L10n.t("projectLayout.tabs.sync")
    case .documents: L10n.t("projectLayout.tabs.documents")
    case .publish: L10n.t("projectLayout.tabs.publish")
    case .updates: L10n.t("projectLayout.tabs.updates")
    case .backups: L10n.t("projectLayout.tabs.backups")
    }
  }

  /// SF Symbols in place of QuartzControl's Lucide icons (`navConfig.ts`, `TAB_ICONS`).
  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .config: "slider.horizontal.3"
    case .plugins: "puzzlepiece.extension"
    case .layout: "rectangle.split.3x1"
    case .styles: "paintbrush"
    case .templates: "shippingbox"
    case .server: "server.rack"
    case .sync: "arrow.triangle.branch"
    case .documents: "book.closed"
    case .publish: "icloud.and.arrow.up"
    case .updates: "arrow.triangle.2.circlepath"
    case .backups: "archivebox"
    }
  }
}
