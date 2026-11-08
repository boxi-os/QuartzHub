import Foundation

// What QuartzHub knows about a plugin's options, in one shape whatever the plugin brought along: a
// port of QuartzControl's shared/pluginOptionSchema.ts, measured against it with
// `scripts/option-schema-golden.mjs` (OptionSchemaTests).
//
// Four sources describe options (counted 2026-10-07 on gui-test: 33 plugins with
// `quartz.optionSchema`, 45 with `quartz.defaultOptions`; configSchema since 1.1 in the own ones):
//
//   quartz.configSchema   JSON Schema, plus the `x-quartz-*` keywords below
//   quartz.optionSchema   the flat form of the @quartz-community plugins: a map of option → schema,
//                         with `type: "enum"` + `values` instead of `enum`
//   .d.ts                 the type declarations, translated to JSON Schema by the dts-schema helper
//   quartz.defaultOptions the values quartz merges under the user's; fills what the others miss
//
// One normalizer, for JSON Schema; the other forms are brought to it. What cannot be read is never
// dropped silently: it becomes a `json` node (edited as text) and a note with path and reason.
//
// The `x-quartz-*` keywords a configSchema property may carry. The list is a format and stands
// twice in QuartzControl (the reader's head and docs/plugin-config-schema.md); whoever changes it
// here changes it there too.
//
//   x-quartz-when        { "<sibling key>": value | [values] }: the field applies only while every
//                        named sibling (a dotted path walks into objects) has one of the values; an
//                        unset sibling counts with its default
//   x-quartz-group       section heading
//   x-quartz-order       sort key within the object (lower first)
//   x-quartz-advanced    true: shown folded away
//   x-quartz-widget      "snippetFile" | "html" | "markdown" | "glob"
//   x-quartz-dir-option  for snippetFile: the option naming the snippet directory, looked up in the
//                        field's own object first, then in each enclosing one
//   x-quartz-keys        for a record: "languages", its keys are the site's language codes
//   x-quartz-l10n        { "<lang>": { title?, description?, group?, enum?: { "<value>": label } } }
//   x-quartz-note        on a schema the app cannot draw: why, shown with the JSON field
//
// Deviations from QuartzControl, both where it threw (OptionSchemaTests, "where QuartzControl
// threw"): a `$ref` with a broken %-escape is unresolvable instead of a URIError, and a `$ref`
// that names itself as its own target ends in a note instead of a RangeError from following its
// annotations forever. Keys are own keys: QuartzControl's `key in values` also found
// `constructor` on every object.

public enum OptionEnumValue: Equatable, Hashable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)

  init?(_ value: JSONValue) {
    switch value {
    case .string(let s): self = .string(s)
    case .number(let n): self = .number(n)
    case .bool(let b): self = .bool(b)
    default: return nil
    }
  }

  public var jsonValue: JSONValue {
    switch self {
    case .string(let s): .string(s)
    case .number(let n): .number(n)
    case .bool(let b): .bool(b)
    }
  }
}

public indirect enum OptionNode: Equatable, Sendable {
  case boolean
  case string
  case number(integer: Bool, minimum: Double?, maximum: Double?)
  case enumeration([OptionEnumValue])
  case union([OptionNode])
  case object(fields: [OptionField], rest: OptionNode?)
  /// `languageKeys`: `x-quartz-keys: "languages"`.
  case record(value: OptionNode, languageKeys: Bool)
  case array(items: OptionNode)
  case json

  public var kind: String {
    switch self {
    case .boolean: "boolean"
    case .string: "string"
    case .number: "number"
    case .enumeration: "enum"
    case .union: "union"
    case .object: "object"
    case .record: "record"
    case .array: "array"
    case .json: "json"
    }
  }
}

public enum OptionWidget: Equatable, Sendable {
  case snippetFile(dirOption: String?)
  case html
  case markdown
  case glob
}

public struct OptionFieldText: Equatable, Sendable {
  public var title: String?
  public var description: String?
  public var group: String?
  /// Value → label, in the order the plugin wrote them; only string labels.
  public var enumLabels: [EnumLabel]?

