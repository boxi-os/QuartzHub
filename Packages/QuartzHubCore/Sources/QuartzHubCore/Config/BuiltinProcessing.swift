import Foundation

/// What a project's Quartz can do, read from the project itself rather than from a version number:
/// a checkout of the v5 branch between two releases carries the new code under the old
/// `package.json` version. Quartz 5.1 brought all four together.
public struct QuartzFeatures: Equatable, Sendable {
  /// `version` of the project's package.json (`5.1.0`), nil when unreadable.
  public var version: String?
  /// `quartz/plugins/builtins/index.ts`: frontmatter, links, drafts and the content index are part
  /// of Quartz, configured under `configuration.<key>` (`BuiltinProcessing`).
  public var builtins: Bool
  /// `configuration.prefetch` and `configuration.publishAssets`, declared in `quartz/cfg.ts`.
  public var prefetch: Bool
  public var publishAssets: Bool
  /// `layout.sidebars` (`fit`/`scroll`/`static`), declared in `quartz/cfg.ts`.
  public var sidebars: Bool
  /// PostHog's `apiHost`, `uiHost` and `personProfiles` and umami's `script`, declared in `quartz/cfg.ts`.
  public var analytics51: Bool

  public init(version: String? = nil, builtins: Bool = false, prefetch: Bool = false, publishAssets: Bool = false, sidebars: Bool = false,
              analytics51: Bool = false) {
    self.version = version
    self.builtins = builtins
    self.prefetch = prefetch
    self.publishAssets = publishAssets
    self.sidebars = sidebars
    self.analytics51 = analytics51
  }

  /// Everything a 5.1 project has, for tests and previews.
  public static let quartz51 = QuartzFeatures(version: "5.1.0", builtins: true, prefetch: true, publishAssets: true, sidebars: true,
                                              analytics51: true)

  public static func read(project: String) -> QuartzFeatures {
    var features = QuartzFeatures()
    if case .ok(let package) = JSONStore.peek(NodePath.join(project, "package.json")) {
      features.version = package["version"]?.stringValue
    }
    features.builtins = Posix.exists(NodePath.join(project, "quartz", "plugins", "builtins", "index.ts"))
    // The declarations, not the comments around them: `prefetch?: "viewport" | …`.
    if let data = try? Posix.read(NodePath.join(project, "quartz", "cfg.ts")), data.count < 1_000_000 {
      let text = String(decoding: data, as: UTF8.self)
      features.prefetch = text.contains("prefetch?:")
      features.publishAssets = text.contains("publishAssets?:")
      features.sidebars = text.contains("sidebars?:")
      features.analytics51 = text.contains("apiHost?:")
    }
    return features
  }
}

/// Quartz 5.1's built-in processing (`quartz/plugins/builtins/index.ts`, `planBuiltins`): which of
/// the four built-ins run, with which options and order, and which plugin entries they absorb.
///
/// | built-in      | configuration key            | formerly                        |
/// |---------------|------------------------------|---------------------------------|
/// | frontmatter   | `configuration.frontmatter`  | parsing half of note-properties |
/// | links         | `configuration.links`        | crawl-links                     |
/// | drafts        | `configuration.drafts`       | remove-draft                    |
/// | contentIndex  | `configuration.contentIndex` | content-index                   |
///
/// Ported from 5.1.0 and tested against its `builtins.test.ts` cases (BuiltinProcessingTests).
/// Deviations: a plugin's short name is the name QuartzHub derives from its source
/// (`PluginEntry.name`), not the manifest's `name`, which Quartz prefers; the two differ only for
/// a plugin whose package calls itself something else. The notices Quartz prints are not built:
/// QuartzHub says the same in its own words.
public enum BuiltinProcessing {
  public enum Builtin: String, CaseIterable, Sendable {
    case frontmatter, links, drafts, contentIndex

    public var configKey: String { rawValue }

    /// Position among plugins of the same category (the scale of a plugin's `order`).
    public var defaultOrder: Double {
      switch self {
      case .frontmatter: 0
      case .links: 60
      case .drafts, .contentIndex: 50
      }
    }

