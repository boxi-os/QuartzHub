import Foundation

/// The rules of the Layout page's stage that `LayoutEntries` does not already share with the plugin
/// editors: the rest of QuartzControl's `routes/LayoutEditor/utils.ts`, measured against it with
/// `scripts/layout-board-golden.mjs`. Every change is a new plugin list, as there; the page keeps
/// it as a draft until Save.
public enum LayoutBoard {
  public static let breakpoints = GridFrameCss.breakpoints

  /// `breakpointRangeLabel`: the width a view covers, for its label. Desktop is the unconditional
  /// base of a frame's CSS and so owns everything above the tablet threshold.
  public static func rangeLabel(_ bp: String, widths: (tablet: Double, mobile: Double)) -> String {
    let n = { (value: Double) in JS.string(.number(value)) }
    switch bp {
    case "desktop": return "> \(n(widths.tablet)) px"
    case "tablet": return "\(n(widths.mobile + 1))–\(n(widths.tablet)) px"
    default: return "≤ \(n(widths.mobile)) px"
    }
  }

  // MARK: Quartz's own frames

  /// `BUILTIN_FRAME_LAYOUT`: Quartz's two single-column frames. Their render() never looks at
  /// `left`/`right`, so what sits there is dropped on a page built with them.
  public static let builtinFrameSlots: [String: [String]] = [
    "full-width": ["header", "beforeBody", "afterBody", "footer"],
    "minimal": ["footer"],
  ]

  /// `sidebarDirection`: `.sidebar.left` turns into a row on mobile only, `.sidebar.right` already
  /// on tablet (base.scss).
  public static func sidebarIsRow(_ position: String, _ bp: String) -> Bool {
    if bp == "desktop" { return false }
    return position == "right" || bp == "mobile"
  }

  // MARK: counting and naming

  /// `duplicateNameCounts`: how many components share each name.
  public static func nameCounts(_ plugins: [PluginEntry]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for (plugin, _) in LayoutEntries.components(plugins) { counts[plugin.name, default: 0] += 1 }
    return counts
  }

  /// The name the board shows: with its number where the name is shared.
  public static func label(_ plugins: [PluginEntry], _ index: Int) -> String {
    let name = plugins[index].name
    guard (nameCounts(plugins)[name] ?? 0) > 1 else { return name }
    return "\(name) #\(LayoutEntries.duplicateRanks(plugins)[index] ?? 1)"
  }

  /// `distinctComponentChips`: the tray, one chip per name, the first entry of it.
  public static func trayChips(_ plugins: [PluginEntry]) -> [Int] {
    var seen: Set<String> = []
    return LayoutEntries.components(plugins).compactMap { plugin, index in
      seen.insert(plugin.name).inserted ? index : nil
    }
  }

  /// `parkedIndices`: a switched-off component that is the only one of its name lives in the tray.
  /// A switched-off duplicate stays on the board, because the tray's chip of its name stands for
  /// the instance that is on.
  public static func parked(_ plugins: [PluginEntry]) -> Set<Int> {
    let counts = nameCounts(plugins)
    return Set(LayoutEntries.components(plugins).compactMap { plugin, index in
      !plugin.enabled && counts[plugin.name] == 1 ? index : nil
    })
  }

  /// `buildBoardPositionMap`: each position's list without the parked entries.
  public static func boardPositions(_ plugins: [PluginEntry], parked: Set<Int>) -> [String: [Int]] {
    LayoutEntries.positionMap(plugins).mapValues { $0.filter { !parked.contains($0) } }
  }

  /// `resolveComponentRef`: the entry a remembered selection names, or nil when it is gone.
  public static func resolve(_ plugins: [PluginEntry], name: String, occurrence: Int) -> Int? {
    let ranks = LayoutEntries.duplicateRanks(plugins)
    return LayoutEntries.components(plugins).first { $0.plugin.name == name && ranks[$0.index] == occurrence }?.index
  }

