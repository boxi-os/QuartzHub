import Foundation
import Testing
@testable import QuartzHubCore

/// basic-ftp in the `ftp-session` helper against vsftpd on debian-vm (TLS allowed, not forced,
/// session reuse required; a server certificate for debian.local from the test CA in
/// /etc/ssl/qh-8c). Only with `QH_VM_TESTS=1`, `QH_FTP_PW` (qchost's password) and `QH_VM_CERT`
/// (that CA). Checked on the host.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["QH_VM_TESTS"] == "1" && HelperRuntime.available,
                             "QH_VM_TESTS=1, QH_FTP_PW, QH_VM_CERT und Helpers/dist"))
struct FTPSessionTests {
  static let host = "debian.local"
  static let folder = "/srv/qc/www/qh8c"
  static var ca: String { String(decoding: (try? Posix.read(ProcessInfo.processInfo.environment["QH_VM_CERT"] ?? "")) ?? Data(), as: UTF8.self) }

  static func admin(_ command: String) async -> String {
    await ProcessRunner.run(Command("/usr/bin/ssh", ["-o", "BatchMode=yes", "debian-vm", command], environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()])).stdout
  }

  func exercise(secure: Bool) async throws {
    _ = await Self.admin("sudo rm -rf \(Self.folder)")
    let ftp = try FTPSession.start(runtime: HelperRuntime.runtime)
    try await ftp.access(host: Self.host, port: 21, user: "qchost", password: ProcessInfo.processInfo.environment["QH_FTP_PW"], secure: secure,
                         ca: secure ? Self.ca : nil)
    #expect(try await ftp.pwd() == "/home/qchost")
    try await ftp.ensureDir("\(Self.folder)/Gärten/b")
    try await ftp.cd("/home/qchost")
    let local = TestFolder.make("qh-ftp") + "/datei.bin"
    var bytes = [UInt8](repeating: 0, count: 300_001)
    for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 7) }
    // A file whose blocks start with "R" and "Q": what s_client took for commands.
    bytes[0] = UInt8(ascii: "R")
    bytes[16384] = UInt8(ascii: "Q")
    try Posix.write(local, Data(bytes))
    try await ftp.upload(local, to: "\(Self.folder)/Gärten/b/über.bin")
    #expect(try await ftp.size("\(Self.folder)/Gärten/b/über.bin") == bytes.count)
    #expect(try await ftp.download("\(Self.folder)/Gärten/b/über.bin") == Data(bytes))
    try await ftp.send("SITE CHMOD 640 \(Self.folder)/Gärten/b/über.bin")
    let listed = try await ftp.list("\(Self.folder)/Gärten/b")
    #expect(listed.map(\.name) == ["über.bin"] && listed.first?.mode == 0o640, "\(listed)")
    #expect(await Self.admin("sudo stat -c '%a %s %n' \(Self.folder)/Gärten/b/*") == "640 300001 \(Self.folder)/Gärten/b/über.bin\n")
    try await ftp.remove("\(Self.folder)/Gärten/b/über.bin")
    do {
      try await ftp.remove("\(Self.folder)/Gärten/b/über.bin")
      Issue.record("removed twice")
    } catch let error as FTPSession.FTPError {
      #expect(error.code == 550 && error.message == "550 Delete operation failed." && error.text == "FTPError: 550 Delete operation failed.", "\(error)")
    }
    await ftp.close()
    _ = await Self.admin("sudo rm -rf \(Self.folder)")
  }

  @Test func plain() async throws { try await exercise(secure: false) }

  @Test func explicitTLSWithSessionReuse() async throws { try await exercise(secure: true) }

  /// Node's checks: a CA nobody trusts, a name the certificate does not carry.
  @Test func untrustedOrWrongNameIsRefused() async throws {
    for (host, ca) in [(Self.host, nil), ("192.168.64.6", Self.ca)] as [(String, String?)] {
      let ftp = try FTPSession.start(runtime: HelperRuntime.runtime)
      do {
        try await ftp.access(host: host, port: 21, user: "qchost", password: "x", secure: true, ca: ca)
        Issue.record("\(host): connected")
      } catch let failure as FTPSession.Failure {
        #expect(!failure.message.isEmpty, "\(failure)")
      }
      await ftp.close()
    }
  }
}

/// Without the VM: what a refused connection says. "localhost" has two addresses, so Node answers
/// with an AggregateError whose message is empty; its code is all there is to read. On debian-vm,
/// with the local network not allowed, the same form carried EHOSTUNREACH (2026-11-10).
@Suite(.enabled(if: HelperRuntime.available && FileManager.default.fileExists(atPath: "\(HelperRuntime.runtime.helpers)/ftp-session.cjs"),
                "Runtime/ und Helpers/dist"))
struct FTPSessionFailureTests {
  @Test func aRefusedConnectionCarriesNodesCode() async throws {
    let ftp = try FTPSession.start(runtime: HelperRuntime.runtime)
    do {
      try await ftp.access(host: "localhost", port: LocalSSHD.freePort(), user: "u", password: nil, secure: false, ca: nil)
      Issue.record("connected")
    } catch let failure as FTPSession.Failure {
      #expect(failure.nodeCode == "ECONNREFUSED", "\(failure)")
      #expect(failure.text == "AggregateError:  (control socket)", "\(failure.text)")
    }
    await ftp.close()
  }
}