  public struct EnumLabel: Equatable, Sendable {
    public var value: String
    public var label: String
  }
}

public struct OptionField: Equatable, Sendable {
  public enum Origin: String, Sendable {
    /// The plugin's schema.
    case schema
    /// Only its `defaultOptions`.
    case defaults
    /// Only the user's config: a key nobody describes, shown so it is not lost.
    case config
  }

  public var key: String
  public var node: OptionNode
  public var title: String?
  public var description: String?
  /// nil: no default. `.null` is a default (YAML's empty value).
  public var defaultValue: JSONValue?
  /// Every key must match; a list means "one of". Paths are relative to the containing object.
  /// Validated: each value is a string, number or boolean, or a list of them.
  public var when: JSONObject?
  public var group: String?
  public var order: Double?
  public var advanced = false
  public var widget: OptionWidget?
  /// Language → texts, in the plugin's order.
  public var l10n: [(language: String, text: OptionFieldText)]?
  public var origin: Origin

  public var hasDefault: Bool { defaultValue != nil }

  init(key: String, node: OptionNode, origin: Origin, defaultValue: JSONValue? = nil) {
    self.key = key
    self.node = node
    self.origin = origin
    self.defaultValue = defaultValue
  }

  public static func == (lhs: OptionField, rhs: OptionField) -> Bool {
    lhs.key == rhs.key && lhs.node == rhs.node && lhs.title == rhs.title && lhs.description == rhs.description
      && lhs.defaultValue == rhs.defaultValue && lhs.when == rhs.when && lhs.group == rhs.group && lhs.order == rhs.order
      && lhs.advanced == rhs.advanced && lhs.widget == rhs.widget && lhs.origin == rhs.origin
      && lhs.l10n?.map(\.language) == rhs.l10n?.map(\.language) && lhs.l10n?.map(\.text) == rhs.l10n?.map(\.text)
  }
}

public struct OptionSchemaNote: Equatable, Sendable {
  public var path: [String]
  public var reason: String
}

public struct NormalizedOptionSchema: Equatable, Sendable {
  public enum Source: String, Sendable {
    case configSchema, optionSchema, dts, defaults
  }

  public var source: Source
  public var fields: [OptionField]
  public var notes: [OptionSchemaNote]

  /// Nothing described: what the options form starts from for an entry without a schema.
  public static let empty = NormalizedOptionSchema(source: .defaults, fields: [], notes: [])
}

// MARK: - JSON Schema → OptionNode

public enum OptionSchema {
  /// Nesting deeper than this is not an options object anyone fills in by hand; it also bounds a
  /// schema that refers to itself through `$ref`.
  static let maxDepth = 16

  /// A JSON Schema for the whole options object. `source` says which manifest key (or the .d.ts
  /// translation) it came from; the flat optionSchema goes through `normalize(optionSchema:)`.
  public static func normalize(jsonSchema schema: JSONValue, source: NormalizedOptionSchema.Source) -> NormalizedOptionSchema {
    guard case .object(let root) = schema else {
      return NormalizedOptionSchema(source: source, fields: [], notes: [OptionSchemaNote(path: [], reason: "schema is not an object")])
    }
    let context = Context(root: root)
    let node = context.node(schema, [], 0)
    if case .object(let fields, _) = node {
      return NormalizedOptionSchema(source: source, fields: fields, notes: context.notes)
    }
    if case .json = node {
      if context.notes.isEmpty { context.notes.append(OptionSchemaNote(path: [], reason: "schema describes no properties")) }
    } else {
      context.notes.append(OptionSchemaNote(path: [], reason: "options are a \(node.kind), not an object"))
    }
    return NormalizedOptionSchema(source: source, fields: [], notes: context.notes)
  }

