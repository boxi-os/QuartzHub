import Foundation
import Synchronization

/// One piece of a project's output, as QuartzControl's `LogLine` (`shared/ipc-contract.ts`). `text`
/// is a chunk as it arrived, not necessarily one line.
public struct LogLine: Sendable, Equatable {
  public enum Stream: String, Sendable {
    case stdout
    case stderr
    /// A sentence of QuartzHub's own while the run goes on (frames refreshed before a build, a
    /// server whose output cannot be tailed). Not `stderr`: red in front of an exit-0 build says
    /// "failed". `stderr` stays for what really failed, such as a spawn that never started.
    case warn
  }

  public var projectId: String
  public var stream: Stream
  public var text: String
  public var timestamp: Date

  public init(projectId: String, stream: Stream, text: String, timestamp: Date = Date()) {
    self.projectId = projectId
    self.stream = stream
    self.text = text
    self.timestamp = timestamp
  }
}

/// What a project's server and builds said, kept while QuartzHub runs. A port of
/// `electron/main/services/logBuffer.ts`: in memory only, not a log file (those are under
/// `.quartz-gui/logs/` and belong to `buildService`), capped per project and per kind so one busy
/// project's build cannot push another's server log out.
public final class LogBuffer: Sendable {
  public enum Kind: String, Sendable {
    case server
    case build
  }

  public struct History: Sendable, Equatable {
    public var server: [LogLine] = []
    public var build: [LogLine] = []

    subscript(kind: Kind) -> [LogLine] {
      get { kind == .server ? server : build }
      set { if kind == .server { server = newValue } else { build = newValue } }
    }
  }

  /// The cap of QuartzControl's renderer store and buffer.
  public static let maxLines = 999

  private let buffers = Mutex<[String: History]>([:])

  public init() {}

  public func record(_ kind: Kind, _ line: LogLine) {
    buffers.withLock { buffers in
      var lines = buffers[line.projectId, default: History()][kind]
      lines.append(line)
      if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
      buffers[line.projectId, default: History()][kind] = lines
    }
  }

  /// A copy; the buffer goes on growing.
  public func history(_ projectId: String) -> History {
    buffers.withLock { $0[projectId] ?? History() }
  }

  public func clear(_ projectId: String, _ kind: Kind) {
    buffers.withLock { $0[projectId, default: History()][kind] = [] }
  }
}
