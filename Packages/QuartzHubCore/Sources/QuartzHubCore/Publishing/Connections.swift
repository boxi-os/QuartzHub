import CryptoKit
import Foundation
import Synchronization

/// A sentence for the user from a publishing service: QuartzControl threw `new Error(mainT(…))`.
public struct PublishFailure: Error, Equatable, CustomStringConvertible {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var description: String { message }

  /// `err.message` of what QuartzControl threw: a sentence, or a file error without "Error: ".
  public static func message(of error: Error) -> String {
    if let failure = error as? PublishFailure { return failure.message }
    let text = String(describing: error)
    return JSText.startsWith(text, "Error: ") ? JSText.slice(text, 7) : text
  }
}

/// A server's host key as the connection trusts it (`PinnedHostKey`): the fingerprint as
/// `ssh-keygen -lf` prints it, the raw key blob in base64 (ssh(1) needs it for a known_hosts line)
/// and its type. A pin taken over from before the connection split has no blob.
public struct PinnedHostKey: Equatable, Sendable {
  public var fingerprint: String
  public var blob: String
  public var type: String

  public init(fingerprint: String, blob: String, type: String) {
    self.fingerprint = fingerprint
    self.blob = blob
    self.type = type
  }

  init?(_ value: JSONValue?) {
    guard let object = value?.objectValue, let fingerprint = object["fingerprint"]?.stringValue else { return nil }
    self.init(fingerprint: fingerprint, blob: object["blob"]?.stringValue ?? "", type: object["type"]?.stringValue ?? "")
  }

  public var json: JSONValue {
    .object(JSONObject([("fingerprint", .string(fingerprint)), ("blob", .string(blob)), ("type", .string(type))]))
  }
}

/// One connection as the pages see it (`toPublic`): no secret, only whether one is stored.
public struct Connection: Equatable, Sendable {
  public let stored: StoredConnection

  public var id: String { stored.id }
  public var kind: StoredConnection.Kind? { stored.kind }
  public var name: String { stored.name }
  public var hasSecret: Bool { stored.secretInKeychain }
  public var host: String { stored.host }
  public var port: Int { stored.port }
  public var username: String { stored.username }
  public var authMethod: StoredConnection.AuthMethod { stored.authMethod }
  public var keyPath: String? { stored.keyPath }
  public var hostKey: PinnedHostKey? { PinnedHostKey(stored.object["hostKey"]) }
  public var secure: Bool { stored.secure }
  /// GitHub: the account's login, for display.
  public var login: String? { stored.login }
  /// Webhook: only the origin of its URL; the path carries the token.
  public var displayOrigin: String? { stored.login }

  /// `toPublic(c)` as JSON, in its key order, for comparing with QuartzControl.
  public var json: JSONValue {
    let raw = stored.object
    func value(_ key: String, _ fallback: JSONValue) -> JSONValue {
      guard let found = raw[key], found != .null else { return fallback }
      return found
    }
    var object = JSONObject()
    object["id"] = raw["id"]
    object["name"] = raw["name"]
    object["hasSecret"] = .bool(hasSecret)
    switch kind {
    case .ssh:
      object["kind"] = .string("ssh")
      object["host"] = value("host", .string(""))
      object["port"] = value("port", .number(22))
      object["username"] = value("username", .string(""))
      object["authMethod"] = value("authMethod", .string("password"))
      object["keyPath"] = raw["keyPath"]
      object["hostKey"] = raw["hostKey"]
    case .ftp:
      object["kind"] = .string("ftp")
      object["host"] = value("host", .string(""))
      object["port"] = value("port", .number(21))
      object["username"] = value("username", .string(""))
      object["secure"] = .bool(stored.secure)
    case .github:
      object["kind"] = .string("github")
      object["login"] = raw["login"]
    case .webhook:
      object["kind"] = .string("webhook")
      object["displayOrigin"] = raw["login"]
    case nil:
      return .null
    }
    return .object(object)
  }
}

