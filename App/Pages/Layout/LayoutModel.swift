import Foundation
import QuartzHubCore

/// The Layout page's documents (QuartzControl's `routes/LayoutEditor`): quartz.config.yaml for the
/// overview and the stage, written by "Speichern" like on Konfiguration, and the own frames, each
/// written on its own from the Frames tab. Read when the page appears; "unsaved" is a comparison
/// with what was read.
@MainActor @Observable
final class LayoutModel {
  enum Tab: String, CaseIterable, Identifiable {
    case overview, global, frames
    var id: String { rawValue }

    var title: String {
      switch self {
      case .overview: L10n.t("layoutEditor.tabOverview")
      case .global: L10n.t("layoutEditor.tabGlobal")
      case .frames: L10n.t("layoutEditor.tabFrames")
      }
    }
  }

  enum Status { case idle, saving, saved, failed }

  let project: ProjectContext
  var config: QuartzConfig?
  private(set) var saved: QuartzConfig?
  private(set) var loadError: String?
  private(set) var status = Status.idle
  private(set) var saveError: String?

  /// The project's own frames, in the order of their directory; read with the page.
  private(set) var frames: [FrameView] = []
  private(set) var framesLoaded = false
  /// The frames page type plugins bring, by plugin name (`canvas-page` → `canvas`); nil until asked.
  private(set) var pluginFrames: [String: String]?
  private(set) var widths: LayoutFrames.Widths = FrameBreakpointWidths.defaults
  /// What the project's Quartz can do (5.1: `layout.sidebars`).
  private(set) var features = QuartzFeatures()
  /// Quartz's own frame as this project's Sass measures it; nil until read.
  private(set) var measures: ScssCheck.MeasuresResult?
  /// Instance classes the stylesheets already name, for the class of a copy.
  private(set) var styled: Set<String> = []

  /// The frame being edited on the Frames tab, as its JSON; nil shows Quartz's standard frame.
  var draft: JSONValue?
  /// What the draft was opened as, for "unsaved".
  private(set) var draftBaseline: JSONValue?
  private(set) var draftIsNew = false
  /// The standard frame was chosen, rather than shown for want of an own one.
  private(set) var standardChosen = false
  private(set) var frameSaving = false
  var frameMessage: String?
  /// After a save of an existing frame: a running dev server needs a restart for it.
  private(set) var frameSavedWasEdit = false
  private(set) var frameSavedAt: JSONValue?

  init(project: ProjectContext) {
    self.project = project
  }

  var dirty: Bool { config != nil && config != saved }
  var saving: Bool { status == .saving }
  var draftDirty: Bool { draft != nil && draft != draftBaseline }

  var standardMeasures: ScssCheck.Measures {
    if case .ok(let measures)? = measures { return measures }
    return FrameEditing.quartzMeasures
  }

  // MARK: reading

  func load() async {
    let environment = await AppServices.current()
    do {
      let read = try await ConfigFile.read(project: project.path, runtime: environment.runtime)
      config = read
      saved = read
      loadError = nil
    } catch {
      loadError = ConfigModel.message(error)
    }
    let path = project.path
    reloadFrames()
    widths = await Task.detached { LayoutFrames.widths(project: path) }.value
    features = await Task.detached { QuartzFeatures.read(project: path) }.value
    styled = Set((try? await Task.detached { try SiteFonts.takenClasses(project: path, prefixes: InstanceClass.prefixes) }.value) ?? [])
    await readPluginFrames()
    measures = await ScssCheck.frameMeasures(project: path, runtime: environment.runtime)
  }

  func reloadFrames() {
    frames = LayoutFrames.listFrames(project: project.path).map(FrameView.init)
    framesLoaded = true
    // A frame deleted elsewhere takes its draft along, unless the draft is new.
    if let draft, !draftIsNew, !frames.contains(where: { $0.id == FrameView(draft).id }) {
      open(frames.first.map(\.json), isNew: false)
    } else if draft == nil, !standardChosen, let first = frames.first {
      open(first.json, isNew: false)
    }
  }

  /// Keyed off the plugins' names and sources: moving components around does not ask again.
  func readPluginFrames() async {
    guard let plugins = config?.plugins else { return }
    let environment = await AppServices.current()
    pluginFrames = await PluginSchemaReader.shared.pageTypeFrames(project: project.path, plugins: plugins.map { ($0.name, $0.source) },
                                                                  runtime: environment.runtime)
  }

  var pluginFramesKey: String {
    (config?.plugins ?? []).map { "\($0.name)|\($0.source.map(JSJSON.compact) ?? "")" }.joined(separator: "\n")
  }

  // MARK: the config

