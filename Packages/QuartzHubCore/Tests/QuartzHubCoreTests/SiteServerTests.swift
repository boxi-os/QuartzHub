import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// The server half against QuartzControl's running siteServer (`scripts/site-copy-golden.mjs`):
/// the 50 addresses fetched there are fetched here over http on 127.0.0.1, compared by status,
/// content type and body. Then a HEAD, two requests on one connection, and the end of `close()`.
@Suite struct SiteServerTests {
  static func fetch(_ session: URLSession, _ href: String, method: String = "GET") async throws -> (Int, String?, Data) {
    var request = URLRequest(url: URL(string: href)!)
    request.httpMethod = method
    let (data, response) = try await session.data(for: request)
    let http = response as! HTTPURLResponse
    return (http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), data)
  }

  /// Writes `request` to the server on one TCP connection and reads until `until` has arrived.
  /// The first IPv4 address of this machine that is not loopback, if it has one.
  static func lanAddress() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
      guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
      let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { String(cString: inet_ntoa($0.pointee.sin_addr)) }
      if !ip.hasPrefix("127.") { return ip }
    }
    return nil
  }

  static func exchange(_ origin: String, _ request: String, until: String, host: String = "127.0.0.1") throws -> String {
    let port = UInt16(JSText.split(origin, ":").last!)!
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr(host)
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
    let bytes = Array(request.utf8)
    _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    var received = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while !JSText.includes(String(decoding: received, as: UTF8.self), until) {
      let n = read(fd, &buffer, buffer.count)
      if n <= 0 { break }
      received.append(contentsOf: buffer[0..<n])
    }
    return String(decoding: received, as: UTF8.self)
  }

  @Test func answersAsQuartzControlsServer() async throws {
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-site-server"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let (build, temp) = try SiteCopyTests.buildFixture(work)
    try Posix.write("\(temp)/neben-der-kopie.txt", Data("neben".utf8))
    let server = try await SiteServer.start(try SiteCopy.make(from: build, tempRoot: temp))
    _ = server.copy.setDocument("epub.html", "<p>eigen</p>")
    _ = server.copy.setDocument("drawing.html", "zeichnen")
    _ = server.copy.setDocument("a b.html", "leer")
    let session = URLSession(configuration: .ephemeral)
    #expect(JSText.test(server.origin, #"\Ahttp://127\.0\.0\.1:\d+\z"#))

    let answers = SiteCopyTests.golden["answers"]!.arrayValue!
    #expect(answers.count == 50)
    for a in answers {
      let path = a["path"]!.stringValue!
      // As fetch sends it: escaped by WHATWG, without the fragment.
      let href = WebURL(server.origin + path).parts!.href
      let (status, type, body) = try await Self.fetch(session, href)
      #expect(Double(status) == a["status"]!.numberValue! && (type.map(JSONValue.string) ?? .null) == a["type"]!, "\(path): \(status) \(type ?? "-")")
      #expect(JSText.slice(String(decoding: body, as: UTF8.self), 0, 40) == a["body"]!.stringValue!, "\(path)")
    }
    let head = try await Self.fetch(session, server.origin + "/a", method: "HEAD")
    #expect(head.0 == 200 && head.1 == "text/html; charset=utf-8" && head.2.isEmpty)
    let post = try await Self.fetch(session, server.origin + "/b/", method: "POST")
    #expect(post.0 == 200 && String(decoding: post.2, as: UTF8.self) == "b")

    // Two requests on one connection, the first with a body to read past.
    // A body that would end a head of its own if it were not read past.
    let raw = try Self.exchange(server.origin, "POST /c.html HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nx\r\n\r\nGET /a HTTP/1.1\r\nHost: x\r\n\r\n",
                                until: "a-datei")
    #expect(JSText.matches(raw, "HTTP/1.1 200 OK").count == 2, "\(raw)")
    #expect(JSText.includes(raw, "\r\n\r\nc") && JSText.includes(raw, "Content-Length: 7\r\n") && JSText.endsWith(raw, "a-datei"), "\(raw)")
    // A HEAD answers the head only: the next answer on the connection starts right after it.
    let headThenGet = try Self.exchange(server.origin, "HEAD /a HTTP/1.1\r\nHost: x\r\n\r\nGET /c.html HTTP/1.1\r\nHost: x\r\n\r\n", until: "\r\n\r\nc")
    #expect(!JSText.includes(headThenGet, "a-datei") && JSText.includes(headThenGet, "Content-Length: 7\r\n") && JSText.endsWith(headThenGet, "\r\n\r\nc"), "\(headThenGet)")
    // Only 127.0.0.1 listens: the machine's address on the network does not reach it.
    if let lan = Self.lanAddress() {
      #expect(throws: (any Error).self) { _ = try Self.exchange(server.origin.replacingOccurrences(of: "127.0.0.1", with: lan), "GET / HTTP/1.1\r\n\r\n", until: "\r\n\r\n", host: lan) }
    }
    let missing = try Self.exchange(server.origin, "GET /fehlt HTTP/1.1\r\nHost: x\r\n\r\n", until: "\r\n\r\n")
    #expect(JSText.startsWith(missing, "HTTP/1.1 404 Not Found\r\n") && !JSText.includes(missing, "Content-Type") && JSText.includes(missing, "Content-Length: 0"), "\(missing)")

    let root = server.copy.root
    server.close()
    #expect(!Posix.exists(root))
    await #expect(throws: (any Error).self) { _ = try await Self.fetch(URLSession(configuration: .ephemeral), server.origin + "/") }
  }
}
