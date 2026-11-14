import Foundation

// The files of QuartzControl's profile that QuartzHub takes over or reads (docs/formats.md,
// "Im Profil"; details with file:line in docs/formats/profil.md). Each view reads with
// QuartzControl's defaults and leaves everything else in the object alone.

/// One entry of `projects.json` (`shared/ipc-contract.ts` `Project`).
public struct ProjectEntry: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  /// What `addProject` writes: `id, name, path, addedAt`, name = basename of the path.
  public init(id: String, path: String, addedAt: String) {
    object = JSONObject([
      ("id", .string(id)),
      ("name", .string(NodePath.basename(path))),
      ("path", .string(path)),
      ("addedAt", .string(addedAt))
    ])
  }

  public var id: String { string("id") ?? "" }
  public var name: String { string("name") ?? "" }
  public var path: String { string("path") ?? "" }
  public var addedAt: String? { string("addedAt") }
  public var lastOpenedAt: String? {
    get { string("lastOpenedAt") }
    set { set("lastOpenedAt", newValue) }
  }
}

/// `settings.json`. All fields optional; the defaults are applied on read, never written.
public struct SettingsFile: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public enum Language: String, Sendable { case system, de, en }
  public enum Theme: String, Sendable { case system, light, dark }
  public enum NodeRuntime: String, Sendable { case embedded, system }
  public enum ServersOnQuit: String, Sendable { case ask, stop, keep }

  /// Set to nil removes the key, as `undefined` did in QuartzControl's JSON.
  public var defaultProjectDirectory: String? {
    get { string("defaultProjectDirectory") }
    set { set("defaultProjectDirectory", newValue) }
  }
  /// As stored; `system` or missing means "follow the system" (`i18n.ts` `refreshMainLanguage`).
  public var language: Language {
    get { string("language").flatMap(Language.init) ?? .system }
    set { set("language", newValue.rawValue) }
  }
  /// Anything but light or dark is system (`theme.ts`).
  public var theme: Theme {
    get {
      switch string("theme") {
      case "light": .light
      case "dark": .dark
      default: .system
      }
    }
    set { set("theme", newValue.rawValue) }
  }
  public var nodeRuntime: NodeRuntime {
    get { string("nodeRuntime").flatMap(NodeRuntime.init) ?? .embedded }
    set { set("nodeRuntime", newValue.rawValue) }
  }
  public var serversOnQuit: ServersOnQuit {
    get { string("serversOnQuit").flatMap(ServersOnQuit.init) ?? .ask }
    set { set("serversOnQuit", newValue.rawValue) }
  }
  /// Fields from before the first release (2026-08-27) that QuartzControl migrates into
  /// connections.json; QuartzHub does not take them over and says so.
  public var hasLegacyGithubToken: Bool { object["githubToken"] != nil || object["githubTokenEncrypted"] != nil }
}

/// One entry of `connections.json` (`connectionsService.ts` `StoredConnection`).
public struct StoredConnection: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public enum Kind: String, Sendable { case ssh, ftp, github, webhook }
  public enum AuthMethod: String, Sendable { case password, privateKey, agent }

  public var id: String { string("id") ?? "" }
  public var kind: Kind? { string("kind").flatMap(Kind.init) }
  public var name: String { string("name") ?? "" }
  // Defaults as `toPublic` applies them.
  public var host: String { string("host") ?? "" }
  public var port: Int { number("port").map { Int($0) } ?? (kind == .ftp ? 21 : 22) }
  public var username: String { string("username") ?? "" }
  public var authMethod: AuthMethod { string("authMethod").flatMap(AuthMethod.init) ?? .password }
  public var keyPath: String? { string("keyPath") }
  /// FTPS; `!!secure`.
  public var secure: Bool { object["secure"].map(JS.truthy) ?? false }
  /// GitHub login, or for a webhook the origin of its URL, for display.
  public var login: String? { string("login") }
  /// Standard base64 of what Electron's `safeStorage.encryptString` returned.
  public var encryptedSecret: String? {
    get { string("encryptedSecret") }
    set { set("encryptedSecret", newValue) }
  }
  public var hasSecret: Bool { !(encryptedSecret ?? "").isEmpty }
  public var hostKey: JSONObject? { object["hostKey"]?.objectValue }
}

/// One value of `relay-secrets.json`, keyed by project id.
public struct StoredRelaySecrets: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  /// base64 of `safeStorage` over the compact JSON of `RelaySecrets`.
  public var encrypted: String? { string("encrypted") }
  public var recipients: [String] { strings("recipients") ?? [] }
  public var captchaSecret: Bool { isTrue("captchaSecret") }
  public var captchaSecrets: [String] { strings("captchaSecrets") ?? [] }
  public var updatedAt: String? { string("updatedAt") }
  /// Missing in entries before 2026-10-21.
  public var fingerprint: String? { string("fingerprint") }
}

/// One value of `running-servers.json`, keyed by project id: a dev server QuartzControl started
/// (in its profile) or QuartzHub did (in QuartzHub's, `RunningServersStore`).
public struct TrackedServer: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  /// In QuartzControl's key order.
  public init(pid: Int32, port: Int, startedAt: String) {
    object = JSONObject([("pid", .number(Double(pid))), ("port", .number(Double(port))), ("startedAt", .string(startedAt))])
  }

  /// The pid of the `npx` process, not of the listening child.
  public var pid: Int32? { number("pid").flatMap { Int32(exactly: $0) } }
  public var port: Int? { number("port").flatMap { Int(exactly: $0) } }
  public var startedAt: String? { string("startedAt") }
}

/// A file that is one object keyed by id (`relay-secrets.json`, `running-servers.json`).
public struct JSONMap<Item: JSONView>: Equatable, Sendable {
  public var object: JSONObject

  public init(_ value: JSONValue) { object = value.objectValue ?? JSONObject() }

  public var json: JSONValue { .object(object) }
  public var keys: [String] { object.keys }

  public subscript(key: String) -> Item? {
    get { object[key]?.objectValue.map(Item.init(object:)) }
    set { object[key] = newValue?.json }
  }
}

/// The profile files under one directory, QuartzHub's at `~/Library/Application Support/QuartzHub`
/// (`-QHProfileDir` moves it), in the form QuartzControl 1.3 wrote them.
public struct ProfileDirectory: Sendable {
  public let path: String

  public init(_ path: String) { self.path = path }

  public static var quartzHub: ProfileDirectory { ProfileDirectory("\(Posix.path(URL.applicationSupportDirectory))/QuartzHub") } // path boundary

  public func file(_ name: String) -> String { "\(path)/\(name)" }

  public var projects: String { file("projects.json") }
  public var settings: String { file("settings.json") }
  public var connections: String { file("connections.json") }
  public var relaySecrets: String { file("relay-secrets.json") }
  public var runningServers: String { file("running-servers.json") }
}
