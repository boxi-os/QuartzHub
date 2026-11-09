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

  static func make(project: String, environment: ToolEnvironment,
                   progress: @escaping @Sendable (String, Int, Int, String?) -> Void = { _, _, _, _ in }) -> Deploy {
    let connections = connections()
    let confirm: HostKeyCheck.Confirm = { host, fingerprint in await askHostKey(host: host, fingerprint: fingerprint) }
    return Deploy(project: project, connections: connections, adapters: [
      "folder": FolderAdapter(),
      "sftp": SFTPAdapter(connections: connections, environment: environment, confirm: confirm),
      "rsync": RsyncAdapter(connections: connections, environment: environment),
      "ftp": FTPAdapter(connections: connections, runtime: environment.runtime),
      "git-branch": GitBranchAdapter(environment: environment, token: connections.gitToken),
      "webhook": WebhookAdapter(),
      "document": DocumentAdapter(runtime: environment.runtime),
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
