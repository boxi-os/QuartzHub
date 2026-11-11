import AppKit
import QuartzHubCore
import SwiftUI

/// Design and language as the settings say, applied at once (QuartzControl: "werden sofort
/// übernommen"). The theme sets the app's appearance; the language changes the catalog and bumps
/// `revision`, which the windows' content is keyed by, so every text is asked again.
@MainActor @Observable
final class AppAppearance {
  static let shared = AppAppearance()

  private(set) var revision = 0

  func applyTheme(_ theme: SettingsFile.Theme) {
    NSApp.appearance = switch theme {
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    case .system: nil
    }
  }

  func applyLanguage(_ language: SettingsFile.Language) {
    // A UI test pins the language; the setting does not move it.
    if LaunchArgument.string("QHLanguage") != nil { return }
    L10n.apply(LanguagePreference(rawValue: language.rawValue) ?? .system)
    revision += 1
    // macOS's own menu items (Ablage, Bearbeiten, Fenster) take the language at launch. The
    // per-app language System Settings writes, so they agree from the next start on.
    if language == .system {
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    } else {
      UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }
  }
}

extension View {
  /// Asks every text again after a language change.
  func followsLanguage() -> some View {
    modifier(FollowsLanguage())
  }
}

private struct FollowsLanguage: ViewModifier {
  @State private var appearance = AppAppearance.shared
  func body(content: Content) -> some View { content.id(appearance.revision) }
}
