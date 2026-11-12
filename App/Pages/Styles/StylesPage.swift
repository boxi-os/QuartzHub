import QuartzHubCore
import SwiftUI

/// Stile: everything that changes how the site looks, on one page, in the order of the CSS cascade
/// (QuartzControl's `routes/Styles`): Basis, Community-Themes, Variablen, Eigenes CSS, each
/// overriding the one before. One model for all four, one "Speichern" for the page.
struct StylesPage: View {
  let project: ProjectContext

  @State private var model: StylesModel
  /// The tab per window, by its stable name (docs/conventions.md, „Wo war ich“).
  @SceneStorage("styles.tab") private var tabID = StylesModel.Tab.basics.rawValue
  @State private var migrating = false
  @State private var migrateError: String?
  /// Bumped after every save, for what a tab reads again then.
  @State private var savedRound = 0
  @SceneStorage("styles.theme.selected") private var themeSelected: String?
  @SceneStorage("styles.themeCatalog.query") private var themeQuery = ""
  @State private var themeCatalog: ThemeMarketplace.Catalog?
  @SceneStorage("styles.vars.selected") private var varSelected: String?
  @SceneStorage("styles.vars.openGroups") private var varOpenGroups = "baseColors"
  @SceneStorage("styles.allVars.open") private var varAllOpen = false
  @SceneStorage("styles.allVars.query") private var varQuery = ""
  @SceneStorage("styles.allVars.onlyChanged") private var varOnlyChanged = false
  @SceneStorage("styles.allVars.kind") private var varKind = "all"
  @SceneStorage("styles.allVars.openGroups") private var varOpenBrowseGroups = ""
  @SceneStorage("styles.vars.darkOpen") private var varDarkOpen = ""
  @State private var varScroll: String?
  @SceneStorage("styles.css.openTabs") private var cssOpenTabs = CssTab.mainTab
  @SceneStorage("styles.css.activeTab") private var cssActiveTab = CssTab.mainTab
  @State private var cssCheck: ScssCheck.Result?
  @State private var cssChecking = false
  @State private var cssInsertion: CodeInsertion?
  @State private var cssComponent = ""
  @State private var cssReferences: [StyleFiles.Reference] = []
  @Environment(\.unsavedGuard) private var unsaved

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: StylesModel(project: project))
  }

  private var tab: StylesModel.Tab { StylesModel.Tab(rawValue: tabID) ?? .basics }

  var body: some View {
    PageScaffold(page: .styles) {
      content
      // Four tabs are wider than the middle column of the smallest window with the inspector:
      // PageTabs makes them a menu there, or the window grows past its frame (seen at 1000 × 700).
      .pageTabs(StylesModel.Tab.allCases.map { PageTabs.Tab(id: $0.rawValue, title: $0.title) }, selection: $tabID, identifier: "styles.tabs")
      .historyTab(page: .styles, tab: $tabID)
      .task {
        await model.load()
      }
      .task(id: model.config == nil ? nil : FontDelivery.activeThemeId(model.config!) ?? "") {
        // Once read, and again for a different theme: that is a different variable table.
        if model.config != nil { await model.reloadGraph() }
      }
      .unsavedChanges(model.dirty, save: model.saving || model.config == nil ? nil : { [model, tab] in await model.save(from: tab) })
      .toolbar {
        // Speichern only with something to save, no badge beside it (as on Konfiguration).
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await save() }
          } label: {
            Label(model.saving ? L10n.t("common.saving") : L10n.t("common.save"), systemImage: "square.and.arrow.down")
          }
          .labelStyle(.titleOnly)
          .disabled(!model.dirty || model.saving || model.config == nil)
          .accessibilityIdentifier("styles.save")
        }
      }
    } inspector: {
      if tab == .theme, let themeSelected, let config = model.config {
        let active = config.plugins.first(where: FontDelivery.isThemePlugin).flatMap { FontDelivery.enabled($0) ? $0.object["options"]?["theme"]?.stringValue : nil }
        ThemeInspector(id: themeSelected, listing: themeCatalog?.themes.first { $0.id == themeSelected }, model: model,
                       active: active == themeSelected) { id in activateTheme(id) }
          .id(themeSelected)
      } else if tab == .customCss, model.config != nil {
        CssFilesInspector(model: model, activeTab: cssActiveTab, open: openCssTab, afterFileOp: afterCssFileOp, applyOrder: applyCssOrder,
                          extra: AnyView(Group {
                            PluginReferences(references: cssReferences)
                            CssVariableReference(model: model, insert: { cssInsertion = CodeInsertion(text: $0) }, goToVariables: { tabID = StylesModel.Tab.variables.rawValue })
                            ActiveStylesSection(model: model)
                          }))
      } else if tab == .variables, let varSelected, model.config != nil {
        VariableInspector(key: varSelected, model: model, darkOpen: VariablesPlace.lines(varDarkOpen).contains(varSelected),
                          setDarkOpen: { open in
                            let has = VariablesPlace.lines(varDarkOpen).contains(varSelected)
                            if open != has { varDarkOpen = VariablesPlace.toggled(varDarkOpen, varSelected) }
                          }, navigate: navigateToVariable)
          .id(varSelected)
      } else {
        pageContext
      }
    }
  }

  // MARK: Eigenes CSS

  /// The whole chain with the project's own Sass.
  private func runCssCheck() async {
    cssChecking = true
    let environment = await AppServices.current()
    cssCheck = await ScssCheck.check(project: project.path, runtime: environment.runtime)
    cssChecking = false
  }

  /// The picked component's plugin's own stylesheets, read only.
  private func loadCssReferences() async {
    let plugin = ComponentSelectors.list(model.config?.plugins ?? []).first { $0.selector == cssComponent }?.plugin ?? ""
    guard !plugin.isEmpty else { cssReferences = []; return }
    let path = project.path
    cssReferences = (try? await Task.detached { try StyleFiles.references(plugin: plugin, project: path) }.value) ?? []
  }

  private func openCssTab(_ tab: String) {
    cssOpenTabs = VariablesPlace.adding(cssOpenTabs, tab)
    cssActiveTab = tab
  }

  /// Every file operation rewrites the load order in custom.scss: its draft is read again (kept and
  /// flagged when it has edits), and the check runs.
  private func afterCssFileOp() async {
    await model.reloadFiles()
    await model.reloadScss(after: .stylesheets)
    await runCssCheck()
  }

  private func applyCssOrder(_ next: [String]) async {
    do {
      try await StyleSheets.setImportOrder(next, project: project.path)
      await afterCssFileOp()
    } catch {
      Announce.post(StylesModel.message(error))
    }
  }

  private var variablesPlace: VariablesPlace {
    VariablesPlace(selected: $varSelected, openGroups: $varOpenGroups, allOpen: $varAllOpen, query: $varQuery, onlyChanged: $varOnlyChanged,
                   kind: $varKind, openBrowseGroups: $varOpenBrowseGroups, darkOpen: $varDarkOpen)
  }

  /// A chip in the inspector jumps to a variable: select it, open its group, put its name in the
  /// search, and scroll to its row.
  private func navigateToVariable(_ key: String) {
    varSelected = key
    if let def = CssVariables.definition(key) { varOpenGroups = VariablesPlace.adding(varOpenGroups, def.group) }
    varAllOpen = true
    varQuery = key
    varScroll = key
  }

  /// The catalog's "install" from the inspector: the same as the tab's.
  private func activateTheme(_ id: String) {
    guard var config = model.config else { return }
    let index = config.plugins.firstIndex(where: FontDelivery.isThemePlugin)
    var base = index.map { config.plugins[$0] } ?? PluginEntry(object: JSONObject([("name", .string(id)), ("source", .string("@quartz-themes/core")),
                                                                                   ("enabled", .bool(true)), ("options", .object(JSONObject([("mode", .string("both"))])))]))
    var options = base.object["options"]?.objectValue ?? JSONObject()
    options["theme"] = .string(id)
    base.object["enabled"] = .bool(true)
    base.object["options"] = .object(options)
    if let index { config.plugins[index] = base } else { config.plugins.append(base) }
    model.setConfig(config)
  }

  private var pageContext: some View {
    InspectorPageContext(page: .styles) {
      if model.config != nil {
        Section { Text(cascadeLine).foregroundStyle(.secondary) }
        if tab == .variables { variablesSummary }
      }
    }
  }

  /// The Variablen tab with nothing selected: what there is, and the user's own changes to jump to.
  @ViewBuilder private var variablesSummary: some View {
    let curated = Set(CssVariables.all.map(\.key))
    let extra = VariableResolve.allKnownKeys(model.context).filter { !curated.contains($0) }.count
    let changed = model.overrides.map(\.key).sorted()
    Section(L10n.t("styles.variables.panelEmptyTitle")) {
      Note(L10n.t("styles.variables.panelEmptyText"))
      LabeledContent(L10n.t("styles.variables.summaryMain"), value: String(CssVariables.all.count))
      LabeledContent(L10n.t("styles.variables.summaryAll"), value: String(extra))
      LabeledContent(L10n.t("styles.variables.summaryChanged"), value: String(changed.count))
      ForEach(changed.prefix(24), id: \.self) { key in
        Button("--\(key)") { navigateToVariable(key) }.buttonStyle(.link).font(.system(.callout, design: .monospaced))
      }
      if changed.count > 24 { Note(L10n.t("styles.variables.moreKeys", count: changed.count - 24)) }
    }
  }

  private func save() async -> Bool {
    let saved = await model.save(from: tab)
    savedRound += 1
    if tab == .customCss { await runCssCheck() }
    return saved
  }

  /// "Reihenfolge: Basis → …", and how many variables are overridden.
  private var cascadeLine: String {
    guard let config = model.config else { return "" }
    var line = FontDelivery.activeThemeId(config).map { L10n.t("styles.cascade.themeActive", ["themeId": $0]) } ?? L10n.t("styles.cascade.themeInactive")
    if !model.overrides.isEmpty { line += " " + L10n.t("styles.cascade.overrides", count: model.overrides.count) }
    return line
  }

  @ViewBuilder private var content: some View {
    if let error = model.loadError {
      Form {
        Section {
          Text(L10n.t("styles.loadFailed")).fontWeight(.medium).foregroundStyle(.red)
          Text(error).font(.system(.callout, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
        }
      }
      .formStyle(.grouped)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.styles")
    } else if model.config == nil {
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("page.styles")
    } else {
      VStack(spacing: 0) {
        switch tab {
        case .basics:
          BasicsTab(model: model, goTo: { tabID = $0.rawValue }, savedRound: savedRound, notes: AnyView(notes)) { _ = await save() }
        case .theme:
          ThemeTab(model: model, notes: AnyView(notes), goTo: { tabID = $0.rawValue }, selection: $themeSelected, query: $themeQuery,
                   catalog: $themeCatalog)
        case .variables:
          VariablesTab(model: model, notes: AnyView(notes), place: variablesPlace, scrollTarget: $varScroll)
        case .customCss:
          CssTab(model: model, notes: AnyView(notes), openTabs: $cssOpenTabs, activeTab: $cssActiveTab, check: $cssCheck, checking: $cssChecking,
                 runCheck: runCssCheck, insertion: $cssInsertion, component: $cssComponent)
            .task(id: cssComponent) { await loadCssReferences() }
            // Checked on arrival too: an error made outside the app is worth seeing before the next edit.
            .task { await runCssCheck() }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.styles")
    }
  }

  /// The save's sentences and the move to `_quartzcontrol.scss`, the first sections of every tab's
  /// form: they are about the page, not about the tab in front.
  @ViewBuilder private var notes: some View {
    let failed = model.status == .failed ? model.message : nil
    if failed != nil || model.fontNote != nil {
      Section {
        if let failed {
          Label(failed, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
            .accessibilityIdentifier("styles.saveError")
        }
        if let note = model.fontNote {
          Text(note).foregroundStyle(.secondary).textSelection(.enabled).accessibilityIdentifier("styles.note")
        }
      }
    }
    if model.scss?.info.moved == false { moveNote }
  }

  /// A project in 1.0's form keeps working, so this asks rather than does: a moved project is one an
  /// older QuartzControl reads without variables and stylesheets.
  private var moveNote: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.t("styles.migrate.note"))
        HStack {
          Button(migrating ? L10n.t("styles.migrate.running") : L10n.t("styles.migrate.action")) {
            Task {
              migrating = true
              migrateError = nil
              do { try await model.migrate() } catch { migrateError = StylesModel.message(error) }
              migrating = false
            }
          }
          .disabled(migrating || model.dirty)
          .accessibilityIdentifier("styles.migrate")
          if model.dirty { Text(L10n.t("styles.migrate.saveFirst")).foregroundStyle(.secondary) }
        }
        if let migrateError { Text(migrateError).foregroundStyle(.red).textSelection(.enabled) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
