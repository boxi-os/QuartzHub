import Foundation

/// What the Mehrsprachigkeit editor knows about quartz-multilanguage (QuartzControl's
/// `routes/Plugins/multilanguageOptions.ts`, measured against it in MultilanguageTests).
///
/// Read from the plugin's options.ts: a language is a string (its code) or an object with `code`;
/// codes are trimmed and lower-cased; no usable language means `en`; a `defaultLanguage` that is
/// empty or not among the languages means the first one; an empty `publishLanguages` means all of
/// them.
public enum MultilanguageOptions {
  public static let plugin = "quartz-multilanguage"
  /// The version whose options.ts the defaults are read from.
  public static let readAgainst = "0.3.0"
  /// Versions whose options.ts is the same as that one's (`git diff v0.2.0 v0.3.0 -- src/options.ts`).
  public static let sameCode = ["0.2.0"]
  /// The keys the language list itself edits.
  public static let languageKeys = ["languages", "defaultLanguage", "publishLanguages"]
  public static let unknownGroup = "unknown"

  /// One language as the plugin reads it: an object with its normalized `code`. `readFrom` is the
  /// item it was read from (QuartzControl keeps it in a WeakMap): writing the list back leaves an
  /// entry nobody changed as it was written, `DE` stays `DE`. A changed entry has none.
  public struct Language: Equatable, Sendable {
    public var fields: JSONObject
    public var readFrom: JSONValue?

    public var code: String { fields["code"]?.stringValue ?? "" }

    public init(code: String) {
      fields = JSONObject([("code", .string(code))])
    }

    init(fields: JSONObject, readFrom: JSONValue?) {
      self.fields = fields
      self.readFrom = readFrom
    }

    /// The entry with one key changed: a new entry, no longer the written one.
    public func with(_ key: String, _ value: JSONValue?) -> Language {
      var next = fields
      next[key] = value
      return Language(fields: next, readFrom: nil)
    }

    public subscript(key: String) -> String? { fields[key]?.stringValue }
  }

  public struct Entry: Sendable {
    public var plugin: PluginEntry
    public var index: Int
  }

  public static func entries(_ plugins: [PluginEntry]) -> [Entry] {
    plugins.enumerated().compactMap { index, plugin in
      PluginRepository.quartzName(plugin.source) == Self.plugin ? Entry(plugin: plugin, index: index) : nil
    }
  }

  /// JavaScript's `trim().toLowerCase()`. NSString's lowercasing, not Swift's: only it writes a
  /// final sigma as "ς", as JavaScript does (measured).
  public static func normalizeCode(_ code: String) -> String {
    (ReadmeText.trim(code) as NSString).lowercased
  }

  private enum Raw {
    case language(String, JSONValue)
    case duplicate(String, JSONValue)
    case other(JSONValue)
  }

  /// The written list item by item, as the plugin sorts it.
  private static func classify(_ raw: JSONValue?) -> [Raw] {
    guard case .array(let items)? = raw else { return [] }
    var seen = Set<String>()
    return items.map { item in
      let entry: JSONObject? = switch item {
      case .string(let text): JSONObject([("code", .string(text))])
      case .object(let object): object
      case .array(let list): LayoutBoxes.spread(.array(list))
      default: nil
      }
      let code = entry?["code"]?.stringValue.map(normalizeCode) ?? ""
      guard entry != nil, !code.isEmpty else { return .other(item) }
      if seen.contains(code) { return .duplicate(code, item) }
      seen.insert(code)
      return .language(code, item)
    }
  }

  static func get(_ options: JSONObject?, _ key: String) -> JSONValue? { options?[key] }

  /// The languages as the plugin reads them, each as an object; a plain string becomes `{ code }`.
  public static func languages(_ options: JSONObject?) -> [Language] {
    var out: [Language] = []
    for case .language(let code, let item) in classify(options?["languages"]) {
      var fields = item.objectValue ?? JSONObject()
      fields["code"] = .string(code)
      out.append(Language(fields: fields, readFrom: item))
    }
    return out.isEmpty ? [Language(code: "en")] : out
  }

