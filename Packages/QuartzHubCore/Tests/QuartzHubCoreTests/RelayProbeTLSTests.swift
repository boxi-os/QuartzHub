import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// The certificate the relay check refused, named from the probe's own trust evaluation. At
/// qh-test.borkel.net (2026-11-11) the app said "no encrypted connection" for a wrong name: App
/// Transport Security turns every certificate failure into -1200 with stream code -9802, where a
/// process without an app bundle (this test) still sees -1202 and the stream code. Against a local
/// TLS server (Node's https) with certificates from openssl.
@Suite(.serialized, .enabled(if: ToolEnvironmentTests.hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
struct RelayProbeTLSTests {
  static let server = """
    const https = require('https'), fs = require('fs');
    const s = https.createServer({ key: fs.readFileSync(process.argv[2]), cert: fs.readFileSync(process.argv[3]) }, (q, r) => {
      r.writeHead(200, { 'content-type': 'application/json' }); r.end('{"ok":true}');
    });
    s.listen(0, '127.0.0.1', () => console.log(JSON.stringify({ port: s.address().port })));
    """

  /// A certificate for `san`, valid for two days: `<name>.key`, `<name>.pem`, and its DER.
  static func certificate(_ dir: String, _ name: String, san: String) async throws -> Data {
    let env = ["PATH": "/usr/bin:/bin"]
    let made = await ProcessRunner.run(Command("/usr/bin/openssl", [
      "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "\(dir)/\(name).key", "-out", "\(dir)/\(name).pem",
      "-days", "2", "-subj", "/CN=qh-probe", "-addext", "subjectAltName=\(san)", "-addext", "extendedKeyUsage=serverAuth"
    ], environment: env))
    try #require(made.termination == .exited(0), "\(made.output)")
    let der = await ProcessRunner.run(Command("/usr/bin/openssl", ["x509", "-in", "\(dir)/\(name).pem", "-outform", "der", "-out", "\(dir)/\(name).der"],
                                              environment: env))
    try #require(der.termination == .exited(0), "\(der.output)")
    return try Posix.read("\(dir)/\(name).der")
  }

  static func start(_ dir: String, _ name: String) throws -> (LaunchedProcess, Int) {
    try Posix.write("\(dir)/server.cjs", Data(server.utf8))
    let node = "\(ToolEnvironmentTests.runtime.nodeBin)/node"
    guard case .success(let launched) = ProcessRunner.launchPiped(Command(node, ["\(dir)/server.cjs", "\(dir)/\(name).key", "\(dir)/\(name).pem"],
                                                                         environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"])) else {
      throw PublishFailure("TLS server did not start")
    }
    close(launched.stdin)
    var line = Data()
    var byte: UInt8 = 0
    while read(launched.stdout, &byte, 1) == 1, byte != 0x0A { line.append(byte) }
    return (launched.process, Int(try JSJSON.parse(line)["port"]?.numberValue ?? 0))
  }

  /// One request through the probe's delegate, as `RelayProbe.get` makes it; what it noted.
  static func noted(_ url: String, anchors: [Data]) async -> (String?, String) {
    let fetch = RelayProbe.Fetch(start: url, origin: nil, seconds: "5", reportsStatus: true, anchors: anchors)
    let session = URLSession(configuration: .ephemeral, delegate: fetch, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let result = await withCheckedContinuation { continuation in
      fetch.begin(continuation)
      let task = session.dataTask(with: URL(string: url)!)
      fetch.attach(task, timer: Task {})
      task.resume()
    }
    let reason = if case .failed(let reason) = result { reason } else { "answered" }
    return (fetch.state.withLock { $0.certificate }, reason)
  }

  @Test func aWrongNameIsNamedFromTheTrustEvaluation() async throws {
    let dir = TestFolder.make("qh-relay-tls")
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let der = try await Self.certificate(dir, "other", san: "DNS:qh-probe.invalid")
    let (server, port) = try Self.start(dir, "other")
    defer { _ = server.signal(SIGKILL) }
    let url = "https://127.0.0.1:\(port)/send.php"
    let (noted, reason) = await Self.noted(url, anchors: [der])
    #expect(noted == "net::ERR_CERT_COMMON_NAME_INVALID")
    #expect(reason == L10n.t("main.relayCheckCertificate", ["code": "net::ERR_CERT_COMMON_NAME_INVALID"]))
    var probe = RelayProbe()
    probe.anchors = [der]
    #expect(await probe.check(url: url, origin: nil, form: "kontakt", generation: nil)
      == .unreachable(url: url, reason: L10n.t("main.relayCheckCertificate", ["code": "net::ERR_CERT_COMMON_NAME_INVALID"])))
  }

  @Test func anUnknownIssuerIsNamedFromTheTrustEvaluation() async throws {
    let dir = TestFolder.make("qh-relay-tls")
    defer { try? FileManager.default.removeItem(atPath: dir) }
    _ = try await Self.certificate(dir, "own", san: "IP:127.0.0.1")
    let (server, port) = try Self.start(dir, "own")
    defer { _ = server.signal(SIGKILL) }
    let (noted, reason) = await Self.noted("https://127.0.0.1:\(port)/send.php", anchors: [])
    #expect(noted == "net::ERR_CERT_AUTHORITY_INVALID")
    #expect(reason == L10n.t("main.relayCheckCertificate", ["code": "net::ERR_CERT_AUTHORITY_INVALID"]))
  }

  @Test func atsShapedFailuresAsTheAppSeesThem() {
    let ats = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed, userInfo: ["_kCFStreamErrorCodeKey": -9802])
    #expect(RelayProbe.unreachableReason(ats, certificate: "net::ERR_CERT_DATE_INVALID")
      == L10n.t("main.relayCheckCertificate", ["code": "net::ERR_CERT_DATE_INVALID"]))
    // No certificate refused: a TLS failure of its own (protocol, cipher), as before.
    #expect(RelayProbe.unreachableReason(ats) == L10n.t("main.relayCheckNoTls", ["code": "net::ERR_SSL_PROTOCOL_ERROR"]))
    let http = NSError(domain: NSURLErrorDomain, code: NSURLErrorAppTransportSecurityRequiresSecureConnection)
    #expect(RelayProbe.unreachableReason(http) == L10n.t("relay.checkHttpRefused"))
    #expect(RelayProbe.certificateCode(errSecHostNameMismatch) == "net::ERR_CERT_COMMON_NAME_INVALID")
    #expect(RelayProbe.certificateCode(errSecCertificateExpired) == "net::ERR_CERT_DATE_INVALID")
    #expect(RelayProbe.certificateCode(errSecNotTrusted) == "net::ERR_CERT_AUTHORITY_INVALID")
  }
}
