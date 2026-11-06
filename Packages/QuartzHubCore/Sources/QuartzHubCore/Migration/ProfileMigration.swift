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
    if let value = load(source.relaySecrets) {
      guard let object = value.objectValue else {
        plan.unreadable.append(NodePath.basename(source.relaySecrets))
        return plan
      }
      plan.relaySecrets = object.keys.compactMap { key in
        object[key]?.objectValue.map { (key, StoredRelaySecrets(object: $0)) }
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
    if !plan.connections.isEmpty {
      let moved: [StoredConnection] = plan.connections.map { connection in
        var copy = connection
        let stored = secret(connection.encryptedSecret, account: "connection:\(connection.id)",
                            label: "QuartzHub – \(connection.name)", id: connection.id)
        copy.encryptedSecret = nil
        if stored { copy.object["secretInKeychain"] = .bool(true) }
        return copy
      }
      try write(JSONList(items: moved).json, to: target.connections)
      report.connections = moved.count
    }

    if !plan.relaySecrets.isEmpty {
      var object = JSONObject()
      for (projectId, entry) in plan.relaySecrets {
        var copy = entry
        let stored = secret(entry.encrypted, account: "relay:\(projectId)", label: "QuartzHub – Relay", id: projectId)
        copy.object["encrypted"] = nil
        if stored { copy.object["secretInKeychain"] = .bool(true) }
        object[projectId] = copy.json
      }
      try write(.object(object), to: target.relaySecrets)
    }

    if var settings = plan.settings {
      settings.object["githubToken"] = nil
      settings.object["githubTokenEncrypted"] = nil
      try write(settings.json, to: target.settings)
      report.settings = true
    }

    // Last: the marker that the takeover is done.
    try write(JSONList(items: plan.projects).json, to: target.projects)
    report.projects = plan.projects.count
    return report
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
