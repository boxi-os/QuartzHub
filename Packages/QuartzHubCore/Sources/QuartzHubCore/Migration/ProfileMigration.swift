import Foundation

/// Taking over QuartzControl's profile on QuartzHub's first start (docs/plan.md, Phase 2): the
/// project list, the settings, the connections and the relay secrets. QuartzControl's files are
/// only read (`JSONStore.peek`, never moved aside), its Keychain item only read; everything lands
/// in QuartzHub's own profile and Keychain items, so QuartzControl keeps working as before.
///
/// Two steps, so the app can show what will happen before anything is written: `plan` reads,
/// `run` writes. `projects.json` is written last and is the marker that the takeover happened: a
/// run that stops halfway leaves no project list, and the next start offers it again.
public enum ProfileMigration {
  public struct Plan: Equatable, Sendable {
    public var projects: [ProjectEntry] = []
    /// Project folders that are not there any more. They are taken over all the same, as
    /// QuartzControl keeps them; the start page shows them as missing.
    public var missingProjectPaths: [String] = []
    public var settings: SettingsFile?
    public var connections: [StoredConnection] = []
    public var relaySecrets: [(projectId: String, secrets: StoredRelaySecrets)] = []
    /// Files of QuartzControl's that exist but could not be read; they are left alone.
    public var unreadable: [String] = []
    /// Leftovers from before QuartzControl's first release that QuartzHub does not take over.
    public var legacy: [String] = []

    public var secretCount: Int {
      connections.filter(\.hasSecret).count + relaySecrets.filter { $0.secrets.encrypted?.isEmpty == false }.count
    }
    public var isEmpty: Bool { projects.isEmpty && connections.isEmpty && settings == nil && relaySecrets.isEmpty }

    public static func == (lhs: Plan, rhs: Plan) -> Bool {
      lhs.projects == rhs.projects && lhs.missingProjectPaths == rhs.missingProjectPaths && lhs.settings == rhs.settings
        && lhs.connections == rhs.connections && lhs.unreadable == rhs.unreadable && lhs.legacy == rhs.legacy
        && lhs.relaySecrets.map(\.projectId) == rhs.relaySecrets.map(\.projectId)
        && lhs.relaySecrets.map(\.secrets) == rhs.relaySecrets.map(\.secrets)
    }
  }

  public struct Report: Equatable, Sendable {
    public var projects = 0
    public var connections = 0
    public var secretsMoved = 0
    /// Connection ids and relay project ids whose secret could not be taken over (no key, wrong
    /// key, damaged): those have to be entered again in QuartzHub.
    public var secretsLost: [String] = []
    public var settings = false
    /// A file of QuartzControl's could not be read: nothing marks the takeover done, so the next
    /// start offers it again.
    public var offeredAgain = false
  }

  public enum Failure: Error, Equatable {
    /// QuartzHub already has a project list: the takeover only runs on a first start.
    case alreadyTakenOver
    case write(String)
  }

  /// Whether QuartzHub should offer the takeover: its own list is missing and QuartzControl's
  /// profile has one.
  public static func shouldOffer(source: ProfileDirectory = .quartzControl, target: ProfileDirectory = .quartzHub) -> Bool {
    JSONStore.peek(target.projects) == .missing && FileManager.default.fileExists(atPath: source.projects)
  }

  public static func plan(source: ProfileDirectory) -> Plan {
    var plan = Plan()
    func load(_ path: String) -> JSONValue? {
      switch JSONStore.peek(path) {
      case .ok(let value): return value
      case .missing: return nil
      case .unreadable: plan.unreadable.append(NodePath.basename(path)); return nil
      }
    }

    if let value = load(source.projects) {
      if value.arrayValue == nil { plan.unreadable.append(NodePath.basename(source.projects)) }
      plan.projects = JSONList<ProjectEntry>(value).items
      plan.missingProjectPaths = plan.projects.map(\.path).filter { !FileManager.default.fileExists(atPath: $0) }
    }
    if let value = load(source.settings) {
      if let object = value.objectValue {
        let settings = SettingsFile(object: object)
        plan.settings = settings
        if settings.hasLegacyGithubToken { plan.legacy.append("settings.json: githubToken") }
      } else {
        plan.unreadable.append(NodePath.basename(source.settings))
      }
    }
    if let value = load(source.connections) {
      if value.arrayValue == nil { plan.unreadable.append(NodePath.basename(source.connections)) }
      plan.connections = JSONList<StoredConnection>(value).items
    }
    // Not an object is unreadable like the others, and the leftovers below are still listed.
    if let value = load(source.relaySecrets) {
      if let object = value.objectValue {
        plan.relaySecrets = object.keys.compactMap { key in
          object[key]?.objectValue.map { (key, StoredRelaySecrets(object: $0)) }
        }
      } else {
        plan.unreadable.append(NodePath.basename(source.relaySecrets))
      }
    }
    for name in ["deploy-secrets.json", "legacy-publish-targets.json"]
    where FileManager.default.fileExists(atPath: source.file(name)) {
      plan.legacy.append(name)
    }
    return plan
  }

