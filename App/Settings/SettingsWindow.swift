import AppKit
import QuartzHubCore
import SwiftUI

/// QuartzHub ▸ Einstellungen… (⌘,): QuartzControl's settings page (`src/routes/Settings.tsx`) as
/// the macOS settings window with four tabs. Every control writes at once (`SettingsStore`), as the
/// page did; the one text field, the default folder, has its own "Speichern", and a connection is
/// edited in a sheet with its own.
struct SettingsWindow: View {
  /// Which tab is open. Veröffentlichen's "Zugänge verwalten" sets it before it opens the window.
  @Bindable private var tab = SettingsTab.State.shared

  var body: some View {
    TabView(selection: $tab.selected) {
      GeneralSettings()
        .frame(height: 540)
        .tabItem { Label(L10n.t("shell.settings.general"), systemImage: "gearshape") }
        .tag(SettingsTab.general.rawValue)
      ConnectionsSettings()
        .frame(height: 600)
        .tabItem { Label(L10n.t("settings.connections.title"), systemImage: "key") }
        .tag(SettingsTab.connections.rawValue)
      RuntimeSettings()
        .frame(height: 470)
        .tabItem { Label(L10n.t("settings.runtime.title"), systemImage: "terminal") }
        .tag(SettingsTab.runtime.rawValue)
      MaintenanceSettings()
        .frame(height: 430)
        .tabItem { Label(L10n.t("settings.maintenance.title"), systemImage: "externaldrive") }
        .tag(SettingsTab.maintenance.rawValue)
    }
    .frame(width: 560)
    .followsLanguage()
  }
}

enum SettingsTab: String {
  case general, connections, runtime, maintenance

  /// For the process only, not stored: a stored tab opened every later start on it, and the UI
  /// test, which shares the app's defaults, found no "Allgemein" (measured).
  @MainActor @Observable
  final class State {
    static let shared = State()
    var selected = SettingsTab.general.rawValue
  }
}

/// Reads the settings once and writes one field per change.
@MainActor @Observable
final class SettingsModel {
  private(set) var file = SettingsStore.read(AppProfile.own)
  var failure: String?

  func update(_ change: (inout SettingsFile) -> Void) {
    do {
      file = try SettingsStore.update(AppProfile.own, change)
    } catch {
      failure = String(describing: error)
    }
  }
}

private struct GeneralSettings: View {
  @State private var model = SettingsModel()
  @State private var directory = ""
  @State private var directoryFailure: String?
  @State private var saved = false