  public static func defaultLanguage(_ options: JSONObject?, _ languages: [Language]) -> String {
    let set = options?["defaultLanguage"]?.stringValue.map(normalizeCode) ?? ""
    return languages.contains { $0.code == set } ? set : languages[0].code
  }

  /// The codes `publishLanguages` names that are languages of the site; empty means every language.
  public static func published(_ options: JSONObject?, _ languages: [Language]) -> [String] {
    guard case .array(let raw)? = options?["publishLanguages"] else { return [] }
    let codes = Set(languages.map(\.code))
    return raw.compactMap(\.stringValue).map(normalizeCode).filter(codes.contains)
  }

  public static func isPublished(_ code: String, _ published: [String]) -> Bool {
    published.isEmpty || published.contains(code)
  }

  /// Writes the languages back into the list they were read from, touching only what changed. The
  /// languages fill the places languages had, in their new order, new ones go at the end; an item
  /// that is no language stays where it is. A second entry with a code the list already has stays
  /// only while that code is still a language and comes first.
  static func write(_ written: JSONValue?, _ languages: [Language]) -> [JSONValue] {
    func asWritten(_ l: Language) -> JSONValue {
      if let readFrom = l.readFrom { return readFrom }
      return l.fields.count == 1 ? .string(l.code) : .object(l.fields)
    }
    var queue = languages[...]
    var out: [JSONValue] = []
    var placed = Set<String>()
    for raw in classify(written) {
      switch raw {
      case .other(let item): out.append(item)
      case .duplicate(let code, let item):
        if placed.contains(code), languages.contains(where: { $0.code == code }) { out.append(item) }
      case .language:
        guard let next = queue.popFirst() else { continue }
        placed.insert(next.code)
        out.append(asWritten(next))
      }
    }
    out.append(contentsOf: queue.map(asWritten))
    return out
  }

  public static func withLanguages(_ options: JSONObject, _ languages: [Language]) -> JSONObject {
    var next = options
    next["languages"] = .array(write(options["languages"], languages))
    return next
  }

  /// `publishLanguages` after turning one language on or off; all of them on is the empty list again.
  public static func withPublished(_ options: JSONObject, _ languages: [Language], code: String, on: Bool) -> JSONObject {
    let current = published(options, languages)
    let all = languages.map(\.code)
    var now = Set(current.isEmpty ? all : current)
    if on { now.insert(code) } else { now.remove(code) }
    let list = all.filter(now.contains)
    var next = options
    next["publishLanguages"] = .array(list.count == all.count ? [] : list.map(JSONValue.string))
    return next
  }

  /// The options after renaming a language: its entry and every option that names it by code
  /// (`defaultLanguage`, `publishLanguages`, `seo.xDefault`). Content stays as it is.
  public static func rename(_ options: JSONObject, _ languages: [Language], from: String, to: String) -> JSONObject {
    var next = withLanguages(options, languages.map { $0.code == from ? $0.with("code", .string(to)) : $0 })
    if let set = options["defaultLanguage"]?.stringValue, normalizeCode(set) == from { next["defaultLanguage"] = .string(to) }
    if case .array(let list)? = options["publishLanguages"] {
      next["publishLanguages"] = .array(list.map { item in
        if let code = item.stringValue, normalizeCode(code) == from { return .string(to) }
        return item
      })
    }
    if case .object(var seo)? = options["seo"], let x = seo["xDefault"]?.stringValue, normalizeCode(x) == from {
      seo["xDefault"] = .string(to)
      next["seo"] = .object(seo)
    }
    return next
  }

  /// The languages removing `code` would publish without anyone turning them on: when it is the
  /// only published one, `publishLanguages` is left empty, and empty means every language.
  public static func publishedByRemoving(_ options: JSONObject?, _ languages: [Language], code: String) -> [Language] {
    let published = published(options, languages)
    if published.isEmpty || published.contains(where: { $0 != code }) { return [] }
    return languages.filter { $0.code != code }
  }

