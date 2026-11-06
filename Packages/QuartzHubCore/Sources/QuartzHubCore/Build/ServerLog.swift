import Darwin
import Foundation
import Synchronization

/// A dev server's output goes into two files under `.quartz-gui/logs/` that QuartzHub tails, never
/// down a pipe it holds (QuartzControl's `openServerLog`, `pruneServerLogs`, `tailFile`). A pipe's
/// read end dies with the app, and the server's next write after "Weiterlaufen lassen" kills it on
/// the broken pipe (QuartzControl measured: alive and answering right after the app was gone, both
/// processes gone after one note was saved).
///
/// One pair per run, named after the process that writes it: a fixed name was truncated by the
/// next start under a server left running, and the two wrote past each other (QuartzControl
/// measured 112 bytes, 90 of them NUL, the old server's lines in the new console).
struct ServerLogFiles {
  let directory: URL
  private(set) var stdout: URL
  private(set) var stderr: URL
  let stdoutFD: Int32
  let stderrFD: Int32

  static func names(_ owner: String) -> (stdout: String, stderr: String) {
    ("dev-server-\(owner).out.log", "dev-server-\(owner).err.log")
  }

  /// Opens this run's two files under a temporary name (the pid does not exist yet), after removing
  /// the files of runs that are over. Throws when the project cannot be written to (read-only
  /// volume, a `.quartz-gui` of another user): the server then starts without a console and says so.
  static func open(project: URL, now: Date = Date()) throws -> ServerLogFiles {
    let directory = try QuartzGuiDirectory(project: project).create("logs")
    prune(directory)
    let names = names("tmp-\(Int(now.timeIntervalSince1970 * 1000))")
    let stdout = directory.appendingPathComponent(names.stdout), stderr = directory.appendingPathComponent(names.stderr)
    let out = Darwin.open(stdout.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
    guard out >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let err = Darwin.open(stderr.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
    guard err >= 0 else {
      let code = errno
      close(out)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    return ServerLogFiles(directory: directory, stdout: stdout, stderr: stderr, stdoutFD: out, stderrFD: err)
  }

  /// QuartzHub's copies, once the child has its own.
  func closeOurs() {
    close(stdoutFD)
    close(stderrFD)
  }

  /// The final names, once the pid is known. Renaming a file two processes hold open changes
  /// neither descriptor; the tails start afterwards, on whatever name the files ended up with.
  mutating func adopt(_ pid: Int32) {
    let wanted = Self.names(String(pid))
    let target = (directory.appendingPathComponent(wanted.stdout), directory.appendingPathComponent(wanted.stderr))
    if rename(stdout.path, target.0.path) == 0 { stdout = target.0 }
    if rename(stderr.path, target.1.path) == 0 { stderr = target.1 }
  }

  /// Removes the files of runs that are over, and only those: a pid in a name is asked as every
  /// pid read back is asked (alive and still a quartz server), so the files of a server left
  /// running survive. The fixed pair of old and a `tmp-` pair whose spawn never got far go.
  static func prune(_ directory: URL, isRunning: (Int32) -> Bool = ServerScan.isQuartzServer) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
    for name in names {
      guard let match = name.wholeMatch(of: /dev-server(?:-(tmp-[0-9]+|[0-9]+))?\.(?:out|err)\.log/) else { continue }
      if let owner = match.1, !owner.hasPrefix("tmp-"), let pid = Int32(owner), isRunning(pid) { continue }
      unlink(directory.appendingPathComponent(name).path)
    }
  }
}

/// Reads what a file grows by, every 200 ms, with a descriptor of its own (the writer is another
/// process; a shared one would move one offset for both). A read boundary inside a character
/// waits for its end (`UTF8Stream`). `stop` reads once more and is safe to call twice.
final class LogTail: Sendable {
  private struct State {
    var fd: Int32 = -1
    var position: off_t = 0
    var decoder = UTF8Stream()
    var stopped = false
  }

  private let path: String
  private let deliver: @Sendable (String) -> Void
  private let state = Mutex(State())

  init(path: String, deliver: @escaping @Sendable (String) -> Void) {
    self.path = path
    self.deliver = deliver
    Task.detached { [self] in
      while !state.withLock({ $0.stopped }) {
        pump()
        try? await Task.sleep(for: .milliseconds(200))
      }
    }
  }

  func stop() {
    let first = state.withLock { state -> Bool in
      defer { state.stopped = true }
      return !state.stopped
    }
    guard first else { return }
    pump(final: true)
    state.withLock { state in
      if state.fd >= 0 { close(state.fd) }
      state.fd = -1
    }
  }

  /// Delivers under the lock, so the tick and `stop` cannot hand two pieces over out of order (the
  /// receiver only queues them).
  private func pump(final: Bool = false) {
    state.withLock { state in
      if state.stopped && !final { return }
      if state.fd < 0 { state.fd = open(path, O_RDONLY | O_CLOEXEC) }
      // Not there yet: the next tick asks again.
      guard state.fd >= 0 else { return }
      var text = ""
      var buffer = [UInt8](repeating: 0, count: 64 * 1024)
      while true {
        let count = pread(state.fd, &buffer, buffer.count, state.position)
        guard count > 0 else { break }
        state.position += off_t(count)
        text += state.decoder.feed(buffer[0..<count])
      }
      if final { text += state.decoder.finish() }
      if !text.isEmpty { deliver(text) }
    }
  }
}