/// What the connection form saves (`SaveConnectionInput`). `secret` nil means "leave the stored one
/// alone"; on an edit an empty one means the same, unless the auth method changed.
public struct SaveConnectionInput: Equatable, Sendable {
  public var id: String?
  public var kind: StoredConnection.Kind
  public var name: String
  public var host: String?
  public var port: Int?
  public var username: String?
  public var authMethod: StoredConnection.AuthMethod?
  public var keyPath: String?
  public var secure: Bool?
  public var login: String?
  public var secret: String?

  public init(id: String? = nil, kind: StoredConnection.Kind, name: String, host: String? = nil, port: Int? = nil,
              username: String? = nil, authMethod: StoredConnection.AuthMethod? = nil, keyPath: String? = nil,
              secure: Bool? = nil, login: String? = nil, secret: String? = nil) {
    self.id = id
    self.kind = kind
    self.name = name
    self.host = host
    self.port = port
    self.username = username
    self.authMethod = authMethod
    self.keyPath = keyPath
    self.secure = secure
    self.login = login
    self.secret = secret
  }

  /// Why the input cannot be saved, or nil: QuartzControl's `saveConnectionInput` schema, which the
  /// form and `save` share here (in QuartzControl it guarded the IPC boundary). Lengths count UTF-16
  /// units, as zod does. One rule more than the schema: an SSH or FTP connection needs a host;
  /// QuartzControl's service failed on a missing one with a TypeError.
  /// A host or user name that no ssh, rsync or FTP command line can mistake for something else:
  /// no leading "-", no blank or control character.
  public static func isLoginWord(_ text: String) -> Bool {
    !JSText.startsWith(text, "-") && !text.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
  }

  /// A password or token is one line; a key pasted as text is not. FTP refuses a control
  /// character in `PASS` (basic-ftp names the whole command in its error), and the askpass helper
  /// ends the password with a newline of its own (measured 2026-11-11 with a pasted password).
  var isOneLineSecret: Bool { kind == .ftp || kind == .github || (kind == .ssh && authMethod == .password) }

  /// What a paste leaves at the end of a one-line secret (line breaks) goes; nothing else changes.
  public var normalized: SaveConnectionInput {
    guard isOneLineSecret, var text = secret else { return self }
    while let last = text.unicodeScalars.last, last == "\n" || last == "\r" { text.unicodeScalars.removeLast() }
    var copy = self
    copy.secret = text
    return copy
  }

  /// A one-line secret that still holds a control character after `normalized`.
  public var secretHasControlCharacter: Bool {
    guard isOneLineSecret, let secret = normalized.secret else { return false }
    return secret.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
  }

  public var problem: String? {
    let length = { (text: String) in JSText.length(text) }
    if length(name) < 1 || length(name) > 200 { return "name" }
    if let host, length(JS.trim(host)) < 1 || length(JS.trim(host)) > 255 { return "host" }
    if (kind == .ssh || kind == .ftp) && host == nil { return "host" }
    if let port, port < 1 || port > 65535 { return "port" }
    if let username, length(username) > 255 { return "username" }
    // ssh and rsync would read a leading "-" as an option (review 2026-11-11, N1).
    if let host, !Self.isLoginWord(JS.trim(host)) { return "host" }
    if kind == .ssh, let username, !username.isEmpty, !Self.isLoginWord(username) { return "username" }
    if let keyPath, length(keyPath) < 1 || length(keyPath) > 4096 || !JSText.startsWith(keyPath, "/") { return "keyPath" }
    if let login, length(login) > 255 { return "login" }
    if let secret, length(secret) > 100_000 { return "secret" }
    // A webhook's secret is its URL, https only; empty on an edit keeps the stored one.
    if kind == .webhook, let secret, !(secret.isEmpty && id != nil), WebURL(secret).protocol != "https:" { return "secret" }
    return nil
  }
}

