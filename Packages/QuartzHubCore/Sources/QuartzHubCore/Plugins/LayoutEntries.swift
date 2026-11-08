import Foundation

/// The component entries of `plugins:` as the layout board orders them (QuartzControl's
/// `routes/LayoutEditor/utils.ts`, the part the plugin editors share with the board; measured
/// against it in NavigationsTests). The Layout page adds the rest.
///
/// Priorities are numbers in every config QuartzHub and QuartzControl write. One that is missing
/// or not a number made QuartzControl's sort comparator answer NaN, which a stable sort reads as
/// "equal", and the order then depends on the sort algorithm; here such an entry keeps its place
/// among its equals too, but that order is not measured.
public enum LayoutEntries {
  public static let positions = ["header", "left", "right", "beforeBody", "afterBody", "footer"]

  /// `getLayout`: the entry's `layout` block, if it has one.
  public static func layout(_ entry: PluginEntry) -> JSONObject? {
    entry.object["layout"]?.objectValue
  }

  /// Whether QuartzControl's `getLayout` found a block: any object, a list too (`typeof` says
  /// "object" for both). A list has no position and stands in no position's list.
  static func hasLayout(_ entry: PluginEntry) -> Bool {
    switch entry.object["layout"] {
    case .object?, .array?: true
    default: false
    }
  }

  /// `componentItems`: the entries with a layout block, with their index in `plugins:`.
  public static func components(_ plugins: [PluginEntry]) -> [(plugin: PluginEntry, index: Int)] {
    plugins.enumerated().compactMap { index, plugin in hasLayout(plugin) ? (plugin, index) : nil }
  }

  static func priority(_ entry: PluginEntry) -> Double {
    JS.toNumber(layout(entry)?["priority"])
  }

  /// `buildPositionMap`: each position's entries by priority, as Quartz's config loader sorts them.
  public static func positionMap(_ plugins: [PluginEntry]) -> [String: [Int]] {
    let items = components(plugins)
    var map: [String: [Int]] = [:]
    for position in positions {
      let here = items.filter { layout($0.plugin)?["position"] == .string(position) }
      map[position] = here.enumerated().sorted { a, b in
        let d = priority(a.element.plugin) - priority(b.element.plugin)
        return d.isNaN || d == 0 ? a.offset < b.offset : d < 0
      }.map(\.element.index)
    }
    return map
  }

  /// `duplicateRanks`: each component's 1-based rank among the components of its name.
  public static func duplicateRanks(_ plugins: [PluginEntry]) -> [Int: Int] {
    var seen: [String: Int] = [:]
    var ranks: [Int: Int] = [:]
    for (plugin, index) in components(plugins) {
      let rank = (seen[plugin.name] ?? 0) + 1
      seen[plugin.name] = rank
      ranks[index] = rank
    }
    return ranks
  }

  /// `componentRef`: what the Layout page remembers as selected, the name with its rank.
  public static func componentRef(_ plugins: [PluginEntry], _ index: Int) -> (name: String, occurrence: Int)? {
    guard plugins.indices.contains(index), hasLayout(plugins[index]) else { return nil }
    return (plugins[index].name, duplicateRanks(plugins)[index] ?? 1)
  }

  /// `duplicateEntry`: a copy with its own layout. A navigation's `id` stays behind (two with the
  /// same one share element ids and their stored state), and a navigation or a box gets a class of
  /// its own. What a copy does not inherit is listed here and nowhere else.
  public static func duplicate(_ source: PluginEntry, layout: JSONObject, plugins: [PluginEntry], styled: Set<String> = []) -> PluginEntry {
    var object = source.object
    object["layout"] = .object(layout)
    if var options = source.object["options"]?.objectValue, options["id"] != nil,
       PluginSource(source.source)?.quartzName == NavigationVariants.plugin {
      options["id"] = nil
      object["options"] = .object(options)
    }
    return InstanceClass.withOwnForCopy(PluginEntry(object: object), source: source, plugins: plugins, styled: styled)
  }

  /// `duplicateAfter`: the copy right after the entry in its position, that position renumbered
  /// in steps of ten. The copy is appended to `plugins:`; nil for an entry without a layout or in
  /// a position the board does not know.
  public static func duplicateAfter(_ plugins: [PluginEntry], _ sourceIndex: Int, styled: Set<String> = [])
    -> (plugins: [PluginEntry], newIndex: Int)? {
    guard plugins.indices.contains(sourceIndex), let layout = layout(plugins[sourceIndex]),
          case .string(let position)? = layout["position"], let list = positionMap(plugins)[position] else { return nil }
    var order = list
    order.insert(-1, at: (list.firstIndex(of: sourceIndex) ?? -1) + 1)
    var priorities: [Int: Double] = [:]
    for (i, index) in order.enumerated() { priorities[index] = Double((i + 1) * 10) }
    var copyLayout = layout
    copyLayout["priority"] = .number(priorities[-1] ?? JS.toNumber(layout["priority"]) + 1)
    let copy = duplicate(plugins[sourceIndex], layout: copyLayout, plugins: plugins, styled: styled)
    let next = (plugins + [copy]).enumerated().map { i, plugin -> PluginEntry in
      guard let priority = priorities[i], var own = self.layout(plugin), own["position"] == .string(position) else { return plugin }
      own["priority"] = .number(priority)
      var object = plugin.object
      object["layout"] = .object(own)
      return PluginEntry(object: object)
    }
    return (next, plugins.count)
  }
}
