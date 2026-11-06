import QuartzHubCore
import SwiftUI

@main
struct QuartzHubApp: App {
  init() {
    // The language from QuartzHub's settings.json (QuartzControl's form, taken over on first
    // start). A UI test pins it with -QHLanguage de|en, so screenshots and checks do not depend on
    // the Mac they run on.
    let pinned = UserDefaults.standard.string(forKey: "QHLanguage").flatMap(LanguagePreference.init(rawValue:))
    let stored = JSONStore.peek(AppProfile.own.settings)
    let settings: LanguagePreference? = if case .ok(.object(let object)) = stored {
      LanguagePreference(rawValue: SettingsFile(object: object).language.rawValue)
    } else {
      nil
    }
    L10n.apply(pinned ?? settings ?? .system)
    // A saved window frame ("NSWindow Frame …" in this app's defaults) wins over defaultSize; a
    // test that asks for a size gets it only without one.
    if UserDefaults.standard.string(forKey: "QHWindowSize") != nil {
      for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame ") {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }
  }

  /// The first window's size. A UI test sets it with -QHWindowSize 1500x950: dragging a window's
  /// edge or corner did not resize it under XCUITest on macOS 27 (measured 2026-11-06), so the
  /// smoke test opens the app once per size, the way QuartzControl's smoke set it through the API.
  private static let initialSize: CGSize = {
    let parts = (UserDefaults.standard.string(forKey: "QHWindowSize") ?? "").split(separator: "x").compactMap { Double($0) }
    return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1200, height: 780)
  }()

  var body: some Scene {
    WindowGroup {
      RootView()
        .frame(minWidth: 900, minHeight: 560)
    }
    .defaultSize(Self.initialSize)
    .commands {
      SidebarCommands()
      InspectorCommand()
    }
  }
}
