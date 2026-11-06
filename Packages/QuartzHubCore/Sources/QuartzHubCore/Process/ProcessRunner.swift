import Darwin
import Foundation
import Synchronization

/// One child process to run and wait for. A port of `electron/main/services/runCommand.ts`; the
/// reasons below are QuartzControl's measurements (`docs/decisions/process-model-and-ipc.md`)
/// unless they say otherwise.
public struct Command: Sendable {
  /// A name looked up in `environment["PATH"]`, or a path (anything with a "/").
  public var executable: String
  /// Never through a shell. Whatever comes from a project goes behind "--" (the caller's part).
  public var arguments: [String]
  public var directory: URL?
  /// The whole environment of the child, not additions to QuartzHub's own.
  public var environment: [String: String]
  /// Written to stdin, which is then closed. Without input stdin is /dev/null, so an unexpected
  /// prompt fails at once instead of hanging (`quartz create`'s wizard, `quartz-cli.md`).
  public var input: Data?
  /// For calls that talk to another host, and for helpers. Left unset for local work and for
  /// `npm install`, which legitimately takes minutes.
  public var timeout: Duration?
  /// How long the process group gets between SIGTERM and SIGKILL after a timeout or a cancel.
  public var killGrace: Duration = .seconds(2)

  public init(
    _ executable: String,
    _ arguments: [String] = [],
    in directory: URL? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    input: Data? = nil,
    timeout: Duration? = nil
  ) {
    self.executable = executable
    self.arguments = arguments
    self.directory = directory
    self.environment = environment
    self.input = input
    self.timeout = timeout
  }

  /// The same command with some variables set on top (QuartzControl's `env` argument: a
  /// credential for `GIT_ASKPASS`, which argv would show in `ps`).
  public func adding(_ variables: [String: String]) -> Command {
    var copy = self
    copy.environment.merge(variables) { _, new in new }
    return copy
  }
}

public struct CommandResult: Sendable, Equatable {
  public enum Termination: Sendable, Equatable {
    case exited(Int32)
    case signaled(Int32)
    /// Answered at the deadline with what had arrived by then; the process group is being killed.
    case timedOut
    case cancelled
    case couldNotStart(StartFailure)
  }

  /// "Not there" and "there but refused" are two answers (conventions: "fehlt" ≠ "kaputt").
  public enum StartFailure: Error, Sendable, Equatable {
    case notFound
    case directoryMissing
    /// argv and environment over ARG_MAX. QuartzControl measured 16000 paths / 834 KB spawning
    /// and 18000 / 940 KB failing (ARG_MAX 1048576); a caller with a user-sized list batches it.
    case argumentsTooLong
    case other(Int32)
  }

  public var termination: Termination
  /// stdout and stderr in the order they arrived, for showing.
  public var output: String
  /// stdout alone, for parsing: a warning on stderr can land between the records (git with
  /// AppleDouble files in `.git/objects/pack`, measured on macOS by QuartzControl).
  public var stdout: String
  /// stderr alone: `lsof` says "nothing matched" with exit 1 and an empty stderr.
  public var stderr: String = ""

  public var success: Bool { termination == .exited(0) }

  /// `output` with a sentence for the failures that have no output of their own, as QuartzControl
  /// shows it.
  public func report(for command: Command) -> String {
    let name = "\(command.executable) \(command.arguments.first ?? "")"
    switch termination {
    case .timedOut:
      let ms = command.timeout.map { String(Int($0 / .milliseconds(1))) } ?? "?"
      return "\(output)\n\(L10n.t("main.commandTimeout", ["ms": ms, "command": name]))"
    case .couldNotStart(let reason):
      let code = switch reason {
      case .notFound: "ENOENT"
      case .directoryMissing: "ENOTDIR \(command.directory?.path ?? "")"
      case .argumentsTooLong: "E2BIG"
      case .other(let number): String(cString: strerror(number))
      }
      return "\(output)spawn \(command.executable) \(code)"
    default:
      return output
    }
  }
}