  // MARK: page types and groups

  /// `derivePageTypes`: the 404 page, every enabled `*-page` plugin without its suffix, and every
  /// key already under `layout.byPageType` (a plugin may call its type something else, as
  /// obsidian-plugin-excalidraw does). In the order a reader meets them; an unknown type goes
  /// before the 404 page.
  public static func pageTypes(_ config: QuartzConfig) -> [String] {
    let fromPlugins = config.plugins.filter { $0.enabled && $0.name.hasSuffix("-page") }.map { String($0.name.dropLast(5)) }
    let fromConfig = LayoutBoxes.spread(config.layout?["byPageType"]).keys
    var found: [String] = []
    for type in ["404"] + fromPlugins + fromConfig where !found.contains(type) { found.append(type) }
    let order = ["content", "folder", "tag", "bases", "canvas", "excalidraw"]
    let rank = { (type: String) -> Int in order.firstIndex(of: type) ?? (type == "404" ? 1001 : 1000) }
    return found.enumerated().sorted { a, b in
      let (ra, rb) = (rank(a.element), rank(b.element))
      return ra != rb ? ra < rb : a.offset < b.offset
    }.map(\.element)
  }

  /// `groupNamesOf`: every group of the layout in a stable order, the order the group colours are
  /// taken from. Declared groups, the groups the frames' areas name, and every group a component
  /// names: a group exists as soon as one does, and without the last source a group whose area is
  /// gone could not be cleared from its member.
  public static func groupNames(_ config: QuartzConfig, frames: [FrameView]) -> [String] {
    var names: [String] = []
    let add = { (name: String) in if !names.contains(name) { names.append(name) } }
    LayoutBoxes.spread(config.layout?["groups"]).keys.forEach(add)
    for frame in frames { frame.areas.compactMap(\.group).forEach(add) }
    for plugin in config.plugins {
      if case .string(let group)? = LayoutEntries.layout(plugin)?["group"], !group.isEmpty { add(group) }
    }
    return names
  }

  // MARK: changing one component

  /// The entry at `index` with its layout block changed, as `{ ...p, layout: { ...p.layout, … } }`;
  /// an entry without a (truthy) layout block is left alone.
  static func withLayout(_ plugins: [PluginEntry], _ index: Int, _ change: (inout JSONObject) -> Void) -> [PluginEntry] {
    plugins.enumerated().map { i, plugin in
      guard i == index, let raw = plugin.object["layout"], JS.truthy(raw) else { return plugin }
      var layout = LayoutBoxes.spread(raw)
      change(&layout)
      var object = plugin.object
      object["layout"] = .object(layout)
      return PluginEntry(object: object)
    }
  }

  /// `withGroup`: "" takes it out of any group.
  public static func withGroup(_ plugins: [PluginEntry], _ index: Int, _ group: String) -> [PluginEntry] {
    withLayout(plugins, index) { $0["group"] = group.isEmpty ? nil : .string(group) }
  }

  /// `withDisplay`: "all" (or nothing) writes no key; Quartz's base.scss does the rest.
  public static func withDisplay(_ plugins: [PluginEntry], _ index: Int, _ display: String?) -> [PluginEntry] {
    withLayout(plugins, index) { $0["display"] = display.flatMap { $0.isEmpty || $0 == "all" ? nil : .string($0) } }
  }

  /// Quartz's four built-in conditions (`quartz/plugins/loader/conditions.ts`); a plugin can add
  /// more, and an unknown name shows the component always.
  public static let builtinConditions = ["not-index", "has-tags", "has-backlinks", "has-toc"]

  /// `withCondition`: trimmed, and an empty one writes no key.
  public static func withCondition(_ plugins: [PluginEntry], _ index: Int, _ condition: String) -> [PluginEntry] {
    let trimmed = JS.trim(condition)
    return withLayout(plugins, index) { $0["condition"] = trimmed.isEmpty ? nil : .string(trimmed) }
  }

