import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// The ssh transport against a real sshd on this machine (`LocalSSHD`): each login method, the
/// first contact with a host key, a changed one, and ssh's failures in QuartzControl's sentences.
/// ~/.ssh/config is left out (`-F /dev/null`), so the user's settings cannot change the answer.
@Suite(.serialized) struct SSHLoginTests {
  static let none = "/dev/null"

  @Test func aKeyFileLogsIn() async throws {
    let sshd = try await LocalSSHD()
    let connection = sshd.connection(keyPath: sshd.clientKey)
    guard case .key(let shown) = await SSHLogin.probe(connection, environment: sshd.environment, configFile: Self.none) else {
      Issue.record("probe failed \(sshd.log)"); return
    }
    #expect(shown == sshd.hostKey)
    let login = try SSHLogin.prepare(connection, secret: nil, hostKey: shown, environment: [:], configFile: Self.none)
    defer { login.cleanup() }
    let result = await sshd.run(login, ["echo", "ok"])
    #expect(result.success && result.stdout == "ok\n", "\(result.output)")
  }

  /// The fingerprint is ssh-keygen's.
  @Test func theFingerprintIsSshKeygens() async throws {
    let sshd = try await LocalSSHD()
    let listed = await ProcessRunner.run(Command("/usr/bin/ssh-keygen", ["-lf", "\(sshd.root)/host.pub"], environment: ["PATH": "/usr/bin"]))
    #expect(JSText.split(listed.stdout, " ")[1] == sshd.hostKey.fingerprint)
    #expect(sshd.hostKey.type == "ssh-ed25519" && SSHLogin.keyType(blob: Data(base64Encoded: sshd.hostKey.blob)!) == "ssh-ed25519")
    #expect(SSHLogin.keyType(blob: Data([0, 0, 0])) == "" && SSHLogin.keyType(blob: Data([0, 0, 0, 9, 65])) == "")
  }

  /// A key stored as text goes into a 0600 file in a 0700 folder for the call and is gone after.
  @Test func aStoredKeyLogsInAndLeavesNothing() async throws {
    let sshd = try await LocalSSHD()
    let text = String(decoding: try Posix.read(sshd.clientKey), as: UTF8.self)
    let login = try SSHLogin.prepare(sshd.connection(), secret: JS.trim(text), hostKey: sshd.hostKey, environment: [:], configFile: Self.none)
    var info = stat()
    #expect(stat("\(login.directory)/key", &info) == 0 && info.st_mode & 0o777 == 0o600)
    #expect(stat(login.directory, &info) == 0 && info.st_mode & 0o777 == 0o700)
    let result = await sshd.run(login)
    #expect(result.success, "\(result.output)")
    login.cleanup()
    #expect(!Posix.exists(login.directory))
  }