/// Starts child processes. Differences to Node's `spawn`, each a decision:
///
/// - **posix_spawn, not Foundation's `Process`.** `Process` hands arguments over decomposed (NFD):
///   "wört" arrived as `6f cc 88` instead of `c3 b6` (measured in Phase 2,
///   `decisions/phase-2-formate.md`). Here the bytes go through as the String holds them.
/// - **Its own process group** (`POSIX_SPAWN_SETPGROUP`) instead of `tree-kill`: a timeout or a
///   cancel signals the group, so a grandchild (npm's node, rsync's ssh) goes too.
/// - **No inherited descriptors** (`POSIX_SPAWN_CLOEXEC_DEFAULT`) and default signal handling with
///   an empty mask, whatever the app has set for itself.
/// - **Waits for exit and for both pipes to close** (Node's `close`, not `exit`): a child that
///   leaves a grandchild holding stdout delivers "HEAD" at exit and "HEAD\nTAIL" at close. A
///   timeout answers at once instead, because that grandchild could keep the pipe open forever.
public enum ProcessRunner {
  public enum OutputStream: Sendable, Equatable {
    case stdout
    case stderr
  }

  /// `onOutput` gets the text as it arrives, from the supervising thread, before the answer: the
  /// build's console fills while it runs. A character cut by a read boundary waits for its end
  /// (`UTF8Stream`); the pieces together are `output`.
  public static func run(_ command: Command,
                         onOutput: (@Sendable (OutputStream, String) -> Void)? = nil) async -> CommandResult {
    let wake = WakePipe()
    defer { wake.close() }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
        let thread = Thread {
          var supervisor = Supervisor(command: command, wake: wake.readEnd, onOutput: onOutput) { continuation.resume(returning: $0) }
          supervisor.run()
        }
        thread.name = "ProcessRunner \(command.executable)"
        thread.start()
      }
    } onCancel: {
      wake.signal()
    }
  }

  /// The executable `name` resolves to, the way `execvp` would look it up, but in the PATH of the
  /// child's environment rather than QuartzHub's own.
  public static func resolve(_ name: String, path: String?) -> String? {
    if name.contains("/") { return isExecutableFile(name) ? name : nil }
    for directory in (path ?? "").split(separator: ":", omittingEmptySubsequences: false) {
      let candidate = (directory.isEmpty ? "." : String(directory)) + "/" + name
      if isExecutableFile(candidate) { return candidate }
    }
    return nil
  }

  /// Starts a process that is not waited for and may outlive QuartzHub: the dev server.
  ///
  /// - stdout and stderr go to the descriptors given (files, never a pipe to the app: a server
  ///   left running at quit would die on its first write after the app was gone; QuartzControl's
  ///   `spawnServer`), or to /dev/null. The caller closes its own copies once this returns.
  /// - stdin is /dev/null; `input` and `timeout` of the command are not used.
  /// - Its own process group, as with `run`: QuartzHub's quit, a Ctrl+C in the terminal that
  ///   started it, do not reach it; `LaunchedProcess.signal` reaches all of it.
  public static func launch(_ command: Command, stdout: Int32? = nil, stderr: Int32? = nil)
    -> Result<LaunchedProcess, CommandResult.StartFailure> {
    let path: String
    switch preflight(command) {
    case .success(let found): path = found
    case .failure(let failure): return .failure(failure)
    }
    var pid: pid_t = 0
    let status = spawnChild(command, path: path, stdin: nil, stdout: stdout, stderr: stderr, pid: &pid)
    guard status == 0 else { return .failure(startFailure(status)) }
    return .success(LaunchedProcess(pid: pid))
  }

  /// "Not there" before anything is spawned: the executable in the child's PATH, the directory.
  static func preflight(_ command: Command) -> Result<String, CommandResult.StartFailure> {
    guard let path = resolve(command.executable, path: command.environment["PATH"]) else { return .failure(.notFound) }
    if let directory = command.directory {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return .failure(.directoryMissing)
      }
    }
    return .success(path)
  }

  static func startFailure(_ status: Int32) -> CommandResult.StartFailure {
    switch status {
    case ENOENT: .notFound
    case E2BIG: .argumentsTooLong
    default: .other(status)
    }
  }

  private static func isExecutableFile(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && access(path, X_OK) == 0
  }
}

