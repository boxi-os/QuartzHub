import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct ChromiumSafeStorageTests {
  // Chromium's own test vector would be better; until the measurement against Electron
  // (docs/decisions/phase-2-formate.md) this checks the formula against Node's crypto, an
  // independent implementation of the same primitives.
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
  let root: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qh-migration-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()
  var source: ProfileDirectory { ProfileDirectory(root.appendingPathComponent("QuartzControl")) }
  var target: ProfileDirectory { ProfileDirectory(root.appendingPathComponent("QuartzHub")) }
  let key = ChromiumSafeStorage.key(password: "test-password")

  /// A QuartzControl profile in its writers' key order.
  func makeSource(extra: (ProfileDirectory) throws -> Void = { _ in }) throws {
    try FileManager.default.createDirectory(at: source.url, withIntermediateDirectories: true)
    let project = root.appendingPathComponent("site").path
    try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
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

  func snapshot(_ dir: URL) throws -> [String: Data] {
    var files: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
      files[name] = try Data(contentsOf: dir.appendingPathComponent(name))
    }
    return files
  }

  @Test func planReadsWithoutTouchingTheSource() throws {
    try makeSource { profile in
      try Data("{broken".utf8).write(to: profile.file("running-servers.json"))
      try Data("[]".utf8).write(to: profile.file("legacy-publish-targets.json"))
    }
    let before = try snapshot(source.url)
    let plan = ProfileMigration.plan(source: source)
    #expect(try snapshot(source.url) == before)  // nothing moved aside, nothing written
    #expect(plan.projects.map(\.id) == ["p1", "p2"])
    #expect(plan.missingProjectPaths == ["/nowhere/gone"])
    #expect(plan.connections.count == 3 && plan.secretCount == 3)
    #expect(plan.legacy.sorted() == ["legacy-publish-targets.json", "settings.json: githubToken"])
    #expect(plan.unreadable.isEmpty)  // running-servers.json is not part of the takeover
  }

  @Test func runMovesSecretsAndKeepsEverythingElse() throws {
    try makeSource()
    let before = try snapshot(source.url)
    var stored: [String: String] = [:]
    let report = try ProfileMigration.run(ProfileMigration.plan(source: source), target: target, secretKey: key) { account, _, secret in
      stored[account] = secret
    }
    #expect(try snapshot(source.url) == before)
    #expect(report.projects == 2 && report.connections == 3 && report.settings)
    #expect(report.secretsMoved == 2 && report.secretsLost == ["c3"])  // c3 was sealed with another key
    #expect(stored == ["connection:c1": "sftp-pass", "relay:p1": #"{"secret":"s","recipients":{"Ich":"a@example.org"}}"#])

    // Projects byte for byte as QuartzControl wrote them.
    #expect(try Data(contentsOf: target.projects) == before["projects.json"])
    let settings = try String(contentsOf: target.settings, encoding: .utf8)
    #expect(settings == "{\n  \"language\": \"de\",\n  \"theme\": \"dark\",\n  \"futureKey\": [\n    1\n  ]\n}")
    let connections = JSONList<StoredConnection>(try JSJSON.parse(Data(contentsOf: target.connections))).items
    #expect(connections.allSatisfy { $0.encryptedSecret == nil })
    #expect(connections.map { $0.object["secretInKeychain"] } == [.bool(true), nil, nil])
    #expect(connections[0].object.keys == ["id", "kind", "name", "host", "port", "username", "authMethod", "secretInKeychain"])
    let relay = try JSJSON.parse(Data(contentsOf: target.relaySecrets))
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
    try makeSource { profile in try Data("[1,".utf8).write(to: profile.connections) }
    let plan = ProfileMigration.plan(source: source)
    #expect(plan.unreadable == ["connections.json"] && plan.connections.isEmpty)
    #expect(FileManager.default.fileExists(atPath: source.connections.path))
  }

  @Test func foreignServersNeedALivePidAndAServeCommand() throws {
    try makeSource { profile in
      try JSONStore.write(try JSJSON.parse("""
        {"p1":{"pid":\(getpid()),"port":8080,"startedAt":"x"},"p2":{"pid":999999,"port":8081,"startedAt":"x"}}
        """), to: profile.runningServers)
    }
    let serve = Coexistence.foreignServers(profile: source) { _ in "npm exec quartz build --serve --port 8080" }
    #expect(serve == [.init(projectId: "p1", projectPath: root.appendingPathComponent("site").path, pid: getpid(), port: 8080)])
    // The same live pid, but it is not a Quartz server any more: not counted.
    #expect(Coexistence.foreignServers(profile: source) { _ in "/usr/bin/something" }.isEmpty)
  }
}
