import QuartzHubCore
import SwiftUI

/// Konfiguration: QuartzControl's `ConfigEditor` with its two tabs. Website is what the site is:
/// where its notes come from, its picture, its own settings, what it leaves out, its statistics.
/// Übersetzungen are the fixed texts of the site. Colours and fonts are the Styles page's.
///
/// The page owns quartz.config.yaml (docs/conventions.md, „Eine Seite besitzt ihr Dokument“):
/// "Speichern" in the toolbar and ⌘S write it on the Website tab, and leaving with edits asks
/// (`UnsavedGuard`) from either tab. Übersetzungen save per locale from their own row.
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
      VStack(spacing: 0) {
        // Above the content, not in the toolbar: there it pushed the inspector button to the
        // middle of the window (seen in the running app).
        Picker(L10n.t("common.viewSwitcher"), selection: $tabID) {
          ForEach(Tab.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.top, 12)
        .accessibilityIdentifier("config.tabs")
        switch tab {
        case .site: siteForm
        case .localization:
          LocalizationTab(model: localization, configured: model.config == nil ? nil : model.string("locale"))
        }
      }
      .returnTab(page: .config, tab: $tabID)
      .task { await model.load() }
      .unsavedChanges(model.dirty, save: model.saving || model.config == nil ? nil : { await model.save() },
                      command: tab == .site)
      .toolbar {
        if tab == .site {
          ToolbarItemGroup(placement: .primaryAction) {
            if model.status == .saved {
              Text(L10n.t("common.saved")).foregroundStyle(.green)
            } else if model.dirty, !model.saving {
              UnsavedBadge().accessibilityIdentifier("config.unsaved")
            }
            Button {
              Task { await model.save() }
            } label: {
              Label(model.saving ? L10n.t("common.saving") : L10n.t("common.save"), systemImage: "square.and.arrow.down")
            }
            .labelStyle(.titleOnly)
            .disabled(model.saving || model.config == nil)
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
    Form {
      if model.status == .failed, let error = model.saveError {
        Section {
          Label(error, systemImage: "exclamationmark.octagon.fill")
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .accessibilityIdentifier("config.saveError")
        }
      }
      ContentFolderSection(project: project)
      if let error = model.loadError {
        Section {
          Text(L10n.t("configEditor.loadError")).fontWeight(.medium).foregroundStyle(.red)
          Text(error).font(.system(.callout, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
            .accessibilityIdentifier("config.loadError")
        }
      } else if model.config == nil {
        Section { Text(L10n.t("configEditor.loading")).foregroundStyle(.secondary) }
      } else {
        ProjectImageSection(model: model)
        SiteSettingsSections(model: model)
        Section {
          HStack(alignment: .firstTextBaseline) {
            Note(L10n.t("configEditor.stylesHint"))
            Button(L10n.t("configEditor.stylesHintLink")) { openPage(.styles) }.buttonStyle(.link).font(.callout)
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}
