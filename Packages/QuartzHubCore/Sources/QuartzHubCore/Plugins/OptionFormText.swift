import Foundation

/// What the options form says about an option and how it reads what was typed: QuartzControl's
/// `PluginOptionsForm/text.ts`, `parseOptionValue` (AddOptionRow.tsx) and the three helpers of
/// editors.tsx that are not drawing (`emptyOf`, `conditionText`, `groupsOf`), measured against them
/// with `scripts/option-form-golden.mjs` (OptionFormTextTests).
///
/// One deviation: a typed `Infinity` stays the text it was typed as. QuartzControl made it a number,
/// which its YAML writer put down as `.inf`; JSON, the way to the yaml-edit helper here, has no
/// infinity, and the option would have arrived as `null`.
public enum OptionFormText {
  /// The two languages a plugin's `x-quartz-l10n` is read in: the page's.
  public enum Language: String, Sendable {
    case de, en
  }

  public struct Texts: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var group: String?
  }

  /// `fieldText`: the schema's own words (English, by convention) unless `x-quartz-l10n` carries
  /// some for the language.
  public static func texts(_ field: OptionField, _ language: Language) -> Texts {
    let own = field.l10n?.first { $0.language == language.rawValue }?.text
    return Texts(title: own?.title ?? field.title, description: own?.description ?? field.description,
                 group: own?.group ?? field.group)
  }

  /// `enumLabel`: the translated label of one value where the schema has it, the value otherwise.
  public static func enumLabel(_ field: OptionField?, _ value: OptionEnumValue, _ language: Language) -> String {
    let key = JS.string(value.jsonValue)
    let labels = field?.l10n?.first { $0.language == language.rawValue }?.text.enumLabels
    // An object's keys: the last one written wins, as in JavaScript.
    return labels?.last { $0.value == key }?.label ?? key
  }

  /// `inlineValue`: a value as one line, for "Vorgabe: …" and an untouched list.
  public static func inline(_ value: JSONValue) -> String {
    switch value {
    case .string(let text): return text.isEmpty ? "\"\"" : text
    case .array(let items) where items.allSatisfy({ if case .string = $0 { true } else if case .number = $0 { true } else { false } }):
      return items.map { JS.string($0) }.joined(separator: ", ")
    default: return JSJSON.compact(value)
    }
  }

  public enum Match: String, Sendable {
    /// By its own words: shown whole.
    case own = "self"
    /// Through a field inside it: only the children that match.
    case child
    case none
  }

  /// `fieldMatch`. `query` is lower-cased by the caller; empty: no search. Compared as JavaScript's
  /// `includes` does, code unit by code unit, not by canonical equivalence.
  public static func match(_ field: OptionField, query: String, _ language: Language) -> Match {
    if query.isEmpty { return .own }
    let text = texts(field, language)
    let own = [field.key, text.title, text.description, text.group]
    if own.contains(where: { $0.map { includes($0.lowercased(), query) } ?? false }) { return .own }
    return nested(field.node).contains { match($0, query: query, language) != .none } ? .child : .none
  }

  static func includes(_ text: String, _ part: String) -> Bool {
    part.isEmpty || text.range(of: part, options: .literal) != nil
  }

  private static func nested(_ node: OptionNode) -> [OptionField] {
    switch node {
    case .object(let fields, _): fields
    case .record(let value, _): nested(value)
    case .array(let items): nested(items)
    case .union(let variants): variants.flatMap(nested)
    default: []
    }
  }

  /// `parseOptionValue`: a hand-typed value as the config's YAML would hold it. "true" and "false"
  /// become switches, what JavaScript's `Number()` reads becomes a number, `[`, `{` or `"` at the
  /// start is tried as JSON; anything else stays the text as typed, untrimmed.
  public static func typedValue(_ raw: String) -> JSONValue {
    let text = JS.trim(raw)
    if text == "true" { return .bool(true) }
    if text == "false" { return .bool(false) }
    if !text.isEmpty {
      let number = JS.toNumber(.string(text))
      if number.isFinite { return .number(number) }
      if !number.isNaN { return .string(raw) }  // the deviation in the header
    }
    if let first = text.first, "[{\"".contains(first), let parsed = try? JSJSON.parse(text) {
      return parsed
    }
    return .string(raw)
  }

  /// `emptyOf`: what a new item of a list or a new entry of a record starts as. nil for an enum
  /// without values, which JavaScript answered with `undefined`.
  public static func empty(of node: OptionNode) -> JSONValue? {
    switch node {
    case .boolean: .bool(false)
    case .number: .number(0)
    case .string, .json: .string("")
    case .enumeration(let values): values.first?.jsonValue
    case .object, .record: .object(JSONObject())
    case .array: .array([])
    case .union(let variants): variants.first.flatMap(empty(of:))
    }
  }

  /// The words `conditionText` is made of, so the golden can compare what a sentence is built from.
  public typealias Translate = @Sendable (_ key: String, _ args: [(String, String)]?) -> String

  /// The catalog, one literal key per case so `qh-check i18n` can read them.
  public static let catalog: Translate = { key, args in
    let args = Dictionary(args ?? [], uniquingKeysWith: { _, last in last })
    switch key {
    case "pluginOptions.onlyWhen": return L10n.t("pluginOptions.onlyWhen", args)
    case "pluginOptions.conditionOn": return L10n.t("pluginOptions.conditionOn", args)
    case "pluginOptions.conditionOff": return L10n.t("pluginOptions.conditionOff", args)
    case "pluginOptions.conditionPart": return L10n.t("pluginOptions.conditionPart", args)
    case "pluginOptions.conditionOr": return L10n.t("pluginOptions.conditionOr")
    case "pluginOptions.conditionAnd": return L10n.t("pluginOptions.conditionAnd")
    default: return key
    }
  }

  /// `conditionText`: "Wirkt nur, wenn „Sortierung“ auf Datum steht." A switch is "is on", not
  /// "= true"; a field without a title, or a path into a nested one, is named by its key.
  public static func conditionText(_ field: OptionField, siblings: [OptionField], _ language: Language,
                                   keyPrefix: String = "", translate: Translate = catalog) -> String {
    let when = field.when ?? JSONObject()
    let parts = when.keys.map { path -> String in
      let allowed = when[path] ?? .null
      let head = siblings.first { $0.key == path }
      let name = head.flatMap { texts($0, language).title } ?? keyPrefix + path
      let list: [JSONValue] = if case .array(let items) = allowed { items } else { [allowed] }
      if list.count == 1, case .bool(let on) = list[0] {
        return translate(on ? "pluginOptions.conditionOn" : "pluginOptions.conditionOff", [("name", name)])
      }
      let values = list.map { value in OptionEnumValue(value).map { enumLabel(head, $0, language) } ?? JS.string(value) }
      return translate("pluginOptions.conditionPart", [("name", name), ("values", values.joined(separator: translate("pluginOptions.conditionOr", nil)))])
    }
    return translate("pluginOptions.onlyWhen", [("conditions", parts.joined(separator: translate("pluginOptions.conditionAnd", nil)))])
  }

  /// `groupsOf`: the fields by their group in the page's language, in the order the groups first
  /// appear, the ungrouped ones first.
  public static func groups(_ fields: [OptionField], _ language: Language) -> [(group: String?, fields: [OptionField])] {
    var order: [String?] = []
    var members: [String?: [OptionField]] = [:]
    for field in fields {
      let group = texts(field, language).group
      if members[group] == nil { order.append(group) }
      members[group, default: []].append(field)
    }
    let ungrouped = order.filter { $0 == nil }, grouped = order.filter { $0 != nil }
    return (ungrouped + grouped).map { ($0, members[$0] ?? []) }
  }

  /// ObjectBlock's order: by `x-quartz-order` where the schema orders (the others after, as listed),
  /// otherwise as the schema lists them.
  public static func ordered(_ fields: [OptionField]) -> [OptionField] {
    guard fields.contains(where: { $0.order != nil }) else { return fields }
    let last = Double(9_007_199_254_740_991)
    return fields.enumerated()
      .sorted { ($0.element.order ?? last, $0.offset) < ($1.element.order ?? last, $1.offset) }
      .map(\.element)
  }
}

