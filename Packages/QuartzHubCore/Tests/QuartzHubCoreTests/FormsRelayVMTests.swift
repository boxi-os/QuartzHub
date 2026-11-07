import Foundation
import Testing
@testable import QuartzHubCore

/// The relay on a real host: debian-vm with Apache, mod_php as www-data on :8441 and a PHP-FPM pool
/// as the upload account on :8442 (both with the test CA's certificate from /etc/ssl/qh-8c), the
/// relay written by the real quartz-forms (the development checkout, linked into a project with
/// gui-test's quartz.config.yaml), uploaded over SFTP and over FTPS, probed, made readable,
/// probed again and removed. What QuartzControl measured on the same host (formsService.ts): with
/// config.php 0600, FPM as the account answers and mod_php stops with an empty 500; readable, both
/// answer, and mod_php cannot write the counters. Only with `QH_VM_TESTS=1`, `QH_VM_KEY` and
/// `QH_VM_CERT` (the FTPS run also `QH_FTP_PW`), and the checkout in `QH_FORMS_PLUGIN` (default
/// ~/Development/quartz-forms).
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["QH_VM_TESTS"] == "1" && ToolEnvironmentTests.hasRuntime,
                             "QH_VM_TESTS=1, QH_VM_KEY, QH_VM_CERT"))
struct FormsRelayVMTests {
  static let host = "debian.local"
  static let env = ProcessInfo.processInfo.environment
  static var plugin: String { env["QH_FORMS_PLUGIN"] ?? "\(NSHomeDirectory())/Development/quartz-forms" }
  /// The test CA, as DER.
  static var anchors: [Data] {
    let pem = String(decoding: (try? Posix.read(env["QH_VM_CERT"] ?? "")) ?? Data(), as: UTF8.self)
    let base64 = pem.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
    return Data(base64Encoded: base64).map { [$0] } ?? []
  }

