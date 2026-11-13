import Foundation

/// One repository of the quartz-community organisation, as the Marktplatz lists it.
///
/// `topics` and `archived` separate a real plugin from the rest of the org: the catalog is every
/// repository there, which also holds the core itself (`v5`, archived), shared libraries, a
/// template, an awesome-list and a few forks. 47 of the 63 repositories carry the `quartz-plugin`
/// topic (QuartzControl, docs/decisions/plugins-and-config.md), so the page sorts by that instead
/// of offering "install" on an awesome-list.
public struct MarketplacePlugin: Sendable, Equatable {
  public var name: String
  public var fullName: String
  public var description: String?
  public var stars: Int?
  public var url: String
  public var topics: [String]?
  public var archived: Bool?

  /// In the plugin list rather than "Andere Repositories": the topic, and not archived.
  public var isMarkedPlugin: Bool { (topics ?? []).contains(MarketplaceResult.pluginTopic) && archived != true }
}

/// What one catalog read produced. `unavailable` is its own answer rather than an empty list: an
/// unreachable or rate-limited GitHub leaves a single hard-coded entry, which is otherwise
/// indistinguishable from a one-plugin organisation.
public struct MarketplaceResult: Sendable, Equatable {
  public var plugins: [MarketplacePlugin]
  public var unavailable: Bool
}

/// A catalog entry's README: "this repository has none" and "GitHub did not answer" are different
/// things to say; `truncated` when the text was cut at `Marketplace.readmeLimit`.
public enum MarketplaceReadme: Sendable, Equatable {
  case ok(text: String, truncated: Bool)
  case missing
  case unavailable
}

