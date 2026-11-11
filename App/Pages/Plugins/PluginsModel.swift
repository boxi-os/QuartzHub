import AppKit
import QuartzHubCore

/// One entry of the plugin list with what the list needs to know beside it.
struct IndexedPlugin: Identifiable {
  let entry: PluginEntry
  let index: Int
  /// The authored frame this entry registers, for the entries that are one.
  let frame: JSONValue?
  /// Which of the same-named entries this is, counted from 1.
  let occurrence: Int
  /// How many entries carry this name.
  let of: Int

  /// What the inspector remembers as selected: the name, with its number where there are several.
  /// Not the index (docs/conventions.md, „Wo war ich“). A frame keeps the plain name: frame ids are
  /// unique by construction.
  var id: String { frame != nil || occurrence == 1 ? entry.name : "\(entry.name)#\(occurrence)" }

  /// What a row is called on screen: a frame its own name, everything else the plugin name with its
  /// number where there are several ("quartz-layout-box #2").
  var displayName: String {
    if let frame { return frame["frameName"]?.stringValue ?? entry.name }
    return of > 1 ? "\(entry.name) #\(occurrence)" : entry.name
  }

  var layout: JSONObject? { entry.object["layout"]?.objectValue }
  var enabled: Bool { entry.enabled }
  var description: String? { PluginDescriptions.text(entry.name) }

  /// Quartz's built-in page types all end in "-page"; its loader orders each category on its own.
  var isPageType: Bool { entry.name.hasSuffix("-page") }

  var sourceLabel: String {
    switch entry.source {
    case .string(let text)?: return text
    case .object(let object)?:
      let repo = object["repo"]?.stringValue ?? ""
      let ref = object["ref"]?.stringValue.map { "#\($0)" } ?? ""
      let subdir = object["subdir"]?.stringValue.map { " (\($0))" } ?? ""
      return repo + ref + subdir
    default: return ""
    }
  }
}

/// The Installiert tab's state (QuartzControl's `routes/Plugins/Installed.tsx`): quartz.config.yaml
/// with the authored frames beside it, and every change written at once. There is no Save on this
/// tab: a switch writes on the click, a text field when it is left.
///
/// Every edit goes into the page's state at once and the writes queue up, one after the other;
/// only the last of a run reads the file again. Two fields left in quick succession otherwise wrote
/// the state from before the first plus the second's value, and the first was gone (QuartzControl's
/// fortieth review, finding 3). Entries are addressed by index, never by name: two entries can
/// derive the same name.
@MainActor @Observable
final class PluginsModel {
  enum Maintenance { case install, prune }

  let project: ProjectContext
  private(set) var config: QuartzConfig?
  private(set) var loadError: String?
  private(set) var frames: [JSONValue] = []
  /// Plugins the Updates page would offer an update for; its own check, which nothing waits for.
  private(set) var outdated: Set<String> = []
  private(set) var busy = false
  private(set) var message: String?
  /// A change refused while a removal ran, apart from `message`, so the next change that is saved
  /// takes it away without taking a failure with it.
  private(set) var refused = false
  private(set) var savedIndex: Int?
  private(set) var maintenance: Maintenance?
  private(set) var maintenanceNotice: String?
  /// What the project's Quartz can do; 5.1 brings the built-ins and `plugin doctor`.
  private(set) var features = QuartzFeatures()
  /// Quartz's own check (`plugin doctor`, 5.1), read after every reload; nil before and on 5.0.
  private(set) var doctor: PluginDoctorReport?
  private var doctorRun = 0

  private var writes: Task<Void, Never>?
  private var removing = false
  private var generation = 0
  private var savedTimer: Task<Void, Never>?

  init(project: ProjectContext) {
    self.project = project
  }

  // MARK: Reading

  func load() async {
    await reload()
    reloadFrames()
  }

  func reload() async {
    let environment = await AppServices.current()
    do {
      config = try await ConfigFile.read(project: project.path, runtime: environment.runtime)
      loadError = nil
    } catch {
      loadError = ConfigModel.message(error)
    }
    let path = project.path
    features = await Task.detached { QuartzFeatures.read(project: path) }.value
    Task { await checkDoctor() }
  }

  /// `quartz plugin doctor` without --fix: it only reads (some 0.7 s on gui-test). Only the last
  /// of several runs started in a row is kept.
  func checkDoctor() async {
    guard features.builtins else {
      doctor = nil
      return
    }
    doctorRun += 1
    let run = doctorRun
    let environment = await AppServices.current()
    let result = await PluginCommands.shared.doctor(project: project.path, fix: false, environment: environment)
    guard run == doctorRun else { return }
    doctor = PluginDoctorReport.parse(result.output)
  }

  func findings(_ item: IndexedPlugin) -> [PluginDoctorReport.Finding] {
    item.frame != nil ? [] : doctor?.findings(for: item.entry.name) ?? []
  }

