import QuartzHubCore
import SwiftUI

/// Plugins: QuartzControl's `routes/Plugins` with its six tabs. Finding a plugin and configuring
/// it is one job, so it is one page; updating is maintenance and lives on Updates.
///
/// The editors for this project's own plugins (navigations, extras, languages, forms) sit between
/// the list and the marketplace: they are a closer look at entries of the list.
struct PluginsPage: View {
  enum Tab: String, CaseIterable, Identifiable {
    case installed, navigations, extras, languages, forms, marketplace
    var id: String { rawValue }

    var title: String {
      switch self {
      case .installed: L10n.t("plugins.tabs.installed")
      case .navigations: L10n.t("plugins.tabs.navigations")
      case .extras: L10n.t("plugins.tabs.extras")
      case .languages: L10n.t("plugins.tabs.languages")
      case .forms: L10n.t("plugins.tabs.forms")
      case .marketplace: L10n.t("plugins.tabs.marketplace")
      }
    }

    var description: String {
      switch self {
      case .installed: L10n.t("plugins.descriptions.installed")
      case .navigations: L10n.t("plugins.descriptions.navigations")
      case .extras: L10n.t("plugins.descriptions.extras")
      case .languages: L10n.t("plugins.descriptions.languages")
      case .forms: L10n.t("plugins.descriptions.forms")
      case .marketplace: L10n.t("plugins.descriptions.marketplace")
      }
    }
  }

  let project: ProjectContext

  @State private var model: PluginsModel
  /// Per window, by stable names (docs/conventions.md, „Wo war ich“).
  @SceneStorage("plugins.tab") private var tabID = Tab.installed.rawValue
  @SceneStorage("plugins.selected") private var selected: String?

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: PluginsModel(project: project))
  }

  private var tab: Tab { Tab(rawValue: tabID) ?? .installed }

  private var tabPicker: some View {
    Picker(L10n.t("common.viewSwitcher"), selection: $tabID) {
      ForEach(Tab.allCases) { Text($0.title).tag($0.rawValue) }
    }
    .labelsHidden()
    .accessibilityIdentifier("plugins.tabs")
  }

  var body: some View {
    PageScaffold(page: .plugins) {
      VStack(spacing: 0) {
        // Six tabs are wider than the middle column of the smallest window: there they become a
        // menu, or the window was pushed wider than the screen (measured with the UI test at 900 pt).
        ViewThatFits(in: .horizontal) {
          tabPicker.pickerStyle(.segmented).fixedSize()
          tabPicker.pickerStyle(.menu).fixedSize()
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        switch tab {
        case .installed:
          InstalledTab(model: model, selection: $selected)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page.plugins")
        default:
          ContentUnavailableView {
            Label(tab.title, systemImage: ProjectPage.plugins.symbol)
          } description: {
            Text(L10n.t("shell.page.pending"))
          }
        }
      }
      .task {
        await model.load()
        await model.checkOutdated()
      }
    } inspector: {
      if tab == .installed, let selected, let item = model.items.first(where: { $0.id == selected }) {
        PluginInspector(item: item, model: model)
          .id(item.id)
      } else {
        InspectorPageContext(page: .plugins) {
          Section {
            Text(tab.description).foregroundStyle(.secondary)
          }
          if tab == .installed, model.config != nil { summary }
        }
      }
    }
  }

  /// Nothing selected: what the list holds, in numbers.
  private var summary: some View {
    let items = model.items
    let groups = InstalledTab.groups(items)
    let components = groups.components.reduce(0) { $0 + $1.items.count }
    let processing = groups.pageTypes.items.count + groups.processing.items.count
    let active = items.filter(\.enabled).count
    return Section(L10n.t("pluginsInstalled.panelEmptyTitle")) {
      Note(L10n.t("pluginsInstalled.panelEmptyText"))
      LabeledContent(L10n.t("pluginsInstalled.summaryActive"),
                     value: L10n.t("pluginsInstalled.summaryOf", ["count": String(active), "total": String(items.count)]))
      LabeledContent(L10n.t("pluginsInstalled.componentsHeading"), value: String(components))
      LabeledContent(L10n.t("pluginsInstalled.processingHeading"), value: String(processing))
      if !groups.frames.isEmpty {
        LabeledContent(L10n.t("pluginsInstalled.framesHeading"), value: String(groups.frames.count))
      }
      if !model.outdated.isEmpty {
        LabeledContent(L10n.t("pluginsInstalled.updateAvailable"), value: String(model.outdated.count))
      }
    }
  }
}