  /// The options after removing a language and what named it: a default on it moves to the first one left.
  public static func remove(_ options: JSONObject, _ languages: [Language], code: String) -> JSONObject {
    let rest = languages.filter { $0.code != code }
    var next = withLanguages(options, rest)
    if let set = options["defaultLanguage"]?.stringValue, normalizeCode(set) == code {
      next["defaultLanguage"] = rest.first.map { .string($0.code) }
    }
    if case .array(let list)? = options["publishLanguages"] {
      next["publishLanguages"] = .array(list.filter { item in !(item.stringValue.map { normalizeCode($0) == code } ?? false) })
    }
    if case .object(var seo)? = options["seo"], let x = seo["xDefault"]?.stringValue, normalizeCode(x) == code {
      seo["xDefault"] = .string("default")
      next["seo"] = .object(seo)
    }
    return next
  }

  public enum CodeProblem: String, Sendable { case empty, taken, form }

  /// Why a code cannot be used, or nil. Loose on purpose: the plugin itself only asks for one.
  public static func codeProblem(_ code: String, _ languages: [Language], own: String? = nil) -> CodeProblem? {
    let c = normalizeCode(code)
    if c.isEmpty { return .empty }
    // `/[\s/\\]/`: JavaScript's white space (all of it in the BMP), a slash or a backslash.
    if c.utf16.contains(where: { ReadmeText.isSpace($0) || $0 == 0x2F || $0 == 0x5C }) { return .form }
    if c != own, languages.contains(where: { $0.code == c }) { return .taken }
    return nil
  }

  /// One row of the settings below the languages: a group of the plugin's own schema, in the order
  /// its fields give. `id` is the group's untranslated name; "" the fields without one, `unknown`
  /// the keys the config sets and no schema names.
  public struct SettingsGroup: Equatable, Sendable {
    public var id: String
    /// The group's name in the page's language; "" for the two rows the caller names itself.
    public var title: String
    public var keys: [String]
  }

  public static func settingsGroups(_ schema: NormalizedOptionSchema?, options: JSONObject, lang: OptionFormText.Language) -> [SettingsGroup] {
    guard let schema else {
      let set = options.keys.filter { !languageKeys.contains($0) }
      return set.isEmpty ? [] : [SettingsGroup(id: "", title: "", keys: set)]
    }
    let fields = schema.fields.filter { !languageKeys.contains($0.key) }
    // JavaScript's sort is stable; Swift's is not promised to be, so the place breaks ties.
    let ordered = fields.contains { $0.order != nil }
      ? fields.enumerated().sorted { a, b in
          let (x, y) = (a.element.order ?? 9_007_199_254_740_991, b.element.order ?? 9_007_199_254_740_991)
          return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
      : fields
    var order: [String] = []
    var groups: [String: SettingsGroup] = [:]
    for field in ordered {
      let id = field.group ?? ""
      if groups[id] == nil {
        order.append(id)
        groups[id] = SettingsGroup(id: id, title: id.isEmpty ? "" : (OptionFormText.texts(field, lang).group ?? id), keys: [])
      }
      groups[id]?.keys.append(field.key)
    }
    // The group without a name last, as the form puts it.
    var out = order.filter { !$0.isEmpty }.compactMap { groups[$0] } + (groups[""].map { [$0] } ?? [])
    let named = Set(languageKeys + fields.map(\.key))
    let unknown = options.keys.filter { !named.contains($0) }
    if !unknown.isEmpty { out.append(SettingsGroup(id: unknownGroup, title: "", keys: unknown)) }
    return out
  }

  /// The field of a group that is one object and nothing else (`switcher`, `seo`), so its panel
  /// can show what is inside without the wrapper. nil otherwise.
  public static func soleObject(_ schema: NormalizedOptionSchema?, _ group: SettingsGroup) -> OptionField? {
    guard group.keys.count == 1, group.id != unknownGroup,
          let field = schema?.fields.first(where: { $0.key == group.keys[0] }), case .object = field.node else { return nil }
    return field
  }
}