  /// `quartz.optionSchema`: a map of option name → schema, no wrapping object.
  public static func normalize(optionSchema flat: JSONValue) -> NormalizedOptionSchema {
    guard case .object = flat else {
      return NormalizedOptionSchema(source: .optionSchema, fields: [], notes: [OptionSchemaNote(path: [], reason: "optionSchema is not an object")])
    }
    return normalize(jsonSchema: .object(JSONObject([("type", .string("object")), ("properties", flat)])), source: .optionSchema)
  }

  private final class Context {
    let root: JSONObject
    var notes: [OptionSchemaNote] = []
    var refs: [String] = []

    init(root: JSONObject) { self.root = root }

    func json(_ path: [String], _ reason: String) -> OptionNode {
      notes.append(OptionSchemaNote(path: path, reason: reason))
      return .json
    }

    func resolve(_ ref: String) -> JSONObject? {
      guard let match = ref.wholeMatch(of: OptionSchema.refPattern),
            case .object(let defs)? = root[String(match.output.1)],
            let name = String(match.output.2).removingPercentEncoding,
            case .object(let target)? = defs[name] else { return nil }
      return target
    }

    func node(_ raw: JSONValue, _ path: [String], _ depth: Int) -> OptionNode {
      if depth > OptionSchema.maxDepth { return json(path, "nested too deeply") }
      if raw == .bool(true) { return .json }
      guard case .object(let s) = raw else { return json(path, "not a schema object") }
      if s.keys.allSatisfy({ ["description", "title", "default"].contains($0) || $0.hasPrefix("x-quartz-") }) {
        // `{}` and `true` accept anything. Not a gap in the reader but the schema's own answer.
        if case .string(let note)? = s["x-quartz-note"] { return json(path, note) }
        return .json
      }

      if case .string(let ref)? = s["$ref"] {
        if refs.contains(ref) { return json(path, "refers to itself (\(ref))") }
        guard let target = resolve(ref) else { return json(path, "unresolvable $ref \(ref)") }
        refs.append(ref)
        defer { refs.removeLast() }
        return node(.object(target), path, depth + 1)
      }

      if let constant = s["const"], let value = OptionEnumValue(constant) { return .enumeration([value]) }
      let enumValues: [JSONValue]? = if case .array(let values)? = s["enum"] {
        values
      } else if s["type"] == .string("enum"), case .array(let values)? = s["values"] {
        values
      } else {
        nil
      }
      if let enumValues {
        let scalars = enumValues.compactMap(OptionEnumValue.init)
        if scalars.count == enumValues.count { return .enumeration(scalars) }
        return json(path, "enum with non-scalar values")
      }

      let alternatives: [JSONValue]? = if case .array(let one)? = s["oneOf"] { one } else if case .array(let any)? = s["anyOf"] { any } else { nil }
      if let alternatives {
        return OptionSchema.union(alternatives.enumerated().map { node($0.element, path + ["|\($0.offset)"], depth + 1) })
      }

      // `type: ["string", "null"]`: null is what YAML writes for an empty value, and the form never
      // writes one (an emptied field removes the key), so the null member says nothing to edit.
      let declared: [JSONValue?] = if case .array(let list)? = s["type"] { list } else { [s["type"]] }
      let types = declared.filter { $0 != .string("null") }
      if types.count > 1 {
        return OptionSchema.union(types.map { type in
          var copy = s
          copy["type"] = type ?? .null
          return node(.object(copy), path, depth)
        })
      }
      // `[s.type]` with s.type absent is `[undefined]`; an empty list after the filter is too.
      let type: JSONValue? = types.first ?? nil

      switch type {
      case .string("boolean")?:
        return .boolean
      case .string("string")?:
        return .string
      case .string("number")?, .string("integer")?:
        return .number(integer: type == .string("integer"), minimum: s["minimum"]?.numberValue, maximum: s["maximum"]?.numberValue)
      case .string("array")?:
        if case .array? = s["items"] { return json(path, "tuple arrays are not supported") }
        guard let items = s["items"] else { return .array(items: .json) }
        return .array(items: node(items, path + ["[]"], depth + 1))
      case .string("object")?, nil:
        if type == nil, s["properties"]?.objectValue == nil, s["additionalProperties"] == nil {
          let unsupported = ["allOf", "not", "if", "patternProperties"].first { s[$0] != nil }
          return json(path, unsupported.map { "\($0) is not supported" } ?? "no type")
        }
        return object(s, path, depth)
      case let other?:
        return json(path, "unknown type \(OptionSchema.jsString(other))")
      }
    }

