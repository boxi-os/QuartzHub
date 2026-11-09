import AppKit
import QuartzHubCore

/// The app's `Deploy`: the profile's connections from the Keychain and the adapters of the targets
/// a relay or a site can go to. An unknown SSH host is asked about as QuartzControl's
/// `hostVerifier.ts` asked: a native dialog with the fingerprint, the safe answer first.
enum AppDeploy {
  static func connections() -> Connections {
    Connections(profile: AppProfile.own, secrets: KeychainSecrets())
  }

  static func make(project: String, environment: ToolEnvironment) -> Deploy {
    let connections = connections()
    let confirm: HostKeyCheck.Confirm = { host, fingerprint in await askHostKey(host: host, fingerprint: fingerprint) }
    return Deploy(project: project, connections: connections, adapters: [
      "folder": FolderAdapter(),
      "sftp": SFTPAdapter(connections: connections, environment: environment, confirm: confirm),
      "rsync": RsyncAdapter(connections: connections, environment: environment),
      "ftp": FTPAdapter(connections: connections, runtime: environment.runtime),
    ])
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
