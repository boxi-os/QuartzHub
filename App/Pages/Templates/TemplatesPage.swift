import QuartzHubCore
import SwiftUI

/// Vorlagen: QuartzControl's `Templates.tsx` as a settings form (variant C), writing a template
/// first and applying one after. Both halves are in the middle, under each other, as there; the inspector
/// keeps the page's context, since nothing on the page is a selection.
struct TemplatesPage: View {
  let project: ProjectContext

  @State private var model: TemplatesModel
  @Environment(\.unsavedGuard) private var unsaved

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: TemplatesModel.shared(project))
  }

  var body: some View {
    PageScaffold(page: .templates) {
      SettingsForm {
        exportSections
        importSections
      }
      .task { await model.appear() }
    } inspector: {
      InspectorPageContext(page: .templates) {
        Section {
          Text(L10n.t("templates.description")).foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: Writing a template

  @ViewBuilder private var exportSections: some View {
    SettingsSection(L10n.t("templates.exportHeading"), symbol: "shippingbox", note: L10n.t("templates.exportHint"),
                    identifier: "page.templates") {
      TextField(L10n.t("templates.nameLabel"), text: $model.name)
        .accessibilityIdentifier("templates.name")
      TextField(L10n.t("templates.descriptionLabel"), text: $model.description, prompt: Text(L10n.t("templates.descriptionPlaceholder")))
    }

    // The parts and what writes them, in one group: a section without a heading has no place in
    // the heading column.
    SettingsSection(L10n.t("templates.partsHeading")) {
      if let available = model.available {
        if available.isEmpty {
          Note(L10n.t("templates.nothingToExport"))
        } else {
          ForEach(TemplatesModel.sortedForDisplay(available, id: \.id), id: \.id) { part in
            exportRow(part)
          }
        }
      } else {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Note(L10n.t("common.loading"))
        }
      }
      HStack(spacing: 12) {
        Button(model.exporting ? L10n.t("templates.exporting") : L10n.t("templates.exportButton")) {
          Task { await model.export(window: unsaved?.window) }
        }
        .disabled(!model.canExport)
        .accessibilityIdentifier("templates.export")
        if let available = model.available {
          Text(L10n.t("templates.selectedCount", ["total": String(available.count)], count: (model.exportSelected ?? []).count))
            .font(.callout).foregroundStyle(.secondary)
        }
      }
      if let result = model.exportResult {
        Text(result.text).font(.callout).foregroundStyle(result.ok ? .green : .red).textSelection(.enabled)
          .accessibilityIdentifier("templates.exportResult")
      }
      if let translations = model.available?.first(where: { $0.id == "translations" }),
         case let undetermined = Int(translations.stats["undetermined"]?.numberValue ?? 0), undetermined > 0,
         (model.exportSelected ?? []).contains("translations") {
        Note(L10n.t("templates.baselineHint", count: undetermined))
      }
    }
  }

  private func exportRow(_ part: TemplatePackage.Summary) -> some View {
    let checked = (model.exportSelected ?? []).contains(part.id)
    return PartRow(id: part.id, checked: checked, disabled: model.exporting, summary: TemplateWords.exportSummary(part, scope: model.scope),
                   identifier: "templates.export.\(part.id)") {
      model.toggleExport(part.id)
    } extra: {
      if part.id == "translations", checked {
        Picker(L10n.t("templates.scopeLabel"), selection: $model.scope) {
          Text(L10n.t("templates.scopeChanged", count: Int(part.stats["entries"]?.numberValue ?? 0))).tag(TemplatePackage.TranslationScope.changed)
          Text(L10n.t("templates.scopeAll", count: Int(part.stats["allEntries"]?.numberValue ?? 0))).tag(TemplatePackage.TranslationScope.all)
        }
        .pickerStyle(.segmented)
        .fixedSize()
      }
    }
  }

  // MARK: Applying a template

  @ViewBuilder private var importSections: some View {
    SettingsSection(L10n.t("templates.importHeading"), symbol: "square.and.arrow.down.on.square", note: L10n.t("templates.importHint")) {
      HStack(spacing: 8) {
        Button(L10n.t("templates.pickBuiltin")) { Task { await model.pickBuiltin() } }
          .accessibilityIdentifier("templates.pickBuiltin")
        Button(L10n.t("templates.pickPackage")) { Task { await model.pick(window: unsaved?.window) } }
          .accessibilityIdentifier("templates.pick")
        if model.planning {
          ProgressView().controlSize(.small)
          Note(L10n.t("templates.planning"))
        } else if let path = model.packagePath {
          Text(sourceLine(path)).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            .help(path)
        }
      }
      .disabled(model.running || model.planning)
      if model.unreadable {
        Callout(.error, L10n.t("templates.previewError"))
      }
      if model.plan == nil, let failure = model.failure {
        Callout(.error, failure)
      }
      if let plan = model.plan {
        packageBox(plan)
      }
    }

    if let plan = model.plan {
      SettingsSection(L10n.t("templates.strategyHeading")) {
        Picker(L10n.t("templates.strategyHeading"), selection: $model.strategy) {
          Text(L10n.t("templates.strategyPackage")).tag(TemplatePackage.Strategy.packageWins)
          Text(L10n.t("templates.strategyProject")).tag(TemplatePackage.Strategy.projectWins)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(model.running)
        .accessibilityIdentifier("templates.strategy")
        Note(model.strategy == .packageWins ? L10n.t("templates.strategyPackageHint") : L10n.t("templates.strategyProjectHint"))
      }

      SettingsSection(L10n.t("templates.partsHeading")) {
        ForEach(TemplatesModel.sortedForDisplay(plan.parts, id: \.id), id: \.id) { part in
          PartRow(id: part.id, checked: model.importSelected.contains(part.id), disabled: model.running,
                  summary: TemplateWords.planSummary(part, strategy: model.strategy),
                  notes: TemplateWords.planNotes(part, strategy: model.strategy, pluginsSelected: model.importSelected.contains("plugins")),
                  identifier: "templates.import.\(part.id)") {
            model.toggleImport(part.id)
          } extra: {
            EmptyView()
          }
        }
        if !model.missingPackages.isEmpty {
          Note(L10n.t("templates.willInstall", ["packages": model.missingPackages.joined(separator: ", ")]))
        }
        if !model.clonedPlugins.isEmpty {
          Note(L10n.t("templates.willClone", ["plugins": model.clonedPlugins.joined(separator: ", ")], count: model.clonedPlugins.count))
        }
        HStack(spacing: 12) {
          Button(model.running ? L10n.t("templates.importing") : L10n.t("templates.importButton")) {
            Task { await model.runImport(window: unsaved?.window) }
          }
          .disabled(model.running || model.planning || model.importSelected.isEmpty)
          .accessibilityIdentifier("templates.apply")
          if let progress = model.progress {
            Text(progressLine(progress)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        if let progress = model.progress, progress.total > 0 {
          ProgressView(value: Double(progress.done), total: Double(progress.total))
        }
        if let failure = model.failure {
          Callout(.error, failure)
        }
        if let warnings = model.warnings {
          outcome(warnings)
        }
      }
    }
  }

  private func sourceLine(_ path: String) -> String {
    switch model.builtinSource {
    case .downloaded: L10n.t("templates.builtinDownloaded")
    case .bundled: model.builtinDownloadNotNewer ? L10n.t("templates.builtinBundledCurrent") : L10n.t("templates.builtinBundled")
    case nil: path
    }
  }

  private func packageBox(_ plan: TemplatePackage.Plan) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: "doc.zipper").foregroundStyle(.secondary).accessibilityHidden(true)
        Text(plan.manifest["name"]?.stringValue ?? "").fontWeight(.medium)
        if plan.legacy { WordBadge(text: L10n.t("templates.legacyBadge")) }
      }
      if let description = plan.manifest["description"]?.stringValue, !description.isEmpty {
        Text(description).font(.callout)
      }
      Text(L10n.t("templates.packageOrigin", [
        "date": Formats.date(iso: plan.manifest["createdAt"]?.stringValue ?? "")
          .map { $0.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: L10n.language))) } ?? "",
        "project": plan.manifest["source"]?["projectName"]?.stringValue ?? L10n.t("templates.unknownProject"),
      ]))
      .font(.callout).foregroundStyle(.secondary)
      if !plan.unknownParts.isEmpty {
        Callout(.warning, L10n.t("templates.unknownParts", ["parts": plan.unknownParts.map { $0.stringValue ?? JSJSON.stringify($0) }.joined(separator: ", ")]))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("templates.package")
  }

  private func progressLine(_ progress: TemplatesModel.Progress) -> String {
    guard let id = progress.partId else { return L10n.t("templates.importPreparing") }
    return TemplateWords.label(id) + (progress.message.isEmpty ? "" : " — \(progress.message)")
  }

  /// QuartzControl's `ImportOutcome`: one line when nothing stayed open, the grouped warnings otherwise.
  @ViewBuilder private func outcome(_ warnings: [String]) -> some View {
    if warnings.isEmpty {
      Label(L10n.t("templates.importSuccessNoWarnings"), systemImage: "checkmark")
        .font(.callout).foregroundStyle(.green)
        .accessibilityIdentifier("templates.outcome")
    } else {
      Callout(.warning) {
        ForEach(Array(ImportWarnings.lines(warnings).enumerated()), id: \.offset) { _, line in Text(line) }
      }
      .accessibilityIdentifier("templates.outcome")
    }
  }
}

/// One part of a package, ticked or not: its name and counts on the checkbox, what it is under it,
/// and the plan's sentences about it.
private struct PartRow<Extra: View>: View {
  let id: String
  let checked: Bool
  let disabled: Bool
  let summary: String
  var notes: [String] = []
  let identifier: String
  let toggle: () -> Void
  @ViewBuilder var extra: () -> Extra

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Toggle(isOn: Binding(get: { checked }, set: { _ in toggle() })) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(TemplateWords.label(id)).fontWeight(.medium)
          Text(summary).font(.callout).foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.checkbox)
      .disabled(disabled)
      .accessibilityIdentifier(identifier)
      VStack(alignment: .leading, spacing: 3) {
        Text(TemplateWords.description(id)).font(.callout).foregroundStyle(.secondary)
        ForEach(notes, id: \.self) { note in
          Callout(.warning, note)
        }
        extra()
      }
      .padding(.leading, 20)
    }
  }
}
