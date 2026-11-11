import Darwin
import Foundation
import Synchronization

/// The SFTP protocol, version 3 (draft-ietf-secsh-filexfer-02, what OpenSSH speaks), over the
/// standard input and output of `ssh -s <host> sftp`: QuartzHub's own client, with the system's ssh
/// as the transport (point 8b). Only what the SFTP adapter needs: realpath, stat and lstat, open with
/// a mode, fsetstat, pipelined writes, read, close, mkdir, setstat, remove.
///
/// Every request gets its own id and waits for its answer; a status from the server is a
/// `Status` with the server's code and text (2 is "no such file", 3 "permission denied", 4
/// "failure"), anything else that ends the conversation is `disconnected` with what ssh said on
/// stderr: a dead connection is never mistaken for an answer.
public final class SFTPChannel: @unchecked Sendable {
  public struct Status: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: UInt32
    public let message: String
    public var description: String { message }
  }

  public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
    case status(Status)
    /// The process ended or the stream broke; ssh's stderr.
    case disconnected(String)
    case malformed(String)

    public var description: String {
      switch self {
      case .status(let status): status.message
      case .disconnected(let text): text
      case .malformed(let text): "SFTP: \(text)"
      }
    }
  }

  public struct Attributes: Equatable, Sendable {
    public var size: UInt64?
    public var permissions: UInt32?
    public var isDirectory: Bool { (permissions ?? 0) & 0o170000 == 0o040000 }
    public var isFile: Bool { (permissions ?? 0) & 0o170000 == 0o100000 }
    public var isSymbolicLink: Bool { (permissions ?? 0) & 0o170000 == 0o120000 }
    public var mode: UInt32 { (permissions ?? 0) & 0o7777 }
  }

  enum Reply {
    case status(Status)
    case handle(Data)
    case data(Data)
    case name([String])
    case attributes(Attributes)
  }

  // Packet types.
  static let INIT: UInt8 = 1, VERSION: UInt8 = 2, OPEN: UInt8 = 3, CLOSE: UInt8 = 4, READ: UInt8 = 5, WRITE: UInt8 = 6,
             LSTAT: UInt8 = 7, FSETSTAT: UInt8 = 10, SETSTAT: UInt8 = 9, REMOVE: UInt8 = 13, MKDIR: UInt8 = 14,
             REALPATH: UInt8 = 16, STAT: UInt8 = 17
  static let STATUS: UInt8 = 101, HANDLE: UInt8 = 102, DATA: UInt8 = 103, NAME: UInt8 = 104, ATTRS: UInt8 = 105
  static let chunk = 32 * 1024
  static let window = 32

  private let process: LaunchedProcess
  private let input: Int32
  private let state = Mutex(State())
  private let writes = DispatchQueue(label: "SFTPChannel.write")
  private let stderrDone = DispatchSemaphore(value: 0)

  private struct State {
    var next: UInt32 = 1
    var waiting: [UInt32: CheckedContinuation<Reply, any Error>] = [:]
    var version: CheckedContinuation<Void, any Error>?
    var closed: Failure?
    var stderr = Data()
  }

  /// What ssh said on stderr so far.
  public var stderr: String { String(decoding: state.withLock { $0.stderr }, as: UTF8.self) }

  private init(process: LaunchedProcess, input: Int32, output: Int32, errors: Int32) {
    self.process = process
    self.input = input
    // A write into the pipe after ssh ended raises SIGPIPE, which ends the app; an error instead.
    _ = fcntl(input, F_SETNOSIGPIPE, 1)
    let reader = Thread { [self] in readReplies(output) }
    reader.name = "SFTPChannel read"
    reader.start()
    let errorReader = Thread { [self] in
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        let count = read(errors, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        if count <= 0 { break }
        state.withLock { $0.stderr.append(contentsOf: buffer[..<count]) }
      }
      Darwin.close(errors)
      stderrDone.signal()
    }
    errorReader.name = "SFTPChannel stderr"
    errorReader.start()
  }

  /// `ssh <options> -s <host> sftp` with the login's environment, and the version exchange.
  public static func open(_ login: SSHLogin, environment: ToolEnvironment) async throws(Failure) -> SFTPChannel {
    let command = environment.command("ssh", login.options + ["-o", "ClearAllForwardings=yes", "-s", "--", login.host, "sftp"]).adding(login.variables)
    let launched: (LaunchedProcess, Int32, Int32, Int32)
    switch ProcessRunner.launchPiped(command) {
    case .success(let value): launched = value
    case .failure(let failure): throw .disconnected("spawn ssh \(failure)")
    }
    let channel = SFTPChannel(process: launched.0, input: launched.1, output: launched.2, errors: launched.3)
    do {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let closed = channel.state.withLock { state -> Failure? in
          if let closed = state.closed { return closed }
          state.version = continuation
          return nil
        }
        if let closed { continuation.resume(throwing: closed); return }
        var body = Data([INIT])
        body.appendUInt32(3)
        channel.send(body)
      }
    } catch {
      await channel.close()
      throw (error as? Failure) ?? .disconnected(String(describing: error))
    }
    return channel
  }

  /// Ends the conversation and waits for ssh to exit.
  public func close() async {
    writes.sync { Darwin.close(input) }
    _ = await process.exit()
  }

  // MARK: requests

  public func realpath(_ path: String) async throws(Failure) -> String {
    guard case .name(let names) = try await request(Self.REALPATH, path: path), let first = names.first else { throw .malformed("realpath") }
    return first
  }

  public func stat(_ path: String) async throws(Failure) -> Attributes { try await attributes(Self.STAT, path) }

  public func lstat(_ path: String) async throws(Failure) -> Attributes { try await attributes(Self.LSTAT, path) }

  func attributes(_ type: UInt8, _ path: String) async throws(Failure) -> Attributes {
    guard case .attributes(let attributes) = try await request(type, path: path) else { throw .malformed("stat") }
    return attributes
  }

  public func setPermissions(_ path: String, _ mode: UInt32) async throws(Failure) {
    try expectOK(await request(Self.SETSTAT, path: path, attributes: mode))
  }

  public func mkdir(_ path: String) async throws(Failure) {
    try expectOK(await request(Self.MKDIR, path: path, attributes: nil, emptyAttributes: true))
  }

  public func remove(_ path: String) async throws(Failure) {
    try expectOK(await request(Self.REMOVE, path: path))
  }

  /// The whole file, read 32 KiB at a time.
  public func readFile(_ path: String) async throws(Failure) -> Data {
    let handle = try await openHandle(path, flags: 0x1, mode: nil)
    var content = Data()
    var offset: UInt64 = 0
    readLoop: while true {
      var body = Data()
      body.appendString(handle)
      body.appendUInt64(offset)
      body.appendUInt32(UInt32(Self.chunk))
      switch try await send(Self.READ, body) {
      case .data(let data):
        content.append(data)
        offset += UInt64(data.count)
      case .status(let status) where status.code == 1:
        break readLoop
      case .status(let status):
        _ = try? await closeHandle(handle)
        throw .status(status)
      default:
        throw .malformed("read")
      }
    }
    try await closeHandle(handle)
    return content
  }

  /// A local file to `remote` as ssh2 wrote one: opened for writing, created or truncated, with
  /// `mode` as its attributes and then set on the open handle (a server that refuses that keeps
  /// the mode it opened with, and the upload goes on, as with ssh2); the content in 32 KiB pieces,
  /// up to 32 on the way at once.
  public func writeFile(local: String, remote: String, mode: UInt32) async throws(Failure) {
    let fd = Darwin.open(local, O_RDONLY | O_CLOEXEC)
    guard fd >= 0 else { throw .malformed("open \(local): \(String(cString: strerror(errno)))") }
    defer { Darwin.close(fd) }
    let handle = try await openHandle(remote, flags: 0x2 | 0x8 | 0x10, mode: mode)
    var setMode = Data()
    setMode.appendString(handle)
    setMode.appendAttributes(mode)
    // Refused or not: ssh2 went on with the mode the file was opened with.
    guard case .status = try await send(Self.FSETSTAT, setMode) else { throw .malformed("fsetstat") }
    var offset: UInt64 = 0
    var failure: Failure?
    await withTaskGroup(of: Failure?.self) { group in
      var running = 0
      var buffer = [UInt8](repeating: 0, count: Self.chunk)
      while failure == nil {
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count < 0 {
          if errno == EINTR { continue }
          failure = .malformed("read \(local): \(String(cString: strerror(errno)))")
          break
        }
        if count == 0 { break }
        var body = Data()
        body.appendString(handle)
        body.appendUInt64(offset)
        body.appendString(Data(buffer[..<count]))
        offset += UInt64(count)
        group.addTask { [self] in
          do throws(Failure) {
            try expectOK(await send(Self.WRITE, body))
            return nil
          } catch {
            return error
          }
        }
        running += 1
        if running >= Self.window, let finished = await group.next() {
          running -= 1
          if let finished { failure = finished }
        }
      }
      for await finished in group where failure == nil { if let finished { failure = finished } }
    }
    if let failure {
      _ = try? await closeHandle(handle)
      throw failure
    }
    try await closeHandle(handle)
  }

  func openHandle(_ path: String, flags: UInt32, mode: UInt32?) async throws(Failure) -> Data {
    var body = Data()
    body.appendString(Data(path.utf8))
    body.appendUInt32(flags)
    body.appendAttributes(mode)
    switch try await send(Self.OPEN, body) {
    case .handle(let handle): return handle
    case .status(let status): throw .status(status)
    default: throw .malformed("open")
    }
  }

  func closeHandle(_ handle: Data) async throws(Failure) {
    var body = Data()
    body.appendString(handle)
    try expectOK(await send(Self.CLOSE, body))
  }

  func expectOK(_ reply: Reply) throws(Failure) {
    guard case .status(let status) = reply else { throw .malformed("status expected") }
    if status.code != 0 { throw .status(status) }
  }

  /// A request on a path; a status other than OK from a request that answers with data is thrown.
  func request(_ type: UInt8, path: String, attributes mode: UInt32? = nil, emptyAttributes: Bool = false) async throws(Failure) -> Reply {
    var body = Data()
    body.appendString(Data(path.utf8))
    if mode != nil || emptyAttributes || type == Self.SETSTAT { body.appendAttributes(mode) }
    let reply = try await send(type, body)
    if case .status(let status) = reply, status.code != 0 { throw .status(status) }
    return reply
  }

  /// Sends one request with a fresh id and waits for the reply with that id.
  func send(_ type: UInt8, _ body: Data) async throws(Failure) -> Reply {
    do {
      return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Reply, any Error>) in
        let id: UInt32? = state.withLock { state in
          if state.closed != nil { return nil }
          let id = state.next
          state.next &+= 1
          state.waiting[id] = continuation
          return id
        }
        guard let id else {
          continuation.resume(throwing: state.withLock { $0.closed } ?? .disconnected(""))
          return
        }
        var packet = Data([type])
        packet.appendUInt32(id)
        packet.append(body)
        send(packet)
      }
    } catch {
      throw (error as? Failure) ?? .disconnected(String(describing: error))
    }
  }

  /// Writes length and packet on the write queue; a broken pipe shows up as the end of the replies.
  private func send(_ packet: Data) {
    var framed = Data()
    framed.appendUInt32(UInt32(packet.count))
    framed.append(packet)
    writes.async { [input] in
      framed.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
          let written = Darwin.write(input, raw.baseAddress! + offset, raw.count - offset)
          if written < 0 {
            if errno == EINTR { continue }
            return
          }
          offset += written
        }
      }
    }
  }

  // MARK: replies

  private func readReplies(_ fd: Int32) {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    var failure: Failure?
    loop: while true {
      let count = read(fd, &chunk, chunk.count)
      if count < 0 && errno == EINTR { continue }
      if count <= 0 { break }
      buffer.append(contentsOf: chunk[..<count])
      while buffer.count >= 4 {
        let length = Int(buffer.uint32(at: buffer.startIndex))
        guard buffer.count >= 4 + length else { break }
        let packet = Data(buffer[(buffer.startIndex + 4)..<(buffer.startIndex + 4 + length)])
        buffer = Data(buffer[(buffer.startIndex + 4 + length)...])
        do {
          try dispatch(packet)
        } catch {
          failure = error as? Failure ?? .malformed(String(describing: error))
          break loop
        }
      }
    }
    Darwin.close(fd)
    // ssh writes its reason to stderr as it ends; wait for that stream's end too, briefly.
    _ = stderrDone.wait(timeout: .now() + 2)
    let reason = failure ?? .disconnected(JS.trim(stderr))
    let (waiting, version) = state.withLock { state in
      state.closed = reason
      defer { state.waiting = [:]; state.version = nil }
      return (state.waiting, state.version)
    }
    version?.resume(throwing: reason)
    for continuation in waiting.values { continuation.resume(throwing: reason) }
  }

  private func dispatch(_ packet: Data) throws {
    var reader = PacketReader(packet)
    let type = try reader.byte()
    if type == Self.VERSION {
      _ = try reader.uint32()
      state.withLock { state in
        defer { state.version = nil }
        return state.version
      }?.resume()
      return
    }
    let id = try reader.uint32()
    let reply: Reply
    switch type {
    case Self.STATUS:
      let code = try reader.uint32()
      let message = reader.isEmpty ? "" : String(decoding: try reader.string(), as: UTF8.self)
      reply = .status(Status(code: code, message: message))
    case Self.HANDLE: reply = .handle(try reader.string())
    case Self.DATA: reply = .data(try reader.string())
    case Self.NAME:
      let count = try reader.uint32()
      var names: [String] = []
      for _ in 0..<count {
        names.append(String(decoding: try reader.string(), as: UTF8.self))
        _ = try reader.string()
        _ = try reader.attributes()
      }
      reply = .name(names)
    case Self.ATTRS: reply = .attributes(try reader.attributes())
    default: throw Failure.malformed("packet type \(type)")
    }
    state.withLock { state in state.waiting.removeValue(forKey: id) }?.resume(returning: reply)
  }
}

