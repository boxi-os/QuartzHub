import QuartzHubCore
import SwiftUI

@main
struct QuartzHubApp: App {
  /// The questions about dev servers at the start and at quit (Shell/ServerLifecycle.swift).
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  init() {
    // The language from QuartzHub's settings.json (QuartzControl's form, taken over on first
    // start). A UI test pins it with -QHLanguage de|en, so screenshots and checks do not depend on
    // the Mac they run on.
    let pinned = LaunchArgument.string("QHLanguage").flatMap(LanguagePreference.init(rawValue:))
    let stored = JSONStore.peek(AppProfile.own.settings)
    let settings: LanguagePreference? = if case .ok(.object(let object)) = stored {
      LanguagePreference(rawValue: SettingsFile(object: object).language.rawValue)
    } else {
      nil
    }
    L10n.apply(pinned ?? settings ?? .system)
    // A saved window frame ("NSWindow Frame …" in this app's defaults) wins over defaultSize; a
    // test that asks for a size gets it only without one.
    if LaunchArgument.string("QHWindowSize") != nil {
      for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame ") {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }
  }

  /// The first window's size. A UI test sets it with -QHWindowSize 1500x950: dragging a window's
  /// edge or corner did not resize it under XCUITest on macOS 27 (measured 2026-11-06), so the
  /// smoke test opens the app once per size, the way QuartzControl's smoke set it through the API.
  private static let initialSize: CGSize = {
    let parts = (LaunchArgument.string("QHWindowSize") ?? "").split(separator: "x").compactMap { Double($0) }
    return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1200, height: 780)
  }()

  var body: some Scene {
    // First, so it is the window at launch and the one the Dock icon brings back. Window ▸ Projekte
    // lists it with its shortcut.
    Window(L10n.t("shell.projects.title"), id: ProjectsWindow.sceneID) {
      ProjectsWindow()
        .frame(minWidth: 640, minHeight: 420)
        .followsLanguage()
    }
    .defaultSize(width: 980, height: 640)
    .keyboardShortcut("0", modifiers: [.command, .shift])
    .commands {
      SidebarCommands()
      InspectorCommand()
      ProjectCommands()
      SaveCommand()
      ArrangeCommands()
      HelpCommands()
    }

    WindowGroup(id: ProjectWindow.sceneID, for: String.self) { $projectId in
      ProjectWindow(projectId: projectId)
        .followsLanguage()
    }
    .defaultSize(Self.initialSize)

    Settings {
      SettingsWindow()
    }
  }
}

/// The File menu: no "New Window" (a project window without a project means nothing), but
/// "Neues Projekt…" (⌘N) and "Vorhandenes Projekt öffnen…" (⌘O), from any window.
struct ProjectCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    // Read so the items are made again after a language change.
    let _ = AppAppearance.shared.revision
    CommandGroup(replacing: .newItem) {
      Button(L10n.t("shell.menu.newProject")) {
        openWindow(id: ProjectsWindow.sceneID)
        ProjectsModel.shared.request = .create
      }
      .keyboardShortcut("n", modifiers: .command)
      Button(L10n.t("shell.menu.openExisting")) {
        openWindow(id: ProjectsWindow.sceneID)
        ProjectsModel.shared.request = .openExisting
      }
      .keyboardShortcut("o", modifiers: .command)
    }
  }
}