  /// Writes the plan into QuartzHub's profile. `secretKey` yields the key for QuartzControl's
  /// secrets (reading "QuartzControl Safe Storage" asks the user); nil means "without secrets".
  /// `storeSecret` keeps one secret; the app passes the Keychain, the tests a dictionary.
  public static func run(
    _ plan: Plan,
    target: ProfileDirectory,
    secretKey: Data?,
    storeSecret: (_ account: String, _ label: String, _ secret: String) throws -> Void
  ) throws(Failure) -> Report {
    guard JSONStore.peek(target.projects) == .missing else { throw .alreadyTakenOver }
    var report = Report()
    do {
      try Posix.mkdirs(target.path)
    } catch {
      throw .write(target.path)
    }

    func secret(_ encrypted: String?, account: String, label: String, id: String) -> Bool {
      guard let encrypted, !encrypted.isEmpty else { return false }
      guard let secretKey, let plain = try? ChromiumSafeStorage.decrypt(base64: encrypted, key: secretKey),
            (try? storeSecret(account, label, plain)) != nil
      else {
        report.secretsLost.append(id)
        return false
      }
      report.secretsMoved += 1
      return true
    }

    // Connections: the same objects without `encryptedSecret`; `secretInKeychain` says where the
    // secret went (QuartzHub's own field, docs/formats.md).
    // A second run (the first could not read everything) keeps what QuartzHub has by now, and
    // its secrets.
    let kept = existingItems(target.connections)
    let keptIds = Set(kept.compactMap { $0.objectValue?["id"]?.stringValue })
    let newConnections = plan.connections.filter { !keptIds.contains($0.id) }
    if !newConnections.isEmpty {
      let moved: [StoredConnection] = newConnections.map { connection in
        var copy = connection
        let stored = secret(connection.encryptedSecret, account: "connection:\(connection.id)",
                            label: "QuartzHub – \(connection.name)", id: connection.id)
        copy.encryptedSecret = nil
        if stored { copy.object["secretInKeychain"] = .bool(true) }
        return copy
      }
      try write(.array(kept + JSONList(items: moved).json.arrayValue!), to: target.connections)
      report.connections = moved.count
    }

    if !plan.relaySecrets.isEmpty {
      var object = JSONObject()
      if case .ok(let value) = JSONStore.peek(target.relaySecrets), let existing = value.objectValue { object = existing }
      for (projectId, entry) in plan.relaySecrets where object[projectId] == nil {
        var copy = entry
        let stored = secret(entry.encrypted, account: "relay:\(projectId)", label: "QuartzHub – Relay", id: projectId)
        copy.object["encrypted"] = nil
        if stored { copy.object["secretInKeychain"] = .bool(true) }
        object[projectId] = copy.json
      }
      try write(.object(object), to: target.relaySecrets)
    }

    if var settings = plan.settings, JSONStore.peek(target.settings) == .missing {
      settings.object["githubToken"] = nil
      settings.object["githubTokenEncrypted"] = nil
      try write(settings.json, to: target.settings)
      report.settings = true
    }

    // Last: the marker that the takeover is done. Not while one of QuartzControl's files could not
    // be read: that would mark it done for good, and what the file holds would never come over
    // once it is repaired (review 2026-11-11, N3). The next start offers it again; what was taken
    // now is written again then, the same way.
    if !plan.unreadable.isEmpty {
      report.offeredAgain = true
      return report
    }
    try write(JSONList(items: plan.projects).json, to: target.projects)
    report.projects = plan.projects.count
    return report
  }

  // MARK: - Secrets later

  /// Secrets QuartzControl still holds for connections and relays that came over without one: the
  /// Keychain question was denied, or the key did not fit then (review 2026-11-11, N3). Matched by
  /// id; what QuartzHub already has a secret for is never touched.
  public struct PendingSecrets: Equatable, Sendable {
    public var connections: [String: String] = [:]
    public var relays: [String: String] = [:]
    public var count: Int { connections.count + relays.count }
    public init() {}
  }

