import Foundation

/// What the Formulare editor knows about quartz-forms (QuartzControl's
/// `routes/Plugins/formsOptions.ts`, measured against it in FormsOptionsTests): the id and field
/// name rules, the four templates word for word, how a form is laid over its template and the
/// global transport, the field types, conditions, where a message of the plugin's check belongs,
/// and which captcha secrets the relay needs. What the build says about a definition is not
/// copied: the tab asks the plugin itself (`FormsCLI.check`).
///
/// Matching is spelled out by hand, not with regular expressions: JavaScript's `$`, `\s`, `\d` and
/// `\b` are not ICU's (decisions/phase-4-oberflaeche.md, Navigationen), and the patterns are small.
public enum FormsOptions {
  public static let plugin = "quartz-forms"
  /// The version whose source the copies are read from.
  public static let readAgainst = "0.6.0"
  /// Versions whose source is the same as that one's: `git diff v0.6.0 v0.6.1 -- src` changes
  /// comments and the header comment of the generated relay file, nothing the copies read.
  public static let sameCode = ["0.6.1"]
  /// Widths, the arrangement of options, conditions and page breaks came with this version.
  public static let layoutSince = "0.4.0"
  /// `dist/cli.js texts` came with this version.
  public static let textsSince = "0.5.9"
  /// The relay's `envelopeSender` came with this version.
  public static let envelopeSenderSince = "0.6.0"

  public static let reservedNames = ["form", "lang", "page", "ts", "pow", "captcha", "encrypted", "ciphertext", "fields", "pageTitle",
                                     "cf-turnstile-response", "h-captcha-response"]
  public static let templateNames = ["contact", "feedback", "rsvp", "survey"]
  public static let transportKinds = ["relay", "endpoint", "formspree", "web3forms", "mailto", "demo"]
  public static let encryptionModes = ["required", "optional", "off"]

  private static func tx(_ en: String, _ de: String) -> JSONValue { .object(JSONObject([("en", .string(en)), ("de", .string(de))])) }
  private static func obj(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(JSONObject(pairs)) }
  private static func n(_ value: Double) -> JSONValue { .number(value) }
  private static func s(_ text: String) -> JSONValue { .string(text) }

  /// The plugin's templates, word for word (src/templates/index.ts).
  public static let templates: [String: JSONObject] = [
    "contact": JSONObject([
      ("title", tx("Contact", "Kontakt")),
      ("fields", .array([
        obj([("type", s("text")), ("name", s("name")), ("label", tx("Name", "Name")), ("autocomplete", s("name"))]),
        obj([("type", s("email")), ("name", s("email")), ("label", tx("E-mail", "E-Mail")),
             ("hint", tx("Only if you want a reply.", "Nur, wenn du eine Antwort möchtest.")), ("autocomplete", s("email"))]),
        obj([("type", s("textarea")), ("name", s("message")), ("label", tx("Message", "Nachricht")), ("required", .bool(true))]),
        obj([("type", s("consent")), ("name", s("consent")),
             ("text", tx("I agree that my message is processed to answer it.", "Ich bin einverstanden, dass meine Nachricht zur Beantwortung verarbeitet wird."))])
      ]))
    ]),
    "feedback": JSONObject([
      ("title", tx("Feedback on this page", "Feedback zu dieser Seite")),
      ("pageContext", .bool(true)),
      ("fields", .array([
        obj([("type", s("scale")), ("name", s("rating")), ("label", tx("How helpful was this page?", "Wie hilfreich war diese Seite?")),
             ("min", n(1)), ("max", n(5)), ("minLabel", tx("Not at all", "Gar nicht")), ("maxLabel", tx("Very", "Sehr")), ("required", .bool(true))]),
        obj([("type", s("textarea")), ("name", s("comment")), ("label", tx("What could be better?", "Was könnte besser sein?")), ("rows", n(4))])
      ]))
    ]),
    "rsvp": JSONObject([
      ("title", tx("Sign up", "Anmeldung")),
      ("fields", .array([
        obj([("type", s("text")), ("name", s("name")), ("label", tx("Name", "Name")), ("required", .bool(true)), ("autocomplete", s("name"))]),
        obj([("type", s("email")), ("name", s("email")), ("label", tx("E-mail", "E-Mail")), ("required", .bool(true)), ("autocomplete", s("email"))]),
        obj([("type", s("select")), ("name", s("choice")), ("label", tx("Date", "Termin")), ("required", .bool(true)),
             ("options", .array([obj([("value", s("1")), ("label", tx("First date", "Erster Termin"))]),
                                 obj([("value", s("2")), ("label", tx("Second date", "Zweiter Termin"))])]))]),
        obj([("type", s("number")), ("name", s("guests")), ("label", tx("Number of people", "Anzahl Personen")), ("min", n(1)), ("max", n(10)),
             ("required", .bool(true))]),
        obj([("type", s("textarea")), ("name", s("note")), ("label", tx("Note", "Anmerkung")), ("rows", n(3))]),
        obj([("type", s("consent")), ("name", s("consent")),
             ("text", tx("I agree that my details are stored to organise the event.", "Ich bin einverstanden, dass meine Angaben zur Organisation gespeichert werden."))])
      ]))
    ]),
    "survey": JSONObject([
      ("title", tx("Survey", "Umfrage")),
      ("anonymous", .bool(true)),
      ("fields", .array([
        obj([("type", s("radio")), ("name", s("usage")), ("label", tx("How often do you visit this site?", "Wie oft besuchst du diese Website?")),
             ("required", .bool(true)),
             ("options", .array([obj([("value", s("first")), ("label", tx("First time", "Zum ersten Mal"))]),
                                 obj([("value", s("sometimes")), ("label", tx("Now and then", "Gelegentlich"))]),
                                 obj([("value", s("often")), ("label", tx("Often", "Oft"))])]))]),
        obj([("type", s("checkboxes")), ("name", s("topics")), ("label", tx("Which topics interest you?", "Welche Themen interessieren dich?")),
             ("options", .array([obj([("value", s("news")), ("label", tx("News", "Neuigkeiten"))]),
                                 obj([("value", s("guides")), ("label", tx("Guides", "Anleitungen"))]),
                                 obj([("value", s("background")), ("label", tx("Background", "Hintergrund"))])]))]),
        obj([("type", s("scale")), ("name", s("satisfaction")), ("label", tx("How satisfied are you overall?", "Wie zufrieden bist du insgesamt?")),
             ("min", n(1)), ("max", n(5))]),
        obj([("type", s("textarea")), ("name", s("comment")), ("label", tx("Anything else?", "Noch etwas?")), ("rows", n(3))])
      ]))
    ])
  ]