/// The pipe a cancel writes into, so the supervising thread wakes up. Closed under the lock: the
/// cancel handler may run on another thread while `run` returns.
private final class WakePipe: Sendable {
  let readEnd: Int32
  private let writeEnd: Mutex<Int32>

  init() {
    var fds: [Int32] = [-1, -1]
    if pipe(&fds) == 0 {
      for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
      _ = fcntl(fds[1], F_SETFL, O_NONBLOCK)
    }
    readEnd = fds[0]
    writeEnd = Mutex(fds[1])
  }

  func signal() {
    writeEnd.withLock { fd in
      guard fd >= 0 else { return }
      var byte: UInt8 = 1
      _ = write(fd, &byte, 1)
    }
  }

  /// Closes the write end; the supervisor closes the read end when it is done with it.
  func close() {
    writeEnd.withLock { fd in
      if fd >= 0 { Darwin.close(fd) }
      fd = -1
    }
  }
}

/// Runs on its own thread: spawns, then serves the pipes and the deadlines with one kqueue until
/// the child has exited and both pipes are closed.
private struct Supervisor {
  let command: Command
  let wake: Int32
  let onOutput: (@Sendable (ProcessRunner.OutputStream, String) -> Void)?
  let finish: (CommandResult) -> Void

  private var answered = false
  private var output = Data()
  private var stdout = Data()
  private var stderr = Data()

  init(command: Command, wake: Int32, onOutput: (@Sendable (ProcessRunner.OutputStream, String) -> Void)?,
       finish: @escaping (CommandResult) -> Void) {
    self.command = command
    self.wake = wake
    self.onOutput = onOutput
    self.finish = finish
  }

  private mutating func answer(_ termination: CommandResult.Termination) {
    guard !answered else { return }
    answered = true
    finish(CommandResult(
      termination: termination,
      output: String(decoding: output, as: UTF8.self),
      stdout: String(decoding: stdout, as: UTF8.self),
      stderr: String(decoding: stderr, as: UTF8.self)
    ))
  }

  mutating func run() {
    defer { close(wake) }
    let path: String
    switch ProcessRunner.preflight(command) {
    case .success(let found): path = found
    case .failure(let failure): return answer(.couldNotStart(failure))
    }

    let out = Pipe(), err = Pipe()
    let stdin = command.input == nil ? nil : Pipe()
    defer { out.closeBoth(); err.closeBoth(); stdin?.closeBoth() }

    var pid: pid_t = 0
    let status = spawnChild(command, path: path, stdin: stdin?.read, stdout: out.write, stderr: err.write, pid: &pid)
    out.closeWrite()
    err.closeWrite()
    stdin?.closeRead()
    guard status == 0 else { return answer(.couldNotStart(ProcessRunner.startFailure(status))) }
    supervise(pid: pid, out: out, err: err, stdin: stdin)
  }

  private mutating func supervise(pid: pid_t, out: Pipe, err: Pipe, stdin: Pipe?) {
    let queue = kqueue()
    defer { close(queue) }
    var open: Set<Int32> = [out.read, err.read]
    var pendingInput = command.input ?? Data()
    var exitStatus: Int32?

    var changes = [
      watch(fd: out.read, filter: EVFILT_READ),
      watch(fd: err.read, filter: EVFILT_READ),
      watch(fd: wake, filter: EVFILT_READ)
    ]
    if let stdin {
      _ = fcntl(stdin.write, F_SETNOSIGPIPE, 1)
      _ = fcntl(stdin.write, F_SETFL, O_NONBLOCK)
      if pendingInput.isEmpty { stdin.closeWrite() } else { changes.append(watch(fd: stdin.write, filter: EVFILT_WRITE)) }
    }
    var exitWatch = Darwin.kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
                                  fflags: NOTE_EXIT, data: 0, udata: nil)
    for var change in changes { _ = kevent(queue, &change, 1, nil, 0, nil) }
    if kevent(queue, &exitWatch, 1, nil, 0, nil) != 0 {
      // ESRCH: gone before the watch was set.
      exitStatus = reap(pid)
    }

