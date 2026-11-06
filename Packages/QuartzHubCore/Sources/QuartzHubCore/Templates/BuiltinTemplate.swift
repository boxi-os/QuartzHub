import Foundation

/// QuartzControl's `builtinTemplateService.ts`: where the basic template comes from when a project
/// is created with it.
///
/// Two sources: a file in a public repository, over plain HTTPS (no token, no API, no rate limit),
/// cached in the profile and asked again after a day; and the copy inside the app, which makes the
/// feature work on a train and on a first run. Of the cached and the shipped copy the newer
/// `createdAt` wins, a tie goes to the copy (it cannot go away). Every path ends at a package
/// that can be read, which is not the same as a file that exists: a torn cache is deleted and
/// fetched again on the spot.
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
  }

  public static let url = "https://raw.githubusercontent.com/boxi-os/quartzcontrol-templates/main/qc-basic.qtpl"
  static let fileName = "qc-basic.qtpl"
  static let maxAge: TimeInterval = 24 * 60 * 60
  static let timeout: Duration = .seconds(15)
  /// A design and, here, its manual; anything larger is not that.
  static let maxBytes = 25 * 1024 * 1024

  /// The copy inside the app (`Contents/Resources/templates`), in a development build the
  /// repository's `Resources/templates`.
  public static let bundledCopy: String = {
    if let resources = Bundle.main.resourceURL.map({ Posix.path($0) }) {
      let packaged = "\(resources)/templates/\(fileName)"
      if FileManager.default.fileExists(atPath: packaged) { return packaged }
    }
    var root = #filePath
    for _ in 0..<6 { root = NodePath.dirname(root) }
    return "\(root)/Resources/templates/\(fileName)"
  }()

  let profile: ProfileDirectory
  let bundled: String
  let fetch: FontService.Fetch
  let now: @Sendable () -> Date

  public init(profile: ProfileDirectory = .quartzHub, bundled: String = BuiltinTemplate.bundledCopy, fetch: @escaping FontService.Fetch = FontService.liveFetch,
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
    let shipped = Self.inspect(bundled)
    if let downloaded, shipped == nil || downloaded.createdAt > shipped!.createdAt {
      return Found(path: cached, source: .downloaded, pages: downloaded.pages)
    }
    if let shipped { return Found(path: bundled, source: .bundled, pages: shipped.pages) }
    return nil
  }
}