  @Test func whatIsMissingIsASentence() throws {
    let connection = { (method: StoredConnection.AuthMethod, keyPath: String?) in
      Connection(stored: StoredConnection(object: JSONObject([("id", .string("x")), ("kind", .string("ssh")), ("host", .string("h")),
                                                               ("authMethod", .string(method.rawValue))]
                                                              + (keyPath.map { [("keyPath", JSONValue.string($0))] } ?? []))))
    }
    let key = PinnedHostKey(fingerprint: "SHA256:x", blob: "AAAA", type: "ssh-ed25519")
    #expect(throws: PublishFailure(L10n.t("main.sshNoAgent"))) {
      try SSHLogin.prepare(connection(.agent, nil), secret: nil, hostKey: key, environment: [:])
    }
    #expect(throws: PublishFailure(L10n.t("main.sshNoPrivateKey"))) {
      try SSHLogin.prepare(connection(.privateKey, nil), secret: nil, hostKey: key, environment: [:])
    }
    #expect(throws: PublishFailure(L10n.t("main.sshKeyFileUnreadable", ["path": "/nirgends/key"]))) {
      try SSHLogin.prepare(connection(.privateKey, "/nirgends/key"), secret: nil, hostKey: key, environment: [:])
    }
  }

  /// The agent: a key added to an agent of the test's own logs in, with nothing else offered.
  @Test func theAgentLogsIn() async throws {
    let sshd = try await LocalSSHD()
    // A socket path has at most 104 bytes; the scratch folder is longer.
    let socket = "\(NSTemporaryDirectory())qh-agent-\(UUID().uuidString.prefix(8)).sock"
    defer { unlink(socket) }
    let started = await ProcessRunner.run(Command("/usr/bin/ssh-agent", ["-a", socket], environment: ["PATH": "/usr/bin"]))
    let pid = JSText.firstMatch(started.stdout, "SSH_AGENT_PID=(\\d+)")?.groups[1].flatMap { Int32($0) }
    defer { if let pid { kill(pid, SIGTERM) } }
    let added = await ProcessRunner.run(Command("/usr/bin/ssh-add", [sshd.clientKey], environment: ["PATH": "/usr/bin", "SSH_AUTH_SOCK": socket]))
    #expect(added.success, "\(added.output)")
    let login = try SSHLogin.prepare(sshd.connection(.agent), secret: nil, hostKey: sshd.hostKey, environment: ["SSH_AUTH_SOCK": socket],
                                     configFile: Self.none)
    defer { login.cleanup() }
    let result = await sshd.run(login)
    #expect(result.success, "\(result.output)")
  }

  /// A password goes to ssh through the helper, never in argv: the server's log has the attempt.
  @Test func aPasswordIsOfferedThroughTheHelper() async throws {
    let sshd = try await LocalSSHD(config: "PasswordAuthentication yes")
    let login = try SSHLogin.prepare(sshd.connection(.password), secret: "pässwort", hostKey: sshd.hostKey, environment: [:], configFile: Self.none)
    defer { login.cleanup() }
    #expect(!login.options.contains { $0.contains("pässwort") })
    let result = await sshd.run(login)
    #expect(!result.success)
    #expect(JSText.includes(sshd.log, "Failed password for \(sshd.user)"), "\(sshd.log)")
    #expect(SSHFailure.translate(result.output, connection: sshd.connection(.password))?
      .hasPrefix(L10n.t("main.sshPasswordRejected", ["user": sshd.user, "host": "127.0.0.1"])) == true, "\(result.output)")
  }

  /// A key the server does not know: the sentence names the key file, ssh's line underneath.
  @Test func aRefusedKeyNamesTheKeyFile() async throws {
    let sshd = try await LocalSSHD()
    let connection = sshd.connection(keyPath: sshd.strangerKey)
    let login = try SSHLogin.prepare(connection, secret: nil, hostKey: sshd.hostKey, environment: [:], configFile: Self.none)
    defer { login.cleanup() }
    let result = await sshd.run(login)
    let said = SSHFailure.translate(result.output, connection: connection) ?? ""
    #expect(said.hasPrefix(L10n.t("main.rsyncKeyRejected", ["user": sshd.user, "host": "127.0.0.1", "identity": sshd.strangerKey])), "\(said)")
    #expect(JSText.includes(said, "Permission denied (publickey"))
  }

  /// A changed key: ssh refuses it, and the sentence has both fingerprints.
  @Test func aChangedKeyIsRefusedWithBothFingerprints() async throws {
    let sshd = try await LocalSSHD()
    let other = try await LocalSSHD()
    let connection = sshd.connection(keyPath: sshd.clientKey, hostKey: other.hostKey)
    let login = try SSHLogin.prepare(connection, secret: nil, hostKey: other.hostKey, environment: [:], configFile: Self.none)
    defer { login.cleanup() }
    let result = await sshd.run(login)
    #expect(!result.success)
    #expect(SSHFailure.translate(result.output, connection: connection, sftp: true)
      == L10n.t("main.hostKeyChanged", ["host": "127.0.0.1", "expected": other.hostKey.fingerprint, "received": sshd.hostKey.fingerprint]),
      "\(result.output)")
    #expect(SSHFailure.translate(result.output, connection: connection)
      == L10n.t("main.rsyncHostKeyMismatch", ["host": "127.0.0.1", "expected": other.hostKey.fingerprint, "received": sshd.hostKey.fingerprint]))
  }

  /// rsync's errno after a login that worked is not a refused login: the run below is from
  /// debian-vm (rsync 3.5.0, a folder owned by root in the target, 2026-11-10).
  @Test func aRefusedDeletionIsNotARefusedLogin() {
    var object = JSONObject([("id", .string("x")), ("kind", .string("ssh")), ("host", .string("debian.local")),
                             ("port", .number(22)), ("username", .string("boxi"))])
    object["authMethod"] = .string("privateKey")
    object["keyPath"] = .string("/Users/boxi/.ssh/id_ed25519")
    let connection = Connection(stored: StoredConnection(object: object))
    let deletion = """
      rsync: [generator] delete_file: unlink(gesperrt/alt.html) failed: Permission denied (13)
      cannot delete non-empty directory: gesperrt
      .d..t.... ./
      """
    #expect(SSHFailure.translate(deletion, connection: connection) == nil)
    let who = ["user": "boxi", "host": "debian.local", "identity": "/Users/boxi/.ssh/id_ed25519"]
    for refused in ["boxi@debian.local: Permission denied (publickey).", "boxi@debian.local: Permission denied (password).",
                    "boxi@debian.local: Permission denied (publickey,password,keyboard-interactive)."] {
      #expect(SSHFailure.translate(refused, connection: connection)?.hasPrefix(L10n.t("main.rsyncKeyRejected", who)) == true, "\(refused)")
    }
  }

  /// What a run got on debian-vm while macOS had not allowed the local network, against a host
  /// that is merely off.
  @Test func anUnroutedHostNamesTheLocalNetworkPermission() {
    var object = JSONObject([("id", .string("x")), ("kind", .string("ssh")), ("host", .string("debian.local")),
                             ("port", .number(22)), ("username", .string("boxi"))])
    object["authMethod"] = .string("agent")
    let connection = Connection(stored: StoredConnection(object: object))
    let unrouted = "ssh: connect to host debian.local port 22: No route to host"
    #expect(SSHFailure.translate(unrouted, connection: connection)
      == "\(L10n.t("main.hostUnreachableLocalNetwork", ["host": "debian.local"]))\n\n\(unrouted)")
    #expect(SSHFailure.translate("ssh: connect to host 192.168.64.250 port 22: Host is down", connection: connection) == nil)
  }

  @Test func aRefusedPortIsASentence() async throws {
    var object = JSONObject([("id", .string("x")), ("kind", .string("ssh")), ("host", .string("127.0.0.1")),
                             ("port", .number(Double(LocalSSHD.freePort()))), ("username", .string("u"))])
    object["authMethod"] = .string("password")
    let connection = Connection(stored: StoredConnection(object: object))
    let environment = try await LocalSSHD().environment
    guard case .failed(let output) = await SSHLogin.probe(connection, environment: environment, configFile: Self.none) else {
      Issue.record("probe answered"); return
    }
    #expect(SSHFailure.translate(output, connection: connection)?
      .hasPrefix(L10n.t("main.sshPortRefused", ["host": "127.0.0.1", "port": String(connection.port)])) == true, "\(output)")
  }

  final class Asked: Sendable {
    let questions = Mutex<[String]>([])
  }

  /// First contact asks with the fingerprint and pins on yes; no is a sentence and pins nothing; a
  /// pin with a fingerprint only gets its key; a different fingerprint is refused.
  @Test func trustOnFirstUse() async throws {
    let sshd = try await LocalSSHD()
    let profile = TestFolder.make("qh-hostkey")
    defer { try? FileManager.default.removeItem(atPath: profile) }
    let connections = Connections(profile: ProfileDirectory(profile), secrets: MemorySecrets())
    let saved = try connections.save(SaveConnectionInput(kind: .ssh, name: "lokal", host: "127.0.0.1", port: sshd.port, username: sshd.user,
                                                         authMethod: .privateKey, keyPath: sshd.clientKey))
    let asked = Asked()
    await #expect(throws: PublishFailure(L10n.t("main.hostKeyRejected"))) {
      try await HostKeyCheck.trusted(saved, connections: connections, environment: sshd.environment, confirm: { host, print in
        asked.questions.withLock { $0.append("\(host) \(print)") }
        return false
      }, configFile: Self.none)
    }
    #expect(connections.get(saved.id)?.hostKey == nil)
    let trusted = try await HostKeyCheck.trusted(saved, connections: connections, environment: sshd.environment, confirm: { _, _ in true },
                                                 configFile: Self.none)
    #expect(trusted == sshd.hostKey && connections.get(saved.id)?.hostKey == sshd.hostKey)
    #expect(asked.questions.withLock { $0 } == ["127.0.0.1 \(sshd.hostKey.fingerprint)"])
    // Pinned in full: nothing asked, nothing probed (a probe is a refused login the server counts).
    let contacts = JSText.split(sshd.log, "Connection from").count
    #expect(try await HostKeyCheck.trusted(connections.get(saved.id)!, connections: connections, environment: sshd.environment,
                                           confirm: { _, _ in Issue.record("asked again"); return false }, configFile: Self.none) == sshd.hostKey)
    #expect(JSText.split(sshd.log, "Connection from").count == contacts)
    // A fingerprint without its key, as QuartzControl's pre-split store left it.
    try connections.rememberHostKey(saved.id, PinnedHostKey(fingerprint: sshd.hostKey.fingerprint, blob: "", type: ""))
    #expect(try await HostKeyCheck.trusted(connections.get(saved.id)!, connections: connections, environment: sshd.environment,
                                           confirm: { _, _ in false }, configFile: Self.none) == sshd.hostKey)
    #expect(connections.get(saved.id)?.hostKey == sshd.hostKey)
    try connections.rememberHostKey(saved.id, PinnedHostKey(fingerprint: "SHA256:anders", blob: "", type: ""))
    await #expect(throws: PublishFailure(L10n.t("main.hostKeyChanged", ["host": "127.0.0.1", "expected": "SHA256:anders", "received": sshd.hostKey.fingerprint]))) {
      try await HostKeyCheck.trusted(connections.get(saved.id)!, connections: connections, environment: sshd.environment,
                                     confirm: { _, _ in true }, configFile: Self.none)
    }
  }

  @Test func rsyncNeedsAKeyFileAndAPin() {
    let pinned = PinnedHostKey(fingerprint: "SHA256:x", blob: "AAAA", type: "ssh-ed25519")
    let make = { (method: String, keyPath: String?, key: PinnedHostKey?) -> Connection in
      var object = JSONObject([("kind", .string("ssh")), ("authMethod", .string(method))])
      object["keyPath"] = keyPath.map(JSONValue.string)
      object["hostKey"] = key?.json
      return Connection(stored: StoredConnection(object: object))
    }
    #expect(RsyncSupport.blockReason(make("privateKey", "/k", pinned), rsyncAvailable: false) == .notInstalled)
    #expect(RsyncSupport.blockReason(make("password", nil, pinned), rsyncAvailable: true) == .passwordAuth)
    #expect(RsyncSupport.blockReason(make("privateKey", nil, pinned), rsyncAvailable: nil) == .keyNotAFile)
    #expect(RsyncSupport.blockReason(make("privateKey", "", pinned), rsyncAvailable: nil) == .keyNotAFile)
    #expect(RsyncSupport.blockReason(make("agent", nil, PinnedHostKey(fingerprint: "SHA256:x", blob: "", type: "")), rsyncAvailable: true) == .noPinnedHostKey)
    #expect(RsyncSupport.blockReason(make("agent", nil, nil), rsyncAvailable: true) == .noPinnedHostKey)
    #expect(RsyncSupport.blockReason(make("agent", nil, pinned), rsyncAvailable: true) == nil)
    #expect(RsyncSupport.blockReason(make("privateKey", "/k", pinned), rsyncAvailable: nil) == nil)
  }
}