  public static func withEnabled(_ plugins: [PluginEntry], _ index: Int, _ enabled: Bool) -> [PluginEntry] {
    plugins.enumerated().map { i, plugin in
      guard i == index else { return plugin }
      var object = plugin.object
      object["enabled"] = .bool(enabled)
      return PluginEntry(object: object)
    }
  }

  /// What Quartz's Flex fills in for a missing key (`quartz/components/Flex.tsx`). A value equal
  /// to it is written as no key, so switching something on and off leaves the file as it was.
  public static let groupOptionDefaults: [String: JSONValue] = [
    "grow": .bool(false), "shrink": .bool(true), "basis": .string("auto"), "order": .number(0), "align": .string("center"),
  ]

  /// `withGroupOption`: nil or "" removes the key, and `groupOptions` goes when it is empty.
  public static func withGroupOption(_ plugins: [PluginEntry], _ index: Int, _ key: String, _ value: JSONValue?) -> [PluginEntry] {
    withLayout(plugins, index) { layout in
      var options = LayoutBoxes.spread(layout["groupOptions"])
      if value == nil || value == .string("") || value == groupOptionDefaults[key] {
        options[key] = nil
      } else {
        options[key] = value
      }
      layout["groupOptions"] = options.isEmpty ? nil : .object(options)
    }
  }

  /// `withOptions`: the plugin's own options as the form hands them back; nil removes the key.
  public static func withOptions(_ plugins: [PluginEntry], _ index: Int, _ options: JSONObject?) -> [PluginEntry] {
    plugins.enumerated().map { i, plugin in
      guard i == index else { return plugin }
      var object = plugin.object
      object["options"] = options.map(JSONValue.object)
      return PluginEntry(object: object)
    }
  }

  /// `appendDuplicateToPosition`: a chip from the tray dropped on a position, another instance at
  /// `insertIndex` of that position's list (the end when nil), the list renumbered in tens.
  public static func appendDuplicate(_ plugins: [PluginEntry], _ sourceIndex: Int, position: String, insertIndex: Int? = nil,
                                     styled: Set<String> = []) -> (plugins: [PluginEntry], newIndex: Int)? {
    guard plugins.indices.contains(sourceIndex) else { return nil }
    var order = LayoutEntries.positionMap(plugins)[position] ?? []
    let wanted = insertIndex ?? order.count
    order.insert(-1, at: wanted < 0 ? max(order.count + wanted, 0) : min(wanted, order.count))
    var priorities: [Int: Double] = [:]
    for (i, index) in order.enumerated() { priorities[index] = Double((i + 1) * 10) }
    let layout = JSONObject([("position", .string(position)), ("priority", .number(priorities[-1] ?? 10))])
    let copy = LayoutEntries.duplicate(plugins[sourceIndex], layout: layout, plugins: plugins, styled: styled)
    let next = (plugins + [copy]).enumerated().map { i, plugin -> PluginEntry in
      guard let priority = priorities[i], let raw = plugin.object["layout"], JS.truthy(raw),
            raw["position"] == .string(position) else { return plugin }
      var own = LayoutBoxes.spread(raw)
      own["position"] = .string(position)
      own["priority"] = .number(priority)
      var object = plugin.object
      object["layout"] = .object(own)
      return PluginEntry(object: object)
    }
    return (next, plugins.count)
  }

  /// Removing an entry (a duplicate dropped on the tray, "Duplikat entfernen"), and where the
  /// selection goes: the entry that was selected keeps it, renumbered; the removed one loses it.
  public static func removing(_ plugins: [PluginEntry], _ index: Int, selected: Int?) -> (plugins: [PluginEntry], selected: Int?) {
    let keep: Int? = selected.flatMap { s in s == index ? nil : (s > index ? s - 1 : s) }
    return (plugins.enumerated().filter { $0.offset != index }.map(\.element), keep)
  }
}
