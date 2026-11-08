import Foundation
import QuartzHubCore

/// quartz.config.yaml as the Konfiguration page holds it (QuartzControl's `ConfigEditor/index.tsx`):
/// read when the page appears, edited in memory, written by "Speichern" (⌘S), read again after
/// every write of its own. "Unsaved" is a comparison with what was read, so an edit typed and
/// undone is no edit.
@MainActor @Observable
final class ConfigModel {
  enum Status { case idle, saving, saved, failed }

  let project: ProjectContext
  var config: QuartzConfig?
  private(set) var saved: QuartzConfig?
  private(set) var loadError: String?
  private(set) var status = Status.idle
  private(set) var saveError: String?
  /// The locale files the project ships; nil while reading, empty when there are none.
  private(set) var locales: [String]?

  init(project: ProjectContext) {
    self.project = project
  }

  var dirty: Bool { config != nil && config != saved }
  var saving: Bool { status == .saving }

  func load() async {
    let environment = await AppServices.current()
    do {
      let read = try await ConfigFile.read(project: project.path, runtime: environment.runtime)
      config = read
      saved = read
      loadError = nil
    } catch {
      loadError = Self.message(error)
    }
    let path = project.path
    locales = await Task.detached { (try? LocaleFiles(environment: environment).list(project: path)) ?? [] }.value
  }

  /// Whether it worked: the leave question goes on only then, and the error stays on the page.
  @discardableResult
  func save() async -> Bool {
    guard let config, !saving else { return false }
    status = .saving
    saveError = nil
    let environment = await AppServices.current()
    do {
      try await ConfigFile.write(config, project: project.path, runtime: environment.runtime,
                                 snapshot: SnapshotStore.live(environment: environment).take)
    } catch {
      status = .failed
      saveError = Self.message(error)
      return false
    }
    // Read again: what is on disk is what the page shows now. Edits typed meanwhile stay.
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

  /// After someone else wrote the file (`quartz plugin add`): the draft is what is on disk.
  func reread() async throws -> QuartzConfig {
    let environment = await AppServices.current()
    let read = try await ConfigFile.read(project: project.path, runtime: environment.runtime)
    config = read
    saved = read
    return read
  }

  static func message(_ error: Error) -> String {
    if let failure = error as? ConfigFile.Failure { return failure.message }
    return String(describing: error)
  }

  // MARK: configuration

  func string(_ key: String) -> String { config?.configuration[key]?.stringValue ?? "" }

  func setString(_ key: String, _ value: String) {
    config?.configuration[key] = .string(value)
  }

  func bool(_ key: String) -> Bool { config?.configuration[key]?.boolValue ?? false }

  func setBool(_ key: String, _ value: Bool) {
    config?.configuration[key] = .bool(value)
  }

  var ignorePatterns: [String] {
    config?.configuration["ignorePatterns"]?.arrayValue?.compactMap(\.stringValue) ?? []
  }

  func setIgnorePatterns(_ patterns: [String]) {
    config?.configuration["ignorePatterns"] = .array(patterns.map(JSONValue.string))
  }

  var plugins: [PluginEntry] { config?.plugins ?? [] }

  func setPlugins(_ plugins: [PluginEntry]) {
    config?.plugins = plugins
  }
}
