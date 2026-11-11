import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// Review 2026-11-11 (2), nebenbei 15: the basic template's download stops at its limit while it
/// arrives, with or without a Content-Length, instead of being checked once it is all there. A
/// one-request HTTP server on 127.0.0.1; no network.
@Suite struct LimitedFetchTests {
  /// Answers one request with `body`, with a Content-Length header or without (then it closes).
  static func server(body: Int, contentLength: Bool) -> (url: String, done: () -> Void) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }
    listen(fd, 1)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
    let port = Int(UInt16(bigEndian: address.sin_port))
    Thread {
      let client = accept(fd, nil, nil)
      guard client >= 0 else { return }
      var buffer = [UInt8](repeating: 0, count: 4096)
      _ = Darwin.read(client, &buffer, buffer.count)
      let head = "HTTP/1.1 200 OK\r\n" + (contentLength ? "Content-Length: \(body)\r\n" : "") + "Connection: close\r\n\r\n"
      _ = head.withCString { Darwin.write(client, $0, strlen($0)) }
      let chunk = [UInt8](repeating: 65, count: 1024)
      var sent = 0
      while sent < body {
        let n = min(chunk.count, body - sent)
        if Darwin.write(client, chunk, n) <= 0 { break }
        sent += n
      }
      close(client)
    }.start()
    return ("http://127.0.0.1:\(port)/t", { close(fd) })
  }

  @Test(arguments: [true, false]) func aBodyPastTheLimitIsRefused(_ contentLength: Bool) async throws {
    let (url, done) = Self.server(body: 64 * 1024, contentLength: contentLength)
    defer { done() }
    await #expect(throws: FontService.FetchFailure.unreachable) {
      _ = try await FontService.limitedFetch(16 * 1024)(url, nil, .seconds(10))
    }
  }

  @Test func aBodyWithinTheLimitArrivesWhole() async throws {
    let (url, done) = Self.server(body: 3000, contentLength: false)
    defer { done() }
    let response = try await FontService.limitedFetch(16 * 1024)(url, nil, .seconds(10))
    #expect(response.status == 200 && response.body.count == 3000)
  }
}
