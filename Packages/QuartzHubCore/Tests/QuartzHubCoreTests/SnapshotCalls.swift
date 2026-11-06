import Foundation
import Synchronization
@testable import QuartzHubCore

/// A stand-in for `SnapshotStore.take` that notes kind and label, and can look at the project at
/// the moment it is asked (to show the snapshot came before the write).
final class SnapshotCalls: Sendable {
  private let calls = Mutex<[[String]]>([])
  var all: [[String]] { calls.withLock { $0 } }

  func take(_ look: @escaping @Sendable (URL) throws -> Void = { _ in }) -> SnapshotStore.Take {
    { [self] project, kind, label in
      try look(project)
      self.calls.withLock { $0.append([kind, label]) }
      return "snap-\(kind)"
    }
  }
}
