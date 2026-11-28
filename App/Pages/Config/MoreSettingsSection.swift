import QuartzHubCore
import SwiftUI

/// „Weitere Einstellungen“: what the project's Quartz describes under `configuration` and no
/// section above edits, from Quartz's own schema (`QuartzConfigSchema`), with the plugins' options
/// form. A setting a Quartz release adds shows here without a QuartzHub release; the descriptions
/// are Quartz's, in English. Keys nobody describes stand under "Unbekannte Schlüssel" so they are
/// seen, not lost. Not there without the schema file or with nothing to show.
struct MoreSettingsSection: View {
  @Bindable var model: ConfigModel

  var body: some View {
    let values = model.moreValues
    if let schema = model.moreSettings, !schema.fields.isEmpty || !values.isEmpty || !schema.notes.isEmpty {
      SettingsSection(L10n.t("configEditor.more.heading"), symbol: "slider.horizontal.3", note: L10n.t("configEditor.more.note"),
                      identifier: "config.more") {
        OptionsForm(schema: schema, values: values, onChange: { model.setMore($0) }, freeKeys: false, projectPath: model.project.path)
      }
    }
  }
}