    func object(_ s: JSONObject, _ path: [String], _ depth: Int) -> OptionNode {
      let properties = s["properties"]?.objectValue ?? JSONObject()
      let fields = properties.keys.map { key in field(key, properties[key]!, path + [key], depth + 1) }
      var rest: OptionNode?
      switch s["additionalProperties"] {
      case nil, .bool(false)?: rest = nil
      case .bool(true)?: rest = node(.object(JSONObject()), path + ["*"], depth + 1)
      case let additional?: rest = node(additional, path + ["*"], depth + 1)
      }
      if fields.isEmpty, let rest {
        let keys = s["x-quartz-keys"]
        if let keys, keys != .string("languages") {
          notes.append(OptionSchemaNote(path: path, reason: "unknown x-quartz-keys \(JSJSON.stringify(keys))"))
        }
        return .record(value: rest, languageKeys: keys == .string("languages"))
      }
      // An object nobody describes ({ type: "object" } and nothing else: `graph.localGraph` in the
      // community optionSchema) is edited as text: an empty form would offer nothing to fill in.
      if fields.isEmpty { return .json }
      return .object(fields: fields, rest: rest)
    }

    /// A property written as `{ "$ref": "#/$defs/title" }` carries its description, translation
    /// and widget in the target. Keywords beside the `$ref` win. A chain of refs is followed until
    /// it repeats (QuartzControl followed a ref to itself until the stack ran out).
    func annotations(_ raw: JSONValue, _ seen: [String] = []) -> JSONObject {
      guard case .object(let object) = raw else { return JSONObject() }
      guard case .string(let ref)? = object["$ref"], !seen.contains(ref), let target = resolve(ref) else { return object }
      var merged = annotations(.object(target), seen + [ref])
      for key in object.keys { merged[key] = object[key] }
      return merged
    }

    static let knownKeywords: Set<String> = Set(["when", "group", "order", "advanced", "widget", "dir-option", "keys", "l10n", "note"].map { "x-quartz-\($0)" })
    static let knownWidgets: Set<String> = ["snippetFile", "html", "markdown", "glob"]

    func field(_ key: String, _ raw: JSONValue, _ path: [String], _ depth: Int) -> OptionField {
      let s = annotations(raw)
      for keyword in s.keys where keyword.hasPrefix("x-quartz-") && !Self.knownKeywords.contains(keyword) {
        notes.append(OptionSchemaNote(path: path, reason: "unknown keyword \(keyword)"))
      }
      let widget = s["x-quartz-widget"]
      if let widget, !(widget.stringValue.map(Self.knownWidgets.contains) ?? false) {
        notes.append(OptionSchemaNote(path: path, reason: "unknown x-quartz-widget \(JSJSON.stringify(widget)), edited as plain text"))
      }
      var field = OptionField(key: key, node: node(raw, path, depth), origin: .schema)
      field.title = s["title"]?.stringValue
      field.description = s["description"]?.stringValue
      field.defaultValue = s["default"]
      if let when = s["x-quartz-when"] {
        if case .object(let map) = when, map.keys.allSatisfy({ OptionSchema.isCondition(map[$0]!) }) {
          field.when = map
        } else {
          notes.append(OptionSchemaNote(path: path, reason: "x-quartz-when is not a map of values"))
        }
      }
      field.group = s["x-quartz-group"]?.stringValue
      field.order = s["x-quartz-order"]?.numberValue
      field.advanced = s["x-quartz-advanced"] == .bool(true)
      switch widget {
      case .string("snippetFile")?: field.widget = .snippetFile(dirOption: s["x-quartz-dir-option"]?.stringValue)
      case .string("html")?: field.widget = .html
      case .string("markdown")?: field.widget = .markdown
      case .string("glob")?: field.widget = .glob
      default: break
      }
      if case .object(let l10n)? = s["x-quartz-l10n"] {
        field.l10n = l10n.keys.compactMap { language in
          guard case .object(let text) = l10n[language]! else { return nil }
          var t = OptionFieldText(title: text["title"]?.stringValue, description: text["description"]?.stringValue,
                                  group: text["group"]?.stringValue)
          if case .object(let labels)? = text["enum"] {
            t.enumLabels = labels.keys.compactMap { value in labels[value]!.stringValue.map { OptionFieldText.EnumLabel(value: value, label: $0) } }
          }
          return (language, t)
        }
      }
      return field
    }
  }

