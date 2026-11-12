import QuartzHubCore
import SwiftUI

/// Where the notes come from (QuartzControl's `ContentFolder.tsx`): a folder of the project or a
/// link to a vault, how much is in it, whether it has a start page, and the two dialogs that
/// change that. Outside the config's loading and error states: it is not in quartz.config.yaml,
/// and a config QuartzHub cannot read is no reason to hide where the notes are.
struct ContentFolderSection: View {
  let project: ProjectContext

  @State private var status: ContentFolder.Status?
  @State private var loaded = false
  @State private var changing = false
  @State private var creatingIndex = false
  /// The list on a just-created start page came from the fallback walk, not from Quartz's globby.
  /// It outlives the dialog, which closes on success.
  @State private var indexFallback = false

  var body: some View {
    SettingsSection(L10n.t("content.label"), symbol: "folder", note: L10n.t("content.cardHint")) {
      if let status {
        if !status.exists {
          Text(L10n.t("content.noFolder")).foregroundStyle(.orange)
            .accessibilityIdentifier("page.config")
        } else {
          HStack(spacing: 10) {
            StateBadge(text: status.isSymlink ? L10n.t("content.symlinkBadge") : L10n.t("content.realFolderBadge"),
                       color: status.isSymlink ? (status.targetExists == true ? .secondary : .red) : .green)
            if let count = status.fileCount {
              Text(L10n.t("content.filesCount", ["count": String(count)], count: count)).foregroundStyle(.secondary)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("page.config")
          Text(status.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
          if status.isSymlink, let target = status.symlinkTarget {
            Text("→ " + target + (status.targetExists == true ? "" : L10n.t("content.targetMissingSuffix")))
              .font(.callout)
              .foregroundStyle(status.targetExists == true ? .secondary : Color.red)
              .textSelection(.enabled)
          }
        }
        if status.hasIndex == false {
          HStack(alignment: .firstTextBaseline) {
            Text(L10n.t("content.noIndex")).foregroundStyle(.orange)
            Spacer()
            Button(L10n.t("content.createIndex")) { creatingIndex = true }
              .accessibilityIdentifier("config.createIndex")
          }
        }
        if indexFallback, status.hasIndex == true {
          Text(L10n.t("content.indexCreatedFallback")).font(.callout).foregroundStyle(.orange)
        }
      } else if loaded {
        Text(L10n.t("content.noFolder")).foregroundStyle(.orange).accessibilityIdentifier("page.config")
      } else {
        Text(L10n.t("content.loading")).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button(L10n.t("content.changeSource")) { changing = true }
      }
    }
    .task { await reload() }
    .sheet(isPresented: $changing) {
      ChangeSourceSheet(project: project) { await reload() }
    }
    .sheet(isPresented: $creatingIndex) {
      if let status {
        CreateIndexSheet(project: project, status: status) { fallback in
          indexFallback = fallback
          await reload()
        }
      }
    }
  }

  private func reload() async {
    let path = project.path
    status = await Task.detached { try? ContentFolder.status(project: path) }.value
    loaded = true
  }
}

/// "Quelle ändern…": content/ becomes a copy of another folder or a link to it. Two nets first, a
/// snapshot and the old content folder moved aside, which the warning names.
private struct ChangeSourceSheet: View {
  let project: ProjectContext
  let done: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var source = ""
  @State private var strategy = ContentFolder.SourceStrategy.symlink
  @State private var busy = false
  @State private var progress: (processed: Int, total: Int)?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(L10n.t("content.dialogTitle")).font(.headline)
      Text(L10n.t("content.dialogWarning")).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
      Form {
        LabeledContent(L10n.t("content.newSourceFolder")) {
          HStack {
            TextField(L10n.t("content.newSourceFolder"), text: $source)
              .labelsHidden()
              .onSubmit { Task { await apply() } }
            Button(L10n.t("common.select")) {
              if let folder = ProjectsModel.pickFolder(start: source.isEmpty ? nil : source) { source = folder }
            }
          }
        }
        Picker(L10n.t("content.strategy"), selection: $strategy) {
          Text(L10n.t("content.strategySymlink")).tag(ContentFolder.SourceStrategy.symlink)
          Text(L10n.t("content.strategyCopy")).tag(ContentFolder.SourceStrategy.copy)
        }
      }
      if let progress {
        Text(L10n.t("content.progress", ["processed": String(progress.processed), "total": String(progress.total)]))
          .font(.callout).foregroundStyle(.secondary)
      }
      if let error {
        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
      }
      HStack {
        Spacer()
        Button(L10n.t("common.cancel"), role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(busy)
        Button(busy ? L10n.t("content.applying") : L10n.t("content.apply")) { Task { await apply() } }
          .keyboardShortcut(.defaultAction)
          .disabled(busy || source.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 520)
    .interactiveDismissDisabled(busy)
  }

  private func apply() async {
    guard !busy, !source.isEmpty else { return }
    busy = true
    error = nil
    progress = nil
    let environment = await AppServices.current()
    let take = SnapshotStore.live(environment: environment).take
    let report = ProgressReport { processed, total in progress = (processed, total) }
    let path = project.path, source = source, strategy = strategy
    do {
      // Off the main actor: the copy reports from there, and the report hops back.
      try await Task.detached {
        try await ContentFolder.changeSource(
          project: path, source: source, strategy: strategy,
          snapshot: { project, kind, label in _ = try await take(project, kind, label) },
          progress: { processed, total, _ in report.post(processed, total) })
      }.value
      busy = false
      await done()
      dismiss()
    } catch {
      self.error = (error as? ContentBackups.Failure)?.message ?? String(describing: error)
      busy = false
    }
  }
}

/// The copy reports from wherever it runs; the sheet shows it on the main actor.
private final class ProgressReport: @unchecked Sendable {
  let show: @MainActor (Int, Int) -> Void
  init(show: @escaping @MainActor (Int, Int) -> Void) { self.show = show }
  func post(_ processed: Int, _ total: Int) {
    Task { @MainActor in show(processed, total) }
  }
}

/// "Startseite anlegen…": writes content/index.md, in a linked vault into the user's own notes,
/// which the dialog says.
private struct CreateIndexSheet: View {
  let project: ProjectContext
  let status: ContentFolder.Status
  let done: (_ fallback: Bool) async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var busy = false
  @State private var error: String?

  private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(L10n.t("content.createIndexTitle")).font(.headline)
      Form {
        FormField(hint: L10n.t("content.createIndexTitleHint")) {
          TextField(L10n.t("content.createIndexTitleLabel"), text: $title)
            .onChange(of: title) { _, text in if text.count > 200 { title = String(text.prefix(200)) } }
            .onSubmit { Task { await create() } }
            .accessibilityIdentifier("config.indexTitle")
        }
      }
      Note(L10n.t("content.createIndexListHint"))
      if status.isSymlink, let target = status.symlinkTarget {
        Text(L10n.t("content.createIndexLinked", ["path": target]))
          .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
      }
      if let error {
        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        Button(L10n.t("common.cancel"), role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(busy)
        Button(busy ? L10n.t("content.creatingIndex") : L10n.t("content.createIndexAction")) { Task { await create() } }
          .keyboardShortcut(.defaultAction)
          .disabled(busy || trimmed.isEmpty)
          .accessibilityIdentifier("config.indexCreate")
      }
    }
    .padding(20)
    .frame(width: 480)
    .interactiveDismissDisabled(busy)
    .onAppear { title = project.name }
  }

  private func create() async {
    guard !busy, !trimmed.isEmpty else { return }
    busy = true
    error = nil
    let runtime = await AppServices.current().runtime
    do {
      let created = try await ContentIndexPage.create(project: project.path, title: trimmed, runtime: runtime)
      let fallback = created.listSource == .fallback
      let said = L10n.t("content.indexCreated", ["path": created.path])
      Announce.post(fallback ? said + " " + L10n.t("content.indexCreatedFallback") : said)
      busy = false
      await done(fallback)
      dismiss()
    } catch {
      self.error = error.message
      busy = false
    }
  }
}