/// The relay's secrets (`RelaySecrets`): the signing secret, the recipient addresses and the
/// captcha secrets, in the key order QuartzControl encrypts them in.
public struct RelaySecrets: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public var secret: String { string("secret") ?? "" }
  public var recipients: JSONObject { object["recipients"]?.objectValue ?? JSONObject() }
  public var captchaSecret: String? { string("captchaSecret") }
  public var captchaSecrets: JSONObject? { object["captchaSecrets"]?.objectValue }
}

/// A change to a project's relay secrets (`saveRelaySecrets`' second argument). In a map, a value
/// of `.null` or a blank string removes the entry; `captchaSecret` nil leaves it, `.remove` drops
/// it, a blank `.set` leaves it too.
public struct RelaySecretsChange: Sendable {
  public enum Edit: Sendable, Equatable {
    case remove
    case set(String)
  }

  public var recipients: JSONObject?
  public var captchaSecret: Edit?
  public var captchaSecrets: JSONObject?
  public var moveCaptchaSecret: (from: String, to: String)?
  public var renewSecret: Bool

  public init(recipients: JSONObject? = nil, captchaSecret: Edit? = nil, captchaSecrets: JSONObject? = nil,
              moveCaptchaSecret: (from: String, to: String)? = nil, renewSecret: Bool = false) {
    self.recipients = recipients
    self.captchaSecret = captchaSecret
    self.captchaSecrets = captchaSecrets
    self.moveCaptchaSecret = moveCaptchaSecret
    self.renewSecret = renewSecret
  }
}

/// What the relay section may know without the secret.
public struct RelaySecretInfo: Equatable, Sendable {
  public let stored: Bool
  public let recipients: [String]
  public let captchaSecret: Bool
  public let captchaSecrets: [String]
  public let fingerprint: String?
}

/// The connections store (`connectionsService.ts`): one list in the profile's `connections.json`,
/// the secrets in the Keychain, one item per secret (`SecretStore`). The relay's secrets sit
/// beside it in `relay-secrets.json`, keyed by project id.
///
/// The file has QuartzControl's form with one field exchanged, as the takeover writes it
/// (docs/formats.md): where QuartzControl has `encryptedSecret`, QuartzHub has
/// `secretInKeychain: true`, in the same place. Nothing from before QuartzControl's first release
/// is migrated (`deploy-secrets.json`, a token in settings.json): the takeover did not take it.
///
/// A read never writes: QuartzControl wrote `[]` the first time it found no file (the migration's
/// empty result); here a missing file is just an empty list.
///
/// A stored secret that cannot be read is a sentence, never nil: every caller reads nil as "no
/// credential", and said so over a stored one (QuartzControl's thirty-seventh review).
public struct Connections: Sendable {
  public let profile: ProfileDirectory
  public let secrets: any SecretStore
  let makeID: @Sendable () -> String
  let randomBytes: @Sendable (Int) -> [UInt8]
  let now: @Sendable () -> Date

  public init(profile: ProfileDirectory, secrets: any SecretStore,
              makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
              randomBytes: @escaping @Sendable (Int) -> [UInt8] = Connections.systemRandom,
              now: @escaping @Sendable () -> Date = { Date() }) {
    self.profile = profile
    self.secrets = secrets
    self.makeID = makeID
    self.randomBytes = randomBytes
    self.now = now
  }