  /// The built-in that has taken over this entry's job, on a project whose Quartz has them.
  func builtin(_ item: IndexedPlugin) -> BuiltinProcessing.Builtin? {
    features.builtins ? BuiltinProcessing.absorbing(item.entry) : nil
  }

  var pendingMigrations: [String] {
    guard features.builtins, let plugins = config?.plugins else { return [] }
    return BuiltinProcessing.pendingMigrations(plugins).map { plugins[$0].name }
  }

  func reloadFrames() {
    frames = LayoutFrames.listFrames(project: project.path)
  }

  /// `git ls-remote` per lockfile entry: slow or failing, it must not hold up the list.
  func checkOutdated() async {
    #if DEBUG
    if UserDefaults.standard.bool(forKey: "QHNoUpdateCheck") { return }
    #endif
    let environment = await AppServices.current()
    let updater = CoreUpdate(environment: environment, snapshot: SnapshotStore.live(environment: environment).take)
    let statuses = await PluginUpdates.status(project: project.path, core: updater)
    outdated = Set(statuses.filter { $0.state == .behind }.map(\.name))
  }

  var items: [IndexedPlugin] {
    let plugins = config?.plugins ?? []
    var total: [String: Int] = [:]
    for plugin in plugins { total[plugin.name, default: 0] += 1 }
    var seen: [String: Int] = [:]
    let frameByID = Dictionary(frames.compactMap { frame in frame["id"]?.stringValue.map { ($0, frame) } }, uniquingKeysWith: { first, _ in first })
    return plugins.enumerated().map { index, plugin in
      // Both halves have to agree: a frame with that id exists, and the entry points at a frame's
      // directory. A plugin that merely shares a name with a frame is still a plugin.
      let frame = frameByID[plugin.name]
      let isFrame = frame != nil && (plugin.source?.stringValue?.contains("authored-frames") ?? false)
      seen[plugin.name, default: 0] += 1
      return IndexedPlugin(entry: plugin, index: index, frame: isFrame ? frame : nil, occurrence: seen[plugin.name] ?? 1,
                           of: total[plugin.name] ?? 1)
    }
  }

  // MARK: Writing

  /// The one way an edit on this tab reaches the file: fields, the switch and both kinds of
  /// reordering. Nothing is committed while a removal is queued: the state it would mutate still
  /// holds the entry being removed, and its save would put it back.
  @discardableResult
  func commit(sayRefusal: Bool = true, _ mutate: ([PluginEntry]) -> [PluginEntry]) async -> Bool {
    if removing {
      refused = true
      if sayRefusal { Announce.post(L10n.t("pluginsInstalled.busyRemoving")) }
      return false
    }
    guard var next = config else { return false }
    next.plugins = mutate(next.plugins)
    config = next
    generation += 1
    let mine = generation
    let previous = writes
    let project = project.path
    let snapshot = next
    let write = Task { @MainActor () -> Error? in
      await previous?.value
      let environment = await AppServices.current()
      do {
        try await ConfigFile.write(snapshot, project: project, runtime: environment.runtime,
                                   snapshot: SnapshotStore.live(environment: environment).take)
        return nil
      } catch {
        return error
      }
    }
    writes = Task { _ = await write.value }
    if let error = await write.value {
      // What the file holds, back on screen, and the failure said.
      await reload()
      message = ConfigModel.message(error)
      return false
    }
    if generation == mine { await reload() }
    refused = false
    return true
  }

  func updateField(_ index: Int, path: [String], value: JSONValue?) async {
    let done = await commit { plugins in
      plugins.enumerated().map { offset, plugin in
        guard offset == index else { return plugin }
        return PluginEntry(object: OptionSchema.setting(value, at: path, in: plugin.object))
      }
    }
    if done { flagSaved(index) }
  }

  func toggleEnabled(_ index: Int) async {
    await commit { plugins in
      plugins.enumerated().map { offset, plugin in
        guard offset == index else { return plugin }
        var changed = plugin
        changed.enabled.toggle()
        return changed
      }
    }
  }

  /// The visible half is a word beside the name; the spoken half names the entry, because
  /// "Gespeichert." alone says nothing about which one.
  /// Waits for the queued writes, for a reader of the file (the plugin's own check).
  func waitForWrites() async {
    await writes?.value
  }

  func flagSaved(_ index: Int) {
    savedIndex = index
    savedTimer?.cancel()
    savedTimer = Task {
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { savedIndex = nil }
    }
    if let name = config?.plugins[safe: index]?.name {
      Announce.post(L10n.t("pluginsInstalled.savedAnnounce", ["name": name]))
    }
  }

