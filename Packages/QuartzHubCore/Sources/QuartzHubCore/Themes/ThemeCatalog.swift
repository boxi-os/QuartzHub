import Foundation

/// The catalog of community themes: Obsidian's own list (`community-css-themes.json` in
/// `obsidianmd/obsidian-releases`), the one `@quartz-themes/core` 3 looks a theme name up in. Each
/// entry has a name, author, repo, modes and a screenshot; nothing is installed any more, a theme is
/// a name in the plugin entry and core loads it at build time (docs/plan-themes-core-3.md, step 2).
///
/// The list is kept in the profile (`theme-docs/community-css-themes.json`, where QuartzControl kept
/// its copy) and a copy younger than a day answers without asking, as core keeps its own for a day.
/// Offline is a normal state: an older copy answers then, marked as not current, and the network is
/// asked again a quarter of an hour later. `StyleSettingsSchema` reads the same list through
/// `entries()`.
public actor ThemeCatalog {
  static let registryURL = "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/community-css-themes.json"
  static let lifetime: TimeInterval = 24 * 60 * 60
  static let retryAfterFailure: TimeInterval = 15 * 60
  /// Clear of the list's 186 KB (1061 themes, 2026-11-23).
  static let maxBytes = 16 * 1024 * 1024

  public struct Theme: Equatable, Sendable, Identifiable {
    /// What `theme:` takes; unique in the list.
    public var name: String
    public var author: String?
    /// `owner/repo` on GitHub.
    public var repo: String
    /// `dark`, `light`, in the list's order.
    public var modes: [String]
    /// The screenshot on GitHub, as Obsidian shows it; nil when the list names none.
    public var screenshotURL: String?
    /// Obsidian marks 15 themes as made for its versions before 1.0.
    public var legacy: Bool

    public var id: String { name }

    public init(name: String, author: String? = nil, repo: String, modes: [String] = [], screenshotURL: String? = nil, legacy: Bool = false) {
      self.name = name
      self.author = author
      self.repo = repo
      self.modes = modes
      self.screenshotURL = screenshotURL
      self.legacy = legacy
    }
  }

  public struct Listing: Equatable, Sendable {
    public var themes: [Theme]
    /// When the list was fetched.
    public var fetched: Date
    /// false: the network could not be asked, an older copy answers.
    public var current: Bool
  }

  let session: URLSession
  let file: String
  let now: @Sendable () -> Date

  struct Loaded {
    var entries: [JSONValue]
    var fetched: Date
    var current: Bool
    /// When the network was last asked, for the retry of a copy that is not current.
    var checked: Date
  }
  private var loaded: Loaded?
  /// The network failed and there was no copy: nothing to answer until the retry.
  private var failedAt: Date?
  /// Set by `invalidate()`: the next load asks the network before a young copy counts.
  private var askNetwork = false
  private var loading: Task<Loaded?, Never>?

  public init(profile: ProfileDirectory = .quartzHub, configuration: URLSessionConfiguration = .ephemeral, timeout: Duration = .seconds(45),
              now: @escaping @Sendable () -> Date = Date.init) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let seconds = Double(timeout.components.seconds)
    configuration.timeoutIntervalForRequest = seconds
    configuration.timeoutIntervalForResource = seconds
    Offline.apply(configuration)
    session = URLSession(configuration: configuration)
    file = profile.file("theme-docs/community-css-themes.json")
    self.now = now
  }

  /// The catalog, or nil when neither the network nor a copy had it.
  public func list() async -> Listing? {
    guard let loaded = await load() else { return nil }
    return Listing(themes: loaded.entries.compactMap(Self.theme), fetched: loaded.fetched, current: loaded.current)
  }

  /// The list as it stands in the file, every field kept; empty when there is none.
  func entries() async -> [JSONValue] { await load()?.entries ?? [] }

  /// Forgets the list in memory; the next load asks the network first (a copy stays the fallback).
  public func invalidate() {
    loaded = nil
    failedAt = nil
    askNetwork = true
  }

  /// One load at a time: a second caller waits for the first one's answer.
  func load() async -> Loaded? {
    let time = now()
    if let loaded {
      if loaded.current ? time.timeIntervalSince(loaded.fetched) < Self.lifetime : time.timeIntervalSince(loaded.checked) < Self.retryAfterFailure {
        return loaded
      }
    } else if let failedAt, time.timeIntervalSince(failedAt) < Self.retryAfterFailure {
      return nil
    }
    if let loading { return await loading.value }
    let task = Task { await self.fetchOrCopy() }
    loading = task
    let result = await task.value
    loading = nil
    return result
  }

  private func fetchOrCopy() async -> Loaded? {
    let time = now()
    if !askNetwork, let copy = readCopy(), time.timeIntervalSince(copy.modified) < Self.lifetime {
      loaded = Loaded(entries: copy.entries, fetched: copy.modified, current: true, checked: time)
      return loaded
    }
    if let target = URL(string: Self.registryURL), let (data, response) = try? await session.data(from: target),
       let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= Self.maxBytes,
       case .array(let entries)? = try? JSJSON.parse(data), !entries.isEmpty {
      try? Posix.mkdirs(NodePath.dirname(file))
      try? JSONStore.writeAtomic(Data(JSJSON.compact(.array(entries)).utf8), to: file)
      askNetwork = false
      failedAt = nil
      loaded = Loaded(entries: entries, fetched: time, current: true, checked: time)
      return loaded
    }
    if let copy = readCopy() {
      loaded = Loaded(entries: copy.entries, fetched: copy.modified, current: false, checked: time)
      return loaded
    }
    loaded = nil
    failedAt = time
    return nil
  }

  private func readCopy() -> (entries: [JSONValue], modified: Date)? {
    var info = stat()
    guard stat(file, &info) == 0, info.st_size <= Self.maxBytes, let data = try? Posix.read(file),
          case .array(let entries)? = try? JSJSON.parse(data), !entries.isEmpty else { return nil }
    return (entries, Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9))
  }

  /// An entry of the list, or nil without a name or a repo that is `owner/name`: both come from a
  /// third party's file, and the repo goes into a URL path.
  static func theme(_ entry: JSONValue) -> Theme? {
    guard case .string(let name)? = entry[safe: "name"], !JS.trim(name).isEmpty,
          case .string(let repo)? = entry[safe: "repo"], StyleSettingsSchema.isRepo(repo) else { return nil }
    let author = entry[safe: "author"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    let modes = (entry[safe: "modes"]?.arrayValue ?? []).compactMap(\.stringValue).filter { $0 == "dark" || $0 == "light" }
    let screenshot = entry[safe: "screenshot"]?.stringValue.flatMap { screenshotURL(repo: repo, file: $0) }
    return Theme(name: name, author: author, repo: repo, modes: modes, screenshotURL: screenshot, legacy: entry[safe: "legacy"] == .bool(true))
  }

  /// `https://raw.githubusercontent.com/<repo>/HEAD/<file>`, as Obsidian builds it, each segment
  /// encoded; nil for an empty name or one that leaves the repo (`..`, an absolute path). Spaces
  /// around the name go, as a browser drops them from an `src` (two entries end in one; the file is
  /// there without it, 2026-11-23).
  static func screenshotURL(repo: String, file: String) -> String? {
    let file = JS.trim(file)
    let segments = JSText.split(file, "/")
    guard !file.isEmpty, !file.hasPrefix("/"), !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
    let encoded = segments.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) }
    guard encoded.count == segments.count else { return nil }
    return "https://raw.githubusercontent.com/\(repo)/HEAD/\(encoded.joined(separator: "/"))"
  }

  /// The entry a `theme:` value names, the way core 3.1.1's `resolveTheme` finds it: an
  /// `owner/repo` by its repo (case aside), a name as written, then case aside, then by its slug.
  /// core's own table of 2.x ids (`catppuccin.frappe`) is core's: its answer (`ThemeFetch`) names
  /// the theme. nil for Obsidian's built-in theme, a path and a URL, which core takes before the list.
  public static func find(_ spec: String, in themes: [Theme]) -> Theme? {
    let trimmed = JS.trim(spec)
    guard !trimmed.isEmpty, !builtIn.contains(trimmed.lowercased()),
          !JSText.test(trimmed, #"\A(\.{1,2}[\\/]|/|~|[A-Za-z]:[\\/])"#), !trimmed.hasSuffix(".css"),
          !JSText.test(trimmed, #"\Ahttps?://"#) else { return nil }
    if JSText.test(trimmed, #"\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z"#) {
      return themes.first { $0.repo.lowercased() == trimmed.lowercased() }
    }
    return themes.first { $0.name == trimmed } ?? themes.first { $0.name.lowercased() == trimmed.lowercased() }
      ?? themes.first { slug($0.name) == slug(trimmed) }
  }

  /// core 3.1.1's `BUILT_IN`: Obsidian's own theme, no entry of the list.
  static let builtIn: Set<String> = ["default", "obsidian", "obsidian default"]

  /// core 3.1.1's `slugify`: NFD, accents and apostrophes dropped, runs of anything else a dash.
  static func slug(_ name: String) -> String {
    let folded = String(String.UnicodeScalarView(name.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }))
    var slug = JSText.replaceAll(folded, "['’]", with: "").lowercased()
    slug = JSText.replaceAll(slug, "[^a-z0-9]+", with: "-")
    return JSText.replaceAll(slug, #"\A-|-\z"#, with: "")
  }
}
