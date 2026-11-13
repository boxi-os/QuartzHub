import QuartzHubCore
import SwiftUI

/// Konfiguration: QuartzControl's `ConfigEditor` with its two tabs. Website is what the site is:
/// where its notes come from, its picture, its own settings, what it leaves out, its statistics.
/// Übersetzungen are the fixed texts of the site. Colours and fonts are the Styles page's.
///
/// The page owns quartz.config.yaml (docs/conventions.md, „Eine Seite besitzt ihr Dokument“):
/// "Speichern" in the toolbar writes it on the Website tab. Übersetzungen save the open locale
/// with the button beside its picker. ⌘S, and the question on leaving with edits (`UnsavedGuard`),
/// cover both tabs at once.
struct ConfigPage: View {
  enum Tab: String, CaseIterable, Identifiable {
    case site, localization
    var id: String { rawValue }

    var title: String {
      switch self {
      case .site: L10n.t("configEditor.tabs.site")
      case .localization: L10n.t("configEditor.tabs.localization")
      }
    }

    var description: String {
      switch self {
      case .site: L10n.t("configEditor.descriptions.site")
      case .localization: L10n.t("configEditor.descriptions.localization")
      }
    }
  }

  let project: ProjectContext

  @State private var model: ConfigModel
  @State private var localization: LocalizationModel
  /// The tab per window, by its stable name (docs/conventions.md, „Wo war ich“).
  @SceneStorage("config.tab") private var tabID = Tab.site.rawValue
  @Environment(\.openPage) private var openPage

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: ConfigModel(project: project))
    _localization = State(initialValue: LocalizationModel.forProject(project))
  }

  private var tab: Tab { Tab(rawValue: tabID) ?? .site }

  var body: some View {
    PageScaffold(page: .config) {
      Group {
        switch tab {
        case .site: siteForm
        case .localization:
          LocalizationTab(model: localization, configured: model.config == nil ? nil : model.string("locale"))
        }
      }
      // Above the content, not in the toolbar: there it pushed the inspector button to the
      // middle of the window (seen in the running app).
      .pageTabs(Tab.allCases.map { PageTabs.Tab(id: $0.rawValue, title: $0.title) }, selection: $tabID, identifier: "config.tabs")
      .historyTab(page: .config, tab: $tabID)
      .task { await model.load() }
      // Both tabs in one registration (the guard keeps one per window): the translations survive a
      // trip to another page in memory, but quitting, closing the window or leaving with
      // "Verwerfen" lost them without a question (review 2026-11-13, handbook, M1). Speichern
      // saves what is unsaved in either; ⌘S too, on both tabs.
      .unsavedChanges(model.dirty || localization.dirty,
                      canSave: !model.saving && !localization.saving && (!model.dirty || model.config != nil),
                      discard: { localization.discardEdits() }) {
        if model.dirty, await !model.save() { return false }
        if localization.dirty { return await localization.saveAll() }
        return true
      }
      .toolbar {
        if tab == .site {
          // No "Gespeichert" and no badge beside it: Speichern is enabled only with something to
          // save, and the dot in the close button says the same (decisions/ui-ueberarbeitung.md).
          ToolbarItem(placement: .primaryAction) {
            Button {
              Task { await model.save() }
            } label: {
              Label(model.saving ? L10n.t("common.saving") : L10n.t("common.save"), systemImage: "square.and.arrow.down")
            }
            .labelStyle(.titleOnly)
            .disabled(!model.dirty || model.saving || model.config == nil)
            .accessibilityIdentifier("config.save")
          }
        }
      }
    } inspector: {
      InspectorPageContext(page: .config) {
        Section {
          Text(tab.description).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var siteForm: some View {
    SettingsForm {
      if model.status == .failed, let error = model.saveError {
        Callout(.error) {
          Text(error).textSelection(.enabled).accessibilityIdentifier("config.saveError")
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.s)
      }
      if let error = model.loadError {
        Callout(.error) {
          Text(L10n.t("configEditor.loadError")).fontWeight(.medium)
          Text(error).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            .accessibilityIdentifier("config.loadError")
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.s)
      }
      ContentFolderSection(project: project)
      if model.loadError == nil, model.config == nil {
        ProgressView(L10n.t("configEditor.loading")).frame(maxWidth: .infinity).padding(Spacing.xl)
      } else if model.config != nil {
        ProjectImageSection(model: model)
        SiteSettingsSections(model: model)
        ProcessingSections(model: model, project: project)
        HStack(alignment: .firstTextBaseline) {
          Note(L10n.t("configEditor.stylesHint"))
          Button(L10n.t("configEditor.stylesHintLink")) { openPage(.styles) }.buttonStyle(.link).font(.callout)
        }
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, Spacing.m)
      }
    }
  }
}
