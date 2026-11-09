import Foundation
import QuartzHubCore

/// Everything the Styles page edits, for all four tabs at once (QuartzControl's
/// `routes/Styles/index.tsx`): the four tabs write two places, quartz.config.yaml and the project's
/// stylesheets, so a draft on one tab survives a switch to another, the line under the tabs can say
/// what the others hold, and the page has one "Speichern" that writes everything `dirty` counts.
///
/// The page owns its documents (docs/conventions.md): read when it appears, `dirty` a comparison
/// with what was read, read again after every write of its own.
@MainActor @Observable
final class StylesModel {
  enum Tab: String, CaseIterable, Identifiable {
    case basics, theme, variables, customCss
    var id: String { rawValue }

    var title: String {
      switch self {
      case .basics: L10n.t("styles.tabs.basics")
      case .theme: L10n.t("styles.tabs.theme")
      case .variables: L10n.t("styles.tabs.variables")
      case .customCss: L10n.t("styles.tabs.customCss")
      }
    }
  }

  /// What can rewrite custom.scss or `_quartzcontrol.scss` while the CSS tab holds a draft of it.
  enum Writer: String { case variables, fontImport, fontRemoval, googleFonts, stylesheets }

  enum Status { case idle, saving, saved, failed }

  /// custom.scss as the page holds it. `original` is what the file held when last read, so `dirty`
  /// stays a comparison; `staleBy` says what rewrote the file under an unsaved draft.
  struct Scss: Equatable {
    var info: StyleSheets.Info
    var content: String
    var original: String
    var staleBy: Writer?
    var dirty: Bool { content != original }
  }

  static let managedStylesheet = "_quartzcontrol.scss"

  let project: ProjectContext

  private(set) var config: QuartzConfig?
  private var savedConfig: QuartzConfig?
  /// The config on disk still has Quartz download the Google fonts at build time (`cdnCaching:
  /// false` without the app's block): the switch reads "served locally", and the next save fetches
  /// them into the project.
  private(set) var quartzStillDownloadsFonts = false
  private(set) var overrides: [(key: String, value: VariableResolve.Override)] = []
  private var savedOverrides: [(key: String, value: VariableResolve.Override)] = []
  private(set) var scss: Scss?
  /// What rewrote `_quartzcontrol.scss` under its unsaved draft.
  private(set) var managedStale: Writer?
  private(set) var fileSet: StyleFiles.FileSet?
  /// Unsaved editor content per relativePath: only files someone typed in.
  private(set) var fileDrafts: [String: String] = [:]
  /// What the opened stylesheets hold on disk, so "changed" is a comparison; read when a file's
  /// editor tab opens, updated from what a save wrote.
  private(set) var loadedFiles: [String: String] = [:]
  private(set) var graph: VariableGraph.Graph?
  private(set) var graphLoading = true
  private var graphRound = 0

  private(set) var loadError: String?
  private(set) var status = Status.idle
  /// The save's own sentence when it failed or was refused.
  private(set) var message: String?
  /// What the last save did without asking (Google fonts chosen away, a line put back). Stays
  /// until the next save, because it names something that changed.
  private(set) var fontNote: String?

  init(project: ProjectContext) {
    self.project = project
  }

  // MARK: Reading

  /// The config and the stylesheets together: whether the Google fonts live in the project is the
  /// block in the stylesheets. The file list and the overrides may fail without stopping the page.
  func load() async {
    let environment = await AppServices.current()
    let path = project.path
    do {
      let loaded = try await ConfigFile.read(project: path, runtime: environment.runtime)
      let info = try await Task.detached { try StyleSheets.readCustom(project: path) }.value
      let presented = FontDelivery.present(loaded, scss: "\(info.managed?.content ?? "")\n\(info.content)")
      config = presented
      savedConfig = presented
      quartzStillDownloadsFonts = FontDelivery.fetchesGoogleFonts(loaded) && presented == loaded
      scss = Scss(info: info, content: info.content, original: info.content, staleBy: nil)
      loadError = nil
    } catch {
      loadError = Self.message(error)
      return
    }
    fileSet = try? await Task.detached { try StyleFiles.list(project: path) }.value
    let list = (try? await Task.detached { try StyleSheets.variableOverrides(project: path) }.value) ?? []
    // An empty dark, not a copy of light: the dark half is optional, and what goes back to the file
    // is this same list. A dark that repeats light is dropped on the way in (QuartzControl).
    overrides = list.map { o in
      (o.key, VariableResolve.Override(light: o.light, dark: o.dark == o.light ? "" : (o.dark ?? ""), lightOnly: o.lightOnly))
    }
    savedOverrides = overrides
  }