extension QuartzConfig {
  /// `siteLanguages`: quartz-multilanguage's `languages` (codes or `{ code }`) where it is in the
  /// config, otherwise the primary subtag of `configuration.locale`. For an option keyed by
  /// language, such as layout-box's `byLang`.
  public var siteLanguages: [String] {
    let entry = plugins.first { PluginRepository.quartzName($0.source) == "quartz-multilanguage" }
    var own: [String] = []
    if case .array(let list)? = entry?.object["options"]?.objectValue?["languages"] {
      for item in list {
        let code: String? = switch item {
        case .string(let text): text
        case .object(let object): object["code"]?.stringValue
        default: nil
        }
        guard let code else { continue }
        let trimmed = JS.trim(code)
        if !trimmed.isEmpty, !own.contains(trimmed.lowercased()) { own.append(trimmed.lowercased()) }
      }
    }
    if !own.isEmpty { return own }
    guard case .string(let locale)? = configuration["locale"], !locale.isEmpty else { return [] }
    return [String(locale.split(separator: "-", omittingEmptySubsequences: false)[0]).lowercased()]
  }
}

/// Where a plugin comes from on GitHub (QuartzControl's `routes/Plugins/pluginSource.ts`): the
/// Marketplace marks what is installed with it, the plugin list links to it.
public enum PluginRepository {
  /// `normalizedRepoId`: any source form down to a lower-case "owner/repo", or nil.
  public static func id(_ source: JSONValue?) -> String? {
    var raw: String
    switch source {
    case .string(let text)?: raw = text
    case .object(let object)?:
      guard case .string(let repo)? = object["repo"] else { return nil }
      raw = repo
    default: return nil
    }
    for prefix in ["git+", "github:"] where raw.hasPrefix(prefix) { raw.removeFirst(prefix.count) }
    if let match = raw.prefixMatch(of: Self.githubURL) { raw.removeSubrange(match.range) }
    if raw.hasPrefix("@") { raw.removeFirst() }
    raw = String(raw.split(separator: "#", omittingEmptySubsequences: false)[0])
    if raw.hasSuffix(".git") { raw.removeLast(4) }
    let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return raw.lowercased()
  }