    public var defaults: JSONObject {
      switch self {
      case .frontmatter: JSONObject([("delimiters", .string("---")), ("language", .string("yaml"))])
      case .links:
        JSONObject([("markdownLinkResolution", .string("shortest")), ("prettyLinks", .bool(true)), ("openLinksInNewTab", .bool(false)),
                    ("lazyLoad", .bool(false)), ("externalLinkIcon", .bool(true)), ("disableBrokenWikilinks", .bool(false))])
      case .drafts: JSONObject([("publish", .bool(false))])
      case .contentIndex:
        JSONObject([("enableSiteMap", .bool(true)), ("enableRSS", .bool(true)), ("rssLimit", .number(10)), ("rssFullHtml", .bool(false)),
                    ("rssSlug", .string("index")), ("includeEmptyFiles", .bool(true))])
      }
    }

    /// The official plugin whose entry it absorbs (short name).
    public var absorbs: String? {
      switch self {
      case .frontmatter: nil
      case .links: "crawl-links"
      case .drafts: "remove-draft"
      case .contentIndex: "content-index"
      }
    }

    /// Defaults of the absorbed plugin that differ from the built-in's: crawl-links resolved
    /// "absolute", the built-in "shortest".
    var absorbedDefaults: JSONObject {
      self == .links ? JSONObject([("markdownLinkResolution", .string("absolute"))]) : JSONObject()
    }

    /// A plugin providing any of these replaces it (`replacedBy`).
    var replacedBy: [String: [String]] {
      switch self {
      case .frontmatter: ["data": ["frontmatter"]]
      case .links: ["data": ["links"]]
      case .drafts: [:]
      case .contentIndex: ["files": ["static/contentIndex.json"]]
      }
    }
  }

  public enum Note: Equatable, Sendable {
    /// `configuration.<key>.enabled: false` (or `<key>: false`).
    case disabledInConfiguration
    /// The absorbed plugin's entry is there and off, and the configuration does not say.
    case disabledByEntry(plugin: String)
    /// An enabled plugin provides the same thing.
    case replacedBy(plugin: String)
  }

  public struct Planned: Equatable, Sendable {
    public var builtin: Builtin
    public var enabled: Bool
    public var options: JSONObject
    public var order: JSONValue
    public var note: Note?
    /// Index into `plugins` of the entry whose settings it took (the enabled one, else the first).
    public var absorbed: Int?
  }

  public struct Plan: Equatable, Sendable {
    public var builtins: [Planned]
    /// Indices into `plugins` of the entries Quartz handles itself: not installed, not loaded.
    public var absorbedEntries: Set<Int>

    public subscript(builtin: Builtin) -> Planned { builtins.first { $0.builtin == builtin }! }

    /// Whether `draft: true` keeps a page off the site.
    public var removesDrafts: Bool {
      let drafts = self[.drafts]
      return drafts.enabled && drafts.options["publish"] != .bool(true)
    }
  }

  /// Short name of an official `quartz-community` plugin source, nil for anything else.
  public static func officialPluginName(_ source: JSONValue?) -> String? {
    switch source {
    case .object(let object)?: return officialPluginName(object["repo"])
    case .string(let source)?:
      if let match = source.wholeMatch(of: npmOfficial) { return String(match.output.1) }
      if let match = source.wholeMatch(of: githubOfficial) { return String(match.output.1) }
      return nil
    default: return nil
    }
  }

  nonisolated(unsafe) private static let npmOfficial = #/@quartz-community\/([a-z0-9-]+)(?:@.*)?/#.matchingSemantics(.unicodeScalar)
  nonisolated(unsafe) private static let githubOfficial =
    #/(?:github:|git\+https:\/\/github\.com\/|https:\/\/github\.com\/)quartz-community\/([a-z0-9-]+?)(?:\.git)?(?:#.*)?/#.matchingSemantics(.unicodeScalar)

  /// The built-in that absorbs this entry, if its plugin now lives in Quartz.
  public static func absorbing(_ entry: PluginEntry) -> Builtin? {
    guard let name = officialPluginName(entry.source) else { return nil }
    return Builtin.allCases.first { $0.absorbs == name }
  }

  /// The entries `quartz plugin doctor --fix` would change (`findBuiltinMigrations`): every entry of
  /// an absorbed plugin, on or off, and note-properties while its options name `delimiters` or
  /// `language`. Indices into `plugins`.
  public static func pendingMigrations(_ plugins: [PluginEntry]) -> [Int] {
    plugins.indices.filter { index in
      let entry = plugins[index]
      if absorbing(entry) != nil { return true }
      guard officialPluginName(entry.source) == "note-properties", let options = entry.object["options"]?.objectValue else { return false }
      return options["delimiters"] != nil || options["language"] != nil
    }
  }

