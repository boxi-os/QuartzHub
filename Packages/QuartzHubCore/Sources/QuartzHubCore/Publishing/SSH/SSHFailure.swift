import Foundation

/// ssh's own failure text is written for a terminal (`translateSshFailure` in deploy/rsync.ts):
/// the host-key warning is a wall of "@" that ends by telling the user to edit a known_hosts file
/// that is a throwaway. The failures that happen get QuartzControl's sentences, with ssh's own
/// lines underneath where they are short; anything else is passed through as it is.
///
/// With ssh as the transport for SFTP too, the SFTP adapter's sentences for a refused login, a
/// refused port and silence (`loginRefused`, `unreached` in sftp.ts, written against ssh2's
/// messages) are said for ssh's lines here: "Permission denied (…)" is ssh2's "All configured
/// authentication methods failed".
public enum SSHFailure {
  /// The sentence for `output` of a failed ssh, or nil to pass it through. `hostKeyMismatch` is
  /// rsync's wording; SFTP finds a changed key before it connects (`HostKeyCheck`).
  public static func translate(_ output: String, connection: Connection, sftp: Bool = false) -> String? {
    let raw = JS.trim(output)
    if JSText.includes(output, "REMOTE HOST IDENTIFICATION HAS CHANGED") || JSText.includes(output, "Host key verification failed") {
      let received = JSText.firstMatch(output, "SHA256:[A-Za-z0-9+/=]+")?.groups[0] ?? L10n.t("main.unknownFingerprint")
      let expected = connection.hostKey?.fingerprint ?? "—"
      // SFTP says what QuartzControl's host verifier said; it found the change in the handshake.
      return sftp
        ? L10n.t("main.hostKeyChanged", ["host": connection.host, "expected": expected, "received": received])
        : L10n.t("main.rsyncHostKeyMismatch", ["host": connection.host, "expected": expected, "received": received])
    }
    if JSText.includes(output, "Too many authentication failures") {
      guard connection.authMethod == .agent else { return nil }
      return "\(L10n.t("main.sshTooManyKeys", ["user": connection.username, "host": connection.host]))\n\n\(raw)"
    }
    if refusedLogin(output) {
      return "\(loginRefused(connection))\n\n\(raw)"
    }
    if JSText.test(output, "Timeout, server .* not responding") {
      return "\(L10n.t("main.sshSilent", ["host": connection.host, "seconds": String(SSHLogin.silentSeconds)]))\n\n\(raw)"
    }
    if JSText.test(output, "port \\d+: Connection refused") {
      return "\(L10n.t("main.sshPortRefused", ["host": connection.host, "port": String(connection.port)]))\n\n\(raw)"
    }
    return nil
  }

  /// ssh's refused login, "user@host: Permission denied (publickey,password).": the parentheses
  /// hold the methods the server offered. QuartzControl matches "Permission denied (publickey"
  /// only; a password-only server says "(password)", so this takes any list of method names, but
  /// not rsync's errno, "unlink(gesperrt/alt.html) failed: Permission denied (13)". That line,
  /// from a folder owned by root on debian-vm (2026-11-10), was reported as the server refusing the
  /// key the run had just logged in with.
  static func refusedLogin(_ output: String) -> Bool {
    JSText.test(output, #"Permission denied \([a-z-]+(?:,[a-z-]+)*\)"#)
  }

  /// Which sentence a refused login gets: the advice about a key's .pub file fits only a key file.
  static func loginRefused(_ connection: Connection) -> String {
    let who = ["user": connection.username, "host": connection.host]
    switch connection.authMethod {
    case .password: return L10n.t("main.sshPasswordRejected", who)
    case .privateKey where (connection.keyPath ?? "").isEmpty: return L10n.t("main.sshStoredKeyRejected", who)
    case .agent: return L10n.t("main.sshAgentRejected", who)
    case .privateKey:
      return L10n.t("main.rsyncKeyRejected", who.merging(["identity": connection.keyPath ?? ""]) { a, _ in a })
    }
  }
}

/// Whether a connection can be used with rsync (`shared/rsyncSupport.ts`): one rule for the target
/// form and the adapter. QuartzHub runs on macOS only, so "platform-unsupported" is gone.
public enum RsyncSupport {
  public enum BlockReason: String, Sendable {
    /// ssh cannot take a password from rsync's wrapper.
    case passwordAuth = "password-auth"
    /// ssh needs a key file; a key pasted as text lives only in the Keychain.
    case keyNotAFile = "key-not-a-file"
    /// A known_hosts line needs the raw key, which a fingerprint alone does not give.
    case noPinnedHostKey = "no-pinned-host-key"
    case notInstalled = "not-installed"
  }

  /// `rsyncAvailable` nil: not known yet, no blocker (the adapter asks again before it starts).
  public static func blockReason(_ connection: Connection, rsyncAvailable: Bool?) -> BlockReason? {
    if rsyncAvailable == false { return .notInstalled }
    if connection.authMethod == .password { return .passwordAuth }
    if connection.authMethod == .privateKey && (connection.keyPath ?? "").isEmpty { return .keyNotAFile }
    if (connection.hostKey?.blob ?? "").isEmpty { return .noPinnedHostKey }
    return nil
  }
}
