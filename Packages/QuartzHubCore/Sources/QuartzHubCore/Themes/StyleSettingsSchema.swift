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
/// disk gone is kept as "none" until then.)
public actor StyleSettingsSchema {
  static let registryURL = "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/community-css-themes.json"
  static let registryLifetime: TimeInterval = 24 * 60 * 60
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
  let directory: URL
  let readYaml: ReadYaml
  let now: @Sendable () -> Date
  private var registry: (at: Date, entries: [JSONValue])?

  public init(profile: ProfileDirectory = .quartzHub, configuration: URLSessionConfiguration = .ephemeral, timeout: Duration = .seconds(45),
              readYaml: @escaping ReadYaml = StyleSettingsSchema.helperYaml(runtime: .current), now: @escaping @Sendable () -> Date = Date.init) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let seconds = Double(timeout.components.seconds)
    configuration.timeoutIntervalForRequest = seconds
    configuration.timeoutIntervalForResource = seconds
    session = URLSession(configuration: configuration)
    directory = URL(fileURLWithPath: profile.file("theme-docs"))
    self.readYaml = readYaml
    self.now = now
  }

  public struct InvalidThemeId: Error, Equatable { public let id: String }

  /// The ids QuartzControl's schema let through: they become file names here.
  static func check(_ themeId: String) throws {
    guard (1...128).contains(JSText.length(themeId)), JSText.test(themeId, #"\A[a-z0-9][a-z0-9._-]*\z"#) else { throw InvalidThemeId(id: themeId) }
  }

  func cacheDirectory() -> URL {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

  /// The registry, a day in memory; offline is a normal state, so the copy on disk answers then.
  func loadRegistry() async -> [JSONValue] {
    if let registry, now().timeIntervalSince(registry.at) < Self.registryLifetime { return registry.entries }
    let copy = cacheDirectory().appendingPathComponent("community-css-themes.json")
    if let answer = await get(Self.registryURL), (200..<300).contains(answer.status),
       case .array(let entries)? = try? JSJSON.parse(answer.body), !entries.isEmpty {
      registry = (now(), entries)
      try? JSONStore.writeAtomic(Data(JSJSON.compact(.array(entries)).utf8), to: copy)
      return entries
    }
    if let data = try? Data(contentsOf: copy), case .array(let entries)? = try? JSJSON.parse(data) {
      registry = (now(), entries)
      return entries
    }
    return []
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
  public func schema(themeId: String) async throws -> JSONValue {
    try Self.check(themeId)
    let file = cacheDirectory().appendingPathComponent("\(themeId).json")
    if let data = try? Data(contentsOf: file), let cached = try? JSJSON.parse(data) { return cached }
    let schema = await build(themeId)
    try? JSONStore.writeAtomic(Data(JSJSON.compact(schema).utf8), to: file)
    return schema
  }

  func build(_ themeId: String) async -> JSONValue {
    // A port's variation suffix ("catppuccin.frappe") names the same upstream theme.
    let wanted = JSText.split(themeId, ".")[0]
    guard let entry = await loadRegistry().first(where: { Self.slugify(JS.string($0[safe: "name"])) == wanted }),
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

  /// Size and number of the cached answers, for the Settings page; creates nothing.
  public func cacheStats() -> (entries: Int, bytes: Int) {
    var entries = 0, bytes = 0
    for entry in LayoutFrames.directoryEntriesWithKind(directory) {
      guard let size = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(entry.name).path)[.size] as? Int,
            entry.kind == .file || entry.kind == .link, size > 0 else { continue }
      entries += 1
      bytes += size
    }
    return (entries, bytes)
  }

  /// Empties the cache; the number of entries removed.
  public func clearCache() -> Int {
    registry = nil
    var removed = 0
    for entry in LayoutFrames.directoryEntriesWithKind(directory) where JSText.endsWith(entry.name, ".json") {
      if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.name))) != nil { removed += 1 }
    }
    return removed
  }

  /// One theme's answer forgotten: an emptied file reads as "not cached".
  public func clearCache(themeId: String) throws {
    try Self.check(themeId)
    registry = nil
    try? Data().write(to: cacheDirectory().appendingPathComponent("\(themeId).json"))
  }
}
