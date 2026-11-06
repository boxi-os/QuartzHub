import Foundation

/// A plugin's `source` as quartz.config.yaml writes it, in the shape QuartzControl's
/// `plugin.optionSchema` channel accepted (ipc/schemas.ts, `pluginOptionSchemaArgs`): a string that
/// is not empty and does not start with "-", or an object with a `repo` and maybe a `name`.
/// Anything else QuartzControl refused before its service ran; here it does not become a
/// `PluginSource` at all.
public enum PluginSource: Equatable, Sendable {
  case string(String)
  case object(repo: String, name: String?)

  /// Lengths count UTF-16 code units, as zod's `.min`/`.max` do.
  public init?(_ value: JSONValue?) {
    switch value {
    case .string(let source):
      guard (1...2048).contains(source.utf16.count), !source.hasPrefix("-") else { return nil }
      self = .string(source)
    case .object(let object):
      guard case .string(let repo)? = object["repo"], (1...2048).contains(repo.utf16.count) else { return nil }
      var name: String?
      switch object["name"] {
      case nil: break
      case .string(let given)? where (1...214).contains(given.utf16.count): name = given
      default: return nil
      }
      // The other keys zod named, with their bounds; unknown keys pass (looseObject).
      for (key, limit) in [("subdir", 1024), ("ref", 255)] {
        switch object[key] {
        case nil: break
        case .string(let text)? where text.utf16.count <= limit: break
        default: return nil
        }
      }
      self = .object(repo: repo, name: name)
    default:
      return nil
    }
  }

  var repo: String {
    switch self {
    case .string(let source): source
    case .object(let repo, _): repo
    }
  }

  /// The name quartz matches `layout.byPageType.<type>.exclude` against and installs a git plugin
  /// under: `extractPluginName` (plugins/loader/config-loader.ts), ported from QuartzControl's
  /// `shared/quartzPluginName.ts`. Not `PluginEntry.derivedName`: an npm source with a scope stays
  /// whole here (`@quartz-community/page-title`), and the git forms drop `.git` and `#ref`.
  /// A Windows path is cut as on macOS, at "/" only (QuartzControl measured that with
  /// `check:plugin-names`: `\` is an ordinary character in a POSIX file name).
  public var quartzName: String {
    if case .object(_, let name?) = self, !name.isEmpty { return name }
    return Self.quartzName(repo)
  }

  static func quartzName(_ source: String) -> String {
    if isLocal(source) {
      var trimmed = source
      while trimmed.hasSuffix("/") { trimmed.removeLast() }
      let last = trimmed.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
      return last.isEmpty ? trimmed : last
    }
    if source.hasPrefix("github:") {
      let path = String(source.dropFirst("github:".count))
      let repoPath = path.split(separator: "#", omittingEmptySubsequences: false).first.map(String.init) ?? ""
      return repoPath.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    }
    if source.hasPrefix("git+") || source.hasPrefix("https://") {
      // `replace('git+', '')`: the first occurrence anywhere, as JavaScript's string replace does.
      var url = source
      if let range = url.range(of: "git+") { url.removeSubrange(range) }
      if let match = url.firstMatch(of: Self.lastSegment) { return String(match.output.1) }
      return source
    }
    return source
  }

  /// quartz's `isLocalSource` (plugins/loader/gitLoader.ts), with its Windows drive letter.
  static func isLocal(_ source: String) -> Bool {
    source.firstMatch(of: Self.driveLetter) != nil || source.hasPrefix("./") || source.hasPrefix("../") || source.hasPrefix("/")
  }

  /// quartz's `parsePluginSource`: what is not a local path, `github:`, `git+` or `https://` is an
  /// npm package, and quartz looks for it under node_modules.
  var isNpm: Bool {
    let repo = repo
    return !Self.isLocal(repo) && !repo.hasPrefix("github:") && !repo.hasPrefix("git+") && !repo.hasPrefix("https://")
  }

  // Unicode scalars, as JavaScript's regular expressions without the `v` flag see a string (no
  // grapheme clusters: "\r\n" is two characters there).
  nonisolated(unsafe) private static let driveLetter = #/^[A-Za-z]:[\\/]/#.matchingSemantics(.unicodeScalar)
  nonisolated(unsafe) private static let lastSegment = #/\/([^\/]+?)(?:\.git)?(?:#|$)/#.matchingSemantics(.unicodeScalar)
}

extension PluginSource {
  /// The form quartz.config.yaml writes, for the golden tests.
  var jsonValue: JSONValue {
    switch self {
    case .string(let source): return .string(source)
    case .object(let repo, let name):
      var object = JSONObject([("repo", .string(repo))])
      if let name { object["name"] = .string(name) }
      return .object(object)
    }
  }
}