  // ── matching by hand ───────────────────────────────────────────────────────────────────────────

  private static func ascii(_ u: UInt16, lower: Bool = true, upper: Bool = false, digit: Bool = true) -> Bool {
    (lower && (0x61...0x7A).contains(u)) || (upper && (0x41...0x5A).contains(u)) || (digit && (0x30...0x39).contains(u))
  }

  /// `/^[a-z0-9][a-z0-9-]*$/`
  public static func isFormId(_ id: String) -> Bool {
    let units = Array(id.utf16)
    guard let first = units.first, ascii(first) else { return false }
    return units.dropFirst().allSatisfy { ascii($0) || $0 == 0x2D }
  }

  /// `/^[A-Za-z][A-Za-z0-9_-]*$/`
  public static func isFieldName(_ name: String) -> Bool {
    let units = Array(name.utf16)
    guard let first = units.first, ascii(first, digit: false, upper: true) else { return false }
    return units.dropFirst().allSatisfy { ascii($0, upper: true) || $0 == 0x5F || $0 == 0x2D }
  }

  private static func ascii(_ u: UInt16, digit: Bool, upper: Bool) -> Bool { ascii(u, lower: true, upper: upper, digit: digit) }

  /// JavaScript's `toLowerCase`, which only NSString matches (MultilanguageOptions.normalizeCode).
  static func lower(_ text: String) -> String { (text as NSString).lowercased }

  // ── forms ──────────────────────────────────────────────────────────────────────────────────────

  public struct Entry: Sendable {
    public var plugin: PluginEntry
    public var index: Int
  }

  public static func entries(_ plugins: [PluginEntry]) -> [Entry] {
    plugins.enumerated().compactMap { index, plugin in
      PluginRepository.quartzName(plugin.source) == Self.plugin ? Entry(plugin: plugin, index: index) : nil
    }
  }

  /// The forms as written, in their order; a key whose value is no object counts as an empty form.
  public static func forms(_ options: JSONObject?) -> [(id: String, def: JSONObject)] {
    guard case .object(let raw)? = options?["forms"] else { return [] }
    return raw.keys.map { ($0, raw[$0]?.objectValue ?? JSONObject()) }
  }

  public static func isTemplate(_ name: JSONValue?) -> Bool {
    name?.stringValue.map(templateNames.contains) ?? false
  }

