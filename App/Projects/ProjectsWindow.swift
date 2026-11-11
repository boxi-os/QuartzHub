import AppKit
import QuartzHubCore
import SwiftUI

/// The window „Projekte“: QuartzControl's start page (`src/routes/Home.tsx`) as a list with the
/// inspector. A project opens in its own window (`ProjectWindow`); opening one that is open
/// already brings its window to the front.
///
/// What QuartzControl put beside the cards (getting started, what Quartz is, what the app does) is
/// the inspector's page context here; with a project selected the inspector shows that project.
struct ProjectsWindow: View {
  static let sceneID = "projects"

  @State private var model = ProjectsModel.shared
  @State private var monitor = BuildMonitor.shared
  @State private var selection: String?
  @State private var query = ""
  @State private var failure: String?
  @State private var removing: ProjectOverview?
  @State private var creating = false
  @State private var duplicating: ProjectOverview?
  @SceneStorage("inspector.presented") private var inspectorPresented = true
  @Environment(\.openWindow) private var openWindow
  /// The takeover from QuartzControl, offered while QuartzHub has no project list of its own.
  @State private var migration: (source: ProfileDirectory, plan: ProfileMigration.Plan)? = ProjectsWindow.pendingMigration()

  private static func pendingMigration() -> (source: ProfileDirectory, plan: ProfileMigration.Plan)? {
    guard let source = AppProfile.quartzControl,
          ProfileMigration.shouldOffer(source: source, target: AppProfile.own) else { return nil }
    let plan = ProfileMigration.plan(source: source)
    return plan.isEmpty ? nil : (source, plan)
  }

  private var sorted: [ProjectOverview] { ProjectOverviews.sorted(model.rows) }
  private var shown: [ProjectOverview] { ProjectOverviews.filter(sorted, query: query) }

