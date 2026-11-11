import AppKit
import QuartzHubCore

/// The app's `Deploy`: the profile's connections from the Keychain and the adapters of every kind
/// of target. An unknown SSH host is asked about as QuartzControl's `hostVerifier.ts` asked: a
/// native dialog with the fingerprint, the safe answer first.
enum AppDeploy {
  /// The Keychain. For looking at the app without touching it (DEBUG, `-QHMemorySecrets YES`),
  /// one store in memory for the process: a secret saved there is gone when the app quits.
  static let secrets: any SecretStore = {
    #if DEBUG
    if UserDefaults.standard.bool(forKey: "QHMemorySecrets") { return MemorySecrets() }
    #endif
    return KeychainSecrets()
  }()

  static func connections() -> Connections {
    Connections(profile: AppProfile.own, secrets: secrets)
  }

  /// Bumped after every write to the connections. QuartzControl's settings were a route in the
  /// one window, so a page showing a connection was mounted again after an edit; here the settings
  /// are a window of their own beside the project, and the publish page kept saying "keine URL
  /// hinterlegt" after the URL was saved (measured 2026-11-11). A reader watches `value`.
  @MainActor @Observable
  final class ConnectionsVersion {
    static let shared = ConnectionsVersion()
    private(set) var value = 0
    func bump() { value += 1 }
  }

  /// For looking at the app without the network (DEBUG, `-QHNoUpdateCheck YES`): a document is
  /// exported without what its pages load from outside, as `qh-check export-document` does.
  static var offline: Bool {
    #if DEBUG
    return UserDefaults.standard.bool(forKey: "QHNoUpdateCheck")
    #else
    return false
    #endif
  }

  static func make(project: String, environment: ToolEnvironment,
                   progress: @escaping @Sendable (String, Int, Int, String?) -> Void = { _, _, _, _ in }) -> Deploy {
    let connections = connections()
    let confirm: HostKeyCheck.Confirm = { host, fingerprint in await askHostKey(host: host, fingerprint: fingerprint) }
    return Deploy(project: project, connections: connections, adapters: [
      "folder": FolderAdapter(),
      "sftp": SFTPAdapter(connections: connections, environment: environment, confirm: confirm),
      "rsync": RsyncAdapter(connections: connections, environment: environment),
      "ftp": FTPAdapter(connections: connections, runtime: environment.runtime),
      "git-branch": GitBranchAdapter(environment: environment, token: connections.gitToken, pagesDomain: { project in
        // Unknown unless GitHub answered: no origin there, no Pages call, an error.
        guard let info = try? await GitHubAPI(environment: environment, token: connections.gitToken).pagesInfo(project),
              info.error == nil else { return nil }
        return .some(info.configured ? info.cname?.stringValue : nil)
      }),
      "webhook": WebhookAdapter(),
      "document": DocumentAdapter(runtime: environment.runtime, outside: !offline),
    ], progress: progress)
  }

  @MainActor static func askHostKey(host: String, fingerprint: String) async -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.t("main.hostKeyUnknownMessage", ["host": host])
    alert.informativeText = L10n.t("main.hostKeyUnknownDetail", ["fingerprint": fingerprint, "host": host])
    alert.addButton(withTitle: L10n.t("main.hostKeyCancel"))
    alert.addButton(withTitle: L10n.t("main.hostKeyAccept"))
    alert.window.title = L10n.t("main.hostKeyUnknownTitle")
    if let window = NSApp.keyWindow {
      return await alert.beginSheetModal(for: window) == .alertSecondButtonReturn
    }
    return alert.runModal() == .alertSecondButtonReturn
  }
}
