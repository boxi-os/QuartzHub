import CryptoKit
import Foundation

/// How QuartzHub reaches an SSH server: through the system's OpenSSH (`/usr/bin/ssh`), for SFTP
/// (`ssh -s sftp`, the protocol spoken by `SFTPChannel`) and for rsync alike (decision of
/// 2026-11-06, docs/decisions/phase-3-dienste.md, point 8b). QuartzControl used ssh2 for SFTP and
/// ssh for rsync; one transport for both means one way of pinning, one set of keepalives and every
/// key type and the agent, as the user's own ssh has them.
///
/// The options are the ones QuartzControl gave rsync's ssh, plus what ssh2 did for SFTP:
/// - the pinned host key as the only known host (`StrictHostKeyChecking=yes`, a throwaway
///   known_hosts, the system's and the user's ignored, nothing written back);
/// - keepalives: four unanswered 15 s probes end the connection, 45 to 60 s after the last answer;
/// - per auth method: the agent (BatchMode, so nothing can prompt behind a pipe nobody reads), a key
///   file (`-i` and nothing else), a key stored as text (written to a 0600 file in a 0700 folder
///   for the one call), a password (handed to ssh by an askpass helper from this call's
///   environment, never in argv).
/// The user's ~/.ssh/config still applies, as it did to QuartzControl's rsync.
public struct SSHLogin: Sendable {
  public static let keepaliveSeconds = 15
  public static let keepaliveCount = 3
  /// When a silent connection ends: at the fourth unanswered keepalive.
  public static let silentSeconds = keepaliveSeconds * (keepaliveCount + 1)

  public let connection: Connection
  /// The temporary folder with known_hosts, the askpass helper or the key; nil until prepared.
  public let directory: String
  /// Everything before the host in an ssh command line.
  public let options: [String]
  /// For the child's environment, on top of its own.
  public let variables: [String: String]

  public var host: String { connection.host }

  /// Removes the folder with the known_hosts file, the helper and a stored key.
  public func cleanup() {
    try? FileManager.default.removeItem(atPath: directory)
  }

  /// "host key-type base64", with the bracketed form ssh uses whenever the port is not 22.
  static func knownHostsLine(host: String, port: Int, key: PinnedHostKey) -> String {
    let name = port == 22 ? host : "[\(host)]:\(port)"
    return "\(name) \(key.type) \(key.blob)\n"
  }

  static func temporaryFolder(_ prefix: String) throws(PublishFailure) -> String {
    var template = Array("\(NSTemporaryDirectory())\(prefix)-XXXXXX".utf8CString)
    guard let made = mkdtemp(&template) else { throw PublishFailure(String(describing: Posix.error("mkdtemp", NSTemporaryDirectory()))) }
    return String(cString: made)
  }

  /// The options every connection gets.
  static func common(port: Int, knownHosts: String, configFile: String?) -> [String] {
    var options: [String] = []
    if let configFile { options += ["-F", configFile] }
    for option in ["UserKnownHostsFile=\(knownHosts)", "GlobalKnownHostsFile=/dev/null", "StrictHostKeyChecking=yes", "UpdateHostKeys=no",
                   "ServerAliveInterval=\(keepaliveSeconds)", "ServerAliveCountMax=\(keepaliveCount)", "ConnectTimeout=20"] {
      options += ["-o", option]
    }
    return options + ["-p", String(port)]
  }

