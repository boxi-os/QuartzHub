import Foundation
import Synchronization

/// What a plugin package says about itself, read where quartz finds it: a port of QuartzControl's
/// pluginSchemaService.ts, measured against it with `scripts/option-schema-golden.mjs`
/// (PluginSchemaReaderTests).
///
/// - **Options:** `quartz.configSchema` → `quartz.optionSchema` → the `.d.ts` under `dist/` →
///   `quartz.defaultOptions` alone; the first that yields a field wins, and the defaults are laid
///   over it. Nothing here runs plugin code: package.json is parsed as JSON under a size cap, the
///   `.d.ts` by TypeScript's parser in the dts-schema helper.
/// - **The default frame of a page-type plugin** (`frame: "canvas"` beside `match` in its entry
///   file), which quartz uses when `layout.byPageType.<type>.template` is not set.
/// - **A theme's theme.json** (`@quartz-themes/<id>`): Style Settings ids and class keys, modes,
///   variations, fonts.
///
/// One helper call per page, not per plugin: the helper costs some 130 ms, mostly loading
/// typescript, and the plugin page asks for all plugins at once (`optionSchemas`, `pageTypeFrames`).
///
/// Deviations from QuartzControl:
/// - **The page-type cache follows the files.** QuartzControl kept a frame until the app restarted
///   (`invalidateBuiltinPageTypeFrameCache` had no caller); here the key holds size and mtime of
///   package.json and the entry file, as the option cache did already.
/// - **A `.d.ts` directory that cannot be read, or a helper that does not answer, is a sentence**
///   (`main.pluginSchemaTypesUnreadable`); in QuartzControl the first was an exception out of the
///   IPC handler. Not cached.
/// - **A package.json that cannot be read gives the reason in the system's words**
///   (`strerror`, or the JSON parser's message), not Node's (`EISDIR: illegal operation …`).
/// - **Values QuartzControl passed through unchecked are typed:** a theme's lists keep their
///   strings and drop the rest, `styleSettingsId: 5` is no id. Where QuartzControl threw a
///   TypeError (`category: 5`, `main: 5`, a package.json of `null`), there is no frame.
public final class PluginSchemaReader: Sendable {
  public static let shared = PluginSchemaReader()

  static let maxPackageJSONBytes = 1024 * 1024
  static let maxDtsFiles = 200

  private let optionCache = Mutex<[String: (fingerprint: String, result: PluginOptionSchemaResult)]>([:])
  private let frameCache = Mutex<[String: (fingerprint: String, frame: String?)]>([:])

  public init() {}

  // MARK: where the package is

  /// The plugin's package directory as quartz resolves it: npm sources under node_modules, all
  /// others under `.quartz/plugins/<quartzName>`. Nil if that would leave its base, or for an empty
  /// name. As Node's `path.relative`: a first segment that starts with ".." (a folder "..x") counts
  /// as leaving.
  public static func packageDirectory(project: URL, source: PluginSource) -> URL? {
    let name = source.quartzName
    let base = FramePaths.resolve(project.path + (source.isNpm ? "/node_modules" : "/.quartz/plugins"))
    let dir = FramePaths.resolve(name.hasPrefix("/") ? name : base + "/" + name)
    guard !name.isEmpty, dir.hasPrefix(base + "/") else { return nil }
    let relative = dir.dropFirst(base.count + 1)
    guard !relative.hasPrefix("..") else { return nil }
    return URL(fileURLWithPath: dir)
  }

  // MARK: options

  public func optionSchema(project: URL, source: PluginSource, runtime: RuntimeLocation = .current) async -> PluginOptionSchemaResult {
    await optionSchemas(project: project, sources: [source], runtime: runtime)[0]
  }

