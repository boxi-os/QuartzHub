import QuartzHubCore
import SwiftUI

/// Veröffentlichen: QuartzControl's `Publish/index.tsx`. In the middle the targets as a list, then
/// for the selected one what would change and the button that publishes it, the file list last
/// (it can run to hundreds of lines). The inspector shows the selected target: where it goes, its
/// connection, its exclusions, and editing and deleting it. A target is edited in a sheet with its
/// own "Speichern"; a connection begun there is a sheet over it.
///
/// A list page (decisions/ui-ueberarbeitung.md). Publishing is the toolbar's one prominent action,
/// not the inspector's: the inspector can be hidden for the whole window, and the page's one action
/// must not go with it. A new target and the connections are the toolbar's too.
struct PublishPage: View {
  let project: ProjectContext

  @State private var model: PublishModel
  @Environment(\.unsavedGuard) private var unsaved
  @Environment(\.openSettings) private var openSettings
  /// The selected target, by id ("where was I").
  @SceneStorage("publish.target") private var selectedId: String?
  @State private var editing: Identified<TargetDraft>?
  @FocusState private var outputDirFocused: Bool

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: PublishModel.shared(project))
  }

  var body: some View {
    PageScaffold(page: .publish) {
      VStack(alignment: .leading, spacing: 0) {
        notices
        list
      }
      .toolbar { toolbar }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.publish")
      .task {
        await model.appear()
        pickDefault()
      }
      .onChange(of: selectedId) { old, id in
        // A click on the list's empty space cleared the selection: the page below the list went
        // and the inspector said "Noch kein Ziel … Lege eins an" beside two targets (measured
        // 2026-11-10). QuartzControl always has one selected; a deleted target is not kept.
        if id == nil, let old, model.targets.contains(where: { $0.id == old }) {
          selectedId = old
          return
        }
        model.select(id)
      }
      .onChange(of: model.targets.map(\.id)) { _, _ in pickDefault() }
      .onChange(of: AppDeploy.ConnectionsVersion.shared.value) { _, _ in model.reloadConnections() }
      .sheet(item: $editing) { item in TargetSheet(model: model, draft: item.value) { selectedId = $0 } }
    } inspector: {
      if let target = model.selected {
        TargetInspector(model: model, target: target, window: unsaved?.window) { editing = Identified(value: TargetDraft(target)) }
      } else {
        InspectorPageContext(page: .publish) {
          Section {
            Text(L10n.t("publish.panelEmptyText")).foregroundStyle(.secondary)
          } header: {
            Text(L10n.t("publish.panelEmptyTitle"))
          }
        }
      }
    }
  }

  /// Without a selection everything below the list describes nothing, so the first target is
  /// taken when none is selected or the selected one is gone; a choice made is never overwritten.
  private func pickDefault() {
    let ids = model.targets.map(\.id)
    if let selectedId, ids.contains(selectedId) {
      model.select(selectedId)
    } else {
      selectedId = ids.first
      model.select(ids.first)
    }
  }

  // MARK: Toolbar and notices

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button { editing = Identified(value: .empty()) } label: {
        Label(L10n.t("publish.newTarget"), systemImage: "plus")
      }
      .help(L10n.t("publish.newTarget"))
      .accessibilityIdentifier("publish.newTarget")
      Button { PublishModel.openConnectionSettings(openSettings) } label: {
        Label(L10n.t("publish.manageConnections"), systemImage: "key")
      }
      .help(L10n.t("publish.manageConnections"))
      .accessibilityIdentifier("publish.manageConnections")
    }
    if let target = model.selected {
      let document = target.destination["type"] == .string("document")
      let running = model.running && model.runningTarget == target.id
      ToolbarSpacer(.fixed, placement: .primaryAction)
      ToolbarItem(placement: .primaryAction) {
        Button { Task { await model.publish(window: unsaved?.window) } } label: {
          Label(running ? L10n.t("common.saving") : document ? L10n.t("publish.exportButton") : L10n.t("publish.deployButton"),
                systemImage: ProjectPage.publish.symbol)
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glassProminent)
        .disabled(!model.canDeploy)
        .accessibilityIdentifier("publish.deploy")
      }
    }
  }

  /// Outside the list's scrolling, so no `fixedSize(vertical:)` here (Snapshots).
  @ViewBuilder private var notices: some View {
    if model.baseUrlWarning || model.failure != nil {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if model.baseUrlWarning {
          Callout(.warning, L10n.t("publish.baseUrlWarning", ["baseUrl": model.baseUrl?.isEmpty == false ? model.baseUrl! : "—"]))
            .accessibilityIdentifier("publish.baseUrlWarning")
        }
        if let failure = model.failure {
          Callout(.error) { Text(failure).textSelection(.enabled) }
        }
      }
      .padding(.horizontal, Spacing.page)
      .padding(.vertical, Spacing.s)
    }
  }

  // MARK: The list

  private var list: some View {
    List(selection: $selectedId) {
      Section {
        if model.targets.isEmpty { Text(L10n.t("publish.noTargets")).foregroundStyle(.secondary) }
        ForEach(model.targets, id: \.id) { target in
          TargetRow(target: target, line: PublishWords.destination(target, connections: model.connections))
            .tag(target.id)
            .contextMenu {
              Button(L10n.t("common.edit")) { editing = Identified(value: TargetDraft(target)) }
              Divider()
              Button(L10n.t("common.deleteNamed", ["name": target.name]), role: .destructive) { delete(target) }
            }
            .accessibilityActions {
              Button(L10n.t("common.deleteNamed", ["name": target.name])) { delete(target) }
            }
        }
      } header: {
        Text(L10n.t("publish.targetHeading"))
      } footer: {
        Note(L10n.t("publish.connectionVsTarget"))
      }
      if let target = model.selected { targetSections(target) }
    }
    .accessibilityIdentifier("publish.list")
  }

  private func delete(_ target: PublishTarget) {
    Task {
      if await model.delete(target, window: unsaved?.window), selectedId == target.id { selectedId = nil }
    }
  }

  @ViewBuilder private func targetSections(_ target: PublishTarget) -> some View {
    let type = target.destination["type"]?.stringValue
    if type == "git-branch", target.destination["provider"] == .string("github") {
      GitHubPagesSection(project: project.path, branch: target.destination["branch"]?.stringValue ?? "")
    }
    if model.hasFileDiff {
      diffSection(target)
    } else {
      Section { Note(L10n.t("publish.webhookExplainer")) }
    }
    publishSection(target)
    if let diff = model.diff, !diff.isEmpty { fileSections(diff) }
  }

  // MARK: What would change

  private func diffSection(_ target: PublishTarget) -> some View {
    Section {
      HStack {
        Button(model.building ? L10n.t("common.saving") : L10n.t("publish.buildNow")) { Task { await model.buildNow() } }
          .disabled(model.building || model.running)
          .accessibilityIdentifier("publish.build")
        Button(model.diffing ? L10n.t("common.loading") : L10n.t("publish.refreshDiff")) { Task { await model.refreshDiff() } }
          .disabled(model.diffing || model.running)
          .accessibilityIdentifier("publish.refreshDiff")
        if model.canExclude {
          Button(model.forgetting ? L10n.t("common.saving") : L10n.t("publish.uploadEverything")) { Task { await model.forgetManifest() } }
            .disabled(model.forgetting || model.diffing || model.running)
            .help(L10n.t("publish.uploadEverythingHint"))
            .accessibilityIdentifier("publish.uploadEverything")
        }
      }
      outputDirRow
      if let line = model.buildLine {
        Text(line.text).font(.callout).foregroundStyle(line.success ? .green : .red)
      }
      if let error = model.diffError ?? model.buildError {
        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("publish.diffError")
      }
      if model.diff == nil && model.diffError == nil {
        Note(L10n.t("publish.noDiffYet"))
      } else if let diff = model.diff {
        if diff.isEmpty {
          Note(L10n.t("publish.noChanges")).accessibilityIdentifier("publish.noChanges")
        } else {
          Text(summary(diff)).font(.callout).accessibilityIdentifier("publish.diffSummary")
        }
      }
    } header: {
      Label(L10n.t("publish.diffHeading"), systemImage: "doc.badge.arrow.up")
    }
  }

  private func summary(_ diff: [DeployDiffEntry]) -> String {
    [DeployDiffEntry.Status.added, .changed, .removed].compactMap { status in
      let count = diff.filter { $0.status == status }.count
      return count > 0 ? "\(PublishWords.status(status)): \(count)" : nil
    }.joined(separator: " · ")
  }

  private var outputDirRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      // A List row shows no TextField label of its own.
      LabeledContent(L10n.t("publish.outputDir")) {
        TextField(L10n.t("publish.outputDir"), text: $model.outputDir, prompt: Text(L10n.t("publish.outputDirPlaceholder")))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 420)
          .focused($outputDirFocused)
          .onSubmit { model.commitOutputDir(model.outputDir) }
          .onChange(of: outputDirFocused) { _, focused in if !focused { model.commitOutputDir(model.outputDir) } }
          .accessibilityIdentifier("publish.outputDir")
      }
      Note(L10n.t("publish.outputDirShared"))
      if let error = model.outputDirError { Text(error).font(.caption).foregroundStyle(.red) }
    }
  }

  // MARK: Publishing

  private func publishSection(_ target: PublishTarget) -> some View {
    let document = target.destination["type"] == .string("document")
    let running = model.running && model.runningTarget == target.id
    // The button is the toolbar's; here what it does and how it went.
    return Section {
      if document && running {
        Button(L10n.t("publish.cancelExport")) { model.cancelExport() }
          .accessibilityIdentifier("publish.cancelExport")
      }
      if !running, model.result?.targetId != target.id {
        Note(L10n.t("publish.deployHint"))
      }
      if target.destination["deleteRemoved"] == .bool(false) {
        Note(L10n.t("publish.deleteDisabledHint"))
      }
      // Its own view: only it reads the progress, so an event redraws one row and not the page.
      if running { DeployProgress(model: model) }
      if let result = model.result, result.targetId == target.id {
        OutcomeTitle(title: model.resultTitle(result.value, document: document), success: result.value.success, partial: !result.value.kept.isEmpty)
          .accessibilityIdentifier("publish.result")
        RunOutput(text: result.value.output, label: L10n.t("publish.deployHeading"), identifier: "publish.output")
      }
    } header: {
      Label(L10n.t("publish.deployHeading"), systemImage: "icloud.and.arrow.up")
    }
  }

  // MARK: The files

  @ViewBuilder private func fileSections(_ diff: [DeployDiffEntry]) -> some View {
    ForEach([DeployDiffEntry.Status.added, .changed, .removed], id: \.self) { status in
      let entries = diff.filter { $0.status == status }
      if !entries.isEmpty {
        Section("\(PublishWords.status(status)) (\(entries.count))") {
          ForEach(entries, id: \.path) { entry in
            if model.canExclude {
              Toggle(isOn: Binding(get: { !model.isExcluded(entry.path) }, set: { _ in model.toggleExcluded(entry.path) })) {
                Text(verbatim: entry.path).font(.callout.monospaced())
                  .strikethrough(model.isExcluded(entry.path))
                  .foregroundStyle(model.isExcluded(entry.path) ? .secondary : .primary)
              }
              .toggleStyle(.checkbox)
              .disabled(model.running)
            } else {
              Text(verbatim: entry.path).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }
}

private struct DeployProgress: View {
  let model: PublishModel

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let run = model.run, run.total > 0 {
        ProgressView(value: Double(run.processed), total: Double(run.total))
        Text(L10n.t("publish.progress", ["processed": String(run.processed), "total": String(run.total), "file": run.file ?? ""]))
          .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      } else {
        ProgressView().controlSize(.small)
      }
    }
  }
}

private struct TargetRow: View {
  let target: PublishTarget
  let line: String

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(target.name)
        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
      Spacer()
      Text(PublishWords.type(target.destination["type"]?.stringValue ?? "")).font(.caption).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}

/// The selected target: where it goes, the connection it logs in with, what it never publishes;
/// editing it, forgetting its host key, deleting it.
private struct TargetInspector: View {
  let model: PublishModel
  let target: PublishTarget
  let window: NSWindow?
  let edit: () -> Void

  var body: some View {
    let connection = model.connection(of: target)
    Form {
      Section {
        LabeledContent(L10n.t("publish.targetForm.type"), value: PublishWords.type(target.destination["type"]?.stringValue ?? ""))
        Text(PublishWords.destination(target, connections: model.connections))
          .textSelection(.enabled)
          .accessibilityIdentifier("publish.inspector.destination")
        if let connection, ConnectionWords.missingCredential(connection) {
          Text(L10n.t("publish.noSecretWarning")).foregroundStyle(.orange)
        }
        if let connection, connection.kind == .ssh {
          Text(ConnectionWords.hostKey(connection)).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
          if connection.hostKey != nil {
            Button(L10n.t("publish.forgetHostKey")) { Task { await model.forgetHostKey(connection, window: window) } }
          }
        }
        if !target.excludes.isEmpty {
          LabeledContent(L10n.t("publish.targetForm.excludes")) {
            Text(target.excludes.joined(separator: ", ")).textSelection(.enabled)
          }
        }
      } header: {
        Text(target.name).font(.headline)
      }
      Section {
        Button(L10n.t("common.edit"), action: edit)
          .accessibilityIdentifier("publish.editTarget")
        Button(L10n.t("common.deleteNamed", ["name": target.name]), role: .destructive) {
          Task { _ = await model.delete(target, window: window) }
        }
      }
    }
    .formStyle(.grouped)
  }
}