  /// Components move within their position (`layout.priority`), everything else within its
  /// sequence (`order`), renumbered in steps of ten from the order handed in. Never while
  /// filtered: a filtered group renumbered alone reshuffles the hidden entries too.
  func reorder(_ group: [IndexedPlugin], moved: IndexedPlugin, byPriority: Bool) async {
    let done = await commit { plugins in
      var next = plugins
      for (position, item) in group.enumerated() {
        let value = JSONValue.number(Double((position + 1) * 10))
        var object = next[item.index].object
        if byPriority {
          var layout = object["layout"]?.objectValue ?? JSONObject()
          layout["priority"] = value
          object["layout"] = .object(layout)
        } else {
          object["order"] = value
        }
        next[item.index] = PluginEntry(object: object)
      }
      return next
    }
    guard done, let position = group.firstIndex(where: { $0.index == moved.index }) else { return }
    Announce.post(L10n.t("pluginsInstalled.reorderedAnnounce",
                         ["name": moved.displayName, "position": String(position + 1), "total": String(group.count)]))
  }

  // MARK: Removing and maintenance

  func remove(_ item: IndexedPlugin, window: NSWindow?) async {
    let question = item.frame != nil ? L10n.t("pluginsInstalled.removeFrameConfirm", ["name": item.displayName])
      : L10n.t("pluginsInstalled.removeConfirm", ["name": item.displayName])
    guard await Confirm.ask(question, confirm: L10n.t("common.remove"), destructive: true, window: window) else { return }
    busy = true
    message = nil
    refused = false
    removing = true
    defer {
      removing = false
      busy = false
    }
    // In the write queue like every edit: a save still pending wrote the whole config, the entry
    // in it, after the CLI had taken the entry out.
    await writes?.value
    let environment = await AppServices.current()
    let take = SnapshotStore.live(environment: environment).take
    do {
      let result: PluginCommands.Result
      if let id = item.frame?["id"]?.stringValue {
        // Through the frame API: `quartz plugin remove` alone leaves the frame's directory, and the
        // frame stayed in the Layout page's list while it was in no build any more.
        result = try await LayoutFrames(plugins: .cli(environment: { await AppServices.current() }, snapshot: take))
          .deleteFrame(id: id, project: project.path)
      } else {
        // Quartz's name for the entry, not the one on screen: a scoped npm plugin is only found by
        // its whole `@quartz-community/…` name.
        let name = PluginSource(item.entry.source)?.quartzName ?? item.entry.name
        result = await PluginCommands.shared.remove(name: name, project: project.path, environment: environment, snapshot: take)
      }
      if !result.success { message = result.output }
    } catch {
      message = String(describing: error)
    }
    await reload()
    reloadFrames()
  }

  /// `quartz plugin add <source>` from the Marktplatz, with a snapshot (QuartzControl's
  /// `addPlugin`). After the edits still queued: the CLI rewrites the config, and a save pending
  /// behind it wrote the list without the new entry.
  func add(source: String) async -> PluginCommands.Result {
    busy = true
    defer { busy = false }
    await writes?.value
    let environment = await AppServices.current()
    let result = await PluginCommands.shared.add(source: source, project: project.path, environment: environment,
                                                 snapshot: SnapshotStore.live(environment: environment).take)
    await reload()
    reloadFrames()
    return result
  }

  /// The repositories the config already holds, as the Marktplatz compares them (`owner/repo`,
  /// lower case).
  var installedRepositories: Set<String> {
    Set((config?.plugins ?? []).compactMap { PluginRepository.id($0.source) })
  }

  /// `quartz plugin install` and `prune` repair `.quartz/plugins` rather than change the site.
  func runMaintenance(_ kind: Maintenance, window: NSWindow?) async {
    if kind == .prune {
      guard await Confirm.ask(L10n.t("pluginsInstalled.pruneConfirm"), confirm: L10n.t("pluginsInstalled.pruneConfirmAction"),
                              destructive: true, window: window) else { return }
    }
    maintenance = kind
    message = nil
    maintenanceNotice = nil
    defer { maintenance = nil }
    let environment = await AppServices.current()
    let result = kind == .install
      ? await PluginCommands.shared.installFromLock(project: project.path, environment: environment)
      : await PluginCommands.shared.prune(project: project.path, environment: environment)
    // Quartz ends with 0 when single plugins fail: "wiederhergestellt" would be the wrong sentence.
    if !result.success {
      message = result.output
    } else if let failed = result.failed, !failed.isEmpty {
      message = L10n.t("pluginsInstalled.installPartial", ["count": String(failed.count), "names": failed.joined(separator: ", ")],
                       count: failed.count)
    } else {
      maintenanceNotice = kind == .install ? L10n.t("pluginsInstalled.installDone") : L10n.t("pluginsInstalled.pruneDone")
      Announce.post(maintenanceNotice!)
    }
    await reload()
  }
}

extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
