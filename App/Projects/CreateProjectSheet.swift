import QuartzHubCore
import SwiftUI

/// "Neues Quartz-Projekt": QuartzControl's `CreateWizard` (`Home.tsx`) as a sheet on the Projects
/// window. Two fields for the place rather than one path, because the folder is created here: a
/// folder picker can only return a folder that exists. The line under them shows what will be made.
///
/// Once the project exists the form gives way to one message and one way on ("Zum Projekt"), if
/// there is anything to report; with nothing to report it goes to the project directly.
struct CreateProjectSheet: View {
  /// Called with the new project's id when the sheet should open it; nil when it was cancelled.
  let finish: (String?) -> Void

  @State private var parent = ProjectsModel.defaultDirectory ?? ""
  @State private var name = ""
  @State private var quartzTemplate = ProjectCreator.Template.default
  @State private var strategy = ProjectCreator.Strategy.new
  @State private var source = ""
  @State private var linkResolution = ProjectCreator.LinkResolution.shortest
  @State private var baseUrl = "localhost"
  /// The example template, asked for once: the answer may involve a download.
  @State private var builtin: BuiltinTemplate.Found?
  /// Asked and nothing came: QuartzHub ships no copy, so the wizard says so and can ask again.
  @State private var builtinMissing = false
  @State private var builtinLoading = false
  @State private var useTemplate = true
  @State private var withContent = true
  @State private var busy = false
  @State private var error: String?
  @State private var outcome: ProjectCreation.Outcome?

  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var nameInvalid: Bool { trimmedName.contains("/") || trimmedName == "." || trimmedName == ".." }
  /// One separator: macOS only.
  private var target: String {
    guard !parent.isEmpty, !trimmedName.isEmpty else { return "" }
    var base = parent
    while base.hasSuffix("/") { base.removeLast() }
    return "\(base)/\(trimmedName)"
  }
  private var canCreate: Bool { !busy && !target.isEmpty && !nameInvalid && (strategy == .new || !source.isEmpty) }
  private var contentAllowed: Bool { ProjectCreation.contentAllowed(strategy) }

  var body: some View {
    Group {
      if let outcome, let id = outcome.projectId {
        done(outcome, id)
      } else {
        form
      }
    }
    .frame(width: 560)
    .interactiveDismissDisabled(busy)
    .task { await loadBuiltin() }
  }

