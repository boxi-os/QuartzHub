import AppKit
import QuartzHubCore
import SwiftUI

/// Übersicht: QuartzControl's `ProjectDashboard.tsx` as one grouped form. Its tiles become sections
/// in the same order (Dev-Server, Die Seite, Git-Sync, Plugins, Gestaltung, Build, Veröffentlichen,
/// Updates, Snapshots), each leading with the one number or name it is about and ending with a link
/// to the page that owns it. The band "Handlungsbedarf" stands above them; the three things worth
/// doing from here are in the toolbar.
struct OverviewPage: View {
  let project: ProjectContext

  @State private var model: OverviewModel
  @State private var monitor = BuildMonitor.shared
  @Environment(\.openPage) private var openPage
  /// Read by Konfiguration and Stile: the tab an entry under "Handlungsbedarf" leads to
  /// (QuartzControl's `config?tab=site`), the way Updates hands Snapshots its snapshot. The same
  /// type as on those pages (a key with two types left the window blank, measured on Snapshots).
  @SceneStorage("config.tab") private var configTab = ConfigPage.Tab.site.rawValue
  @SceneStorage("styles.tab") private var stylesTab = StylesModel.Tab.basics.rawValue

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: OverviewModel(project: project))
  }

  private var server: BuildService.ServerStatus { monitor.status(project.id) }
  private var activity: BuildActivity? { monitor.activity(project.id) }
  private var buildRunning: Bool { activity?.kind == .build }

  var body: some View {
    PageScaffold(page: .overview) {
      // Relative ages ("vor 3 Minuten") are worked out when drawn; without a nudge they stay what
      // they were when something else last changed (QuartzControl measured "vor 1 Sekunde" 55 s on).
      // The clock of the drawing, not of the last tick: something newer than the tick read "in 13
      // Sekunden" (measured on Vorschau & Build, 2026-11-09).
      TimelineView(.periodic(from: .now, by: 30)) { context in
        form(now: max(context.date, Date()))
      }
      .toolbar { actions }
      .task { await model.load() }
      .task { await model.checkUpdates() }
      // A build that ends while the page is open changes the folder the Build section describes.
      .onChange(of: buildRunning) { _, running in
        if !running { Task { await model.loadBuild() } }
      }
      .alert(model.failure ?? "", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
        Button(L10n.t("shell.alert.ok"), role: .cancel) {}
      }
    } inspector: {
      InspectorPageContext(page: .overview) {
        Section {
          Text(L10n.t("projectLayout.descriptions.overview")).foregroundStyle(.secondary)
          LabeledContent(L10n.t("shell.projects.folder")) {
            Text(project.path).font(.caption).textSelection(.enabled).multilineTextAlignment(.trailing)
          }
          Button(L10n.t("dashboard.openProjectFolder"), systemImage: "folder", action: openFolder)
        }
      }
    }
  }

  // MARK: The form

  private func form(now: Date) -> some View {
    Form {
      attentionSection
      serverSection(now: now)
      siteSection
      gitSection(now: now)
      pluginsSection
      designSection
      buildSection(now: now)
      publishSection
      updatesSection
      snapshotsSection(now: now)
    }
    .formStyle(.grouped)
  }

  private func open(_ issue: ProjectAttention.Issue) {
    guard let page = ProjectPage(rawValue: issue.page) else { return }
    if let tab = issue.tab {
      switch page {
      case .config where ConfigPage.Tab(rawValue: tab) != nil: configTab = tab
      case .styles where StylesModel.Tab(rawValue: tab) != nil: stylesTab = tab
      default: break
      }
    }
    openPage(page)
  }

  /// The page's reads with the server as it is now: the monitor follows it, the model never read it,
  /// and a server that died on start left the band at "Alles ok" (measured 2026-11-09).
  private var reads: ProjectAttention.Reads {
    var reads = model.attention
    reads.server = server
    return reads
  }

  @ViewBuilder private var attentionSection: some View {
    let issues = ProjectAttention.issues(reads)
    if !issues.isEmpty {
      Section {
        ForEach(issues) { issue in
          IssueRow(issue: issue, installing: model.busy.contains(.install)) {
            Task { await model.installDependencies() }
          } open: {
            open(issue)
          }
        }
      } header: {
        Label {
          Text(L10n.t("dashboard.attention.title")) + Text(" (\(issues.count))").foregroundStyle(.secondary)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .accessibilityIdentifier("overview.attention")
      }
    } else if ProjectAttention.allGood(reads) {
      Section {
        Label(L10n.t("dashboard.attention.allGood"), systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityIdentifier("overview.allGood")
      }
    }
  }

  private func serverSection(now: Date) -> some View {
    Section {
      // On a row that is always there: a Form's identifier does not reach the accessibility tree.
      Group {
        if server.state == .running, let options = server.options,
           let url = URL(string: "http://\(options.host.isEmpty ? "localhost" : options.host):\(options.port)") {
          Link(destination: url) {
            Label(url.absoluteString, systemImage: "arrow.up.right.square").font(.title3.weight(.semibold))
          }
          .help(L10n.t("common.openInBrowser"))
        } else {
          Metric(L10n.t("dashboard.noPreview"), muted: true)
        }
      }
      .accessibilityIdentifier("page.overview")
      if let activity, activity.kind != .build { ActivityLine(activity: activity) }
      Note(serverFacts(now: now))
      // "Stoppen" from `starting` on: a start waits for a one-off build into the same folder, and
      // that whole build had no way out. Only `stopping` disables it.
      HStack {
        if server.state == .stopped || server.state == .error {
          Button(L10n.t("dashboard.start"), systemImage: "play.fill", action: model.startServer)
        } else {
          Button(L10n.t("dashboard.stop"), systemImage: "stop.fill", action: model.stopServer)
            .disabled(server.state == .stopping)
        }
        Button(L10n.t("dashboard.restart"), systemImage: "arrow.clockwise", action: model.restartServer)
          .disabled(server.state != .running)
      }
    } header: {
      SectionHeader(title: L10n.t("dashboard.devServer"), symbol: ProjectPage.server.symbol) {
        StateBadge(text: ServerStateText.text(server.state), color: server.state == .running ? .green : server.state == .error ? .red : .secondary)
      }
    } footer: {
      PageLink(page: .server)
    }
  }

  private func serverFacts(now: Date) -> String {
    guard server.state == .running else {
      return ProjectAttention.serverErrorText(server) ?? L10n.t("dashboard.serverIdleHint")
    }
    var facts = L10n.t("dashboard.startedAgo", ["since": Formats.relative(server.startedAt, now: now) ?? "–"])
    if let options = server.options { facts += " · WebSocket \(options.wsPort)" }
    if let pid = server.pid { facts += " · PID \(pid)" }
    return facts
  }

  /// All four rows are fields of Konfiguration ▸ Website, so the link names that page.
  private var siteSection: some View {
    let config = model.attention.config
    let baseUrl = ProjectAttention.baseUrl(config)
    return Section {
      LabeledContent(L10n.t("dashboard.pageTitle"), value: nonEmpty(config?.configuration["pageTitle"]?.stringValue))
      LabeledContent(L10n.t("dashboard.baseUrl")) {
        if baseUrl.isEmpty {
          StateBadge(text: L10n.t("dashboard.notSet"), color: .orange)
        } else {
          Text(baseUrl).font(.body.monospaced()).textSelection(.enabled)
        }
      }
      LabeledContent(L10n.t("dashboard.locale"), value: nonEmpty(config?.configuration["locale"]?.stringValue))
      LabeledContent(L10n.t("dashboard.contentFolder")) { contentValue }
    } header: {
      SectionHeader(title: L10n.t("dashboard.site"), symbol: ProjectPage.config.symbol) { EmptyView() }
    } footer: {
      PageLink(page: .config, configTab: .site)
    }
  }

  private func nonEmpty(_ text: String?) -> String {
    guard let text, !text.isEmpty else { return "–" }
    return text
  }

  @ViewBuilder private var contentValue: some View {
    if let content = model.attention.content {
      if !content.exists {
        StateBadge(text: L10n.t("dashboard.notPresent"), color: .orange)
      } else if content.isSymlink {
        if content.targetExists == false {
          StateBadge(text: L10n.t("dashboard.targetMissing"), color: .red)
        } else {
          Label(content.symlinkTarget ?? "", systemImage: "link").font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
        }
      } else {
        let count = content.fileCount ?? 0
        Text(L10n.t("dashboard.realFolderFiles", ["count": String(count)], count: count))
      }
    } else {
      Text("–")
    }
  }

  /// Read straight from git: no token, no network.
  private func gitSection(now: Date) -> some View {
    let git = model.attention.git
    return Section {
      if let git {
        if git.readError != nil {
          Metric(L10n.t("dashboard.git.unreadable"), muted: true)
          Note(L10n.t("dashboard.git.unreadableHint"))
        } else if !git.isRepo {
          Metric(L10n.t("dashboard.git.noRepo"), muted: true)
          Note(L10n.t("dashboard.git.noRepoHint"))
        } else {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("↑ \(git.ahead)").monospacedDigit()
            Text("↓ \(git.behind)").monospacedDigit().foregroundStyle(.secondary)
            if git.conflictCount > 0 {
              Text(L10n.t("dashboard.git.conflicts", ["count": String(git.conflictCount)], count: git.conflictCount))
                .font(.callout.weight(.medium)).foregroundStyle(.red)
            }
            if git.upstream == nil { Text(L10n.t("dashboard.git.noUpstream")).font(.callout).foregroundStyle(.secondary) }
          }
          .font(.title3.weight(.semibold))
          .accessibilityElement(children: .combine)
          Text("\(git.changeCount) ").fontWeight(.semibold).monospacedDigit() + Text(L10n.t("dashboard.git.uncommitted")).foregroundStyle(.secondary)
          if let commit = git.lastCommit {
            Note("„\(commit.subject)“ · \(Formats.relative(Formats.date(iso: commit.date), now: now) ?? "–") · \(commit.author)")
              .lineLimit(1)
          }
        }
      } else {
        Metric("–", muted: true)
      }
    } header: {
      SectionHeader(title: L10n.t("projectLayout.tabs.sync"), symbol: ProjectPage.sync.symbol) {
        if let operation = git?.inProgress {
          StateBadge(text: L10n.t("dashboard.git.inProgress", ["operation": operation.rawValue]), color: .red)
        } else if let branch = git?.branch {
          Text(branch).font(.callout.monospaced())
        }
      }
    } footer: {
      PageLink(page: .sync)
    }
  }

  private var pluginsSection: some View {
    Section {
      if let config = model.attention.config {
        let total = config.plugins.count
        let active = config.plugins.filter(\.enabled).count
        Metric(String(active), note: L10n.t("dashboard.plugins.ofTotal", ["total": String(total)]))
        Note(total - active > 0 ? L10n.t("dashboard.plugins.disabled", ["count": String(total - active)])
             : L10n.t("dashboard.plugins.allEnabled"))
      } else {
        ProgressView().controlSize(.small)
      }
    } header: {
      SectionHeader(title: L10n.t("projectLayout.tabs.plugins"), symbol: ProjectPage.plugins.symbol) { EmptyView() }
    } footer: {
      PageLink(page: .plugins)
    }
  }

  /// The active theme is no field of its own: it is the enabled `@quartz-themes/*` plugin's
  /// `theme` option (the convention of quartz-themes/core, as Stile ▸ Theme reads it).
  private var activeTheme: String? {
    let plugin = model.attention.config?.plugins.first { plugin in
      guard plugin.enabled, case .string(let source)? = plugin.source else { return false }
      return source.hasPrefix("@quartz-themes/")
    }
    return plugin?.object["options"]?["theme"]?.stringValue
  }

  private var designSection: some View {
    Section {
      Metric(activeTheme ?? L10n.t("dashboard.design.stockTheme"))
      Note(L10n.t("dashboard.design.frames", ["count": String(model.frameCount ?? 0)], count: model.frameCount ?? 0) + " · "
           + L10n.t("dashboard.design.stylesheets", ["count": String(model.stylesheetCount ?? 0)], count: model.stylesheetCount ?? 0))
      switch model.attention.scss {
      case nil: ProgressView().controlSize(.small)
      case .ok?: StateBadge(text: L10n.t("dashboard.design.cssOk"), color: .green)
      case .error?: StateBadge(text: L10n.t("dashboard.design.cssError"), color: .red)
      case .unavailable?: StateBadge(text: L10n.t("dashboard.design.cssUnchecked"), color: .secondary)
      }
    } header: {
      SectionHeader(title: L10n.t("projectLayout.groups.design"), symbol: ProjectPage.styles.symbol) { EmptyView() }
    } footer: {
      PageLink(page: .styles)
    }
  }

  /// Nothing records that a build happened: this is the output folder as it is on disk.
  private func buildSection(now: Date) -> some View {
    Section {
      if buildRunning, let activity {
        Metric(L10n.t("dashboard.build.running"))
        ActivityLine(activity: activity)
      } else {
        switch model.build {
        case nil:
          ProgressView().controlSize(.small)
        case .success(let info) where info.exists:
          Metric(Formats.relative(info.builtDate, now: now) ?? "–")
          Note(L10n.t("dashboard.build.files", ["count": String(info.fileCount)], count: info.fileCount) + " · " + Formats.bytes(info.sizeBytes))
        case .success:
          Metric(L10n.t("dashboard.build.never"), muted: true)
          Note(L10n.t("dashboard.build.neverHint"))
        case .failure(let unreadable):
          Metric("–", muted: true)
          Note(unreadable.path)
        }
      }
      if let message = model.buildMessage { Note(message) }
    } header: {
      SectionHeader(title: L10n.t("dashboard.build.title"), symbol: "hammer") { EmptyView() }
    } footer: {
      PageLink(page: .server)
    }
  }

  private var publishSection: some View {
    Section {
      if let targets = model.targets, !targets.isEmpty {
        Metric(String(targets.count), note: L10n.t("dashboard.publish.targets", count: targets.count))
        ForEach(targets.prefix(3), id: \.id) { target in
          Note("\(target.name) · \(target.destination["type"]?.stringValue ?? "")").lineLimit(1)
        }
      } else if model.targets == nil {
        ProgressView().controlSize(.small)
      } else {
        Metric(L10n.t("dashboard.publish.none"), muted: true)
        Note(L10n.t("dashboard.publish.noneHint"))
      }
    } header: {
      SectionHeader(title: L10n.t("projectLayout.tabs.publish"), symbol: ProjectPage.publish.symbol) { EmptyView() }
    } footer: {
      PageLink(page: .publish)
    }
  }

  /// The one section that goes to the network.
  private var updatesSection: some View {
    let behind = model.pluginUpdates?.filter { $0.state == .behind }.count ?? 0
    let unknown = model.pluginUpdates?.filter { $0.state == .unknown }.count ?? 0
    let coreState = model.core?.state
    let count = (coreState == .behind || coreState == .pending ? 1 : 0) + behind
    return Section {
      if model.updatesPending {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Note(L10n.t("dashboard.updates.checking"))
        }
      } else {
        Metric(updatesHeadline(core: coreState, behind: behind), tint: coreState == .upToDate && behind == 0 ? .green : nil)
        Note(behind > 0 ? L10n.t("dashboard.updates.pluginsBehind", ["count": String(behind)], count: behind)
             : L10n.t("dashboard.updates.pluginsCurrent", ["count": String(model.pluginUpdates?.count ?? 0)], count: model.pluginUpdates?.count ?? 0))
        if unknown > 0 { Note(L10n.t("dashboard.updates.checkFailed", ["count": String(unknown)], count: unknown)) }
      }
    } header: {
      SectionHeader(title: L10n.t("projectLayout.tabs.updates"), symbol: ProjectPage.updates.symbol) {
        if !model.updatesPending && count > 0 { StateBadge(text: String(count), color: .orange) }
      }
    } footer: {
      PageLink(page: .updates)
    }
  }

  private func updatesHeadline(core: CoreUpdate.Status.State?, behind: Int) -> String {
    switch core {
    case .pending?: L10n.t("dashboard.updates.corePending")
    case .behind?: L10n.t("dashboard.updates.coreBehind")
    case .upToDate?: behind > 0 ? L10n.t("dashboard.updates.pluginsOnly") : L10n.t("dashboard.updates.allCurrent")
    default: L10n.t("dashboard.updates.unknown")
    }
  }

  private func snapshotsSection(now: Date) -> some View {
    Section {
      if let snapshots = model.snapshots, let newest = snapshots.first {
        Metric(String(snapshots.count), note: L10n.t("dashboard.backups.states", count: snapshots.count))
        Note(L10n.t("dashboard.backups.newest", ["when": Formats.relative(Formats.date(iso: newest.createdAt), now: now) ?? "–"]))
        Note(newest.label.isEmpty ? SnapshotKinds.title(newest.kind) : newest.label).lineLimit(1)
      } else if model.snapshots == nil {
        ProgressView().controlSize(.small)
      } else {
        Metric(L10n.t("dashboard.backups.none"), muted: true)
        Note(L10n.t("dashboard.backups.noneHint"))
      }
    } header: {
      SectionHeader(title: L10n.t("projectLayout.tabs.backups"), symbol: ProjectPage.backups.symbol) { EmptyView() }
    } footer: {
      PageLink(page: .backups)
    }
  }

  // MARK: Toolbar

  @ToolbarContentBuilder private var actions: some ToolbarContent {
    ToolbarItemGroup {
      Button(model.busy.contains(.build) || buildRunning ? L10n.t("dashboard.build.running") : L10n.t("dashboard.build.run"),
             systemImage: "hammer") {
        Task { await model.runBuild() }
      }
      .disabled(model.busy.contains(.build) || buildRunning)
      .help(L10n.t("dashboard.build.run"))
      .accessibilityIdentifier("overview.build")
      Button(model.busy.contains(.snapshot) ? L10n.t("dashboard.backups.saving") : L10n.t("dashboard.backups.save"),
             systemImage: "archivebox") {
        Task { await model.takeSnapshot() }
      }
      .disabled(model.busy.contains(.snapshot))
      .help(L10n.t("dashboard.backups.save"))
      Button(L10n.t("dashboard.openProjectFolder"), systemImage: "folder", action: openFolder)
        .help(L10n.t("dashboard.openProjectFolder"))
    }
  }

  private func openFolder() {
    NSWorkspace.shared.open(URL(fileURLWithPath: project.path)) // path boundary
  }
}