  /// One answer per source, in order; at most one helper call for all of them.
  public func optionSchemas(project: URL, sources: [PluginSource], runtime: RuntimeLocation = .current) async -> [PluginOptionSchemaResult] {
    enum Step {
      case done(PluginOptionSchemaResult)
      case types(dir: URL, fingerprint: String, read: PackageRead, helperIndex: Int?)
    }
    var steps: [Step] = []
    var distDirs: [String] = []
    for source in sources {
      guard let dir = Self.packageDirectory(project: project, source: source) else {
        steps.append(.done(PluginOptionSchemaResult(unreadable: L10n.t("main.pluginSchemaOutsideProject"))))
        continue
      }
      let fingerprint = Self.fingerprint(dir)
      if let cached = optionCache.withLock({ $0[dir.path] }), cached.fingerprint == fingerprint {
        steps.append(.done(cached.result))
        continue
      }
      switch Self.readPackage(dir) {
      case .answer(let result):
        store(dir, fingerprint, result)
        steps.append(.done(result))
      case .read(let read):
        if let schema = read.localSchema {
          let result = read.result(with: schema)
          store(dir, fingerprint, result)
          steps.append(.done(result))
          continue
        }
        // No dist, no .d.ts: the helper would answer null (indexDts); spare the process.
        let dist = dir.appendingPathComponent("dist")
        var helperIndex: Int?
        if FileManager.default.fileExists(atPath: dist.path) {
          helperIndex = distDirs.count
          distDirs.append(dist.path)
        }
        steps.append(.types(dir: dir, fingerprint: fingerprint, read: read, helperIndex: helperIndex))
      }
    }

    var answers: [JSONValue] = []
    var failure: String?
    if !distDirs.isEmpty {
      do {
        let answer = try await Helper.call("dts-schema", JSONObject([("dts", .array(distDirs.map(JSONValue.string)))]), runtime: runtime)
        answers = answer["dts"]?.arrayValue ?? []
        if answers.count != distDirs.count { failure = "dts-schema answered \(answers.count) of \(distDirs.count)" }
      } catch {
        failure = error.description
      }
    }

    return steps.map { step in
      switch step {
      case .done(let result):
        return result
      case .types(let dir, let fingerprint, let read, let helperIndex):
        var translated: JSONValue?
        if let helperIndex {
          if let failure { return PluginOptionSchemaResult(unreadable: L10n.t("main.pluginSchemaTypesUnreadable", ["reason": failure])) }
          let answer = answers[helperIndex]
          if let error = answer["error"]?.stringValue {
            return PluginOptionSchemaResult(unreadable: L10n.t("main.pluginSchemaTypesUnreadable", ["reason": error]))
          }
          translated = answer["schema"].flatMap { $0 == .null ? nil : $0 }
        }
        let fromTypes = translated.map { OptionSchema.normalize(jsonSchema: $0, source: .dts) }
        let result = read.result(with: fromTypes.flatMap { $0.fields.isEmpty ? nil : $0 })
        store(dir, fingerprint, result)
        return result
      }
    }
  }

  private func store(_ dir: URL, _ fingerprint: String, _ result: PluginOptionSchemaResult) {
    optionCache.withLock { $0[dir.path] = (fingerprint, result) }
  }

  /// What package.json says, before the `.d.ts` are asked.
  struct PackageRead {
    var quartz: JSONObject
    var version: String?
    var categories: [String]?

    /// configSchema, then optionSchema; nil when neither yields a field.
    var localSchema: NormalizedOptionSchema? {
      if let config = quartz["configSchema"] {
        let schema = OptionSchema.normalize(jsonSchema: config, source: .configSchema)
        if !schema.fields.isEmpty { return schema }
      }
      if let flat = quartz["optionSchema"] {
        let schema = OptionSchema.normalize(optionSchema: flat)
        if !schema.fields.isEmpty { return schema }
      }
      return nil
    }

    /// The winner with the defaults laid over it, or the defaults alone.
    func result(with schema: NormalizedOptionSchema?) -> PluginOptionSchemaResult {
      let defaults = quartz["defaultOptions"]
      let final = schema.map { OptionSchema.applyDefaults($0, defaults) } ?? OptionSchema.fromDefaults(defaults)
      return PluginOptionSchemaResult(schema: final, packageVersion: version, categories: categories)
    }
  }

  enum PackageOutcome {
    case answer(PluginOptionSchemaResult)
    case read(PackageRead)
  }

