import Foundation

/// `quartz.config.yaml` as `readConfig` hands it out: `configuration` without `theme`, `theme` on
/// its own, the plugin entries with a derived `name`, and `layout` when there is one. Everything
/// stays a JSON view (`JSONValue.swift`): what QuartzHub does not know about goes back in the file
/// where it was.
public struct QuartzConfig: Equatable, Sendable {
  public var configuration: JSONObject
  public var theme: JSONObject
  public var plugins: [PluginEntry]
  /// Only `groups` and `byPageType` are written back; nil leaves the file's `layout:` alone.
  public var layout: JSONObject?

  public init(configuration: JSONObject = JSONObject(), theme: JSONObject = JSONObject(),
              plugins: [PluginEntry] = [], layout: JSONObject? = nil) {
    self.configuration = configuration
    self.theme = theme
    self.plugins = plugins
    self.layout = layout
  }
}

/// One entry of `plugins:`, as the object QuartzControl built for it: the entry's own keys, then
/// `name` and `enabled` where JavaScript's `{ ...entry, name, enabled }` puts them. `name` is never
/// written; an entry is addressed by its index, because two entries can derive the same name
/// (`@quartz-community/explorer` and `github:quartz-community/explorer`, plugins-and-config.md).
public struct PluginEntry: Equatable, Sendable {
  public var object: JSONObject

  public init(object: JSONObject) {
    self.object = object
  }

  public var name: String { object["name"]?.stringValue ?? "" }
  public var source: JSONValue? { object["source"] }

  /// Read the way Quartz's build reads it: only a truthy `enabled` builds. Its CLI takes a missing
  /// key as on, and following that made the next save of anything put the plugin on the site
  /// (configService.ts, readConfig).
  public var enabled: Bool {
    get { object["enabled"]?.boolValue ?? false }
    set { object["enabled"] = .bool(newValue) }
  }

  /// `deriveName` of configService.ts. Nil where QuartzControl threw a TypeError: an entry whose
  /// source is neither a string nor an object with a `name` or a `repo`.
  static func derivedName(_ source: JSONValue?) -> String? {
    switch source {
    case .string(let source):
      var withoutRef = source
      if withoutRef.hasPrefix("github:") { withoutRef.removeFirst("github:".count) }
      if withoutRef.hasPrefix("git+") { withoutRef.removeFirst("git+".count) }
      withoutRef = String(withoutRef.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
      let last = withoutRef.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
      return last.isEmpty ? withoutRef : last
    case .object(let object):
      if case .string(let name)? = object["name"], !name.isEmpty { return name }
      guard case .string(var repo)? = object["repo"] else { return nil }
      if repo.hasSuffix(".git") { repo.removeLast(4) }
      return repo.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    default:
      return nil
    }
  }
}

extension QuartzConfig {
  /// The object QuartzControl's renderer held, for the golden tests and for whoever wants to
  /// compare: `{ configuration, theme, plugins, layout }`.
  var jsonValue: JSONValue {
    var object = JSONObject([("configuration", .object(configuration)), ("theme", .object(theme)),
                             ("plugins", .array(plugins.map { .object($0.object) }))])
    if let layout { object["layout"] = .object(layout) }
    return .object(object)
  }

  init?(jsonValue: JSONValue) {
    guard let configuration = jsonValue["configuration"]?.objectValue, let theme = jsonValue["theme"]?.objectValue,
          let plugins = jsonValue["plugins"]?.arrayValue else { return nil }
    self.init(configuration: configuration, theme: theme,
              plugins: plugins.compactMap { $0.objectValue.map(PluginEntry.init) },
              layout: jsonValue["layout"]?.objectValue)
  }
}
