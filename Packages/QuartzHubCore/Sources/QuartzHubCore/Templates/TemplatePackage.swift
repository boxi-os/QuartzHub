import Foundation

/// QuartzControl's `templatePackage/` (index.ts, parts.ts, shared.ts): a template package
/// (`.qtpl`) is one ZIP holding `manifest.json`, one `parts/<id>.json` per slice and the files
/// under `files/`. Twelve parts, each in three phases: read the project (`collect`), say what an
/// import would do (`plan`), do it (`apply`).
///
/// A package is no trust boundary: every name a payload lists goes through
/// `PackagePaths.writable`, in `plan` as in `apply`, and the ZIP reader refuses unsafe entry names.
///
/// The import takes a snapshot first, as the way back; one that fails stops it before it writes.
/// The manifest says who wrote it: here "QuartzHub".
public struct TemplatePackage: Sendable {
  public enum Strategy: String, Sendable { case packageWins, projectWins }
  public enum TranslationScope: String, Sendable { case changed, all }

  /// `createSnapshot(project, kind, label)`.
  public typealias Snapshot = @Sendable (_ project: URL, _ kind: String, _ label: String) async throws -> Void
  /// `npm <arguments>` in the project.
  public typealias Npm = @Sendable (_ arguments: [String], _ project: URL) async -> PluginCommands.Result
  /// `quartz plugin add <source>` without a snapshot (`installPluginSource`).
  public typealias AddPlugin = @Sendable (_ source: String, _ project: URL) async -> PluginCommands.Result
  /// `git rev-parse --short HEAD`, trimmed; nil where it fails.
  public typealias Head = @Sendable (_ project: URL) async -> String?
  public typealias Progress = @Sendable (_ partId: String, _ message: String, _ done: Int, _ total: Int) -> Void

  /// Export order is import order: frames and plugins go through the Quartz CLI before the parts
  /// that write the config from a copy, the three that share custom.scss run late, the notes last.
  public static let partIds = ["frames", "theme", "plugins", "appearance", "layout", "presets", "translations", "styles", "fonts", "static",
                               "cssVariables", "content"]
  static let manifestFile = "manifest.json"
  static let formatVersion = 1
  static func partFile(_ id: String) -> String { "parts/\(id).json" }

  let runtime: RuntimeLocation
  let locales: LocaleFiles
  let frames: LayoutFrames
  let fonts: FontService
  let npm: Npm
  let addPlugin: AddPlugin
  let head: Head
  let snapshot: Snapshot
  let app: (name: String, version: String)
  let now: @Sendable () -> Date

  public init(runtime: RuntimeLocation = .current, locales: LocaleFiles, frames: LayoutFrames, fonts: FontService, npm: @escaping Npm,
              addPlugin: @escaping AddPlugin, head: @escaping Head, snapshot: @escaping Snapshot,
              app: (name: String, version: String), now: @escaping @Sendable () -> Date = { Date() }) {
    self.runtime = runtime
    self.locales = locales
    self.frames = frames
    self.fonts = fonts
    self.npm = npm
    self.addPlugin = addPlugin
    self.head = head
    self.snapshot = snapshot
    self.app = app
    self.now = now
  }

  /// The commands of a real environment: npm with its 20-minute deadline, `quartz plugin add`
  /// through the CLI, git for the source's commit, the project's snapshot store.
  public static func live(environment: ToolEnvironment, locales: LocaleFiles, frames: LayoutFrames, fonts: FontService,
                          snapshots: SnapshotStore, appVersion: String) -> TemplatePackage {
    TemplatePackage(
      runtime: environment.runtime, locales: locales, frames: frames, fonts: fonts,
      npm: { arguments, project in
        let result = await ProcessRunner.run(environment.command("npm", arguments, in: project, timeout: .seconds(20 * 60)))
        return PluginCommands.Result(success: result.success, output: result.output)
      },
      addPlugin: { source, project in await PluginCommands.shared.add(source: source, project: project.path, environment: environment) },
      head: { project in
        let result = await ProcessRunner.run(environment.command("git", ["rev-parse", "--short", "HEAD"], in: project, timeout: .seconds(30)))
        return result.success ? JS.trim(result.output) : nil
      },
      snapshot: { project, kind, label in _ = try await snapshots.create(project: project, kind: kind, label: label) },
      app: ("QuartzHub", appVersion))
  }

  // MARK: - Results

  public struct Dependency: Equatable, Sendable {
    public var name: String
    /// What was installed at export time; informational, the import installs by name.
    public var version: JSONValue?
    var json: JSONValue { .object(JSONObject([("name", .string(name))] + (version.map { [("version", $0)] } ?? []))) }
  }

  public struct Summary: Equatable, Sendable {
    public var id: String
    public var stats: JSONObject
    public var requires: [Dependency]
    var json: JSONValue { .object(JSONObject([("id", .string(id)), ("stats", .object(stats)), ("requires", .array(requires.map(\.json)))])) }
  }

  /// What one part would do to this project: `conflicts` is what exists and would be replaced
  /// (`packageWins`) or kept (`projectWins`); the strategy flips its meaning, not its contents.
  public struct PartPlan: Equatable, Sendable {
    public var id: String
    public var additions: [JSONValue] = []
    public var conflicts: [JSONValue] = []
    public var missingPackages: [Dependency] = []
    public var notes: [String] = []
    var json: JSONValue {
      .object(JSONObject([("id", .string(id)), ("additions", .array(additions)), ("conflicts", .array(conflicts)),
                          ("missingPackages", .array(missingPackages.map(\.json))), ("notes", .array(notes.map(JSONValue.string)))]))
    }
  }

  public struct Plan: Equatable, Sendable {
    public var manifest: JSONValue
    public var parts: [PartPlan]
    /// Part ids this version cannot read (a newer app's, or a payload that does not parse).
    public var unknownParts: [JSONValue]
    public var legacy: Bool
  }

  public struct Exported: Equatable, Sendable {
    public var file: URL
    public var bytes: Int
    public var parts: [Summary]
  }

  public struct Imported: Equatable, Sendable {
    public var success: Bool
    public var warnings: [String]
  }

  // MARK: - Names

  /// The save dialog's suggestion; the manifest keeps every character of the name.
  public static func slugifyFileName(_ name: String) -> String {
    let slug = JSText.replaceAll(JSText.replaceAll(JS.trim(name).lowercased(), "[^a-z0-9]+", with: "-"), #"\A-+|-+\z"#, with: "")
    return slug.isEmpty ? "vorlage" : slug
  }

  // MARK: - Export

  /// What every part would bring from this project, for the export form's counts. A part that
  /// fails is left out, as there.
  public func inspect(project: URL) async -> [Summary] {
    var out: [Summary] = []
    for id in Self.partIds {
      if id == "translations" {
        guard let stats = try? await probeTranslations(project) else { continue }
        if stats.keys.contains(where: { (stats[$0]?.numberValue ?? 0) > 0 }) { out.append(Summary(id: id, stats: stats, requires: [])) }
        continue
      }
      if let collected = try? await collect(id, project, scope: .changed) { out.append(Summary(id: id, stats: collected.stats, requires: collected.requires)) }
    }
    return out
  }

  public func export(project: URL, to file: URL, name: String, description: String? = nil, parts: [String], scope: TranslationScope) async throws -> Exported {
    var entries: [ZipArchive.Entry] = []
    var summaries: [Summary] = []
    for id in Self.partIds where parts.contains(id) {
      guard let collected = try await collect(id, project, scope: scope) else { continue }
      entries.append(ZipArchive.Entry(name: Self.partFile(id), data: Data(JSJSON.stringify(collected.payload).utf8)))
      entries += collected.files
      summaries.append(Summary(id: id, stats: collected.stats, requires: collected.requires))
    }
    var source = JSONObject([("projectName", .string(NodePath.basename(project.path)))])
    if let head = await head(project) { source["quartzHead"] = .string(head) }
    var manifest = JSONObject([("formatVersion", .number(Double(Self.formatVersion))), ("name", .string(name))])
    if let description, !description.isEmpty { manifest["description"] = .string(description) }
    manifest["createdAt"] = .string(Self.isoDate(now()))
    manifest["createdBy"] = .object(JSONObject([("app", .string(app.name)), ("appVersion", .string(app.version))]))
    manifest["source"] = .object(source)
    manifest["parts"] = .array(summaries.map(\.json))
    entries.insert(ZipArchive.Entry(name: Self.manifestFile, data: Data(JSJSON.stringify(.object(manifest)).utf8)), at: 0)
    try ZipArchive.write(entries, to: file)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
    return Exported(file: file, bytes: bytes, parts: summaries)
  }

  /// `Date.toISOString()`: milliseconds, UTC, "Z".
  static func isoDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  // MARK: - Reading a package

  struct Loaded {
    var manifest: JSONValue
    var files: ZipArchive.Files
    var legacy: Bool
  }

  /// nil for no file, and for a file without a readable manifest; a ZIP the reader refuses throws
  /// its own sentence (the only place that knows what is wrong).
  func load(_ path: URL) throws -> Loaded? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else { return nil }
    if isDirectory.boolValue { return try loadLegacyFolder(path) }
    let files = try ZipArchive.read(contentsOf: path)
    guard let raw = files[Self.manifestFile], let manifest = try? JSJSON.parse(raw) else { return nil }
    return Loaded(manifest: manifest, files: files, legacy: false)
  }

  func payload(_ loaded: Loaded, _ id: String) -> JSONValue? {
    guard let raw = loaded.files[Self.partFile(id)], let value = try? JSJSON.parse(raw), value != .null else { return nil }
    return value
  }

