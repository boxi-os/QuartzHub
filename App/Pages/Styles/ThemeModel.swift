import QuartzHubCore
import SwiftUI

/// The services the Community-Themes tab shares across windows.
@MainActor
enum ThemeServices {
  /// Obsidian's theme list: what core 3 looks a name up in.
  static let catalog = ThemeCatalog(profile: AppProfile.own)
  static let screenshots = ThemeScreenshots(profile: AppProfile.own)
}

/// Community-Themes with `@quartz-themes/core` 3 (docs/plan-themes-core-3.md, step 6): what the
/// list and the inspector share. The entry itself lives in the Styles page's config draft and is
/// saved with the page; this holds what is read about it: the catalog, the theme as core loads it
/// (`ThemeFetch`), its Style Settings, the presets and what `ThemeLegacy` would clear away.
@MainActor
@Observable
final class ThemeModel {
  let styles: StylesModel

  private(set) var listing: ThemeCatalog.Listing?
  private(set) var catalogLoading = false
  /// The list was asked for and neither the network nor a copy had it.
  private(set) var catalogMissing = false

  enum Load: Equatable {
    case idle
    case loading
    case loaded(ThemeFetch.Theme)
    /// core's own sentence, or why core could not be asked.
    case failed(String)
  }
  private(set) var load = Load.idle
  /// The Style Settings as core reads them; nil while loading or without a loaded theme.
  private(set) var schema: JSONValue?
  private(set) var info: ThemeStyleSettingsInfo?

  private(set) var presets: [JSONValue] = []
  private(set) var legacy = ThemeLegacy.Findings.none
  private(set) var cleaning = false
  /// A cleanup's outcome when it was not all good, or a failure; said in the section.
  var cleanupMessage: String?

  init(styles: StylesModel) {
    self.styles = styles
  }

  // MARK: The entry

  static let entrySource = "@quartz-themes/core"
  /// Selection ids of the rows that are no catalog theme; a theme name of the list never starts
  /// with a NUL.
  static let builtInRow = "\u{0}builtin"
  static let otherRow = "\u{0}other"

  private var config: QuartzConfig { styles.config ?? QuartzConfig() }
  /// Found whether it is on or not: a disabled entry is offered back rather than "no theme".
  var entryIndex: Int? { config.plugins.firstIndex(where: FontDelivery.isThemePlugin) }
  var entry: PluginEntry? { entryIndex.map { config.plugins[$0] } }
  var enabled: Bool { entry.map(FontDelivery.enabled) ?? false }
  var options: JSONObject { entry?.object["options"]?.objectValue ?? JSONObject() }
  /// The `theme:` value as written.
  var spec: String? { options["theme"]?.stringValue }

  /// The catalog's entry the spec names (as core finds it: by repo, name, case, slug), or for a
  /// 2.x id like `catppuccin.frappe`, the one core named when it loaded it.
  var catalogTheme: ThemeCatalog.Theme? {
    guard let spec, let themes = listing?.themes else { return nil }
    if let found = ThemeCatalog.find(spec, in: themes) { return found }
    if case .loaded(let theme) = load, ThemeSource.kind(of: spec) == .catalog { return themes.first { $0.name == theme.name } }
    return nil
  }

  var isBuiltIn: Bool { spec.map(ThemeSource.isBuiltIn) ?? false }

  /// The list row that stands for the project's theme.
  var activeRow: String? {
    guard spec != nil else { return nil }
    if isBuiltIn { return Self.builtInRow }
    return catalogTheme?.name ?? Self.otherRow
  }

  /// What decides which CSS is loaded: every option but the values and the mode.
  var fetchKey: String {
    guard styles.features.themesCore3, enabled else { return "" }
    var opts = options
    opts["styleSettings"] = nil
    opts["mode"] = nil
    return JSJSON.compact(.object(opts))
  }

  func updateEntry(_ change: (inout JSONObject) -> Void) {
    var next = config
    var object = entry?.object ?? JSONObject([("source", .string(Self.entrySource)), ("enabled", .bool(true)),
                                              ("options", .object(JSONObject([("mode", .string("both"))])))])
    var opts = object["options"]?.objectValue ?? JSONObject()
    change(&opts)
    object["options"] = .object(opts)
    if let entryIndex { next.plugins[entryIndex] = PluginEntry(object: object) } else { next.plugins.append(PluginEntry(object: object)) }
    styles.setConfig(next)
  }

