import Foundation

/// One row of the project list: the entry from `projects.json` and what the list says about it.
/// A port of `ProjectOverview` (`shared/ipc-contract.ts`).
public struct ProjectOverview: Equatable, Sendable, Identifiable {
  public var entry: ProjectEntry
  /// The folder is gone: moved, renamed, or on a volume that is not mounted.
  public var missing: Bool
  /// The folder exists but holds no `quartz.config.yaml`. Adding never checked, so a plain folder
  /// can be in the list; the row says so instead of opening into a project that fails everywhere.
  public var isQuartzProject: Bool
  public var siteTitle: String?
  public var baseUrl: String?
  public var serverRunning: Bool
  public var serverPort: Int?
  /// QuartzHub keeps a relay recipient or captcha secret for it; removing the entry deletes them,
  /// so the question says so.
  public var relaySecrets: Bool
  /// The project's own picture (PNG thumbnail), nil while it carries the icon Quartz ships.
  public var icon: Data?

  public var id: String { entry.id }
  public var name: String { entry.name }
  public var path: String { entry.path }

  public init(entry: ProjectEntry, missing: Bool, isQuartzProject: Bool, siteTitle: String? = nil, baseUrl: String? = nil,
              serverRunning: Bool = false, serverPort: Int? = nil, relaySecrets: Bool = false, icon: Data? = nil) {
    self.entry = entry
    self.missing = missing
    self.isQuartzProject = isQuartzProject
    self.siteTitle = siteTitle
    self.baseUrl = baseUrl
    self.serverRunning = serverRunning
    self.serverPort = serverPort
    self.relaySecrets = relaySecrets
    self.icon = icon
  }
}

/// `projectOverviewService.getProjectOverviews` and the order and filter of QuartzControl's start
/// page (`Home.tsx`).
///
/// Local reads only, no network. Every read per project swallows its own failure: one unreadable
/// project must not blank the list, it gets a row marked for what is wrong with it. A malformed
/// `quartz.config.yaml` (a half-finished hand edit) keeps its row without a title; the
/// configuration page is where that gets reported.
public enum ProjectOverviews {
  /// The list in `projects.json` order. `servers` answers a project id with the dev server's port
  /// while it runs (nil: not running; a running server without a known port is `.some(nil)`).
  public static func read(
    store: ProjectStore,
    relaySecrets: Set<String>,
    servers: [String: Int?],
    runtime: RuntimeLocation = .current
  ) async -> [ProjectOverview] {
    let entries = store.list()
    return await withTaskGroup(of: (Int, ProjectOverview).self) { group in
      for (index, entry) in entries.enumerated() {
        group.addTask {
          (index, await overview(entry, relaySecrets: relaySecrets, server: servers[entry.id], runtime: runtime))
        }
      }
      var rows = [ProjectOverview?](repeating: nil, count: entries.count)
      for await (index, row) in group { rows[index] = row }
      return rows.compactMap { $0 }
    }
  }

  static func overview(_ entry: ProjectEntry, relaySecrets: Set<String>, server: Int??, runtime: RuntimeLocation) async -> ProjectOverview {
    let missing = !Posix.exists(entry.path)
    let isQuartz = !missing && Posix.exists(NodePath.join(entry.path, "quartz.config.yaml"))
    var row = ProjectOverview(entry: entry, missing: missing, isQuartzProject: isQuartz,
                              serverRunning: server != nil, serverPort: server ?? nil,
                              relaySecrets: relaySecrets.contains(entry.id))
    guard isQuartz else { return row }
    row.icon = ProjectIcon.customThumbnail(project: entry.path)
    if let config = try? await ConfigFile.read(project: entry.path, runtime: runtime) {
      row.siteTitle = config.configuration["pageTitle"]?.stringValue
      row.baseUrl = config.configuration["baseUrl"]?.stringValue
    }
    return row
  }

  /// Most recently opened first, never opened last, by name within each group:
  /// `bt - at || a.name.localeCompare(b.name)`. A stamp `Date.parse` cannot read is NaN there.
  public static func sorted(_ rows: [ProjectOverview]) -> [ProjectOverview] {
    func time(_ row: ProjectOverview) -> Double {
      // `a.lastOpenedAt ? … : 0`: an empty stamp is falsy, so 0, not NaN.
      guard let stamp = row.entry.lastOpenedAt, !stamp.isEmpty else { return 0 }
      return parseISO(stamp)?.timeIntervalSince1970 ?? .nan
    }
    var list = rows
    JS.sort(&list) { a, b in
      let difference = time(b) - time(a)
      // `NaN || x` is x: an unreadable stamp falls through to the name, like an equal one.
      return difference != 0 && !difference.isNaN ? difference : JS.localeCompare(a.name, b.name)
    }
    return list
  }

  /// The stamps QuartzHub and QuartzControl write (`toISOString`), with or without milliseconds.
  static func parseISO(_ stamp: String) -> Date? {
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp))
      ?? (try? Date.ISO8601FormatStyle().parse(stamp))
  }

  /// The search field: name, path or site title, case-insensitive (`toLowerCase` and `includes`).
  /// One difference on purpose: Swift's `contains` takes „ü“ and „u“ + combining diaeresis as the
  /// same text, JavaScript's `includes` did not, so a typed „Gärten“ finds a path that the system
  /// handed over decomposed.
  public static func filter(_ rows: [ProjectOverview], query: String) -> [ProjectOverview] {
    let needle = JS.trim(query).lowercased()
    guard !needle.isEmpty else { return rows }
    return rows.filter { row in
      row.name.lowercased().contains(needle) || row.path.lowercased().contains(needle)
        || (row.siteTitle ?? "").lowercased().contains(needle)
    }
  }

  /// From this many projects on the start page shows its search field.
  public static let searchThreshold = 6
}