  /// `planBuiltins`. `providesOf` gives an enabled entry's `quartz.capabilities.provides`
  /// (`providedCapabilities`); nil when it declares none.
  public static func plan(configuration: JSONObject, plugins: [PluginEntry],
                          providesOf: (PluginEntry) -> [String: [String]]? = { _ in nil }) -> Plan {
    var absorbedEntries = Set<Int>()
    var planned: [Planned] = []
    let shortName = { (entry: PluginEntry) in officialPluginName(entry.source) ?? entry.name }

    for builtin in Builtin.allCases {
      var configured = JSONObject()
      switch configuration[builtin.configKey] {
      case .bool(let flag)?: configured["enabled"] = .bool(flag)
      case .object(let object)?: configured = object
      default: break
      }
      let explicitEnabled = configured["enabled"]
      let configuredOrder = configured["order"]
      configured["enabled"] = nil
      configured["order"] = nil

      var options = builtin.defaults
      var order = JSONValue.number(builtin.defaultOrder)
      var enabled = explicitEnabled != .bool(false)
      var note: Note? = explicitEnabled == .bool(false) ? .disabledInConfiguration : nil
      var absorbed: Int?

      // 1. The entry of the official plugin it replaces.
      let legacy = plugins.indices.filter { absorbing(plugins[$0]) == builtin }
      absorbedEntries.formUnion(legacy)
      if let index = legacy.first(where: { plugins[$0].enabled }) ?? legacy.first {
        absorbed = index
        let entry = plugins[index]
        if entry.enabled {
          merge(&options, builtin.absorbedDefaults)
          if let own = entry.object["options"]?.objectValue { merge(&options, own) }
          if let own = entry.object["order"], own != .null { order = own }
        } else if explicitEnabled == nil {
          enabled = false
          note = .disabledByEntry(plugin: shortName(entry))
        }
      }

      // 2. Options a still-supported plugin donates: note-properties' delimiters and language.
      if builtin == .frontmatter, let donor = plugins.first(where: { $0.enabled && shortName($0) == "note-properties" }) {
        for key in ["delimiters", "language"] {
          if let value = donor.object["options"]?.objectValue?[key], configured[key] == nil { options[key] = value }
        }
      }

      merge(&options, configured)
      if case .number? = configuredOrder { order = configuredOrder! }

      // 3. Yield to an enabled plugin that provides the same thing, unless forced on.
      if enabled, explicitEnabled != .bool(true),
         let provider = plugins.indices.first(where: { index in
           plugins[index].enabled && !absorbedEntries.contains(index) && !legacy.contains(index)
             && overlaps(builtin.replacedBy, providesOf(plugins[index]))
         }) {
        enabled = false
        note = .replacedBy(plugin: plugins[provider].name)
      }

      planned.append(Planned(builtin: builtin, enabled: enabled, options: options, order: order, note: note, absorbed: absorbed))
    }
    return Plan(builtins: planned, absorbedEntries: absorbedEntries)
  }

  /// `{ ...a, ...b }`: b's keys win, a's order stays, new keys go to the end.
  static func merge(_ into: inout JSONObject, _ other: JSONObject) {
    for key in other.keys { into[key] = other[key] }
  }

  static func overlaps(_ wanted: [String: [String]], _ provided: [String: [String]]?) -> Bool {
    guard let provided else { return false }
    let strip = { (name: String) in String(name.drop { $0 == "/" }) }
    for (kind, names) in wanted {
      let other = Set((provided[kind] ?? []).map(strip))
      if names.contains(where: { other.contains(strip($0)) }) { return true }
    }
    return false
  }

  /// `quartz.capabilities.provides` of a plugin's package.json, as `parseCapabilities` keeps it:
  /// string entries of the known kinds.
  public static func providedCapabilities(project: String, entry: PluginEntry) -> [String: [String]]? {
    guard let source = PluginSource(entry.source), let dir = PluginSchemaReader.packageDirectory(project: project, source: source),
          case .ok(let package) = JSONStore.peek(NodePath.join(dir, "package.json")),
          case .object(let provides)? = package["quartz"]?["capabilities"]?["provides"] else { return nil }
    var out: [String: [String]] = [:]
    for kind in provides.keys where ["data", "dom", "globals", "events", "files", "cssVars"].contains(kind) {
      if case .array(let list)? = provides[kind] { out[kind] = list.compactMap(\.stringValue) }
    }
    return out
  }
}