  static func readPackage(_ dir: URL) -> PackageOutcome {
    let path = dir.appendingPathComponent("package.json").path
    var info = stat()
    guard stat(path, &info) == 0 else {
      // Not installed (yet) is the ordinary case for a plugin that was just added: no schema, no
      // complaint. Anything else is a package that is there and broken, and says so.
      if errno == ENOENT { return .answer(PluginOptionSchemaResult()) }
      return .answer(unreadable(String(cString: strerror(errno))))
    }
    if info.st_size > maxPackageJSONBytes {
      return .answer(PluginOptionSchemaResult(unreadable: L10n.t("main.pluginSchemaPackageTooLarge", ["size": String(info.st_size)])))
    }
    let value: JSONValue
    do {
      value = try JSJSON.parse(try readFile(path))
    } catch let error as JSJSON.ParseError {
      return .answer(unreadable(error.description))
    } catch {
      return .answer(unreadable("\(error)"))
    }
    guard case .object(let package) = value else {
      return .answer(PluginOptionSchemaResult(unreadable: L10n.t("main.pluginSchemaPackageNotObject")))
    }
    let quartz = package["quartz"]?.objectValue ?? JSONObject()
    let version = quartz["version"]?.stringValue ?? package["version"]?.stringValue
    // A string or a list in the wild; quartz itself reads both.
    let listed: [JSONValue] = if case .array(let list)? = quartz["category"] { list } else { [quartz["category"] ?? .null] }
    let categories = listed.compactMap(\.stringValue)
    return .read(PackageRead(quartz: quartz, version: version, categories: categories.isEmpty ? nil : categories))
  }

  private static func unreadable(_ reason: String) -> PluginOptionSchemaResult {
    PluginOptionSchemaResult(unreadable: L10n.t("main.pluginSchemaPackageUnreadable", ["reason": reason]))
  }

  struct ReadError: Error, CustomStringConvertible {
    let code: Int32
    var description: String { String(cString: strerror(code)) }
  }

