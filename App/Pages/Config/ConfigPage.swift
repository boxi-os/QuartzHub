import QuartzHubCore
import SwiftUI

/// Konfiguration: QuartzControl's `ConfigEditor` as one grouped form. What the site is: where its
/// notes come from, its picture, its own settings, what it leaves out, its statistics. Colours and
/// fonts are the Styles page's.
///
/// The page owns quartz.config.yaml (docs/conventions.md, „Eine Seite besitzt ihr Dokument“):
/// "Speichern" in the toolbar and ⌘S write it, and leaving with edits asks (`UnsavedGuard`).
struct ConfigPage: View {
  let project: ProjectContext

  @State private var model: ConfigModel
  @Environment(\.openPage) private var openPage

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: ConfigModel(project: project))
  }

  var body: some View {
    PageScaffold(page: .config) {
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
      .task { await model.load() }
      .unsavedChanges(model.dirty, save: model.saving || model.config == nil ? nil : { await model.save() })
      .toolbar {
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
    } inspector: {
      InspectorPageContext(page: .config) {
        Section {
          Text(L10n.t("configEditor.descriptions.site")).foregroundStyle(.secondary)
        }
      }
    }
  }
}
