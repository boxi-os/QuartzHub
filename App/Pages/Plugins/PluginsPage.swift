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
  @State private var marketplace: MarketplaceModel
  /// Per window, by stable names (docs/conventions.md, „Wo war ich“).
  @SceneStorage("plugins.tab") private var tabID = Tab.installed.rawValue
  @SceneStorage("plugins.selected") private var selected: String?
  @SceneStorage("marketplace.selected") private var marketplaceSelected: String?
  /// The navigation by its #n among the navigations: instances have no name of their own.
  @SceneStorage("navigations.selected") private var navigationSelected: Int?
  /// The box by its #n among the boxes, as the plugin list keys a second instance.
  @SceneStorage("extraContent.selected") private var boxSelected: Int?
  @State private var styled: Set<String> = []

  init(project: ProjectContext) {
    self.project = project
    let plugins = PluginsModel(project: project)
    _model = State(initialValue: plugins)
    _marketplace = State(initialValue: MarketplaceModel(plugins: plugins))
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
        case .navigations:
          NavigationsTab(model: model, selection: $navigationSelected, styled: $styled)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page.plugins.navigations")
        case .extras:
          ExtraContentTab(model: model, selection: $boxSelected, styled: $styled)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page.plugins.extras")
        case .marketplace:
          MarketplaceTab(model: marketplace, selection: $marketplaceSelected)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page.plugins.marketplace")
            // Asked when the tab is first shown, not with the page: the catalog is a GitHub request.
            .task { if marketplace.result == nil { await marketplace.load() } }
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
        let path = project.path
        styled = Set((try? await Task.detached { try SiteFonts.takenClasses(project: path, prefixes: InstanceClass.prefixes) }.value) ?? [])
        await model.checkOutdated()
      }
    } inspector: {
      if tab == .installed, let selected, let item = model.items.first(where: { $0.id == selected }) {
        PluginInspector(item: item, model: model)
          .id(item.id)
      } else if tab == .navigations, let navigationSelected,
                let item = NavigationInstance.all(model.config?.plugins ?? []).first(where: { $0.occurrence == navigationSelected }) {
        let count = NavigationInstance.all(model.config?.plugins ?? []).count
        NavigationInspector(item: item, label: item.label(among: count), model: model) {
          // The plugin list knows the entry by its name and its number among the same-named.
          let same = (model.config?.plugins ?? []).prefix(item.index + 1).filter { $0.name == item.entry.name }.count
          selected = same == 1 ? item.entry.name : "\(item.entry.name)#\(same)"
          tabID = Tab.installed.rawValue
        }
        .id(item.occurrence)
      } else if tab == .extras, let boxSelected,
                let box = LayoutBoxes.boxes(model.config?.plugins ?? []).first(where: { $0.occurrence == boxSelected }) {
        let boxes = LayoutBoxes.boxes(model.config?.plugins ?? [])
        BoxInspector(box: box, label: BoxLabels.label(box, among: boxes), model: model) {
          // The plugin list knows the entry by its name and its number among the same-named.
          let same = (model.config?.plugins ?? []).prefix(box.index + 1).filter { $0.name == box.plugin.name }.count
          selected = same == 1 ? box.plugin.name : "\(box.plugin.name)#\(same)"
          tabID = Tab.installed.rawValue
        }
        .id(box.occurrence)
      } else if tab == .marketplace, let marketplaceSelected,
                let plugin = marketplace.result?.plugins.first(where: { $0.fullName == marketplaceSelected }) {
        MarketplaceInspector(plugin: plugin, model: marketplace)
          .id(plugin.fullName)
      } else {
        InspectorPageContext(page: .plugins) {
          Section {
            Text(tab.description).foregroundStyle(.secondary)
          }
          if tab == .installed, model.config != nil { summary }
          if tab == .marketplace { marketplaceSummary }
          if tab == .navigations {
            Section(L10n.t("navigationsEditor.panelEmptyTitle")) { Note(L10n.t("navigationsEditor.panelEmptyText")) }
          }
          if tab == .extras {
            Section(L10n.t("extraContent.panelEmptyTitle")) { Note(L10n.t("extraContent.panelEmptyText")) }
          }
        }
      }
    }
  }

  /// Nothing selected on the Marktplatz: how to start, and how many of the catalog's plugins this
  /// project has.
  private var marketplaceSummary: some View {
    Section(L10n.t("pluginsMarketplace.panelEmptyTitle")) {
      Note(L10n.t("pluginsMarketplace.panelEmptyText"))
      if let result = marketplace.result {
        let plugins = result.split(query: "").plugins
        Text(L10n.t("pluginsMarketplace.panelEmptyCount", ["count": String(plugins.count),
                                                          "installed": String(plugins.filter(marketplace.isInstalled).count)]))
          .foregroundStyle(.secondary)
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
