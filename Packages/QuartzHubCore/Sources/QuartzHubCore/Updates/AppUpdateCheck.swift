import Foundation

/// Whether a newer QuartzHub exists (QuartzControl's `appUpdateService.ts`). Not an updater, an
/// answer: one HTTPS request and a line in the Projects window. It never downloads or installs.
///
/// Unlike QuartzControl, which read a `latest.json` from its template repository, it asks GitHub
/// for the repository's latest release: one file less to keep in step with every release, and
/// `releases/latest` already leaves out drafts and prereleases. Until the repository is public
/// (or has a release) GitHub answers 404, which is "unknown", and nothing is shown.
public enum AppUpdateCheck {
  public static let latestURL = URL(string: "https://api.github.com/repos/boxi-os/QuartzHub/releases/latest")!
  /// A release page is only offered when it is this repository's own.
  static let releasesPrefix = "https://github.com/boxi-os/QuartzHub/releases/"
  static let timeout: TimeInterval = 8
  /// QuartzControl's: the Projects window does not ask on every visit, and a day's work still
  /// learns of a release made that morning.
  static let maxAge: TimeInterval = 6 * 60 * 60

  public enum Status: Equatable, Sendable {
    case newer(current: String, latest: String, url: String?)
    case current(current: String, latest: String?)
    /// "Could not check" is never "up to date".
    case unknown(current: String)
  }

  /// The answer to one response: 200 with a tag that is a later version is "newer", 200 otherwise
  /// "current", anything else "unknown". The tag may carry a leading "v".
  public static func status(data: Data, statusCode: Int, current: String) -> Status {
    guard statusCode == 200,
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let tag = object["tag_name"] as? String
    else { return .unknown(current: current) }
    let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    guard SemVer.isNewer(latest, than: current) else { return .current(current: current, latest: latest.isEmpty ? nil : latest) }
    let page = (object["html_url"] as? String).flatMap { $0.hasPrefix(releasesPrefix) ? $0 : nil }
    return .newer(current: current, latest: latest, url: page)
  }

  private static let cache = Cache()

  private actor Cache {
    var entry: (at: Date, current: String, status: Status)?
    func get(_ current: String) -> Status? {
      guard let entry, entry.current == current, Date().timeIntervalSince(entry.at) < AppUpdateCheck.maxAge else { return nil }
      return entry.status
    }
    func set(_ current: String, _ status: Status) { entry = (Date(), current, status) }
  }

  /// One question to GitHub at most every six hours; `force` asks again.
  public static func check(current: String, force: Bool = false) async -> Status {
    if !force, let cached = await cache.get(current) { return cached }
    var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let status: Status
    do {
      let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
      status = Self.status(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, current: current)
    } catch {
      status = .unknown(current: current)
    }
    await cache.set(current, status)
    return status
  }
}