  public static func pendingSecrets(source: ProfileDirectory, target: ProfileDirectory) -> PendingSecrets {
    var pending = PendingSecrets()
    func items(_ path: String) -> [JSONValue] {
      if case .ok(let value) = JSONStore.peek(path) { return value.arrayValue ?? [] }
      return []
    }
    func object(_ path: String) -> JSONObject {
      if case .ok(let value) = JSONStore.peek(path) { return value.objectValue ?? JSONObject() }
      return JSONObject()
    }
    var theirs: [String: String] = [:]
    for item in items(source.connections) {
      let connection = StoredConnection(object: item.objectValue ?? JSONObject())
      if let encrypted = connection.encryptedSecret, !encrypted.isEmpty { theirs[connection.id] = encrypted }
    }
    for item in items(target.connections) {
      let connection = StoredConnection(object: item.objectValue ?? JSONObject())
      if !connection.secretInKeychain, let encrypted = theirs[connection.id] { pending.connections[connection.id] = encrypted }
    }
    let theirRelays = object(source.relaySecrets), ourRelays = object(target.relaySecrets)
    for projectId in ourRelays.keys {
      guard let ours = ourRelays[projectId]?.objectValue, ours["secretInKeychain"] != .bool(true),
            let encrypted = theirRelays[projectId]?.objectValue.map({ StoredRelaySecrets(object: $0) })?.encrypted, !encrypted.isEmpty
      else { continue }
      pending.relays[projectId] = encrypted
    }
    return pending
  }

  /// Takes `pending` over as the first run would have, and marks each one stored in QuartzHub's
  /// files. What still fails is counted in `secretsLost` again.
  public static func takeOverSecrets(
    _ pending: PendingSecrets,
    target: ProfileDirectory,
    secretKey: Data?,
    storeSecret: (_ account: String, _ label: String, _ secret: String) throws -> Void
  ) throws(Failure) -> Report {
    var report = Report()
    func store(_ encrypted: String, account: String, label: String, id: String) -> Bool {
      guard let secretKey, let plain = try? ChromiumSafeStorage.decrypt(base64: encrypted, key: secretKey),
            (try? storeSecret(account, label, plain)) != nil
      else {
        report.secretsLost.append(id)
        return false
      }
      report.secretsMoved += 1
      return true
    }
    if !pending.connections.isEmpty, case .ok(let value) = JSONStore.peek(target.connections), var items = value.arrayValue {
      for index in items.indices {
        guard var object = items[index].objectValue, let id = object["id"]?.stringValue, let encrypted = pending.connections[id] else { continue }
        let name = StoredConnection(object: object).name
        if store(encrypted, account: "connection:\(id)", label: "QuartzHub – \(name)", id: id) {
          object["secretInKeychain"] = .bool(true)
          items[index] = .object(object)
        }
      }
      try write(.array(items), to: target.connections)
    }
    if !pending.relays.isEmpty, case .ok(let value) = JSONStore.peek(target.relaySecrets), var object = value.objectValue {
      for projectId in pending.relays.keys.sorted() {
        guard var entry = object[projectId]?.objectValue, let encrypted = pending.relays[projectId] else { continue }
        if store(encrypted, account: "relay:\(projectId)", label: "QuartzHub – Relay", id: projectId) {
          entry["secretInKeychain"] = .bool(true)
          object[projectId] = .object(entry)
        }
      }
      try write(.object(object), to: target.relaySecrets)
    }
    return report
  }

  static func existingItems(_ path: String) -> [JSONValue] {
    if case .ok(let value) = JSONStore.peek(path) { return value.arrayValue ?? [] }
    return []
  }

  private static func write(_ value: JSONValue, to path: String) throws(Failure) {
    do {
      try JSONStore.write(value, to: path)
    } catch {
      throw .write(NodePath.basename(path))
    }
  }

  /// QuartzControl's key, from its Keychain item. Asks the user (the item belongs to another app).
  /// Electron names the item "<App> Safe Storage" with the account "<App> Key" (read from the
  /// item's attributes, 2026-11-06).
  public static func quartzControlKey() throws(Keychain.Failure) -> Data {
    ChromiumSafeStorage.key(password: try Keychain.read(service: "QuartzControl Safe Storage", account: "QuartzControl Key"))
  }
}