  /// A form as the plugin reads it: laid over its template, own `fields` replacing the template's.
  public static func effectiveForm(_ def: JSONObject) -> JSONObject {
    var merged = def["template"]?.stringValue.flatMap { templates[$0] } ?? JSONObject()
    for key in def.keys where def[key] != .null { merged[key] = def[key] }
    let fields: [JSONValue] = if case .array(let list)? = merged["fields"] { list.filter { $0.objectValue != nil } } else { [] }
    merged["fields"] = .array(fields)
    return merged
  }

  public static func fields(_ def: JSONObject) -> [JSONObject] {
    effectiveForm(def)["fields"]?.arrayValue?.compactMap(\.objectValue) ?? []
  }

  /// Whether the fields are the template's: no own `fields`, a template set.
  public static func usesTemplateFields(_ def: JSONObject) -> Bool {
    guard isTemplate(def["template"]) else { return false }
    if case .array? = def["fields"] { return false }
    return true
  }

  /// The transport kind a form sends through: its own, else the global one, else the relay.
  public static func transportKind(_ def: JSONObject, _ options: JSONObject?) -> String {
    if let own = def["transport"]?.objectValue?["kind"]?.stringValue { return own }
    return options?["transport"]?.objectValue?["kind"]?.stringValue ?? "relay"
  }

  public static func encryptionMode(_ def: JSONObject) -> String {
    def["encryption"]?.objectValue?["mode"]?.stringValue ?? "off"
  }

  public static func isAnonymous(_ def: JSONObject) -> Bool { effectiveForm(def)["anonymous"] == .bool(true) }