  /// The variable table: read again when the theme changes or someone asks after a build.
  func reloadGraph() async {
    guard let config else { return }
    graphRound += 1
    let mine = graphRound
    graphLoading = true
    let path = project.path
    let themeId = FontDelivery.activeThemeId(config)
    let read = try? await Task.detached { try VariableGraph.graph(project: path, themeId: themeId) }.value
    guard mine == graphRound else { return }
    graph = read
    graphLoading = false
  }

  /// Creating, renaming, reordering and deleting a stylesheet act on disk at once: only a file's
  /// content is a draft.
  func reloadFiles() async {
    let path = project.path
    fileSet = try? await Task.detached { try StyleFiles.list(project: path) }.value
  }

  /// After something wrote custom.scss or `_quartzcontrol.scss` behind the CSS tab: an unsaved
  /// draft is never dropped silently. It stays, flagged with what wrote its file, when that file
  /// changed on disk; `force` (nil) drops it.
  func reloadScss(after writer: Writer?) async {
    let path = project.path
    let read = Task.detached { try StyleSheets.readCustom(project: path) }
    guard let info = try? await read.value else { return }
    let previousManaged = scss?.info.managed?.content
    if var current = scss, current.dirty, let writer {
      current.staleBy = info.content != current.original ? writer : current.staleBy
      current.original = info.content
      current.info = info
      scss = current
    } else {
      scss = Scss(info: info, content: info.content, original: info.content, staleBy: nil)
    }
    if writer == nil {
      managedStale = nil
    } else if fileDrafts[Self.managedStylesheet] != nil, info.managed?.content != previousManaged {
      managedStale = writer
    }
  }

  // MARK: Editing

  var dirty: Bool {
    (savedConfig != nil && config != savedConfig) || !Self.same(overrides, savedOverrides) || (scss?.dirty ?? false) || !fileDrafts.isEmpty
  }

  var saving: Bool { status == .saving }

