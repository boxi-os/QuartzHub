import Foundation

/// The custom properties plugins bring that are not global: declared at a plugin's own selector
/// (`.quartz-nav`, `.quartz-form`), so `VariableGraph`, which reads `:root` only, never sees them.
/// For the Variables tab's "Plugin-Variablen" (docs/plan-plugin-variablen.md, A2).
///
/// Two sources, and the answer says which one answered:
/// - **A catalogue** in the plugin's manifest, `quartz.cssVariables` (QuartzHub's own plugins since
///   quartz-navigations 0.7.0 and quartz-forms 0.7.0): groups with labels in English and German and
///   per variable its selector, defaults, kind, group and description, in display order. Needs no
///   build. The same shape serves a template's catalogue (`catalog(_:)`).
/// - **The last build**: Quartz emits component CSS inside `@layer quartz-base`
///   (measured in gui-test's build, 2026-11-21), so a layered rule with a selector that is not
///   global is a plugin's (or Quartz's own), an unlayered one the project's (template, custom.scss,
///   QuartzHub's blocks). A layered variable no catalogue lists goes to the plugin whose package
///   files declare it (`--name:`; an npm plugin ships its CSS as a string in `dist/`); one that no
///   package declares is `unattributed`.
///
/// Rules inside `@media` are left out: they are an exception to a value, not the value (the same
/// rule as `VariableGraph`'s for `:root`).
public enum PluginVariables {
  public struct Group: Equatable, Sendable {
    public var id: String
    public var label: String
    public var labelDe: String
  }

  /// A rule of the project's that sets the variable too, read from the build.
  public struct Setter: Equatable, Sendable {
    public var selector: String
    /// `light` or `dark`.
    public var mode: String
    public var value: String
    /// The rule's whole selector as the build has it, the mode prefix included: what its
    /// specificity is counted from.
    public var rule: String

    public init(selector: String, mode: String, value: String, rule: String? = nil) {
      self.selector = selector
      self.mode = mode
      self.value = value
      self.rule = rule ?? selector
    }
  }

  public struct Variable: Equatable, Sendable {
    public var name: String
    /// Where the plugin declares it; an override is written to this selector.
    public var selector: String
    /// The plugin's own values: from its catalogue, else from its layered rules in the build.
    public var light: String?
    public var dark: String?
    /// `color`, `length`, `number`, `font`, `time`, `other`; nil when nothing describes it.
    public var kind: String?
    public var group: String?
    public var description: String?
    public var descriptionDe: String?
    /// Further selectors the plugin's own rules set it at (a callout type, a state).
    public var alsoAt: [String] = []
    /// Unlayered rules of the project that set it as well.
    public var setBy: [Setter] = []
  }

  public struct Plugin: Equatable, Sendable {
    /// The name QuartzHub shows a plugin by elsewhere (`PluginSource.quartzName`).
    public var name: String
    public var displayName: String?
    /// From the catalogue; empty for a plugin read from the build only.
    public var groups: [Group]
    public var variables: [Variable]
    /// Whether a catalogue described it (groups, kinds, descriptions).
    public var described: Bool

    public init(name: String, displayName: String?, groups: [Group], variables: [Variable], described: Bool) {
      self.name = name
      self.displayName = displayName
      self.groups = groups
      self.variables = variables
      self.described = described
    }
  }

  public struct Result: Equatable, Sendable {
    public var plugins: [Plugin]
    public var unattributed: [Variable]
    public var sources: (manifest: Bool, build: Bool)

    public static func == (a: Result, b: Result) -> Bool {
      a.plugins == b.plugins && a.unattributed == b.unattributed && a.sources == b.sources
    }
  }

  // MARK: The catalogue

