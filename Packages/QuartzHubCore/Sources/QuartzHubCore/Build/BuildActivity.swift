import Foundation

/// What Quartz is doing for one project right now (QuartzControl's `BuildActivity`): `build` is
/// "Jetzt bauen", `serve` the dev server's first build before it listens, `rebuild` the dev server
/// building again after a change. Held by `BuildService`, so every page sees the same.
public struct BuildActivity: Sendable, Equatable {
  public enum Kind: String, Sendable {
    case build
    case serve
    case rebuild
  }

  public enum Phase: String, Sendable {
    case preparing
    case parsing
    case emitting
  }

  public var kind: Kind
  public var startedAt: Date
  public var phase: Phase

  public init(kind: Kind, startedAt: Date, phase: Phase) {
    self.kind = kind
    self.startedAt = startedAt
    self.phase = phase
  }
}

/// Reads one project's activity off Quartz's output lines (QuartzControl's `followQuartzOutput`
/// and `setActivity`, measured in BuildActivityTrackerTests). Quartz prints them when stdout is
/// not a terminal; matched on the words, with colour codes taken out.
///
/// Two sources feed it, the one-off build's stdout and the dev server's log, and they can run at
/// once. Each moves only the activity it owns, and a build wins: a rebuild beside it stays silent
/// (QuartzControl measured a rebuild taking a running build's line and lock away for 3.3 of its 6.9
/// seconds).
///
/// Beyond QuartzControl: a line is read when it is whole. QuartzControl matched each chunk as it
/// came, so "Emitting files" cut by a read boundary moved nothing.
public struct BuildActivityTracker: Sendable {
  public enum Source: Sendable {
    case build
    case server
  }

  public private(set) var current: BuildActivity?
  private var partial: [Source: String] = [:]

  public init() {}

  /// Sets the activity; true when that changed it (and an event is due). The same value again is
  /// no change, as QuartzControl compared the JSON.
  @discardableResult
  public mutating func set(_ next: BuildActivity?) -> Bool {
    guard current.map(Self.millisecondForm) != next.map(Self.millisecondForm) else { return false }
    current = next
    return true
  }

  /// Takes a chunk of output; answers each change it made, in order (nil: cleared).
  public mutating func follow(_ text: String, from source: Source, now: Date) -> [BuildActivity?] {
    var lines = (partial[source, default: ""] + text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    partial[source] = lines.removeLast()
    return lines.flatMap { read($0, from: source, now: now) }
  }

  /// The end of a source: a last line without its newline is read now.
  public mutating func flush(_ source: Source, now: Date) -> [BuildActivity?] {
    guard let rest = partial.removeValue(forKey: source), !rest.isEmpty else { return [] }
    return read(rest, from: source, now: now)
  }

  private mutating func read(_ raw: String, from source: Source, now: Date) -> [BuildActivity?] {
    let line = raw.replacing(/\x{1b}\[[0-9;]*m/, with: "")
    var changes: [BuildActivity?] = []
    func change(_ next: BuildActivity?) { if set(next) { changes.append(next) } }

    if source == .build {
      guard var activity = current, activity.kind == .build else { return [] }
      if line.contains("Parsing input files") {
        activity.phase = .parsing
        change(activity)
      } else if line.contains("Emitting files") {
        activity.phase = .emitting
        change(activity)
      }
      return changes
    }
    if current?.kind == .build { return [] }
    // Quartz's two rebuilds: the soft one (content watcher) says "Detected change, rebuilding..."
    // and ends on "Done rebuilding"; the hard one (config, *.scss, *.ts, quartz/static) prints the
    // lines of a first build and ends on "Done processing". The soft one never says "Emitting
    // files", so "Filtered out" moves the phase too.
    if line.contains("Detected change, rebuilding") {
      change(BuildActivity(kind: .rebuild, startedAt: now, phase: .parsing))
    } else if line.contains("Detected a source code change") {
      change(BuildActivity(kind: .rebuild, startedAt: now, phase: .preparing))
    } else if line.contains("Done rebuilding in") || line.contains("Rebuild failed") {
      if current?.kind == .rebuild { change(nil) }
    } else if var activity = current {
      if line.contains("Parsing input files") {
        activity.phase = .parsing
        change(activity)
      } else if line.contains(/Filtered out [0-9]+ files/) || line.contains("Emitting files") {
        activity.phase = .emitting
        change(activity)
      } else if line.contains("Done processing") {
        change(nil)
      }
    }
    return changes
  }

  /// `toISOString` keeps milliseconds: two activities a fraction of a millisecond apart were one.
  private static func millisecondForm(_ activity: BuildActivity) -> String {
    "\(activity.kind.rawValue) \(activity.phase.rawValue) \(JS.isoString(activity.startedAt))"
  }
}