  /// The whole file, with the system's reason when it fails (a directory opens on macOS and fails
  /// at the first read with EISDIR).
  static func readFile(_ path: String) throws -> Data {
    let fd = open(path, O_RDONLY | O_CLOEXEC)
    guard fd >= 0 else { throw ReadError(code: errno) }
    defer { close(fd) }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = read(fd, &buffer, buffer.count)
      if count < 0 { throw ReadError(code: errno) }
      if count == 0 { return data }
      data.append(buffer, count: count)
    }
  }

  // MARK: the cache key

  /// Size and mtime of package.json and of every `.d.ts` under dist/: what the answer depends on.
  /// QuartzControl's old cache was keyed by name only, and after `quartz plugin update` the page
  /// kept the previous version's options until the app restarted.
  static func fingerprint(_ dir: URL) -> String {
    var parts = [stamp(dir.appendingPathComponent("package.json").path)]
    let dist = dir.appendingPathComponent("dist").path
    if FileManager.default.fileExists(atPath: dist) {
      do {
        parts += try dtsFiles(dist).prefix(maxDtsFiles).map(stamp)
      } catch {
        parts.append("dist:unreadable")
      }
    }
    return parts.joined(separator: "|")
  }

  static func stamp(_ path: String) -> String {
    var info = stat()
    guard stat(path, &info) == 0 else { return "\(path):-" }
    return "\(path):\(info.st_size):\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
  }

  /// `walkFiles(dist, '.d.ts')`: through links (stat), past node_modules, in byte order as Node's
  /// readdir gives it. Deeper than 40 is a loop of links, which in Node ended in ELOOP.
  static func dtsFiles(_ dir: String, depth: Int = 0) throws -> [String] {
    struct TooDeep: Error {}
    guard depth <= 40 else { throw TooDeep() }
    var out: [String] = []
    let names = try FileManager.default.contentsOfDirectory(atPath: dir).sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
    for name in names where name != "node_modules" {
      let full = dir + "/" + name
      var info = stat()
      guard stat(full, &info) == 0 else { throw ReadError(code: errno) }
      if info.st_mode & S_IFMT == S_IFDIR {
        out += try dtsFiles(full, depth: depth + 1)
      } else if name.hasSuffix(".d.ts") {
        out.append(full)
      }
    }
    return out
  }

  // MARK: the default frame of a page-type plugin

  /// For the layout board: which of these plugins are built-in page types with a frame of their
  /// own, keyed by the name the caller gives (QuartzControl's renderer passed the display name).
  /// Only string sources count, and only packages under node_modules, as in QuartzControl.
  public func pageTypeFrames(project: URL, plugins: [(name: String, source: JSONValue?)], runtime: RuntimeLocation = .current) async -> [String: String] {
    var known: [String: String?] = [:]
    var parse: [(key: String, source: String, fingerprint: String, file: String)] = []
    for case (_, .string(let source)?) in plugins where known[source] == nil && !parse.contains(where: { $0.source == source }) {
      let key = "\(project.path)::\(source)"
      let lookup = Self.pageTypeEntry(project: project, source: source)
      if let cached = frameCache.withLock({ $0[key] }), cached.fingerprint == lookup.fingerprint {
        known[source] = .some(cached.frame)
      } else if let file = lookup.entry {
        parse.append((key, source, lookup.fingerprint, file))
      } else {
        frameCache.withLock { $0[key] = (lookup.fingerprint, nil) }
        known[source] = .some(nil)
      }
    }
    if !parse.isEmpty, let answer = try? await Helper.call("dts-schema", JSONObject([("frames", .array(parse.map { .string($0.file) }))]), runtime: runtime),
       let frames = answer["frames"]?.arrayValue, frames.count == parse.count {
      for (item, frame) in zip(parse, frames) where frame["error"] == nil {
        let name = frame["frame"]?.stringValue
        frameCache.withLock { $0[item.key] = (item.fingerprint, name) }
        known[item.source] = .some(name)
      }
    }
    var result: [String: String] = [:]
    for case (let name, .string(let source)?) in plugins {
      if case .some(.some(let frame)) = known[source] { result[name] = frame }
    }
    return result
  }

  /// The entry file to parse, or nil when the package is no page type or has no entry; and the key
  /// the answer depends on.
  static func pageTypeEntry(project: URL, source: String) -> (entry: String?, fingerprint: String) {
    let packageDir = FramePaths.resolve(project.path + "/node_modules/" + source)
    let packageJSON = packageDir + "/package.json"
    var fingerprint = stamp(packageJSON)
    guard FileManager.default.fileExists(atPath: packageJSON),
          case .object(let package)? = try? JSJSON.parse(try readFile(packageJSON)),
          isPageType(package["quartz"]),
          let relative = entryPath(package) else { return (nil, fingerprint) }
    let entry = FramePaths.resolve(packageDir + "/" + relative)
    fingerprint += "|" + stamp(entry)
    return (FileManager.default.fileExists(atPath: entry) ? entry : nil, fingerprint)
  }

  /// `pkg.quartz?.category?.includes('pageType')`: a list holds it, a string contains it.
  static func isPageType(_ quartz: JSONValue?) -> Bool {
    switch quartz?.objectValue?["category"] {
    case .array(let list)?: list.contains(.string("pageType"))
    case .string(let text)?: text.contains("pageType")
    default: false
    }
  }

  /// `exports["."]` as a string or its `import`, else `main`.
  static func entryPath(_ package: JSONObject) -> String? {
    var importPath: String?
    switch package["exports"]?.objectValue?["."] {
    case .string(let path)?:
      importPath = path
    case .object(let conditions)?:
      switch conditions["import"] {
      case .string(let path)?: importPath = path
      case nil, .null?: break
      default: return nil
      }
    default:
      break
    }
    if let importPath { return importPath.isEmpty ? nil : importPath }
    switch package["main"] {
    case .string(let main)?: return main.isEmpty ? nil : main
    default: return nil
    }
  }

  // MARK: themes

  /// The Obsidian Style Settings ids a ported theme declared, and its class keys (there is no
  /// title or type next to them, so a form can only offer switches). Nil when the theme is not
  /// installed or its theme.json cannot be read.
  public static func themeStyleSettings(project: URL, themeId: String) -> ThemeStyleSettingsInfo? {
    guard let theme = themeJSON(project: project, themeId: themeId) else { return nil }
    let ids = styleSettingsIds(theme)
    guard !ids.isEmpty else { return ThemeStyleSettingsInfo(styleSettingsId: [], classSettingKeys: []) }
    let keys: [String] = switch theme.objectValue?["classSettings"] {
    case .object(let object)?: object.keys
    case .array(let list)?: list.indices.map(String.init)
    case .string(let text)?: Array(0..<text.utf16.count).map(String.init)
    default: []
    }
    return ThemeStyleSettingsInfo(styleSettingsId: ids, classSettingKeys: keys)
  }

  /// The fuller shape for the theme catalog's detail panel; local only.
  public static func localThemeDetail(project: URL, themeId: String) -> ThemeDetail? {
    guard let theme = themeJSON(project: project, themeId: themeId) else { return nil }
    let meta = theme.objectValue?["meta"]?.objectValue
    let strings = { (key: String) in meta?[key]?.arrayValue?.compactMap(\.stringValue) ?? [] }
    return ThemeDetail(modes: strings("modes"), variations: strings("variations"), styleSettingsId: styleSettingsIds(theme), fonts: strings("fonts"))
  }

  static func styleSettingsIds(_ theme: JSONValue) -> [String] {
    switch theme.objectValue?["meta"]?.objectValue?["styleSettingsId"] {
    case .array(let list)?: list.compactMap(\.stringValue)
    case .string(let id)?: [id]
    default: []
    }
  }

  /// `node_modules/@quartz-themes/<id>/theme.json`; nil for an id QuartzControl's channel refused
  /// (`^[a-z0-9][a-z0-9._-]*$`, at most 128), a file that is not there or not JSON, and a JSON
  /// value JavaScript calls falsy.
  static func themeJSON(project: URL, themeId: String) -> JSONValue? {
    guard themeId.utf16.count <= 128, themeId.wholeMatch(of: themeIdPattern) != nil else { return nil }
    let path = project.appendingPathComponent("node_modules/@quartz-themes/\(themeId)/theme.json").path
    guard FileManager.default.fileExists(atPath: path), let value = try? JSJSON.parse(try readFile(path)), JS.truthy(value) else { return nil }
    return value
  }

  nonisolated(unsafe) static let themeIdPattern = #/[a-z0-9][a-z0-9._-]*/#.matchingSemantics(.unicodeScalar)
}