  /// A package of the format before 1: a folder with fixed files and six categories. Read, never
  /// written. Its `plugins.json` held the theme and the frames' entries too; the frames' carry
  /// absolute paths of the machine that wrote them and are dropped (the frames part registers anew).
  func loadLegacyFolder(_ dir: URL) throws -> Loaded? {
    guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent(Self.manifestFile).path),
          let old = try? JSJSON.parse(data), old["categories"]?.arrayValue != nil else { return nil }
    var files = ZipArchive.Files()
    var parts: [JSONValue] = []
    func put(_ id: String, _ payload: JSONValue, _ stats: JSONObject) {
      files.set(Self.partFile(id), Data(JSJSON.compact(payload).utf8))
      parts.append(Summary(id: id, stats: stats, requires: []).json)
    }
    func readJson(_ name: String) -> JSONValue? {
      guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent(name).path), let value = try? JSJSON.parse(data) else { return nil }
      return value
    }

    let layout = readJson("layout.json")
    if JS.truthy(layout) {
      let defaults = FrameBreakpointWidths.defaults
      put("layout", .object(JSONObject([("layout", layout!), ("breakpoints", .object(JSONObject([("tablet", .number(defaults.tablet)), ("mobile", .number(defaults.mobile))])))])),
          JSONObject([("groups", .number(0)), ("pageTypes", .number(0))]))
    }
    let colors = readJson("colors.json")
    if JS.truthy(colors), let colors {
      var appearance = JSONObject([("colors", Self.orEmptyObject(colors["colors"])), ("typography", Self.orEmptyObject(colors["typography"]))])
      if let origin = colors["fontOrigin"] { appearance["fontOrigin"] = origin }
      put("appearance", .object(appearance), JSONObject())
      let overrides = colors["cssVariableOverrides"]?.arrayValue ?? []
      if !overrides.isEmpty { put("cssVariables", .object(JSONObject([("overrides", .array(overrides))])), JSONObject([("variables", .number(Double(overrides.count)))])) }
    }
    let frameList = readJson("frames.json")?.arrayValue
    if let frameList, !frameList.isEmpty { put("frames", .object(JSONObject([("frames", .array(frameList))])), JSONObject([("frames", .number(Double(frameList.count)))])) }
    if let entries = readJson("plugins.json")?.arrayValue {
      let frameIds = Set((frameList ?? []).compactMap { $0["id"]?.stringValue })
      let themeIndex = entries.firstIndex { $0["source"]?.stringValue.map { $0.hasPrefix("@quartz-themes/") } ?? false }
      let rest = entries.enumerated().filter { index, entry in
        guard index != themeIndex else { return false }
        let name = entry["name"]?.stringValue ?? ""
        return !(frameIds.contains(name) && (entry["source"]?.stringValue.map { JSText.includes($0, "authored-frames") } ?? false))
      }.map(\.element)
      if let themeIndex {
        let entry = entries[themeIndex]
        put("theme", .object(JSONObject([("entry", entry), ("themeId", entry["options"]?["theme"] ?? .null)])), JSONObject())
      }
      if !rest.isEmpty { put("plugins", .object(JSONObject([("entries", .array(rest))])), JSONObject([("plugins", .number(Double(rest.count)))])) }
    }
    let scss = dir.appendingPathComponent("custom.scss")
    if FileManager.default.fileExists(atPath: scss.path) {
      let imported = Self.listFilesFlat(dir.appendingPathComponent("imported"))
      for name in imported { files.set("files/styles/imported/\(name)", try Data(contentsOf: dir.appendingPathComponent("imported").appendingPathComponent(name))) }
      let relative = imported.map { JSONValue.string("imported/\($0)") }
      put("styles", .object(JSONObject([("customScss", .string(try LocaleFiles.readText(scss))), ("order", .array(relative)), ("files", .array(relative))])),
          JSONObject([("files", .number(Double(relative.count)))]))
    }
    let fontNames = Self.listFilesFlat(dir.appendingPathComponent("fonts"))
    if !fontNames.isEmpty {
      for name in fontNames { files.set("files/fonts/\(name)", try Data(contentsOf: dir.appendingPathComponent("fonts").appendingPathComponent(name))) }
      put("fonts", .object(JSONObject([("fontFaceCss", .null), ("files", .array(fontNames.map(JSONValue.string)))])), JSONObject([("files", .number(Double(fontNames.count)))]))
    }
    let manifest = JSONObject([
      ("formatVersion", .number(0)), ("name", old["name"] ?? .string(NodePath.basename(dir.path))),
      ("createdAt", old["createdAt"] ?? .string("1970-01-01T00:00:00.000Z")),
      ("createdBy", .object(JSONObject([("app", .string("QuartzControl")), ("appVersion", .string(""))]))),
      ("source", .object(JSONObject())), ("parts", .array(parts))
    ])
    return Loaded(manifest: .object(manifest), files: files, legacy: true)
  }

  // MARK: - Dry run and import

  /// A real dry run: both the package and the project read, per part what would be added and what
  /// exists already, before anything is written. A part whose plan fails is "unknown", not fatal.
  public func plan(project: URL, package path: URL) async throws -> Plan? {
    guard let loaded = try load(path) else { return nil }
    var parts: [PartPlan] = []
    var unknown: [JSONValue] = []
    for summary in loaded.manifest["parts"]?.arrayValue ?? [] {
      let rawId = summary["id"] ?? .null
      guard let id = rawId.stringValue, Self.partIds.contains(id), let payload = payload(loaded, id) else {
        unknown.append(rawId)
        continue
      }
      let run = Run(project: project, strategy: .packageWins, files: loaded.files)
      do {
        var plan = try await planPart(id, payload, run)
        plan.id = id
        parts.append(plan)
      } catch {
        unknown.append(rawId)
      }
    }
    return Plan(manifest: loaded.manifest, parts: parts, unknownParts: unknown, legacy: loaded.legacy)
  }

  public func importPackage(project: URL, package path: URL, parts selected: [String], strategy: Strategy,
                            progress: Progress? = nil) async throws -> Imported {
    guard let loaded = try load(path) else { return Imported(success: false, warnings: ["packageUnreadable"]) }
    // The most far-reaching thing the app does to a project, and what a snapshot is for.
    try await snapshot(project, "styleChange", loaded.manifest["name"]?.stringValue ?? "")
    let run = Run(project: project, strategy: strategy, files: loaded.files)
    let todo = Self.partIds.filter { selected.contains($0) && loaded.files[Self.partFile($0)] != nil }
    var done = 0
    for id in todo {
      guard let payload = payload(loaded, id) else {
        run.warn("partUnreadable:\(id)")
        done += 1
        continue
      }
      progress?(id, "", done, todo.count)
      run.progress = { [done] message in progress?(id, message, done, todo.count) }
      do {
        // The three that share custom.scss, one at a time under the stylesheets' lock.
        if ["styles", "fonts", "cssVariables"].contains(id) {
          try await ProjectLock.styles.run(project.path) { try await applyPart(id, payload, run) }
        } else {
          try await applyPart(id, payload, run)
        }
      } catch {
        run.warn("partFailed:\(id):\(Self.message(error))")
      }
      done += 1
      progress?(id, "", done, todo.count)
    }
    return Imported(success: true, warnings: run.warnings)
  }

  /// `err.message`: the sentence without the "Error: " a description starts with.
  static func message(_ error: Error) -> String {
    let text = String(describing: error)
    for prefix in ["Error: ", "TypeError: "] where text.hasPrefix(prefix) { return String(text.dropFirst(prefix.count)) }
    return text
  }

  /// One import's warnings and progress; the parts run one after another.
  final class Run: @unchecked Sendable {
    let project: URL
    let strategy: Strategy
    let files: ZipArchive.Files
    var warnings: [String] = []
    var progress: (String) -> Void = { _ in }

    init(project: URL, strategy: Strategy, files: ZipArchive.Files) {
      self.project = project
      self.strategy = strategy
      self.files = files
    }

    func warn(_ message: String) { warnings.append(message) }
  }

  struct Collected {
    var payload: JSONValue
    var files: [ZipArchive.Entry] = []
    var stats: JSONObject
    var requires: [Dependency] = []
  }

  func collect(_ id: String, _ project: URL, scope: TranslationScope) async throws -> Collected? {
    switch id {
    case "appearance": try await collectAppearance(project)
    case "cssVariables": try collectVariables(project)
    case "theme": try await collectTheme(project)
    case "styles": try collectStyles(project)
    case "fonts": try collectFonts(project)
    case "static": try collectStatic(project)
    case "layout": try await collectLayout(project)
    case "frames": collectFrames(project)
    case "plugins": try await collectPlugins(project)
    case "translations": try await collectTranslations(project, scope)
    case "presets": collectPresets(project)
    case "content": try collectContent(project)
    default: nil
    }
  }

  func planPart(_ id: String, _ payload: JSONValue, _ run: Run) async throws -> PartPlan {
    switch id {
    case "appearance": try await planAppearance(payload, run)
    case "cssVariables": try planVariables(payload, run)
    case "theme": try await planTheme(payload, run)
    case "styles": try planStyles(payload, run)
    case "fonts": try planFonts(payload, run)
    case "static": try planStatic(payload, run)
    case "layout": try await planLayout(payload, run)
    case "frames": try planFrames(payload, run)
    case "plugins": try await planPlugins(payload, run)
    case "translations": try await planTranslations(payload, run)
    case "presets": try planPresets(payload, run)
    case "content": try await planContent(payload, run)
    default: PartPlan(id: id)
    }
  }

  func applyPart(_ id: String, _ payload: JSONValue, _ run: Run) async throws {
    switch id {
    case "appearance": try await applyAppearance(payload, run)
    case "cssVariables": try await applyVariables(payload, run)
    case "theme": try await applyTheme(payload, run)
    case "styles": try applyStyles(payload, run)
    case "fonts": try await applyFonts(payload, run)
    case "static": try applyStatic(payload, run)
    case "layout": try await applyLayout(payload, run)
    case "frames": try await applyFrames(payload, run)
    case "plugins": try await applyPlugins(payload, run)
    case "translations": try await applyTranslations(payload, run)
    case "presets": try applyPresets(payload, run)
    case "content": try applyContent(payload, run)
    default: break
    }
  }

  // MARK: - Helpers shared by the parts

  /// `for (const x of payload.key)`: a TypeError where the value is not a list.
  static func list(_ value: JSONValue?, _ name: String) throws -> [JSONValue] {
    guard let items = value?.arrayValue else { throw JS.TypeError("payload.\(name) is not iterable") }
    return items
  }

  /// The names of a payload list; a name that is no string fails as `path.resolve` would.
  static func names(_ value: JSONValue?, _ name: String) throws -> [String] {
    try list(value, name).map { item in
      guard let text = item.stringValue else { throw JS.TypeError("The \"paths[1]\" argument must be of type string. Received \(JSJSON.compact(item))") }
      return text
    }
  }

  static func orEmptyObject(_ value: JSONValue?) -> JSONValue {
    guard let value, value != .null else { return .object(JSONObject()) }
    return value
  }

  /// `JSON.stringify` for a comparison, with `undefined` for what is not there.
  static func stringified(_ value: JSONValue?) -> String { value.map(JSJSON.compact) ?? "undefined" }

  func readConfig(_ project: URL) async throws -> QuartzConfig { try await ConfigFile.read(project: project, runtime: runtime) }
  func writeConfig(_ config: QuartzConfig, _ project: URL) async throws { try await ConfigFile.write(config, project: project, runtime: runtime) }

  static func hasNodeModule(_ project: URL, _ name: String) -> Bool {
    FileManager.default.fileExists(atPath: NodePath.join(project.path, "node_modules", name, "package.json"))
  }

  static func installedVersion(_ project: URL, _ name: String) -> JSONValue? {
    guard let data = FileManager.default.contents(atPath: NodePath.join(project.path, "node_modules", name, "package.json")),
          let value = try? JSJSON.parse(data) else { return nil }
    return value["version"]
  }

  static func stylesDir(_ project: URL) -> String { NodePath.join(project.path, "quartz", "styles") }
  static func fontsDir(_ project: URL) -> String { NodePath.join(project.path, "quartz", "static", "fonts") }
  static func staticDir(_ project: URL) -> String { NodePath.join(project.path, "quartz", "static") }

  static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

  static func write(_ data: Data, to path: String) throws {
    try FileManager.default.createDirectory(atPath: NodePath.dirname(path), withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// JavaScript's default `sort()`: by UTF-16 code units.
  static func jsSorted(_ names: [String]) -> [String] { names.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) } }

  /// The files of one folder, not its folders and not its links.
  static func listFilesFlat(_ dir: URL) -> [String] {
    jsSorted(LayoutFrames.directoryEntriesWithKind(dir.path).filter { $0.kind == .file }.map(\.name))
  }

  /// Every file under a folder but the hidden ones, links followed (a link to a folder descended
  /// into, once per real folder; a dangling one skipped), as relative paths.
  static func listFilesDeep(_ dir: String, _ prefix: String = "", _ seen: inout Set<String>) -> [String] {
    guard exists(dir) else { return [] }
    if seen.isEmpty, let real = realpath(dir) { seen.insert(real) }
    var out: [String] = []
    for entry in LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: dir).path) where !entry.name.hasPrefix(".") {
      let full = NodePath.join(dir, entry.name)
      let rel = prefix.isEmpty ? entry.name : "\(prefix)/\(entry.name)"
      var isDirectory = entry.kind == .directory
      if entry.kind == .link {
        var info = stat()
        guard stat(full, &info) == 0 else { continue }
        isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
      }
      if !isDirectory {
        out.append(rel)
        continue
      }
      guard let real = realpath(full), !seen.contains(real) else { continue }
      seen.insert(real)
      out += listFilesDeep(full, rel, &seen)
    }
    return jsSorted(out)
  }

  static func listFilesDeep(_ dir: String) -> [String] {
    var seen: Set<String> = []
    return listFilesDeep(dir, "", &seen)
  }

  static func realpath(_ path: String) -> String? {
    guard let resolved = Darwin.realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  // A theme is the entry whose source is any package of the @quartz-themes scope.
  static func themeEntryIndex(_ plugins: [PluginEntry]) -> Int? {
    plugins.firstIndex { $0.source?.stringValue.map { JSText.startsWith($0, "@quartz-themes/") } ?? false }
  }

  // A frame's entry: a frame with that id exists and the source points into the frame directory.
  static func isFrameEntry(_ entry: PluginEntry, _ frameIds: Set<String>) -> Bool {
    frameIds.contains(entry.name) && (entry.source?.stringValue.map { JSText.includes($0, "authored-frames") } ?? false)
  }

  /// A bare npm specifier, as the Quartz CLI's `parseGitSource` calls an "npmPackage" source.
  static func npmPackageName(_ source: JSONValue?) -> String? {
    guard let source = source?.stringValue, !JSText.test(source, #"\A(github:|git\+|https?:|file:|\.|/)"#) else { return nil }
    return JSText.test(source, #"\A(@[^/]+/)?[^@/][^/]*\z"#) ? source : nil
  }

  /// `configService.deriveName`; a TypeError where QuartzControl's threw one.
  static func deriveName(_ source: JSONValue?) throws -> String {
    guard let name = PluginEntry.derivedName(source) else { throw JS.TypeError("Cannot read properties of undefined (reading 'replace')") }
    return name
  }

  /// One key per entry, instances of one plugin told apart by position: `quartz-layout-box#0`, `#1`.
  static func instanceKeys(_ entries: [JSONObject]) throws -> [String] {
    var seen: [String: Int] = [:]
    return try entries.map { entry in
      let name: String
      if let given = entry["name"], given != .null { name = JS.string(given) } else { name = try deriveName(entry["source"]) }
      let occurrence = seen[name] ?? 0
      seen[name] = occurrence + 1
      return "\(name)#\(occurrence)"
    }
  }

  // MARK: - appearance

  func collectAppearance(_ project: URL) async throws -> Collected? {
    let config = try await readConfig(project)
    var payload = JSONObject([("colors", Self.orEmptyObject(config.theme["colors"])), ("typography", Self.orEmptyObject(config.theme["typography"]))])
    if let origin = config.theme["fontOrigin"] { payload["fontOrigin"] = origin }
    if let caching = config.theme["cdnCaching"] { payload["cdnCaching"] = caching }
    // theme.colors nests one object per mode: the leaves are what counts.
    var colours = 0
    if case .object(let groups) = payload["colors"]! {
      for key in groups.keys { colours += JS.isObject(groups[key]) ? JS.keyCount(groups[key]!) : 1 }
    }
    return Collected(payload: .object(payload), stats: JSONObject([("colors", .number(Double(colours))), ("fonts", .number(Double(JS.keyCount(payload["typography"]!))))]))
  }

  func planAppearance(_ payload: JSONValue, _ run: Run) async throws -> PartPlan {
    let config = try await readConfig(run.project)
    var plan = PartPlan(id: "appearance")
    if Self.stringified(Self.orEmptyObject(config.theme["colors"])) != Self.stringified(payload["colors"]) { plan.conflicts.append(.string("colors")) }
    if Self.stringified(Self.orEmptyObject(config.theme["typography"])) != Self.stringified(payload["typography"]) { plan.conflicts.append(.string("typography")) }
    if config.theme["fontOrigin"] != payload["fontOrigin"] || config.theme["cdnCaching"] != payload["cdnCaching"] { plan.conflicts.append(.string("fontDelivery")) }
    return plan
  }

  func applyAppearance(_ payload: JSONValue, _ run: Run) async throws {
    if run.strategy == .projectWins {
      run.warn("appearanceSkipped")
      return
    }
    var config = try await readConfig(run.project)
    config.theme["colors"] = payload["colors"]
    config.theme["typography"] = payload["typography"]
    if let origin = payload["fontOrigin"] { config.theme["fontOrigin"] = origin }
    if let caching = payload["cdnCaching"] { config.theme["cdnCaching"] = caching }
    try await writeConfig(config, run.project)
  }

  // MARK: - cssVariables

  static func json(_ override: VariableOverride) -> JSONValue {
    var object = JSONObject([("key", .string(override.key)), ("light", .string(override.light))])
    if let dark = override.dark { object["dark"] = .string(dark) }
    if override.lightOnly && override.dark == nil { object["lightOnly"] = .bool(true) }
    return .object(object)
  }

  static func override(_ value: JSONValue) -> VariableOverride {
    VariableOverride(key: value["key"].map(JS.string) ?? "undefined", light: value["light"].map(JS.string) ?? "undefined",
                     dark: value["dark"].flatMap { $0 == .null ? nil : JS.string($0) }, lightOnly: value["lightOnly"] == .bool(true))
  }

  func collectVariables(_ project: URL) throws -> Collected? {
    let overrides = try StyleSheets.variableOverrides(project: project.path)
    guard !overrides.isEmpty else { return nil }
    return Collected(payload: .object(JSONObject([("overrides", .array(overrides.map(Self.json)))])),
                     stats: JSONObject([("variables", .number(Double(overrides.count)))]))
  }

  func planVariables(_ payload: JSONValue, _ run: Run) throws -> PartPlan {
    var existing: [String: VariableOverride] = [:]
    for override in try StyleSheets.variableOverrides(project: run.project.path) { existing[override.key] = override }
    var plan = PartPlan(id: "cssVariables")
    for override in try Self.list(payload["overrides"], "overrides") {
      let key = override["key"].map(JS.string) ?? "undefined"
      guard let current = existing[key] else {
        plan.additions.append(.string("--\(key)"))
        continue
      }
      if .string(current.light) != override["light"] || current.dark.map(JSONValue.string) != override["dark"] { plan.conflicts.append(.string("--\(key)")) }
    }
    return plan
  }

  // Merged per key: an override the package never mentions stays.
  func applyVariables(_ payload: JSONValue, _ run: Run) async throws {
    var order: [String] = []
    var merged: [String: VariableOverride] = [:]
    func set(_ override: VariableOverride) {
      if merged.updateValue(override, forKey: override.key) == nil { order.append(override.key) }
    }
    for override in try StyleSheets.variableOverrides(project: run.project.path) { set(override) }
    for override in try await inFormOfTarget(run.project, try Self.list(payload["overrides"], "overrides").map(Self.override)) {
      if run.strategy == .projectWins && merged[override.key] != nil { continue }
      set(override)
    }
    try await StyleSheets.saveVariableOverrides(order.map { merged[$0]! }, project: run.project.path)
  }

  /// A light-only value goes into a project not moved to `_quartzcontrol.scss` with its dark half
  /// explicit, as the Variables tab writes it there (1.0.x drops a third rule): the dark value the
  /// tab shows as the base, from the variable graph, then from Quartz's own catalog.
  func inFormOfTarget(_ project: URL, _ overrides: [VariableOverride]) async throws -> [VariableOverride] {
    let lightOnly = { (o: VariableOverride) in o.lightOnly && JS.trim(o.dark ?? "").isEmpty }
    guard overrides.contains(where: lightOnly), !StyleSheets.isMoved(try StyleSheets.readSources(project: project.path)) else { return overrides }
    let config = try await readConfig(project)
    let theme = Self.themeEntryIndex(config.plugins).map { config.plugins[$0] }
    let themeId = theme.flatMap { $0.enabled ? $0.object["options"]?["theme"]?.stringValue : nil }
    let graph = try VariableGraph.graph(project: project.path, themeId: themeId)
    let colors = config.theme["colors"]?.objectValue
    return overrides.map { o in
      guard lightOnly(o) else { return o }
      let info = graph.vars[o.key]
      var dark: String?
      if let value = info?["dark"]?.stringValue, !value.isEmpty { dark = value }
      else if let value = info?["light"]?.stringValue, !value.isEmpty { dark = value }
      else if let def = CssVariables.definition(o.key) {
        let value = CssVariables.defaultValue(def, lightMode: colors?["lightMode"]?.objectValue, darkMode: colors?["darkMode"]?.objectValue,
                                              typography: config.theme["typography"]?.objectValue, dark: true)
        if !value.isEmpty { dark = value }
      }
      return VariableOverride(key: o.key, light: o.light, dark: dark)
    }
  }

  // MARK: - theme

  func collectTheme(_ project: URL) async throws -> Collected? {
    let config = try await readConfig(project)
    guard let index = Self.themeEntryIndex(config.plugins) else { return nil }
    let entry = config.plugins[index].object
    let themeId = entry["options"]?["theme"]?.stringValue
    let packages = ["@quartz-themes/core"] + (themeId.map { ["@quartz-themes/\($0)"] } ?? [])
    let settings = entry["options"]?["styleSettings"]
    return Collected(payload: .object(JSONObject([("entry", .object(entry)), ("themeId", themeId.map(JSONValue.string) ?? .null)])),
                     stats: JSONObject([("styleSettings", .number(Double(JS.truthy(settings) && JS.isObject(settings) ? JS.keyCount(settings!) : 0)))]),
                     requires: packages.map { Dependency(name: $0, version: Self.installedVersion(project, $0)) })
  }

  static func themePackages(_ payload: JSONValue) -> [String] {
    let themeId = payload["themeId"].flatMap { JS.truthy($0) ? JS.string($0) : nil }
    return ["@quartz-themes/core"] + (themeId.map { ["@quartz-themes/\($0)"] } ?? [])
  }

  func planTheme(_ payload: JSONValue, _ run: Run) async throws -> PartPlan {
    let config = try await readConfig(run.project)
    var plan = PartPlan(id: "theme")
    if let index = Self.themeEntryIndex(config.plugins) {
      let current = config.plugins[index].object["options"]?["theme"]
      plan.conflicts.append(current.flatMap { $0 == .null ? nil : $0 } ?? .string("@quartz-themes/core"))
    } else {
      plan.additions.append(payload["themeId"].flatMap { $0 == .null ? nil : $0 } ?? .string("@quartz-themes/core"))
    }
    for name in Self.themePackages(payload) where !Self.hasNodeModule(run.project, name) { plan.missingPackages.append(Dependency(name: name)) }
    return plan
  }

  func applyTheme(_ payload: JSONValue, _ run: Run) async throws {
    let config = try await readConfig(run.project)
    let index = Self.themeEntryIndex(config.plugins)
    if index != nil && run.strategy == .projectWins {
      run.warn("themeSkipped")
      return
    }
    // The theme's own package: the entry alone resolved nothing on a machine without it.
    let missing = Self.themePackages(payload).filter { !Self.hasNodeModule(run.project, $0) }
    if !missing.isEmpty {
      run.progress(missing.joined(separator: ", "))
      let result = await npm(["install"] + missing, run.project)
      if !result.success { run.warn("themeInstallFailed:\(missing.joined(separator: ", ")):\(JSText.slice(result.output, -400))") }
    }
    guard var entry = payload["entry"]?.objectValue else { throw JS.TypeError("payload.entry is not an object") }
    var next = config
    if let index {
      if let order = next.plugins[index].object["order"] ?? entry["order"] { entry["order"] = order }
      next.plugins[index] = PluginEntry(object: entry)
    } else {
      next.plugins.append(PluginEntry(object: entry))
    }
    try await writeConfig(next, run.project)
  }

  // MARK: - styles

  static let managedMarkers = ["imports", "css-vars", "fonts", "google-fonts", "imported-styles"]

  /// custom.scss without all five managed blocks and without the line that loads the managed file:
  /// the part the user wrote, and what an older app can read.
  static func stripAllManaged(_ content: String) -> String {
    JS.trim(ManagedBlocks.stripManagedUse(managedMarkers.reduce(content) { ManagedBlocks.strip($0, $1) }))
  }

  // Sass wants a @use before any other rule, so an imported body's own are hoisted.
  static func splitUseStatements(_ content: String) -> (useLines: [String], rest: String) {
    var useLines: [String] = []
    var rest: [String] = []
    for line in JSText.split(content, "\n") {
      if JSText.test(line, #"\A[\#(JSText.space)]*@(use|forward)[\#(JSText.space)]+.*;[\#(JSText.space)]*\z"#) { useLines.append(JS.trim(line)) } else { rest.append(line) }
    }
    return (useLines, rest.joined(separator: "\n"))
  }

  static func onlyComments(_ scss: String) -> Bool {
    JSText.split(JSText.replaceAll(scss, #"/\*[\s\S]*?\*/"#, with: ""), "\n").allSatisfy { line in
      let trimmed = JS.trim(line)
      return trimmed.isEmpty || JSText.startsWith(trimmed, "//")
    }
  }

  /// custom.scss's free body under `projectWins`: the project's file stays, the package's rules
  /// come in their own managed block (removable later), their @use lines on top.
  static func projectWinsCustomScss(_ own: String, _ packageScss: String) -> String {
    let (useLines, rest) = splitUseStatements(packageScss)
    let incoming = JS.trim(rest)
    if onlyComments(incoming) { return own }
    let missing = useLines.filter { !JSText.includes(own, $0) }
    let withUses = missing.isEmpty ? own : "\(missing.joined(separator: "\n"))\n\(own)"
    return JSText.includes(own, incoming) ? withUses : ManagedBlocks.upsert(withUses, "imported-styles", incoming)
  }

  /// The stylesheets of the other template form (the 31 before 1.1 against the twelve), as far as
  /// this project loads them; `older` when the package brings the twelve.
  static func otherFormStylesheets(_ order: [String], _ project: URL) throws -> (older: Bool, paths: [String]) {
    let set = try StyleFiles.list(project: project.path)
    let loaded = set.files.filter(\.imported).map(\.relativePath)
    if StylesheetConsolidation.isConsolidatedOrder(order) { return (true, loaded.filter(StylesheetConsolidation.isLegacyOnly)) }
    if order.contains(where: StylesheetConsolidation.isLegacyOnly) && set.consolidated { return (false, loaded.filter(StylesheetConsolidation.isConsolidatedOnly)) }
    return (true, [])
  }

  // `--tpl-` is the template's own prefix; Quartz's variables are defined in no stylesheet.
  static let templateVariable = #"var\(["# + JSText.space + #"]*(--tpl-[A-Za-z0-9_-]+)"#
  static let definedVariable = #"(--tpl-[A-Za-z0-9_-]+)["# + JSText.space + #"]*:"#

  static func scssUnder(_ dir: String, _ depth: Int = 0) -> [String] {
    guard depth <= 6, exists(dir) else { return [] }
    var out: [String] = []
    for entry in LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: dir).path) {
      let path = NodePath.join(dir, entry.name)
      if entry.kind == .directory { out += scssUnder(path, depth + 1) } else if JSText.endsWith(entry.name, ".scss") { out.append(path) }
    }
    return out
  }

  /// The template variables the package's stylesheets read and neither they nor the project define.
  static func missingTemplateVariables(_ files: [String], _ project: URL, _ packageFiles: ZipArchive.Files) throws -> [String] {
    var used: [String] = []
    var defined: Set<String> = []
    for relativePath in files {
      let text = packageFiles["files/styles/\(relativePath)"].map { String(decoding: $0, as: UTF8.self) } ?? ""
      for match in JSText.matches(text, templateVariable) where !used.contains(match.groups[1]!) { used.append(match.groups[1]!) }
      for match in JSText.matches(text, definedVariable) { defined.insert(match.groups[1]!) }
    }
    if used.isEmpty { return [] }
    for path in scssUnder(stylesDir(project)) {
      for match in JSText.matches(try LocaleFiles.readText(URL(fileURLWithPath: path)), definedVariable) { defined.insert(match.groups[1]!) }
    }
    return jsSorted(used.filter { !defined.contains($0) })
  }

  func collectStyles(_ project: URL) throws -> Collected? {
    let set = try StyleFiles.list(project: project.path)
    let body = Self.stripAllManaged(set.main.content)
    let files = set.files.map(\.relativePath)
    if body.isEmpty && files.isEmpty { return nil }
    var entries: [ZipArchive.Entry] = []
    for relativePath in files {
      let path = StyleSheets.styleFile(project.path, relativePath)
      if Self.exists(URL(fileURLWithPath: path).path) { entries.append(ZipArchive.Entry(name: "files/styles/\(relativePath)", data: try Posix.read(path))) }
    }
    let payload = JSONObject([("customScss", .string(body)), ("order", .array(set.files.filter(\.imported).map { .string($0.relativePath) })),
                              ("files", .array(files.map(JSONValue.string)))])
    return Collected(payload: .object(payload), files: entries, stats: JSONObject([("files", .number(Double(files.count)))]))
  }

  func planStyles(_ payload: JSONValue, _ run: Run) throws -> PartPlan {
    var plan = PartPlan(id: "styles")
    let files = try Self.names(payload["files"], "files")
    for relativePath in files {
      // Said, not passed over: the plan must not promise a file that will never be written.
      guard let target = PackagePaths.writable(Self.stylesDir(run.project), relativePath) else {
        plan.notes.append("outside:\(relativePath)")
        continue
      }
      if Self.exists(target) { plan.conflicts.append(.string(relativePath)) } else { plan.additions.append(.string(relativePath)) }
    }
    let customScss = payload["customScss"].map(JS.string) ?? "undefined"
    let current = Self.stripAllManaged(try StyleSheets.readCustom(project: run.project.path).content)
    if current != customScss { plan.conflicts.append(.string("custom.scss")) }
    if current != customScss && Self.projectWinsCustomScss(current, customScss) != current { plan.notes.append("customScssMerged") }
    let other = try Self.otherFormStylesheets(try Self.names(payload["order"], "order"), run.project)
    if !other.paths.isEmpty { plan.notes.append("\(other.older ? "legacyStyles" : "newerStyles"):\(other.paths.count)") }
    let missing = try Self.missingTemplateVariables(files, run.project, run.files)
    if !missing.isEmpty { plan.notes.append("missingVariables:\(missing.joined(separator: ","))") }
    return plan
  }

  func applyStyles(_ payload: JSONValue, _ run: Run) throws {
    let project = run.project
    for relativePath in try Self.names(payload["files"], "files") {
      guard let data = run.files["files/styles/\(relativePath)"] else { continue }
      guard let target = PackagePaths.writable(Self.stylesDir(project), relativePath) else {
        run.warn("fileOutsideProject:\(relativePath)")
        continue
      }
      if Self.exists(target) && run.strategy == .projectWins {
        run.warn("styleFileSkipped:\(relativePath)")
        continue
      }
      try Self.write(data, to: target)
    }
    let order = try Self.names(payload["order"], "order")
    let old = try Self.otherFormStylesheets(order, project).paths
    let before = try StyleSheets.readCustom(project: project.path)
    var existingOrder = try StyleFiles.list(project: project.path).files.filter(\.imported).map(\.relativePath)
      .filter { !(run.strategy == .packageWins && old.contains($0)) }
    let customScss = payload["customScss"].map(JS.string) ?? "undefined"
    let body = run.strategy == .packageWins ? customScss : Self.projectWinsCustomScss(Self.stripAllManaged(before.content), customScss)
    try StyleSheets.replaceCustomBodyNow(body, project: project.path)
    // The package's order, restricted to files that exist here; under projectWins with the other
    // form loaded, the package's stylesheets are written but not loaded.
    var packageOrder = order.filter { Self.exists(NodePath.join(Self.stylesDir(project), $0)) }
      .filter { !(run.strategy == .projectWins && !old.isEmpty && !existingOrder.contains($0)) }
    if run.strategy == .packageWins {
      for path in existingOrder where !packageOrder.contains(path) { packageOrder.append(path) }
      try StyleSheets.setImportOrderNow(packageOrder, project: project.path)
    } else {
      for path in packageOrder where !existingOrder.contains(path) { existingOrder.append(path) }
      try StyleSheets.setImportOrderNow(existingOrder, project: project.path)
    }
  }

  // MARK: - fonts

  // A package from before 2026-09-19 has root-relative font URLs; read as the relative form.
  static func incomingFontFaceCss(_ payload: JSONValue) -> JSONValue? {
    guard let css = payload["fontFaceCss"] else { return nil }
    guard case .string(let text) = css, !text.isEmpty else { return css }
    return .string(ManagedBlocks.relativeFontUrls(text))
  }

  static func currentFontFaceCss(_ sources: StyleSheets.Sources) -> String? {
    guard let body = StyleSheets.managedBody(sources, "fonts"), !body.isEmpty else { return StyleSheets.managedBody(sources, "fonts") }
    return ManagedBlocks.relativeFontUrls(body)
  }

  func collectFonts(_ project: URL) throws -> Collected? {
    let names = Self.listFilesFlat(URL(fileURLWithPath: Self.fontsDir(project)))
    let sources = try StyleSheets.readSources(project: project.path)
    let fontFaceCss = StyleSheets.managedBody(sources, "fonts")
    let googleFontsCss = StyleSheets.managedBody(sources, "google-fonts")
    if names.isEmpty && (fontFaceCss ?? "").isEmpty && (googleFontsCss ?? "").isEmpty { return nil }
    let entries = try names.map { ZipArchive.Entry(name: "files/fonts/\($0)", data: try Data(contentsOf: URL(fileURLWithPath: NodePath.join(Self.fontsDir(project), $0)))) }
    let payload = JSONObject([("fontFaceCss", fontFaceCss.map(JSONValue.string) ?? .null), ("googleFontsCss", googleFontsCss.map(JSONValue.string) ?? .null),
                              ("files", .array(names.map(JSONValue.string)))])
    return Collected(payload: .object(payload), files: entries, stats: JSONObject([("files", .number(Double(names.count)))]))
  }

  func planFonts(_ payload: JSONValue, _ run: Run) throws -> PartPlan {
    var plan = PartPlan(id: "fonts")
    let project = run.project
    let faceCss = Self.incomingFontFaceCss(payload)
    for name in try Self.names(payload["files"], "files") {
      guard let target = PackagePaths.writable(Self.fontsDir(project), name) else {
        plan.notes.append("outside:\(name)")
        continue
      }
      guard Self.exists(target) else {
        plan.additions.append(.string(name))
        continue
      }
      // The same font twice is neither an addition nor a conflict.
      if let incoming = run.files["files/fonts/\(name)"], incoming == FileManager.default.contents(atPath: target) { plan.notes.append("identical:\(name)") }
      else { plan.conflicts.append(.string(name)) }
    }
    let google = payload["googleFontsCss"]
    let incoming = [faceCss.map { $0 == .null ? "" : JS.string($0) } ?? "", google.map { $0 == .null ? "" : JS.string($0) } ?? ""].joined(separator: "\n")
    var removed: [String] = []
    func remove(_ names: [String]) { for name in names where !removed.contains(name) { removed.append(name) } }
    if let faceCss, JS.truthy(faceCss) {
      let face = JS.string(faceCss)
      let current = Self.currentFontFaceCss(try StyleSheets.readSources(project: project.path))
      if let current, !current.isEmpty, current != face {
        plan.conflicts.append(.string("@font-face"))
        remove(try fonts.fontFilesReplacedRulesWouldRemove(previous: current, incoming: incoming, project: project.path))
      } else if (current ?? "").isEmpty {
        plan.additions.append(.string("@font-face"))
      }
    }
    if let google, JS.truthy(google) {
      let css = JS.string(google)
      let current = StyleSheets.managedBody(try StyleSheets.readSources(project: project.path), "google-fonts")
      if let current, !current.isEmpty, current != css {
        plan.conflicts.append(.string("@font-face (Google)"))
        remove(try fonts.fontFilesReplacedRulesWouldRemove(previous: current, incoming: incoming, project: project.path))
      } else if (current ?? "").isEmpty {
        plan.additions.append(.string("@font-face (Google)"))
      }
    }
    if !removed.isEmpty { plan.notes.append("fontsRemoved:\(removed.joined(separator: ","))") }
    return plan
  }

  func applyFonts(_ payload: JSONValue, _ run: Run) async throws {
    let project = run.project
    let faceCss = Self.incomingFontFaceCss(payload)
    try FileManager.default.createDirectory(atPath: Self.fontsDir(project), withIntermediateDirectories: true)
    for name in try Self.names(payload["files"], "files") {
      guard let data = run.files["files/fonts/\(name)"] else { continue }
      guard let target = PackagePaths.writable(Self.fontsDir(project), name) else {
        run.warn("fileOutsideProject:\(name)")
        continue
      }
      if Self.exists(target) {
        if data == FileManager.default.contents(atPath: target) { continue }
        if run.strategy == .projectWins {
          run.warn("fontSkipped:\(name)")
          continue
        }
      }
      try data.write(to: URL(fileURLWithPath: target))
    }
    // What the replaced rules pointed at goes too, once both blocks are written (packageWins only).
    var replaced: [String] = []
    if let previous = try applyGoogleFontsCss(project, payload["googleFontsCss"].flatMap { JS.truthy($0) ? JS.string($0) : nil }, run.strategy),
       !previous.isEmpty { replaced.append(previous) }
    if let faceCss, JS.truthy(faceCss),
       let previous = try writeFontFaceBlock(project, try StyleSheets.readSources(project: project.path), JS.string(faceCss), run.strategy), !previous.isEmpty {
      replaced.append(previous)
    }
    for css in replaced {
      for name in try await fonts.deleteFontFilesOfReplacedRules(css, project: project.path) { run.warn("fontRemoved:\(name)") }
    }
  }

  /// One request's answer, replaced whole: under projectWins a project with its own keeps them.
  /// Answers the block it replaced.
  func applyGoogleFontsCss(_ project: URL, _ css: String?, _ strategy: Strategy) throws -> String? {
    guard let css else { return nil }
    let current = StyleSheets.managedBody(try StyleSheets.readSources(project: project.path), "google-fonts")
    if current == css || (!(current ?? "").isEmpty && strategy == .projectWins) { return nil }
    try StyleSheets.writeManagedBlocksNow(["google-fonts": css], project: project.path)
    return current
  }

  /// The package's @font-face rules; under projectWins appended to the project's, only the new
  /// ones. Answers the block they replaced (packageWins only).
  func writeFontFaceBlock(_ project: URL, _ sources: StyleSheets.Sources, _ faceCss: String, _ strategy: Strategy) throws -> String? {
    let current = Self.currentFontFaceCss(sources)
    let hasCurrent = !(current ?? "").isEmpty
    let body = hasCurrent && strategy == .projectWins ? ManagedBlocks.joinUniqueRules([current!, faceCss]) : current == faceCss ? current! : faceCss
    try StyleSheets.writeManagedBlocksNow(["fonts": body], project: project.path)
    return strategy == .packageWins && hasCurrent && current != body ? StyleSheets.managedBody(sources, "fonts") : nil
  }

  // MARK: - static

  /// The design's other files under quartz/static (snippets, logos, backgrounds), not the fonts.
  static let staticMaxBytes = 25 * 1024 * 1024

  func collectStatic(_ project: URL) throws -> Collected? {
    let dir = Self.staticDir(project)
    let names = Self.listFilesDeep(dir).filter { !JSText.startsWith($0, "fonts/") }
    if names.isEmpty { return nil }
    var entries: [ZipArchive.Entry] = []
    var bytes = 0
    for name in names {
      let data = try Data(contentsOf: URL(fileURLWithPath: NodePath.join(dir, name)))
      bytes += data.count
      // Thrown, not trimmed: a package that silently dropped half its images would be worse.
      if bytes > Self.staticMaxBytes { throw TemplateFailure(message: L10n.t("main.templateStaticTooLarge", ["limit": String(Self.staticMaxBytes / 1024 / 1024)])) }
      entries.append(ZipArchive.Entry(name: "files/static/\(name)", data: data))
    }
    return Collected(payload: .object(JSONObject([("files", .array(names.map(JSONValue.string)))])), files: entries,
                     stats: JSONObject([("files", .number(Double(names.count))), ("kilobytes", .number(JS.round(Double(bytes) / 1024)))]))
  }

  func planStatic(_ payload: JSONValue, _ run: Run) throws -> PartPlan {
    let dir = Self.staticDir(run.project)
    var plan = PartPlan(id: "static")
    let usersOwn = ProjectIcon.userChosenStaticFiles(project: run.project.path)
    var unrecorded: Set<String> = []
    if ProjectIcon.hasUnrecordedIcon(project: run.project.path) { unrecorded.insert("icon.png") }
    if ProjectIcon.hasUnrecordedDarkIcon(project: run.project.path) { unrecorded.insert("icon-dark.png") }
    for name in try Self.names(payload["files"], "files") {
      guard let target = PackagePaths.writable(dir, name) else {
        plan.notes.append("outside:\(name)")
        continue
      }
      guard Self.exists(target) else {
        plan.additions.append(.string(name))
        continue
      }
      if let incoming = run.files["files/static/\(name)"], incoming == FileManager.default.contents(atPath: target) { plan.notes.append("identical:\(name)") }
      else if usersOwn.contains(name) { plan.notes.append("projectIcon:\(name)") }
      else {
        plan.conflicts.append(.string(name))
        if unrecorded.contains(name) { plan.notes.append("unrecordedIcon:\(name)") }
      }
    }
    return plan
  }

  func applyStatic(_ payload: JSONValue, _ run: Run) throws {
    let dir = Self.staticDir(run.project)
    // The project's own picture, chosen in the app, is theirs and not a design.
    let usersOwn = ProjectIcon.userChosenStaticFiles(project: run.project.path)
    for name in try Self.names(payload["files"], "files") {
      guard let data = run.files["files/static/\(name)"] else { continue }
      guard let target = PackagePaths.writable(dir, name) else {
        run.warn("fileOutsideProject:\(name)")
        continue
      }
      if Self.exists(target) {
        if data == FileManager.default.contents(atPath: target) { continue }
        if usersOwn.contains(name) {
          run.warn("projectIconKept:\(name)")
          continue
        }
        if run.strategy == .projectWins {
          run.warn("staticSkipped:\(name)")
          continue
        }
      }
      try Self.write(data, to: target)
    }
  }

  // MARK: - layout

  func collectLayout(_ project: URL) async throws -> Collected? {
    let config = try await readConfig(project)
    let widths = LayoutFrames.widths(project: project.path)
    let layout = config.layout
    let payload = JSONObject([("layout", layout.map(JSONValue.object) ?? .null),
                              ("breakpoints", .object(JSONObject([("tablet", .number(widths.tablet)), ("mobile", .number(widths.mobile))])))])
    return Collected(payload: .object(payload), stats: JSONObject([("groups", .number(Double(layout?["groups"].map(JS.keyCount) ?? 0))),
                                                                   ("pageTypes", .number(Double(layout?["byPageType"].map(JS.keyCount) ?? 0)))]))
  }

  func planLayout(_ payload: JSONValue, _ run: Run) async throws -> PartPlan {
    let config = try await readConfig(run.project)
    var plan = PartPlan(id: "layout")
    if Self.stringified(config.layout.map(JSONValue.object) ?? .null) != Self.stringified(payload["layout"]) { plan.conflicts.append(.string("layout")) }
    let current = LayoutFrames.widths(project: run.project.path)
    if payload["breakpoints"]?["tablet"] != .number(current.tablet) || payload["breakpoints"]?["mobile"] != .number(current.mobile) {
      plan.conflicts.append(.string("breakpoints"))
    }
    return plan
  }

  func applyLayout(_ payload: JSONValue, _ run: Run) async throws {
    if run.strategy == .projectWins {
      run.warn("layoutSkipped")
      return
    }
    if let layout = payload["layout"], JS.truthy(layout) {
      var config = try await readConfig(run.project)
      config.layout = layout.objectValue
      try await writeConfig(config, run.project)
    }
    // Every frame's media queries carry the widths, so every frame is rewritten.
    let breakpoints = payload["breakpoints"]
    try await frames.saveWidths((JS.toNumber(breakpoints?["tablet"]), JS.toNumber(breakpoints?["mobile"])), project: run.project.path)
  }

  // MARK: - frames

  // The payload is a file somebody passed along: even a frame's name may be no string.
  static func frameLabel(_ frame: JSONValue) -> String {
    let named: JSONValue? = if let name = frame["frameName"], case .string(let text) = name, !text.isEmpty { name } else { frame["id"] }
    guard case .string(let text)? = named, !text.isEmpty else { return "?" }
    return JSText.slice(text, 0, 120)
  }

  /// `frame.frameName || frame.id`.
  static func frameShown(_ frame: JSONValue) -> JSONValue {
    if let name = frame["frameName"], JS.truthy(name) { return name }
    return frame["id"] ?? .null
  }

  func collectFrames(_ project: URL) -> Collected? {
    let list = LayoutFrames.listFrames(project: project.path)
    guard !list.isEmpty else { return nil }
    return Collected(payload: .object(JSONObject([("frames", .array(list))])), stats: JSONObject([("frames", .number(Double(list.count)))]))
  }

  func planFrames(_ payload: JSONValue, _ run: Run) throws -> PartPlan {
    let existing = Set(LayoutFrames.listFrames(project: run.project.path).compactMap { $0["id"]?.stringValue })
    var plan = PartPlan(id: "frames")
    for frame in try Self.list(payload["frames"], "frames") {
      // The question saveFrame will ask, asked while the answer is worth something, with its reason.
      if let problem = LayoutFrames.problem(frame) {
        plan.notes.append("invalidFrame:\(L10n.t("main.frameNameAndReason", ["name": Self.frameLabel(frame), "reason": problem]))")
        continue
      }
      if let id = frame["id"]?.stringValue, existing.contains(id) { plan.conflicts.append(Self.frameShown(frame)) } else { plan.additions.append(Self.frameShown(frame)) }
    }
    return plan
  }

  func applyFrames(_ payload: JSONValue, _ run: Run) async throws {
    let existing = Set(LayoutFrames.listFrames(project: run.project.path).compactMap { $0["id"]?.stringValue })
    for frame in try Self.list(payload["frames"], "frames") {
      let shown = JS.string(Self.frameShown(frame))
      if let id = frame["id"]?.stringValue, existing.contains(id), run.strategy == .projectWins {
        run.warn("frameSkipped:\(shown)")
        continue
      }
      run.progress(shown)
      // saveFrame writes the frame's files and registers it with `quartz plugin add <its dir>`,
      // which is why a frame's entry never travels in the plugins part.
      let result = try await frames.saveFrame(frame, project: run.project.path, snapshot: false)
      guard result.success else {
        run.warn("frameFailed:\(L10n.t("main.frameNameAndReason", ["name": Self.frameLabel(frame), "reason": JSText.slice(result.output, -400)]))")
        continue
      }
      // With a `.quartz/plugins/<id>` link already there, `quartz plugin add` exits 0 and writes
      // no entry (measured in QuartzControl): the file is checked, not the exit code.
      let id = frame["id"]?.stringValue ?? ""
      var config = try await readConfig(run.project)
      if !config.plugins.contains(where: { $0.name == id }) {
        config.plugins.append(PluginEntry(object: JSONObject([("name", .string(id)), ("source", .string(try LayoutFrames.frameDirectory(project: run.project.path, id: id))),
                                                              ("enabled", .bool(true))])))
        try await writeConfig(config, run.project)
      }
    }
  }

  // MARK: - plugins

  static let formsPlugin = "quartz-forms"

  /// `key in object` for a plain object: its own keys and Object.prototype's.
  static func hasKey(_ object: JSONObject, _ key: String) -> Bool {
    object[key] != nil || ["constructor", "hasOwnProperty", "isPrototypeOf", "propertyIsEnumerable", "toLocaleString", "toString", "valueOf", "__proto__",
                           "__defineGetter__", "__defineSetter__", "__lookupGetter__", "__lookupSetter__"].contains(key)
  }

  /// quartz-forms' options are a site's working state, not its looks: merged, not replaced. The
  /// project keeps everything, the package brings only the forms it lacks; an added form that
  /// would send through the project's transport carries the package's own.
  static func mergeFormsOptions(_ own: JSONValue?, _ fromPackage: JSONValue?) -> (options: JSONObject, added: [String], kept: [String], pinned: String?) {
    let ownOptions = own?.objectValue ?? JSONObject()
    let ownForms = ownOptions["forms"]?.objectValue ?? JSONObject()
    let packageForms = fromPackage?["forms"]?.objectValue ?? JSONObject()
    let packageTransport = fromPackage?["transport"]?.objectValue
    let pin = packageTransport != nil && JSJSON.compact(.object(packageTransport!)) != JSJSON.compact(ownOptions["transport"] ?? .null)
    var added = JSONObject()
    var kept: [String] = []
    for id in packageForms.keys {
      if hasKey(ownForms, id) {
        kept.append(id)
        continue
      }
      let form = packageForms[id]!
      if pin, case .object(var object) = form, object["transport"] == nil {
        object["transport"] = .object(packageTransport!)
        added[id] = .object(object)
      } else {
        added[id] = form
      }
    }
    let pinned = pin && !added.isEmpty ? packageTransport?["kind"]?.stringValue : nil
    var forms = ownForms
    for id in added.keys { forms[id] = added[id] }
    var options = ownOptions
    options["forms"] = .object(forms)
    return (options, added.keys, kept, pinned)
  }

  func collectPlugins(_ project: URL) async throws -> Collected? {
    let config = try await readConfig(project)
    let frameIds = Set(LayoutFrames.listFrames(project: project.path).compactMap { $0["id"]?.stringValue })
    let themeIndex = Self.themeEntryIndex(config.plugins)
    let entries = config.plugins.enumerated().filter { $0.offset != themeIndex && !Self.isFrameEntry($0.element, frameIds) }.map(\.element)
    if entries.isEmpty { return nil }
    // A git source goes out as the project has it, without a pinned ref.
    let requires = entries.compactMap { entry in Self.npmPackageName(entry.source).map { Dependency(name: $0, version: Self.installedVersion(project, $0)) } }
    return Collected(payload: .object(JSONObject([("entries", .array(entries.map { .object($0.object) }))])),
                     stats: JSONObject([("plugins", .number(Double(entries.count))), ("active", .number(Double(entries.filter(\.enabled).count)))]),
                     requires: requires)
  }

  static func entryName(_ entry: JSONObject) throws -> String {
    if let given = entry["name"], given != .null { return JS.string(given) }
    return try deriveName(entry["source"])
  }

  func planPlugins(_ payload: JSONValue, _ run: Run) async throws -> PartPlan {
    let config = try await readConfig(run.project)
    let entries = try Self.list(payload["entries"], "entries").map { $0.objectValue ?? JSONObject() }
    let existingKeys = try Self.instanceKeys(config.plugins.map(\.object))
    let keys = try Self.instanceKeys(entries)
    var plan = PartPlan(id: "plugins")
    let countOf = { (name: String) in config.plugins.filter { (try? Self.entryName($0.object)) == name }.count }
    for (index, entry) in entries.enumerated() {
      let name = try Self.deriveName(entry["source"])
      if let at = existingKeys.firstIndex(of: keys[index]) {
        plan.conflicts.append(.string(name))
        let own = config.plugins[at]
        if .bool(own.enabled) != entry["enabled"] { plan.notes.append("\(entry["enabled"] == .bool(true) ? "pluginOn" : "pluginOff"):\(name)") }
        if countOf(name) > 1 && !plan.notes.contains("byPosition:\(name)") { plan.notes.append("byPosition:\(name)") }
        if name == Self.formsPlugin {
          let merged = Self.mergeFormsOptions(own.object["options"], entry["options"])
          plan.notes.append("formsMerged:\(merged.added.joined(separator: ","))")
          if !merged.kept.isEmpty { plan.notes.append("formsOwn:\(merged.kept.joined(separator: ","))") }
          if let pinned = merged.pinned { plan.notes.append("formsPinned:\(pinned)") }
        }
      } else {
        plan.additions.append(.string(name))
      }
      if let npmName = Self.npmPackageName(entry["source"]) {
        if !Self.hasNodeModule(run.project, npmName) { plan.missingPackages.append(Dependency(name: npmName)) }
      } else if entry["source"]?.stringValue != nil && !Self.exists(NodePath.join(run.project.path, ".quartz", "plugins", name)) {
        plan.notes.append("cliInstall:\(name)")
      }
    }
    return plan
  }

  /// Installs only what is missing and writes every entry in one save.
  func applyPlugins(_ payload: JSONValue, _ run: Run) async throws {
    let project = run.project
    let config = try await readConfig(project)
    let entries = try Self.list(payload["entries"], "entries").map { $0.objectValue ?? JSONObject() }
    var byInstance: [String: Int] = [:]
    for (index, key) in try Self.instanceKeys(config.plugins.map(\.object)).enumerated() { byInstance[key] = index }
    let payloadKeys = try Self.instanceKeys(entries)
    var next = config.plugins.map(\.object)

    let missingNpm = entries.compactMap { Self.npmPackageName($0["source"]) }.filter { !Self.hasNodeModule(project, $0) }
    if !missingNpm.isEmpty {
      run.progress(missingNpm.joined(separator: ", "))
      var unique: [String] = []
      for name in missingNpm where !unique.contains(name) { unique.append(name) }
      let result = await npm(["install"] + unique, project)
      if !result.success { run.warn("pluginInstallFailed:\(missingNpm.joined(separator: ", ")):\(JSText.slice(result.output, -400))") }
    }

    for (position, entry) in entries.enumerated() {
      let name = try Self.deriveName(entry["source"])
      let index = byInstance[payloadKeys[position]]
      if let index, run.strategy == .projectWins {
        // The project's entry stays; a form it lacks is an addition (the package's pages embed it).
        if name == Self.formsPlugin {
          let forms = Self.mergeFormsOptions(next[index]["options"], entry["options"])
          if !forms.added.isEmpty {
            next[index]["options"] = .object(forms.options)
            continue
          }
        }
        run.warn("pluginSkipped:\(name)")
        continue
      }
      guard let source = entry["source"]?.stringValue else {
        run.warn("pluginUnsupported:\(name)")
        continue
      }
      // A github:/git+ source goes through the CLI: it clones, builds and writes quartz.lock.json.
      if Self.npmPackageName(.string(source)) == nil && !Self.exists(NodePath.join(project.path, ".quartz", "plugins", name)) {
        run.progress(name)
        let result = await addPlugin(source, project)
        guard result.success else {
          run.warn("pluginInstallFailed:\(name):\(JSText.slice(result.output, -400))")
          continue
        }
      }
      var written = entry
      written["name"] = .string(name)
      if let index {
        if name == Self.formsPlugin { written["options"] = .object(Self.mergeFormsOptions(next[index]["options"], entry["options"]).options) }
        next[index] = written
      } else {
        next.append(written)
      }
    }

    // Re-read: a CLI install appends its own bare entry. Entries written here win by key, what
    // the CLI added that is unknown here stays, and what is still missing is appended.
    var after = try await readConfig(project)
    let nextKeys = try Self.instanceKeys(next)
    var written: [String: JSONObject] = [:]
    for (index, key) in nextKeys.enumerated() { written[key] = next[index] }
    let afterKeys = try Self.instanceKeys(after.plugins.map(\.object))
    var merged = after.plugins.enumerated().map { written[afterKeys[$0.offset]] ?? $0.element.object }
    let covered = Set(afterKeys)
    for (index, entry) in next.enumerated() where !covered.contains(nextKeys[index]) { merged.append(entry) }
    after.plugins = merged.map(PluginEntry.init(object:))
    try await writeConfig(after, project)
  }

  // MARK: - translations

  static func json(_ entry: LocaleFiles.Entry) -> JSONValue {
    .object(JSONObject([("path", .array(entry.path.map(JSONValue.string))), ("kind", .string(entry.kind.rawValue)), ("value", .string(entry.value))]))
  }

  func probeTranslations(_ project: URL) async throws -> JSONObject {
    let customizations = try await locales.customizations(project: project)
    let withChanges = customizations.filter { !$0.changed.isEmpty }
    var all: [[LocaleFiles.Entry]] = []
    for item in customizations {
      let entries = try await locales.entries(project: project, code: item.code)
      if !entries.isEmpty { all.append(entries) }
    }
    return JSONObject([("languages", .number(Double(withChanges.count))), ("entries", .number(Double(withChanges.reduce(0) { $0 + $1.changed.count }))),
                       ("allLanguages", .number(Double(all.count))), ("allEntries", .number(Double(all.reduce(0) { $0 + $1.count }))),
                       ("undetermined", .number(Double(customizations.filter { $0.source == .none }.count)))])
  }

  func collectTranslations(_ project: URL, _ scope: TranslationScope) async throws -> Collected? {
    var localesOut: [(code: String, entries: [LocaleFiles.Entry])] = []
    for item in try await locales.customizations(project: project) {
      let entries = scope == .all ? try await locales.entries(project: project, code: item.code) : item.changed
      if !entries.isEmpty { localesOut.append((item.code, entries)) }
    }
    if localesOut.isEmpty { return nil }
    let payload = JSONObject([("scope", .string(scope.rawValue)),
                              ("locales", .array(localesOut.map { .object(JSONObject([("code", .string($0.code)), ("entries", .array($0.entries.map(Self.json)))])) }))])
    return Collected(payload: .object(payload), stats: JSONObject([("languages", .number(Double(localesOut.count))),
                                                                   ("entries", .number(Double(localesOut.reduce(0) { $0 + $1.entries.count })))]))
  }

  /// Per locale: the keys the project changed itself (a conflict, not an addition).
  func customised(_ project: URL) async throws -> [String: Set<String>] {
    var own: [String: Set<String>] = [:]
    for item in try await locales.customizations(project: project) { own[item.code] = Set(item.changed.map { $0.path.joined(separator: ".") }) }
    return own
  }

  func current(_ project: URL, _ code: String) async throws -> [String: String] {
    var map: [String: String] = [:]
    for entry in try await locales.entries(project: project, code: code) { map[entry.path.joined(separator: ".")] = entry.value }
    return map
  }

  static func localeEntries(_ payload: JSONValue) throws -> [(code: String, entries: [JSONValue])] {
    try list(payload["locales"], "locales").map { locale in
      (locale["code"].map(JS.string) ?? "undefined", try list(locale["entries"], "entries"))
    }
  }

  static func key(_ entry: JSONValue) throws -> String {
    try names(entry["path"], "path").joined(separator: ".")
  }

  func planTranslations(_ payload: JSONValue, _ run: Run) async throws -> PartPlan {
    var plan = PartPlan(id: "translations")
    let own = try await customised(run.project)
    for (code, entries) in try Self.localeEntries(payload) {
      let current = try await current(run.project, code)
      for entry in entries {
        let key = try Self.key(entry)
        guard let value = current[key] else {
          plan.notes.append("missingKey:\(code):\(key)")
          continue
        }
        if .string(value) == entry["value"] { continue }
        if own[code]?.contains(key) == true { plan.conflicts.append(.string("\(code): \(key)")) } else { plan.additions.append(.string("\(code): \(key)")) }
      }
    }
    return plan
  }

  func applyTranslations(_ payload: JSONValue, _ run: Run) async throws {
    let own = try await customised(run.project)
    for (code, entries) in try Self.localeEntries(payload) {
      run.progress(code)
      let current = try await current(run.project, code)
      for entry in entries {
        let key = try Self.key(entry)
        guard let value = current[key] else {
          run.warn("missingKey:\(code):\(key)")
          continue
        }
        if .string(value) == entry["value"] { continue }
        if run.strategy == .projectWins && own[code]?.contains(key) == true { continue }
        let kind: LocaleFiles.Kind = entry["kind"] == .string("string") ? .string : .template
        let result = try await locales.save(project: run.project, code: code, path: try Self.names(entry["path"], "path"), kind: kind,
                                            value: entry["value"].map(JS.string) ?? "undefined")
        if !result.success { run.warn("translationFailed:\(code):\(key):\(result.error ?? "")") }
      }
    }
  }

  // MARK: - presets

  func collectPresets(_ project: URL) -> Collected? {
    let list = ThemePresets.list(project: project)
    guard !list.isEmpty else { return nil }
    return Collected(payload: .object(JSONObject([("presets", .array(list))])), stats: JSONObject([("presets", .number(Double(list.count)))]))
  }

  func planPresets(_ payload: JSONValue, _ run: Run) throws -> PartPlan {
    let existing = ThemePresets.list(project: run.project).compactMap { $0["id"] }
    var plan = PartPlan(id: "presets")
    for preset in try Self.list(payload["presets"], "presets") {
      if let id = preset["id"], existing.contains(id) { plan.conflicts.append(preset["name"] ?? .null) } else { plan.additions.append(preset["name"] ?? .null) }
    }
    return plan
  }

  func applyPresets(_ payload: JSONValue, _ run: Run) throws {
    let existing = ThemePresets.list(project: run.project).compactMap { $0["id"] }
    for preset in try Self.list(payload["presets"], "presets") {
      if let id = preset["id"], existing.contains(id), run.strategy == .projectWins {
        run.warn("presetSkipped:\(preset["name"].map(JS.string) ?? "undefined")")
        continue
      }
      try ThemePresets.save(preset, project: run.project)
    }
  }

  // MARK: - content

  /// The notes. Hidden entries are skipped, there is a cap, and a content folder that is a link
  /// (into somebody's vault) is never written into.
  static let contentMaxBytes = 100 * 1024 * 1024
  static let formBlock = JSText.lineStart + #"```quartz-form[ \t]*\r?\n[ \t]*([a-z0-9][a-z0-9-]*)[ \t]*\r?\n```"#

  /// quartz-forms' forms, or nil without the plugin.
  static func formsOf(_ config: QuartzConfig) -> JSONObject? {
    guard let entry = config.plugins.first(where: { (try? entryName($0.object)) == formsPlugin }) else { return nil }
    return entry.object["options"]?["forms"]?.objectValue ?? JSONObject()
  }

  func collectContent(_ project: URL) throws -> Collected? {
    let dir = ContentFolder.path(project: project).path
    let names = Self.listFilesDeep(dir)
    if names.isEmpty { return nil }
    var entries: [ZipArchive.Entry] = []
    var bytes = 0
    for name in names {
      let data = try Data(contentsOf: URL(fileURLWithPath: NodePath.join(dir, name)))
      bytes += data.count
      if bytes > Self.contentMaxBytes { throw TemplateFailure(message: L10n.t("main.templateContentTooLarge", ["limit": String(Self.contentMaxBytes / 1024 / 1024)])) }
      entries.append(ZipArchive.Entry(name: "files/content/\(name)", data: data))
    }
    return Collected(payload: .object(JSONObject([("files", .array(names.map(JSONValue.string)))])), files: entries,
                     stats: JSONObject([("files", .number(Double(names.count))), ("kilobytes", .number(JS.round(Double(bytes) / 1024)))]))
  }

  func planContent(_ payload: JSONValue, _ run: Run) async throws -> PartPlan {
    var plan = PartPlan(id: "content")
    if try ContentFolder.status(project: run.project).isSymlink {
      plan.notes.append("contentIsSymlink")
      return plan
    }
    let dir = ContentFolder.path(project: run.project).path
    let files = try Self.names(payload["files"], "files")
    for name in files {
      guard let target = PackagePaths.writable(dir, name) else {
        plan.notes.append("outside:\(name)")
        continue
      }
      guard Self.exists(target) else {
        plan.additions.append(.string(name))
        continue
      }
      if let incoming = run.files["files/content/\(name)"], incoming == FileManager.default.contents(atPath: target) { plan.notes.append("identical:\(name)") }
      else { plan.conflicts.append(.string(name)) }
    }
    // Pages that embed a form the project's quartz-forms lacks stop its build.
    if let have = Self.formsOf(try await readConfig(run.project)) {
      var missing: [String] = []
      for name in files where JSText.endsWith(name, ".md") {
        let text = run.files["files/content/\(name)"].map { String(decoding: $0, as: UTF8.self) } ?? ""
        for match in JSText.matches(text, Self.formBlock) {
          let id = match.groups[1]!
          if !Self.hasKey(have, id) && !missing.contains(id) { missing.append(id) }
        }
      }
      if !missing.isEmpty { plan.notes.append("formsMissing:\(missing.joined(separator: ","))") }
    }
    return plan
  }

  func applyContent(_ payload: JSONValue, _ run: Run) throws {
    let status = try ContentFolder.status(project: run.project)
    if status.isSymlink {
      run.warn("contentIsSymlink:\(status.symlinkTarget ?? "")")
      return
    }
    let dir = ContentFolder.path(project: run.project).path
    var done = 0
    for name in try Self.names(payload["files"], "files") {
      guard let data = run.files["files/content/\(name)"] else { continue }
      guard let target = PackagePaths.writable(dir, name) else {
        run.warn("fileOutsideProject:\(name)")
        continue
      }
      if Self.exists(target) {
        if data == FileManager.default.contents(atPath: target) { continue }
        if run.strategy == .projectWins {
          run.warn("contentSkipped:\(name)")
          continue
        }
      }
      try Self.write(data, to: target)
      done += 1
      if done % 25 == 0 { run.progress("content:\(done)") }
    }
  }
}

/// A part that refuses to be collected (the static and content ceilings).
public struct TemplateFailure: Error, Equatable, CustomStringConvertible {
  public let message: String
  public var description: String { "Error: " + message }
}
