import Foundation

/// Where a site's webfonts come from, and the two switches the Basis tab of the Styles page has
/// for it: a port of `src/routes/Styles/fontDelivery.ts`, with `primaryFamily` and
/// `summarizeFaces` of `fontSpec.ts`, `fontBuildState` of `previewFonts.ts` and the ready-made
/// stylesheets of `cssFixes.ts`. Measured against QuartzControl's code
/// (`scripts/font-delivery-golden.mjs`).
///
/// Three things can load a webfont, and QuartzControl's comment says which and how it was
/// measured: Quartz's own `theme.fontOrigin`/`cdnCaching`, the plugin
/// `@quartz-community/quartz-fonts` with its own `fontOrigin` (default Google), and a community
/// theme's own `@font-face` rules on unpkg (off only with `themeFonts: false`).
///
/// "Served locally" means since QuartzControl 1.0.1: the app fetched the Google fonts into the
/// project, and the config says `fontOrigin: local`. On the page the draft keeps the older spelling
/// (`googleFonts` with `cdnCaching: false`), because that is what the switch and the font fields
/// mean; `present` and `persist` translate on the way in and out.
public enum FontDelivery {
  public static let fontsPluginSource = "@quartz-community/quartz-fonts"
  public static let themePluginPrefix = "@quartz-themes/"

  public struct Loader: Equatable, Sendable, Hashable {
    /// `core`, `plugin` or `theme`.
    public var via: String
    /// `google`, `selfHosted` or `cdn`.
    public var mode: String
  }

  public static func enabled(_ plugin: PluginEntry) -> Bool { JS.truthy(plugin.object["enabled"]) }

  public static func isThemePlugin(_ plugin: PluginEntry) -> Bool {
    if case .string(let source)? = plugin.source { return JSText.startsWith(source, themePluginPrefix) }
    return false
  }

  static func fontsPluginIndex(_ config: QuartzConfig) -> Int? {
    config.plugins.firstIndex { enabled($0) && $0.source == .string(fontsPluginSource) }
  }

  /// The theme plugin, while it emits its font rules.
  static func themeFontsIndex(_ config: QuartzConfig) -> Int? {
    config.plugins.firstIndex { enabled($0) && isThemePlugin($0) && $0.object["options"]?["themeFonts"] != .bool(false) }
  }

  /// Everything that will fetch a webfont for this site. Empty: nothing does.
  public static func loaders(_ config: QuartzConfig) -> [Loader] {
    var loaders: [Loader] = []
    let coreOrigin = config.theme["fontOrigin"]?.stringValue ?? "googleFonts"
    if coreOrigin == "googleFonts" {
      loaders.append(Loader(via: "core", mode: config.theme["cdnCaching"] == .bool(false) ? "selfHosted" : "google"))
    }
    if let index = fontsPluginIndex(config) {
      let origin = config.plugins[index].object["options"]?["fontOrigin"]
      loaders.append(Loader(via: "plugin", mode: origin == .string("selfHosted") ? "selfHosted" : "google"))
    }
    if themeFontsIndex(config) != nil { loaders.append(Loader(via: "theme", mode: "cdn")) }
    return loaders
  }

  public static func themeFontsEnabled(_ config: QuartzConfig) -> Bool { themeFontsIndex(config) != nil }

  /// Whether a theme plugin is on at all.
  public static func hasTheme(_ config: QuartzConfig) -> Bool { config.plugins.contains { enabled($0) && isThemePlugin($0) } }

  /// The theme's own fonts on or off. Not part of the self-hosting switch: there is no option to
  /// serve them locally, so turning them off changes how the site looks.
  public static func withThemeFonts(_ config: QuartzConfig, _ on: Bool) -> QuartzConfig {
    guard let index = config.plugins.firstIndex(where: { enabled($0) && isThemePlugin($0) }) else { return config }
    var next = config
    var options = next.plugins[index].object["options"]?.objectValue ?? JSONObject()
    options["themeFonts"] = on ? nil : .bool(false)
    next.plugins[index].object["options"] = .object(options)
    return next
  }

  public static func callsGoogle(_ config: QuartzConfig) -> Bool { loaders(config).contains { $0.mode == "google" } }