  // Swift Regex in Unicode scalars, as JavaScript sees a string.
  nonisolated(unsafe) static let refPattern = #/#\/(\$defs|definitions)\/([^\/]+)/#.matchingSemantics(.unicodeScalar)

  static func isCondition(_ value: JSONValue) -> Bool {
    if OptionEnumValue(value) != nil { return true }
    if case .array(let list) = value { return list.allSatisfy { OptionEnumValue($0) != nil } }
    return false
  }

  /// `unionOf`: unions flattened, enums merged (first occurrence wins), duplicates dropped.
  static func union(_ variants: [OptionNode]) -> OptionNode {
    let flat = variants.flatMap { node -> [OptionNode] in if case .union(let inner) = node { inner } else { [node] } }
    if !flat.isEmpty, flat.allSatisfy({ if case .enumeration = $0 { true } else { false } }) {
      var values: [OptionEnumValue] = []
      for case .enumeration(let list) in flat {
        for value in list where !values.contains(value) { values.append(value) }
      }
      return .enumeration(values)
    }
    var unique: [OptionNode] = []
    for node in flat where !unique.contains(node) { unique.append(node) }
    return unique.count == 1 ? unique[0] : .union(unique)
  }

  /// JavaScript's `String(value)` for a JSON value.
  static func jsString(_ value: JSONValue) -> String { JS.string(value) }
}

// MARK: - values → OptionNode

extension OptionSchema {
  /// The node a bare value suggests: for keys only `defaultOptions` or the config know about.
  public static func inferNode(_ value: JSONValue) -> OptionNode {
    switch value {
    case .bool: return .boolean
    case .number: return .number(integer: false, minimum: nil, maximum: nil)
    case .string: return .string
    case .array(let list):
      if !list.isEmpty, list.allSatisfy({ $0.stringValue != nil }) { return .array(items: .string) }
      if !list.isEmpty, list.allSatisfy({ $0.numberValue != nil }) { return .array(items: .number(integer: false, minimum: nil, maximum: nil)) }
      return .array(items: .json)
    case .object(let object):
      if object.isEmpty { return .json }
      // Nested keys count as defaults, whichever origin the outer one has (as in QuartzControl).
      return .object(fields: object.keys.map { inferredField($0, object[$0]!, .defaults) }, rest: nil)
    case .null:
      return .json
    }
  }

  static func inferredField(_ key: String, _ value: JSONValue, _ origin: OptionField.Origin) -> OptionField {
    OptionField(key: key, node: inferNode(value), origin: origin, defaultValue: origin == .defaults ? value : nil)
  }

  /// Whether `value` is something `node` can show and edit as it stands.
  public static func accepts(_ node: OptionNode, _ value: JSONValue) -> Bool {
    switch node {
    case .boolean: value.boolValue != nil
    case .string: value.stringValue != nil
    case .number: value.numberValue != nil
    case .enumeration(let values): OptionEnumValue(value).map(values.contains) ?? false
    case .union(let variants): variants.contains { accepts($0, value) }
    case .object, .record: value.objectValue != nil
    case .array: value.arrayValue != nil
    case .json: true
    }
  }

  // A schema and a value that disagree are both kept: the schema says what the plugin documents,
  // the value is what the plugin actually gets.
  static func widen(_ node: OptionNode, _ value: JSONValue) -> OptionNode {
    accepts(node, value) ? node : union([node, inferNode(value)])
  }