  /// Whether it worked: the leave question goes on only then, and the error stays on the page.
  @discardableResult
  func save() async -> Bool {
    guard let config, !saving else { return false }
    guard dirty else { return true }
    status = .saving
    saveError = nil
    let environment = await AppServices.current()
    do {
      try await ConfigFile.write(config, project: project.path, runtime: environment.runtime,
                                 snapshot: SnapshotStore.live(environment: environment).take)
    } catch {
      status = .failed
      saveError = ConfigModel.message(error)
      return false
    }
    let written = config
    if let read = try? await ConfigFile.read(project: project.path, runtime: environment.runtime) {
      saved = read
      if self.config == written { self.config = read }
    } else {
      saved = written
    }
    status = .saved
    Announce.post(L10n.t("common.saved"))
    Task {
      try? await Task.sleep(for: .seconds(2))
      if status == .saved { status = .idle }
    }
    return true
  }

  /// After the CLI registered or removed a frame: only what the CLI changed in `plugins:` is taken
  /// from the file, so edits of the stage stay and still count as unsaved, and the new entry does
  /// not. Taking the file's list whole dropped them (review 2026-11-13, H2).
  func syncPluginsFromDisk() async {
    let environment = await AppServices.current()
    guard let fresh = try? await ConfigFile.read(project: project.path, runtime: environment.runtime) else { return }
    if let config, let saved {
      self.config?.plugins = PluginListMerge.merge(base: saved.plugins, local: config.plugins, disk: fresh.plugins)
    } else if config == nil {
      config = fresh
    } else {
      config?.plugins = fresh.plugins
    }
    saved = fresh
  }

  // MARK: frames

  func open(_ def: JSONValue?, isNew: Bool) {
    draft = def
    draftBaseline = def
    draftIsNew = isNew
    standardChosen = def == nil
    frameMessage = nil
    frameSavedAt = nil
  }

  /// A new frame id, as QuartzControl made one.
  static func newId(_ prefix: String) -> String { "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1000))" }

  func newFrame() { open(FrameEditing.emptyDraft(id: Self.newId("frame")), isNew: true) }

  func customizeStandard() {
    open(FrameEditing.quartzDefaultFrame(id: Self.newId("frame"), frameName: FrameEditing.freeName("standard", frames: frames),
                                         measures: standardMeasures), isNew: true)
  }

  func duplicateDraft() {
    guard let draft else { return }
    let copy = FrameEditing.duplicate(draft, id: Self.newId("frame"), frames: frames)
    open(copy, isNew: true)
    Announce.post(L10n.t("layoutEditor.frameBuilder.duplicated", ["name": FrameView(copy).frameName]))
  }

  /// Whether the draft may be written, or the sentence why not.
  func draftProblem() -> String? {
    guard let draft else { return nil }
    let view = FrameView(draft)
    if view.frameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L10n.t("layoutEditor.frameBuilder.nameRequired") }
    if FrameEditing.nameCollision(view, frames: frames) { return L10n.t("layoutEditor.frameBuilder.nameCollision") }
    let names = FrameEditing.duplicateAreaNames(view)
    if !names.isEmpty { return L10n.t("layoutEditor.frameBuilder.areaNameCollision", ["names": names.joined(separator: ", ")]) }
    let groups = FrameEditing.duplicateAreaGroups(view)
    if !groups.isEmpty { return L10n.t("layoutEditor.frameBuilder.areaGroupCollision", ["names": groups.joined(separator: ", ")]) }
    return nil
  }

  @discardableResult
  func saveFrame() async -> Bool {
    guard let draft, !frameSaving else { return false }
    if let problem = draftProblem() {
      frameMessage = problem
      return false
    }
    frameSaving = true
    defer { frameSaving = false }
    let environment = await AppServices.current()
    let take = SnapshotStore.live(environment: environment).take
    do {
      let result = try await LayoutFrames(plugins: .cli(environment: { await AppServices.current() }, snapshot: take))
        .saveFrame(draft, project: project.path)
      guard result.success else {
        frameMessage = result.output
        return false
      }
    } catch {
      frameMessage = String(describing: error)
      return false
    }
    frameSavedWasEdit = !draftIsNew
    draftIsNew = false
    standardChosen = false
    frameMessage = nil
    draftBaseline = draft
    frameSavedAt = draft
    reloadFrames()
    await syncPluginsFromDisk()
    Announce.post(L10n.t("layoutEditor.frameBuilder.saved"))
    return true
  }

  func deleteFrame(_ id: String) async {
    let environment = await AppServices.current()
    let take = SnapshotStore.live(environment: environment).take
    do {
      let result = try await LayoutFrames(plugins: .cli(environment: { await AppServices.current() }, snapshot: take))
        .deleteFrame(id: id, project: project.path)
      frameMessage = result.success ? nil : result.output
      if result.success, let draft, FrameView(draft).id == id {
        open(frames.first { $0.id != id }?.json, isNew: false)
      }
    } catch {
      frameMessage = String(describing: error)
    }
    reloadFrames()
    await syncPluginsFromDisk()
  }

  func saveWidths(tablet: Double, mobile: Double) async -> String? {
    let environment = await AppServices.current()
    do {
      try await LayoutFrames(plugins: .cli(environment: { environment }, snapshot: nil))
        .saveWidths((tablet: tablet, mobile: mobile), project: project.path)
      widths = (tablet, mobile)
      return nil
    } catch {
      return String(describing: error)
    }
  }
}