  static func same(_ a: [(key: String, value: VariableResolve.Override)], _ b: [(key: String, value: VariableResolve.Override)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
  }

  func setConfig(_ next: QuartzConfig) {
    config = next
  }

  func setOverrides(_ next: [(key: String, value: VariableResolve.Override)]) {
    overrides = next
  }

  /// One variable's override in place, a new one at the end, nil takes it out (an object's keys
  /// in JavaScript).
  func setOverride(_ key: String, _ value: VariableResolve.Override?) {
    if let index = overrides.firstIndex(where: { $0.key == key }) {
      if let value { overrides[index].value = value } else { overrides.remove(at: index) }
    } else if let value {
      overrides.append((key, value))
    }
  }

  func setScssContent(_ content: String) {
    scss?.content = content
  }

  func setFileDraft(_ relativePath: String, _ content: String) {
    fileDrafts[relativePath] = content
  }

  func setLoaded(_ relativePath: String, _ content: String) {
    loadedFiles[relativePath] = content
  }

  func clearFileDrafts(_ relativePaths: [String]) {
    for path in relativePaths { fileDrafts[path] = nil }
  }

  /// The banner's "reload" for `_quartzcontrol.scss`.
  func discardManagedDraft() {
    fileDrafts[Self.managedStylesheet] = nil
    managedStale = nil
  }

  // MARK: Saving

  /// The page's one save, from whichever tab is in front: custom.scss as a whole first (the block
  /// writers after it replace one block each, and in the other order the draft would put the old
  /// blocks back), then the other stylesheets, the config with the Google fonts, the variables.
  /// A draft of custom.scss or `_quartzcontrol.scss` that something wrote under is written only
  /// from the CSS tab, where the banner says so. `written` is handed to `after`: the drafts that
  /// reached disk, by relativePath. Returns whether everything was written.
  @discardableResult
  func save(from tab: Tab, after: ([String: String]) async -> Void = { _ in }) async -> Bool {
    guard let config, let scss, !saving else { return false }
    status = .saving
    message = nil
    fontNote = nil
    let environment = await AppServices.current()
    let path = project.path
    var blocksWritten: Writer?
    var draftsWritten: [String: String] = [:]
    var managedReloaded = false

    func commitDrafts() async {
      clearFileDrafts(Array(draftsWritten.keys))
      for (path, content) in draftsWritten where path != Self.managedStylesheet { loadedFiles[path] = content }
      if let managed = draftsWritten[Self.managedStylesheet], !managedReloaded, var current = self.scss, let info = current.info.managed {
        current.info.managed = (info.path, managed)
        self.scss = current
      }
      await after(draftsWritten)
    }

    do {
      let configDirty = config != savedConfig || quartzStillDownloadsFonts
      let overridesDirty = !Self.same(overrides, savedOverrides)
      // Asked before the first write, so a value the file cannot hold stops the save as a whole.
      if overridesDirty, let bad = overrides.first(where: { !CssVariables.isWritable($0.value.light) || !CssVariables.isWritable($0.value.dark) }) {
        status = .failed
        message = L10n.t("styles.variableNotWritable", ["name": bad.key])
        return false
      }
      let scssRefused = scss.dirty && scss.staleBy != nil && tab != .customCss
      let managedRefused = fileDrafts[Self.managedStylesheet] != nil && managedStale != nil && tab != .customCss
      if scss.dirty && !scssRefused {
        let content = scss.content
        let restored = try await StyleSheets.saveCustom(content, project: path)
        // Said, because the editor shows a line after the save that the user had just deleted.
        if restored { fontNote = L10n.t("styles.managedUseRestored") }
      }
      for (relativePath, draft) in fileDrafts.sorted(by: { $0.key < $1.key }) {
        if relativePath == Self.managedStylesheet && managedRefused { continue }
        try await StyleFiles.write(relativePath, draft, project: path)
        draftsWritten[relativePath] = draft
        if relativePath == Self.managedStylesheet { managedStale = nil }
      }
      if configDirty {
        try await saveConfig(config, environment: environment) { blocksWritten = .googleFonts }
        savedConfig = config
      }
      if overridesDirty {
        // A row whose fields were both emptied is no override: the file gets nothing for it, and
        // the page drops it too.
        let kept = overrides.filter { !Self.trim($0.value.light).isEmpty || !Self.trim($0.value.dark).isEmpty }
        let list = kept.map { VariableOverride(key: $0.key, light: $0.value.light, dark: $0.value.dark, lightOnly: $0.value.lightOnly) }
        try await StyleSheets.saveVariableOverrides(list, project: path)
        blocksWritten = .variables
        overrides = kept
        savedOverrides = kept
      }
      if scssRefused || managedRefused {
        // Re-read under the writer's name, so the refused draft keeps its banner.
        if configDirty { await reloadScss(after: .googleFonts) } else if overridesDirty { await reloadScss(after: .variables) }
        managedReloaded = configDirty || overridesDirty
      } else if scss.dirty || configDirty || overridesDirty {
        await reloadScss(after: nil)
        managedReloaded = true
      }
      await commitDrafts()
      if scssRefused || managedRefused {
        status = .failed
        message = scssRefused ? L10n.t("styles.scssStaleNotSaved") : L10n.t("styles.managedStaleNotSaved")
        return false
      }
      status = .saved
      Announce.post(L10n.t("common.saved"))
      Task {
        try? await Task.sleep(for: .seconds(2))
        if status == .saved { status = .idle }
      }
      return true
    } catch {
      // A step after the block writers can fail with custom.scss already rewritten: the draft is
      // flagged stale, so the next save does not put the old block back.
      if let blocksWritten { await reloadScss(after: blocksWritten) }
      if !draftsWritten.isEmpty { await commitDrafts() }
      status = .failed
      message = Self.message(error)
      return false
    }
  }

  /// The fonts first and the config after: a fetch that fails leaves the config as it was rather
  /// than one that says `local` over a block that is not there.
  private func saveConfig(_ config: QuartzConfig, environment: ToolEnvironment, blockWritten: () -> Void) async throws {
    let path = project.path
    let fonts = FontService(readConfig: { try await ConfigFile.read(project: $0, runtime: environment.runtime) })
    if FontDelivery.fetchesGoogleFonts(config) {
      let result = try await fonts.fetchGoogleFonts(config.theme["typography"]?.objectValue ?? JSONObject(), project: path)
      blockWritten()
      var notes: [String] = []
      if result.changed && !result.ownFamilies.isEmpty {
        notes.append(L10n.t("styles.googleFontsOwn", ["families": result.ownFamilies.joined(separator: ", ")], count: result.ownFamilies.count))
      }
      if result.changed && !result.coveredFamilies.isEmpty {
        notes.append(L10n.t("styles.googleFontsCovered", ["families": result.coveredFamilies.joined(separator: ", ")], count: result.coveredFamilies.count))
      }
      if !result.removedFamilies.isEmpty {
        notes.append(L10n.t("styles.googleFontsRemoved", ["families": result.removedFamilies.joined(separator: ", ")], count: result.removedFiles.count))
      }
      if result.removedFamilies.isEmpty && !result.removedFiles.isEmpty {
        notes.append(L10n.t("styles.googleFontsFilesRemoved", count: result.removedFiles.count))
      }
      if !result.missingFamilies.isEmpty {
        notes.append(L10n.t("styles.googleFontsMissing", ["families": result.missingFamilies.joined(separator: ", ")], count: result.missingFamilies.count))
      }
      // As QuartzControl: these replace the sentence about the restored line, which is rarer.
      if !notes.isEmpty { fontNote = notes.joined(separator: " ") }
    } else {
      let result = try await fonts.dropGoogleFonts(project: path)
      blockWritten()
      if !result.removedFiles.isEmpty { fontNote = L10n.t("styles.googleFontsDropped", count: result.removedFiles.count) }
    }
    try await ConfigFile.write(FontDelivery.persist(config), project: path, runtime: environment.runtime,
                               snapshot: SnapshotStore.live(environment: environment).take)
    quartzStillDownloadsFonts = false
  }

  // MARK: Moving the blocks

  /// The one door to 1.1's form (`_quartzcontrol.scss`), with a snapshot first: the way back for a
  /// machine that stays on 1.0.x. Not while the page holds drafts: the move rewrites custom.scss.
  func migrate() async throws {
    let environment = await AppServices.current()
    _ = try await StyleSheets.migrate(project: project.path, snapshot: StyleFiles.snapshot(SnapshotStore.live(environment: environment).take))
    await reloadScss(after: nil)
    await reloadFiles()
    fontNote = L10n.t("styles.migrate.done")
  }

  // MARK: Helpers

  var context: VariableResolve.Context {
    VariableResolve.Context(vars: graph?.vars, overrides: overrides, colors: config?.theme["colors"]?.objectValue ?? JSONObject(),
                            typography: config?.theme["typography"]?.objectValue)
  }

  /// JavaScript's `trim`, near enough for a field: whitespace and line ends at both ends.
  static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  static func message(_ error: Error) -> String {
    if let failure = error as? ConfigFile.Failure { return failure.message }
    if let failure = error as? FontService.Failure { return failure.message }
    return String(describing: error)
  }
}
