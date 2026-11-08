import AppKit
import QuartzHubCore
import SwiftUI

/// The project list for every window: the Projects window shows it, a project window looks its
/// entry up in it (and notices when it was removed), the File menu adds to it.
@MainActor @Observable
final class ProjectsModel {
  static let shared = ProjectsModel()

  /// In `projects.json` order; the window sorts (`ProjectOverviews.sorted`).
  private(set) var rows: [ProjectOverview] = []
  /// nil until the first read: the window says "Lade…" rather than "no projects yet".
  private(set) var loaded = false
  /// What a menu command asked the Projects window to do once it is in front.
  var request: Request?

  enum Request: Equatable {
    case openExisting
  }

  let list: ProjectList

  private init() {
    let profile = AppProfile.own
    list = ProjectList(store: ProjectStore(profile: profile), builds: AppServices.shared.builds,
                       connections: Connections(profile: profile, secrets: KeychainSecrets()))
  }

  func row(_ id: String) -> ProjectOverview? { rows.first { $0.id == id } }

  func reload() async {
    let servers = Dictionary(await list.builds.runningServerSummaries().map { ($0.projectId, Optional($0.port)) },
                             uniquingKeysWith: { first, _ in first })
    rows = await ProjectOverviews.read(store: list.store, relaySecrets: list.connections.projectsWithRelaySecrets(),
                                       servers: servers)
    loaded = true
  }

  /// "Vorhandenes Projekt öffnen": a folder from the panel goes into the list. Returns its id when
  /// it is a Quartz project, the one case that opens; a plain folder is listed, not opened, so its
  /// row can say what is wrong with it.
  func addFromPanel() async throws -> String? {
    guard let folder = Self.pickFolder(start: Self.defaultDirectory) else { return nil }
    let entry = try await list.add(path: folder)
    await reload()
    return row(entry.id)?.isQuartzProject == true ? entry.id : nil
  }

  /// "Ordner suchen…" for a project whose folder moved.
  func relocate(_ id: String) async throws {
    guard let folder = Self.pickFolder(start: nil) else { return }
    try await list.relocate(id: id, to: folder)
    await reload()
  }

  func remove(_ id: String) async throws {
    try await list.remove(id: id)
    await reload()
  }

  /// The entry stamped as opened (`projects:open`); the list order follows it.
  func opened(_ id: String) {
    _ = try? list.open(id: id)
    Task { await reload() }
  }

  /// The settings' default folder for new and opened projects (`defaultProjectDirectory`).
  static var defaultDirectory: String? {
    let file = SettingsFile(object: JSONStore.read(AppProfile.own.settings, orEmpty: .object).objectValue ?? JSONObject())
    return file.defaultProjectDirectory.flatMap { $0.isEmpty ? nil : $0 }
  }

  static func pickFolder(start: String?) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    if let start { panel.directoryURL = URL(fileURLWithPath: start, isDirectory: true) } // path boundary
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return Posix.path(url)
  }
}

/// The project a window shows, for its pages.
struct ProjectContext: Equatable {
  let id: String
  let name: String
  let path: String
}

extension EnvironmentValues {
  @Entry var project: ProjectContext?
}