  var body: some View {
    Form {
      Section {
        Picker(L10n.t("settings.appearance.theme"), selection: Binding(get: { model.file.theme }, set: { theme in
          model.update { $0.theme = theme }
          AppAppearance.shared.applyTheme(theme)
        })) {
          Text(L10n.t("settings.appearance.themeSystem")).tag(SettingsFile.Theme.system)
          Text(L10n.t("settings.appearance.themeLight")).tag(SettingsFile.Theme.light)
          Text(L10n.t("settings.appearance.themeDark")).tag(SettingsFile.Theme.dark)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("settings.theme")
        Picker(L10n.t("settings.language"), selection: Binding(get: { model.file.language }, set: { language in
          model.update { $0.language = language }
          AppAppearance.shared.applyLanguage(language)
        })) {
          Text(L10n.t("settings.languageSystem")).tag(SettingsFile.Language.system)
          Text(L10n.t("settings.languageDe")).tag(SettingsFile.Language.de)
          Text(L10n.t("settings.languageEn")).tag(SettingsFile.Language.en)
        }
        .accessibilityIdentifier("settings.language")
      } header: {
        Text(L10n.t("settings.appearance.title"))
      } footer: {
        Text(L10n.t("settings.appearance.appliedImmediately")).font(.caption).foregroundStyle(.secondary)
      }

      Section {
        LabeledContent(L10n.t("settings.defaultProjectDirectory")) {
            HStack {
              TextField("", text: $directory, prompt: Text("~/Documents"))
                .labelsHidden()
                .onSubmit(saveDirectory)
                .accessibilityIdentifier("settings.directory")
              Button(L10n.t("common.select")) {
                if let folder = ProjectsModel.pickFolder(start: directory.isEmpty ? nil : directory) {
                  directory = folder
                  saveDirectory()
                }
              }
              Button(saved ? L10n.t("common.saved") : L10n.t("common.save"), action: saveDirectory)
                .disabled(directory == (model.file.defaultProjectDirectory ?? ""))
            }
        }
        if let directoryFailure {
          Text(directoryFailure).foregroundStyle(.red).font(.callout)
        }
      } header: {
        Text(L10n.t("settings.projects.title"))
      } footer: {
        Text(L10n.t("settings.projects.description")).font(.caption).foregroundStyle(.secondary)
      }

      Section {
        Picker(L10n.t("settings.quit.label"), selection: Binding(get: { model.file.serversOnQuit }, set: { mode in
          model.update { $0.serversOnQuit = mode }
        })) {
          Text(L10n.t("settings.quit.ask")).tag(SettingsFile.ServersOnQuit.ask)
          Text(L10n.t("settings.quit.keep")).tag(SettingsFile.ServersOnQuit.keep)
          Text(L10n.t("settings.quit.stop")).tag(SettingsFile.ServersOnQuit.stop)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("settings.quit")
      } header: {
        Text(L10n.t("settings.quit.title"))
      } footer: {
        Text(quitHint).font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onAppear { directory = model.file.defaultProjectDirectory ?? "" }
  }

  private var quitHint: String {
    switch model.file.serversOnQuit {
    case .ask: L10n.t("settings.quit.hint.ask")
    case .keep: L10n.t("settings.quit.hint.keep")
    case .stop: L10n.t("settings.quit.hint.stop")
    }
  }

  private func saveDirectory() {
    do {
      let value = try SettingsStore.projectDirectory(directory)
      directoryFailure = nil
      directory = value ?? ""
      model.update { $0.defaultProjectDirectory = value }
      saved = true
      Task {
        try? await Task.sleep(for: .seconds(2))
        saved = false
      }
    } catch let failure as SettingsStore.Failure {
      directoryFailure = failure.message
    } catch {
      directoryFailure = String(describing: error)
    }
  }
}

private struct RuntimeSettings: View {
  @State private var model = SettingsModel()
  @State private var report: EnvironmentReport?

  private func tool(_ name: String) -> EnvironmentReport.Tool? { report?.tools.first { $0.name == name } }

  var body: some View {
    Form {
      Section {
        Picker(L10n.t("settings.runtime.label"), selection: Binding(get: { model.file.nodeRuntime }, set: { mode in
          model.update { $0.nodeRuntime = mode }
          AppServices.shared.reloadEnvironment()
          Task { await probe() }
        })) {
          Text(L10n.t("settings.runtime.embedded")).tag(SettingsFile.NodeRuntime.embedded)
          Text(L10n.t("settings.runtime.system")).tag(SettingsFile.NodeRuntime.system)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("settings.runtime")
        Text(inUse)
        Text(hint).font(.caption).foregroundStyle(.secondary)
        Text(L10n.t("settings.runtime.appliesToNewProcesses")).font(.caption).foregroundStyle(.secondary)
      } header: {
        Text(L10n.t("settings.runtime.title"))
      } footer: {
        Text(L10n.t("settings.runtime.description")).font(.caption).foregroundStyle(.secondary)
      }
      // git with it, because the question is the same (what does the app run with) and the answer
      // the other way round: the computer's wins, it carries the user's own setup. No switch.
      if let git = tool("git") {
        Section {
          let version = EnvironmentReport.versionNumber(git.version) ?? "—"
          if git.source == .bundled {
            Text(L10n.t("settings.runtime.gitBundled", ["version": version]))
            HStack(spacing: 4) {
              Text(L10n.t("settings.runtime.gitLicense")).font(.caption).foregroundStyle(.secondary)
              Link(L10n.t("settings.runtime.gitSource"), destination: URL(string: "https://github.com/git/git/tree/v\(version)")!)
                .font(.caption)
            }
          } else {
            Text(L10n.t("settings.runtime.gitHost", ["version": version]))
          }
        }
      }
    }
    .formStyle(.grouped)
    .task { await probe() }
  }

  private func probe() async {
    report = await EnvironmentReport.probe(await AppServices.shared.environment.value)
  }

  private var inUse: String {
    model.file.nodeRuntime == .embedded
      ? L10n.t("settings.runtime.inUseEmbedded", ["node": tool("node")?.version ?? "—", "npm": tool("npm")?.version ?? "—"])
      : L10n.t("settings.runtime.inUseSystem", ["node": tool("node")?.version ?? L10n.t("settings.runtime.noSystemNode")])
  }

  private var hint: String {
    if model.file.nodeRuntime == .system { return L10n.t("settings.runtime.hintSystem") }
    if let host = report?.hostNodeVersion { return L10n.t("settings.runtime.hintSwitchable", ["node": host]) }
    return L10n.t("settings.runtime.hintNoHostNode")
  }
}

private struct MaintenanceSettings: View {
  @State private var cache: (entries: Int, bytes: Int)?
  @State private var clearing = false
  private let schema = StyleSettingsSchema(profile: AppProfile.own)

  var body: some View {
    Form {
      // Normally absent: a store that could not be read was moved aside, not overwritten, and
      // this is the one place that can say so.
      let quarantined = JSONStore.quarantinedFiles()
      if !quarantined.isEmpty {
        Section {
          Label(L10n.t("settings.maintenance.unreadableTitle"), systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(L10n.t("settings.maintenance.unreadableHint")).foregroundStyle(.secondary)
          ForEach(quarantined, id: \.path) { file in
            Text(file.quarantinedAs ?? file.path).font(.caption.monospaced()).textSelection(.enabled)
          }
        }
      }
      Section {
        LabeledContent(L10n.t("settings.maintenance.cache")) {
          if let cache {
            Text(L10n.t("settings.maintenance.cacheSize", ["count": String(cache.entries), "size": Formats.bytes(cache.bytes)], count: cache.entries))
          } else {
            Text("…")
          }
        }
        Text(L10n.t("settings.maintenance.cacheHint")).font(.caption).foregroundStyle(.secondary)
        Button(clearing ? L10n.t("settings.maintenance.clearing") : L10n.t("settings.maintenance.clearCache")) {
          clearing = true
          Task {
            _ = await schema.clearCache()
            cache = await schema.cacheStats()
            clearing = false
          }
        }
        .disabled(clearing || cache?.entries == 0)
      }
      Section {
        LabeledContent(L10n.t("settings.maintenance.storage")) {
          Text(AppProfile.own.path).font(.caption).textSelection(.enabled).multilineTextAlignment(.trailing)
        }
        Text(L10n.t("settings.maintenance.storageHint")).font(.caption).foregroundStyle(.secondary)
        Button(L10n.t("settings.maintenance.reveal")) {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppProfile.own.path)]) // path boundary
        }
      } footer: {
        Text("QuartzHub \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .task { cache = await schema.cacheStats() }
  }
}