struct PacketReader {
  var data: Data
  var offset: Int

  init(_ data: Data) {
    self.data = data
    offset = data.startIndex
  }

  var isEmpty: Bool { offset >= data.endIndex }

  mutating func byte() throws -> UInt8 {
    guard offset < data.endIndex else { throw SFTPChannel.Failure.malformed("short packet") }
    defer { offset += 1 }
    return data[offset]
  }

  mutating func uint32() throws -> UInt32 {
    guard offset + 4 <= data.endIndex else { throw SFTPChannel.Failure.malformed("short packet") }
    defer { offset += 4 }
    return data.uint32(at: offset)
  }

  mutating func uint64() throws -> UInt64 { UInt64(try uint32()) << 32 | UInt64(try uint32()) }

  mutating func string() throws -> Data {
    let length = Int(try uint32())
    guard offset + length <= data.endIndex else { throw SFTPChannel.Failure.malformed("short string") }
    defer { offset += length }
    return Data(data[offset..<(offset + length)])
  }

  mutating func attributes() throws -> SFTPChannel.Attributes {
    let flags = try uint32()
    var result = SFTPChannel.Attributes()
    if flags & 0x1 != 0 { result.size = try uint64() }
    if flags & 0x2 != 0 { _ = try uint32(); _ = try uint32() }
    if flags & 0x4 != 0 { result.permissions = try uint32() }
    if flags & 0x8 != 0 { _ = try uint32(); _ = try uint32() }
    if flags & 0x80000000 != 0 {
      for _ in 0..<(try uint32()) { _ = try string(); _ = try string() }
    }
    return result
  }
}

extension Data {
  func uint32(at index: Int) -> UInt32 {
    UInt32(self[index]) << 24 | UInt32(self[index + 1]) << 16 | UInt32(self[index + 2]) << 8 | UInt32(self[index + 3])
  }

  mutating func appendUInt32(_ value: UInt32) {
    append(contentsOf: [UInt8(value >> 24), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)])
  }

  mutating func appendUInt64(_ value: UInt64) {
    appendUInt32(UInt32(value >> 32))
    appendUInt32(UInt32(value & 0xffff_ffff))
  }

  mutating func appendString(_ value: Data) {
    appendUInt32(UInt32(value.count))
    append(value)
  }

  /// Attributes with only the permissions, or none.
  mutating func appendAttributes(_ mode: UInt32?) {
    if let mode {
      appendUInt32(0x4)
      appendUInt32(mode)
    } else {
      appendUInt32(0)
    }
  }
}