// MARK: Pieces

/// One line of the band: what is wrong, why, and the way to it (or "Installieren").
private struct IssueRow: View {
  let issue: ProjectAttention.Issue
  let installing: Bool
  let install: () -> Void
  let open: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: Self.symbol(issue.id))
        .foregroundStyle(issue.tone == .red ? .red : .orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(issue.title).fontWeight(.medium)
        if let detail = issue.detail {
          Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 8)
      if issue.installs {
        Button(installing ? L10n.t("dashboard.attention.dependenciesInstalling") : L10n.t("dashboard.attention.dependenciesInstall"),
               action: install)
          .disabled(installing)
      } else {
        Button(action: open) {
          Label(issue.linkLabel, systemImage: "chevron.right").labelStyle(TrailingIcon())
        }
        .buttonStyle(.link)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("overview.issue.\(issue.id)")
  }

  static func symbol(_ id: String) -> String {
    switch id {
    case "dependencies", "dependencies-unreadable": ProjectPage.plugins.symbol
    case "frames": ProjectPage.layout.symbol
    case "server": ProjectPage.server.symbol
    case "content", "content-missing", "no-index": "link"
    case "git-conflict", "git-progress", "git-unreadable": ProjectPage.sync.symbol
    case "scss": ProjectPage.styles.symbol
    case "core-update-pending": ProjectPage.updates.symbol
    case "baseurl": "globe"
    default: "exclamationmark.triangle"
    }
  }
}