  /// `quartz.cssVariables` (or a template's catalogue): `{ groups: [...], variables: [...] }`.
  /// Entries without a name, or without a selector when no `defaultSelector` is given, are skipped;
  /// nil when there is no usable list.
  public static func catalog(_ value: JSONValue?, defaultSelector: String? = nil) -> (groups: [Group], variables: [Variable])? {
    guard let object = value?.objectValue, let list = object["variables"]?.arrayValue else { return nil }
    let groups: [Group] = (object["groups"]?.arrayValue ?? []).compactMap { entry in
      guard let g = entry.objectValue, let id = g["id"]?.stringValue, !id.isEmpty else { return nil }
      let label = g["label"]?.stringValue ?? id
      return Group(id: id, label: label, labelDe: g["label_de"]?.stringValue ?? label)
    }
    var seen = Set<String>()
    let variables: [Variable] = list.compactMap { entry in
      guard let v = entry.objectValue, let raw = v["name"]?.stringValue, let selector = v["selector"]?.stringValue ?? defaultSelector,
            !JS.trim(selector).isEmpty else { return nil }
      let name = JSText.replaceAll(JS.trim(raw), #"\A--"#, with: "")
      guard JSText.test(name, #"\A[A-Za-z0-9_-]+\z"#), seen.insert(name).inserted else { return nil }
      return Variable(name: name, selector: JS.trim(selector), light: v["default"]?.stringValue, dark: v["defaultDark"]?.stringValue,
                      kind: v["kind"]?.stringValue, group: v["group"]?.stringValue, description: v["description"]?.stringValue,
                      descriptionDe: v["description_de"]?.stringValue)
    }
    return variables.isEmpty ? nil : (groups, variables)
  }

  // MARK: Reading

  /// One declaration of a variable in the build: at which selector, in which mode, with what value.
  struct Declared {
    var selector: String
    var mode: String
    var value: String
    var rule: String = ""
  }

  /// The mode a scoped selector is for and the selector without the mode prefix:
  /// `:root[saved-theme=dark] .quartz-nav` is `.quartz-nav` in dark. A list of selectors keeps its
  /// text and counts as light.
  static func scopedMode(_ selector: String) -> (selector: String, mode: String) {
    let trimmed = JS.trim(selector)
    guard !JSText.includes(trimmed, ","),
          let match = JSText.firstMatch(trimmed, #"\A(?::root|html)?"# + VariableGraph.savedTheme + "[\(JSText.space)]+") else {
      return (trimmed, "light")
    }
    return (JS.trim(JSText.slice(trimmed, match.range.location + match.range.length)), match.groups[1] ?? "light")
  }

  /// Reads the plugins' variables. `plugins`: the enabled ones, in the config's order, duplicates
  /// allowed (a plugin with several entries counts once). Quartz's own stylesheets are asked
  /// before any plugin and answer as the plugin `quartz` ("Quartz"): gui-test's callout variables
  /// (`--callout-icon-*`, `--bg` at `.callout`) are Quartz's, and quartz-themes' package text names
  /// some of them too (measured 2026-11-21).
  public static func read(project: String, plugins: [PluginSource], outputDir: String? = nil) -> Result {
    // The build: layered and unlayered declarations at selectors that are not global. A name that
    // starts with "_" is a plugin's private helper (`--_size` in quartz-navigations), not a setting.
    var layered: [(name: String, Declared)] = []
    var unlayered: [(name: String, Declared)] = []
    var seenLayered = Set<String>(), seenUnlayered = Set<String>()
    let buildDir = BuildOutputGuard.buildDirectory(project: project, outputDir: outputDir)
    let hasBuild = FileManager.default.fileExists(atPath: buildDir)
    if hasBuild {
      for file in VariableGraph.cssFiles(buildDir).prefix(50) {
        let content = (try? StyleSheets.readText(file)) ?? ""
        VariableGraph.eachRule(content) { selector, body, context in
          guard !context.conditional, VariableGraph.rootMode(selector) == nil else { return }
          let (base, mode) = scopedMode(selector)
          for (name, value) in VariableGraph.declarations(body) where !name.hasPrefix("_") {
            // A component's CSS reaches the build twice (its own file and index-<hash>.css).
            if context.layered {
              if seenLayered.insert("\(name)\u{0}\(base)\u{0}\(mode)").inserted { layered.append((name, Declared(selector: base, mode: mode, value: value))) }
            } else if seenUnlayered.insert("\(name)\u{0}\(base)\u{0}\(mode)\u{0}\(value)").inserted {
              unlayered.append((name, Declared(selector: base, mode: mode, value: value, rule: JS.trim(selector))))
            }
          }
        }
      }
    }
    let layeredNames = orderedNames(layered.map(\.name))

    var result: [Plugin] = []
    var claimed = Set<String>()
    var seenDirs = Set<String>()
    var anyCatalog = false
    var packages: [(plugin: Int, dir: String)] = []
    for source in plugins {
      guard let dir = PluginSchemaReader.packageDirectory(project: project, source: source), seenDirs.insert(dir).inserted,
            case .read(let package) = PluginSchemaReader.readPackage(dir) else { continue }
      var plugin = Plugin(name: source.quartzName, displayName: package.quartz["displayName"]?.stringValue, groups: [], variables: [], described: false)
      if let listed = catalog(package.quartz["cssVariables"]) {
        anyCatalog = true
        plugin.described = true
        plugin.groups = listed.groups
        plugin.variables = listed.variables.filter { claimed.insert($0.name).inserted }
      }
      result.append(plugin)
      packages.append((result.count - 1, dir))
    }

    // Layered variables no catalogue lists: Quartz's own first, then the first plugin whose
    // package declares them; each package's declared names are collected once.
    var unattributed: [Variable] = []
    var quartzOwn: [Variable] = []
    let open = layeredNames.filter { !claimed.contains($0) }
    if !open.isEmpty {
      let core = declaredNames(NodePath.join(project, "quartz"), skip: quartzSkip)
      var names: [Int: Set<String>] = [:]
      for name in open {
        let variable = fromBuild(name, layered)
        if core.contains(name) { quartzOwn.append(variable); continue }
        var owner: Int?
        for (index, dir) in packages {
          let declared = names[index] ?? { let n = declaredNames(dir); names[index] = n; return n }()
          if declared.contains(name) { owner = index; break }
        }
        if let owner { result[owner].variables.append(variable) } else { unattributed.append(variable) }
      }
    }
    if !quartzOwn.isEmpty { result.append(Plugin(name: "quartz", displayName: "Quartz", groups: [], variables: quartzOwn, described: false)) }

    // What the build says about every variable: the plugin's further selectors and the project's rules.
    var ownSelectors: [String: [String]] = [:]
    for (name, declared) in layered { ownSelectors[name, default: []].append(declared.selector) }
    var setters: [String: [Setter]] = [:]
    for (name, declared) in unlayered { setters[name, default: []].append(Setter(selector: declared.selector, mode: declared.mode, value: declared.value, rule: declared.rule)) }
    func complete(_ variable: Variable) -> Variable {
      var v = variable
      v.alsoAt = orderedNames((ownSelectors[v.name] ?? []).filter { $0 != v.selector })
      v.setBy = setters[v.name] ?? []
      return v
    }
    for index in result.indices { result[index].variables = result[index].variables.map(complete) }
    unattributed = unattributed.map(complete)
    return Result(plugins: result.filter { !$0.variables.isEmpty }, unattributed: unattributed, sources: (anyCatalog, hasBuild))
  }

  /// What in `quartz/` is not Quartz's own: the project's stylesheets and the transpiled cache,
  /// which holds a copy of everything.
  static func quartzSkip(_ relative: String) -> Bool {
    let skipped = [".quartz-cache", "node_modules", "styles/custom", "styles/imported", "styles/custom.scss", "styles/_quartzcontrol.scss"]
    return skipped.contains { relative == $0 || relative.hasPrefix($0 + "/") }
  }

  /// A variable known from the build only: its first light selector, with that selector's values.
  static func fromBuild(_ name: String, _ layered: [(name: String, Declared)]) -> Variable {
    let own = layered.filter { $0.name == name }.map(\.1)
    let selector = (own.first { $0.mode == "light" } ?? own[0]).selector
    let at = own.filter { $0.selector == selector }
    return Variable(name: name, selector: selector, light: at.first { $0.mode == "light" }?.value, dark: at.first { $0.mode == "dark" }?.value)
  }

  static func orderedNames(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return names.filter { seen.insert($0).inserted }
  }

  // MARK: What a package declares

  static let packageTextLimit = 32 * 1024 * 1024
  static let packageFileLimit = 8 * 1024 * 1024
  static let packageExtensions: Set<String> = [".js", ".mjs", ".cjs", ".css", ".scss", ".ts", ".tsx"]

  /// Every `--name:` (spaces allowed before the colon) in the CSS-bearing files under `dir`, up to a
  /// limit; for an npm plugin that includes the CSS it ships as a string in `dist/`. Scanned as bytes:
  /// a package can hold megabytes of script (obsidian-plugin-excalidraw). `node_modules` inside a
  /// package is not the plugin's own; `skip` gets the path relative to `dir`.
  static func declaredNames(_ dir: String, skip: (String) -> Bool = { _ in false }) -> Set<String> {
    var names = Set<String>()
    var total = 0
    func isNameByte(_ b: UInt8) -> Bool { (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2D || b == 0x5F }
    func scan(_ bytes: [UInt8]) {
      var i = 0
      let n = bytes.count
      while i + 2 < n {
        guard bytes[i] == 0x2D, bytes[i + 1] == 0x2D, i == 0 || !isNameByte(bytes[i - 1]) else { i += 1; continue }
        var j = i + 2
        while j < n, isNameByte(bytes[j]) { j += 1 }
        var k = j
        while k < n, bytes[k] == 0x20 || bytes[k] == 0x09 { k += 1 }
        if j > i + 2, k < n, bytes[k] == 0x3A, let name = String(bytes: bytes[(i + 2)..<j], encoding: .utf8) { names.insert(name) }
        i = j
      }
    }
    func walk(_ path: String, _ relative: String, _ depth: Int) {
      guard depth <= 8, total < packageTextLimit else { return }
      for entry in LayoutFrames.directoryEntriesWithKind(path) where entry.name != "node_modules" && entry.name != ".git" {
        let full = NodePath.join(path, entry.name)
        let rel = relative.isEmpty ? entry.name : "\(relative)/\(entry.name)"
        if skip(rel) { continue }
        if entry.kind == .directory {
          walk(full, rel, depth + 1)
        } else if packageExtensions.contains(NodePath.extname(entry.name)) {
          var info = stat()
          guard stat(full, &info) == 0, info.st_size <= packageFileLimit, total + Int(info.st_size) <= packageTextLimit,
                let data = FileManager.default.contents(atPath: full) else { continue }
          total += data.count
          scan([UInt8](data))
        }
      }
    }
    walk(dir, "", 0)
    return names
  }
}
