import Foundation
import Synchronization

/// What send.php answered right after an upload (`RelayCheck`): `GET ?challenge=<form>` with the
/// site's origin.
public enum RelayCheck: Equatable, Sendable {
  public enum Listed: Equatable, Sendable {
    case yes, no, any
  }

  /// The origin the check sent, and whether the uploaded "Erlaubte Origins" name it.
  public struct OriginNote: Equatable, Sendable {
    public let sent: String
    public let listed: Listed
  }

  /// `counters`: whether PHP may write the counter directory (quartz-forms 0.5.11 on), nil before.
  case ok(url: String, counters: Bool?)
  /// 500 with an empty body: PHP stopped before send.php could answer.
  case phpError(url: String)
  /// The relay's own refusal; with `origin`, the origin the check sent and whether the uploaded
  /// "Erlaubte Origins" name it (set by the upload, not the probe).
  case relayError(url: String, status: Int, error: String, message: String, origin: OriginNote?)
  /// send.php came back as its own source; `configOpen`: config.php was served as well.
  case noPhp(url: String, configOpen: String?)
  case redirect(url: String, to: String)
  case postRedirect(url: String, to: String, status: Int)
  /// `local`: `to` is this machine or its network, and the check did not go there.
  case redirectNoRelay(url: String, to: String, local: Bool)
  case otherRelay(url: String)
  case phpMessage(url: String, message: String)
  case phpCannotRead(url: String)
  case http(url: String, status: Int)
  case unreachable(url: String, reason: String)
  case noURL

  public var url: String? {
    switch self {
    case .ok(let url, _), .phpError(let url), .relayError(let url, _, _, _, _), .noPhp(let url, _), .redirect(let url, _),
         .postRedirect(let url, _, _), .redirectNoRelay(let url, _, _), .otherRelay(let url), .phpMessage(let url, _),
         .phpCannotRead(let url), .http(let url, _), .unreachable(let url, _):
      url
    case .noURL: nil
    }
  }
}

/// The relay probe of QuartzControl's `formsService.ts` (checkRelay, countersServed, getWithOrigin,
/// phpMessage, localHost): asks the uploaded relay for a stamp, as a form does when its page opens,
/// so a relay that cannot run is found by the upload and not by the first visitor. Every branch
/// and its reason is QuartzControl's; the comments there name the measurement behind each.
///
/// The transport is URLSession instead of Chromium's `net.request`, with Chromium's behaviour where
/// formsService.ts depends on it: redirects followed and seen hop by hop, `Origin: null` once a hop
/// changed the origin, every redirect target serialized as WHATWG does (`WebURL`, numeric hosts).
/// Deviations, each a decision:
/// - A failure names Chromium's code where QuartzControl measured one (refused, no name, no route,
///   dropped, certificate, no TLS); any other failure is the system's sentence.
/// - A redirect to a host WebURL does not parse ("%" or non-ASCII) counts as this machine and is not
///   followed; a relay address with such a host is `noURL`.
/// - URLSession sends a GET once more (up to three times) when the connection drops without an
///   answer; the server sees the repeats, the answer is the same.
/// - A text/plain answer whose body stalls below 512 bytes is "no answer" (relayCheckTimeout), not
///   "incomplete": URLSession holds the response back for MIME sniffing and does not show its
///   status. JSON (the relay) and HTML (a host's page) are not held back.
public struct RelayProbe: Sendable {
  /// One request's deadline, redirects included; 10 s.
  var timeout: Duration
  /// The pause before asking once more for another generation; 3 s.
  var askAgain: Duration
  let configuration: @Sendable () -> URLSessionConfiguration
  /// Certificates (DER) trusted besides the system's, for a test's server (as FTPSession's `ca`).
  var anchors: [Data] = []