  static func merge(_ fields: [OptionField], _ values: JSONObject, _ origin: OptionField.Origin) -> [OptionField] {
    var out = fields.map { field -> OptionField in
      guard let value = values[field.key] else { return field }
      var next = field
      next.node = widen(field.node, value)
      if origin == .defaults, !field.hasDefault { next.defaultValue = value }
      if case .object(let nested, let rest) = next.node, case .object(let object) = value {
        next.node = .object(fields: merge(nested, object, origin), rest: rest)
      }
      return next
    }
    for key in values.keys where !fields.contains(where: { $0.key == key }) {
      out.append(inferredField(key, values[key]!, origin))
    }
    return out
  }

  /// Fill in what `quartz.defaultOptions` says: the default of every field it names (a schema's own
  /// `default` wins), and a field for every key no schema describes. Nested objects alike.
  public static func applyDefaults(_ schema: NormalizedOptionSchema, _ defaults: JSONValue?) -> NormalizedOptionSchema {
    guard case .object(let values)? = defaults else { return schema }
    var out = schema
    out.fields = merge(schema.fields, values, .defaults)
    return out
  }

  /// A schema from `defaultOptions` alone, for a plugin that brings nothing else.
  public static func fromDefaults(_ defaults: JSONValue?) -> NormalizedOptionSchema? {
    guard case .object(let values)? = defaults, !values.isEmpty else { return nil }
    return applyDefaults(NormalizedOptionSchema(source: .defaults, fields: [], notes: []), defaults)
  }

  /// A field for every key in one plugin entry's options that the schema does not describe, and a
  /// wider node where the schema does not accept the value. Per entry, not per plugin: two
  /// instances of the same plugin set different keys.
  public static func withPresentKeys(_ schema: NormalizedOptionSchema, _ values: JSONValue?) -> NormalizedOptionSchema {
    guard case .object(let object)? = values else { return schema }
    var out = schema
    out.fields = merge(schema.fields, object, .config)
    return out
  }
}

// MARK: - reading and writing values

extension OptionSchema {
  /// The value at `path`, or nil.
  public static func value(at path: [String], in value: JSONValue?) -> JSONValue? {
    var current = value
    for key in path {
      guard case .object(let object)? = current else { return nil }
      current = object[key]
    }
    return current
  }

  /// A copy of `object` with `value` at `path`. nil removes the key, and an object this removal
  /// leaves empty goes with it, up the path; otherwise clearing `byLang.en.title` leaves
  /// `byLang: { en: {} }`, which says "configured" about something that is not. Objects that were
  /// empty before are left alone, and so is a value in the way that is not an object only when
  /// something is set (QuartzControl's `setAtPath`).
  public static func setting(_ value: JSONValue?, at path: [String], in object: JSONObject) -> JSONObject {
    guard let head = path.first else { return object }
    var out = object
    if path.count == 1 {
      out[head] = value
      return out
    }
    let child = object[head]?.objectValue ?? JSONObject()
    let next = setting(value, at: Array(path.dropFirst()), in: child)
    out[head] = value == nil && next.isEmpty ? nil : .object(next)
    return out
  }

  /// Every key whose value is an empty plain object removed, recursively.
  public static func pruningEmptyObjects(_ object: JSONObject) -> JSONObject {
    var out = JSONObject()
    for key in object.keys {
      if case .object(let inner) = object[key]! {
        let pruned = pruningEmptyObjects(inner)
        if !pruned.isEmpty { out[key] = .object(pruned) }
      } else {
        out[key] = object[key]
      }
    }
    return out
  }

  /// Whether a field's `when` holds, given the values of its containing object. An unset sibling
  /// counts with its default, because that is what the plugin will see.
  public static func evaluate(_ when: JSONObject?, values: JSONValue?, fields: [OptionField]) -> Bool {
    guard let when else { return true }
    return when.keys.allSatisfy { path in
      let keys = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      let value = Self.value(at: keys, in: values) ?? defaultValue(at: keys, in: fields)
      let allowed: [JSONValue] = if case .array(let list) = when[path]! { list } else { [when[path]!] }
      // `===`: an object or a list is only ever equal to itself, never to another parsed one.
      return allowed.contains { a in value.map { $0.objectValue == nil && $0.arrayValue == nil && $0 == a } ?? false }
    }
  }