  public static let systemRandom: @Sendable (Int) -> [UInt8] = { count in
    var bytes = [UInt8](repeating: 0, count: count)
    precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess)
    return bytes
  }

  /// Read-modify-write of either file, one at a time within this process.
  static let lock = Mutex(())

  static func account(_ id: String) -> String { "connection:\(id)" }
  static func relayAccount(_ projectId: String) -> String { "relay:\(projectId)" }

  // MARK: connections

  func readAll() -> JSONList<StoredConnection> {
    // A file that cannot be read is not a file that is not there; JSONStore has moved it aside, and
    // this session has no connections rather than a fresh empty store over the old one.
    if case .ok(let value) = JSONStore.read(profile.connections), value.arrayValue != nil { return JSONList(value) }
    return JSONList(items: [])
  }

  func writeAll(_ list: JSONList<StoredConnection>) throws(PublishFailure) {
    do {
      try Posix.mkdirs(profile.path)
      try JSONStore.write(list.json, to: profile.connections)
    } catch {
      throw PublishFailure(String(describing: error))
    }
  }

  public func list() -> [Connection] { readAll().items.map(Connection.init(stored:)) }

  public func get(_ id: String) -> Connection? { readAll().items.first { $0.object["id"] == .string(id) }.map(Connection.init(stored:)) }

  /// `saveConnection`. The secret goes to the Keychain before the file says it is there; a secret
  /// that is no longer wanted is removed after.
  @discardableResult
  public func save(_ given: SaveConnectionInput) throws(PublishFailure) -> Connection {
    let input = given.normalized
    if let problem = input.problem { throw PublishFailure(L10n.t("main.connectionInvalid", ["field": problem])) }
    if input.secretHasControlCharacter { throw PublishFailure(L10n.t("main.connectionSecretControl")) }
    return try Self.lock.withLock { _ throws(PublishFailure) in
      var list = readAll()
      let existing = input.id.flatMap { id in list.items.first { $0.object["id"] == .string(id) } }

      // Changing the auth method invalidates what was stored for the previous one; the one case
      // where an emptied field is not "unchanged".
      let authMethodChanged = input.kind == .ssh && existing?.kind == .ssh
        && existing?.object["authMethod"] != input.authMethod.map { .string($0.rawValue) }
      // An empty field on an edit means "leave the stored secret alone", as the placeholder says.
      let keepStoredSecret = input.secret == nil || (input.secret == "" && existing != nil && !authMethodChanged)

      enum Plan { case keep, set(String), clear }
      var plan: Plan = keepStoredSecret ? .keep : (input.secret!.isEmpty ? .clear : .set(input.secret!))
      // A key read from a file is never copied into the store; with the agent there is nothing to
      // keep either, unless given now.
      if input.kind == .ssh && (input.authMethod == .agent || !(input.keyPath ?? "").isEmpty) {
        plan = (input.secret ?? "").isEmpty ? .clear : .set(input.secret!)
      }

      let id = existing?.object["id"] ?? .string(makeID())
      let account = Self.account(id.stringValue ?? "")
      var hasSecret: Bool
      switch plan {
      case .keep: hasSecret = existing?.secretInKeychain ?? false
      case .clear: hasSecret = false
      case .set(let secret):
        try write(secret, account: account, label: "QuartzHub – \(input.name)")
        hasSecret = true
      }

      var object = JSONObject()
      object["id"] = id
      object["kind"] = .string(input.kind.rawValue)
      object["name"] = .string(input.name)
      object["secretInKeychain"] = hasSecret ? .bool(true) : nil
      // Carried over on edit: a new password does not change which server is trusted.
      object["hostKey"] = existing?.object["hostKey"]
      switch input.kind {
      case .ssh:
        // Trimmed here for every caller: "  DEBIAN.LOCAL " reached the adapters with its spaces.
        object["host"] = .string(JS.trim(input.host ?? ""))
        object["port"] = input.port.map { .number(Double($0)) }
        object["username"] = input.username.map(JSONValue.string)
        object["authMethod"] = input.authMethod.map { .string($0.rawValue) }
        object["keyPath"] = input.keyPath.map(JSONValue.string)
      case .ftp:
        object["host"] = .string(JS.trim(input.host ?? ""))
        object["port"] = input.port.map { .number(Double($0)) }
        object["username"] = input.username.map(JSONValue.string)
        object["secure"] = input.secure.map(JSONValue.bool)
      case .github:
        object["login"] = input.login.map(JSONValue.string)
      case .webhook:
        // Only the origin is kept for display; the path carries the token.
        if !keepStoredSecret, let secret = input.secret, !secret.isEmpty, let parts = WebURL(secret).parts {
          object["login"] = .string(parts.origin)
        } else {
          object["login"] = existing?.object["login"]
        }
      }
      let stored = StoredConnection(object: object)
      list.upsert(stored, id: id.stringValue ?? "")
      try writeAll(list)
      if !hasSecret { try? secrets.delete(account: account) }
      return Connection(stored: stored)
    }
  }

  public func delete(_ id: String) throws(PublishFailure) {
    try Self.lock.withLock { _ throws(PublishFailure) in
      var list = readAll()
      list.entries.removeAll { $0["id"] == .string(id) }
      try writeAll(list)
    }
    try? secrets.delete(account: Self.account(id))
  }

  /// The connection's secret, nil when none is stored; a sentence when one is and cannot be read.
  public func secret(_ id: String) throws(PublishFailure) -> String? {
    guard let found = readAll().items.first(where: { $0.object["id"] == .string(id) }), found.secretInKeychain else { return nil }
    return try read(account: Self.account(id))
  }

  /// The GitHub token: the first GitHub connection with a secret.
  public func githubToken() throws(PublishFailure) -> String? {
    guard let github = readAll().items.first(where: { $0.kind == .github && $0.secretInKeychain }) else { return nil }
    return try read(account: Self.account(github.id))
  }

  /// The token for a push (`GitAuth.Token`): one that is stored and cannot be read fails it.
  public var gitToken: GitAuth.Token { { try githubToken() } }

  /// The token for the marketplaces, where it only raises the rate limit: one that cannot be read
  /// is none (`getGithubToken().catch(() => undefined)`).
  public var rateLimitToken: @Sendable () async -> String? { { try? githubToken() } }

  public func rememberHostKey(_ id: String, _ key: PinnedHostKey) throws(PublishFailure) {
    try Self.lock.withLock { _ throws(PublishFailure) in
      var list = readAll()
      guard let index = list.entries.firstIndex(where: { $0.objectValue != nil && $0["id"] == .string(id) }) else { return }
      var object = list.entries[index].objectValue!
      object["hostKey"] = key.json
      list.entries[index] = .object(object)
      try writeAll(list)
    }
  }

  /// The deliberate way out for a server that changed its key.
  public func forgetHostKey(_ id: String) throws(PublishFailure) {
    try Self.lock.withLock { _ throws(PublishFailure) in
      var list = readAll()
      guard let index = list.entries.firstIndex(where: { $0.objectValue != nil && $0["id"] == .string(id) }),
            var object = list.entries[index].objectValue, object["hostKey"] != nil, object["hostKey"] != .null else { return }
      object["hostKey"] = nil
      list.entries[index] = .object(object)
      try writeAll(list)
    }
  }

  func read(account: String) throws(PublishFailure) -> String {
    let found: String?
    do throws(Keychain.Failure) {
      found = try secrets.read(account: account)
    } catch {
      throw Self.sentence(error, reading: true)
    }
    // The file says there is one and the Keychain has none: deleted there by hand.
    guard let found else { throw PublishFailure(L10n.t("main.secretMissingInKeychain")) }
    return found
  }

  func write(_ secret: String, account: String, label: String) throws(PublishFailure) {
    do throws(Keychain.Failure) {
      try secrets.write(secret, account: account, label: label)
    } catch {
      throw Self.sentence(error, reading: false)
    }
  }

  static func sentence(_ failure: Keychain.Failure, reading: Bool) -> PublishFailure {
    switch failure {
    case .denied: PublishFailure(reading ? L10n.t("main.secretStorageUnreadableMac") : L10n.t("main.secretStorageUnavailableMac"))
    case .notFound: PublishFailure(L10n.t("main.secretMissingInKeychain"))
    case .other(let status): PublishFailure(L10n.t("main.keychainFailed", ["status": String(status)]))
    }
  }

  // MARK: the relay's secrets

  func readRelayStore() -> JSONMap<StoredRelaySecrets> {
    if case .ok(let value) = JSONStore.read(profile.relaySecrets), value.objectValue != nil { return JSONMap(value) }
    return JSONMap(.object(JSONObject()))
  }

  public func relaySecretInfo(_ projectId: String) -> RelaySecretInfo {
    let entry = readRelayStore()[projectId]
    return RelaySecretInfo(stored: entry != nil, recipients: entry?.recipients ?? [], captchaSecret: entry?.captchaSecret ?? false,
                           captchaSecrets: entry?.captchaSecrets ?? [], fingerprint: entry?.fingerprint)
  }

  /// The projects with a recipient address or a captcha secret stored, from the names beside the
  /// secret. The signing secret alone does not count: it is made anew and asks for nothing.
  public func projectsWithRelaySecrets() -> Set<String> {
    let all = readRelayStore()
    return Set(all.keys.filter { key in
      guard let entry = all[key] else { return false }
      return !entry.recipients.isEmpty || entry.captchaSecret || !entry.captchaSecrets.isEmpty
    })
  }

  /// The secrets, nil when none are stored.
  public func relaySecrets(_ projectId: String) throws(PublishFailure) -> RelaySecrets? {
    guard let entry = readRelayStore()[projectId], entry.secretInKeychain else { return nil }
    let plain: String
    do throws(PublishFailure) {
      plain = try read(account: Self.relayAccount(projectId))
    } catch where error == PublishFailure(L10n.t("main.secretMissingInKeychain")) {
      // Said where they are entered, the relay section, not under the connections.
      throw PublishFailure(L10n.t("relay.secretsMissing"))
    }
    guard let object = (try? JSJSON.parse(Data(plain.utf8)))?.objectValue else { return nil }
    return RelaySecrets(object: object)
  }

  /// `saveRelaySecrets`: merges a change in. The signing secret is made the first time anything is
  /// stored and kept (the relay signs its stamps with it); only `renewSecret` makes a new one.
  public func saveRelaySecrets(_ projectId: String, _ change: RelaySecretsChange) throws(PublishFailure) {
    try Self.lock.withLock { _ throws(PublishFailure) in
      var all = readRelayStore()
      // A rename asks after every form; the stored names answer without the Keychain when there is
      // nothing to carry.
      if let move = change.moveCaptchaSecret, change.recipients == nil, change.captchaSecret == nil, change.captchaSecrets == nil,
         !change.renewSecret, !(all[projectId]?.captchaSecrets.contains(move.from) ?? false) {
        return
      }
      // Missing from the Keychain although the file names them (another Mac, an item deleted):
      // what is lost is lost, and the change starts a new set instead of failing every save, which
      // left no way to enter an address again (measured 2026-11-11).
      let current: RelaySecrets?
      do throws(PublishFailure) {
        current = try relaySecrets(projectId)
      } catch where error == PublishFailure(L10n.t("relay.secretsMissing")) {
        current = nil
      }
      // QuartzControl made the default's secret first and a renewed one after it: two draws.
      let fresh = current == nil ? Self.base64url(randomBytes(32)) : nil
      var recipients = current?.recipients ?? JSONObject()
      for name in change.recipients?.keys ?? [] {
        let address = change.recipients![name]!.stringValue.map(JS.trim) ?? ""
        recipients[name] = address.isEmpty ? nil : .string(address)
      }
      var captchaSecrets = current?.captchaSecrets ?? JSONObject()
      if let move = change.moveCaptchaSecret, move.from != move.to, let moved = captchaSecrets[move.from] {
        captchaSecrets[move.to] = moved
        captchaSecrets[move.from] = nil
      }
      for form in change.captchaSecrets?.keys ?? [] {
        let value = change.captchaSecrets![form]!.stringValue.map(JS.trim) ?? ""
        captchaSecrets[form] = value.isEmpty ? nil : .string(value)
      }
      // Truthiness, as `captchaSecret ? { captchaSecret } : {}`: an empty one is none.
      var captchaSecret = current?.captchaSecret.flatMap { $0.isEmpty ? nil : $0 }
      switch change.captchaSecret {
      case .remove: captchaSecret = nil
      case .set(let value) where !JS.trim(value).isEmpty: captchaSecret = JS.trim(value)
      default: break
      }
      let secret = change.renewSecret ? Self.base64url(randomBytes(32)) : current?.secret ?? fresh!
      var next = JSONObject()
      next["secret"] = .string(secret)
      next["recipients"] = .object(recipients)
      next["captchaSecret"] = captchaSecret.map(JSONValue.string)
      next["captchaSecrets"] = captchaSecrets.keys.isEmpty ? nil : .object(captchaSecrets)
      try write(JSJSON.compact(.object(next)), account: Self.relayAccount(projectId), label: "QuartzHub – Relay")

      var entry = JSONObject()
      entry["secretInKeychain"] = .bool(true)
      entry["recipients"] = .array(recipients.keys.map(JSONValue.string))
      entry["captchaSecret"] = .bool(captchaSecret != nil)
      entry["captchaSecrets"] = .array(captchaSecrets.keys.map(JSONValue.string))
      entry["updatedAt"] = .string(JS.isoString(now()))
      entry["fingerprint"] = .string(Self.fingerprint(secret: secret, recipients: recipients, captchaSecret: captchaSecret,
                                                      captchaSecrets: captchaSecrets))
      all[projectId] = StoredRelaySecrets(object: entry)
      try writeRelayStore(all)
    }
  }

  /// Removes a project's relay secrets (the project left the app).
  public func deleteRelaySecrets(_ projectId: String) throws(PublishFailure) {
    try Self.lock.withLock { _ throws(PublishFailure) in
      var all = readRelayStore()
      guard all[projectId] != nil else { return }
      all.object[projectId] = nil
      try writeRelayStore(all)
    }
    try? secrets.delete(account: Self.relayAccount(projectId))
  }

  func writeRelayStore(_ all: JSONMap<StoredRelaySecrets>) throws(PublishFailure) {
    do {
      try Posix.mkdirs(profile.path)
      try JSONStore.write(all.json, to: profile.relaySecrets)
    } catch {
      throw PublishFailure(String(describing: error))
    }
  }

  /// `secretsFingerprint`: an HMAC over the addresses and captcha secrets, keyed with the signing
  /// secret, so the relay's status can tell a change since the upload without the Keychain.
  static func fingerprint(secret: String, recipients: JSONObject, captchaSecret: String?, captchaSecrets: JSONObject) -> String {
    func sorted(_ record: JSONObject) -> JSONValue {
      var keys = record.keys
      JS.sort(&keys) { JS.localeCompare($0, $1) }
      return .array(keys.map { .array([.string($0), record[$0]!]) })
    }
    let values: JSONValue = .array([sorted(recipients), captchaSecret.map(JSONValue.string) ?? .null, sorted(captchaSecrets)])
    let mac = HMAC<SHA256>.authenticationCode(for: Data(JSJSON.compact(values).utf8), using: SymmetricKey(data: Data(secret.utf8)))
    return String(mac.map { String(format: "%02x", $0) }.joined().prefix(32))
  }

  static func base64url(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-", options: .literal)
      .replacingOccurrences(of: "/", with: "_", options: .literal).replacingOccurrences(of: "=", with: "", options: .literal)
  }
}

extension StoredConnection {
  /// QuartzHub's own field in place of `encryptedSecret`: the secret is in the Keychain.
  public var secretInKeychain: Bool { isTrue("secretInKeychain") }
}

extension StoredRelaySecrets {
  public var secretInKeychain: Bool { isTrue("secretInKeychain") }
}
