import Darwin
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// The registry's answers for `ThemeCatalogTests`: a body, or a network error without one; every
/// request counted. Its own class, so `ThemeNet`'s golden run does not share its state.
final class CatalogNet: URLProtocol, @unchecked Sendable {
  struct State {
    var answers: [String: String] = [:]
    var requests: [String] = []
  }

  static let state = Mutex(State())

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogNet.self]
    return configuration
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!.absoluteString
    let body: String? = Self.state.withLock { state in
      state.requests.append(url)
      return state.answers[url]
    }
    guard let body else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: body == "404" ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: [:])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct ThemeCatalogTests {
  static let registry = ThemeCatalog.registryURL
  /// Entries as the real list has them (2026-11-23), and the ones a third party's file might hold.
  static let list = #"""
  [{"name":"Minimal","author":"kepano","repo":"kepano/obsidian-minimal","screenshot":"dark-simple.png","modes":["dark","light"]},
   {"name":"Amethyst","author":"cotemaxime","repo":"cotemaxime/obsidian-amethyst","screenshot":"screenshot.png","modes":["dark","light"],"legacy":true},
   {"name":"Tokyo Night","author":"tcmmichaelb139","repo":"tcmmichaelb139/obsidian-tokyonight","screenshot":"assets/Cover Shot.png","modes":["dark","sepia"]},
   {"name":"Wolai","author":"liicos","repo":"liicos/obsidian-wolai-theme","screenshot":"screenshot.png ","modes":["light"]},
   {"name":"80's Neon","author":"","repo":"someone/neon","screenshot":"","modes":["dark"]},
   {"name":"Café","repo":"x/cafe","screenshot":"../../other/repo/x.png"},
   {"name":"Bad repo","repo":"a/b/c","screenshot":"s.png","modes":["dark"]},
   {"repo":"no/name","screenshot":"s.png","modes":["dark"]}]
  """#

  let scratch = TestFolder.make("qh-catalog")
  var profile: ProfileDirectory { ProfileDirectory("\(scratch)/userData") }
  var copy: String { "\(scratch)/userData/theme-docs/community-css-themes.json" }

  init() {
    CatalogNet.state.withLock { $0 = CatalogNet.State() }
  }

  func online(_ body: String = Self.list) { CatalogNet.state.withLock { $0.answers[Self.registry] = body } }
  func offline() { CatalogNet.state.withLock { $0.answers = [:] } }
  var requests: Int { CatalogNet.state.withLock { $0.requests.count } }

  func catalog(now: @escaping @Sendable () -> Date = Date.init) -> ThemeCatalog {
    ThemeCatalog(profile: profile, configuration: CatalogNet.configuration, now: now)
  }

  /// The copy in the profile, `hours` old.
  func writeCopy(hoursOld hours: Double, _ body: String = Self.list) throws {
    try Posix.mkdirs(NodePath.dirname(copy))
    try Posix.write(copy, Data(body.utf8))
    let t = Date().addingTimeInterval(-hours * 3600).timeIntervalSince1970
    var times = [timeval(tv_sec: Int(t), tv_usec: 0), timeval(tv_sec: Int(t), tv_usec: 0)]
    #expect(utimes(copy, &times) == 0)
  }

  /// A clock the test moves.
  final class Clock: @unchecked Sendable {
    let time = Mutex(Date())
    func advance(hours: Double) { time.withLock { $0 = $0.addingTimeInterval(hours * 3600) } }
    var now: @Sendable () -> Date { { self.time.withLock { $0 } } }
  }

  @Test func theListBecomesTheCatalog() async throws {
    online()
    let listing = try #require(await catalog().list())
    #expect(listing.current)
    #expect(listing.themes.map(\.name) == ["Minimal", "Amethyst", "Tokyo Night", "Wolai", "80's Neon", "Café"])
    #expect(listing.themes[0] == ThemeCatalog.Theme(name: "Minimal", author: "kepano", repo: "kepano/obsidian-minimal", modes: ["dark", "light"],
                                                   screenshotURL: "https://raw.githubusercontent.com/kepano/obsidian-minimal/HEAD/dark-simple.png"))
    #expect(listing.themes[1].legacy && !listing.themes[0].legacy)
    // Each segment encoded, the slash kept; an unknown mode dropped.
    #expect(listing.themes[2].screenshotURL == "https://raw.githubusercontent.com/tcmmichaelb139/obsidian-tokyonight/HEAD/assets/Cover%20Shot.png")
    #expect(listing.themes[2].modes == ["dark"])
    #expect(listing.themes[3].screenshotURL == "https://raw.githubusercontent.com/liicos/obsidian-wolai-theme/HEAD/screenshot.png")
    // No author, no screenshot; a screenshot outside the repo is none.
    #expect(listing.themes[4].author == nil && listing.themes[4].screenshotURL == nil)
    #expect(listing.themes[5].screenshotURL == nil && listing.themes[5].modes.isEmpty)
    #expect(requests == 1)
    // Kept in the profile, compact, every field as it came.
    let kept = try JSJSON.parse(Posix.read(copy))
    #expect(kept.arrayValue?.count == 8)
    #expect(kept.arrayValue?.first?[safe: "screenshot"] == .string("dark-simple.png"))
  }

  @Test func aDayInMemory() async throws {
    online()
    let clock = Clock()
    let catalog = catalog(now: clock.now)
    _ = await catalog.list()
    clock.advance(hours: 23)
    _ = await catalog.list()
    #expect(requests == 1)
    clock.advance(hours: 2)
    _ = await catalog.list()
    #expect(requests == 2)
  }

  @Test func aYoungCopyAnswersWithoutAsking() async throws {
    try writeCopy(hoursOld: 23)
    online("[]")
    let listing = try #require(await catalog().list())
    #expect(listing.current && listing.themes.count == 6)
    #expect(abs(listing.fetched.timeIntervalSinceNow + 23 * 3600) < 2)
    #expect(requests == 0)
  }

  @Test func anOldCopyIsReplaced() async throws {
    try writeCopy(hoursOld: 25, #"[{"name":"Old","repo":"o/old","screenshot":"","modes":["dark"]}]"#)
    online()
    let listing = try #require(await catalog().list())
    #expect(listing.current && listing.themes.count == 6)
    #expect(requests == 1)
    #expect(try JSJSON.parse(Posix.read(copy)).arrayValue?.count == 8)
  }

  /// Offline: the old copy answers, not current, and the network is asked again after 15 minutes.
  @Test func offlineTheOldCopyAnswers() async throws {
    try writeCopy(hoursOld: 50)
    offline()
    let clock = Clock()
    let catalog = catalog(now: clock.now)
    let listing = try #require(await catalog.list())
    #expect(!listing.current && listing.themes.count == 6)
    #expect(abs(listing.fetched.timeIntervalSinceNow + 50 * 3600) < 2)
    clock.advance(hours: 0.2)
    _ = await catalog.list()
    #expect(requests == 1)
    online()
    clock.advance(hours: 0.1)
    #expect(await catalog.list()?.current == true)
    #expect(requests == 2)
  }

  @Test func nothingToAnswerWith() async throws {
    offline()
    let clock = Clock()
    let catalog = catalog(now: clock.now)
    #expect(await catalog.list() == nil)
    #expect(await catalog.list() == nil)
    #expect(requests == 1)
    clock.advance(hours: 0.3)
    online()
    #expect(await catalog.list()?.themes.count == 6)
    #expect(requests == 2)
  }

  /// Not a list, an empty one, a 404: none of them replaces the copy.
  @Test func aBadAnswerKeepsTheCopy() async throws {
    for body in ["{}", "[]", "404", "<html>"] {
      try writeCopy(hoursOld: 30)
      online(body)
      let listing = try #require(await catalog().list(), "\(body)")
      #expect(!listing.current && listing.themes.count == 6, "\(body)")
    }
  }

  /// "Neu laden" and the Settings page's "Cache leeren": the network first, even with a young copy.
  @Test func invalidateAsksTheNetwork() async throws {
    try writeCopy(hoursOld: 1)
    offline()
    let catalog = catalog()
    #expect(await catalog.list()?.current == true)
    #expect(requests == 0)
    await catalog.invalidate()
    #expect(await catalog.list()?.current == false)
    #expect(requests == 1)
  }

  @Test func callersAtOnceShareOneRequest() async throws {
    online()
    let catalog = catalog()
    async let first = catalog.list()
    async let second = catalog.list()
    let (a, b) = await (first, second)
    #expect(a != nil && a == b)
    #expect(requests == 1)
  }

  /// `StyleSettingsSchema` looks a theme up in the catalog it is given: one list for both.
  @Test func theSchemaSharesTheList() async throws {
    online()
    CatalogNet.state.withLock { $0.answers["https://raw.githubusercontent.com/tcmmichaelb139/obsidian-tokyonight/HEAD/theme.css"] = "404"
                                $0.answers["https://raw.githubusercontent.com/tcmmichaelb139/obsidian-tokyonight/HEAD/obsidian.css"] = "404" }
    let catalog = catalog()
    _ = await catalog.list()
    let schema = StyleSettingsSchema(profile: profile, configuration: CatalogNet.configuration, readYaml: { _ in nil }, catalog: catalog)
    #expect(try await schema.schema(themeId: "tokyo-night") == .null)
    let asked = CatalogNet.state.withLock { $0.requests }
    #expect(asked.filter { $0 == Self.registry }.count == 1)
    #expect(asked.count == 3)
    // Clearing an answer makes the catalog ask again.
    try await schema.clearCache(themeId: "tokyo-night")
    _ = await catalog.list()
    #expect(CatalogNet.state.withLock { $0.requests }.filter { $0 == Self.registry }.count == 2)
  }

  /// core 3.1.1's order: repo, name as written, case aside, slug; built-in, path and URL are no entry.
  @Test func findsAsCoreDoes() throws {
    let themes = [ThemeCatalog.Theme(name: "Minimal", repo: "kepano/obsidian-minimal"), ThemeCatalog.Theme(name: "minimal", repo: "x/lower"),
                  ThemeCatalog.Theme(name: "Tokyo Night", repo: "tcmmichaelb139/obsidian-tokyonight"), ThemeCatalog.Theme(name: "80's Neon", repo: "s/neon"),
                  ThemeCatalog.Theme(name: "Café Élégant", repo: "x/cafe"), ThemeCatalog.Theme(name: "Default", repo: "d/default")]
    let found = { (spec: String) in ThemeCatalog.find(spec, in: themes)?.repo }
    #expect(found("Minimal") == "kepano/obsidian-minimal")
    #expect(found("minimal") == "x/lower")
    #expect(found("MINIMAL") == "kepano/obsidian-minimal")
    #expect(found("  tokyo night ") == "tcmmichaelb139/obsidian-tokyonight")
    #expect(found("tokyo-night") == "tcmmichaelb139/obsidian-tokyonight")
    #expect(found("80s-neon") == "s/neon")
    #expect(found("cafe-elegant") == "x/cafe")
    #expect(found("Kepano/Obsidian-Minimal") == "kepano/obsidian-minimal")
    #expect(found("kepano/other") == nil)
    for none in ["default", "Obsidian", "obsidian default", "./themes/x", "~/x", "/abs/theme.css", "my.css", "https://example.org/theme",
                 "Tokio Night", ""] {
      #expect(found(none) == nil, "\(none)")
    }
  }

  /// core's slug: the expected values are what core 3.1.1's own `slugify` line (`dist/index.js`) gave for these names, run by hand.
  @Test func slugAsCore() {
    #expect(ThemeCatalog.slug("80's Neon") == "80s-neon")
    #expect(ThemeCatalog.slug("Café Élégant") == "cafe-elegant")
    #expect(ThemeCatalog.slug("  AnuPpuccin!! ") == "anuppuccin")
    #expect(ThemeCatalog.slug("It’s—Theme") == "its-theme")
  }
}