  static func splitLang(_ text: String) -> String {
    String(lower(text).split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
  }

  /// A Text in one language: the exact code, the primary subtag, then the first entry.
  public static func text(_ text: JSONValue?, _ lang: String) -> String {
    if case .string(let plain)? = text { return plain }
    guard case .object(let map)? = text else { return "" }
    let entries = map.keys.compactMap { key in map[key]?.stringValue.map { (key, $0) } }
    let primary = splitLang(lang)
    let hit = entries.first { lower($0.0) == lower(lang) } ?? entries.first { splitLang($0.0) == primary } ?? entries.first
    return hit?.1 ?? ""
  }

  public enum IdProblem: String, Sendable { case empty, pattern, taken }

  public static func formIdProblem(_ id: String, existing: [String], own: String? = nil) -> IdProblem? {
    if id.isEmpty { return .empty }
    if !isFormId(id) { return .pattern }
    if id != own, existing.contains(id) { return .taken }
    return nil
  }

  public enum FieldNameProblem: String, Sendable { case empty, pattern, reserved, taken }

  public static func fieldNameProblem(_ name: String, others: [String]) -> FieldNameProblem? {
    if name.isEmpty { return .empty }
    if !isFieldName(name) { return .pattern }
    if reservedNames.contains(name) { return .reserved }
    if others.contains(name) { return .taken }
    return nil
  }

  /// A free id after `base`: `base`, then `base-2`, `base-3` …
  public static func freeId(_ base: String, existing: [String]) -> String {
    // `.replace(/[^a-z0-9-]+/g, '-')`: a run of anything else, a surrogate pair included, is one dash.
    var replaced: [UInt16] = []
    var inRun = false
    for u in lower(base).utf16 {
      if ascii(u) || u == 0x2D {
        replaced.append(u)
        inRun = false
      } else if !inRun {
        replaced.append(0x2D)
        inRun = true
      }
    }
    var slice = replaced[...]
    while slice.first == 0x2D { slice = slice.dropFirst() }
    while slice.last == 0x2D { slice = slice.dropLast() }
    let clean = slice.isEmpty ? "form" : String(decoding: slice, as: UTF16.self)
    if !existing.contains(clean) { return clean }
    var n = 2
    while existing.contains("\(clean)-\(n)") { n += 1 }
    return "\(clean)-\(n)"
  }

  private static func withForms(_ options: JSONObject, _ entries: [(String, JSONObject)]) -> JSONObject {
    var next = options
    next["forms"] = .object(JSONObject(entries.map { ($0.0, .object($0.1)) }))
    return next
  }

  public static func withForm(_ options: JSONObject, id: String, def: JSONObject) -> JSONObject {
    var list = forms(options).map { ($0.id, $0.def) }
    if let at = list.firstIndex(where: { $0.0 == id }) { list[at] = (id, def) } else { list.append((id, def)) }
    return withForms(options, list)
  }

  /// Renames a form where it stands; the layout form follows. Pages that embed it do not.
  public static func rename(_ options: JSONObject, from: String, to: String) -> JSONObject {
    var next = withForms(options, forms(options).map { ($0.id == from ? to : $0.id, $0.def) })
    if next["layoutForm"] == .string(from) { next["layoutForm"] = .string(to) }
    return next
  }

  public static func remove(_ options: JSONObject, id: String) -> JSONObject {
    var next = withForms(options, forms(options).filter { $0.id != id }.map { ($0.id, $0.def) })
    if next["layoutForm"] == .string(id) { next["layoutForm"] = .string("") }
    return next
  }

  /// A copy of a form right after it, under a free id.
  public static func duplicate(_ options: JSONObject, id: String) -> (options: JSONObject, id: String) {
    var list = forms(options).map { ($0.id, $0.def) }
    guard let at = list.firstIndex(where: { $0.0 == id }) else { return (options, id) }
    let copy = freeId("\(id)-copy", existing: list.map(\.0))
    list.insert((copy, list[at].1), at: at + 1)
    return (withForms(options, list), copy)
  }

  /// The start of a new form: a template, or a single message field (a form without fields stops
  /// the build, so "empty" is the smallest form that builds).
  public static func newForm(_ start: String, messageLabel: String) -> JSONObject {
    if start != "empty" { return JSONObject([("template", .string(start))]) }
    return JSONObject([("fields", .array([obj([("type", s("textarea")), ("name", s("message")), ("label", s(messageLabel)), ("required", .bool(true))])]))])
  }

  // ── the schema's parts ─────────────────────────────────────────────────────────────────────────

  /// The fields of one form as the plugin's schema describes them: the value of the `forms` record.
  public static func formSchema(_ schema: NormalizedOptionSchema?) -> NormalizedOptionSchema? {
    guard let schema, case .record(let value, _)? = schema.fields.first(where: { $0.key == "forms" })?.node,
          case .object(let fields, _) = value else { return nil }
    return NormalizedOptionSchema(source: schema.source, fields: fields, notes: [])
  }

  /// The schema of one top-level object option (`spam`, `transport`).
  public static func objectSchema(_ schema: NormalizedOptionSchema?, key: String) -> NormalizedOptionSchema? {
    guard let schema, case .object(let fields, _)? = schema.fields.first(where: { $0.key == key })?.node else { return nil }
    return NormalizedOptionSchema(source: schema.source, fields: fields, notes: [])
  }

  /// The fields of the field shape for `type`: the variant of the `fields` union whose `type` names it.
  public static func fieldVariant(_ form: NormalizedOptionSchema?, type: String) -> [OptionField] {
    guard case .array(let items)? = form?.fields.first(where: { $0.key == "fields" })?.node else { return [] }
    let variants: [OptionNode] = if case .union(let list) = items { list } else { [items] }
    for case .object(let fields, _) in variants {
      if case .enumeration(let values)? = fields.first(where: { $0.key == "type" })?.node, values.contains(.string(type)) { return fields }
    }
    return []
  }

  /// The value an option has when unset: the plugin's default for it.
  public static func defaultOf(_ schema: NormalizedOptionSchema?, key: String) -> JSONValue? {
    schema?.fields.first { $0.key == key }?.defaultValue
  }

  /// Global spam or transport as the plugin resolves it: its defaults, the written keys over them.
  public static func resolvedGlobal(_ schema: NormalizedOptionSchema?, _ options: JSONObject?, key: String) -> JSONObject {
    var out = defaultOf(schema, key: key)?.objectValue ?? JSONObject()
    if let own = options?[key]?.objectValue { for k in own.keys { out[k] = own[k] } }
    return out
  }

  /// The settings rows below the list, by the keys each one shows. `relay` is the tab's own.
  public static let sections: [(id: String, keys: [String])] = [
    ("transport", ["transport"]), ("keys", ["keys"]), ("spam", ["spam"]), ("layout", ["layoutForm", "language"]), ("relay", []),
    ("texts", ["texts"]), ("technical", ["frontmatterKey", "codeBlockLang"])
  ]

  public struct Embed: Equatable, Sendable {
    public var codeBlock: String
    public var placeholder: String
    public var frontmatter: String
  }

  /// What the code block and the placeholder look like for a form, with the plugin's own words.
  public static func embed(_ id: String, _ options: JSONObject?) -> Embed {
    func set(_ key: String, _ fallback: String) -> String {
      guard let text = options?[key]?.stringValue, !ReadmeText.trim(text).isEmpty else { return fallback }
      return text
    }
    let lang = set("codeBlockLang", "quartz-form"), key = set("frontmatterKey", "form")
    return Embed(codeBlock: "```\(lang)\n\(id)\n```", placeholder: "{{form:\(id)}}", frontmatter: "\(key): \(id)")
  }

  // ── keys (FormsKeys.tsx) ──────────────────────────────────────────────────────────────────────

  /// The forms that encrypt to a key: every encrypting form without a list of its own, and those that name it.
  public static func formsUsingKey(_ options: JSONObject?, name: String) -> [String] {
    forms(options).filter { form in
      guard encryptionMode(form.def) != "off" else { return false }
      guard case .array(let keys)? = form.def["encryption"]?.objectValue?["keys"] else { return true }
      return keys.contains(.string(name))
    }.map(\.id)
  }

  /// Takes a key out of `keys` and out of every form's own list; a list left empty goes (= all keys).
  public static func withoutKey(_ options: JSONObject, name: String) -> JSONObject {
    var keys = options["keys"]?.objectValue ?? JSONObject()
    keys[name] = nil
    var next = options
    next["keys"] = .object(keys)
    guard options["forms"]?.objectValue != nil else { return next }
    let list = forms(options).map { form -> (String, JSONObject) in
      guard var encryption = form.def["encryption"]?.objectValue, case .array(let own)? = encryption["keys"],
            own.contains(.string(name)) else { return (form.id, form.def) }
      let rest = own.filter { $0 != .string(name) }
      encryption["keys"] = rest.isEmpty ? nil : .array(rest)
      var def = form.def
      def["encryption"] = .object(encryption)
      return (form.id, def)
    }
    next["forms"] = .object(JSONObject(list.map { ($0.0, .object($0.1)) }))
    return next
  }

  public enum KeyNameProblem: String, Sendable { case empty, pattern, taken }

  /// A key's name: `/^[A-Za-z0-9_-]{1,64}$/`, not one that is there.
  public static func keyNameProblem(_ name: String, existing: [String]) -> KeyNameProblem? {
    if name.isEmpty { return .empty }
    let units = Array(name.utf16)
    guard units.count <= 64, units.allSatisfy({ ascii($0, upper: true) || $0 == 0x5F || $0 == 0x2D }) else { return .pattern }
    return existing.contains { $0.utf16.elementsEqual(name.utf16) } ? .taken : nil
  }

  // ── the relay (FormsRelay.tsx) ──────────────────────────────────────────────────────────────────

  /// A recipient name the relay maps to an address: `/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/`.
  public static func isRecipientName(_ name: String) -> Bool {
    let units = Array(name.utf16)
    guard let first = units.first, ascii(first, upper: true), units.count <= 64 else { return false }
    return units.dropFirst().allSatisfy { ascii($0, upper: true) || $0 == 0x5F || $0 == 0x2E || $0 == 0x2D }
  }

  /// `/@example\./i`: the relay reads such an address as its template's placeholder, i.e. as missing.
  /// The i flag without u folds ASCII only.
  public static func isExampleAddress(_ address: String) -> Bool {
    let folded = String(decoding: address.utf16.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 }, as: UTF16.self)
    return JSText.includes(folded, "@example.")
  }

