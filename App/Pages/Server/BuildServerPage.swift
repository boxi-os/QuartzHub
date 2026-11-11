import AppKit
import QuartzHubCore
import SwiftUI

/// Vorschau & Build: QuartzControl's `BuildServer.tsx` as one grouped form. The dev server leads
/// with its address (live when it runs, muted saying what it will be when not), then its facts,
/// settings, live preview and console; then every Quartz server on this Mac; then the one-off build
/// with the folder it writes to and its console.
struct BuildServerPage: View {
  let project: ProjectContext

  @State private var model: BuildServerModel
  @State private var monitor = BuildMonitor.shared
  @State private var copied = false
  @FocusState private var outputDirFocused: Bool
  @Environment(\.openPage) private var openPage

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: BuildServerModel(project: project))
  }

  private var status: BuildService.ServerStatus { monitor.status(project.id) }
  private var activity: BuildActivity? { monitor.activity(project.id) }
  private var logs: ProjectLogs { monitor.logs(project.id) }
  private var running: Bool { status.state == .running }
  /// Not "not stopped": after the server died (`error`) is exactly when the port needs changing.
  private var serverActive: Bool { [.starting, .running, .stopping].contains(status.state) }
  private var liveOptions: BuildService.ServerOptions { running ? status.options ?? model.options : model.options }
  /// Locked, the fields show what the server really took; unlocked, they are the form again.
  private var formOptions: BuildService.ServerOptions { serverActive ? status.options ?? model.options : model.options }
  private var address: String { "http://\(liveOptions.host.isEmpty ? "localhost" : liveOptions.host):\(liveOptions.port)" }
  /// Only this Mac's server is shown inside; a preview behind a tunnel keeps the link.
  private var embeddable: Bool { running && liveOptions.host.isEmpty }
  private var buildRunning: Bool { activity?.kind == .build }
  private var building: Bool { model.clicked || buildRunning }

  var body: some View {
    PageScaffold(page: .server) {
      // The clock of the drawing, not of the last tick: drawn between two ticks, a folder written
      // a moment ago was newer than the tick and read "in 13 Sekunden" (measured 2026-11-09).
      TimelineView(.periodic(from: .now, by: 30)) { context in
        let now = max(context.date, Date())
        Form {
          serverSection(now: now)
          DiscoveredServersSection(ports: [liveOptions.port, liveOptions.wsPort]) {
            Task { await BuildMonitor.shared.refresh(project.id, from: AppServices.shared.builds) }
          }
          buildSection(now: now)
        }
        .formStyle(.grouped)
      }
      .task { await model.load() }
      // A build that ends while the page is open, started here or anywhere else, changed the folder.
      .onChange(of: buildRunning) { _, running in
        if !running { Task { await model.refreshOutput() } }
      }
    } inspector: {
      InspectorPageContext(page: .server) {
        Section {
          Text(L10n.t("projectLayout.descriptions.server")).foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: Dev server

  private func serverSection(now: Date) -> some View {
    Section {
      addressRow
      Note(serverFacts(now: now))
      if let error = ProjectAttention.serverErrorText(status) {
        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
      }
      if model.missingIndex {
        HStack(alignment: .firstTextBaseline) {
          Text(L10n.t("buildServer.noIndex")).font(.callout).foregroundStyle(.orange)
          Button(L10n.t("buildServer.noIndexLink")) { openPage(.config, tab: ConfigPage.Tab.site.rawValue) }.buttonStyle(.link).font(.callout)
        }
      }
      if let activity, activity.kind != .build { ActivityLine(activity: activity) }
      // Only what applies now; "Stoppen" from `starting` on, because a start waits for a build
      // into the same folder and that is when someone wants out.
      HStack {
        if status.state == .stopped || status.state == .error {
          Button(L10n.t("buildServer.start"), systemImage: "play.fill", action: model.start)
            .accessibilityIdentifier("server.start")
        } else {
          Button(L10n.t("buildServer.restart"), systemImage: "arrow.clockwise", action: model.restart)
            .disabled(!running)
          Button(L10n.t("buildServer.stop"), systemImage: "stop.fill", role: .destructive, action: model.stop)
            .disabled(status.state == .stopping)
            .accessibilityIdentifier("server.stop")
        }
      }
      DisclosureGroup(isExpanded: $model.optionsOpen) {
        optionsFields
      } label: {
        Label(L10n.t("buildServer.serverOptions"), systemImage: "slider.horizontal.3")
      }
      if embeddable { preview }
      LogConsole(lines: logs.server, label: L10n.t("buildServer.serverLogLabel"), identifier: "server.log.server") {
        monitor.clearLog(project.id, .server)
      }
    } header: {
      SectionHeader(title: L10n.t("buildServer.devServer"), symbol: ProjectPage.server.symbol) {
        StateBadge(text: ServerStateText.text(status.state), color: running ? .green : status.state == .error ? .red : .secondary)
      }
    }
  }

  private var addressRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Group {
        if running, let url = URL(string: address) {
          Link(destination: url) {
            Label(address, systemImage: "arrow.up.right.square").font(.title3.weight(.semibold))
          }
          .help(L10n.t("common.openInBrowser"))
        } else {
          Text(address).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
        }
      }
      .accessibilityIdentifier("page.server")
      Button(action: copyAddress) {
        Label(L10n.t("common.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
      }
      .buttonStyle(.borderless)
      .font(.callout)
    }
  }

  private func copyAddress() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(address, forType: .string)
    copied = true
    // The tick is not a word: the copy is also said.
    Announce.post(L10n.t("common.copied", ["value": address]))
    Task {
      try? await Task.sleep(for: .seconds(2))
      copied = false
    }
  }

  private func serverFacts(now: Date) -> String {
    guard running else { return L10n.t("buildServer.devServerHint") }
    var facts = L10n.t("buildServer.startedAgo", ["since": Formats.relative(status.startedAt, now: now) ?? "–"])
    facts += " · " + L10n.t("buildServer.wsPort") + " \(liveOptions.wsPort)"
    if let pid = status.pid { facts += " · PID \(pid)" }
    return facts + " · " + L10n.t("buildServer.autoReload")
  }

  @ViewBuilder private var optionsFields: some View {
    // One row each, as a grouped form lays a field out: its label left, its value right.
    TextField(L10n.t("buildServer.port"), value: Binding(get: { formOptions.port }, set: { model.options.port = $0 }),
              format: .number.grouping(.never))
      .disabled(serverActive)
      .accessibilityIdentifier("server.port")
    TextField(L10n.t("buildServer.wsPort"), value: Binding(get: { formOptions.wsPort }, set: { model.options.wsPort = $0 }),
              format: .number.grouping(.never))
      .disabled(serverActive)
    FormField(hint: serverActive ? L10n.t("buildServer.optionsLocked")
                : model.options.host.isEmpty ? L10n.t("buildServer.portsAuto") : L10n.t("buildServer.portsFixedBehindTunnel")) {
      TextField(L10n.t("buildServer.remoteDevHost"), text: Binding(get: { formOptions.host }, set: { model.options.host = $0 }),
                prompt: Text(L10n.t("buildServer.remoteDevHostPlaceholder")))
        .disabled(serverActive)
    }
  }

  /// At real CSS pixels: switching the width resizes the view and keeps where the reader had gone in
  /// the site; only "Vorschau neu laden" (and a new address) loads it again.
  @ViewBuilder private var preview: some View {
    let width = PreviewWidth.points(model.previewMode, widths: model.breakpoints)
    DisclosureGroup(isExpanded: $model.previewOpen) {
      HStack {
        Picker(L10n.t("buildServer.viewport.label"), selection: $model.previewMode) {
          ForEach(PreviewWidth.Mode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        Text(PreviewWidth.text(width)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
        Spacer()
        Button(L10n.t("buildServer.reloadPreview"), systemImage: "arrow.clockwise") { model.previewNonce += 1 }
          .buttonStyle(.borderless)
      }
      if let url = URL(string: address) {
        ScrollView(.horizontal) {
          HStack(spacing: 0) {
            SitePreview(url: url, label: L10n.t("buildServer.livePreview"))
              .id("\(address)#\(model.previewNonce)")
              .frame(width: width.map { CGFloat($0) })
          }
          .containerRelativeFrame(.horizontal) { length, _ in max(length, width.map { CGFloat($0) } ?? length) }
        }
        .frame(height: 560)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      }
    } label: {
      Text(L10n.t("buildServer.livePreview"))
    }
  }

  // MARK: One-off build

  private func buildSection(now: Date) -> some View {
    Section {
      HStack(alignment: .firstTextBaseline) {
        Note(L10n.t("buildServer.oneOffBuildHint"))
        Spacer(minLength: 12)
        Button(building ? L10n.t("buildServer.building") : L10n.t("buildServer.buildNow"), systemImage: "hammer") {
          Task { await model.runBuild() }
        }
        .disabled(building)
        .accessibilityIdentifier("server.build")
      }
      if let activity, activity.kind == .build { ActivityLine(activity: activity) }
      outputRows(now: now)
      outputDirField
      if let result = model.buildResult {
        Text(model.resultLine(result)).font(.callout).foregroundStyle(result.success ? .green : .red)
      }
      LogConsole(lines: logs.build, label: L10n.t("buildServer.buildLogLabel"), identifier: "server.log.build") {
        monitor.clearLog(project.id, .build)
      }
    } header: {
      SectionHeader(title: L10n.t("buildServer.oneOffBuild"), symbol: "hammer") { EmptyView() }
    }
  }

  /// What is in the output folder now, read from the files: nothing records that a build happened.
  @ViewBuilder private func outputRows(now: Date) -> some View {
    switch model.output {
    case nil:
      ProgressView().controlSize(.small)
    case .success(let info):
      VStack(alignment: .leading, spacing: 4) {
        if info.exists {
          Metric(L10n.t("buildServer.lastBuilt", ["when": Formats.relative(info.builtDate, now: now) ?? "–"]))
          Note(L10n.t("buildServer.outputFiles", ["count": String(info.fileCount)], count: info.fileCount) + " · " + Formats.bytes(info.sizeBytes))
        } else {
          Metric(L10n.t("buildServer.neverBuilt"), muted: true)
        }
        HStack(alignment: .firstTextBaseline) {
          Text(info.dir).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
          // Only inside the project: opening hands the path to the system, which would launch an
          // app bundle as readily as show a folder.
          if info.exists && Self.isInside(project.path, info.dir) {
            Button(L10n.t("buildServer.openFolder"), systemImage: "folder") {
              ExternalOpen.open(URL(fileURLWithPath: info.dir)) // path boundary
            }
            .buttonStyle(.link)
            .font(.caption)
          }
        }
      }
      .accessibilityIdentifier("server.output")
    case .failure(let unreadable):
      Metric("–", muted: true)
      Note(unreadable.path)
    }
  }

  @ViewBuilder private var outputDirField: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        TextField(L10n.t("buildServer.exportDir"), text: $model.outputDir, prompt: Text(L10n.t("buildServer.exportDirPlaceholder")))
          .focused($outputDirFocused)
          .onSubmit { Task { await model.commitOutputDir(model.outputDir) } }
          .accessibilityIdentifier("server.outputDir")
        Button(L10n.t("common.select")) {
          if let folder = ProjectsModel.pickFolder(start: project.path) { Task { await model.commitOutputDir(folder) } }
        }
        if !model.outputDir.isEmpty {
          Button(L10n.t("buildServer.reset")) { Task { await model.commitOutputDir("") } }
        }
      }
      .disabled(building)
      .onChange(of: outputDirFocused) { _, focused in
        if !focused { Task { await model.commitOutputDir(model.outputDir) } }
      }
      Text(L10n.t("buildServer.exportDirShared") + " " + L10n.t("buildServer.exportDirWipes"))
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      // `quartz build` empties its folder first; a folder holding something that is not a build
      // is about to lose it. The build asks again before it runs (BuildOutputGuard).
      if case .success(let info)? = model.output, info.fileCount > 0, !info.looksLikeBuild {
        Text(L10n.t("buildServer.exportDirForeign", ["count": String(info.fileCount)], count: info.fileCount))
          .font(.caption).foregroundStyle(.orange)
      }
      if let error = model.outputDirError {
        Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("server.outputDir.error")
      }
    }
  }

  /// QuartzControl's `isInsideDirectory`: the folder itself, or below it.
  static func isInside(_ parent: String, _ child: String) -> Bool {
    if child == parent { return true }
    return child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
  }
}