  static func defaultValue(at keys: [String], in fields: [OptionField]) -> JSONValue? {
    guard let head = keys.first, let field = fields.first(where: { $0.key == head }) else { return nil }
    let rest = Array(keys.dropFirst())
    if rest.isEmpty { return field.defaultValue }
    if case .object(let nested, _) = field.node, let found = defaultValue(at: rest, in: nested) { return found }
    return field.defaultValue.flatMap { value(at: rest, in: $0) }
  }
}

// MARK: - the canonical JSON form, for the golden tests

extension OptionNode {
  /// scripts/lib/option-schema-canon.mjs, `canonNode`.
  var canonicalJSON: JSONValue {
    var o = JSONObject([("kind", .string(kind))])
    switch self {
    case .number(let integer, let minimum, let maximum):
      if integer { o["integer"] = .bool(true) }
      if let minimum { o["minimum"] = .number(minimum) }
      if let maximum { o["maximum"] = .number(maximum) }
    case .enumeration(let values): o["values"] = .array(values.map(\.jsonValue))
    case .union(let variants): o["variants"] = .array(variants.map(\.canonicalJSON))
    case .object(let fields, let rest):
      o["fields"] = .array(fields.map(\.canonicalJSON))
      if let rest { o["rest"] = rest.canonicalJSON }
    case .record(let value, let languageKeys):
      o["value"] = value.canonicalJSON
      if languageKeys { o["keys"] = .string("languages") }
    case .array(let items): o["items"] = items.canonicalJSON
    case .boolean, .string, .json: break
    }
    return .object(o)
  }
}

extension OptionField {
  /// scripts/lib/option-schema-canon.mjs, `canonField`.
  var canonicalJSON: JSONValue {
    var o = JSONObject([("key", .string(key)), ("node", node.canonicalJSON)])
    if let title { o["title"] = .string(title) }
    if let description { o["description"] = .string(description) }
    o["hasDefault"] = .bool(hasDefault)
    if let defaultValue { o["default"] = defaultValue }
    if let when { o["when"] = .object(when) }
    if let group { o["group"] = .string(group) }
    if let order { o["order"] = .number(order) }
    if advanced { o["advanced"] = .bool(true) }
    if let widget {
      var w = JSONObject()
      switch widget {
      case .snippetFile(let dirOption):
        w["kind"] = .string("snippetFile")
        if let dirOption { w["dirOption"] = .string(dirOption) }
      case .html: w["kind"] = .string("html")
      case .markdown: w["kind"] = .string("markdown")
      case .glob: w["kind"] = .string("glob")
      }
      o["widget"] = .object(w)
    }
    if let l10n {
      var texts = JSONObject()
      for (language, t) in l10n {
        var text = JSONObject()
        if let title = t.title { text["title"] = .string(title) }
        if let description = t.description { text["description"] = .string(description) }
        if let group = t.group { text["group"] = .string(group) }
        if let labels = t.enumLabels { text["enum"] = .object(JSONObject(labels.map { ($0.value, .string($0.label)) })) }
        texts[language] = .object(text)
      }
      o["l10n"] = .object(texts)
    }
    o["origin"] = .string(origin.rawValue)
    return .object(o)
  }
}

extension NormalizedOptionSchema {
  /// scripts/lib/option-schema-canon.mjs, `canonSchema`.
  var canonicalJSON: JSONValue {
    .object(JSONObject([
      ("source", .string(source.rawValue)),
      ("fields", .array(fields.map(\.canonicalJSON))),
      ("notes", .array(notes.map { .object(JSONObject([("path", .array($0.path.map(JSONValue.string))), ("reason", .string($0.reason))])) }))
    ]))
  }
}