/// The section's way to the page that owns it.
private struct PageLink: View {
  let page: ProjectPage
  /// "Die Seite" describes fields of Website, so it leads there rather than to whichever tab
  /// Konfiguration last had open (QuartzControl's `config?tab=site`, its 28th review, finding 5).
  var configTab: ConfigPage.Tab?
  @Environment(\.openPage) private var openPage
  @SceneStorage("config.tab") private var storedConfigTab = ConfigPage.Tab.site.rawValue

  var body: some View {
    HStack {
      Spacer()
      Button {
        if let configTab { storedConfigTab = configTab.rawValue }
        openPage(page)
      } label: {
        Label(page.title, systemImage: "chevron.right").labelStyle(TrailingIcon())
      }
      .buttonStyle(.link)
      .accessibilityIdentifier("overview.link.\(page.rawValue)")
    }
  }
}

/// A snapshot's kind in words (`backups.kinds.*`); an unknown kind as it stands.
enum SnapshotKinds {
  static func title(_ kind: String) -> String {
    switch kind {
    case "manual": L10n.t("backups.kinds.manual")
    case "configChange": L10n.t("backups.kinds.configChange")
    case "contentChange": L10n.t("backups.kinds.contentChange")
    case "coreUpdate": L10n.t("backups.kinds.coreUpdate")
    case "imported": L10n.t("backups.kinds.imported")
    case "pluginChange": L10n.t("backups.kinds.pluginChange")
    case "restore": L10n.t("backups.kinds.restore")
    case "styleChange": L10n.t("backups.kinds.styleChange")
    case "styleMigration": L10n.t("backups.kinds.styleMigration")
    default: kind
    }
  }
}