/// The Marktplatz: the repositories of quartz-community and their READMEs, from the GitHub API
/// (QuartzControl's marketplaceService.ts, measured against it in MarketplaceTests).
///
/// - The catalog is read whole and kept for fifteen minutes; searching it is the page's business
///   and costs no request. A read that fails is never kept: retrying costs one request, and
///   someone who fixes their connection should not wait out the window holding a placeholder.
/// - One read at a time: callers that arrive while one is under way get its answer.
/// - Everything has a deadline (20 s, body included): a connection that stalls rather than fails
///   would otherwise leave the page spinning.
/// - The token only raises the rate limit; without one (or with one that cannot be read) the
///   requests go out anonymous.
///
/// Beyond QuartzControl: the catalog follows GitHub's `Link: rel="next"` (QuartzControl read the
/// first hundred repositories and would have lost the rest without a word; the org has 63 today);
/// a repository entry without name, full name or address is left out instead of listed with holes.
public actor Marketplace {
  public static let cacheLifetime: TimeInterval = 15 * 60
  /// A README is shown, not stored: the cap keeps a pathological one from being held whole. The
  /// largest in quartz-community is a few kilobytes.
  public static let readmeLimit = 256 * 1024
  /// Pages of a hundred repositories; beyond that the catalog ends where it is.
  public static let pageLimit = 10

  /// Shown when GitHub does not answer, so the tab is never empty, but always with
  /// `unavailable: true`.
  public static let fallback = [MarketplacePlugin(
    name: "explorer", fullName: "quartz-community/explorer", description: "Enhanced file explorer for Quartz.",
    url: "https://github.com/quartz-community/explorer")]

  private let session: URLSession
  private let base: String
  private let now: @Sendable () -> Date
  private let token: @Sendable () async -> String?

  private var cache: (at: Date, plugins: [MarketplacePlugin])?
  private var inFlight: Task<[MarketplacePlugin]?, Never>?
  private var readmes: [String: (at: Date, readme: MarketplaceReadme)] = [:]

  /// `token` is asked before every request and kept nowhere here. `configuration` is copied;
  /// caching and cookies are switched off, as with QuartzControl's fetch.
  public init(configuration: URLSessionConfiguration = .ephemeral, base: String = "https://api.github.com",
              deadline: Duration = .seconds(20), now: @escaping @Sendable () -> Date = Date.init,
              token: @escaping @Sendable () async -> String? = { nil }) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    // `timeoutIntervalForResource` is the whole request, body included, as with QuartzControl's
    // AbortSignal.timeout; `ForRequest` (the silence between packets) cannot be longer.
    let seconds = Double(deadline.components.seconds) + Double(deadline.components.attoseconds) / 1e18
    configuration.timeoutIntervalForRequest = seconds
    configuration.timeoutIntervalForResource = seconds
    Offline.apply(configuration)
    session = URLSession(configuration: configuration)
    self.base = base
    self.now = now
    self.token = token
  }

  // MARK: catalog

  public func list() async -> MarketplaceResult {
    if let cache, now().timeIntervalSince(cache.at) <= Self.cacheLifetime {
      return MarketplaceResult(plugins: cache.plugins, unavailable: false)
    }
    let task = inFlight ?? Task { await self.fetchCatalog() }
    inFlight = task
    let fetched = await task.value
    if inFlight == task { inFlight = nil }
    guard let fetched else { return MarketplaceResult(plugins: Self.fallback, unavailable: true) }
    cache = (now(), fetched)
    return MarketplaceResult(plugins: fetched, unavailable: false)
  }

  /// "Katalog neu laden": the next list and every README are asked again.
  public func invalidate() {
    cache = nil
    readmes.removeAll()
  }

  /// nil: GitHub did not deliver a catalog (no answer, not 2xx, not a non-empty list).
  private func fetchCatalog() async -> [MarketplacePlugin]? {
    let token = await token()
    var next: String? = "\(base)/orgs/quartz-community/repos?per_page=100"
    var plugins: [MarketplacePlugin] = []
    var pages = 0
    while let address = next, pages < Self.pageLimit {
      guard let url = URL(string: address) else { return nil }
      let request = Self.request(url, accept: "application/vnd.github+json", token: token)
      guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            case .array(let repos)? = try? JSJSON.parse(data)
      else { return nil }
      plugins += repos.compactMap(Self.plugin)
      pages += 1
      next = Self.nextPage(http.value(forHTTPHeaderField: "Link"), sameOriginAs: base)
    }
    return plugins.isEmpty ? nil : plugins
  }

  static func plugin(_ repo: JSONValue) -> MarketplacePlugin? {
    guard let name = repo["name"]?.stringValue, let fullName = repo["full_name"]?.stringValue,
          let url = repo["html_url"]?.stringValue else { return nil }
    return MarketplacePlugin(
      name: name, fullName: fullName, description: repo["description"]?.stringValue,
      stars: repo["stargazers_count"]?.numberValue.flatMap { Int(exactly: $0) }, url: url,
      topics: repo["topics"]?.arrayValue.map { $0.compactMap(\.stringValue) }, archived: repo["archived"]?.boolValue)
  }

  /// The `rel="next"` address of a `Link` header, if it stays where the first request went (the
  /// token goes with it).
  static func nextPage(_ link: String?, sameOriginAs base: String) -> String? {
    guard let link else { return nil }
    for part in link.split(separator: ",") {
      let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
      guard let target = pieces.first, target.hasPrefix("<"), target.hasSuffix(">"),
            pieces.dropFirst().contains(where: { $0 == #"rel="next""# }) else { continue }
      let address = String(target.dropFirst().dropLast())
      return address.hasPrefix(base + "/") ? address : nil
    }
    return nil
  }

  // MARK: README

  /// The README of one repository, as raw text. A 404 is the repository having none (kept like a
  /// text); anything else that is not a 2xx with a body is `unavailable` and, like a failed catalog
  /// read, not kept. A name that is not `owner/repo` is never asked for (`isRepositoryName`).
  public func readme(_ fullName: String) async -> MarketplaceReadme {
    guard Self.isRepositoryName(fullName) else { return .unavailable }
    if let cached = readmes[fullName], now().timeIntervalSince(cached.at) <= Self.cacheLifetime { return cached.readme }
    let token = await token()
    guard let url = URL(string: "\(base)/repos/\(fullName)/readme") else { return .unavailable }
    let request = Self.request(url, accept: "application/vnd.github.raw", token: token)
    let result = (try? await fetchReadme(request)) ?? .unavailable
    if result != .unavailable { readmes[fullName] = (now(), result) }
    return result
  }

  private func fetchReadme(_ request: URLRequest) async throws -> MarketplaceReadme {
    let (bytes, response) = try await session.bytes(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode else { return .unavailable }
    if status == 404 { bytes.task.cancel(); return .missing }
    // 204 and 205 carry no body: fetch had none to read (a 304 is no 2xx).
    guard (200..<300).contains(status), ![204, 205].contains(status) else { bytes.task.cancel(); return .unavailable }
    var data = Data()
    data.reserveCapacity(16 * 1024)
    var truncated = false
    for try await byte in bytes {
      if data.count == Self.readmeLimit {
        truncated = true
        bytes.task.cancel()
        break
      }
      data.append(byte)
    }
    // A cut in the middle of a character becomes U+FFFD, as with Buffer.toString.
    return .ok(text: String(decoding: data, as: UTF8.self), truncated: truncated)
  }

  /// QuartzControl's IPC rule for a README's repository (`marketplaceReadmeArgs`): at most 200
  /// UTF-16 units, `owner/repo` with the owner in `[A-Za-z0-9-]` and the repository in
  /// `[A-Za-z0-9._-]`, no "..", not ending in "/.". It keeps the name from walking the API path.
  public static func isRepositoryName(_ name: String) -> Bool {
    guard name.utf16.count <= 200, !name.contains(".."), !name.hasSuffix("/.") else { return false }
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
    let ascii = { (s: Unicode.Scalar) in ("a"..."z").contains(s) || ("A"..."Z").contains(s) || ("0"..."9").contains(s) }
    return parts[0].unicodeScalars.allSatisfy { ascii($0) || $0 == "-" }
      && parts[1].unicodeScalars.allSatisfy { ascii($0) || "._-".unicodeScalars.contains($0) }
  }

  // MARK: plumbing

  static func request(_ url: URL, accept: String, token: String?) -> URLRequest { // not a file path
    var request = URLRequest(url: url)
    request.setValue(accept, forHTTPHeaderField: "Accept")
    if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return request
  }
}

// MARK: - The page's two lists

extension MarketplaceResult {
  /// The org's own marker for "this is a plugin". A split rather than a filter: a forked plugin can
  /// be missing it, and hiding a real plugin is worse than listing an odd repository under "other".
  public static let pluginTopic = "quartz-plugin"

  /// The Marktplatz's two lists for a search (QuartzControl's `useMemo` in Marketplace.tsx): a
  /// substring of name, full name or description, ignoring case; plugins are the entries with the
  /// topic that are not archived (the org's archived entry is the Quartz core itself), everything
  /// else is "other". Both by stars, most first, and otherwise in the catalog's order (JavaScript's
  /// sort is stable).
  public func split(query: String) -> (plugins: [MarketplacePlugin], other: [MarketplacePlugin]) {
    let q = ReadmeText.trim(query).lowercased()
    let found = plugins.filter { plugin in
      q.isEmpty || plugin.name.lowercased().contains(q) || plugin.fullName.lowercased().contains(q)
        || (plugin.description ?? "").lowercased().contains(q)
    }
    let isPlugin = { (plugin: MarketplacePlugin) in plugin.isMarkedPlugin }
    func byStars(_ list: [MarketplacePlugin]) -> [MarketplacePlugin] {
      list.enumerated().sorted { a, b in
        let (x, y) = (a.element.stars ?? 0, b.element.stars ?? 0)
        return x != y ? x > y : a.offset < b.offset
      }.map(\.element)
    }
    return (byStars(found.filter(isPlugin)), byStars(found.filter { !isPlugin($0) }))
  }
}
