import AppKit
import QuartzHubCore
import SwiftUI

/// Vorschau & Build: QuartzControl's `BuildServer.tsx` as a workspace (decisions/ui-ueberarbeitung.md,
/// Seitentypen). The site fills the middle, scaled from the width of a device (`ScaledSite`), with
/// both consoles in a panel under it that folds away. Server and build are the toolbar's; the
/// server's address and settings, the output folder and the other Quartz servers on this Mac are
/// the inspector's.
struct BuildServerPage: View {
  let project: ProjectContext

  @State private var model: BuildServerModel
  @State private var monitor = BuildMonitor.shared
  @State private var copied = false
  /// The room the preview has, for the scale it is shown at.
  @State private var previewRoom = 0.0
  @SceneStorage("server.previewFit") private var fit = true
  @SceneStorage("server.outputOpen") private var outputOpen = true
  /// The height of the output's head: a DisclosureGroup gives its content only the content's own
  /// height, so the consoles get the rest of the pane as a number (`PaneHeight`).
  @State private var outputHead: CGFloat = 20
  @FocusState private var outputDirFocused: Bool
  @Environment(\.openPage) private var openPage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
  /// The width the site is rendered at: Desktop wider than the tablet band, so it shows its desktop
  /// layout at any window width (before, it got the form row's ~570 pt and showed the phone's).
  private var renderWidth: Double {
    PreviewWidth.points(model.previewMode, widths: model.breakpoints) ?? ScaledSite.desktopWidth(tablet: model.breakpoints.tablet)
  }
  private var shownScale: Double { ScaledSite.scale(width: renderWidth, room: previewRoom, fit: fit) }

  var body: some View {
    PageScaffold(page: .server) {
      // The output's height is dragged at the grip above it, like the Plugins editors' panes.
      SplitPanes("server.output", initial: 0.72, topMin: 240, bottomMin: 140, collapsed: !outputOpen) {
        VStack(spacing: 0) {
          notices
          if embeddable, let url = URL(string: address) {
            previewBar
            Divider()
            ScaledSite(url: url, reloadKey: "\(address)#\(model.previewNonce)", width: renderWidth, fit: fit,
                       label: L10n.t("buildServer.livePreview"))
              .onGeometryChange(for: Double.self) { $0.size.width } action: { previewRoom = $0 }
              .transition(.opacity)
          } else {
            emptyPreview
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .transition(.opacity)
          }
        }
      } bottom: {
        PaneHeight { outputPanel(height: $0) }
      }
      .animation(reduceMotion ? nil : Motion.quick, value: embeddable)
      .toolbar { toolbar }
      .task { await model.load() }
      // A build that ends while the page is open, started here or anywhere else, changed the folder.
      .onChange(of: buildRunning) { _, running in
        if !running { Task { await model.refreshOutput() } }
      }
    } inspector: {
      // The clock of the drawing, not of the last tick: drawn between two ticks, a folder written
      // a moment ago was newer than the tick and read "in 13 Sekunden" (measured 2026-11-09).
      TimelineView(.periodic(from: .now, by: 30)) { context in
        let now = max(context.date, Date())
        InspectorPageContext(page: .server) {
          serverSection(now: now)
          DiscoveredServersSection(ports: [liveOptions.port, liveOptions.wsPort]) {
            Task { await BuildMonitor.shared.refresh(project.id, from: AppServices.shared.builds) }
          }
          buildSection(now: now)
        }
      }
    }
  }

  // MARK: Toolbar

