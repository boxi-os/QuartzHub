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
  @Environment(\.unsavedGuard) private var unsaved

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: StylesModel(project: project))
  }

  private var tab: StylesModel.Tab { StylesModel.Tab(rawValue: tabID) ?? .basics }

  private var tabPicker: some View {
    Picker(L10n.t("common.viewSwitcher"), selection: $tabID) {
      ForEach(StylesModel.Tab.allCases) { Text($0.title).tag($0.rawValue) }
    }
    .labelsHidden()
    .accessibilityIdentifier("styles.tabs")
  }

  var body: some View {
    PageScaffold(page: .styles) {
      VStack(spacing: 0) {
        // Four tabs are wider than the middle column of the smallest window with the inspector:
        // there they become a menu, or the window grows past its frame (seen at 1000 × 700).
        ViewThatFits(in: .horizontal) {
          tabPicker.pickerStyle(.segmented).fixedSize()
          tabPicker.pickerStyle(.menu).fixedSize()
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        content
      }
      .task {
        await model.load()
      }
      .task(id: model.config == nil ? nil : FontDelivery.activeThemeId(model.config!) ?? "") {
        // Once read, and again for a different theme: that is a different variable table.
        if model.config != nil { await model.reloadGraph() }
      }
      .unsavedChanges(model.dirty, save: model.saving || model.config == nil ? nil : { [model, tab] in await model.save(from: tab) })
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          if model.status == .saved {
            Text(L10n.t("common.saved")).foregroundStyle(.green)
          } else if model.dirty, !model.saving {
            UnsavedBadge().accessibilityIdentifier("styles.unsaved")
          }
          Button {
            Task { await save() }
          } label: {
            Label(model.saving ? L10n.t("common.saving") : L10n.t("common.save"), systemImage: "square.and.arrow.down")
          }
          .labelStyle(.titleOnly)
          .disabled(model.saving || model.config == nil)
          .accessibilityIdentifier("styles.save")
        }
      }
    } inspector: {
      if tab == .theme, let themeSelected, let config = model.config {
        let active = config.plugins.first(where: FontDelivery.isThemePlugin).flatMap { FontDelivery.enabled($0) ? $0.object["options"]?["theme"]?.stringValue : nil }
        ThemeInspector(id: themeSelected, listing: themeCatalog?.themes.first { $0.id == themeSelected }, model: model,
                       active: active == themeSelected) { id in activateTheme(id) }
          .id(themeSelected)
      } else {
        pageContext
      }
    }
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
      }
    }
  }

  private func save() async -> Bool {
    let saved = await model.save(from: tab)
    savedRound += 1
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
        case .variables, .customCss:
          ContentUnavailableView {
            Label(tab.title, systemImage: ProjectPage.styles.symbol)
          } description: {
            Text(L10n.t("shell.page.pending"))
          }
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
