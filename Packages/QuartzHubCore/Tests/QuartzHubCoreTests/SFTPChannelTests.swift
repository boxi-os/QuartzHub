import Foundation
import Testing
@testable import QuartzHubCore

/// QuartzHub's SFTP client against the system's sshd (`internal-sftp`), on this machine: what it
/// writes is checked on the disk (content, mode, the bytes of a name), every answer of the server
/// with its code.
@Suite(.serialized) struct SFTPChannelTests {
  static func open(_ sshd: LocalSSHD, key: String? = nil) async throws -> SFTPChannel {
    let login = try SSHLogin.prepare(sshd.connection(keyPath: key ?? sshd.clientKey), secret: nil, hostKey: sshd.hostKey, environment: [:],
                                     configFile: "/dev/null")
    defer { login.cleanup() }
    return try await SFTPChannel.open(login, environment: sshd.environment)
  }

  static func mode(_ path: String) -> UInt32 {
    var info = stat()
    lstat(path, &info)
    return UInt32(info.st_mode & 0o7777)
  }

  @Test func writesReadsAndAnswersAsTheServer() async throws {
    let sshd = try await LocalSSHD()
    let sftp = try await Self.open(sshd)
    #expect(try await sftp.realpath(".") == sshd.home)

    let dir = "\(sshd.home)/Gärten-Ü"
    try await sftp.mkdir(dir)
    #expect(Posix.entries(sshd.home)?.map { Array($0.name.utf8) } == [Array("Gärten-Ü".utf8)])
    #expect(try await sftp.stat(dir).isDirectory)
    await #expect(throws: SFTPChannel.Failure.self) { try await sftp.mkdir(dir) }

    // A new file with its mode, a file that was 0666 set to 0644 by the open handle.
    let local = "\(sshd.root)/local.bin"
    var bytes = [UInt8](repeating: 0, count: 1_000_003)
    for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ i >> 7) }
    try Posix.write(local, Data(bytes))
    try await sftp.writeFile(local: local, remote: "\(dir)/über.bin", mode: 0o644)
    #expect(try Posix.read("\(dir)/über.bin") == Data(bytes))
    #expect(Self.mode("\(dir)/über.bin") == 0o644)
    try Posix.write("\(dir)/alt.html", Data("alt und länger".utf8))
    chmod("\(dir)/alt.html", 0o666)
    try Posix.write(local, Data("neu".utf8))
    try await sftp.writeFile(local: local, remote: "\(dir)/alt.html", mode: 0o644)
    #expect(try Posix.read("\(dir)/alt.html") == Data("neu".utf8) && Self.mode("\(dir)/alt.html") == 0o644)
    try Posix.write(local, Data())
    try await sftp.writeFile(local: local, remote: "\(dir)/leer", mode: 0o600)
    #expect(try Posix.read("\(dir)/leer").isEmpty && Self.mode("\(dir)/leer") == 0o600)
    #expect(try await sftp.readFile("\(dir)/über.bin") == Data(bytes))

    // stat follows a link, lstat does not; a mode set by path.
    try Posix.symlink(dir, "\(sshd.home)/link")
    #expect(try await sftp.lstat("\(sshd.home)/link").isSymbolicLink)
    #expect(try await sftp.stat("\(sshd.home)/link").isDirectory)
    try await sftp.setPermissions("\(dir)/leer", 0o640)
    #expect(Self.mode("\(dir)/leer") == 0o640)
    let attributes = try await sftp.lstat("\(dir)/leer")
    #expect(attributes.mode == 0o640 && attributes.isFile)

    // The server's answers with their codes.
    func code(_ body: () async throws -> Void) async -> UInt32? {
      do {
        try await body()
        return 0
      } catch {
        if case .status(let status)? = error as? SFTPChannel.Failure { return status.code }
        return nil
      }
    }
    #expect(await code { try await sftp.remove("\(dir)/fehlt") } == 2)
    #expect(await code { _ = try await sftp.lstat("\(dir)/fehlt") } == 2)
    #expect(await code { try await sftp.setPermissions("\(dir)/fehlt", 0o644) } == 2)
    #expect(await code { _ = try await sftp.readFile("\(dir)/fehlt") } == 2)
    chmod(dir, 0o555)
    #expect(await code { try await sftp.remove("\(dir)/leer") } == 3)
    chmod(dir, 0o755)
    // A folder: refused, not missing (macOS says 3, Linux's sftp-server 4).
    let folder = await code { try await sftp.remove(dir) }
    #expect(folder != nil && folder != 0 && folder != 2, "\(String(describing: folder))")
    #expect(await code { try await sftp.remove("\(dir)/leer") } == 0)
    #expect(!Posix.exists("\(dir)/leer"))
    await sftp.close()
  }

  /// A refused login ends the conversation before it began, with ssh's line.
  @Test func aRefusedLoginIsNoAnswer() async throws {
    let sshd = try await LocalSSHD()
    do {
      _ = try await Self.open(sshd, key: sshd.strangerKey)
      Issue.record("opened")
    } catch let failure as SFTPChannel.Failure {
      guard case .disconnected(let text) = failure else { Issue.record("\(failure)"); return }
      #expect(JSText.includes(text, "Permission denied"), "\(text)")
    }
  }

  /// A connection that ends: what is asked after fails as disconnected, never as an answer.
  @Test func aDroppedConnectionIsNoAnswer() async throws {
    let sshd = try await LocalSSHD()
    let sftp = try await Self.open(sshd)
    #expect(try await sftp.realpath(".") == sshd.home)
    // The server's session processes: children of this server's listener.
    let listener = JS.trim(String(decoding: try Posix.read("\(sshd.root)/sshd.pid"), as: UTF8.self))
    // The connection is held below the session's monitor: every descendant goes.
    var pending = [listener], session: [Int32] = []
    while let parent = pending.popLast() {
      let children = await ProcessRunner.run(Command("/usr/bin/pgrep", ["-P", parent], environment: ["PATH": "/usr/bin"]))
      for pid in JSText.split(children.stdout, "\n").compactMap({ Int32($0) }) {
        session.append(pid)
        pending.append(String(pid))
      }
    }
    #expect(!session.isEmpty)
    for pid in session { kill(pid, SIGKILL) }
    do {
      _ = try await sftp.lstat(sshd.home)
      Issue.record("answered")
    } catch let failure as SFTPChannel.Failure {
      if case .status = failure { Issue.record("a dropped connection read as an answer: \(failure)") }
    }
    await sftp.close()
  }
}