  /// Every loader to its self-hosted spelling, or back: the plugin's `options.fontOrigin`, and
  /// core's `cdnCaching` while core's own fontOrigin is Google's. The plugin is addressed by index.
  public static func withSelfHostedFonts(_ config: QuartzConfig, _ selfHosted: Bool) -> QuartzConfig {
    var next = config
    let origin = config.theme["fontOrigin"]
    if origin == .string("googleFonts") || origin == nil { next.theme["cdnCaching"] = .bool(!selfHosted) }
    if let index = fontsPluginIndex(config) {
      var options = next.plugins[index].object["options"]?.objectValue ?? JSONObject()
      options["fontOrigin"] = .string(selfHosted ? "selfHosted" : "googleFonts")
      next.plugins[index].object["options"] = .object(options)
    }
    return next
  }

  // MARK: Google fonts held by the project

  /// Whether a stylesheet holds the block of Google fonts fetched into the project.
  public static func holdsGoogleFonts(_ scss: String) -> Bool {
    JSText.test(scss, "/\\* --- [\(JSText.word)-]+:managed:google-fonts:start --- \\*/")
  }

  /// On the way in: `local` plus the block reads as "Google, served locally".
  public static func present(_ config: QuartzConfig, scss: String) -> QuartzConfig {
    guard config.theme["fontOrigin"] == .string("local"), holdsGoogleFonts(scss) else { return config }
    var next = config
    next.theme["fontOrigin"] = .string("googleFonts")
    next.theme["cdnCaching"] = .bool(false)
    return next
  }

  /// Whether the draft asks for Google fonts served from the project.
  public static func fetchesGoogleFonts(_ config: QuartzConfig) -> Bool {
    let origin = config.theme["fontOrigin"]
    return (origin == .string("googleFonts") || origin == nil) && config.theme["cdnCaching"] == .bool(false)
  }

  /// On the way out: what the config file says once the fonts are in the project.
  public static func persist(_ config: QuartzConfig) -> QuartzConfig {
    guard fetchesGoogleFonts(config) else { return config }
    var next = config
    next.theme["fontOrigin"] = .string("local")
    return next
  }

  // MARK: The theme

  /// The active community theme's id: the first `@quartz-themes/` plugin, if it is on and names one.
  public static func activeThemeId(_ config: QuartzConfig) -> String? {
    guard let plugin = config.plugins.first(where: isThemePlugin), enabled(plugin) else { return nil }
    return plugin.object["options"]?["theme"]?.stringValue
  }

  // MARK: Families and faces

  /// A typography entry is a bare family or `{ name, weights?, includeItalic? }`.
  public static func familyOf(_ spec: JSONValue?) -> String {
    switch spec {
    case .string(let family)?: return family
    case .object(let object)?: return object["name"]?.stringValue ?? ""
    default: return ""
    }
  }

  /// A font stack's first family, without its quotes.
  public static func primaryFamily(_ stack: String?) -> String {
    let first = JS.trim(stack.map { JSText.split($0, ",")[0] } ?? "")
    return JSText.replaceAll(first, "\\A[\"']|[\"']\\z", with: "")
  }

  public struct FaceSummary: Equatable, Sendable {
    public var weights: [String]
    public var italic: Bool
    public var origins: [String]
  }

  /// What the site has of one family: its weights (a variable range as `100–900`), whether there is
  /// an italic, and where the faces come from.
  public static func summarizeFaces(_ faces: [SiteFonts.Face], family: String) -> FaceSummary? {
    let key = family.lowercased()
    let matching = faces.filter { $0.family.lowercased() == key }
    guard !matching.isEmpty else { return nil }
    var weights: [String] = []
    for face in matching {
      let parts = JSText.split(JS.trim(face.weight), " ").filter { !$0.isEmpty }
      let formatted = parts.count == 2 ? "\(parts[0])–\(parts[1])" : (parts.first ?? "")
      if !weights.contains(formatted) { weights.append(formatted) }
    }
    // A stable sort by JavaScript's parseInt, NaN as 0.
    weights = weights.enumerated().sorted { a, b in
      let x = parseIntOrZero(a.element), y = parseIntOrZero(b.element)
      return x != y ? x < y : a.offset < b.offset
    }.map(\.element)
    var origins: [String] = []
    for face in matching where !origins.contains(face.origin) { origins.append(face.origin) }
    let italic = matching.contains { $0.style.lowercased().contains("italic") || $0.style.lowercased().contains("oblique") }
    return FaceSummary(weights: weights, italic: italic, origins: origins)
  }

  static func parseIntOrZero(_ text: String) -> Double {
    guard let match = JSText.firstMatch(text, "\\A[\(JSText.space)]*([+-]?[0-9]+)"), let digits = match.groups[1] else { return 0 }
    return Double(digits) ?? 0
  }