    let clock = ContinuousClock()
    var deadline = command.timeout.map { clock.now + $0 }
    var killAt: ContinuousClock.Instant?
    var stopping: CommandResult.Termination?

    let deliver = onOutput
    var pieces = (stdout: UTF8Stream(), stderr: UTF8Stream())

    // `stream` is stdout or stderr alone, `output` both in the order they came.
    func read(_ fd: Int32, into stream: inout Data, alsoStdout: Bool, output: inout Data,
              pieces: inout UTF8Stream) -> Bool {
      var buffer = [UInt8](repeating: 0, count: 65536)
      let kind: ProcessRunner.OutputStream = alsoStdout ? .stdout : .stderr
      while true {
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count > 0 {
          output.append(contentsOf: buffer[0..<count])
          stream.append(contentsOf: buffer[0..<count])
          if let deliver, case let text = pieces.feed(buffer[0..<count]), !text.isEmpty { deliver(kind, text) }
        } else if count == 0 {
          if let deliver, case let text = pieces.finish(), !text.isEmpty { deliver(kind, text) }
          return false
        } else {
          return errno == EAGAIN || errno == EINTR
        }
      }
    }
    for fd in [out.read, err.read] { _ = fcntl(fd, F_SETFL, O_NONBLOCK) }

    while exitStatus == nil || !open.isEmpty {
      let now = clock.now
      if let at = deadline, now >= at, stopping == nil {
        stopping = .timedOut
        deadline = nil
      }
      if let reason = stopping, killAt == nil {
        answer(reason)
        killpg(pid, SIGTERM)
        killAt = now + command.killGrace
      }
      if let at = killAt, now >= at {
        killpg(pid, SIGKILL)
        // Whoever left the group still holds a pipe; the answer is out, so stop listening.
        if exitStatus == nil { exitStatus = reap(pid) }
        break
      }

      let next = [deadline, killAt].compactMap { $0 }.min()
      var events = [Darwin.kevent](repeating: Darwin.kevent(), count: 8)
      let count: Int32
      if let next {
        let (seconds, attoseconds) = max(.zero, next - now).components
        var wait = timespec(tv_sec: Int(seconds), tv_nsec: Int(attoseconds / 1_000_000_000))
        count = kevent(queue, nil, 0, &events, Int32(events.count), &wait)
      } else {
        count = kevent(queue, nil, 0, &events, Int32(events.count), nil)
      }
      if count < 0 {
        if errno == EINTR { continue }
        break
      }
      for event in events.prefix(Int(count)) {
        let fd = Int32(event.ident)
        switch Int32(event.filter) {
        case EVFILT_PROC:
          exitStatus = reap(pid)
        case EVFILT_READ where fd == wake:
          if stopping == nil { stopping = .cancelled }
          var drop = event
          drop.flags = UInt16(EV_DELETE)
          _ = kevent(queue, &drop, 1, nil, 0, nil)
        case EVFILT_READ:
          let isOut = fd == out.read
          let more = isOut
            ? read(fd, into: &stdout, alsoStdout: true, output: &output, pieces: &pieces.stdout)
            : read(fd, into: &stderr, alsoStdout: false, output: &output, pieces: &pieces.stderr)
          if !more {
            open.remove(fd)
            if isOut { out.closeRead() } else { err.closeRead() }
          }
        case EVFILT_WRITE:
          guard let stdin else { break }
          let written = pendingInput.withUnsafeBytes { Darwin.write(stdin.write, $0.baseAddress, $0.count) }
          if written > 0 { pendingInput.removeFirst(written) }
          if pendingInput.isEmpty || (written < 0 && errno != EAGAIN && errno != EINTR) {
            stdin.closeWrite()
          }
        default:
          break
        }
      }
    }