  /// The build as a symbol, the server as the page's one prominent action.
  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button { Task { await model.runBuild() } } label: {
        Label(building ? L10n.t("buildServer.building") : L10n.t("buildServer.buildNow"), systemImage: "hammer")
      }
      .help(L10n.t("buildServer.oneOffBuildHint"))
      .disabled(building)
      .accessibilityIdentifier("server.build")
      if running {
        Button(action: model.restart) {
          Label(L10n.t("buildServer.restart"), systemImage: "arrow.clockwise")
        }
        .help(L10n.t("buildServer.restart"))
      }
    }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
      // Only what applies now; "Stoppen" from `starting` on, because a start waits for a build
      // into the same folder and that is when someone wants out.
      if status.state == .stopped || status.state == .error {
        Button(action: model.start) {
          Label(L10n.t("buildServer.start"), systemImage: "play.fill").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glassProminent)
        .accessibilityIdentifier("server.start")
      } else {
        Button(role: .destructive, action: model.stop) {
          Label(L10n.t("buildServer.stop"), systemImage: "stop.fill").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glassProminent)
        .disabled(status.state == .stopping)
        .accessibilityIdentifier("server.stop")
      }
    }
  }

  // MARK: The middle

  /// What needs saying before the site: the server's error, a missing start page.
  @ViewBuilder private var notices: some View {
    let error = ProjectAttention.serverErrorText(status)
    if error != nil || model.missingIndex {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if let error {
          Callout(.error) { Text(error).textSelection(.enabled) }
        }
        if model.missingIndex {
          Callout(.warning) {
            Text(L10n.t("buildServer.noIndex"))
            Button(L10n.t("buildServer.noIndexLink")) { openPage(.config, tab: ConfigPage.Tab.site.rawValue) }
              .buttonStyle(.link)
          }
        }
      }
      .padding(.horizontal, Spacing.page)
      .padding(.vertical, Spacing.s)
    }
  }

  /// Width, scale, fit or real pixels, reload, browser: the same controls as the editors' preview.
  /// In a narrow middle the two pickers become menus, then the scale goes: at 900 pt with the
  /// inspector, the full bar was wider than the column and pushed the sidebar out (measured).
  private var previewBar: some View {
    ViewThatFits(in: .horizontal) {
      barRow(menus: false, scale: true)
      barRow(menus: true, scale: true)
      barRow(menus: true, scale: false)
    }
    .padding(.horizontal, Spacing.page)
    .padding(.vertical, Spacing.xs)
  }

  private func barRow(menus: Bool, scale: Bool) -> some View {
    HStack(spacing: Spacing.s) {
      Picker(L10n.t("buildServer.viewport.label"), selection: $model.previewMode) {
        ForEach(PreviewWidth.Mode.allCases) { Text($0.title).tag($0) }
      }
      .menuOrSegmented(menus)
      .labelsHidden()
      .fixedSize()
      .accessibilityIdentifier("server.previewMode")
      if scale {
        Text(L10n.t("buildServer.scale", ["width": String(Int(renderWidth)), "percent": String(Int((shownScale * 100).rounded()))]))
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .fixedSize()
          .contentTransition(.numericText())
          .help(L10n.t("sitePreview.scaled", ["width": String(Int(renderWidth)), "percent": String(Int((shownScale * 100).rounded()))]))
          .accessibilityIdentifier("server.previewScale")
      }
      if !menus, let activity, activity.kind != .build { ActivityLine(activity: activity).fixedSize() }
      Spacer(minLength: Spacing.xs)
      Picker(L10n.t("buildServer.fit"), selection: $fit) {
        Text(L10n.t("buildServer.fit")).tag(true)
        Text(L10n.t("buildServer.actualSize")).tag(false)
      }
      .menuOrSegmented(menus)
      .labelsHidden()
      .fixedSize()
      Button { model.previewNonce += 1 } label: {
        Label(L10n.t("buildServer.reloadPreview"), systemImage: "arrow.clockwise")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .help(L10n.t("buildServer.reloadPreview"))
      if let url = URL(string: address) {
        Link(destination: url) {
          Label(L10n.t("common.openInBrowser"), systemImage: "safari")
        }
        .labelStyle(.iconOnly)
        .help(L10n.t("common.openInBrowser"))
      }
    }
  }

  @ViewBuilder private var emptyPreview: some View {
    if running {
      // Behind a tunnel: the address works in the browser, not in here.
      ContentUnavailableView {
        Label(L10n.t("buildServer.livePreview"), systemImage: "play.display")
      } description: {
        Text(L10n.t("sitePreview.remote"))
      }
    } else if status.state == .starting {
      ProgressView(L10n.t("sitePreview.starting")).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ContentUnavailableView {
        Label(L10n.t("buildServer.livePreview"), systemImage: "play.display")
      } description: {
        Text(L10n.t("buildServer.devServerHint"))
      } actions: {
        if status.state == .stopped || status.state == .error {
          // Not prominent: the toolbar's Starten is the page's one main action.
          Button(L10n.t("buildServer.start"), systemImage: "play.fill", action: model.start)
        }
      }
    }
  }

  /// Both consoles under the site, like Xcode's, as high as the grip above them says; folded away,
  /// one line. A DisclosureGroup, so its state is said and its opening animated by the system.
  private func outputPanel(height: CGFloat?) -> some View {
    VStack(spacing: 0) {
      Divider()
      Fold(isExpanded: $outputOpen) {
        HStack(alignment: .top, spacing: Spacing.m) {
          console(L10n.t("buildServer.serverLogLabel"), empty: logs.server.lines.isEmpty, clear: { monitor.clearLog(project.id, .server) }) {
            LogConsole(lines: logs.server, label: L10n.t("buildServer.serverLogLabel"), identifier: "server.log.server", fills: true) {
              monitor.clearLog(project.id, .server)
            }
          }
          console(L10n.t("buildServer.buildLogLabel"), empty: logs.build.lines.isEmpty, clear: { monitor.clearLog(project.id, .build) }) {
            LogConsole(lines: logs.build, label: L10n.t("buildServer.buildLogLabel"), identifier: "server.log.build", fills: true) {
              monitor.clearLog(project.id, .build)
            }
          }
        }
        .frame(height: max(80, (height ?? 0) - outputHead - 1 - 4 * Spacing.xs), alignment: .top)
        .padding(.top, Spacing.xs)
      } label: {
        Text(L10n.t("buildServer.output")).fontWeight(.medium)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { outputHead = $0 }
      }
      .padding(.horizontal, Spacing.page)
      .padding(.vertical, Spacing.xs)
    }
    .frame(maxHeight: outputOpen ? .infinity : nil, alignment: .top)
    .background(.bar)
  }

  private func console<Content: View>(_ title: String, empty: Bool, clear: @escaping () -> Void,
                                      @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack(alignment: .firstTextBaseline) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: Spacing.xs)
        LogConsole.clearButton(empty: empty, action: clear)
      }
      content()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Dev server (inspector)

  private func serverSection(now: Date) -> some View {
    Section {
      addressRow
      Note(serverFacts(now: now))
      Fold(isExpanded: $model.optionsOpen) {
        optionsFields
      } label: {
        Label(L10n.t("buildServer.serverOptions"), systemImage: "slider.horizontal.3")
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
            Label(address, systemImage: "arrow.up.right.square").fontWeight(.semibold)
          }
          .help(L10n.t("common.openInBrowser"))
        } else {
          Text(address).fontWeight(.semibold).foregroundStyle(.secondary)
        }
      }
      .lineLimit(1)
      .accessibilityIdentifier("page.server")
      Spacer(minLength: 0)
      Button(action: copyAddress) {
        Label(L10n.t("common.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .help(L10n.t("common.copy"))
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

  // MARK: One-off build

  private func buildSection(now: Date) -> some View {
    Section {
      Note(L10n.t("buildServer.oneOffBuildHint"))
      if let activity, activity.kind == .build { ActivityLine(activity: activity) }
      outputRows(now: now)
      outputDirField
      if let result = model.buildResult {
        Text(BuildServerModel.resultLine(result)).font(.callout).foregroundStyle(result.success ? .green : .red)
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
              ExternalOpen.openFolder(info.dir)
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
      // The label above the field: in the inspector's width, beside it, it broke into three lines.
      Text(L10n.t("buildServer.exportDir"))
      HStack {
        TextField(L10n.t("buildServer.exportDir"), text: $model.outputDir, prompt: Text(L10n.t("buildServer.exportDirPlaceholder")))
          .labelsHidden()
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
        Callout(.warning, L10n.t("buildServer.exportDirForeign", ["count": String(info.fileCount)], count: info.fileCount))
      }
      if let error = model.outputDirError {
        Callout(.error) { Text(error).accessibilityIdentifier("server.outputDir.error") }
      }
    }
  }

  /// QuartzControl's `isInsideDirectory`: the folder itself, or below it.
  static func isInside(_ parent: String, _ child: String) -> Bool {
    if child == parent { return true }
    return child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
  }
}

private extension View {
  @ViewBuilder func menuOrSegmented(_ menu: Bool) -> some View {
    if menu { pickerStyle(.menu) } else { pickerStyle(.segmented) }
  }
}
