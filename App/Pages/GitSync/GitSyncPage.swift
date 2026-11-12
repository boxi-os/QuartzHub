import QuartzHubCore
import SwiftUI

/// Git-Sync: QuartzControl's `GitSync.tsx` as a settings form (variant C). Its three cards are sections, in
/// this order: the repository's state, the repository on GitHub (only without an origin), the sync,
/// and last the changed files, which can run to 500 rows and would push the sync off the window
/// above them. "Aktualisieren" is in the toolbar.
struct GitSyncPage: View {
  let project: ProjectContext

  @State private var model: GitSyncModel
  /// Whether the sync commits, and under which message. Per window rather than plain state: a
  /// message typed a moment ago survives the trip to another page (QuartzControl's `sync.commit`,
  /// `sync.message`).
  @SceneStorage("sync.commit") private var commit = true
  @SceneStorage("sync.message") private var message = ""
  @State private var repoName = ""
  @State private var repoPrivate = false

  /// The branch `quartz sync --pull` fetches, hardcoded in the CLI (`quartz/cli/constants.js`:
  /// `QUARTZ_SOURCE_BRANCH = "v5"`), not the one checked out. Nothing else would reveal it.
  static let quartzSourceBranch = "v5"

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: GitSyncModel.shared(project))
  }

  var body: some View {
    PageScaffold(page: .sync) {
      SettingsForm {
        statusSection
        if let status = model.status, status.isRepo, status.readError == nil, status.remoteUrl == nil {
          createRepoSection
        }
        syncSection
        if let status = model.status, !status.changes.isEmpty {
          changesSection(status)
        }
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(L10n.t("gitSync.refresh"), systemImage: "arrow.clockwise") { Task { await model.refresh() } }
            .disabled(model.refreshing)
            .help(L10n.t("gitSync.refresh"))
            .accessibilityIdentifier("gitSync.refresh")
        }
      }
      .task { await model.appear() }
    } inspector: {
      InspectorPageContext(page: .sync) {
        Section {
          Text(L10n.t("projectLayout.descriptions.sync")).foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: The repository's state

  private var statusSection: some View {
    SettingsSection(L10n.t("gitSync.statusTitle"), symbol: ProjectPage.sync.symbol) {
      // On a row that is always there: a Form's identifier does not reach the accessibility tree.
      Group {
        if let status = model.status {
          if let readError = status.readError {
            VStack(alignment: .leading, spacing: 6) {
              Text(L10n.t("gitSync.readError")).foregroundStyle(.red)
              Text(verbatim: readError).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          } else if !status.isRepo {
            Note(L10n.t("gitSync.notARepo"))
          } else {
            LabeledContent(L10n.t("gitSync.branchLabel")) {
              if status.detached {
                Text(L10n.t("gitSync.detached"))
              } else {
                Text(verbatim: status.branch ?? "—").font(.system(.body, design: .monospaced))
              }
            }
          }
        } else {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Note(L10n.t("dashboard.updates.checking"))
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.sync")

      if let status = model.status, status.readError == nil, status.isRepo {
        repoRows(status)
      }

      if let notice = model.notice {
        Text(verbatim: notice.text)
          .font(notice.verbatim ? .system(.callout, design: .monospaced) : .body)
          .foregroundStyle(notice.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
          .textSelection(.enabled)
          .accessibilityIdentifier("gitSync.notice")
      }
    } accessory: {
      if model.refreshing { ProgressView().controlSize(.small) }
    }
  }

  @ViewBuilder
  private func repoRows(_ status: GitStatus) -> some View {
    if status.detached { Note(L10n.t("gitSync.detachedHint")) }

    LabeledContent(L10n.t("gitSync.upstreamLabel")) {
      if let upstream = status.upstream {
        Text(verbatim: upstream).font(.system(.body, design: .monospaced))
      } else {
        StateBadge(text: L10n.t("gitSync.noUpstream"), color: .gray)
      }
    }
    if status.upstream != nil {
      LabeledContent(L10n.t("gitSync.remoteStateLabel")) {
        VStack(alignment: .trailing, spacing: 2) {
          if status.ahead == 0 && status.behind == 0 {
            StateBadge(text: L10n.t("gitSync.upToDate"), color: .green)
          }
          if status.ahead > 0 {
            StateBadge(text: L10n.t("gitSync.ahead", ["count": String(status.ahead)], count: status.ahead), color: .orange)
          }
          if status.behind > 0 {
            StateBadge(text: L10n.t("gitSync.behind", ["count": String(status.behind)], count: status.behind), color: .orange)
          }
        }
      }
    } else if status.remoteUrl != nil {
      Note(L10n.t("gitSync.noUpstreamHint"))
    }

    LabeledContent(L10n.t("gitSync.localLabel")) {
      VStack(alignment: .trailing, spacing: 2) {
        if status.conflictCount > 0 {
          StateBadge(text: L10n.t("gitSync.conflicts", ["count": String(status.conflictCount)], count: status.conflictCount), color: .red)
        }
        StateBadge(text: status.changeCount == 0 ? L10n.t("gitSync.clean")
                     : L10n.t("gitSync.changes", ["count": String(status.changeCount)], count: status.changeCount),
                   color: status.changeCount == 0 ? .green : .orange)
      }
    }

    // Read from git rather than from the last result: a half-finished merge is there after the
    // page was left, and this is the way out of it.
    if let operation = status.inProgress {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
        Text(Self.inProgressText(operation))
        Spacer(minLength: 8)
        if operation == .merge {
          Button(L10n.t("gitSync.abortMerge")) { Task { await model.abortMerge() } }
            .disabled(model.aborting || model.busy != nil)
            .accessibilityIdentifier("gitSync.abortMerge")
        }
      }
      .accessibilityElement(children: .contain)
    }

    if let remote = status.remoteUrl {
      LabeledContent {
        VStack(alignment: .trailing, spacing: 2) {
          Text(verbatim: remote).font(.system(.callout, design: .monospaced))
            .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(remote)
          // Only for github.com: the remote itself may be the scp-like form, which no browser opens.
          if let repo = model.repo, let url = URL(string: repo.htmlUrl) {
            Link(destination: url) {
              Label(L10n.t("gitSync.openOnGithub"), systemImage: "arrow.up.right.square").labelStyle(TrailingIcon())
            }
          }
        }
      } label: {
        Text(verbatim: "origin")
      }
    } else {
      Note(L10n.t("gitSync.noRemote"))
    }

    if let last = status.lastCommit {
      LabeledContent(L10n.t("gitSync.lastCommit")) {
        VStack(alignment: .trailing, spacing: 2) {
          Text("\(Text(verbatim: last.shortSha).font(.system(.body, design: .monospaced)))\(Text(verbatim: " " + last.subject))")
            .lineLimit(2).multilineTextAlignment(.trailing)
          Text(verbatim: "\(last.author) · \(Self.when(last.date))").font(.callout).foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: A repository on GitHub

  /// Offered only when the project is a repository with no origin at all: the state a new project
  /// is left in on purpose, so that a push can never reach jackyzha0/quartz.
  private var createRepoSection: some View {
    SettingsSection(L10n.t("gitSync.createRepo.title"), symbol: "plus.rectangle.on.folder") {
      Note(model.viewer.map { L10n.t("gitSync.createRepo.asAccount", ["login": $0.login]) } ?? L10n.t("gitSync.createRepo.noToken"))
      TextField(L10n.t("gitSync.createRepo.name"), text: $repoName)
        .disabled(model.viewer == nil || model.creating)
        .accessibilityIdentifier("gitSync.repoName")
      // The consequence belongs where the decision is taken: GitHub refuses Pages for a private
      // repository on a free account, and says so steps later, on Veröffentlichen.
      Toggle(isOn: $repoPrivate) {
        Text(L10n.t("gitSync.createRepo.private"))
        Text(L10n.t("gitSync.createRepo.privateHint"))
      }
      .disabled(model.viewer == nil || model.creating)
      HStack(spacing: 8) {
        Button(L10n.t("gitSync.createRepo.action")) { Task { await model.createRepo(name: repoName, isPrivate: repoPrivate) } }
          .disabled(model.viewer == nil || repoName.trimmingCharacters(in: .whitespaces).isEmpty || model.creating)
          .accessibilityIdentifier("gitSync.createRepo")
        if model.creating { ProgressView().controlSize(.small) }
      }
      if let result = model.createResult {
        RunOutput(text: result.output, label: L10n.t("gitSync.createRepo.output"), identifier: "gitSync.createRepoOutput")
      }
    }
    .task {
      // A sensible default the user can overwrite: the project folder's own name.
      if repoName.isEmpty { repoName = NodePath.basename(project.path) }
      await model.loadViewer()
    }
  }

  // MARK: The sync

  /// The note says what `quartz sync` does, in its order: the commit (on by default, even for
  /// "Pull"), the fixed pull branch and the force push.
  private var syncSection: some View {
    SettingsSection(L10n.t("gitSync.title"), symbol: "arrow.up.arrow.down",
                    note: L10n.t("gitSync.explainer", ["branch": Self.quartzSourceBranch])) {

      // The commit is part of every direction, so it sits above the buttons.
      Toggle(L10n.t("gitSync.commitChanges"), isOn: $commit)
        .disabled(model.busy != nil)
        .accessibilityIdentifier("gitSync.commit")
      TextField(L10n.t("gitSync.commitMessage"), text: $message, prompt: Text(L10n.t("gitSync.commitMessagePlaceholder")))
        .disabled(!commit || model.busy != nil)
        .accessibilityIdentifier("gitSync.message")
      Note(commitHint)

      if let status = model.status, status.isRepo, !status.detached, let branch = status.branch, branch != Self.quartzSourceBranch {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
          Text(L10n.t("gitSync.pullBranchWarning", ["branch": branch, "source": Self.quartzSourceBranch]))
        }
        .accessibilityElement(children: .combine)
      }

      HStack(spacing: 8) {
        directionButton(.pull, L10n.t("gitSync.pull"), running: L10n.t("gitSync.pullRunning"))
        directionButton(.push, L10n.t("gitSync.push"), running: L10n.t("gitSync.pushRunning"))
        directionButton(.both, L10n.t("gitSync.both"), running: L10n.t("gitSync.bothRunning"))
        if let busy = model.busy {
          ProgressView().controlSize(.small)
          Note(Self.runningText(busy))
        }
      }
      if model.noOrigin, let status = model.status {
        Note(status.isRepo ? L10n.t("gitSync.needsOrigin") : L10n.t("gitSync.needsRepo"))
      }

      if let result = model.result {
        OutcomeTitle(title: result.success ? L10n.t("gitSync.success") : L10n.t("gitSync.failed"), success: result.success)
        RunOutput(text: result.output, label: L10n.t("gitSync.output"), identifier: "gitSync.output")
      }
    }
  }

  private var commitHint: String {
    guard commit else { return L10n.t("gitSync.noCommitHint") }
    if let count = model.status?.changeCount, count > 0 {
      return L10n.t("gitSync.commitHint", ["count": String(count)], count: count)
    }
    return L10n.t("gitSync.commitHintClean")
  }

  private func directionButton(_ direction: Sync.Direction, _ title: String, running: String) -> some View {
    Button(title) { Task { await model.run(direction, commit: commit, message: message) } }
      .disabled(model.busy != nil || model.aborting || model.noOrigin)
      .accessibilityIdentifier("gitSync.\(direction.rawValue)")
  }

  // MARK: The changed files

  private func changesSection(_ status: GitStatus) -> some View {
    SettingsSection(L10n.t("gitSync.changesTitle"), symbol: "doc.badge.ellipsis") {
      ForEach(status.changes, id: \.listId) { change in
        ChangeRow(change: change)
      }
      let hidden = status.changeCount - status.changes.count
      if hidden > 0 {
        Note(L10n.t("gitSync.moreChanges", ["count": String(hidden)], count: hidden))
      }
    } accessory: {
      Text(verbatim: String(status.changeCount)).monospacedDigit()
    }
  }

  // MARK: Pieces

  static func inProgressText(_ operation: GitStatus.Operation) -> String {
    switch operation {
    case .merge: L10n.t("gitSync.inProgress.merge")
    case .rebase: L10n.t("gitSync.inProgress.rebase")
    case .cherryPick: L10n.t("gitSync.inProgress.cherry-pick")
    case .revert: L10n.t("gitSync.inProgress.revert")
    }
  }

  static func runningText(_ direction: Sync.Direction) -> String {
    switch direction {
    case .pull: L10n.t("gitSync.pullRunning")
    case .push: L10n.t("gitSync.pushRunning")
    case .both: L10n.t("gitSync.bothRunning")
    }
  }

  /// git's ISO date in the catalog's language (QuartzControl's `toLocaleString()`).
  static func when(_ iso: String) -> String {
    guard let date = Formats.date(iso: iso) else { return iso }
    return date.formatted(Date.FormatStyle(date: .numeric, time: .standard, locale: Locale(identifier: L10n.language)))
  }
}

/// One changed file: what happened to it in a word, "vorgemerkt" when it is staged, the path.
private struct ChangeRow: View {
  let change: GitStatus.Change

  var body: some View {
    HStack(spacing: 8) {
      StateBadge(text: Self.word(change.status), color: Self.color(change.status))
        .font(.callout)
        .frame(minWidth: 90, alignment: .leading)
      if change.staged { WordBadge(text: L10n.t("gitSync.staged")) }
      Text(verbatim: change.origPath.map { "\($0) → \(change.path)" } ?? change.path)
        .font(.system(.callout, design: .monospaced))
        .lineLimit(1).truncationMode(.middle)
        .help(change.path)
    }
    .accessibilityElement(children: .combine)
  }

  static func color(_ kind: GitStatus.Change.Kind) -> Color {
    switch kind {
    case .conflicted: .red
    case .untracked: .gray
    default: .orange
    }
  }

  static func word(_ kind: GitStatus.Change.Kind) -> String {
    switch kind {
    case .added: L10n.t("gitSync.fileStatus.added")
    case .deleted: L10n.t("gitSync.fileStatus.deleted")
    case .renamed: L10n.t("gitSync.fileStatus.renamed")
    case .copied: L10n.t("gitSync.fileStatus.copied")
    case .modified: L10n.t("gitSync.fileStatus.modified")
    case .untracked: L10n.t("gitSync.fileStatus.untracked")
    case .conflicted: L10n.t("gitSync.fileStatus.conflicted")
    }
  }
}

private extension GitStatus.Change {
  /// QuartzControl's key: a rename's original path and its new one.
  var listId: String { (origPath ?? "") + "\u{0}" + path }
}