  /// "Erlaubte Origins" as typed: `split(/[,\s]+/)`, trimmed, the empty ones left out.
  public static func origins(_ text: String) -> [String] {
    var out: [String] = []
    var current: [UInt16] = []
    for unit in text.utf16 {
      if unit == 0x2C || ReadmeText.isSpace(unit) {
        if !current.isEmpty { out.append(String(decoding: current, as: UTF16.self)); current = [] }
      } else {
        current.append(unit)
      }
    }
    if !current.isEmpty { out.append(String(decoding: current, as: UTF16.self)) }
    return out
  }

  // ── fields ─────────────────────────────────────────────────────────────────────────────────────

  /// The field types by the group the "add field" tiles show them in.
  public static let fieldGroups: [(id: String, types: [String])] = [
    ("text", ["text", "textarea", "email", "tel", "url", "number", "date"]),
    ("choice", ["select", "radio", "checkboxes", "checkbox", "scale"]),
    ("other", ["consent", "pgpKey", "hidden"]),
    // Not a field but where a step begins (0.4.0); it has no name and no value.
    ("structure", ["pageBreak"])
  ]

  /// Types that share a shape: a field can change between them and keep its keys.
  public static let sameShape: [[String]] = [["text", "email", "tel", "url", "number", "date", "textarea"], ["select", "radio", "checkboxes"]]