    guard let exitStatus else { return answer(stopping ?? .cancelled) }
    if let stopping { return answer(stopping) }
    if exitStatus & 0x7f == 0 {
      answer(.exited((exitStatus >> 8) & 0xff))
    } else {
      answer(.signaled(exitStatus & 0x7f))
    }
  }

  private func reap(_ pid: pid_t) -> Int32 {
    var status: Int32 = 0
    while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
    return status
  }

  private func watch(fd: Int32, filter: Int32) -> Darwin.kevent {
    Darwin.kevent(ident: UInt(fd), filter: Int16(filter), flags: UInt16(EV_ADD), fflags: 0, data: 0, udata: nil)
  }
}

/// posix_spawn with the decisions of `ProcessRunner`. A descriptor that is nil is /dev/null.
private func spawnChild(_ command: Command, path: String, stdin: Int32?, stdout: Int32?, stderr: Int32?,
                        pid: inout pid_t) -> Int32 {
  var actions: posix_spawn_file_actions_t?
  var attributes: posix_spawnattr_t?
  posix_spawn_file_actions_init(&actions)
  posix_spawnattr_init(&attributes)
  defer {
    posix_spawn_file_actions_destroy(&actions)
    posix_spawnattr_destroy(&attributes)
  }
  for (fd, target, mode) in [(stdin, Int32(0), O_RDONLY), (stdout, 1, O_WRONLY), (stderr, 2, O_WRONLY)] {
    if let fd {
      posix_spawn_file_actions_adddup2(&actions, fd, target)
    } else {
      posix_spawn_file_actions_addopen(&actions, target, "/dev/null", mode, 0)
    }
  }
  if let directory = command.directory {
    posix_spawn_file_actions_addchdir_np(&actions, directory.path)
  }

  var all = sigset_t(), none = sigset_t()
  sigfillset(&all)
  sigemptyset(&none)
  posix_spawnattr_setsigdefault(&attributes, &all)
  posix_spawnattr_setsigmask(&attributes, &none)
  posix_spawnattr_setpgroup(&attributes, 0)
  posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
    | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

  // strdup of the UTF-8 bytes: no normalization on the way (see ProcessRunner).
  let argv = ([command.executable] + command.arguments).map { strdup($0) }
  let envp = command.environment.map { strdup("\($0.key)=\($0.value)") }
  defer {
    for pointer in argv { free(pointer) }
    for pointer in envp { free(pointer) }
  }
  return (argv + [nil]).withUnsafeBufferPointer { argvBuffer in
    (envp + [nil]).withUnsafeBufferPointer { envpBuffer in
      posix_spawn(&pid, path, &actions, &attributes,
                  UnsafeMutablePointer(mutating: argvBuffer.baseAddress!),
                  UnsafeMutablePointer(mutating: envpBuffer.baseAddress!))
    }
  }
}

/// A pipe whose ends are closed at most once. The descriptors are close-on-exec, so a spawn on
/// another thread never inherits them.
private final class Pipe {
  private(set) var read: Int32 = -1
  private(set) var write: Int32 = -1

  init() {
    var fds: [Int32] = [-1, -1]
    guard Darwin.pipe(&fds) == 0 else { return }
    for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
    read = fds[0]
    write = fds[1]
  }

  func closeRead() {
    if read >= 0 { close(read) }
    read = -1
  }

  func closeWrite() {
    if write >= 0 { close(write) }
    write = -1
  }

  func closeBoth() {
    closeRead()
    closeWrite()
  }
}
