import Foundation

/// What `layout.byPageType.<type>` says and how the stage's page type selector changes it: a port
/// of QuartzControl's `routes/LayoutEditor/pageTypeOverride.ts`, measured with
/// `scripts/layout-board-golden.mjs`.
///
/// Quartz reads three keys there (`config-loader.ts`): `exclude` drops components by
/// `extractPluginName(source)`, an *empty* list under `positions.<pos>` clears that position (any
/// other value is ignored), and `template` names the frame. The frame is `template` ?? the page
/// type plugin's own ?? "default", and a name no frame is registered under renders the default one.
///
/// An entry that is not an object reads as one that customizes nothing.
public enum PageTypeOverride {
  public static let builtinFrames = ["default", "full-width", "minimal"]

  /// What `layout.byPageType.<type>` holds, as it is; nil without a key.
  public static func stored(_ config: QuartzConfig, _ pageType: String) -> JSONValue? {
    GridFrameCss.member(config.layout?["byPageType"], pageType)
  }

  /// `overrideOf`.
  public static func of(_ config: QuartzConfig, _ pageType: String) -> JSONObject {
    GridFrameCss.member(config.layout?["byPageType"], pageType)?.objectValue ?? JSONObject()
  }

  /// `hasPageTypeOverride`: a `{}` (1.0 wrote one for a click) or a list emptied toggle by toggle
  /// customizes nothing; `positions: { beforeBody: [] }` does, the key is the point.
  public static func customizes(_ override: JSONObject?) -> Bool {
    guard let override else { return false }
    if let template = override["template"], JS.truthy(template) { return true }
    if let exclude = override["exclude"], JS.truthy(exclude), length(exclude) > 0 { return true }
    if let positions = override["positions"], JS.truthy(positions), !LayoutBoxes.spread(positions).isEmpty { return true }
    return false
  }

  /// `.length` of a list or a text; nil for what has none.
  static func length(_ value: JSONValue) -> Int {
    switch value {
    case .array(let items): items.count
    case .string(let text): text.utf16.count
    default: 0
    }
  }

  static func quartzName(_ plugin: PluginEntry) -> String? {
    PluginRepository.quartzName(plugin.source)
  }

  /// `isExcluded`, by Quartz's name: an entry in the display spelling excludes nothing.
  public static func isExcluded(_ override: JSONObject, _ plugin: PluginEntry) -> Bool {
    guard let name = quartzName(plugin) else { return false }
    switch override["exclude"] {
    case .array(let items)?: return items.contains(.string(name))
    case .string(let text)?: return name.isEmpty || text.contains(name)
    default: return false
    }
  }

  /// `isPositionCleared`: only an empty list clears.
  public static func isCleared(_ override: JSONObject, _ position: String) -> Bool {
    GridFrameCss.member(override["positions"], position) == .array([])
  }

  /// `deadExcludes`: names of this config's plugins in the app's spelling rather than Quartz's.
  /// They exclude nothing, so they go the next time this page type is written; converting them
  /// would hide a component on the site because of an app update.
  public static func deadExcludes(_ config: QuartzConfig, _ override: JSONObject) -> [String] {
    var dead: [String] = []
    for case .string(let name) in override["exclude"]?.arrayValue ?? [] where !dead.contains(name) {
      if config.plugins.contains(where: { $0.name == name && quartzName($0) != name }) { dead.append(name) }
    }
    return dead
  }

  /// `withOverride`: the one door every change to a page type goes through. A page type that
  /// customizes nothing any more leaves `byPageType` instead of staying as `{}`, and the dead
  /// excludes go out here, because "written" has three doors. A nil value in `patch` removes the key.
  public static func with(_ config: QuartzConfig, _ pageType: String, _ patch: [(String, JSONValue?)]) -> QuartzConfig {
    let current = of(config, pageType)
    let dead = deadExcludes(config, current)
    var merged = current
    for (key, value) in patch { merged[key] = value }
    if case .array(let exclude)? = merged["exclude"], exclude.contains(where: { $0.stringValue.map(dead.contains) ?? false }) {
      let kept = exclude.filter { !($0.stringValue.map(dead.contains) ?? false) }
      merged["exclude"] = kept.isEmpty ? nil : .array(kept)
    }
    if let exclude = merged["exclude"], exclude == .array([]) || exclude == .string("") { merged["exclude"] = nil }
    if let positions = merged["positions"], JS.truthy(positions), LayoutBoxes.spread(positions).isEmpty { merged["positions"] = nil }
    var byPageType = LayoutBoxes.spread(config.layout?["byPageType"])
    byPageType[pageType] = customizes(merged) ? .object(merged) : nil
    var next = config
    var layout = config.layout ?? JSONObject()
    layout["byPageType"] = .object(byPageType)
    next.layout = layout
    return next
  }

  /// `withExcluded`: by Quartz's name, so every instance of the component is hit; Quartz cannot
  /// exclude one duplicate on its own.
  public static func withExcluded(_ config: QuartzConfig, _ pageType: String, _ plugin: PluginEntry, _ excluded: Bool) -> QuartzConfig {
    guard let name = quartzName(plugin) else { return config }
    var exclude: [JSONValue] = []
    for item in of(config, pageType)["exclude"]?.arrayValue ?? [] where !exclude.contains(item) { exclude.append(item) }
    if excluded {
      if !exclude.contains(.string(name)) { exclude.append(.string(name)) }
    } else {
      exclude.removeAll { $0 == .string(name) }
    }
    return with(config, pageType, [("exclude", .array(exclude))])
  }

  public static func withCleared(_ config: QuartzConfig, _ pageType: String, _ position: String, _ cleared: Bool) -> QuartzConfig {
    var positions = LayoutBoxes.spread(of(config, pageType)["positions"])
    positions[position] = cleared ? .array([]) : nil
    return with(config, pageType, [("positions", .object(positions))])
  }

  /// nil takes the template away, which is not "default": the page type's plugin may bring a frame.
  public static func withTemplate(_ config: QuartzConfig, _ pageType: String, _ template: String?) -> QuartzConfig {
    with(config, pageType, [("template", template.map(JSONValue.string))])
  }

  /// The whole key, also one that customizes nothing (how a stray `{}` from 1.0 leaves the file).
  public static func without(_ config: QuartzConfig, _ pageType: String) -> QuartzConfig {
    var byPageType = LayoutBoxes.spread(config.layout?["byPageType"])
    byPageType[pageType] = nil
    var next = config
    var layout = config.layout ?? JSONObject()
    layout["byPageType"] = .object(byPageType)
    next.layout = layout
    return next
  }

  public enum FrameOrigin: String, Sendable { case override, plugin, `default` }

  /// `resolvedFrame`: the frame a page type is built with by Quartz's rule, and where that came
  /// from. `pluginFrames` is keyed by the page plugin's name (`content-page`).
  public static func resolvedFrame(_ config: QuartzConfig, _ pageType: String, pluginFrames: [String: String])
    -> (name: String, from: FrameOrigin) {
    if case .string(let template)? = of(config, pageType)["template"], !template.isEmpty { return (template, .override) }
    if let plugin = pluginFrames["\(pageType)-page"], !plugin.isEmpty { return (plugin, .plugin) }
    return ("default", .default)
  }
}
