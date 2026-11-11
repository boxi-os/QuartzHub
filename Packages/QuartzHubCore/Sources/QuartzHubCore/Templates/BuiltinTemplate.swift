import Foundation

/// QuartzControl's `builtinTemplateService.ts`: where the basic template comes from when a project
/// is created with it.
///
/// The source is a file in a public repository, over plain HTTPS (no token, no API, no rate limit),
/// cached in the profile and asked again after a day. QuartzHub ships no copy of it, unlike
/// QuartzControl (decided 2026-11-11): creating a project clones Quartz from GitHub anyway, so a
/// copy for "a train and a first run" never helped there, and a change to the template needs no
/// release. A `bundled` copy is still taken where one is given, the newer `createdAt` winning and
/// a tie going to the copy, as QuartzControl does: the tests, and a development build looking at
/// the app without the network (`developmentCopy`). Every path ends at a package that can be
/// read, which is not the same as a file that exists: a torn cache is deleted and fetched again
/// on the spot.
///
/// The address is QuartzControl's, deliberately: every version of both apps asks the same file, so a
/// push there reaches them all.
public struct BuiltinTemplate: Sendable {
  public enum Source: String, Sendable { case downloaded, bundled }

  public struct Found: Equatable, Sendable {
    public var path: String
    public var source: Source
    /// Markdown files in the package's content part, 0 when it has none.
    public var pages: Int
    /// For `.bundled`: GitHub delivered a readable copy, just not a newer one. Without it the
    /// page said "GitHub nicht erreichbar" on a tie (measured 2026-11-10; QuartzControl says the
    /// same). Not part of the source, which stays QuartzControl's two values.
    public var downloadNotNewer: Bool = false
  }

  public static let url = "https://raw.githubusercontent.com/boxi-os/quartzcontrol-templates/main/qc-basic.qtpl"
  static let fileName = "qc-basic.qtpl"
  static let maxAge: TimeInterval = 24 * 60 * 60
  static let timeout: Duration = .seconds(15)
  /// A design and, here, its manual; anything larger is not that.
  public static let maxBytes = 25 * 1024 * 1024

  /// The repository's `Resources/templates/qc-basic.qtpl`, for the tests and for a development
  /// build without the network; nil in a release build, which ships none (review 2026-11-11, N4:
  /// a release build reads nothing from the source tree).
  public static let developmentCopy: String? = {
    #if DEBUG
    var root = #filePath
    for _ in 0..<6 { root = NodePath.dirname(root) }
    return "\(root)/Resources/templates/\(fileName)"
    #else
    return nil
    #endif
  }()

  let profile: ProfileDirectory
  let bundled: String?
  let fetch: FontService.Fetch
  let now: @Sendable () -> Date

  public init(profile: ProfileDirectory = .quartzHub, bundled: String? = nil, fetch: @escaping FontService.Fetch = FontService.limitedFetch(BuiltinTemplate.maxBytes),
              now: @escaping @Sendable () -> Date = { Date() }) {
    self.profile = profile
    self.bundled = bundled
    self.fetch = fetch
    self.now = now
  }

  var cached: String { "\(profile.path)/templates/\(Self.fileName)" }

  func age(_ url: String) -> TimeInterval {
    guard let modified = (try? FileManager.default.attributesOfItem(atPath: url))?[.modificationDate] as? Date else { return .infinity }
    return now().timeIntervalSince(modified)
  }

  /// Downloads the package; false on every failure, the caller falls back. What is cached is a
  /// package that reads (the directory walked, every CRC checked, a manifest there), not merely a
  /// file: a captive portal's page is not one.
  func refresh() async -> Bool {
    guard let response = try? await fetch(Self.url, nil, Self.timeout), (200..<300).contains(response.status) else { return false }
    let data = response.body
    guard !data.isEmpty, data.count <= Self.maxBytes, (try? ZipArchive.read(data))?[TemplatePackage.manifestFile] != nil else { return false }
    do {
      try Posix.mkdirs(NodePath.dirname(cached))
      try JSONStore.writeAtomic(data, to: cached)
      return true
    } catch {
      return false
    }
  }

  struct Info {
    var pages: Int
    /// Milliseconds; 0 when the manifest names no readable date, and such a copy never wins on age.
    var createdAt: Double
  }

  /// The whole package read, which is what "usable" means; its pages counted on the way.
  static func inspect(_ path: String) -> Info? {
    guard let files = try? ZipArchive.read(contentsOf: path), let manifest = files[TemplatePackage.manifestFile] else { return nil }
    return Info(pages: countPages(files[TemplatePackage.partFile("content")]), createdAt: createdAt(manifest))
  }

  /// `Date.parse` of the manifest's `createdAt`, for the forms an app writes (`toISOString()`).
  static func createdAt(_ raw: Data) -> Double {
    guard let text = (try? JSJSON.parse(raw))?["createdAt"]?.stringValue else { return 0 }
    let formatter = ISO8601DateFormatter()
    for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
      formatter.formatOptions = options
      if let date = formatter.date(from: text) { return (date.timeIntervalSince1970 * 1000).rounded() }
    }
    return 0
  }

  static func countPages(_ raw: Data?) -> Int {
    guard let raw, let files = (try? JSJSON.parse(raw))?["files"]?.arrayValue else { return 0 }
    return files.filter { $0.stringValue.map { JSText.endsWith($0.lowercased(), ".md") } ?? false }.count
  }

  /// A cached copy that does not read is deleted (its mtime would hold off the repair for a day)
  /// and fetched again at once.
  func usableCache() async -> Info? {
    guard FileManager.default.fileExists(atPath: cached) else { return nil }
    if let info = Self.inspect(cached) { return info }
    try? FileManager.default.removeItem(atPath: cached)
    return await refresh() ? Self.inspect(cached) : nil
  }

  /// The best package there is right now, and where it came from. Never throws.
  public func find() async -> Found? {
    if age(cached) > Self.maxAge { _ = await refresh() }
    let downloaded = await usableCache()
    let shipped = bundled.flatMap { path in Self.inspect(path).map { (path, $0) } }
    if let downloaded, shipped == nil || downloaded.createdAt > shipped!.1.createdAt {
      return Found(path: cached, source: .downloaded, pages: downloaded.pages)
    }
    if let (path, info) = shipped { return Found(path: path, source: .bundled, pages: info.pages, downloadNotNewer: downloaded != nil) }
    return nil
  }
}
