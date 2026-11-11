import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct ChromiumSafeStorageTests {
  // Node's crypto, an independent implementation of the same primitives; Electron itself is the
  // vector in decryptsWhatElectronWrote.
  @Test(.enabled(if: JSJSONTests.node != nil, "Runtime/node fehlt"))
  func matchesNodeCrypto() throws {
    // Password and text go in on stdin: Foundation's Process passes arguments through
    // fileSystemRepresentation, which decomposes "ö" (NFD), so an argv would derive another key.
    let script = """
    let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const [pw,text]=JSON.parse(s);
    const c=require('crypto');const k=c.pbkdf2Sync(pw,'saltysalt',1003,16,'sha1');
    const e=c.createCipheriv('aes-128-cbc',k,Buffer.alloc(16,' '));
    process.stdout.write(Buffer.concat([Buffer.from('v10'),e.update(text,'utf-8'),e.final()]).toString('base64'))})
    """
    let fromNode = try JSJSONTests.runNode(script, input: #"["pass wört","geheim €"]"#)
    let key = ChromiumSafeStorage.key(password: "pass wört")
    #expect(try ChromiumSafeStorage.decrypt(base64: fromNode, key: key) == "geheim €")
    #expect(ChromiumSafeStorage.encrypt("geheim €", key: key) == fromNode)
  }

  /// Measured 2026-11-06: Electron 43.4.1 (QuartzControl's, from its node_modules) encrypted this
  /// with `safeStorage.encryptString` under app name "QHProbe", against a throwaway Keychain item
  /// "QHProbe Safe Storage" / "QHProbe Key" holding the password below; the item is deleted.
  @Test func decryptsWhatElectronWrote() throws {
    let key = ChromiumSafeStorage.key(password: "known-probe-password-1")
    #expect(try ChromiumSafeStorage.decrypt(base64: "djEwtkXxLUXbVGvBKJFylvZZembWICNGVD/x/0BLDSYD60E=", key: key) == "geheim € probe")
  }

  @Test func failuresAreTold() {
    let key = ChromiumSafeStorage.key(password: "a")
    let other = ChromiumSafeStorage.key(password: "b")
    let sealed = ChromiumSafeStorage.encrypt("x", key: key)
    #expect(throws: ChromiumSafeStorage.Failure.undecryptable) { try ChromiumSafeStorage.decrypt(base64: sealed, key: other) }
    #expect(throws: ChromiumSafeStorage.Failure.notBase64) { try ChromiumSafeStorage.decrypt(base64: "%%", key: key) }
    // Linux writes v11; such a connections.json cannot be read on a Mac.
    let v11 = Data("v11".utf8) + Data(base64Encoded: sealed)!.dropFirst(3)
    #expect(throws: ChromiumSafeStorage.Failure.unknownPrefix) { try ChromiumSafeStorage.decrypt(base64: v11.base64EncodedString(), key: key) }
  }
}

@Suite struct ProfileMigrationTests {
  let root = TestFolder.make("qh-migration")
  var source: ProfileDirectory { ProfileDirectory("\(root)/QuartzControl") }
  var target: ProfileDirectory { ProfileDirectory("\(root)/QuartzHub") }
  let key = ChromiumSafeStorage.key(password: "test-password")

  /// A QuartzControl profile in its writers' key order.
  func makeSource(extra: (ProfileDirectory) throws -> Void = { _ in }) throws {
    try Posix.mkdirs(source.path)
    let project = "\(root)/site"
    try Posix.mkdirs(project)
    try JSONStore.write(try JSJSON.parse("""
      [{"id":"p1","name":"site","path":"\(project)","addedAt":"2026-10-01T00:00:00.000Z","lastOpenedAt":"2026-11-01T00:00:00.000Z"},
       {"id":"p2","name":"gone","path":"/nowhere/gone","addedAt":"2026-10-02T00:00:00.000Z"}]
      """), to: source.projects)
    try JSONStore.write(try JSJSON.parse(#"{"language":"de","theme":"dark","futureKey":[1],"githubToken":"old"}"#), to: source.settings)
    let password = ChromiumSafeStorage.encrypt("sftp-pass", key: key)
    try JSONStore.write(try JSJSON.parse("""
      [{"id":"c1","kind":"ssh","name":"Server","encryptedSecret":"\(password)","host":"h","port":22,"username":"u","authMethod":"password"},
       {"id":"c2","kind":"ssh","name":"Agent","host":"h","port":22,"username":"u","authMethod":"agent"},
       {"id":"c3","kind":"github","name":"GitHub","encryptedSecret":"\(ChromiumSafeStorage.encrypt("tok", key: ChromiumSafeStorage.key(password: "other")))"}]
      """), to: source.connections)
    let relay = ChromiumSafeStorage.encrypt(#"{"secret":"s","recipients":{"Ich":"a@example.org"}}"#, key: key)
    try JSONStore.write(try JSJSON.parse("""
      {"p1":{"encrypted":"\(relay)","recipients":["Ich"],"captchaSecret":false,"captchaSecrets":[],"updatedAt":"2026-10-21T00:00:00.000Z","fingerprint":"f"}}
      """), to: source.relaySecrets)
    try extra(source)
  }

  func snapshot(_ dir: String) throws -> [String: Data] {
    var files: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: dir) {
      files[name] = try Posix.read("\(dir)/\(name)")
    }
    return files
  }

  @Test func planReadsWithoutTouchingTheSource() throws {
    try makeSource { profile in
      try Posix.write(profile.file("running-servers.json"), Data("{broken".utf8))
      try Posix.write(profile.file("legacy-publish-targets.json"), Data("[]".utf8))
    }
    let before = try snapshot(source.path)
    let plan = ProfileMigration.plan(source: source)
    #expect(try snapshot(source.path) == before)  // nothing moved aside, nothing written
    #expect(plan.projects.map(\.id) == ["p1", "p2"])
    #expect(plan.missingProjectPaths == ["/nowhere/gone"])
    #expect(plan.connections.count == 3 && plan.secretCount == 3)
    #expect(plan.legacy.sorted() == ["legacy-publish-targets.json", "settings.json: githubToken"])
    #expect(plan.unreadable.isEmpty)  // running-servers.json is not part of the takeover
  }

  /// Review 2026-11-11 (2), nebenbei 8: a password QuartzControl stored with the line break a
  /// paste left at its end is taken over as Connections.save keeps it; a key keeps its lines.
  @Test func aTakenOverPasswordLosesThePastedLineBreak() throws {
    try makeSource()
    let key = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n"
    try JSONStore.write(try JSJSON.parse("""
      [{"id":"f1","kind":"ftp","name":"FTP","encryptedSecret":"\(ChromiumSafeStorage.encrypt("qc-pw\r\n", key: self.key))","host":"h","port":21,"username":"u"},
       {"id":"k1","kind":"ssh","name":"Key","encryptedSecret":"\(ChromiumSafeStorage.encrypt(key, key: self.key))","host":"h","port":22,"username":"u","authMethod":"privateKey"}]
      """), to: source.connections)
    var stored: [String: String] = [:]
    _ = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: self.key) { account, _, secret in
      stored[account] = secret
    }
    #expect(stored["connection:f1"] == "qc-pw")
    #expect(stored["connection:k1"] == key)
  }

  /// The same for secrets fetched later (Keychain question declined at the first start).
  @Test func aPasswordFetchedLaterLosesThePastedLineBreak() throws {
    try makeSource()
    try JSONStore.write(try JSJSON.parse("""
      [{"id":"f1","kind":"ftp","name":"FTP","encryptedSecret":"\(ChromiumSafeStorage.encrypt("qc-pw\n", key: self.key))","host":"h","port":21,"username":"u"}]
      """), to: source.connections)
    _ = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: nil) { _, _, _ in }
    let pending = ProfileMigration.pendingSecrets(source: source, target: target)
    #expect(pending.connections.keys.sorted() == ["f1"])
    var stored: [String: String] = [:]
    _ = try ProfileMigration.takeOverSecrets(pending, target: target, secretKey: self.key) { account, _, secret in stored[account] = secret }
    #expect(stored["connection:f1"] == "qc-pw")
  }

  @Test func runMovesSecretsAndKeepsEverythingElse() throws {
    try makeSource()
    let before = try snapshot(source.path)
    var stored: [String: String] = [:]
    let report = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: key) { account, _, secret in
      stored[account] = secret
    }
    #expect(try snapshot(source.path) == before)
    #expect(report.projects == 2 && report.connections == 3 && report.settings)
    #expect(report.secretsMoved == 2 && report.secretsLost == ["c3"])  // c3 was sealed with another key
    #expect(stored == ["connection:c1": "sftp-pass", "relay:p1": #"{"secret":"s","recipients":{"Ich":"a@example.org"}}"#])

    // Projects byte for byte as QuartzControl wrote them.
    #expect(try Posix.read(target.projects) == before["projects.json"])
    let settings = String(decoding: try Posix.read(target.settings), as: UTF8.self)
    #expect(settings == "{\n  \"language\": \"de\",\n  \"theme\": \"dark\",\n  \"futureKey\": [\n    1\n  ]\n}")
    let connections = JSONList<StoredConnection>(try JSJSON.parse(Posix.read(target.connections))).items
    #expect(connections.allSatisfy { $0.encryptedSecret == nil })
    #expect(connections.map { $0.object["secretInKeychain"] } == [.bool(true), nil, nil])
    #expect(connections[0].object.keys == ["id", "kind", "name", "host", "port", "username", "authMethod", "secretInKeychain"])
    let relay = try JSJSON.parse(Posix.read(target.relaySecrets))
    #expect(relay["p1"]?["encrypted"] == nil && relay["p1"]?["secretInKeychain"] == .bool(true))
    #expect(relay["p1"]?["fingerprint"] == .string("f"))
  }

  @Test func withoutKeyNoSecretIsTakenButTheRestIs() throws {
    try makeSource()
    let report = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: nil) { _, _, _ in
      Issue.record("no secret may be stored without a key")
    }
    #expect(report.secretsMoved == 0 && report.secretsLost.sorted() == ["c1", "c3", "p1"])
    #expect(report.projects == 2)
  }

  @Test func runsOnlyOnce() throws {
    try makeSource()
    let plan = ProfileMigration.plan(source: source)
    _ = try ProfileMigration.run(plan, target: target, secretKey: nil) { _, _, _ in }
    #expect(throws: ProfileMigration.Failure.alreadyTakenOver) {
      try ProfileMigration.run(plan, target: target, secretKey: nil) { _, _, _ in }
    }
    #expect(!ProfileMigration.shouldOffer(source: source, target: target))
  }

  @Test func unreadableSourceFilesAreNamedNotMoved() throws {
    try makeSource { profile in try Posix.write(profile.connections, Data("[1,".utf8)) }
    let plan = ProfileMigration.plan(source: source)
    #expect(plan.unreadable == ["connections.json"] && plan.connections.isEmpty)
    #expect(Posix.exists(source.connections))
  }

  /// Relay secrets that are no object are named like any unreadable file, and the leftovers after
  /// them are still listed (review 2026-11-11, nebenbei 3).
  @Test func relaySecretsThatAreNoObjectStillListTheLeftovers() throws {
    try makeSource { profile in
      try Posix.write(profile.relaySecrets, Data("[]".utf8))
      try Posix.write(profile.file("legacy-publish-targets.json"), Data("[]".utf8))
    }
    let plan = ProfileMigration.plan(source: source)
    #expect(plan.unreadable == ["relay-secrets.json"] && plan.relaySecrets.isEmpty)
    #expect(plan.legacy.sorted() == ["legacy-publish-targets.json", "settings.json: githubToken"])
  }

  // MARK: Review 2026-11-11, N3

  /// A broken project list marked the takeover done with "[]"; repaired, it never came over.
  @Test func anUnreadableFileLeavesTheTakeoverOpen() throws {
    let good = { () throws in try makeSource() }
    try good()
    let list = try Posix.read(source.projects)
    try Posix.write(source.projects, Data("[{".utf8))
    let first = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: key) { _, _, _ in }
    #expect(first.offeredAgain && first.projects == 0 && first.connections == 3)
    #expect(!Posix.exists(target.projects))

    // Meanwhile a connection of QuartzHub's own, and c1 edited: both stay as they are.
    var connections = ProfileMigration.existingItems(target.connections)
    connections[0] = .object(JSONObject([("id", .string("c1")), ("kind", .string("ssh")), ("name", .string("Neu benannt"))]))
    connections.append(.object(JSONObject([("id", .string("eigen")), ("kind", .string("webhook")), ("name", .string("Eigen"))])))
    try JSONStore.write(.array(connections), to: target.connections)

    // Repaired: offered again, and the second run brings the projects without touching the rest.
    try Posix.write(source.projects, list)
    #expect(ProfileMigration.shouldOffer(source: source, target: target))
    var stored: [String: String] = [:]
    let second = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: key) { account, _, secret in
      stored[account] = secret
    }
    #expect(!second.offeredAgain && second.projects == 2 && second.connections == 0)
    #expect(stored.isEmpty, "nothing taken twice: \(stored)")
    let names = ProfileMigration.existingItems(target.connections).map { $0["name"]?.stringValue ?? "" }
    #expect(names == ["Neu benannt", "Agent", "GitHub", "Eigen"])
    #expect(!ProfileMigration.shouldOffer(source: source, target: target))
  }

  /// "Nicht erlauben" in the Keychain question took everything but the secrets, for good. They can
  /// be fetched later, and only those.
  @Test func secretsLeftBehindCanBeFetchedLater() throws {
    try makeSource()
    _ = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: nil) { _, _, _ in }
    let pending = ProfileMigration.pendingSecrets(source: source, target: target)
    #expect(pending.connections.keys.sorted() == ["c1", "c3"] && pending.relays.keys.sorted() == ["p1"])

    var stored: [String: String] = [:]
    let report = try ProfileMigration.takeOverSecrets(pending, target: target, secretKey: key) { account, _, secret in stored[account] = secret }
    #expect(report.secretsMoved == 2 && report.secretsLost == ["c3"])
    #expect(stored == ["connection:c1": "sftp-pass", "relay:p1": #"{"secret":"s","recipients":{"Ich":"a@example.org"}}"#])
    let marks = ProfileMigration.existingItems(target.connections).map { $0["secretInKeychain"] }
    #expect(marks == [.bool(true), nil, nil])
    #expect(try JSJSON.parse(Posix.read(target.relaySecrets))["p1"]?["secretInKeychain"] == .bool(true))
    // What is there now is not offered again; c3's key never fits.
    #expect(ProfileMigration.pendingSecrets(source: source, target: target).connections.keys.sorted() == ["c3"])
    #expect(ProfileMigration.pendingSecrets(source: source, target: target).relays.isEmpty)
  }

  @Test func foreignServersNeedALivePidAndAServeCommand() throws {
    try makeSource { profile in
      try JSONStore.write(try JSJSON.parse("""
        {"p1":{"pid":\(getpid()),"port":8080,"startedAt":"x"},"p2":{"pid":999999,"port":8081,"startedAt":"x"}}
        """), to: profile.runningServers)
    }
    let serve = Coexistence.foreignServers(profile: source) { _ in "npm exec quartz build --serve --port 8080" }
    #expect(serve == [.init(projectId: "p1", projectPath: "\(root)/site", pid: getpid(), port: 8080)])
    // The same live pid, but it is not a Quartz server any more: not counted.
    #expect(Coexistence.foreignServers(profile: source) { _ in "/usr/bin/something" }.isEmpty)
  }
}
