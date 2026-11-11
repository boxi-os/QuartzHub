import Foundation

/// Which Quartz a project has and what changed between two releases, from the project's own git
/// objects: `package.json`'s version and the changesets `CHANGELOG.md`, at HEAD or at the upstream
/// commit the status found. That is what `npx quartz upgrade` shows since 5.1
/// (`cli/upgrade.js`, `describeUpgrade`), without its network fetch.
extension CoreUpdate {
  public struct Versions: Sendable, Equatable {
    /// `version` of package.json at HEAD.
    public var installed: String?
    /// The same at the newest upstream commit, when that commit is in the project (the Updates
    /// page's status fetches it).
    public var latest: String?
  }

  public func versions(project: String, latestCommit: String) async -> Versions {
    async let installed = packageVersion(project, "HEAD")
    async let latest = latestCommit.isEmpty ? nil : packageVersion(project, latestCommit)
    return Versions(installed: await installed, latest: await latest)
  }

  func packageVersion(_ project: String, _ revision: String) async -> String? {
    await jsonAt(project, revision, "package.json")?["version"]?.stringValue
  }

  /// The release notes after `from` up to `to`, newest first, from CHANGELOG.md at `revision`.
  public func releaseNotes(project: String, revision: String, from: String?, to: String?) async -> [ReleaseNotes.Section] {
    let shown = await git(project, ["show", "\(revision):CHANGELOG.md"])
    guard shown.success else { return [] }
    return ReleaseNotes.sections(shown.stdout, from: from, to: to)
  }
}

/// `changelogSections` of Quartz's cli/upgrade.js: the "## 5.1.0" sections of a changesets
/// CHANGELOG.md for versions after `from` up to and including `to`. A heading that is no valid
/// version starts no section (its lines are dropped, as there); a `from` or `to` that is no valid
/// version does not limit. Versions compare by `SemVer` (QuartzControl's semver.ts), which reads
/// changesets' headings as the semver package does.
public enum ReleaseNotes {
  public struct Section: Sendable, Equatable {
    public var version: String
    public var body: String
  }

  public static func sections(_ markdown: String, from: String?, to: String?) -> [Section] {
    var sections: [(version: String, lines: [String])] = []
    var current: Int?
    for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(raw)
      if let heading = line.wholeMatch(of: /## (\S+)\s*/) {
        let version = String(heading.1)
        if SemVer.parse(version) != nil {
          sections.append((version, []))
          current = sections.count - 1
        } else {
          current = nil
        }
        continue
      }
      if let current { sections[current].lines.append(line) }
    }
    let lower = from.flatMap { SemVer.parse($0) != nil ? $0 : nil }
    let upper = to.flatMap { SemVer.parse($0) != nil ? $0 : nil }
    return sections
      .filter { section in
        (lower.map { SemVer.isNewer(section.version, than: $0) } ?? true) && (upper.map { !SemVer.isNewer(section.version, than: $0) } ?? true)
      }
      .sorted { SemVer.isNewer($0.version, than: $1.version) }
      .map { Section(version: $0.version, body: $0.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)) }
  }
}
