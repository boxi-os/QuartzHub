import Darwin
import Foundation
@testable import QuartzHubCore

/// The system's sshd, started by the test as the user on a free port of 127.0.0.1, with its own
/// host key, its own authorized_keys and a log; stopped and removed with the object. Logins are the
/// test user's, and the login directory is the user's real home: ssh commands from tests use
/// absolute paths below `root` only. SFTP starts in `home` (`internal-sftp -d`), so a relative path
/// there stays in the scratch folder.
///
/// No password can be checked (a sshd that is not root cannot read them); a password login is
/// measured as "offered" in the log, and for real on debian-vm.
final class LocalSSHD: @unchecked Sendable {
  let root: String
  let home: String
  let port: Int
  let hostKey: PinnedHostKey
  /// A key the server accepts, and one it does not know.
  let clientKey: String
  let strangerKey: String
  let user = String(cString: getpwuid(getuid())!.pointee.pw_name)
  let environment: ToolEnvironment
  private let process: LaunchedProcess

  static func freePort() -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: 0,
                              sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
    return Int(UInt16(bigEndian: address.sin_port))
  }

  static func reachable(_ port: Int) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: UInt16(port).bigEndian,
                              sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
    return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
  }

  static func shell(_ executable: String, _ arguments: [String]) async throws {
    let result = await ProcessRunner.run(Command(executable, arguments, environment: ["PATH": "/usr/bin:/bin"]))
    guard result.success else { throw PublishFailure("\(executable) \(arguments.joined(separator: " ")): \(result.output)") }
  }

  /// `config` is added to sshd_config (a Match block, a password setting).
  init(config: String = "") async throws {
    root = TemplatePackageTests.realpath(TestFolder.make("qh-sshd"))
    home = "\(root)/home"
    try Posix.mkdirs(home)
    port = Self.freePort()
    for name in ["host", "client", "stranger"] {
      try await Self.shell("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", name, "-f", "\(root)/\(name)"])
    }
    clientKey = "\(root)/client"
    strangerKey = "\(root)/stranger"
    try Posix.write("\(root)/authorized_keys", try Posix.read("\(root)/client.pub"))
    chmod("\(root)/authorized_keys", 0o600)
    let pub = JSText.split(JS.trim(String(decoding: try Posix.read("\(root)/host.pub"), as: UTF8.self)), " ")
    let blob = Data(base64Encoded: pub[1])!
    hostKey = PinnedHostKey(fingerprint: SSHLogin.fingerprint(blob: blob), blob: pub[1], type: pub[0])
    let settings = """
      Port \(port)
      ListenAddress 127.0.0.1
      HostKey \(root)/host
      PidFile \(root)/sshd.pid
      AuthorizedKeysFile \(root)/authorized_keys
      UsePAM no
      StrictModes no
      KbdInteractiveAuthentication no
      Subsystem sftp internal-sftp -d \(home)
      LogLevel VERBOSE
      \(config)

      """
    try Posix.write("\(root)/sshd_config", Data(settings.utf8))
    switch ProcessRunner.launch(Command("/usr/sbin/sshd", ["-D", "-f", "\(root)/sshd_config", "-E", "\(root)/sshd.log"], environment: ["PATH": "/usr/bin:/bin"])) {
    case .success(let launched): process = launched
    case .failure(let failure): throw PublishFailure("sshd: \(failure)")
    }
    environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"],
                                  hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system,
                                  runtime: .repository, git: nil, bundledGitFailure: nil)
    var tries = 0
    while !Self.reachable(port) && tries < 100 {
      tries += 1
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  deinit {
    _ = process.signal(SIGTERM)
    try? FileManager.default.removeItem(atPath: root)
  }

  var log: String { String(decoding: (try? Posix.read("\(root)/sshd.log")) ?? Data(), as: UTF8.self) }

  /// A connection to this server.
  func connection(_ method: StoredConnection.AuthMethod = .privateKey, keyPath: String? = nil, hostKey: PinnedHostKey? = nil,
                  id: String = "00000000-0000-4000-8000-000000000001") -> Connection {
    var object = JSONObject([("id", .string(id)), ("kind", .string("ssh")), ("name", .string("lokal")), ("host", .string("127.0.0.1")),
                             ("port", .number(Double(port))), ("username", .string(user)), ("authMethod", .string(method.rawValue))])
    object["keyPath"] = keyPath.map(JSONValue.string)
    object["hostKey"] = hostKey?.json
    return Connection(stored: StoredConnection(object: object))
  }

  /// `ssh … true` with a login, and its output.
  func run(_ login: SSHLogin, _ remote: [String] = ["true"]) async -> CommandResult {
    await ProcessRunner.run(environment.command("ssh", login.options + [login.host] + remote).adding(login.variables))
  }
}