  /// Which of the input keys each input type reads (render/form.ts).
  public static let inputKeys: [String: [String]] = [
    "text": ["placeholder", "autocomplete", "pattern", "maxLength"], "email": ["placeholder", "autocomplete", "pattern", "maxLength"],
    "tel": ["placeholder", "autocomplete", "pattern", "maxLength"], "url": ["placeholder", "autocomplete", "pattern", "maxLength"],
    "number": ["placeholder", "min", "max", "step"], "date": ["min", "max"], "textarea": ["placeholder", "rows", "maxLength"]
  ]

  /// Autocomplete tokens that name a person (src/validate.ts, PERSONAL_AUTOCOMPLETE).
  public static let personalAutocomplete = ["name", "given-name", "family-name", "additional-name", "honorific-prefix", "honorific-suffix", "nickname",
                                            "username", "street-address", "address-line1", "address-line2", "postal-code", "tel", "email", "bday",
                                            "organization"]

  /// Does this field ask for something that identifies a person (src/validate.ts, isPersonalField)?
  public static func isPersonalField(_ field: JSONObject) -> Bool {
    switch field["type"]?.stringValue {
    case "email", "tel", "pgpKey": return true
    case "text", "textarea", "url", "date", "number": return field["autocomplete"]?.stringValue.map(personalAutocomplete.contains) ?? false
    default: return false
    }
  }

  /// A free field name after `base`: `base`, then `base2`, `base3` …
  public static func freeFieldName(_ base: String, taken: [String]) -> String {
    let kept = base.utf16.filter { ascii($0, upper: true) || $0 == 0x5F || $0 == 0x2D }
    let start = kept.firstIndex { ascii($0, digit: false, upper: true) } ?? kept.endIndex
    let cleaned = String(decoding: kept[start...], as: UTF16.self)
    let clean = cleaned.isEmpty ? "field" : cleaned
    let free = { (name: String) in !taken.contains(name) && !reservedNames.contains(name) }
    if free(clean) { return clean }
    var n = 2
    while !free("\(clean)\(n)") { n += 1 }
    return "\(clean)\(n)"
  }

  // ── conditions (0.4.0) ─────────────────────────────────────────────────────────────────────────

  /// The fields a condition may name: they have values to compare (src/conditions.ts).
  public static let controllerTypes = ["select", "radio", "checkboxes", "checkbox", "scale"]

  public struct ShowIf: Equatable, Sendable {
    public var field: String
    public var equals: [String]
  }

  /// A field's or a page break's `showIf` as the plugin reads it; nil when absent or not well formed.
  public static func showIf(_ field: JSONObject) -> ShowIf? {
    guard case .object(let showIf)? = field["showIf"], let name = showIf["field"]?.stringValue, !name.isEmpty else { return nil }
    let list: [JSONValue] = switch showIf["equals"] {
    case .string(let one)?: [.string(one)]
    case .array(let many)?: many
    default: []
    }
    let values = list.compactMap(\.stringValue).filter { !$0.isEmpty }
    return values.isEmpty ? nil : ShowIf(field: name, equals: values)
  }

  public static func isController(_ field: JSONObject) -> Bool {
    field["type"]?.stringValue.map(controllerTypes.contains) ?? false && field["name"]?.stringValue != nil
  }

  /// The values a condition on this field can name, with what visitors see.
  public static func controllerValues(_ field: JSONObject, lang: String) -> [(value: String, label: String)] {
    switch field["type"]?.stringValue {
    case "select", "radio", "checkboxes":
      guard case .array(let options)? = field["options"] else { return [] }
      return options.compactMap(\.objectValue).compactMap { option in
        guard let value = option["value"]?.stringValue, !value.isEmpty else { return nil }
        let label = text(option["label"], lang)
        return (value, label.isEmpty ? value : label)
      }
    case "checkbox": return [("yes", "yes")]
    case "scale":
      guard let min = field["min"]?.numberValue, let max = field["max"]?.numberValue, min == min.rounded(), max == max.rounded(),
            min.isFinite, max.isFinite, max >= min, max - min <= 20 else { return [] }
      return stride(from: min, through: max, by: 1).map { let v = JSJSON.numberToString($0); return (v, v) }
    default: return []
    }
  }

  /// One value as a string, several as a list: what a person would write in the YAML.
  public static func showIfValue(field: String, equals: [String]) -> JSONObject {
    JSONObject([("field", .string(field)), ("equals", equals.count == 1 ? .string(equals[0]) : .array(equals.map(JSONValue.string)))])
  }

