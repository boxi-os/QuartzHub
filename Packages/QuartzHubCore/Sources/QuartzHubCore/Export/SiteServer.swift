import Foundation
import Network
import Synchronization

/// The copy of a build served to the export window on 127.0.0.1 (the server half of QuartzControl's
/// `siteServer.ts`): every answer is `SiteCopy.answer(pathname:)`.
///
/// Over http on 127.0.0.1 rather than a URL scheme of QuartzHub's own, for the reason QuartzControl
/// gave against file://: a Quartz site resolves its links, scripts and contentIndex.json against a
/// web root, and it keeps its theme in `localStorage`, which WebKit gives only an origin it knows
/// (an own scheme's origin is opaque). The request's method does not matter, as with Node's
/// `createServer`; a HEAD gets the head only. A request body is read past, not used.
public final class SiteServer: Sendable {
  public let copy: SiteCopy
  /// `http://127.0.0.1:<port>`.
  public let origin: String
  private let listener: NWListener
  private let observe: (@Sendable (String) -> Void)?
  private let connections = Mutex<[ObjectIdentifier: NWConnection]>([:])
  private static let queue = DispatchQueue(label: "io.github.boxios.quartzhub.site-server")

  private init(copy: SiteCopy, origin: String, listener: NWListener, observe: (@Sendable (String) -> Void)?) {
    self.copy = copy
    self.origin = origin
    self.listener = listener
    self.observe = observe
  }

  public struct StartFailure: Error, CustomStringConvertible {
    public let description: String
  }

  /// Listens on a free port of 127.0.0.1 and answers from `copy` until `close()`. `observe` hears
  /// the path of every request (for measuring what reached the server).
  public static func start(_ copy: SiteCopy, observe: (@Sendable (String) -> Void)? = nil) async throws -> SiteServer {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    parameters.allowLocalEndpointReuse = true
    let listener = try NWListener(using: parameters)
    let ready = Mutex<CheckedContinuation<UInt16, Error>?>(nil)
    let server = Box<SiteServer?>(nil)
    listener.newConnectionHandler = { connection in server.value?.accept(connection) }
    let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
      ready.withLock { $0 = continuation }
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          ready.withLock { $0?.resume(returning: listener.port?.rawValue ?? 0); $0 = nil }
        case .failed(let error):
          ready.withLock { $0?.resume(throwing: error); $0 = nil }
        case .cancelled:
          ready.withLock { $0?.resume(throwing: StartFailure(description: "listener cancelled")); $0 = nil }
        default: break
        }
      }
      listener.start(queue: queue)
    }
    let made = SiteServer(copy: copy, origin: "http://127.0.0.1:\(port)", listener: listener, observe: observe)
    server.value = made
    return made
  }

  /// Stops listening, drops every connection and removes the copy.
  public func close() {
    listener.cancel()
    for connection in connections.withLock({ Array($0.values) }) { connection.cancel() }
    connections.withLock { $0.removeAll() }
    copy.close()
  }

  private func accept(_ connection: NWConnection) {
    connections.withLock { $0[ObjectIdentifier(connection)] = connection }
    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled: self?.connections.withLock { _ = $0.removeValue(forKey: ObjectIdentifier(connection)) }
      default: break
      }
    }
    connection.start(queue: Self.queue)
    serve(connection, buffer: Data())
  }

  private static let headEnd = Data("\r\n\r\n".utf8)

  /// One request after another on the same connection, as the window keeps it alive.
  private func serve(_ connection: NWConnection, buffer: Data) {
    if let end = buffer.range(of: Self.headEnd) {
      let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
      var rest = Data(buffer[end.upperBound...])
      let lines = head.components(separatedBy: "\r\n")
      let parts = lines.first?.split(separator: " ", omittingEmptySubsequences: true) ?? []
      guard parts.count >= 2 else {
        connection.cancel()
        return
      }
      let method = String(parts[0]), target = String(parts[1])
      var length = 0
      var chunked = false
      for line in lines.dropFirst() {
        let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard pair.count == 2 else { continue }
        if pair[0].lowercased() == "content-length" { length = Int(pair[1]) ?? 0 }
        if pair[0].lowercased() == "transfer-encoding" && pair[1].lowercased().contains("chunked") { chunked = true }
      }
      // The body is read past before the answer goes out, so the next request starts where it should.
      if rest.count < length {
        receive(connection) { [weak self] more in self?.serve(connection, buffer: buffer + more) }
        return
      }
      rest.removeFirst(length)
      // `new URL(req.url, 'http://x').pathname`: dot segments resolved, the escapes as WHATWG writes them.
      let pathname = WebURL("http://x" + target).parts?.pathname ?? "/"
      observe?(pathname)
      let answer = copy.answer(pathname: pathname)
      var response = "HTTP/1.1 \(answer.status) \(Self.reason(answer.status))\r\n"
      if let type = answer.type { response += "Content-Type: \(type)\r\n" }
      response += "Content-Length: \(answer.body.count)\r\nConnection: keep-alive\r\n\r\n"
      var bytes = Data(response.utf8)
      if method != "HEAD" { bytes.append(answer.body) }
      connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
        guard error == nil else { return connection.cancel() }
        // A chunked body has no length to read past; the connection ends with this answer.
        if chunked { return connection.cancel() }
        self?.serve(connection, buffer: rest)
      })
      return
    }
    receive(connection) { [weak self] more in self?.serve(connection, buffer: buffer + more) }
  }

  private func receive(_ connection: NWConnection, then: @escaping @Sendable (Data) -> Void) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
      if let data, !data.isEmpty { return then(data) }
      if isComplete || error != nil { connection.cancel() }
    }
  }

  static func reason(_ status: Int) -> String {
    switch status {
    case 200: "OK"
    case 404: "Not Found"
    default: "Internal Server Error"
    }
  }
}

/// A value set once after it is handed to a callback (the listener exists before the server).
final class Box<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value
  init(_ value: Value) { stored = value }
  var value: Value {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