  public init() {
    self.init(timeout: .seconds(10), askAgain: .seconds(3), configuration: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      return configuration
    })
  }

  init(timeout: Duration, askAgain: Duration, configuration: @escaping @Sendable () -> URLSessionConfiguration) {
    self.timeout = timeout
    self.askAgain = askAgain
    self.configuration = configuration
  }

  /// The relay's answer is a line of JSON; a host's error page is a few KiB. Nothing more is read.
  static let maxBytes = 64 * 1024
  /// What the relay answers a `GET ?challenge=` with when it refuses (send.php).
  static let getErrors = ["unknown_form", "origin", "secret_config", "mbstring_config"]

  // MARK: the judgements

  /// `checkRelay`.
  public func check(url: String?, origin: String?, form: String?, generation: String?, again: Bool = true) async -> RelayCheck {
    guard let url, JSText.test(url, "(?i)^https?://"), let form, !form.isEmpty,
          case .parsed(var probe) = WebURL(url, numericHosts: true) else { return .noURL }
    var params = Self.searchParams(probe.query)
    Self.set(&params, "challenge", form)
    if let generation, !generation.isEmpty { Self.set(&params, "generation", generation) }
    probe = probe.with(query: Self.serialize(params))
    let res = await get(probe.href, origin: origin)
    guard case .answer(let answer) = res else {
      if case .failed(let reason) = res { return .unreachable(url: url, reason: reason) }
      return .noURL
    }
    let json = try? JSJSON.parse(Data(answer.body.utf8))
    let base = WebURL(url, numericHosts: true).parts!
    let to = answer.redirectedTo.flatMap { WebURL($0, numericHosts: true).parts }
    let relayAnswered = json?["ok"] == .bool(true) ? json?["stamp"]?.stringValue != nil
      : json?["ok"] == .bool(false) && Self.getErrors.contains(json?["error"]?.stringValue ?? "\u{0}")
    if let to, to.origin != base.origin || answer.postDropped != nil, !relayAnswered {
      return .redirectNoRelay(url: url, to: Self.place(to), local: answer.local)
    }
    if let to, to.origin != base.origin { return .redirect(url: url, to: Self.place(to)) }
    if let to, let status = answer.postDropped { return .postRedirect(url: url, to: Self.place(to), status: status) }
    if answer.status == 200, json?["ok"] == .bool(true), let generation, !generation.isEmpty, json?["generation"] != .string(generation) {
      if !again { return .otherRelay(url: url) }
      try? await Task.sleep(for: askAgain)
      return await check(url: url, origin: origin, form: form, generation: generation, again: false)
    }
    if answer.status == 200, json?["ok"] == .bool(true) {
      if case .bool(let counters)? = json?["counters"] { return .ok(url: url, counters: counters) }
      return .ok(url: url, counters: nil)
    }
    if json?["error"] == .string("unknown_form") { return .otherRelay(url: url) }
    if let error = json?["error"]?.stringValue {
      return .relayError(url: url, status: answer.status, error: Self.cut(error, 80),
                         message: json?["message"]?.stringValue.map { Self.cut($0, 300) } ?? "", origin: nil)
    }
    if answer.status == 500, JS.trim(answer.body).isEmpty { return .phpError(url: url) }
    if JSText.startsWith(answer.body, "<?php") {
      let config = Self.resolve("config.php", against: url)
      var configOpen: String?
      if let config, case .answer(let served) = await get(config, origin: nil), served.status == 200, JSText.startsWith(served.body, "<?php") {
        configOpen = config
      }
      return .noPhp(url: url, configOpen: configOpen)
    }
    if let shown = Self.phpMessage(answer.body) { return .phpMessage(url: url, message: shown) }
    if answer.status == 404, JS.trim(answer.body) == "File not found." { return .phpCannotRead(url: url) }
    if let to { return .redirectNoRelay(url: url, to: Self.place(to), local: false) }
    return .http(url: url, status: answer.status)
  }

  /// `countersServed`: the address under which counters/qf-probe.count (or, from an older relay,
  /// counters/.htaccess) was served, asked by content.
  public func countersServed(_ url: String) async -> String? {
    async let probe = served(url, "counters/qf-probe.count", "quartz-forms relay probe")
    async let htaccess = served(url, "counters/.htaccess", "# quartz-forms relay")
    let (p, h) = await (probe, htaccess)
    return p ?? h
  }

  func served(_ url: String, _ path: String, _ starts: String) async -> String? {
    guard let address = Self.resolve(path, against: url) else { return nil }
    guard case .answer(let answer) = await get(address, origin: nil), answer.status == 200, JSText.startsWith(answer.body, starts) else { return nil }
    return address
  }

  /// `new URL(path, base).toString()`: relative to the base's folder.
  static func resolve(_ path: String, against base: String) -> String? {
    guard let parts = WebURL(base, numericHosts: true).parts else { return nil }
    let folder = parts.pathname.utf16.lastIndex(of: 0x2F).map { String(parts.pathname[...$0]) } ?? "/"
    return WebURL.Parts(protocol: parts.protocol, username: parts.username, password: parts.password, hostname: parts.hostname, port: parts.port,
                        pathname: folder + path, query: nil, fragment: nil).href
  }

  /// The server's words as the page shows them, at most `max` characters (code points).
  static func cut(_ text: String, _ max: Int) -> String {
    let scalars = text.unicodeScalars
    return scalars.count <= max ? text : String(String.UnicodeScalarView(scalars.prefix(max)))
  }

  /// Where a redirect went, without the query and cut like the rest.
  static func place(_ to: WebURL.Parts) -> String {
    let shown = to.with(query: nil).href
    let short = cut(shown, 300)
    return short == shown ? shown : "\(short)…"
  }

  /// `phpMessage`: the error PHP printed into the answer where `display_errors` is on, the fatal
  /// one first, tags and the place at its end dropped.
  public static func phpMessage(_ body: String) -> String? {
    let html = JSText.test(body, "<b>(?:Fatal error|Parse error|Warning|Deprecated|Notice)</b>:")
    if !html, JSText.test(body, "(?i)<(?:!doctype|html|body)\\b") { return nil }
    let text = JSText.replaceAll(body, "<[^>]+>", with: "")
    let place = "\\s+in\\s+/\\S+?(?: on line \\d+|:\\d+)"
    func line(_ kinds: String) -> String? {
      guard let found = JSText.firstMatch(text, "(?m)^\\s*(?:PHP )?(?:\(kinds)):\\s+(.+?)(?:\(place))\(html ? "?" : "")\\s*$")?.groups[1] else { return nil }
      return cut(found, 300)
    }
    return line("Fatal error|Parse error") ?? line("Warning|Deprecated|Notice")
  }

  /// `localHost`: this machine and its network by the host's literal, the hostname as WHATWG
  /// serializes it.
  public static func localHost(_ hostname: String) -> Bool {
    var host = JSText.replaceAll(hostname, "^\\[|\\]$", with: "").lowercased()
    if JSText.endsWith(host, ".") { host = String(host.dropLast()) }
    if host == "localhost" || JSText.endsWith(host, ".localhost") { return true }
    var v4: String?
    if isIPv4(host) {
      v4 = host
    } else if let hex = JSText.firstMatch(host, "^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$") {
      let high = Int(hex.groups[1]!, radix: 16)!, low = Int(hex.groups[2]!, radix: 16)!
      v4 = [high >> 8, high & 255, low >> 8, low & 255].map(String.init).joined(separator: ".")
    } else {
      v4 = JSText.firstMatch(host, "^::ffff:(\\d+\\.\\d+\\.\\d+\\.\\d+)$")?.groups[1]
    }
    if let v4, isIPv4(v4) {
      let parts = v4.split(separator: ".").map { Int($0)! }
      let a = parts[0], b = parts[1]
      return a == 0 || a == 10 || a == 127 || (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)
    }
    return host.contains(":") && WebURL.ipv6(host) != nil
      && (host == "::" || host == "::1" || JSText.test(host, "^f[cd]") || JSText.test(host, "^fe[89ab]"))
  }

  /// Node's `net.isIPv4`: four decimal parts 0…255 without leading zeros.
  static func isIPv4(_ host: String) -> Bool {
    let parts = JSText.split(host, ".")
    return parts.count == 4 && parts.allSatisfy { JSText.test($0, "^(?:0|[1-9][0-9]{0,2})$") && Int($0)! <= 255 }
  }

  /// The host a redirect target names, as localHost reads it; a host WebURL cannot parse counts
  /// as local (not followed).
  static func isLocal(_ url: String) -> Bool {
    guard let parts = WebURL(url, numericHosts: true).parts else { return true }
    return localHost(parts.hostname)
  }

  // MARK: URLSearchParams

  static func searchParams(_ query: String?) -> [(String, String)] {
    guard let query, !query.isEmpty else { return [] }
    return JSText.split(query, "&").filter { !$0.isEmpty }.map { pair in
      let at = JSText.indexOf(pair, "=")
      let name = at.map { JSText.slice(pair, 0, $0) } ?? pair
      let value = at.map { JSText.slice(pair, $0 + 1) } ?? ""
      return (WebURL.percentDecode(JSText.replaceAll(name, "\\+", with: " ")), WebURL.percentDecode(JSText.replaceAll(value, "\\+", with: " ")))
    }
  }

  static func set(_ params: inout [(String, String)], _ name: String, _ value: String) {
    if let first = params.firstIndex(where: { $0.0 == name }) {
      params[first].1 = value
      var i = params.count - 1
      while i > first {
        if params[i].0 == name { params.remove(at: i) }
        i -= 1
      }
    } else {
      params.append((name, value))
    }
  }

  static func remove(_ params: inout [(String, String)], _ name: String) { params.removeAll { $0.0 == name } }

  /// application/x-www-form-urlencoded; nil for an empty list (the URL then has no "?").
  static func serialize(_ params: [(String, String)]) -> String? {
    guard !params.isEmpty else { return nil }
    func encode(_ text: String) -> String {
      text.utf8.map { byte -> String in
        switch byte {
        case 0x20: "+"
        case 0x2A, 0x2D, 0x2E, 0x5F, 0x30...0x39, 0x41...0x5A, 0x61...0x7A: String(UnicodeScalar(byte))
        default: String(format: "%%%02X", byte)
        }
      }.joined()
    }
    return params.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
  }

  // MARK: the request

  struct Answer: Equatable {
    var status: Int
    var body: String
    var redirectedTo: String?
    var postDropped: Int?
    var local = false
  }

  enum Outcome: Equatable {
    case answer(Answer)
    case failed(String)
  }

  /// `getWithOrigin`: one GET, answering with whatever status came back.
  func get(_ url: String, origin: String?, deadline: ContinuousClock.Instant? = nil) async -> Outcome {
    // A request handed on keeps the first one's deadline, and when it passes, QuartzControl's first
    // request (which never got a response) is the one that answers: no status.
    let handedOn = deadline != nil
    let deadline = deadline ?? .now + timeout
    guard let request = URL(string: url) else { return .failed("net::ERR_INVALID_URL") }
    let fetch = Fetch(start: url, origin: origin, seconds: Self.seconds(timeout), reportsStatus: !handedOn, anchors: anchors)
    let session = URLSession(configuration: configuration(), delegate: fetch, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let outcome: Fetch.Result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        fetch.begin(continuation)
        var urlRequest = URLRequest(url: request, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        if let origin { urlRequest.setValue(origin, forHTTPHeaderField: "Origin") }
        let task = session.dataTask(with: urlRequest)
        fetch.attach(task, timer: Task {
          try? await Task.sleep(until: deadline)
          if !Task.isCancelled { fetch.expire() }
        })
        task.resume()
      }
    } onCancel: {
      fetch.expire()
    }
    switch outcome {
    case .done(let answer): return .answer(answer)
    case .failed(let reason): return .failed(reason)
    case .handOn(let next, let redirectedTo, let postDropped):
      // Not the generation to another origin: what answers there is asked without it, with the
      // `Origin: null` Chromium sends after a redirect.
      let answer = await get(next, origin: "null", deadline: deadline)
      guard case .answer(var handed) = answer else { return answer }
      handed.redirectedTo = handed.redirectedTo ?? redirectedTo
      handed.postDropped = postDropped ?? handed.postDropped
      return .answer(handed)
    }
  }

  static func seconds(_ duration: Duration) -> String {
    let ms = Double(duration / .milliseconds(1))
    return ms.truncatingRemainder(dividingBy: 1000) == 0 ? String(Int(ms / 1000)) : String(ms / 1000)
  }

  /// Chromium's code for the failures formsService.ts names, as `unreachableReason` words them.
  static func unreachableReason(_ error: Error) -> String {
    let ns = error as NSError
    let stream = (ns.userInfo["_kCFStreamErrorCodeKey"] as? Int) ?? 0
    let posix = ((ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain == NSPOSIXErrorDomain ? (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code : nil) ?? stream
    let code: String? = switch ns.code {
    case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot:
      stream == -9843 ? "net::ERR_CERT_COMMON_NAME_INVALID" : "net::ERR_CERT_AUTHORITY_INVALID"
    case NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid: "net::ERR_CERT_DATE_INVALID"
    case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: "net::ERR_NAME_NOT_RESOLVED"
    case NSURLErrorCannotConnectToHost:
      posix == Int(ECONNREFUSED) ? "net::ERR_CONNECTION_REFUSED"
        : posix == Int(EHOSTUNREACH) || posix == Int(ENETUNREACH) ? "net::ERR_ADDRESS_UNREACHABLE" : nil
    case NSURLErrorNetworkConnectionLost:
      posix == Int(ECONNRESET) ? "net::ERR_CONNECTION_RESET" : "net::ERR_EMPTY_RESPONSE"
    case NSURLErrorSecureConnectionFailed: "net::ERR_SSL_PROTOCOL_ERROR"
    default: nil
    }
    guard let code else { return ns.localizedDescription }
    if JSText.startsWith(code, "net::ERR_CERT_") { return L10n.t("main.relayCheckCertificate", ["code": code]) }
    return switch code {
    case "net::ERR_NAME_NOT_RESOLVED": L10n.t("main.relayCheckNoName", ["code": code])
    case "net::ERR_CONNECTION_REFUSED": L10n.t("main.relayCheckRefused", ["code": code])
    case "net::ERR_ADDRESS_UNREACHABLE": L10n.t("main.relayCheckNoRoute", ["code": code])
    case "net::ERR_EMPTY_RESPONSE", "net::ERR_CONNECTION_RESET": L10n.t("main.relayCheckDropped", ["code": code])
    default: L10n.t("main.relayCheckNoTls", ["code": code])
    }
  }

  /// One request through URLSession, with the hops as Chromium reports them.
  final class Fetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Result {
      case done(Answer)
      case failed(String)
      case handOn(next: String, redirectedTo: String, postDropped: Int?)
    }

    struct State {
      var continuation: CheckedContinuation<Result, Never>?
      var task: URLSessionDataTask?
      var timer: Task<Void, Never>?
      var status: Int?
      var body = Data()
      var redirectedTo: String?
      var postDropped: Int?
      var current: String
      var tainted = false
      var hops = 0
    }

    let start: String
    let origin: String?
    let seconds: String
    let reportsStatus: Bool
    let anchors: [Data]
    let state: Mutex<State>

    init(start: String, origin: String?, seconds: String, reportsStatus: Bool, anchors: [Data] = []) {
      self.start = start
      self.origin = origin
      self.seconds = seconds
      self.reportsStatus = reportsStatus
      self.anchors = anchors
      self.state = Mutex(State(current: start))
    }

    func begin(_ continuation: CheckedContinuation<Result, Never>) { state.withLock { $0.continuation = continuation } }
    func attach(_ task: URLSessionDataTask, timer: Task<Void, Never>) {
      state.withLock {
        $0.task = task
        $0.timer = timer
      }
    }

    func finish(_ result: Result) {
      let (continuation, task, timer) = state.withLock { s -> (CheckedContinuation<Result, Never>?, URLSessionDataTask?, Task<Void, Never>?) in
        defer { s.continuation = nil }
        return (s.continuation, s.task, s.timer)
      }
      guard let continuation else { return }
      task?.cancel()
      timer?.cancel()
      continuation.resume(returning: result)
    }

    /// URLSession holds back a text/plain response for MIME sniffing until it has 512 bytes or the
    /// end, so the delegate may not have heard of a response the task already has.
    func expire() {
      let status = reportsStatus ? state.withLock { $0.status ?? ($0.task?.response as? HTTPURLResponse)?.statusCode } : nil
      finish(.failed(status == nil ? L10n.t("main.relayCheckTimeout", ["seconds": seconds])
        : L10n.t("main.relayCheckIncomplete", ["seconds": seconds, "status": String(status!)])))
    }

    func answer(_ s: State) -> Answer {
      let body = s.body.count > RelayProbe.maxBytes ? s.body.prefix(RelayProbe.maxBytes) : s.body
      return Answer(status: s.status ?? 0, body: String(decoding: body, as: UTF8.self), redirectedTo: s.redirectedTo, postDropped: s.postDropped)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
      guard let target = request.url?.absoluteString, case .parsed(let next) = WebURL(target, numericHosts: true) else {
        // A host WebURL does not parse: taken for this machine, not followed.
        let place = request.url?.absoluteString ?? ""
        completionHandler(nil)
        let s = state.withLock { s -> State in
          s.redirectedTo = place
          if [301, 302, 303].contains(response.statusCode) { s.postDropped = s.postDropped ?? response.statusCode }
          return s
        }
        var local = answer(s)
        local.status = response.statusCode
        local.body = ""
        local.local = true
        finish(.done(local))
        return
      }
      let status = response.statusCode
      let (s, previous) = state.withLock { s -> (State, String) in
        s.redirectedTo = next.href
        if [301, 302, 303].contains(status) { s.postDropped = s.postDropped ?? status }
        s.hops += 1
        let previous = s.current
        s.current = next.href
        return (s, previous)
      }
      if RelayProbe.isLocal(next.href), !RelayProbe.isLocal(start) {
        completionHandler(nil)
        var local = answer(s)
        local.status = status
        local.body = ""
        local.local = true
        finish(.done(local))
        return
      }
      let startOrigin = WebURL(start, numericHosts: true).parts?.origin
      var params = RelayProbe.searchParams(next.query)
      if next.origin != startOrigin, params.contains(where: { $0.0 == "generation" }) {
        completionHandler(nil)
        RelayProbe.remove(&params, "generation")
        finish(.handOn(next: next.with(query: RelayProbe.serialize(params)).href, redirectedTo: next.href, postDropped: s.postDropped))
        return
      }
      guard s.hops <= 20 else {
        completionHandler(nil)
        return
      }
      var followed = request
      followed.httpMethod = "GET"
      followed.httpBody = nil
      let tainted = state.withLock { st -> Bool in
        st.tainted = st.tainted || WebURL(previous, numericHosts: true).parts?.origin != next.origin
        return st.tainted
      }
      if origin != nil { followed.setValue(tainted ? "null" : origin, forHTTPHeaderField: "Origin") }
      completionHandler(followed)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
      guard !anchors.isEmpty, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust else {
        completionHandler(.performDefaultHandling, nil)
        return
      }
      let certificates = anchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
      SecTrustSetAnchorCertificates(trust, certificates as CFArray)
      SecTrustSetAnchorCertificatesOnly(trust, false)
      // Not trusted with them either: the system's answer, which names the certificate.
      if SecTrustEvaluateWithError(trust, nil) {
        completionHandler(.useCredential, URLCredential(trust: trust))
      } else {
        completionHandler(.performDefaultHandling, nil)
      }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
      state.withLock { $0.status = (response as? HTTPURLResponse)?.statusCode ?? 0 }
      completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
      let full = state.withLock { s -> State? in
        s.body.append(data)
        return s.body.count >= RelayProbe.maxBytes ? s : nil
      }
      if let full { finish(.done(answer(full))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
      let s = state.withLock { $0 }
      if let error {
        if (error as NSError).code == NSURLErrorCancelled { return }
        finish(.failed(RelayProbe.unreachableReason(error)))
        return
      }
      finish(.done(answer(s)))
    }
  }
}

extension WebURL.Parts {
  /// The same address with another query (nil: no "?").
  func with(query: String?) -> WebURL.Parts {
    WebURL.Parts(protocol: self.protocol, username: username, password: password, hostname: hostname, port: port,
                 pathname: pathname, query: query, fragment: fragment)
  }
}