  // MARK: Whether the fonts are there yet

  public enum BuildState: Equatable, Sendable {
    case notBuilt
    case missing([String])
    case notFetched([String])
    /// Nothing fetches these, and no rule in the project declares them.
    case noRule([String])
  }

  /// Whether the families the site asks for have files yet: under the app's own fetch, in the
  /// project; under the Fonts plugin's `selfHosted`, in the last build; with no loader at all, a
  /// rule of the project's own.
  public static func buildState(_ config: QuartzConfig, faces: [SiteFonts.Face], built: Bool?) -> BuildState? {
    let loaders = loaders(config)
    let heldByProject = loaders.contains { $0.via == "core" && $0.mode == "selfHosted" }
    let pluginAtBuild = loaders.contains { $0.via == "plugin" && $0.mode == "selfHosted" }
    let typography = config.theme["typography"]?.objectValue ?? JSONObject()
    if !heldByProject && !pluginAtBuild {
      if !loaders.isEmpty { return nil }
      let unique = missing(typography, faces.filter { $0.origin != "build" })
      return unique.isEmpty ? nil : .noRule(unique)
    }
    let counted = heldByProject ? faces.filter { $0.origin != "build" } : faces
    let unique = missing(typography, counted)
    if heldByProject { return unique.isEmpty ? nil : .notFetched(unique) }
    guard let built else { return nil }
    if !built { return .notBuilt }
    return unique.isEmpty ? nil : .missing(unique)
  }

  /// The slot families none of `faces` declares, each once.
  static func missing(_ typography: JSONObject, _ faces: [SiteFonts.Face]) -> [String] {
    let have = Set(faces.map { $0.family.lowercased() })
    var out: [String] = []
    for slot in ["header", "body", "code"] {
      guard let family = GoogleFontRequest.request(slot, typography[slot])?.family, !family.isEmpty,
            !have.contains(family.lowercased()), !out.contains(family) else { continue }
      out.append(family)
    }
    return out
  }

  // MARK: Ready-made stylesheets

  /// A conflict this app can see but not settle with a setting, because it is in the cascade: the
  /// fix is a stylesheet the user owns under quartz/styles/custom/. Nothing is applied by itself.
  public struct CssFix: Sendable {
    public var id: String
    public var fileName: String
    public var appliesTo: @Sendable (QuartzConfig) -> Bool
    /// `t` is the catalogue, so the comment follows the app's language.
    public var content: @Sendable (_ t: (String) -> String) -> String
  }

  /// quartz-fonts emits `h1,…,h6 { font-family: … }` unlayered, which beats the theme's layers and
  /// an equally specific rule of the user's; `body hN` is one step more specific and points at the
  /// variables, so the Variablen tab is in control again (QuartzControl measured it in a build).
  public static let headingFontFix = CssFix(
    id: "heading-fonts",
    fileName: "fix-heading-fonts.scss",
    appliesTo: { config in
      config.plugins.contains { enabled($0) && $0.source == .string(fontsPluginSource) } && config.plugins.contains { enabled($0) && isThemePlugin($0) }
    },
    content: { t in
      var lines = ["// \(t("styles.fixes.heading-fonts.title"))", "//"]
      lines += JSText.split(t("styles.fixes.heading-fonts.comment"), "\n").map { "// \($0)" }
      lines.append("")
      lines += (1...6).map { "body h\($0) { font-family: var(--h\($0)-font, var(--headerFont)); }" }
      lines.append("")
      return lines.joined(separator: "\n")
    }
  )

  public static let cssFixes = [headingFontFix]
}

/// Every family Google Fonts served when QuartzControl's list was made, most popular first.
public enum GoogleFontList {
  public enum Category: String, Sendable { case sansSerif = "sans-serif", serif, monospace, display, handwriting }

  public struct Family: Sendable, Equatable {
    public var name: String
    public var category: Category
  }

  public static let families: [Family] = table.split(separator: "\n").compactMap { line in
    let parts = line.split(separator: "\t")
    guard parts.count == 2, let category = Category(rawValue: String(parts[1])) else { return nil }
    return Family(name: String(parts[0]), category: category)
  }

  public static let names: Set<String> = Set(families.map(\.name))

  /// The day the list was fetched, for the sentence under a name it does not know.
  public static var fetchedOn: String { fetched }
}
