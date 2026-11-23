import Foundation

/// What a `@quartz-themes/core` entry resolves to, asked of the project's own core 3 (helper
/// `theme-fetch`) with the entry's options, the way its build will ask: name, modes, version and
/// source of the theme, the Style Settings preset of a 2.x id, and its CSS. What core downloads on
/// the way lands in the cache the build reads, so a theme loaded here builds without network
/// (docs/plan-themes-core-3.md, step 1; measured in decisions/phase-5-gleichstand.md, „themes-core 3“).
///
/// Which names core knows is core's answer, not QuartzHub's: `default` is Obsidian's built-in theme
/// since 3.1.1 and an unknown name before, and a typo comes back with core's three suggestions.
public enum ThemeFetch {
  public struct Theme: Equatable, Sendable {
    /// Display name (`Minimal`, `Obsidian default`, the folder of a local file).
    public var name: String
    /// `dark`, `light`; nil when core does not know (a URL, a local file).
    public var modes: [String]?
    /// The release the CSS came from; nil for HEAD, a URL, a file and the built-in theme.
    public var version: String?
    /// Where the CSS came from: an address, a path, or `built-in`.
    public var source: String
    /// The Style Settings a 2.x id such as `catppuccin.frappe` stood for, applied under the entry's own.
    public var preset: JSONObject?
    /// The theme's own `theme.css`, unconverted ("" for the built-in theme).
    public var css: String
    /// The Style Settings blocks core found in the theme and its snippets (`parseStyleSettings`),
    /// each the YAML document as core read it: the ones the build applies values to.
    public var settingsBlocks: [JSONValue]
    /// The first line of each block core could not read.
    public var settingsErrors: [String]

    public init(name: String, modes: [String]? = nil, version: String? = nil, source: String, preset: JSONObject? = nil, css: String,
                settingsBlocks: [JSONValue] = [], settingsErrors: [String] = []) {
      self.name = name
      self.modes = modes
      self.version = version
      self.source = source
      self.preset = preset
      self.css = css
      self.settingsBlocks = settingsBlocks
      self.settingsErrors = settingsErrors
    }
  }

  public enum Outcome: Equatable, Sendable {
    case loaded(Theme)
    /// Core's own sentence: not in the registry (with suggestions), not downloadable and not cached, no such file.
    case notLoaded(String)
  }

  public struct Answer: Equatable, Sendable {
    /// The installed core's package.json `version`.
    public var coreVersion: String?
    public var outcome: Outcome
  }

  /// Why core was not asked: missing and unpacking are a step away (`npm install`, wait), the
  /// others are broken; two kinds of failing, two answers.
  public enum Failure: Error, Equatable, CustomStringConvertible {
    case coreMissing
    /// The installed core has no `resolveTheme`: 2.x, which wants Quartz 5.2.1 or newer.
    case coreOld(version: String?)
    /// npm is still unpacking this package.
    case unpacking(String)
    case coreBroken(String)
    case helper(String)

    public var description: String {
      switch self {
      case .coreMissing: "@quartz-themes/core is not installed"
      case .coreOld(let version): "@quartz-themes/core \(version ?? "?") has no resolveTheme"
      case .unpacking(let name): "npm is still unpacking \(name)"
      case .coreBroken(let error): "@quartz-themes/core does not load: \(error)"
      case .helper(let report): report
      }
    }
  }

  /// `options` are the entry's options as they stand in quartz.config.yaml; the helper takes from
  /// them what the build takes (`theme`, `variation`, `version`, `cacheDir`, `cacheHours`,
  /// `snippets`). Downloads at most the registry, a manifest, a stylesheet and the snippets given as
  /// addresses, each with core's 20 s; a snippet that cannot be had fails the theme, as in the build.
  public static func fetch(project: String, options: JSONObject, offline: Bool = Offline.isOn,
                           runtime: RuntimeLocation = .current) async throws(Failure) -> Answer {
    if let unpacking = ProjectDependencies.halfUnpackedModule(project: project, "@quartz-themes/core") {
      throw .unpacking(unpacking)
    }
    let request = JSONObject([("project", .string(project)), ("options", .object(options)), ("offline", .bool(offline))])
    let answer: JSONObject
    do {
      answer = try await Helper.call("theme-fetch", request, runtime: runtime, timeout: .seconds(120))
    } catch {
      throw .helper(error.description)
    }
    return try read(answer)
  }

  static func read(_ answer: JSONObject) throws(Failure) -> Answer {
    let coreVersion = answer["coreVersion"]?.stringValue
    switch answer["core"]?.stringValue {
    case "missing": throw .coreMissing
    case "broken": throw .coreBroken(answer["error"]?.stringValue ?? "")
    case "old": throw .coreOld(version: coreVersion)
    case "3": break
    default: throw .helper("unknown answer")
    }
    if let failed = answer["failed"]?.stringValue {
      return Answer(coreVersion: coreVersion, outcome: .notLoaded(failed))
    }
    guard let theme = answer["theme"]?.objectValue, let name = theme["name"]?.stringValue,
          let source = theme["source"]?.stringValue, let css = theme["css"]?.stringValue else {
      throw .helper("no theme")
    }
    let settings = answer["settings"]?.objectValue
    return Answer(coreVersion: coreVersion, outcome: .loaded(Theme(
      name: name,
      modes: theme["modes"]?.arrayValue?.compactMap(\.stringValue),
      version: theme["version"]?.stringValue,
      source: source,
      preset: theme["styleSettings"]?.objectValue,
      css: css,
      settingsBlocks: settings?["sections"]?.arrayValue ?? [],
      settingsErrors: settings?["errors"]?.arrayValue?.compactMap(\.stringValue) ?? [])))
  }
}