/// What QuartzHub answers for one plugin.
public struct PluginOptionSchemaResult: Equatable, Sendable {
  /// nil: the plugin describes no options anywhere (or its package is not installed).
  public var schema: NormalizedOptionSchema?
  /// `quartz.version ?? version` of the package the schema was read from, as quartz reads it.
  public var packageVersion: String?
  /// Set when the package is there but could not be read: a reason, not a schema.
  public var unreadable: String?
  /// `quartz.category` as a list ("component", "transformer", "emitter", …): switching a
  /// component off with `enabled: false` switches off the whole plugin.
  public var categories: [String]?

  public init(schema: NormalizedOptionSchema? = nil, packageVersion: String? = nil, unreadable: String? = nil, categories: [String]? = nil) {
    self.schema = schema
    self.packageVersion = packageVersion
    self.unreadable = unreadable
    self.categories = categories
  }

  /// scripts/lib/option-schema-canon.mjs, `canonResult`.
  var canonicalJSON: JSONValue {
    var o = JSONObject([("schema", schema?.canonicalJSON ?? .null)])
    if let packageVersion { o["packageVersion"] = .string(packageVersion) }
    if let unreadable { o["unreadable"] = .string(unreadable) }
    if let categories { o["categories"] = .array(categories.map(JSONValue.string)) }
    return .object(o)
  }
}

public struct ThemeStyleSettingsInfo: Equatable, Sendable {
  public var styleSettingsId: [String]
  public var classSettingKeys: [String]
}

public struct ThemeDetail: Equatable, Sendable {
  public var modes: [String]
  public var variations: [String]
  public var styleSettingsId: [String]
  public var fonts: [String]
}
