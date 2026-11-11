import QuartzHubCore
import SwiftUI

/// Updates: QuartzControl's `Updates.tsx` as one grouped form, the core and then the plugins. The
/// card that pointed to Snapshots is the inspector's page context now; "Erneut prüfen" is in the
/// toolbar.
struct UpdatesPage: View {
  let project: ProjectContext

  @State private var model: UpdatesModel
  @Environment(\.openPage) private var openPage
  @Environment(\.unsavedGuard) private var unsaved
  /// Read by the Snapshots page: the snapshot to open there (QuartzControl's `backups.open`). The
  /// same type as there: one key declared as `String` here and `String?` there left the whole
  /// window blank on opening Snapshots, sidebar included (measured).
  @SceneStorage("backups.open") private var snapshotToOpen: String?

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: UpdatesModel.shared(project))
  }

  var body: some View {
    PageScaffold(page: .updates) {
      Form {
        coreSection
        pluginsSection
      }
      .formStyle(.grouped)
      .toolbar {
        ToolbarItem {
          Button(L10n.t("updates.recheck"), systemImage: "arrow.clockwise") { Task { await model.reload() } }
            .disabled(model.checking || model.coreBusy)
            .help(L10n.t("updates.recheck"))
            .accessibilityIdentifier("updates.recheck")
        }
      }
      .task { await model.reload() }
    } inspector: {
      InspectorPageContext(page: .updates) {
        Section {
          Text(L10n.t("projectLayout.descriptions.updates")).foregroundStyle(.secondary)
        }
        Section(L10n.t("updates.snapshots.heading")) {
          Text(L10n.t("updates.snapshots.movedHint")).foregroundStyle(.secondary)
          Button(L10n.t("updates.snapshots.openBackups")) { openPage(.backups) }
            .buttonStyle(.link)
        }
        if model.hasInfo {
          Section(L10n.t("updates.info.heading")) {
            Text(L10n.t("updates.info.hint")).foregroundStyle(.secondary)
            Button(model.infoRunning ? L10n.t("updates.info.running") : L10n.t("updates.info.run")) { Task { await model.readInfo() } }
              .disabled(model.infoRunning)
              .accessibilityIdentifier("updates.info")
            if let info = model.info {
              RunOutput(text: info, label: L10n.t("updates.info.heading"), identifier: "updates.infoOutput")
            }
          }
        }
      }
    }
  }

  // MARK: The core

  private var coreSection: some View {
    Section {
      // On a row that is always there: a Form's identifier does not reach the accessibility tree.
      VStack(alignment: .leading, spacing: 4) {
        if let core = model.core {
          Text(commitsLine(core)).monospacedDigit()
        } else {
          checkingLine
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.updates")

      // Read from git rather than from the last result: a half-finished merge is there after the
      // page was left, and this is the way out of it (QuartzControl's banner, as on Git-Sync).
      if let operation = model.git?.inProgress {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
          Text(inProgressText(operation)).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          if operation == .merge {
            Button(L10n.t("updates.core.abortMerge")) { Task { await model.abortMerge() } }
              .disabled(model.coreBusy)
              .accessibilityIdentifier("updates.abortMerge")
          }
        }
        .accessibilityElement(children: .contain)
      }

      // The one place outside the note where an unfinished run's packages are named; the run's own
      // output is gone once the app quits. No packages is its own sentence: npm failed then.
      if let core = model.core, core.state == .pending {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("updates.core.pendingHeading")).fontWeight(.medium)
            Text(pendingDetail(core.pendingPackages ?? []))
              .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityElement(children: .combine)
      }

      HStack(spacing: 8) {
        // Only a positive "you already have it" disables it: "Nicht prüfbar" says nothing about
        // whether the update works, and "Nicht abgeschlossen" is what it finishes.
        Button(L10n.t("updates.core.runUpdate")) { Task { await model.runCore(window: unsaved?.window) } }
          .disabled(model.coreBusy || model.core?.state == .upToDate)
          .accessibilityIdentifier("updates.runCore")
        if model.coreBusy {
          ProgressView().controlSize(.small)
          Note(L10n.t("updates.core.running"))
        }
      }

      if !model.notesAhead.isEmpty, model.coreResult == nil {
        ReleaseNotesView(sections: model.notesAhead, identifier: "updates.notesAhead")
      }

      if let result = model.coreResult {
        OutcomeTitle(title: result.title, success: result.success)
        if !result.conflicts.isEmpty {
          VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("updates.core.conflictHeading")).fontWeight(.medium)
            ForEach(result.conflicts, id: \.self) { file in
              Text(verbatim: "• \(file)").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
          }
          .accessibilityElement(children: .combine)
        }
        RunOutput(text: result.output, label: L10n.t("updates.core.output"), identifier: "updates.coreOutput")
        if let snapshotId = result.snapshotId {
          // After a failed merge the way back to the state before it is the one thing needed.
          Button(L10n.t("updates.core.openSnapshot")) {
            snapshotToOpen = snapshotId
            openPage(.backups)
          }
          .buttonStyle(.link)
        }
        if !model.notesDone.isEmpty { ReleaseNotesView(sections: model.notesDone, identifier: "updates.notesDone") }
        if let doctor = model.doctorAfter { afterUpdate(doctor) }
      }
    } header: {
      SectionHeader(title: L10n.t("updates.core.heading"), symbol: "shippingbox") {
        if let core = model.core { stateBadge(core.state) }
      }
    }
  }

  /// Quartz's check after the update, with what can be done about it here.
  @ViewBuilder private func afterUpdate(_ doctor: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.t("updates.core.doctorHeading")).fontWeight(.medium)
      let report = PluginDoctorReport.parse(doctor)
      // Review 2026-11-11 (2), N2: "only warns" stood above Quartz's errors as well.
      Note(!report.ran ? L10n.t("updates.core.doctorFailed")
           : report.hasErrors ? L10n.t("updates.core.doctorErrors") : L10n.t("updates.core.doctorHint"))
      RunOutput(text: doctor, label: L10n.t("updates.core.doctorHeading"), identifier: "updates.doctorAfter")
      let intended = report.intendedPlugins
      if !intended.isEmpty { Note(L10n.t("updates.core.doctorIntended", ["names": intended.joined(separator: ", ")])) }
      BuiltinMigration(project: project, pending: model.pendingMigrations) { await model.checkAfterUpdate() }
      if model.markdownOrderProblem {
        Label(L10n.t("pluginsInstalled.markdownOrder"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      }
      Button(L10n.t("updates.core.openPlugins")) { openPage(.plugins) }.buttonStyle(.link)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("updates.afterUpdate")
  }

  private var checkingLine: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Note(L10n.t("dashboard.updates.checking"))
    }
  }

  private func commitsLine(_ core: CoreUpdate.Status) -> String {
    var line: String
    if let installed = model.versions?.installed, let latest = model.versions?.latest {
      line = L10n.t("updates.core.versions", ["current": installed, "currentCommit": Self.short(core.currentCommit),
                                              "latest": latest, "latestCommit": Self.short(core.latestCommit)])
    } else if let installed = model.versions?.installed {
      // The project's own package.json answers without the network; only the newest is unknown
      // then (measured offline on a 5.1 copy, 2026-11-11: the line said "Installiert: —").
      line = L10n.t("updates.core.installedVersion", ["current": installed, "latest": Self.short(core.latestCommit)])
    } else {
      line = L10n.t("updates.core.commits", ["current": Self.short(core.currentCommit), "latest": Self.short(core.latestCommit)])
    }
    // Asked of the number, not the state: "pending" wins over "behind", and a project half updated
    // and behind should say both. `> 0` because "upToDate" carries a zero.
    if let missing = core.missingCommits, missing > 0 {
      line += " · " + L10n.t("updates.core.missing", ["count": String(missing)], count: missing)
    }
    return line
  }

  private func pendingDetail(_ packages: [String]) -> String {
    packages.isEmpty ? L10n.t("updates.core.pendingInstallDetail")
      : L10n.t("updates.core.pendingDetail", ["packages": packages.joined(separator: ", ")])
  }

  private func inProgressText(_ operation: GitStatus.Operation) -> String {
    switch operation {
    case .merge: L10n.t("gitSync.inProgress.merge")
    case .rebase: L10n.t("gitSync.inProgress.rebase")
    case .cherryPick: L10n.t("gitSync.inProgress.cherry-pick")
    case .revert: L10n.t("gitSync.inProgress.revert")
    }
  }

  // MARK: Plugins

  private var pluginsSection: some View {
    Section {
      Note(L10n.t("updates.plugins.hint"))
      if let plugins = model.plugins {
        if plugins.isEmpty {
          Note(L10n.t("updates.plugins.none"))
        } else {
          ForEach(plugins, id: \.name) { plugin in pluginRow(plugin) }
          HStack(spacing: 8) {
            Button(L10n.t("updates.plugins.updateAll")) { Task { await model.updatePlugin(nil) } }
              .disabled(model.pluginRun != nil || model.actionablePlugins.isEmpty)
              .accessibilityIdentifier("updates.updateAll")
            if model.pluginRun == .all {
              ProgressView().controlSize(.small)
              Note(L10n.t("updates.plugins.running"))
            }
          }
        }
      } else {
        checkingLine
      }
      if let result = model.pluginResult {
        OutcomeTitle(title: result.title, success: result.success)
        RunOutput(text: result.output, label: L10n.t("updates.plugins.output"), identifier: "updates.pluginOutput")
      }
    } header: {
      SectionHeader(title: L10n.t("updates.plugins.heading"), symbol: ProjectPage.plugins.symbol) {
        let behind = (model.plugins ?? []).filter { $0.state == .behind }.count
        if behind > 0 { StateBadge(text: String(behind), color: .orange) }
      }
    }
  }

  private func pluginRow(_ plugin: PluginUpdates.Status) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(plugin.name).font(.system(.body, design: .monospaced))
        if plugin.state == .local {
          WordBadge(text: L10n.t("updates.plugins.local"))
        } else {
          Text(verbatim: "\(Self.short(plugin.installedCommit?.stringValue)) → \(Self.short(plugin.latestCommit))")
            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      switch plugin.state {
      case .behind, .unknown:
        if plugin.state == .unknown { stateBadge(CoreUpdate.Status.State.unknown) }
        if model.pluginRun == .one(plugin.name) {
          ProgressView().controlSize(.small)
          Note(L10n.t("updates.plugins.running"))
        } else {
          Button(L10n.t("updates.plugins.update")) { Task { await model.updatePlugin(plugin.name) } }
            .disabled(model.pluginRun != nil)
            .accessibilityLabel("\(L10n.t("updates.plugins.update")): \(plugin.name)")
        }
      case .upToDate:
        stateBadge(CoreUpdate.Status.State.upToDate)
      case .local:
        EmptyView()
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("updates.plugin.\(plugin.name)")
  }

  // MARK: Pieces

  /// Four answers, four words. "Nicht prüfbar" is never the green one: it is what a check that
  /// never reached the remote says.
  private func stateBadge(_ state: CoreUpdate.Status.State) -> some View {
    switch state {
    case .upToDate: StateBadge(text: L10n.t("updates.upToDate"), color: .green)
    case .behind: StateBadge(text: L10n.t("updates.updateAvailable"), color: .orange)
    case .pending: StateBadge(text: L10n.t("updates.unfinished"), color: .orange)
    case .unknown: StateBadge(text: L10n.t("updates.checkFailed"), color: .gray)
    }
  }

  private func stateBadge(_ state: PluginUpdates.Status.State) -> some View {
    stateBadge(state == .upToDate ? CoreUpdate.Status.State.upToDate : .unknown)
  }

  /// The first seven characters of a commit, "—" for none.
  static func short(_ commit: String?) -> String {
    guard let commit, !commit.isEmpty else { return "—" }
    return String(commit.prefix(7))
  }
}

/// Quartz's release notes between two versions, as its CHANGELOG.md has them (Markdown left as
/// text), folded: they run to a few hundred lines from 5.0 to 5.1.
private struct ReleaseNotesView: View {
  let sections: [ReleaseNotes.Section]
  let identifier: String
  @State private var open = false

  /// Inline Markdown (code, emphasis, links) as text, line breaks kept; a changesets heading
  /// ("### Minor Changes") loses its hashes. What does not parse stays the plain text.
  static func rendered(_ body: String) -> AttributedString {
    let text = body.replacing(#/(?m)^#{1,6} /#, with: "")
    return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }

  var body: some View {
    DisclosureGroup(isExpanded: $open) {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(sections, id: \.version) { section in
            Text(verbatim: "Quartz \(section.version)").font(.headline)
            Text(Self.rendered(section.body)).font(.callout).textSelection(.enabled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
      }
      .frame(maxHeight: 320)
      .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
    } label: {
      Text(L10n.t("updates.core.releaseNotes", ["versions": sections.map(\.version).joined(separator: ", ")]))
    }
    .accessibilityIdentifier(identifier)
  }
}