  /// `repoUrl`: always github.com, the only host every accepted source form resolves to.
  public static func url(_ source: JSONValue?) -> String? {
    id(source).map { "https://github.com/\($0)" }  // not a file path
  }

  /// `quartzPluginName` of a raw source as the config holds it.
  static func quartzName(_ source: JSONValue?) -> String? {
    switch source {
    case .string(let text)?: return PluginSource.quartzName(text)
    case .object(let object)?:
      if case .string(let name)? = object["name"], !name.isEmpty { return name }
      return object["repo"]?.stringValue.map(PluginSource.quartzName)
    default: return nil
    }
  }

  nonisolated(unsafe) private static let githubURL = #/https?:\/\/github\.com\//#.matchingSemantics(.unicodeScalar)
}

/// What the editors with tiles above the form (navigations, layout-box, forms) add on the top
/// level; the form alone knows only the schema's `when` (QuartzControl's `RootExtras`, editors.tsx).
public struct OptionRoot {
  public struct Lead {
    public var has: (String) -> Bool
    public var title: String
    public var empty: String
    public var note: String?

    public init(has: @escaping (String) -> Bool, title: String, empty: String, note: String? = nil) {
      self.has = has
      self.title = title
      self.empty = empty
      self.note = note
    }
  }

  /// A reason beyond `when` why a field does nothing right now.
  public var inactiveReason: ((String) -> String?)?
  /// Shown only while set (or searched for): the options of the variants not chosen.
  public var hideUnlessSet: ((String) -> Bool)?
  /// These fields first, open, under the given title: the section the tiles above switch.
  public var lead: Lead?
  /// The same as inactiveReason for a field of a record entry: the entry's values and the ones above.
  public var entryReason: ((String, JSONObject, JSONObject) -> String?)?
  /// The groups as plain sections, without a fold.
  public var flat = false
  /// Put before every key on the top level, for a form that shows the inside of one option.
  public var keyPrefix: String?

  public init(inactiveReason: ((String) -> String?)? = nil, hideUnlessSet: ((String) -> Bool)? = nil, lead: Lead? = nil,
              entryReason: ((String, JSONObject, JSONObject) -> String?)? = nil, flat: Bool = false, keyPrefix: String? = nil) {
    self.inactiveReason = inactiveReason
    self.hideUnlessSet = hideUnlessSet
    self.lead = lead
    self.entryReason = entryReason
    self.flat = flat
    self.keyPrefix = keyPrefix
  }
}
