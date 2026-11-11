import Darwin
import Foundation
import Synchronization

/// An FTP session through QuartzControl's own client, basic-ftp 6.2.0, in the helper
/// `ftp-session` under QuartzHub's Node (decision of 2026-11-07, docs/decisions/phase-3-dienste.md,
/// point 8c): explicit FTPS with the data connections resuming the control connection's TLS session,
/// Node's certificate checks, and basic-ftp's commands, listings and error text, which reach the
/// output. One helper process per deploy run, one JSON line per call.
///
/// What fails is said as basic-ftp said it: a reply of the server is an `FTPError` (code and the
/// server's lines), anything else (a deadline, TLS, the connection) a `Failure` with the error's
/// message and `String(err)`.
public final class FTPSession: @unchecked Sendable {
  public struct FTPError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Int
    public let message: String
    /// `String(err)`: "FTPError: 550 …".
    public let text: String
    public var description: String { message }
  }

  public struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    /// `String(err)`: "Error: Timeout (control socket)".
    public let text: String
    /// Node's `err.code` ("EHOSTUNREACH"). A host with several addresses that refuses on all of
    /// them says only "AggregateError:  (control socket)"; the code is the first attempt's.
    public var nodeCode: String? = nil
    public var description: String { message }
  }

  /// One entry of `client.list()`.
  public struct Entry: Equatable, Sendable {
    public let name: String
    public let isSymbolicLink: Bool
    public let isDirectory: Bool
    /// user, group, world as 0…7, nil when the listing carries none.
    public let permissions: [Int]?
    public var mode: Int? { permissions.map { $0[0] << 6 | $0[1] << 3 | $0[2] } }
  }

  private let process: LaunchedProcess
  private let input: Int32
  private let state = Mutex(State())
  private let writes = DispatchQueue(label: "FTPSession.write")

  private struct State {
    var next = 1
    var waiting: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    var ended: Failure?
    var stderr = Data()
    /// The password of `access`, kept out of every message as the helper keeps it (the helper's
    /// own report on a crash is its stderr, shown to the user).
    var secrets: [String] = []
  }

  /// The helper's rule (`ftp-session.ts`): after "PASS " always, elsewhere only from 8 characters
  /// on, so a short password does not turn every word it matches into "***" (Review 2026-11-11 (2),
  /// nebenbei 7).
  func redact(_ text: String) -> String {
    let secrets = state.withLock { $0.secrets }
    return secrets.filter { !$0.isEmpty }.reduce(text) { text, secret in
      let command = text.replacingOccurrences(of: "PASS \(secret)", with: "PASS ***", options: .literal)
      return JSText.length(secret) >= 8 ? command.replacingOccurrences(of: secret, with: "***", options: .literal) : command
    }
  }

  private init(process: LaunchedProcess, input: Int32, output: Int32, errors: Int32) {
    self.process = process
    self.input = input
    _ = fcntl(input, F_SETNOSIGPIPE, 1)
    let reader = Thread { [self] in read(output) }
    reader.name = "FTPSession read"
    reader.start()
    let errorReader = Thread { [self] in
      var chunk = [UInt8](repeating: 0, count: 4096)
      while true {
        let count = Darwin.read(errors, &chunk, chunk.count)
        if count < 0 && errno == EINTR { continue }
        if count <= 0 { break }
        state.withLock { $0.stderr.append(contentsOf: chunk[..<count]) }
      }
      Darwin.close(errors)
    }
    errorReader.name = "FTPSession stderr"
    errorReader.start()
  }

  /// The helper, started; nothing connected yet.
  public static func start(runtime: RuntimeLocation = .current) throws(Failure) -> FTPSession {
    let command = Command("\(runtime.nodeBin)/node", ["\(runtime.helpers)/ftp-session.cjs"], environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"])
    switch ProcessRunner.launchPiped(command) {
    case .success(let launched):
      return FTPSession(process: launched.process, input: launched.stdin, output: launched.stdout, errors: launched.stderr)
    case .failure(let failure):
      throw Failure(message: "ftp-session: \(failure)", text: "Error: ftp-session: \(failure)")
    }
  }

  private func read(_ fd: Int32) {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = Darwin.read(fd, &chunk, chunk.count)
      if count < 0 && errno == EINTR { continue }
      if count <= 0 { break }
      buffer.append(contentsOf: chunk[..<count])
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = Data(buffer[buffer.startIndex..<newline])
        buffer = Data(buffer[(newline + 1)...])
        guard let answer = try? JSJSON.parse(line), let id = answer["id"]?.numberValue.map(Int.init) else { continue }
        state.withLock { $0.waiting.removeValue(forKey: id) }?.resume(returning: answer)
      }
    }
    Darwin.close(fd)
    let stderr = redact(state.withLock { String(decoding: $0.stderr, as: UTF8.self) })
    let ended = Failure(message: "ftp-session ended: \(JS.trim(stderr))", text: "Error: ftp-session ended: \(JS.trim(stderr))")
    let waiting = state.withLock { state in
      state.ended = ended
      defer { state.waiting = [:] }
      return state.waiting
    }
    for continuation in waiting.values { continuation.resume(throwing: ended) }
  }

  @discardableResult
  func call(_ op: String, _ args: [(String, JSONValue)] = []) async throws -> JSONValue {
    let answer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, any Error>) in
      let id: Int? = state.withLock { state in
        if state.ended != nil { return nil }
        let id = state.next
        state.next += 1
        state.waiting[id] = continuation
        return id
      }
      guard let id else {
        continuation.resume(throwing: state.withLock { $0.ended } ?? Failure(message: "ftp-session ended", text: "Error: ftp-session ended"))
        return
      }
      let line = JSJSON.compact(.object(JSONObject([("id", .number(Double(id))), ("op", .string(op)), ("args", .object(JSONObject(args)))]))) + "\n"
      writes.async { [input] in
        Data(line.utf8).withUnsafeBytes { raw in
          var offset = 0
          while offset < raw.count {
            let written = Darwin.write(input, raw.baseAddress! + offset, raw.count - offset)
            if written < 0 { if errno == EINTR { continue }; return }
            offset += written
          }
        }
      }
    }
    if answer["ok"] == .bool(true) { return answer["value"] ?? .null }
    let error = answer["error"] ?? .null
    let message = redact(error["message"]?.stringValue ?? "")
    let text = redact(error["text"]?.stringValue ?? message)
    if error["ftp"] == .bool(true) { throw FTPError(code: Int(error["code"]?.numberValue ?? 0), message: message, text: text) }
    throw Failure(message: message, text: text, nodeCode: error["nodeCode"]?.stringValue)
  }

  // MARK: basic-ftp's calls

  /// `access`; `ca` adds a trusted certificate for a test's server, as Node's `ca` option.
  public func access(host: String, port: Int, user: String, password: String?, secure: Bool, ca: String? = nil) async throws {
    var args: [(String, JSONValue)] = [("host", .string(host)), ("port", .number(Double(port))), ("user", .string(user)), ("secure", .bool(secure))]
    if let password {
      args.append(("password", .string(password)))
      state.withLock { $0.secrets += [password, JS.trim(password)] }
    }
    if let ca { args.append(("ca", .string(ca))) }
    try await call("access", args)
  }

  public func pwd() async throws -> String { try await call("pwd").stringValue ?? "" }
  public func cd(_ path: String) async throws { try await call("cd", [("path", .string(path))]) }
  public func ensureDir(_ path: String) async throws { try await call("ensureDir", [("path", .string(path))]) }
  public func size(_ path: String) async throws -> Int { Int(try await call("size", [("path", .string(path))]).numberValue ?? -1) }
  public func remove(_ path: String) async throws { try await call("remove", [("path", .string(path))]) }
  public func send(_ command: String) async throws { try await call("send", [("command", .string(command))]) }
  public func upload(_ local: String, to remote: String) async throws {
    try await call("uploadFrom", [("local", .string(local)), ("remote", .string(remote))])
  }

  public func download(_ remote: String) async throws -> Data {
    Data(base64Encoded: try await call("downloadTo", [("path", .string(remote))]).stringValue ?? "") ?? Data()
  }

  public func list(_ path: String) async throws -> [Entry] {
    (try await call("list", [("path", .string(path))]).arrayValue ?? []).map { entry in
      Entry(name: entry["name"]?.stringValue ?? "", isSymbolicLink: entry["isSymbolicLink"] == .bool(true), isDirectory: entry["isDirectory"] == .bool(true),
            permissions: entry["permissions"]?.objectValue.map { p in ["user", "group", "world"].map { Int(p[$0]?.numberValue ?? 0) } })
    }
  }

  /// `client.close()`, and the helper ends.
  public func close() async {
    _ = try? await call("close")
    writes.sync { Darwin.close(input) }
    _ = await process.exit()
  }
}
