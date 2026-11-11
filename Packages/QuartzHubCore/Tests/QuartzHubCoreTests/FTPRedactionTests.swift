import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// A password basic-ftp refuses (here one that ends in a newline, as pasted) never shows in the
/// message: basic-ftp names the whole refused command, and the helper died with Node's report on
/// stderr, which QuartzHub showed (measured 2026-11-11 against a real host). The "server" greets
/// and asks for the password; no network.
@Suite(.enabled(if: HelperRuntime.available, "Helpers/dist"))
struct FTPRedactionTests {
  /// A one-connection FTP greeter on 127.0.0.1: 220, then 331 to USER, then it waits.
  static func greeter() throws -> (port: Int, done: () -> Void) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }
    listen(fd, 1)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
    let port = Int(UInt16(bigEndian: address.sin_port))
    let thread = Thread {
      let client = accept(fd, nil, nil)
      guard client >= 0 else { return }
      func say(_ line: String) { _ = line.withCString { Darwin.write(client, $0, strlen($0)) } }
      say("220 qh greeter\r\n")
      var buffer = [UInt8](repeating: 0, count: 1024)
      while true {
        let count = Darwin.read(client, &buffer, buffer.count)
        if count <= 0 { break }
        let text = String(decoding: buffer[..<count], as: UTF8.self)
        if text.hasPrefix("USER") { say("331 password please\r\n") } else if text.hasPrefix("PASS") { say("530 no\r\n") } else { say("502 no\r\n") }
      }
      close(client)
    }
    thread.start()
    return (port, { close(fd) })
  }

  @Test func aRefusedPasswordNeverShowsInTheMessage() async throws {
    let (port, done) = try Self.greeter()
    defer { done() }
    let password = "qh-geheim-7Xq\n"
    let ftp = try FTPSession.start(runtime: HelperRuntime.runtime)
    var shown = ""
    do {
      try await ftp.access(host: "127.0.0.1", port: port, user: "u", password: password, secure: false, ca: nil)
      Issue.record("logged in")
    } catch let failure as FTPSession.Failure {
      shown = failure.message + "\n" + failure.text
    } catch let error as FTPSession.FTPError {
      shown = error.message + "\n" + error.text
    }
    await ftp.close()
    #expect(!shown.isEmpty)
    #expect(!shown.contains("qh-geheim-7Xq"), "\(shown)")
  }

  /// Review 2026-11-11 (2), nebenbei 7: a short password is not an oracle. With "no" the server's
  /// "530 no" stays readable, and the redaction still takes it out of the refused command.
  @Test func aShortPasswordDoesNotBlankEveryWord() async throws {
    let (port, done) = try Self.greeter()
    defer { done() }
    let ftp = try FTPSession.start(runtime: HelperRuntime.runtime)
    var shown = ""
    do {
      try await ftp.access(host: "127.0.0.1", port: port, user: "u", password: "no", secure: false, ca: nil)
      Issue.record("logged in")
    } catch let failure as FTPSession.Failure {
      shown = failure.message + "\n" + failure.text
    } catch let error as FTPSession.FTPError {
      shown = error.message + "\n" + error.text
    }
    #expect(shown.contains("530 no"), "\(shown)")
    #expect(ftp.redact("Invalid command: Contains control characters. (PASS no)") == "Invalid command: Contains control characters. (PASS ***)")
    #expect(ftp.redact("Socket.<anonymous>") == "Socket.<anonymous>")
    await ftp.close()
  }
}
