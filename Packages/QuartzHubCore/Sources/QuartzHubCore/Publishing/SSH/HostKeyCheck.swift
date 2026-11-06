import Foundation

/// Trust on first use, with the pin on the connection (`deploy/hostVerifier.ts`): the same server
/// from two projects has one pin. The first contact shows the server's fingerprint and pins it on
/// confirmation; a pin is checked by ssh itself afterwards (`StrictHostKeyChecking=yes`), and a
/// changed key is refused outright, with no "continue anyway": that is where users click through,
/// and a rebuilt server and an interception look alike from here. The way back is "Host-Key
/// vergessen" (`Connections.forgetHostKey`).
///
/// A pin with a fingerprint and no key (from QuartzControl's pre-split store) gets its key here:
/// the server is asked once, and its key is taken when the fingerprint matches. Every other
/// connection asks the server nothing beforehand: a probe is a refused login, and a host with
/// fail2ban counts those.
public enum HostKeyCheck {
  /// The question to the user: host and fingerprint, true to connect and pin.
  public typealias Confirm = @Sendable (_ host: String, _ fingerprint: String) async -> Bool

  public static func trusted(_ connection: Connection, connections: Connections, environment: ToolEnvironment,
                             confirm: Confirm, configFile: String? = nil) async throws(PublishFailure) -> PinnedHostKey {
    if let pinned = connection.hostKey, !pinned.fingerprint.isEmpty, !pinned.blob.isEmpty, !pinned.type.isEmpty { return pinned }
    let shown: PinnedHostKey
    switch await SSHLogin.probe(connection, environment: environment, configFile: configFile) {
    case .key(let key): shown = key
    case .failed(let output): throw PublishFailure(SSHFailure.translate(output, connection: connection, sftp: true) ?? JS.trim(output))
    }
    if let pinned = connection.hostKey, !pinned.fingerprint.isEmpty {
      guard pinned.fingerprint == shown.fingerprint else {
        throw PublishFailure(L10n.t("main.hostKeyChanged", ["host": connection.host, "expected": pinned.fingerprint, "received": shown.fingerprint]))
      }
      try connections.rememberHostKey(connection.id, shown)
      return shown
    }
    guard await confirm(connection.host, shown.fingerprint) else { throw PublishFailure(L10n.t("main.hostKeyRejected")) }
    try connections.rememberHostKey(connection.id, shown)
    return shown
  }
}