  static func ssh(_ key: String, _ known: String, _ command: String) async -> String {
    await ProcessRunner.run(Command("/usr/bin/ssh", ["-F", "/dev/null", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=accept-new",
                                                     "-o", "UserKnownHostsFile=\(known)", "-i", key, "qchost@\(host)", command],
                                    environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()])).stdout
  }

  @Test func overSFTP() async throws { try await exercise("sftp") }

  /// Needs `QH_FTP_PW` as well.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["QH_FTP_PW"] != nil, "QH_FTP_PW")) func overFTPS() async throws { try await exercise("ftp") }

  func exercise(_ way: String) async throws {
    let key = try #require(Self.env["QH_VM_KEY"])
    let password = Self.env["QH_FTP_PW"] ?? ""
    let ca = String(decoding: try Posix.read(try #require(Self.env["QH_VM_CERT"])), as: UTF8.self)
    try #require(Posix.exists("\(Self.plugin)/dist/cli.js"), "quartz-forms checkout")
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-relay-vm"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let remote = "/srv/qc/www/qh8c-relay-\(way)"
    let known = "\(work)/kh"
    _ = await Self.ssh(key, known, "rm -rf \(remote); mkdir -p \(remote)")

    let project = "\(work)/Gärten-Ü"
    try Posix.mkdirs("\(project)/.quartz/plugins")
    try Posix.write("\(project)/quartz.config.yaml", try Posix.read("\(NSHomeDirectory())/Documents/QuartzProjekte/gui-test/quartz.config.yaml"))
    try Posix.symlink(Self.plugin, "\(project)/.quartz/plugins/quartz-forms")

    let environment = ToolEnvironmentTests.environment(.embedded)
    let profile = "\(work)/profile"
    let connections = Connections(profile: ProfileDirectory(profile), secrets: MemorySecrets())
    let connection = try connections.save(way == "sftp"
      ? SaveConnectionInput(kind: .ssh, name: "Hoster", host: Self.host, port: 22, username: "qchost", authMethod: .privateKey, keyPath: key)
      : SaveConnectionInput(kind: .ftp, name: "Hoster FTP", host: Self.host, port: 21, username: "qchost", secure: true, secret: password))
    let targets = PublishTargets(project: project)
    let target = try targets.save(SavePublishTargetInput(name: "Relay", connectionId: connection.id,
                                                          destination: JSONObject([("type", .string(way)), ("remotePath", .string(remote))] + (way == "sftp" ? [("transfer", .string("sftp"))] : [])
                                                            + [("deleteRemoved", .bool(false))])))
    let adapters: [String: any DeployAdapter] = [
      "sftp": SFTPAdapter(connections: connections, environment: environment, confirm: { _, _ in true }, configFile: "/dev/null"),
      "ftp": FTPAdapter(connections: connections, runtime: HelperRuntime.runtime, ca: ca)
    ]
    let deploy = Deploy(project: project, connections: connections, adapters: adapters)
    let cli = FormsCLI(project: project, source: PluginSource(.string("/Users/boxi/Development/quartz-forms"))!, environment: environment)
    var relayProbe = RelayProbe()
    relayProbe.anchors = Self.anchors
    let relay = FormsRelay(projectId: "vm-\(way)", cli: cli, connections: connections, deploy: deploy, probe: relayProbe)
    try connections.saveRelaySecrets("vm-\(way)", RelaySecretsChange(recipients: JSONObject([("TestKontakt", .string("qchost@debian.local"))])))
    var settings = RelayFile.defaultSettings
    settings["targetId"] = .string(target.id)
    settings["from"] = .string("qhtest@debian.local")
    try relay.saveSettings(settings)

    let fpm = "https://\(Self.host):8442\(remote.replacingOccurrences(of: "/srv/qc/www", with: ""))/forms/send.php"
    let modPHP = fpm.replacingOccurrences(of: ":8442", with: ":8441")
    let first = await relay.upload(url: fpm, form: "kontakt")
    #expect(first.success, "\(first.output)")
    #expect(first.check == .ok(url: fpm, counters: true), "\(String(describing: first.check))")
    let generation = relay.readFile().lastUpload?["generation"]?.stringValue
    let listing = "find \(remote) -printf '%y %m %P\\n' | sort"
    let modes = await Self.ssh(key, known, listing)
    // The modes the relay was given here, whatever the server's umask (QuartzControl: 0700 and 0666 before).
    for line in ["d 755 forms", "f 600 forms/config.php", "f 644 forms/config.generated.php", "f 644 forms/send.php", "d 755 forms/counters",
                 "f 644 forms/counters/.htaccess", "f 644 forms/counters/qf-probe.count"] {
      #expect(JSText.includes(modes, "\(line)\n"), "\(way): \(line)\n\(modes)")
    }
    // Under mod_php (www-data) a config.php of the account with 0600 stops PHP before send.php answers.
    #expect(await relayProbe.check(url: modPHP, origin: "https://quartzmac.borkel.net", form: "kontakt", generation: generation) == .phpError(url: modPHP))
    // Without the test CA, the certificate is the answer.
    let untrusted = await RelayProbe().check(url: fpm, origin: nil, form: "kontakt", generation: nil)
    #expect(untrusted == .unreachable(url: fpm, reason: L10n.t("main.relayCheckCertificate", ["code": "net::ERR_CERT_AUTHORITY_INVALID"])), "\(untrusted)")
    // With the test CA as an anchor, a certificate it did not sign is still refused (nginx on :8443 keeps the snakeoil one).
    let nginx = fpm.replacingOccurrences(of: ":8442", with: ":8443")
    let foreign = await relayProbe.check(url: nginx, origin: nil, form: "kontakt", generation: nil)
    #expect(foreign == .unreachable(url: nginx, reason: L10n.t("main.relayCheckCertificate", ["code": "net::ERR_CERT_AUTHORITY_INVALID"])), "\(foreign)")

    settings["configReadable"] = .bool(true)
    try relay.saveSettings(settings)
    let readable = await relay.upload(url: modPHP, form: "kontakt")
    #expect(readable.success, "\(readable.output)")
    // Readable, mod_php answers, and cannot write the account's counters folder.
    #expect(readable.check == .ok(url: modPHP, counters: false), "\(String(describing: readable.check))")
    #expect(JSText.includes(await Self.ssh(key, known, listing), "f 644 forms/config.php"))
    let state = await relay.state()
    #expect(state.moved == false && !state.operatorChanged && !state.configModeChanged)

    let removed = await relay.remove()
    #expect(removed.success, "\(removed.output)")
    let left = await Self.ssh(key, known, listing)
    #expect(!JSText.includes(left, "send.php") && !JSText.includes(left, "config.php") && JSText.includes(left, "forms/counters/.htaccess"), "\(left)")
    #expect(relay.readFile().lastUpload == nil)
    _ = await Self.ssh(key, known, "rm -rf \(remote)")
  }
}
