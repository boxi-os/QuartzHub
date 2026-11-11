import Foundation
import Synchronization

/// What QuartzHub is in the middle of, so quitting can ask first (review 2026-11-11, M1): a core
/// update holds the vault link parked and runs npm, a restore writes the project, a deploy leaves
/// the server half new. QuartzControl 1.3 asked about none of them. This process only.
public enum RunningWork {
  public enum Kind: String, Sendable, CaseIterable {
    case coreUpdate, pluginUpdate, restore, deploy
  }

  public struct Entry: Equatable, Sendable {
    public let kind: Kind
    public let project: String
  }

  static let entries = Mutex<[UUID: Entry]>([:])

  public static func during<T>(_ kind: Kind, project: String, _ body: () async throws -> T) async rethrows -> T {
    let id = UUID()
    entries.withLock { $0[id] = Entry(kind: kind, project: project) }
    defer { entries.withLock { $0[id] = nil } }
    return try await body()
  }

  public static var current: [Entry] { entries.withLock { Array($0.values) } }
}
