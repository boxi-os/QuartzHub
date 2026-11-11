import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own connectionsService.ts (`scripts/connections-golden.mjs`): 59 calls
/// with their answers, both files after each (QuartzHub's form, by bytes) and the secrets by
/// Keychain account, in a store in memory; and the input rules against its zod schema.
@Suite struct ConnectionsTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/connections/steps.json")))

  final class Counters: Sendable {
    let ids = Mutex(0)
    let bytes = Mutex(0)
    let now = Mutex(Date())
  }

  static func input(_ value: JSONValue) -> SaveConnectionInput {
    SaveConnectionInput(id: value["id"]?.stringValue, kind: .init(rawValue: value["kind"]!.stringValue!)!, name: value["name"]!.stringValue!,
                        host: value["host"]?.stringValue, port: value["port"]?.numberValue.map { Int($0) },
                        username: value["username"]?.stringValue, authMethod: value["authMethod"]?.stringValue.flatMap(StoredConnection.AuthMethod.init),
                        keyPath: value["keyPath"]?.stringValue, secure: value["secure"]?.boolValue, login: value["login"]?.stringValue,
                        secret: value["secret"]?.stringValue)
  }

  static func change(_ value: JSONValue) -> RelaySecretsChange {
    var change = RelaySecretsChange()
    change.recipients = value["recipients"]?.objectValue
    change.captchaSecrets = value["captchaSecrets"]?.objectValue
    switch value["captchaSecret"] {
    case .null?: change.captchaSecret = .remove
    case .string(let text)?: change.captchaSecret = .set(text)
    default: break
    }
    if let move = value["moveCaptchaSecret"] { change.moveCaptchaSecret = (move["from"]!.stringValue!, move["to"]!.stringValue!) }
    change.renewSecret = value["renewSecret"] == .bool(true)
    return change
  }

  static func strings(_ items: [String]) -> JSONValue { .array(items.map(JSONValue.string)) }

  @Test func replaysQuartzControlsSteps() throws {
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 59)
    let root = TestFolder.make("qh-connections")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let profile = ProfileDirectory("\(root)/Gärten-Ü profile")
    let counters = Counters()
    var secrets = MemorySecrets()
    var store = Connections(profile: profile, secrets: secrets)
    // QuartzControl wrote "[]" when a read found no file; QuartzHub writes nothing then.
    var onlyQuartzControlWrote = false

    for step in steps {
      let name = step["name"]!.stringValue!
      let before = step["before"]!
      if before["reset"] == .bool(true) {
        try? FileManager.default.removeItem(atPath: profile.path)
        counters.ids.withLock { $0 = 0 }
        counters.bytes.withLock { $0 = 0 }
        secrets = MemorySecrets()
        store = Connections(profile: profile, secrets: secrets,
                            makeID: { "00000000-0000-4000-8000-" + String(format: "%012d", counters.ids.withLock { $0 += 1; return $0 }) },
                            randomBytes: { n in [UInt8](repeating: UInt8(counters.bytes.withLock { $0 += 1; return $0 }), count: n) },
                            now: { counters.now.withLock { $0 } })
        onlyQuartzControlWrote = false
      }
      counters.now.withLock { $0 = ISO8601DateFormatter().date(from: before["now"]!.stringValue!.replacingOccurrences(of: ".000Z", with: "Z", options: .literal))! }
      if let seed = before["seed"]?.stringValue {
        try Posix.mkdirs(profile.path)
        try Posix.write(profile.connections, Data(seed.utf8))
      }

      let args = step["args"]!.arrayValue!
      let actual: JSONValue
      switch step["op"]!.stringValue! {
      case "read:list": actual = .array(store.list().map(\.json))
      case "read:get": actual = store.get(args[0].stringValue!)?.json ?? .null
      case "read:secret": actual = try store.secret(args[0].stringValue!).map(JSONValue.string) ?? .null
      case "read:githubToken": actual = try store.githubToken().map(JSONValue.string) ?? .null
      case "save": actual = try store.save(Self.input(args[0])).json
      case "save:hostKey":
        try store.rememberHostKey(args[0].stringValue!, PinnedHostKey(args[1])!)
        actual = .null
      case "save:forget":
        try store.forgetHostKey(args[0].stringValue!)
        actual = .null
      case "save:delete":
        try store.delete(args[0].stringValue!)
        actual = .null
      case "relay":
        try store.saveRelaySecrets(args[0].stringValue!, Self.change(args[1]))
        actual = .null
      case "relay:delete":
        try store.deleteRelaySecrets(args[0].stringValue!)
        actual = .null
      case "read:relayInfo":
        let info = store.relaySecretInfo(args[0].stringValue!)
        actual = .object(JSONObject([("stored", .bool(info.stored)), ("recipients", Self.strings(info.recipients)),
                                     ("captchaSecret", .bool(info.captchaSecret)), ("captchaSecrets", Self.strings(info.captchaSecrets)),
                                     ("fingerprint", info.fingerprint.map(JSONValue.string) ?? .null)]))
      case "read:relaySecrets": actual = try store.relaySecrets(args[0].stringValue!)?.json ?? .null
      case "read:relayProjects": actual = Self.strings(store.projectsWithRelaySecrets().sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) })
      default:
        Issue.record("unknown op \(step["op"]!)"); continue
      }
      let expected = step["result"]!["ok"]!
      #expect(JSJSON.compact(actual).utf8.elementsEqual(JSJSON.compact(expected).utf8),
              "\(name): \(JSJSON.compact(actual)) vs \(JSJSON.compact(expected))")

      let file = try? Posix.read(profile.connections)
      if step["writtenOnRead"] == .bool(true) {
        #expect(file == nil, "\(name): QuartzHub wrote on a read")
        onlyQuartzControlWrote = true
      } else if file == nil && onlyQuartzControlWrote {
        #expect(step["connections"] == .string("[]"), "\(name)")
      } else {
        onlyQuartzControlWrote = false
        #expect(file.map { Array($0) } == step["connections"]?.stringValue.map { Array($0.utf8) }, "\(name): connections.json\n\(file.map { String(decoding: $0, as: UTF8.self) } ?? "nil")")
      }
      let relay = try? Posix.read(profile.relaySecrets)
      #expect(relay.map { Array($0) } == step["relaySecrets"]?.stringValue.map { Array($0.utf8) }, "\(name): relay-secrets.json\n\(relay.map { String(decoding: $0, as: UTF8.self) } ?? "nil")")
      let expectedSecrets = step["secrets"]!.objectValue!
      #expect(secrets.all == Dictionary(uniqueKeysWithValues: expectedSecrets.keys.map { ($0, expectedSecrets[$0]!.stringValue!) }),
              "\(name): secrets \(secrets.all)")
    }
  }

  @Test func checksInputsAsTheSchema() {
    let rules = Self.golden["rules"]!.arrayValue!
    #expect(rules.count == 36)
    for rule in rules {
      let input = Self.input(rule["input"]!)
      #expect((input.problem == nil) == (rule["valid"] == .bool(true)), "\(JSJSON.compact(rule["input"]!)): \(input.problem ?? "valid")")
    }
  }

  /// QuartzHub's own rule: an SSH or FTP connection needs a host (QuartzControl failed with a
  /// TypeError on a missing one).
  @Test func aServerConnectionNeedsAHost() {
    #expect(SaveConnectionInput(kind: .ssh, name: "S").problem == "host")
    #expect(SaveConnectionInput(kind: .ftp, name: "F").problem == "host")
    #expect(SaveConnectionInput(kind: .github, name: "G").problem == nil)
  }

  @Test func aStoredSecretThatCannotBeReadIsASentence() throws {
    let root = TestFolder.make("qh-connections-denied")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let secrets = MemorySecrets()
    let store = Connections(profile: ProfileDirectory(root), secrets: secrets)
    let saved = try store.save(SaveConnectionInput(kind: .github, name: "G", secret: "t"))
    #expect(try store.githubToken() == "t")
    secrets.fail(with: .denied)
    #expect(throws: PublishFailure(L10n.t("main.secretStorageUnreadableMac"))) { try store.secret(saved.id) }
    secrets.fail(with: nil)
    try secrets.delete(account: "connection:\(saved.id)")
    #expect(throws: PublishFailure(L10n.t("main.secretMissingInKeychain"))) { try store.githubToken() }
    // And a save that cannot reach the Keychain writes no file that claims a secret.
    secrets.fail(with: .denied)
    #expect(throws: PublishFailure(L10n.t("main.secretStorageUnavailableMac"))) {
      try store.save(SaveConnectionInput(kind: .github, name: "H", secret: "u"))
    }
    #expect(store.list().count == 1)
  }

  /// The relay's secrets named in the file but gone from the Keychain (another Mac, an item
  /// deleted): reading says so where they are entered, and a new address is stored as a fresh set
  /// instead of every save failing (measured 2026-11-11: no address could be entered again).
  @Test func relaySecretsGoneFromTheKeychainCanBeEnteredAgain() throws {
    let root = TestFolder.make("qh-connections-relay-gone")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let secrets = MemorySecrets()
    let store = Connections(profile: ProfileDirectory(root), secrets: secrets)
    try store.saveRelaySecrets("p1", RelaySecretsChange(recipients: JSONObject([("Kontakt", .string("alt@example.org"))])))
    let before = try #require(try store.relaySecrets("p1"))
    try secrets.delete(account: Connections.relayAccount("p1"))
    #expect(throws: PublishFailure(L10n.t("relay.secretsMissing"))) { try store.relaySecrets("p1") }
    try store.saveRelaySecrets("p1", RelaySecretsChange(recipients: JSONObject([("Kontakt", .string("neu@example.org"))])))
    let after = try #require(try store.relaySecrets("p1"))
    #expect(after.recipients["Kontakt"] == .string("neu@example.org"))
    #expect(after.secret != before.secret && !after.secret.isEmpty)
  }

  /// The section's badges come from `relaySecretInfo`: with the Keychain item gone no address
  /// counts as set, with a Keychain that refuses to be read the names stay (2026-11-11: "Adresse
  /// gesetzt" and "gesetzt" in green while the upload said the secrets were missing).
  @Test func relaySecretsGoneFromTheKeychainShowNoNames() throws {
    let root = TestFolder.make("qh-connections-relay-info")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let secrets = MemorySecrets()
    let store = Connections(profile: ProfileDirectory(root), secrets: secrets)
    try store.saveRelaySecrets("p1", RelaySecretsChange(recipients: JSONObject([("Kontakt", .string("a@b.org"))]), captchaSecret: .set("c")))
    var info = store.relaySecretInfo("p1")
    #expect(info.recipients == ["Kontakt"] && info.captchaSecret && !info.missing)
    secrets.fail(with: .denied)
    info = store.relaySecretInfo("p1")
    #expect(info.recipients == ["Kontakt"] && info.captchaSecret && !info.missing)
    secrets.fail(with: nil)
    try secrets.delete(account: Connections.relayAccount("p1"))
    info = store.relaySecretInfo("p1")
    #expect(info.recipients.isEmpty && !info.captchaSecret && info.missing && info.stored)
    try store.saveRelaySecrets("p1", RelaySecretsChange(recipients: JSONObject([("Kontakt", .string("n@b.org"))])))
    info = store.relaySecretInfo("p1")
    #expect(info.recipients == ["Kontakt"] && !info.captchaSecret && !info.missing)
    // Review 2026-11-11 (2), N5: looking at the Forms tab reads no secret (a read meets the item's
    // access list and, after a new build, the system's dialog).
    let before = secrets.reads
    for _ in 0..<5 { _ = store.relaySecretInfo("p1") }
    #expect(secrets.reads == before)
  }

  /// A password or token is one line: a pasted line break at the end goes, any other control
  /// character is refused before it reaches the Keychain; a key pasted as text keeps its lines
  /// (measured 2026-11-11: basic-ftp refused "PASS" with a trailing newline).
  @Test func aOneLineSecretLosesThePastedLineBreak() throws {
    let root = TestFolder.make("qh-connections-oneline")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let store = Connections(profile: ProfileDirectory(root), secrets: MemorySecrets())
    let ftp = try store.save(SaveConnectionInput(kind: .ftp, name: "F", host: "h", port: 21, username: "u", secure: true, secret: "pa ss\r\n"))
    #expect(try store.secret(ftp.id) == "pa ss")
    let ssh = try store.save(SaveConnectionInput(kind: .ssh, name: "S", host: "h", port: 22, username: "u", authMethod: .password, secret: "pw\n"))
    #expect(try store.secret(ssh.id) == "pw")
    let github = try store.save(SaveConnectionInput(kind: .github, name: "G", secret: "ghp_x\n"))
    #expect(try store.secret(github.id) == "ghp_x")
    #expect(throws: PublishFailure(L10n.t("main.connectionSecretControl"))) {
      try store.save(SaveConnectionInput(kind: .ftp, name: "F2", host: "h", port: 21, username: "u", secure: true, secret: "pa\nss"))
    }
    #expect(throws: PublishFailure(L10n.t("main.connectionSecretControl"))) {
      try store.save(SaveConnectionInput(kind: .ssh, name: "S2", host: "h", port: 22, username: "u", authMethod: .password, secret: "pa\0ss"))
    }
    // Review 2026-11-11 (2), N4: a tab, the joiner of an emoji sequence, a soft hyphen go through.
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    for (index, secret) in ["pa\tss", "x\(family)y", "Trenn\u{AD}zeichen"].enumerated() {
      let saved = try store.save(SaveConnectionInput(kind: .ftp, name: "U\(index)", host: "h", port: 21, username: "u", secure: true, secret: secret))
      #expect(try store.secret(saved.id) == secret)
    }
    let key = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n"
    let keyed = try store.save(SaveConnectionInput(kind: .ssh, name: "K", host: "h", port: 22, username: "u", authMethod: .privateKey, secret: key))
    #expect(try store.secret(keyed.id) == key)
  }
}
