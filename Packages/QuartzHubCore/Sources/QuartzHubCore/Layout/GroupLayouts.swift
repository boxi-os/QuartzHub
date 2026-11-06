import Foundation

/// Which groups a position holds, in the order Quartz hands them to a frame: a port of
/// `groupLayoutCandidates` and `groupOrderByPosition` in `shared/gridFrameCss.ts`.
///
/// Quartz collapses a position's grouped entries into one `Flex` each (`resolveGroups`), so the
/// rank of a group is how the generated frame addresses it, and the rank follows from the config
/// alone: members sorted by their own priority, a group placed by its first member unless
/// `layout.groups.<name>.priority` says otherwise. And Quartz builds a layout per page type
/// (`exclude`, cleared `positions`), so there is one ordering per page type that can reach the
/// frame; the frame picks the one that fits what it was handed. A page type whose `template`
/// names another frame is left out: one candidate too many swapped what two areas showed.
///
/// `enabled` is read the way Quartz's loader reads it: anything falsy is out. `exclude` matches
/// `PluginSource.quartzName` (`extractPluginName`), not the displayed name.
public enum GroupLayouts {
  public struct Candidate: Equatable, Sendable {
    /// nil for the config as a whole.
    public var pageType: String?
    /// Position → group names, with JavaScript's key order (`JSONObject`).
    public var order: JSONObject

    public var json: JSONValue {
      .object(JSONObject([("pageType", pageType.map { .string($0) } ?? .null), ("order", .object(order))]))
    }
  }

  /// `frameName` as the frame definition holds it; a page type's `template` is compared with it
  /// strictly, as `!==` does.
  public static func candidates(plugins: [JSONObject], layout: JSONObject?, frameName: JSONValue?) throws -> [Candidate] {
    var candidates = [Candidate(pageType: nil, order: orderByPosition(plugins: plugins, layout: layout))]
    // Positions sorted before comparing: key order follows whichever plugin came first.
    func key(_ order: JSONObject) -> String {
      let sorted = order.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
      return JSJSON.compact(.array(sorted.map { .array([.string($0), order[$0]!]) }))
    }
    var seen: Set<String> = [key(candidates[0].order)]
    for (pageType, override) in entries(layout?["byPageType"] ?? .object(JSONObject())) {
      // Only an explicit template is certain; an unknown name falls back to the default frame,
      // never to another custom one, so a template naming something else never reaches this one.
      if let template = override[safe: "template"], template != .null, template != frameName { continue }
      let excluded = try members(override[safe: "exclude"])
      let kept = try excluded.isEmpty ? plugins : plugins.filter { plugin in
        let name = try quartzName(plugin["source"])
        return !excluded.contains(name)
      }
      var order = orderByPosition(plugins: kept, layout: layout)
      // A position cleared with `[]` renders nothing for this page type; dropped, not emptied, so
      // "no groups here" has one spelling.
      for (position, components) in entries(override[safe: "positions"] ?? .object(JSONObject())) {
        if case .array(let items) = components, items.isEmpty { order[position] = nil }
      }
      let orderKey = key(order)
      if seen.contains(orderKey) { continue }
      seen.insert(orderKey)
      candidates.append(Candidate(pageType: pageType, order: order))
    }
    return candidates
  }

  public static func orderByPosition(plugins: [JSONObject], layout: JSONObject?) -> JSONObject {
    let groupConfigs = layout?["groups"]
    var members = plugins.compactMap { plugin -> JSONValue? in
      guard JS.truthy(plugin["enabled"] ?? .null), let entry = plugin["layout"], JS.truthy(entry[safe: "group"] ?? .null) else { return nil }
      return entry
    }
    JS.sort(&members) { number($0[safe: "priority"]) - number($1[safe: "priority"]) }
    var result = JSONObject()
    for member in members {
      let position = JS.string(member[safe: "position"])
      var list = result[position]?.arrayValue ?? []
      let group = member[safe: "group"]!
      if !list.contains(group) { list.append(group) }
      result[position] = .array(list)
    }
    for position in result.keys {
      var ranked = (result[position]?.arrayValue ?? []).enumerated().map { index, name -> (name: JSONValue, index: Int, priority: Double) in
        let configured = groupConfigs?[safe: JS.string(name)]?[safe: "priority"]
        let priority: JSONValue? = (configured == nil || configured == .null)
          ? firstMemberPriority(members, position, name) : configured
        return (name, index, number(priority))
      }
      JS.sort(&ranked) { a, b in
        let byPriority = a.priority - b.priority
        return byPriority != 0 && !byPriority.isNaN ? byPriority : Double(a.index - b.index)
      }
      result[position] = .array(ranked.map(\.name))
    }
    return result
  }

  static func firstMemberPriority(_ members: [JSONValue], _ position: String, _ group: JSONValue) -> JSONValue {
    let found = members.first { $0[safe: "position"] == .string(position) && $0[safe: "group"] == group }
    guard let priority = found?[safe: "priority"], priority != .null else { return .number(50) }
    return priority
  }

  /// `a.priority - b.priority`: ToNumber on both sides, undefined is NaN.
  static func number(_ value: JSONValue?) -> Double {
    value.map { JS.toNumber($0) } ?? .nan
  }

  /// `Object.entries` of a JSON value: an object's pairs, an array's indices, a string's characters.
  static func entries(_ value: JSONValue) -> [(String, JSONValue)] {
    switch value {
    case .object(let object): return object.keys.map { ($0, object[$0]!) }
    case .array(let items): return items.enumerated().map { (String($0), $1) }
    case .string(let text): return Array(text.utf16).enumerated().map { (String($0), .string(String(decoding: [$1], as: UTF16.self))) }
    default: return []
    }
  }

  /// `new Set(value ?? [])`.
  static func members(_ value: JSONValue?) throws -> [JSONValue] {
    switch value {
    case nil, .null?: return []
    case .array(let items)?: return items
    case .string(let text)?: return text.unicodeScalars.map { .string(String($0)) }
    case .object?: throw JS.TypeError("object is not iterable (cannot read property Symbol(Symbol.iterator))")
    case .number(let number)?: throw JS.TypeError("number \(JSJSON.numberToString(number)) is not iterable (cannot read property Symbol(Symbol.iterator))")
    case .bool(let bool)?: throw JS.TypeError("boolean \(bool) is not iterable (cannot read property Symbol(Symbol.iterator))")
    }
  }

  /// `quartzPluginName(source)` with JavaScript's failures for a source that is neither.
  static func quartzName(_ source: JSONValue?) throws -> JSONValue {
    switch source {
    case .object(let object)?:
      if let name = object["name"], JS.truthy(name) { return name }
      return try quartzName(object["repo"])
    case .string(let text)?: return .string(PluginSource.quartzName(text))
    case nil: throw JS.readError(nil, "startsWith")
    case .null?: throw JS.readError(.null, "startsWith")
    default: throw JS.TypeError("source.startsWith is not a function")
    }
  }
}

extension JSONValue {
  /// `value?.[key]` for an object; nothing for every other value (JavaScript's property read on a
  /// primitive finds nothing these files could hold).
  subscript(safe key: String) -> JSONValue? {
    if case .object(let object) = self { return object[key] }
    return nil
  }
}