  /// A login with `hostKey` as the one trusted key. `environment` is the child's (for the agent's
  /// socket); `configFile` replaces ~/.ssh/config (the tests' `/dev/null`).
  public static func prepare(_ connection: Connection, secret: String?, hostKey: PinnedHostKey, environment: [String: String],
                             configFile: String? = nil) throws(PublishFailure) -> SSHLogin {
    let directory = try temporaryFolder("qh-ssh")
    do {
      let knownHosts = "\(directory)/known_hosts"
      try Posix.write(knownHosts, Data(knownHostsLine(host: connection.host, port: connection.port, key: hostKey).utf8))
      var options = common(port: connection.port, knownHosts: knownHosts, configFile: configFile)
      var variables: [String: String] = [:]
      switch connection.authMethod {
      case .agent:
        guard let socket = environment["SSH_AUTH_SOCK"], !socket.isEmpty else { throw PublishFailure(L10n.t("main.sshNoAgent")) }
        variables["SSH_AUTH_SOCK"] = socket
        options += ["-o", "BatchMode=yes"]
      case .privateKey:
        let keyFile: String
        if let path = connection.keyPath, !path.isEmpty {
          // ssh warns about a key file it cannot open and goes on without it, and the server's
          // "Permission denied (publickey)" then blames the far end for a file never read.
          guard access(path, R_OK) == 0 else { throw PublishFailure(L10n.t("main.sshKeyFileUnreadable", ["path": path])) }
          keyFile = path
        } else {
          guard let secret, !secret.isEmpty else { throw PublishFailure(L10n.t("main.sshNoPrivateKey")) }
          keyFile = "\(directory)/key"
          let text = JSText.endsWith(secret, "\n") ? secret : secret + "\n"
          let fd = open(keyFile, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
          guard fd >= 0 else { throw PublishFailure(String(describing: Posix.error("open", keyFile))) }
          _ = text.utf8CString.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count - 1) }
          close(fd)
        }
        options += ["-i", keyFile, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes"]
      case .password:
        // BatchMode would turn the askpass helper off; one prompt, no key offered first.
        let helper = "\(directory)/askpass.sh"
        try Posix.write(helper, Data("#!/bin/sh\nprintf '%s\\n' \"$QH_SSH_PASSWORD\"\n".utf8))
        chmod(helper, 0o700)
        variables["SSH_ASKPASS"] = helper
        variables["SSH_ASKPASS_REQUIRE"] = "force"
        variables["QH_SSH_PASSWORD"] = secret ?? ""
        options += ["-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "PubkeyAuthentication=no",
                    "-o", "NumberOfPasswordPrompts=1"]
      }
      return SSHLogin(connection: connection, directory: directory, options: options + ["-l", connection.username], variables: variables)
    } catch {
      try? FileManager.default.removeItem(atPath: directory)
      throw error as? PublishFailure ?? PublishFailure(String(describing: error))
    }
  }

  // MARK: host keys

  /// OpenSSH's fingerprint: base64 of the SHA-256 over the raw key blob, unpadded, as
  /// `ssh-keygen -lf` prints it, so it can be compared with what a provider publishes.
  public static func fingerprint(blob: Data) -> String {
    "SHA256:" + JSText.replaceAll(Data(SHA256.hash(data: blob)).base64EncodedString(), "=+\\z", with: "")
  }

  /// The algorithm a key blob names first (RFC 4253 §6.6): a length-prefixed string.
  public static func keyType(blob: Data) -> String {
    let bytes = [UInt8](blob)
    guard bytes.count >= 4 else { return "" }
    let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
    guard length > 0, length <= bytes.count - 4 else { return "" }
    return String(decoding: bytes[4..<(4 + length)], as: UTF8.self)
  }

  public enum Probe: Sendable, Equatable {
    case key(PinnedHostKey)
    /// ssh did not get as far as the key; its output.
    case failed(String)
  }

  /// The key the server shows, the one ssh negotiates and would check later: ssh takes it into an
  /// empty known_hosts (`accept-new`) and is then refused every login method.
  public static func probe(_ connection: Connection, environment: ToolEnvironment, configFile: String? = nil) async -> Probe {
    guard let directory = try? temporaryFolder("qh-ssh-probe") else { return .failed("mkdtemp") }
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let knownHosts = "\(directory)/known_hosts"
    var options = common(port: connection.port, knownHosts: knownHosts, configFile: configFile)
    options = options.map { $0 == "StrictHostKeyChecking=yes" ? "StrictHostKeyChecking=accept-new" : $0 }
    for option in ["BatchMode=yes", "PubkeyAuthentication=no", "PasswordAuthentication=no", "KbdInteractiveAuthentication=no",
                   "HostbasedAuthentication=no", "GSSAPIAuthentication=no", "IdentityAgent=none"] {
      options += ["-o", option]
    }
    let command = environment.command("ssh", options + ["-l", connection.username, connection.host, "true"])
    let result = await ProcessRunner.run(command)
    let line = String(decoding: (try? Posix.read(knownHosts)) ?? Data(), as: UTF8.self)
    let fields = JSText.split(JS.trim(line), " ")
    guard fields.count >= 3, let blob = Data(base64Encoded: fields[2]) else { return .failed(result.report(for: command)) }
    return .key(PinnedHostKey(fingerprint: fingerprint(blob: blob), blob: fields[2], type: keyType(blob: blob)))
  }
}