  /// A field renamed: every condition that named it names the new name.
  public static func renameInConditions(_ fields: [JSONObject], from: String, to: String) -> [JSONObject] {
    fields.map { field in
      guard case .object(var showIf)? = field["showIf"], showIf["field"] == .string(from) else { return field }
      var next = field
      showIf["field"] = .string(to)
      next["showIf"] = .object(showIf)
      return next
    }
  }

  public static func isPageBreak(_ field: JSONObject) -> Bool { field["type"] == .string("pageBreak") }

  /// The number of steps: one more than page breaks.
  public static func stepCount(_ fields: [JSONObject]) -> Int { fields.filter(isPageBreak).count + 1 }

  /// What a field shows as its name in a list: its label, the consent text, else its name; a page
  /// break its title. nil where JavaScript answers undefined (no label, no text, no name).
  public static func fieldLabel(_ field: JSONObject, lang: String) -> String? {
    if isPageBreak(field) { return text(field["title"], lang) }
    let label = text(field["label"], lang)
    if !label.isEmpty { return label }
    let consent = text(field["text"], lang)
    if !consent.isEmpty { return consent }
    switch field["name"] {
    case nil: return nil
    case .string(let name)?: return name
    case let other?: return OptionFormText.inline(other)
    }
  }

  // ── what the plugin's check says, placed ───────────────────────────────────────────────────────

  /// A message of quartz-forms' check with the place its path names. `rest` is the message
  /// without the part of the path the place already says.
  public struct PlacedMessage: Equatable, Sendable {
    public var text: String
    public var form: String?
    public var field: Int?
    public var section: String?
    public var rest: String
  }

  private static let sectionPrefixes: [(keys: [String], section: String)] = [
    (["keys"], "keys"), (["transport"], "transport"), (["spam"], "spam"), (["layoutForm", "language"], "layout"), (["texts"], "texts"),
    (["frontmatterKey", "codeBlockLang"], "technical")
  ]

  public static func place(_ text: String) -> PlacedMessage {
    let units = Array(text.utf16)
    // `/^forms\.([a-z0-9][a-z0-9-]*)(?:\.fields\[(\d+)\])?\.?/`
    let head = Array("forms.".utf16)
    if units.starts(with: head), units.count > head.count, ascii(units[head.count]) {
      var i = head.count + 1
      while i < units.count, ascii(units[i]) || units[i] == 0x2D { i += 1 }
      let form = String(decoding: units[head.count..<i], as: UTF16.self)
      var field: Int?
      let fieldsHead = Array(".fields[".utf16)
      if units[i...].starts(with: fieldsHead) {
        var j = i + fieldsHead.count
        let digitsStart = j
        while j < units.count, (0x30...0x39).contains(units[j]) { j += 1 }
        if j > digitsStart, j < units.count, units[j] == 0x5D {
          field = Int(String(decoding: units[digitsStart..<j], as: UTF16.self))
          i = j + 1
        }
      }
      if i < units.count, units[i] == 0x2E { i += 1 }
      var r = i
      while r < units.count, units[r] == 0x3A || ReadmeText.isSpace(units[r]) { r += 1 }
      return PlacedMessage(text: text, form: form, field: field, rest: String(decoding: units[r...], as: UTF16.self))
    }
    for (keys, section) in sectionPrefixes {
      for key in keys {
        let k = Array(key.utf16)
        if units.starts(with: k), units.count > k.count, units[k.count] == 0x2E || units[k.count] == 0x3A {
          return PlacedMessage(text: text, section: section, rest: text)
        }
      }
    }
    return PlacedMessage(text: text, rest: text)
  }

  /// The keys of a form the panel shows with its own controls.
  public static let formKeys: Set<String> = ["template", "title", "description", "submitLabel", "fields", "recipient", "subject", "transport",
                                             "encryption", "anonymous", "pageContext", "spam", "success", "className"]

  /// The parts of the panel of one form, in their order.
  public enum Part: String, Sendable, CaseIterable { case general, fields, sending, privacy, spam, embed, more }

  /// `key(?=[.:[\s]|$)` at the start of `rest`.
  private static func startsWithKey(_ units: [UInt16], _ key: String) -> Bool {
    let k = Array(key.utf16)
    guard units.starts(with: k) else { return false }
    guard units.count > k.count else { return true }
    let next = units[k.count]
    return next == 0x2E || next == 0x3A || next == 0x5B || ReadmeText.isSpace(next)
  }

  /// `\w` without the u flag: ASCII letters, digits and `_`.
  private static func isWord(_ u: UInt16) -> Bool { ascii(u, upper: true) || u == 0x5F }

