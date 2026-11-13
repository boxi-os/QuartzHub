import AppKit
import QuartzHubCore
import SwiftUI

/// The Help menu, QuartzControl's in `electron/main/menu.ts` (user, 2026-11-09: all of it): where
/// the truth lives (Quartz's docs, the plugin organisation) and where the data is, from any window.
/// Hilfe ▸ Handbuch opens the handbook's start, „Diese Seite im Handbuch“ the chapter for the front
/// project window's page and tab (`Handbook`). The system keeps its search field at the top.
struct HelpCommands: Commands {
  @FocusedValue(\.windowNavigation) private var navigation

  /// A constant, not a setting: this app's own repository. A report only arrives once the
  /// repository is public; GitHub answers 404 for a private one to everyone but collaborators
  /// (QuartzControl measured it on 2026-09-09).
  static let feedbackURL = "https://github.com/boxi-os/QuartzHub/issues/new"
  static let quartzDocs = "https://quartz.jzhao.xyz/"
  static let pluginCatalog = "https://github.com/quartz-community"

  var body: some Commands {
    let _ = AppAppearance.shared.revision
    CommandGroup(replacing: .help) {
      Button(L10n.t("main.menuHandbook")) { ExternalOpen.open(Handbook.url(for: nil, language: L10n.language)) }
      Button(L10n.t("shell.help.handbookHere")) {
        if let place = navigation?.handbookPlace { ExternalOpen.open(Handbook.url(for: place, language: L10n.language)) }
      }
      .disabled(navigation == nil)
      Divider()
      Button(L10n.t("main.menuFeedback")) { Self.sendFeedback() }
      Divider()
      Button(L10n.t("main.menuQuartzDocs")) { Self.open(Self.quartzDocs) }
      Button(L10n.t("main.menuPluginCatalog")) { Self.open(Self.pluginCatalog) }
      Divider()
      Button(L10n.t("main.menuDataFolder")) {
        ExternalOpen.openFolder(AppProfile.own.path)
      }
      Button(L10n.t("main.menuLicenses")) { Self.openLicenses() }
    }
  }

  private static func open(_ address: String) {
    if let url = URL(string: address) { ExternalOpen.open(url) } // not a file path
  }

  /// A new issue with the version and the system filled in, as QuartzControl's `sendFeedback`.
  static func feedbackLink(version: String, system: String, arch: String) -> String {
    let body = ["", "", "---", "QuartzHub \(version)", "macOS \(system) \(arch)"].joined(separator: "\n")
    let title = "QuartzHub \(version) — \(L10n.t("main.feedbackSubject"))"
    return "\(feedbackURL)?title=\(component(title))&body=\(component(body))"
  }

  /// JavaScript's `encodeURIComponent`: everything but its unreserved characters escaped.
  private static func component(_ text: String) -> String {
    let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
  }

  private static func sendFeedback() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let v = ProcessInfo.processInfo.operatingSystemVersion
    open(feedbackLink(version: version, system: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)", arch: "arm64"))
  }

  /// The licence texts travelling with the app (`Contents/Resources/licenses`, scripts/package.sh),
  /// in a development build the repository's. A folder, so the Finder shows what is in it. Missing
  /// means an incomplete installation, and the click says so rather than doing nothing.
  static var licensesFolder: String {
    if let resources = Bundle.main.resourceURL.map({ Posix.path($0) }), FileManager.default.fileExists(atPath: "\(resources)/licenses") {
      return "\(resources)/licenses"
    }
    return "\(NodePath.dirname(NodePath.dirname(RuntimeLocation.repository.node)))/Resources/licenses"
  }

  private static func openLicenses() {
    let folder = licensesFolder
    guard FileManager.default.fileExists(atPath: folder) else {
      let alert = NSAlert()
      alert.alertStyle = .informational
      alert.messageText = L10n.t("main.licensesMissingTitle")
      alert.informativeText = L10n.t("main.licensesMissingDetail")
      alert.runModal()
      return
    }
    ExternalOpen.openFolder(folder)
  }
}