  /// Makes `spec` the theme and turns the entry on. A release pin and a 2.x variation belonged to
  /// the theme before; Style Settings and snippets stay (their keys name their own theme).
  func use(_ spec: String) {
    let changes = StylesModel.trim(spec) != StylesModel.trim(self.spec ?? "")
    updateEntry { opts in
      opts["theme"] = .string(spec)
      if changes {
        opts["version"] = nil
        opts["variation"] = nil
      }
    }
    setEnabled(true)
  }

  func setEnabled(_ on: Bool) {
    guard let entryIndex else { return }
    var next = config
    next.plugins[entryIndex].object["enabled"] = .bool(on)
    styles.setConfig(next)
  }

  func setOption(_ key: String, _ value: JSONValue?) {
    updateEntry { $0[key] = value }
  }

  /// One patch at a time on one copy.
  func applyStyleSettings(_ patch: [(key: String, value: JSONValue?)]) {
    updateEntry { opts in
      let next = StyleSettingsValues.apply(patch, to: opts["styleSettings"]?.objectValue ?? JSONObject())
      opts["styleSettings"] = next.keys.isEmpty ? nil : .object(next)
    }
  }

  // MARK: Reading

  func loadCatalog(refresh: Bool = false) async {
    catalogLoading = true
    if refresh { await ThemeServices.catalog.invalidate() }
    listing = await ThemeServices.catalog.list()
    catalogMissing = listing == nil
    catalogLoading = false
  }

  /// The theme as the build loads it (`theme-fetch`), its Style Settings as core reads them.
  func loadTheme() async {
    let key = fetchKey
    schema = nil
    info = nil
    guard !key.isEmpty else {
      load = .idle
      return
    }
    load = .loading
    let outcome: Load
    do throws(ThemeFetch.Failure) {
      let answer = try await ThemeFetch.fetch(project: styles.project.path, options: options)
      switch answer.outcome {
      case .loaded(let theme): outcome = .loaded(theme)
      case .notLoaded(let sentence): outcome = .failed(sentence)
      }
    } catch {
      outcome = .failed(error.description)
    }
    guard key == fetchKey else { return }
    if case .loaded(let theme) = outcome {
      let author = await ThemeServices.catalog.list().flatMap { ThemeCatalog.find(theme.name, in: $0.themes) }?.author
      guard key == fetchKey else { return }
      schema = StyleSettingsSchema.schema(of: theme, author: author)
      info = StyleSettingsSchema.info(of: schema ?? .null)
    }
    load = outcome
  }

  func reloadPresets() async {
    let path = styles.project.path
    presets = await Task.detached { ThemePresets.list(project: path) }.value
  }

  /// Against the config on disk: the cleanup writes it, and what is only in the draft is not there.
  func findLegacy() async {
    guard styles.features.themesCore3, let onDisk = styles.configOnDisk else {
      legacy = ThemeLegacy.Findings.none
      return
    }
    let path = styles.project.path
    let schema = schema
    legacy = await Task.detached { ThemeLegacy.find(project: path, config: onDisk, schema: schema) }.value
  }

  /// `ThemeLegacy.clean` with the real npm and snapshot store; the page reads the config again.
  func clean() async {
    guard !styles.dirty, !cleaning else { return }
    cleaning = true
    cleanupMessage = nil
    let environment = await AppServices.current()
    do {
      let outcome = try await ThemeLegacy.clean(project: styles.project.path, schema: schema, runtime: environment.runtime,
                                                npm: TemplatePackage.npm(environment: environment),
                                                snapshot: SnapshotStore.live(environment: environment).take)
      if let failure = outcome.npmFailure {
        cleanupMessage = L10n.t("themes.cleanup.npmFailed", ["output": failure])
        Announce.post(cleanupMessage!)
      } else {
        Announce.post(L10n.t("themes.cleanup.done"))
      }
    } catch {
      cleanupMessage = StylesModel.message(error)
      Announce.post(cleanupMessage!)
    }
    await styles.load()
    cleaning = false
    await findLegacy()
  }
}