  private var form: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          Text(L10n.t("home.wizard.intro")).foregroundStyle(.secondary)
        } header: {
          Text(L10n.t("home.wizard.title")).font(.title3.weight(.semibold))
        }
        Section {
          FormField(hint: L10n.t("home.wizard.parentDirectoryHint")) {
            FolderField(label: L10n.t("home.wizard.parentDirectory"), placeholder: L10n.t("home.wizard.parentDirectoryPlaceholder"),
                        path: $parent, start: ProjectsModel.defaultDirectory)
          }
          FormField(hint: L10n.t("home.wizard.projectNameHint")) {
            TextField(L10n.t("home.wizard.projectName"), text: $name, prompt: Text(L10n.t("home.wizard.projectNamePlaceholder")))
              .accessibilityIdentifier("create.name")
          }
          if nameInvalid {
            Text(L10n.t("home.wizard.nameInvalid")).foregroundStyle(.red).font(.callout)
          } else if !target.isEmpty {
            LabeledContent(L10n.t("home.wizard.targetPreview")) {
              Text(target).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
          }
        }
        Section {
          FormField(hint: L10n.t("home.wizard.templateHint")) {
            Picker(L10n.t("home.wizard.template"), selection: $quartzTemplate) {
              ForEach(ProjectCreator.Template.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
          }
          FormField(hint: L10n.t("home.wizard.contentStrategyHint")) {
            Picker(L10n.t("home.wizard.contentStrategy"), selection: $strategy) {
              Text(L10n.t("home.wizard.strategyNew")).tag(ProjectCreator.Strategy.new)
              Text(L10n.t("home.wizard.strategyCopy")).tag(ProjectCreator.Strategy.copy)
              Text(L10n.t("home.wizard.strategySymlink")).tag(ProjectCreator.Strategy.symlink)
            }
          }
          if strategy != .new {
            FormField(hint: L10n.t("home.wizard.sourceFolderHint")) {
              FolderField(label: L10n.t("home.wizard.sourceFolder"), placeholder: nil, path: $source, start: nil)
            }
          }
          FormField(hint: L10n.t("home.wizard.linkResolutionHint")) {
            Picker(L10n.t("home.wizard.linkResolution"), selection: $linkResolution) {
              Text(L10n.t("home.wizard.linkShortest")).tag(ProjectCreator.LinkResolution.shortest)
              Text(L10n.t("home.wizard.linkAbsolute")).tag(ProjectCreator.LinkResolution.absolute)
              Text(L10n.t("home.wizard.linkRelative")).tag(ProjectCreator.LinkResolution.relative)
            }
          }
          FormField(hint: L10n.t("home.wizard.baseUrlHint")) {
            TextField(L10n.t("home.wizard.baseUrl"), text: $baseUrl)
          }
        }
        if let builtin {
          Section {
            FormField(hint: L10n.t("home.wizard.useTemplateHint")) {
              Toggle(L10n.t("home.wizard.useTemplate"), isOn: $useTemplate)
            }
            if useTemplate, builtin.pages > 0 {
              FormField(hint: contentHint(builtin)) {
                Toggle(L10n.t("home.wizard.templateContent"), isOn: Binding(get: { withContent && contentAllowed }, set: { withContent = $0 }))
                  .disabled(!contentAllowed)
              }
            }
          }
        } else if builtinMissing {
          Section {
            FormField(hint: L10n.t("home.wizard.templateUnavailableHint")) {
              LabeledContent(L10n.t("home.wizard.templateUnavailable")) {
                Button(L10n.t("home.wizard.templateRetry")) { Task { await loadBuiltin() } }
                  .disabled(builtinLoading)
                  .accessibilityIdentifier("create.templateRetry")
              }
            }
          }
        }
        if let error {
          Section {
            Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
          }
        }
      }
      .formStyle(.grouped)
      .disabled(busy)
      buttons
    }
    .frame(minHeight: 520, idealHeight: 680)
  }

  private func loadBuiltin() async {
    builtinLoading = true
    defer { builtinLoading = false }
    builtin = await BuiltinTemplate.app().find()
    builtinMissing = builtin == nil
  }

  private func contentHint(_ builtin: BuiltinTemplate.Found) -> String {
    switch strategy {
    case .new: L10n.t("home.wizard.templateContentHint", ["count": String(builtin.pages)], count: builtin.pages)
    case .copy: L10n.t("home.wizard.templateContentHintCopy")
    case .symlink: L10n.t("home.wizard.templateContentHintSymlink")
    }
  }

  private var buttons: some View {
    HStack {
      if busy {
        ProgressView().controlSize(.small)
        Text(L10n.t("home.wizard.creating")).foregroundStyle(.secondary)
      }
      Spacer()
      Button(L10n.t("common.cancel"), role: .cancel) { finish(nil) }
        .keyboardShortcut(.cancelAction)
        .disabled(busy)
      Button(L10n.t("home.wizard.create"), action: create)
        .keyboardShortcut(.defaultAction)
        .disabled(!canCreate)
        .accessibilityIdentifier("create.confirm")
    }
    .padding()
  }

  private func done(_ outcome: ProjectCreation.Outcome, _ id: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.t("home.wizard.doneTitle")).font(.title3.weight(.semibold))
      Text(outcome.failure != nil ? L10n.t("home.wizard.doneWithFailure") : L10n.t("home.wizard.doneWithWarnings"))
        .foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          if let failure = outcome.failure {
            Text(failure).foregroundStyle(.red).textSelection(.enabled)
          }
          if let style = outcome.styleFailure {
            Text(style).foregroundStyle(.orange).textSelection(.enabled)
          }
          ForEach(Array(ImportWarnings.lines(outcome.warnings).enumerated()), id: \.offset) { _, line in
            Text(line).foregroundStyle(.orange)
          }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 240)
      HStack {
        Spacer()
        Button(L10n.t("home.wizard.toProject")) { finish(id) }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
  }

  private func create() {
    guard canCreate else { return }
    var options = ProjectCreator.Options(targetDirectory: target)
    options.template = quartzTemplate
    options.strategy = strategy
    options.linkResolution = linkResolution
    options.source = strategy == .new ? nil : source
    options.baseUrl = baseUrl
    // `pages > 0` too: where the package has no page the switch is not shown, and a part nobody
    // could choose is not taken along.
    let template = builtin.flatMap { found in
      useTemplate ? ProjectCreation.Template(path: found.path, withContent: withContent && contentAllowed && found.pages > 0) : nil
    }
    busy = true
    error = nil
    Task {
      defer { busy = false }
      let services = AppServices.shared
      let result = await ProjectCreation.run(
        options, template: template, appLanguage: L10n.language, environment: await services.environment.value,
        list: ProjectsModel.shared.list, templates: await services.templates())
      await ProjectsModel.shared.reload()
      guard let id = result.projectId else {
        error = result.output
        return
      }
      if result.hasReport { outcome = result } else { finish(id) }
    }
  }
}
