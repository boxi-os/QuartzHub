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
  /// `lang:<code>` or `section:<id>`.
  @SceneStorage("multilanguage.selected") private var languageSelected: String?
  /// `form:<id>` or `section:<id>`.
  @SceneStorage("forms.selected") private var formSelected: String?
  @State private var forms = FormsState()
  /// quartz-multilanguage's schema: its groups are the rows of the tab and the panels of the inspector.
  @State private var multilanguageSchema: PluginOptionSchemaResult?
  @State private var styled: Set<String> = []
  @Environment(\.returnLink) private var returnLink

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
        case .languages:
          MultilanguageTab(model: model, selection: $languageSelected, schema: $multilanguageSchema) {
            if let entry = MultilanguageOptions.entries(model.config?.plugins ?? []).first { showAllOptions(entry.plugin, index: entry.index) }
          }
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("page.plugins.languages")
          .task(id: MultilanguageOptions.entries(model.config?.plugins ?? []).first?.plugin.source.map(JSJSON.compact) ?? "") {
            guard let source = PluginSource(MultilanguageOptions.entries(model.config?.plugins ?? []).first?.plugin.source) else {
              multilanguageSchema = nil
              return
            }
            let environment = await AppServices.current()
            multilanguageSchema = await PluginSchemaReader.shared.optionSchema(project: project.path, source: source, runtime: environment.runtime)
          }
        case .forms:
          FormsTab(model: model, state: forms, selection: $formSelected) {
            if let entry = FormsOptions.entries(model.config?.plugins ?? []).first { showAllOptions(entry.plugin, index: entry.index) }
          }
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("page.plugins.forms")
        case .marketplace:
          MarketplaceTab(model: marketplace, selection: $marketplaceSelected)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page.plugins.marketplace")
            // Asked when the tab is first shown, not with the page: the catalog is a GitHub request.
            .task { if marketplace.result == nil { await marketplace.load() } }
        }
      }
      .returnTab(page: .plugins, tab: $tabID)
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
          showAllOptions(item.entry, index: item.index)
        }
        .id(item.occurrence)
      } else if tab == .extras, let boxSelected,
                let box = LayoutBoxes.boxes(model.config?.plugins ?? []).first(where: { $0.occurrence == boxSelected }) {
        let boxes = LayoutBoxes.boxes(model.config?.plugins ?? [])
        BoxInspector(box: box, label: BoxLabels.label(box, among: boxes), model: model) {
          showAllOptions(box.plugin, index: box.index)
        }
        .id(box.occurrence)
      } else if tab == .languages, let entry = MultilanguageOptions.entries(model.config?.plugins ?? []).first,
                let languageSelected {
        let view = MultilanguageView(entry: entry, schema: multilanguageSchema?.schema)
        if languageSelected.hasPrefix("lang:"), let language = view.languages.first(where: { "lang:\($0.code)" == languageSelected }) {
          LanguageInspector(language: language, view: view, model: model, selection: $languageSelected)
            .id(languageSelected)
        } else if languageSelected.hasPrefix("section:"), let group = view.groups.first(where: { "section:\($0.id)" == languageSelected }) {
          SettingsGroupInspector(group: group, view: view, model: model)
            .id(languageSelected)
        } else {
          InspectorPageContext(page: .plugins) { MultilanguageOverview(view: view) }
        }
      } else if tab == .forms, let entry = FormsOptions.entries(model.config?.plugins ?? []).first, let formSelected {
        let view = FormsView(entry: entry, state: forms)
        if formSelected.hasPrefix("form:"), let form = view.forms.first(where: { "form:\($0.id)" == formSelected }) {
          FormInspector(id: form.id, def: form.def, view: view, model: model, state: forms, selection: $formSelected)
            .id(formSelected)
        } else if formSelected.hasPrefix("section:"), let section = view.sections.first(where: { "section:\($0.id)" == formSelected }) {
          FormsSectionInspector(id: section.id, view: view, model: model, state: forms, selection: $formSelected)
            .id(formSelected)
        } else {
          InspectorPageContext(page: .plugins) { FormsOverview() }
        }
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
          if tab == .languages, let entry = MultilanguageOptions.entries(model.config?.plugins ?? []).first {
            MultilanguageOverview(view: MultilanguageView(entry: entry, schema: multilanguageSchema?.schema))
          }
          if tab == .forms { FormsOverview() }
        }
      }
    }
  }

  /// „Alle Optionen in der Plugin-Liste“, from all four editors: the plugin list knows the entry by
  /// its name and its number among the same-named. The way back leads to the editor.
  private func showAllOptions(_ plugin: PluginEntry, index: Int) {
    let same = (model.config?.plugins ?? []).prefix(index + 1).filter { $0.name == plugin.name }.count
    selected = same == 1 ? plugin.name : "\(plugin.name)#\(same)"
    returnLink?.markTab(.plugins, to: Tab.installed.rawValue)
    tabID = Tab.installed.rawValue
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
