import Foundation

/// The labels of a community theme's options: a port of `styleSettingsSchemaService.ts`. A
/// `@quartz-themes/<id>` package carries compiled CSS and the bare class keys only; the original
/// Obsidian theme's CSS has the Style Settings plugin's `/* @settings */` YAML block with titles,
/// descriptions, types, defaults per mode, ranges and options. The theme is found by its slug in
/// Obsidian's theme registry (636 of 700 ported ids in QuartzControl's count), its CSS on GitHub.
///
/// Answers are kept in the profile under `theme-docs/`, an answer of "none" included, for good: they
/// describe published files that do not change. The Theme tab's reload clears one, the Settings page
/// all. (As in QuartzControl, a theme looked up while the registry is unreachable and its copy on
/// disk gone is kept as "none" until then.) The registry is `ThemeCatalog`'s, whose copy lies in
/// the same folder; clearing one answer or all makes it ask the network again.
///
/// With core 3 the schema comes from the theme core loaded (`schema(of:)`), with core's own reading
/// of the blocks. The lookup by id above (`schema(themeId:)`) has no caller in the app since the
/// `@quartz-themes/<id>` page went (plan step 6); it stays, internal, because `ThemesTests` replays
/// QuartzControl's steps through it, and that is what checks the field reader `schema(of:)` shares.
/// The cache's size and clearing serve Settings ▸ Daten & Wartung: the list and old answers.
public actor StyleSettingsSchema {
  /// Clear of the largest real theme.css (Ultra Lobster, 4.35 MB).
  static let maxCssBytes = 16 * 1024 * 1024

  public typealias ReadYaml = @Sendable (String) async -> JSONValue?

  /// The `yaml-edit` helper's `read`: the value, or nil when the text has errors (QuartzControl's
  /// `parse` threw then).
  public static func helperYaml(runtime: RuntimeLocation) -> ReadYaml {
    { text in
      guard let answer = try? await Helper.call("yaml-edit", JSONObject([("op", .string("read")), ("text", .string(text))]), runtime: runtime),
            (answer["errors"]?.arrayValue ?? []).isEmpty else { return nil }
      return answer["value"] ?? .null
    }
  }

  let session: URLSession
  let directory: String
  let readYaml: ReadYaml
  let catalog: ThemeCatalog

  public init(profile: ProfileDirectory = .quartzHub, configuration: URLSessionConfiguration = .ephemeral, timeout: Duration = .seconds(45),
              readYaml: @escaping ReadYaml = StyleSettingsSchema.helperYaml(runtime: .current), now: @escaping @Sendable () -> Date = Date.init,
              catalog: ThemeCatalog? = nil) {
    self.catalog = catalog ?? ThemeCatalog(profile: profile, configuration: configuration, timeout: timeout, now: now)
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let seconds = Double(timeout.components.seconds)
    configuration.timeoutIntervalForRequest = seconds
    configuration.timeoutIntervalForResource = seconds
    Offline.apply(configuration)
    session = URLSession(configuration: configuration)
    directory = profile.file("theme-docs")
    self.readYaml = readYaml
  }

  public struct InvalidThemeId: Error, Equatable { public let id: String }

  /// The ids QuartzControl's schema let through: they become file names here.
  static func check(_ themeId: String) throws {
    guard (1...128).contains(JSText.length(themeId)), JSText.test(themeId, #"\A[a-z0-9][a-z0-9._-]*\z"#) else { throw InvalidThemeId(id: themeId) }
  }

  func cacheDirectory() -> String {
    try? Posix.mkdirs(directory)
    return directory
  }

  /// "Tokyo Night" → "tokyo-night", "80's Neon" → "80s-neon": accents folded, apostrophes dropped,
  /// as the ports derived their package names.
  public static func slugify(_ name: String) -> String {
    let folded = String(String.UnicodeScalarView(name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }))
    var slug = JSText.replaceAll(folded.lowercased(), "['’]", with: "")
    slug = JSText.replaceAll(slug, "[^a-z0-9]+", with: "-")
    slug = JSText.replaceAll(slug, "-+", with: "-")
    return JSText.replaceAll(slug, #"\A-|-\z"#, with: "")
  }

  func get(_ url: String) async -> (status: Int, headers: [String: String], body: Data)? {
    guard let target = URL(string: url), let (data, response) = try? await session.data(from: target), let http = response as? HTTPURLResponse else { return nil }
    var headers: [String: String] = [:]
    for (key, value) in http.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
    return (http.statusCode, headers, data)
  }

  /// `owner/name` and nothing else: it comes from a third party's file and goes into a URL path.
  static func isRepo(_ repo: String) -> Bool { JSText.test(repo, #"\A[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\z"#) }

  func fetchThemeCss(_ repo: String) async -> String? {
    guard Self.isRepo(repo) else { return nil }
    for file in ["theme.css", "obsidian.css"] {
      guard let answer = await get("https://raw.githubusercontent.com/\(repo)/HEAD/\(file)") else { return nil }
      guard (200..<300).contains(answer.status) else { continue }
      let declared = JS.toNumber(answer.headers["content-length"].map { .string($0) } ?? .null)
      if declared.isFinite && declared > Double(Self.maxCssBytes) { return nil }
      let text = String(decoding: answer.body, as: UTF8.self)
      if JSText.length(text) > Self.maxCssBytes { return nil }
      return text
    }
    return nil
  }

  static let kinds: Set<String> = ["heading", "info-text", "class-toggle", "class-select", "variable-text", "variable-number",
                                   "variable-number-slider", "variable-select", "variable-color", "variable-themed-color"]

  static func asString(_ value: JSONValue?) -> String? {
    switch value {
    case .string(let text)?: text
    case .number(let number)?: JSJSON.numberToString(number)
    default: nil
    }
  }

  static func asNumber(_ value: JSONValue?) -> Double? {
    switch value {
    case .number(let number)?: return number
    case .string(let text)? where !JS.trim(text).isEmpty:
      let number = JS.toNumber(.string(text))
      return number.isNaN ? nil : number
    default: return nil
    }
  }

  /// A bare string or a `{ label, value }` pair per option.
  static func options(_ raw: JSONValue?) -> JSONValue? {
    guard case .array(let items)? = raw else { return nil }
    let options = items.compactMap { entry -> JSONValue? in
      if case .string(let text) = entry { return .object(JSONObject([("label", .string(text)), ("value", .string(text))])) }
      guard case .object(let record) = entry, let value = asString(record["value"]) else { return nil }
      return .object(JSONObject([("label", .string(asString(record["label"]) ?? value)), ("value", .string(value))]))
    }
    return options.isEmpty ? nil : .array(options)
  }

  static func field(_ raw: JSONValue, _ blockId: String) -> JSONValue? {
    guard let id = asString(raw[safe: "id"]), !id.isEmpty, let type = asString(raw[safe: "type"]), !type.isEmpty else { return nil }
    var field = JSONObject([("id", .string(id)), ("blockId", .string(blockId)), ("title", .string(asString(raw[safe: "title"]) ?? id)),
                            ("kind", .string(kinds.contains(type) ? type : "unsupported"))])
    if let description = asString(raw[safe: "description"]), !description.isEmpty { field["description"] = .string(description) }
    if let level = asNumber(raw[safe: "level"]) { field["level"] = .number(level) }
    if raw[safe: "collapsed"] == .bool(true) { field["collapsed"] = .bool(true) }
    if let format = asString(raw[safe: "format"]), !format.isEmpty { field["format"] = .string(format) }
    for key in ["min", "max", "step"] { if let number = asNumber(raw[safe: key]) { field[key] = .number(number) } }
    if let options = options(raw[safe: "options"]) { field["options"] = options }
    if case .bool(let flag)? = raw[safe: "default"] { field["default"] = .bool(flag) } else if let value = asString(raw[safe: "default"]) { field["default"] = .string(value) }
    if let light = asString(raw[safe: "default-light"]) { field["defaultLight"] = .string(light) }
    if let dark = asString(raw[safe: "default-dark"]) { field["defaultDark"] = .string(dark) }
    return .object(field)
  }

  /// One block, or nil: hand-written YAML in a CSS comment is often slightly malformed, and one bad
  /// block must not cost the theme its others.
  func block(_ body: String) async -> (id: String, fields: [JSONValue])? {
    guard let document = await readYaml(body), case .object(let record) = document,
          let id = Self.asString(record["id"]) ?? Self.asString(record["name"]), !id.isEmpty,
          case .array(let settings)? = record["settings"] else { return nil }
    return (id, settings.compactMap { Self.field($0 == .null ? .object(JSONObject()) : $0, id) })
  }

  /// The labelled schema of a theme's Style Settings, or `.null` when there is none to be had.
  /// Only for `ThemesTests` (see the type's comment).
  func schema(themeId: String) async throws -> JSONValue {
    try Self.check(themeId)
    let file = "\(cacheDirectory())/\(themeId).json"
    if let data = try? Posix.read(file), let cached = try? JSJSON.parse(data) { return cached }
    let schema = await build(themeId)
    try? JSONStore.writeAtomic(Data(JSJSON.compact(schema).utf8), to: file)
    return schema
  }

  func build(_ themeId: String) async -> JSONValue {
    // A port's variation suffix ("catppuccin.frappe") names the same upstream theme.
    let wanted = JSText.split(themeId, ".")[0]
    guard let entry = await catalog.entries().first(where: { Self.slugify(JS.string($0[safe: "name"])) == wanted }),
          let repo = entry[safe: "repo"]?.stringValue, let css = await fetchThemeCss(repo) else { return .null }
    var blocks: [(id: String, fields: [JSONValue])] = []
    for match in JSText.matches(css, #"/\*["# + JSText.space + #"]*@settings(?![A-Za-z0-9_])([\s\S]*?)\*/"#) {
      if let parsed = await block(match.groups[1] ?? "") { blocks.append(parsed) }
    }
    guard !blocks.isEmpty else { return .null }
    // `{ themeName: entry.name, author: entry.author, … }`: a key the registry entry lacks is left out.
    var schema = GridFrameCss.present([("ids", .array(blocks.map { .string($0.id) })), ("themeName", entry[safe: "name"]), ("author", entry[safe: "author"]),
                                      ("repo", .string(repo))])
    if let screenshot = entry[safe: "screenshot"], JS.truthy(screenshot) {
      schema["screenshotUrl"] = .string("https://raw.githubusercontent.com/\(repo)/HEAD/\(JS.string(screenshot))")
    }
    schema["fields"] = .array(blocks.flatMap(\.fields))
    return .object(schema)
  }

  // MARK: core 3

  /// The schema of a theme core 3 loaded (`ThemeFetch`): its blocks as core read them, theme and
  /// snippets, in the shape `schema(themeId:)` answers, so one form shows both. Nothing is fetched
  /// or kept: the CSS lies in core's cache in the project, and reading it takes the helper's call
  /// (docs/plan-themes-core-3.md, step 3). A 2.x id's preset (`catppuccin.frappe`) applies under the
  /// entry's own values, so it is what a field shows as its default. `.null` without a block.
  public static func schema(of theme: ThemeFetch.Theme, author: String? = nil) -> JSONValue {
    var ids: [JSONValue] = []
    var fields: [JSONValue] = []
    for block in theme.settingsBlocks {
      // core's test: a truthy `id` and a non-empty `settings` list; the id is a key of an object there.
      guard let id = asString(block[safe: "id"]), JS.truthy(block[safe: "id"] ?? .null), case .array(let settings)? = block[safe: "settings"],
            !settings.isEmpty else { continue }
      ids.append(.string(id))
      fields += settings.compactMap { field($0 == .null ? .object(JSONObject()) : $0, id) }
    }
    guard !ids.isEmpty else { return .null }
    if let preset = theme.preset { fields = fields.map { presetDefault($0, preset) } }
    var schema = JSONObject([("ids", .array(ids)), ("themeName", .string(theme.name))])
    if let author, !author.isEmpty { schema["author"] = .string(author) }
    schema["fields"] = .array(fields)
    return .object(schema)
  }

  /// What the form needs beside a core 3 schema: its block ids, and every class key it names as
  /// shipped, since core converts the theme's whole CSS (a ported package shipped only some).
  public static func info(of schema: JSONValue) -> ThemeStyleSettingsInfo {
    let fields = StyleSettingsValues.fields(schema)
    var keys: [String] = []
    for field in fields {
      let named = field.kind == "class-toggle" ? [field.id] : field.kind == "class-select" ? field.options.map(\.value) : []
      for key in named where !key.isEmpty && !keys.contains(key) { keys.append(key) }
    }
    return ThemeStyleSettingsInfo(styleSettingsId: (schema["ids"]?.arrayValue ?? []).compactMap(\.stringValue), classSettingKeys: keys)
  }

  /// A field whose default is the preset's value where the preset has one, the way core's
  /// `resolveStyleSettings` reads `<block>@@<setting>[@@light|@@dark]`: a themed colour without a
  /// mode is the dark one.
  static func presetDefault(_ field: JSONValue, _ preset: JSONObject) -> JSONValue {
    guard case .object(var object) = field, let blockId = object["blockId"]?.stringValue, let id = object["id"]?.stringValue else { return field }
    let kind = object["kind"]?.stringValue
    func value(_ key: String) -> JSONValue? {
      switch preset[key] {
      case .bool(let flag)?: .bool(flag)
      case let other?: asString(other).map(JSONValue.string)
      case nil: nil
      }
    }
    if kind == "variable-themed-color" {
      if let light = value("\(blockId)@@\(id)@@light")?.stringValue { object["defaultLight"] = .string(light) }
      if let dark = value("\(blockId)@@\(id)@@dark")?.stringValue ?? value("\(blockId)@@\(id)")?.stringValue { object["defaultDark"] = .string(dark) }
    } else if let preset = value("\(blockId)@@\(id)") {
      object["default"] = preset
    }
    return .object(object)
  }

  /// Size and number of the cached answers, for the Settings page; creates nothing.
  public func cacheStats() -> (entries: Int, bytes: Int) {
    var entries = 0, bytes = 0
    for entry in LayoutFrames.directoryEntriesWithKind(directory) {
      guard let size = try? FileManager.default.attributesOfItem(atPath: "\(directory)/\(entry.name)")[.size] as? Int,
            entry.kind == .file || entry.kind == .link, size > 0 else { continue }
      entries += 1
      bytes += size
    }
    return (entries, bytes)
  }

  /// Empties the cache; the number of entries removed.
  public func clearCache() async -> Int {
    await catalog.invalidate()
    var removed = 0
    for entry in LayoutFrames.directoryEntriesWithKind(directory) where JSText.endsWith(entry.name, ".json") {
      if (try? FileManager.default.removeItem(atPath: "\(directory)/\(entry.name)")) != nil { removed += 1 }
    }
    return removed
  }

  /// One theme's answer forgotten: an emptied file reads as "not cached". Only for the tests, as
  /// `schema(themeId:)`.
  func clearCache(themeId: String) async throws {
    try Self.check(themeId)
    await catalog.invalidate()
    try? Posix.write("\(cacheDirectory())/\(themeId).json", Data())
  }
}
