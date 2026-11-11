import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own checkRelay, countersServed, phpMessage and localHost
/// (`scripts/relay-probe-golden.mjs`): 64 probes of Fixtures/forms/relay-server.mjs, which is also
/// the HTTP proxy for the .test names, each with its answer and the requests the server saw (host,
/// path with query, Origin), and the two pure judgements over 19 bodies and 67 addresses. The
/// deadlines are shortened as in the golden (2 s, 0.5 s). Two deviations of the transport: a GET
/// whose connection dropped is sent up to three times, and a text/plain body that stalls below 512
/// bytes is "no answer", as URLSession holds the response back for MIME sniffing.
@Suite(.serialized, .enabled(if: ToolEnvironmentTests.hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
struct RelayProbeTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/forms")
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("probe-cases.json")))

  /// The server, its port, and a port nothing listens on.
  static func startServer() async throws -> (LaunchedProcess, Int, Int) {
    let node = "\(ToolEnvironmentTests.runtime.nodeBin)/node"
    guard case .success(let launched) = ProcessRunner.launchPiped(Command(node, [fixtures.appendingPathComponent("relay-server.mjs").path],
                                                                         environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"])) else {
      throw PublishFailure("relay-server did not start")
    }
    close(launched.stdin)
    var line = Data()
    var byte: UInt8 = 0
    while read(launched.stdout, &byte, 1) == 1, byte != 0x0A { line.append(byte) }
    let port = Int(try JSJSON.parse(line)["port"]?.numberValue ?? 0)
    let probe = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: 0,
                              sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(probe, $0, length) } }
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(probe, $0, &length) } }
    let closed = Int(UInt16(bigEndian: address.sin_port))
    close(probe)
    return (launched.process, port, closed)
  }

  static func probe(port: Int) -> RelayProbe {
    RelayProbe(timeout: .seconds(2), askAgain: .milliseconds(1500), configuration: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      configuration.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable as String: 1, kCFNetworkProxiesHTTPProxy as String: "127.0.0.1", kCFNetworkProxiesHTTPPort as String: port,
        kCFNetworkProxiesExceptionsList as String: ["127.0.0.1", "localhost", "::1"]
      ]
      return configuration
    })
  }

  static func serverLog(_ port: Int) async throws -> JSONValue {
    let (data, _) = try await URLSession(configuration: .ephemeral).data(from: URL(string: "http://127.0.0.1:\(port)/__log")!)
    return try JSJSON.parse(data)
  }

  static func json(_ check: RelayCheck) -> JSONValue {
    func o(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(JSONObject(pairs)) }
    switch check {
    case .noURL: return o([("kind", .string("noUrl"))])
    case .ok(let url, let counters):
      return o([("kind", .string("ok")), ("url", .string(url))] + (counters.map { [("counters", .bool($0))] } ?? []))
    case .phpError(let url): return o([("kind", .string("phpError")), ("url", .string(url))])
    case .relayError(let url, let status, let error, let message, _):
      return o([("kind", .string("relayError")), ("url", .string(url)), ("status", .number(Double(status))), ("error", .string(error)), ("message", .string(message))])
    case .noPhp(let url, let configOpen):
      return o([("kind", .string("noPhp")), ("url", .string(url))] + (configOpen.map { [("configOpen", .string($0))] } ?? []))
    case .redirect(let url, let to): return o([("kind", .string("redirect")), ("url", .string(url)), ("to", .string(to))])
    case .postRedirect(let url, let to, let status):
      return o([("kind", .string("postRedirect")), ("url", .string(url)), ("to", .string(to)), ("status", .number(Double(status)))])
    case .redirectNoRelay(let url, let to, let local):
      return o([("kind", .string("redirectNoRelay")), ("url", .string(url)), ("to", .string(to))] + (local ? [("local", .bool(true))] : []))
    case .otherRelay(let url): return o([("kind", .string("otherRelay")), ("url", .string(url))])
    case .phpMessage(let url, let message): return o([("kind", .string("phpMessage")), ("url", .string(url)), ("message", .string(message))])
    case .phpCannotRead(let url): return o([("kind", .string("phpCannotRead")), ("url", .string(url))])
    case .http(let url, let status): return o([("kind", .string("http")), ("url", .string(url)), ("status", .number(Double(status)))])
    case .unreachable(let url, let reason): return o([("kind", .string("unreachable")), ("url", .string(url)), ("reason", .string(reason))])
    }
  }

  @Test func replaysQuartzControlsProbes() async throws {
    let (server, port, closed) = try await Self.startServer()
    defer { ProcessRunnerTests.endGroup(server) }
    let probe = Self.probe(port: port)
    let unmask = { (s: String) in s.replacingOccurrences(of: "@PORT@", with: String(port)).replacingOccurrences(of: "@CLOSED@", with: String(closed)) }
    let mask = { (s: String) in s.replacingOccurrences(of: ":\(port)", with: ":@PORT@").replacingOccurrences(of: ":\(closed)", with: ":@CLOSED@") }
    var compared = 0
    for c in Self.golden["cases"]?.arrayValue ?? [] {
      let name = c["name"]?.stringValue ?? ""
      let args = c["args"]?.arrayValue ?? []
      _ = try await Self.serverLog(port)
      _ = try await URLSession(configuration: .ephemeral).data(from: URL(string: "http://127.0.0.1:\(port)/__reset")!)
      let started = ContinuousClock.now
      var answer: JSONValue
      if c["op"] == .string("check") {
        let check = await probe.check(url: args[0].stringValue.map(unmask), origin: args[1].stringValue, form: args[2].stringValue, generation: args[3].stringValue)
        answer = try JSJSON.parse(Data(mask(JSJSON.compact(Self.json(check))).utf8))
      } else {
        answer = await probe.countersServed(unmask(args[0].stringValue!)).map { .string(mask($0)) } ?? .null
      }
      // Asking again waits 1.5 s, a deadline 2 s; 1 s between them and a quick answer leaves room
      // for the test runner (at 0.5 s and 0.4 s a quick case read "slow" with the whole suite running).
      let slow = ContinuousClock.now - started > .milliseconds(1000)
      var requests = try await Self.serverLog(port).arrayValue ?? []
      if c["op"] == .string("counters") { requests.sort { JS.string($0["path"]) < JS.string($1["path"]) } }
      // URLSession repeats a GET whose connection dropped without an answer (up to three times).
      if name == "a server that hangs up", requests.count <= 3, Set(requests.map { JSJSON.compact($0) }).count == 1 { requests = Array(requests.prefix(1)) }
      var expected = GoldenText.localize(c["answer"]!)
      if name == "a body that never ends" {
        // text/plain: URLSession holds the response back for MIME sniffing (below 512 bytes).
        expected = .object(JSONObject([("kind", .string("unreachable")), ("url", .string("http://relay.test/slowbody/send.php")),
                                       ("reason", .string(L10n.t("main.relayCheckTimeout", ["seconds": "2"])))]))
      }
      #expect(answer == expected, "\(name)\n\(JSJSON.compact(answer))\n\(JSJSON.compact(expected))")
      #expect(JSONValue.array(requests) == c["requests"]!, "\(name): requests\n\(JSJSON.compact(.array(requests)))\n\(JSJSON.compact(c["requests"]!))")
      #expect(slow == (c["slow"] == .bool(true)), "\(name): slow \(slow)")
      compared += 1
    }
    #expect(compared == 64)
  }

  @Test func phpMessageAsQuartzControl() {
    for c in Self.golden["phpMessage"]?.arrayValue ?? [] {
      let body = c["body"]!.stringValue!
      #expect(RelayProbe.phpMessage(body).map(JSONValue.string) ?? .null == c["message"]!, "\(body)")
    }
  }

  @Test func localHostAsQuartzControl() {
    for c in Self.golden["localHost"]?.arrayValue ?? [] {
      let url = c["url"]!.stringValue!
      let parts = WebURL(url, numericHosts: true).parts
      #expect(parts.map { JSONValue.string($0.hostname) } ?? .null == c["hostname"]!, "\(url): \(String(describing: parts?.hostname))")
      #expect(parts.map { JSONValue.bool(RelayProbe.localHost($0.hostname)) } ?? .null == c["local"]!, "\(url)")
    }
  }
}