  /// The part of the form panel a message belongs to, by the key its path starts with. "no fields"
  /// is said on the form's own path up to quartz-forms 0.5.9 and belongs to the fields; a key the
  /// panel does not know belongs under "Unbekannte Schlüssel".
  public static func part(_ m: PlacedMessage) -> Part {
    if m.field != nil { return .fields }
    let rest = Array(m.rest.utf16)
    if m.form != nil {
      for phrase in ["no fields", "keine Felder"] {
        let p = Array(phrase.utf16)
        if rest.starts(with: p), rest.count == p.count || !isWord(rest[p.count]) { return .fields }
      }
      // `/^([A-Za-z_$][\w$]*)(?=[.:[])/`
      if let first = rest.first, ascii(first, digit: false, upper: true) || first == 0x5F || first == 0x24 {
        var i = 1
        while i < rest.count, isWord(rest[i]) || rest[i] == 0x24 { i += 1 }
        if i < rest.count, rest[i] == 0x2E || rest[i] == 0x3A || rest[i] == 0x5B {
          let key = String(decoding: rest[..<i], as: UTF16.self)
          if !formKeys.contains(key) { return .more }
        }
      }
    }
    if startsWithKey(rest, "fields") { return .fields }
    if ["transport", "recipient", "subject"].contains(where: { startsWithKey(rest, $0) }) { return .sending }
    if ["encryption", "anonymous", "pageContext"].contains(where: { startsWithKey(rest, $0) }) { return .privacy }
    if startsWithKey(rest, "spam") { return .spam }
    return .general
  }

  // ── which captcha secrets the relay needs ──────────────────────────────────────────────────────

  public struct CaptchaNeeds: Equatable, Sendable {
    /// A relay form uses the captcha set for all forms: `captchaSecret` in config.php.
    public var global: String?
    /// Relay forms with a provider or site key of their own: `captchaSecrets[<form>]`.
    public var forms: [(id: String, provider: String)]

    public static func == (a: CaptchaNeeds, b: CaptchaNeeds) -> Bool {
      a.global == b.global && a.forms.map(\.id) == b.forms.map(\.id) && a.forms.map(\.provider) == b.forms.map(\.provider)
    }
  }

  /// What the relay must be told to verify the captchas. Only relay forms count, and not anonymous
  /// ones; a form needs a secret of its own when its `spam` sets another provider or site key.
  public static func captchaNeeds(_ options: JSONObject?, globalSpam: JSONObject) -> CaptchaNeeds {
    let globalProvider = globalSpam["captcha"]?.stringValue ?? "none"
    let globalKey = globalSpam["captchaSiteKey"]?.stringValue ?? ""
    var usesGlobal = false
    var own: [(String, String)] = []
    for (id, def) in forms(options) {
      guard transportKind(def, options) == "relay", !isAnonymous(def) else { continue }
      let spam = def["spam"]?.objectValue ?? JSONObject()
      let provider = spam["captcha"]?.stringValue ?? globalProvider
      if provider == "none" { continue }
      let key = spam["captchaSiteKey"]?.stringValue ?? globalKey
      if provider == globalProvider && key == globalKey { usesGlobal = true } else { own.append((id, provider)) }
    }
    return CaptchaNeeds(global: usesGlobal ? globalProvider : nil, forms: own)
  }

  // ── texts ──────────────────────────────────────────────────────────────────────────────────────

  public static func primary(_ code: String) -> String { splitLang(code) }

  /// The two lines the relay writes itself for every unencrypted post, in its own words.
  public static let relayOwnWords: Set<String> = ["messagePage", "messageKey"]

  /// The entry of `texts` a site language writes to: the one named exactly as the language, else
  /// one of its primary subtag, else a new one under the language's code.
  public static func entryKey(_ texts: JSONObject, code: String) -> String {
    texts.keys.first { lower($0) == code } ?? texts.keys.first { primary($0) == primary(code) } ?? code
  }

  // ── the form extras ────────────────────────────────────────────────────────────────────────────

  /// quartz-forms in the plugin list and the inspector (QuartzControl's `formsRoot`): an anonymous
  /// form sends no page context, which its schema cannot say.
  public static func root(translate: @escaping OptionFormText.Translate = catalog) -> OptionRoot {
    OptionRoot(entryReason: { key, entry, _ in
      key == "pageContext" && isAnonymous(entry) ? translate("formsEditor.pageContextAnonymous", nil) : nil
    })
  }

  public static let catalog: OptionFormText.Translate = { key, _ in
    switch key {
    case "formsEditor.pageContextAnonymous": L10n.t("formsEditor.pageContextAnonymous")
    default: key
    }
  }
}
