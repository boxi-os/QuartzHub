import Foundation

/// The catalog of community themes: a port of `themeMarketplaceService.ts`. `@quartz-themes/<id>`
/// packages are plain npm dependencies consumed by `@quartz-themes/core`, so `npm search` is the
/// only list there is; the `quartz-themes` GitHub organisation adds stars and topics (sparse), and
/// jsDelivr the details of a theme not yet installed (an installed one answers from its theme.json).
///
/// Not yet: the GitHub token from the access store (point 8), which only raises the rate limit.
public actor ThemeMarketplace {
  public struct Listing: Equatable, Sendable {
    public var id: String
    public var description: String?
    public var stars: Int?
    public var topics: [String]?
    public var githubDescription: String?
  }

  public struct Catalog: Equatable, Sendable {
    public var themes: [Listing]
    /// The list is the fallback of seven, not the registry's ~700.
    public var unavailable: Bool
  }

  /// Shown when npm cannot be asked; always with `unavailable`. "default" is what core installs.
  public static let fallback = ["default", "tokyo-night", "catppuccin", "nord", "everforest", "minimal", "obsidian"].map { Listing(id: $0) }
  static let cacheLifetime: TimeInterval = 15 * 60
  static let detailLifetime: TimeInterval = 60 * 60

  /// `npm search @quartz-themes --json --searchlimit=250`: its stdout, or nil when it did not run
  /// to the end within its 30 s (npm has none of its own) or did not start.
  public typealias Search = @Sendable () async -> String?
  /// `npm install` in the project.
  public typealias Install = @Sendable (_ arguments: [String], _ project: URL) async -> PluginCommands.Result

  public static func npmSearch(environment: @escaping @Sendable () async -> ToolEnvironment) -> Search {
    {
      let command = await environment().command("npm", ["search", "@quartz-themes", "--json", "--searchlimit=250"], in: nil, timeout: .seconds(30))
      let result = await ProcessRunner.run(command)
      // QuartzControl read stdout at `close` whatever the exit code; only a deadline or a spawn
      // error answered nothing.
      switch result.termination {
      case .exited, .signaled: return result.stdout
      case .timedOut, .cancelled, .couldNotStart: return nil
      }
    }
  }

  public static func npmInstall(environment: @escaping @Sendable () async -> ToolEnvironment) -> Install {
    { arguments, project in
      let command = await environment().command("npm", arguments, in: project, timeout: .seconds(20 * 60))
      let result = await ProcessRunner.run(command)
      return PluginCommands.Result(success: result.success, output: result.report(for: command))
    }
  }

  let session: URLSession
  let search: Search
  let install: Install
  let now: @Sendable () -> Date
  private var catalog: (at: Date, themes: [Listing])?
  private var github: (at: Date, byName: [String: (stars: Int, topics: [String], description: String?)])?
  private var details: [String: (at: Date, detail: ThemeDetail?)] = [:]

  public init(search: @escaping Search, install: @escaping Install, configuration: URLSessionConfiguration = .ephemeral,
              timeout: Duration = .seconds(20), now: @escaping @Sendable () -> Date = Date.init) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = Double(timeout.components.seconds)
    configuration.timeoutIntervalForResource = Double(timeout.components.seconds)
    session = URLSession(configuration: configuration)
    self.search = search
    self.install = install
    self.now = now
  }

  func fromNpm() async -> [Listing]? {
    guard let output = await search(), case .array(let entries)? = try? JSJSON.parse(output) else { return nil }
    var themes: [Listing] = []
    for entry in entries {
      // `p.name.startsWith(…)` threw for an entry without a name, and the whole answer was lost.
      guard case .string(let name)? = entry[safe: "name"] else { return nil }
      guard name.hasPrefix("@quartz-themes/"), name != "@quartz-themes/core" else { continue }
      themes.append(Listing(id: String(name.dropFirst("@quartz-themes/".count)), description: entry[safe: "description"].flatMap { $0 == .null ? nil : JS.string($0) }))
    }
    return themes.isEmpty ? nil : themes
  }

  /// Every repo of the organisation, a page of 100 at a time, at most five; what came before a
  /// failure stays.
  func githubMetadata() async -> [String: (stars: Int, topics: [String], description: String?)] {
    var byName: [String: (stars: Int, topics: [String], description: String?)] = [:]
    for page in 1...5 {
      var request = URLRequest(url: URL(string: "https://api.github.com/orgs/quartz-themes/repos?per_page=100&page=\(page)")!)
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode), case .array(let repos)? = try? JSJSON.parse(data), !repos.isEmpty else { break }
      for repo in repos {
        guard let name = repo[safe: "name"]?.stringValue else { continue }
        byName[name] = (Int(repo[safe: "stargazers_count"]?.numberValue ?? 0), (repo[safe: "topics"]?.arrayValue ?? []).compactMap(\.stringValue),
                        repo[safe: "description"]?.stringValue)
      }
      if repos.count < 100 { break }
    }
    return byName
  }

  /// The catalog: npm's list (a failed search is never cached, it would hold the seven for a
  /// quarter of an hour) with GitHub's metadata over it.
  public func list() async -> Catalog {
    if catalog == nil || now().timeIntervalSince(catalog!.at) > Self.cacheLifetime {
      guard let themes = await fromNpm() else { return Catalog(themes: Self.fallback, unavailable: true) }
      catalog = (now(), themes)
    }
    if github == nil || now().timeIntervalSince(github!.at) > Self.cacheLifetime {
      github = (now(), await githubMetadata())
    }
    let themes = catalog!.themes.map { theme -> Listing in
      guard let meta = github!.byName[theme.id] else { return theme }
      var merged = theme
      merged.stars = meta.stars
      merged.topics = meta.topics.isEmpty ? nil : meta.topics
      merged.githubDescription = meta.description
      return merged
    }
    return Catalog(themes: themes, unavailable: false)
  }

  public func invalidate() {
    catalog = nil
    github = nil
    details = [:]
  }

  /// A theme's modes, variations, Style Settings ids and fonts: the installed theme.json first, then
  /// jsDelivr. A network failure is not cached; an answer without the file is, for an hour.
  public func detail(themeId: String, project: URL) async throws -> ThemeDetail? {
    try StyleSettingsSchema.check(themeId)
    if let local = PluginSchemaReader.localThemeDetail(project: project, themeId: themeId) { return local }
    if let cached = details[themeId], now().timeIntervalSince(cached.at) < Self.detailLifetime { return cached.detail }
    guard let (data, response) = try? await session.data(from: URL(string: "https://cdn.jsdelivr.net/npm/@quartz-themes/\(themeId)/theme.json")!),
          let http = response as? HTTPURLResponse else { return nil }
    var detail: ThemeDetail?
    if (200..<300).contains(http.statusCode) {
      // `parsed.meta?.…` threw on a body of `null`, and the catch answered null without caching.
      guard let parsed = try? JSJSON.parse(data), parsed != .null else { return nil }
      let meta = parsed[safe: "meta"]
      let strings = { (key: String) in (meta?[safe: key]?.arrayValue ?? []).map { JS.string($0) } }
      let ids: [String] = switch meta?[safe: "styleSettingsId"] {
      case nil, .null?: []
      case .array(let items)?: items.map { JS.string($0) }
      case let value?: [JS.string(value)]
      }
      detail = ThemeDetail(modes: strings("modes"), variations: strings("variations"), styleSettingsId: ids, fonts: strings("fonts"))
    }
    details[themeId] = (now(), detail)
    return detail
  }

  /// The theme and `@quartz-themes/core` (a no-op when core is there), since a theme alone does
  /// nothing without the transformer that reads it.
  public func install(themeId: String, project: URL) async throws -> PluginCommands.Result {
    try StyleSettingsSchema.check(themeId)
    return await install(["install", "@quartz-themes/core", "@quartz-themes/\(themeId)"], project)
  }
}