  var body: some View {
    VStack(spacing: 0) {
      if let report = model.environment, !report.ok {
        EnvironmentBand(report: report) { Task { await model.checkEnvironment() } }
      }
      content
    }
      .navigationTitle(L10n.t("shell.projects.title"))
      .inspectorColumn(isPresented: $inspectorPresented) {
        if let id = selection, let row = model.row(id) {
          ProjectInspector(row: row, open: { open(row) }, duplicate: { duplicating = row }, remove: { askRemove(row) })
        } else {
          ProjectsContext()
        }
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            creating = true
          } label: {
            Label(L10n.t("home.createNew"), systemImage: "plus")
          }
          .help(L10n.t("home.createNew"))
          .accessibilityIdentifier("projects.create")
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            addExisting()
          } label: {
            Label(L10n.t("home.openExisting"), systemImage: "folder.badge.plus")
          }
          .help(L10n.t("home.openExisting"))
          .accessibilityIdentifier("projects.openExisting")
        }
      }
      .task {
        await model.reload()
        await model.checkEnvironment()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        Task { await model.reload() }
      }
      // A server started or stopped in a project window: QuartzControl read the list again on
      // every return to its start page, this window stays open beside the project, so the badge
      // follows the server instead (measured 2026-11-09: without this it came only after QuartzHub
      // had lost and regained focus).
      .onChange(of: monitor.settledServers) {
        Task { await model.reload() }
      }
      .onChange(of: model.request, initial: true) { _, request in
        guard let request else { return }
        model.request = nil
        switch request {
        case .openExisting: addExisting()
        case .create: creating = true
        }
      }
      .onAppear(perform: openFromLaunchArgument)
      .confirmationDialog(removeQuestion, isPresented: removingPresented, titleVisibility: .visible) {
        Button(L10n.t("common.cancel"), role: .cancel) {}
        Button(L10n.t("home.confirmRemoveAction"), role: .destructive) {
          guard let row = removing else { return }
          Task {
            do { try await model.remove(row.id) } catch { failure = error.localizedMessage }
          }
        }
      }
      .alert(failure ?? "", isPresented: failurePresented) {
        Button(L10n.t("shell.alert.ok"), role: .cancel) {}
      }
      .sheet(isPresented: $creating) {
        CreateProjectSheet { id in
          creating = false
          if let id, let row = model.row(id) {
            selection = id
            open(row)
          }
        }
      }
      .sheet(item: $duplicating) { source in
        DuplicateProjectSheet(source: source) { id in
          duplicating = nil
          if let id, let row = model.row(id) {
            selection = id
            open(row)
          }
        }
      }
      .sheet(isPresented: migrationPresented) {
        if let migration {
          MigrationSheet(source: migration.source, plan: migration.plan) {
            self.migration = nil
            Task { await model.reload() }
          }
          .interactiveDismissDisabled()
        }
      }
  }

  @ViewBuilder private var content: some View {
    if !model.loaded {
      ProgressView(L10n.t("common.loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.rows.isEmpty {
      GettingStarted(create: { creating = true }, addExisting: addExisting)
    } else {
      list
        .modifier(SearchFromThreshold(count: model.rows.count, query: $query))
    }
  }

  private var list: some View {
    List(selection: $selection) {
      ForEach(shown) { row in
        ProjectRow(row: row)
          .tag(row.id)
          .accessibilityIdentifier("projects.row.\(row.name)")
      }
    }
    .contextMenu(forSelectionType: String.self) { ids in
      if let id = ids.first, let row = model.row(id) {
        Button(L10n.t("shell.projects.open")) { open(row) }
          .disabled(row.missing || !row.isQuartzProject)
        Button(L10n.t("shell.projects.showInFinder")) { reveal(row) }
          .disabled(row.missing)
        Button(L10n.t("home.duplicate.action") + "…") { duplicating = row }
          .disabled(row.missing || !row.isQuartzProject)
        Divider()
        Button(L10n.t("home.confirmRemoveAction") + "…") { askRemove(row) }
      }
    } primaryAction: { ids in
      if let id = ids.first, let row = model.row(id) { open(row) }
    }
    .overlay {
      if shown.isEmpty {
        ContentUnavailableView.search(text: query)
      }
    }
    .accessibilityIdentifier("projects.list")
  }

  private func open(_ row: ProjectOverview) {
    guard !row.missing, row.isQuartzProject else { return }
    model.opened(row.id)
    openWindow(id: ProjectWindow.sceneID, value: row.id)
  }

  private func reveal(_ row: ProjectOverview) {
    ExternalOpen.reveal([URL(fileURLWithPath: row.path)]) // path boundary
  }

  private func addExisting() {
    Task {
      do {
        if let id = try await model.addFromPanel(), let row = model.row(id) {
          selection = id
          open(row)
        }
      } catch {
        failure = error.localizedMessage
      }
    }
  }

  /// For the UI test: the project at this path, added to the (scratch) profile and opened.
  private func openFromLaunchArgument() {
    #if DEBUG
    guard let path = LaunchArgument.string("QHOpenProject") else { return }
    Task {
      guard let entry = try? await model.list.add(path: Posix.onDisk(path)) else { return }
      await model.reload()
      if let row = model.row(entry.id) { open(row) }
    }
    #endif
  }

  /// QuartzControl's four questions: whether a dev server is stopped and relay secrets go with it.
  /// The question names what removing deletes, so it is asked of a fresh row: relay secrets saved
  /// in a project window change no file this window watches, and while QuartzHub stayed active the
  /// row still said "none" although removing deletes them (measured 2026-11-10). QuartzControl read
  /// the list again on every return to its start page.
  private func askRemove(_ row: ProjectOverview) {
    Task {
      await model.reload()
      removing = model.row(row.id) ?? row
    }
  }

  private var removeQuestion: String {
    guard let row = removing else { return "" }
    let name = ["name": row.name]
    return switch (row.serverRunning, row.relaySecrets) {
    case (true, true): L10n.t("home.confirmRemoveRunningRelay", name)
    case (true, false): L10n.t("home.confirmRemoveRunning", name)
    case (false, true): L10n.t("home.confirmRemoveRelay", name)
    case (false, false): L10n.t("home.confirmRemove", name)
    }
  }

  private var removingPresented: Binding<Bool> {
    Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
  }

  private var failurePresented: Binding<Bool> {
    Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
  }

  private var migrationPresented: Binding<Bool> {
    Binding(get: { migration != nil }, set: { if !$0 { migration = nil } })
  }
}

/// QuartzControl showed the search field from six projects on; below that it is noise.
private struct SearchFromThreshold: ViewModifier {
  let count: Int
  @Binding var query: String

  func body(content: Content) -> some View {
    if count >= ProjectOverviews.searchThreshold {
      content.searchable(text: $query, placement: .toolbar, prompt: L10n.t("home.searchPlaceholder"))
    } else {
      content
    }
  }
}

/// One project: picture, name, what the config says about the site, the folder, and the state.
private struct ProjectRow: View {
  let row: ProjectOverview

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      ProjectAvatar(row: row, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(row.name).font(.headline)
          Spacer(minLength: 8)
          if row.serverRunning { ServerBadge(port: row.serverPort) }
        }
        if let problem = row.problem {
          Label(problem, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .font(.callout)
        } else if let site = row.siteLine {
          Text(site).foregroundStyle(.secondary).lineLimit(1)
        }
        Text(row.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(row.path)
        Text(row.lastOpenedLine)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}

private struct ServerBadge: View {
  let port: Int?

  var body: some View {
    Label {
      Text(port.map { L10n.t("home.serverRunningOnPort", ["port": String($0)]) } ?? L10n.t("home.serverRunning"))
    } icon: {
      Image(systemName: "circle.fill").foregroundStyle(.green).imageScale(.small)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

/// The project's own picture, else the first letter on a colour taken from its id, as
/// QuartzControl's `ProjectAvatar` did (the same project keeps its colour).
struct ProjectAvatar: View {
  let row: ProjectOverview
  let size: CGFloat

  var body: some View {
    Group {
      if let data = row.icon, let image = NSImage(data: data) {
        Image(nsImage: image).resizable().interpolation(.high)
      } else {
        RoundedRectangle(cornerRadius: size * 0.22)
          .fill(Self.colour(row.id).gradient)
          .overlay {
            Text(String(row.name.first.map(String.init)?.uppercased() ?? "?"))
              .font(.system(size: size * 0.45, weight: .semibold))
              .foregroundStyle(.white)
          }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    .accessibilityHidden(true)
  }

  private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .brown]

  static func colour(_ id: String) -> Color {
    palette[Int(id.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value } % UInt32(palette.count))]
  }
}

extension ProjectOverview {
  /// What is wrong with the row, if anything (QuartzControl's amber line).
  var problem: String? {
    if missing { return L10n.t("home.folderMissing") }
    if !isQuartzProject { return L10n.t("home.notAQuartzProject") }
    return nil
  }

  /// `„Titel“ · adresse`, as QuartzControl's card wrote it.
  var siteLine: String? {
    let parts = [siteTitle.map { "„\($0)“" }, baseUrl].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  var lastOpenedLine: String {
    guard let date = lastOpened else { return L10n.t("home.neverOpened") }
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    formatter.locale = Locale(identifier: L10n.language)
    return L10n.t("home.lastOpened", ["when": formatter.localizedString(for: date, relativeTo: Date())])
  }
}

extension Error {
  /// The message a service gave, for an alert.
  var localizedMessage: String {
    if let failure = self as? ProjectStore.Failure { return failure.message }
    return String(describing: self)
  }
}
