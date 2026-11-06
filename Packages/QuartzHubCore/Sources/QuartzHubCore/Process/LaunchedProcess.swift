import Darwin
import Foundation
import Synchronization

/// A process `ProcessRunner.launch` started and nobody waits for in a call: the dev server. It is
/// reaped by a thread of its own as soon as it ends, so it never lingers as a zombie, and its
/// answer is kept for whoever asks later.
///
/// Signals go to the process group, as `ProcessRunner.run`'s timeout does: npx's node and
/// Quartz's workers are in it. The group id stays the process's even after the process itself is
/// reaped and a worker lives on; the system does not hand out a number as a new process id while a
/// group of that number exists. Only a process that took the number after the whole group was gone
/// *and* made itself a group leader could be hit, which takes a wrap of the pid space in between.
/// A descendant that left the group (setsid) is out of reach; Quartz does not do that.
public final class LaunchedProcess: Sendable {
  public let pid: pid_t

  private struct State {
    var status: Int32?
    var waiters: [CheckedContinuation<CommandResult.Termination, Never>] = []
  }

  private let state = Mutex(State())

  init(pid: pid_t) {
    self.pid = pid
    let thread = Thread { [self] in
      var status: Int32 = 0
      while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
      let waiters = state.withLock { state in
        state.status = status
        defer { state.waiters = [] }
        return state.waiters
      }
      let termination = Self.termination(status)
      for waiter in waiters { waiter.resume(returning: termination) }
    }
    thread.name = "LaunchedProcess \(pid)"
    thread.start()
  }

  /// How it ended, once it has; nil while it runs.
  public var termination: CommandResult.Termination? {
    state.withLock { $0.status.map(Self.termination) }
  }

  /// Waits for the end.
  public func exit() async -> CommandResult.Termination {
    await withCheckedContinuation { continuation in
      let status = state.withLock { state -> Int32? in
        if state.status == nil { state.waiters.append(continuation) }
        return state.status
      }
      if let status { continuation.resume(returning: Self.termination(status)) }
    }
  }

  /// Sends `number` to the whole group; false when there is no group any more.
  @discardableResult
  public func signal(_ number: Int32) -> Bool {
    killpg(pid, number) == 0
  }

  /// Whether anything of the group still runs (the process itself, or what it started).
  public var groupIsAlive: Bool { killpg(pid, 0) == 0 }

  /// SIGTERM to the group, SIGKILL to what is left of it after `grace`; answers once the process
  /// itself has ended. Waits for the whole group, not only the process: npx can end on SIGTERM
  /// while its node still holds the port.
  public func stop(grace: Duration = .seconds(2)) async -> CommandResult.Termination {
    signal(SIGTERM)
    let clock = ContinuousClock()
    let deadline = clock.now + grace
    while clock.now < deadline, termination == nil || groupIsAlive {
      try? await Task.sleep(for: .milliseconds(25))
    }
    if groupIsAlive { signal(SIGKILL) }
    return await exit()
  }

  static func termination(_ status: Int32) -> CommandResult.Termination {
    status & 0x7f == 0 ? .exited((status >> 8) & 0xff) : .signaled(status & 0x7f)
  }
}
