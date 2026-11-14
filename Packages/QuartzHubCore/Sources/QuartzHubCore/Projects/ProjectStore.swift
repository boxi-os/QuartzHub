import Foundation
import Synchronization

/// The list of projects, `projects.json` in QuartzHub's profile. A port of
/// `electron/main/services/projectStore.ts`, in the form QuartzControl wrote it (`ProjectEntry`).
///
/// - **One writer at a time.** Every change reads the file, changes it and writes it back. In
///   QuartzControl two of those could interleave between their awaits; here they are serialized,
///   so two folders added at once are both in the file.
/// - **The id stays when a folder moves** (`relocate`): it is what running servers, remembered tabs
///   and relay secrets are keyed by. Removing and adding again would mint a new one.
/// - **The same folder once.** `add` answers the existing entry, `relocate` refuses to make a
///   second. The comparison is Swift's `==`, which takes "ö" and "o" + combining diaeresis as one
///   string, as APFS takes them as one name; QuartzControl's `===` compared code units, so a path
///   that came back from the system in the other form was a second project. Case still counts,
///   as it did there.
public final class ProjectStore: Sendable {
  public enum Failure: Error, Equatable {
    /// `relocate` onto a folder that another entry already names.
    case alreadyRegistered

    public var message: String {
      switch self {
      case .alreadyRegistered: L10n.t("main.projectAlreadyRegistered")
      }
    }
  }

  public let profile: ProfileDirectory
  private let serial = Mutex<Void>(())

  public init(profile: ProfileDirectory = .quartzHub) {
    self.profile = profile
  }

  public func list() -> [ProjectEntry] {
    serial.withLock { _ in read().items }
  }

  public func project(id: String) -> ProjectEntry? {
    list().first { $0.id == id }
  }

  /// The entry for `path`, new or the one that names it already. `name` is the folder's name.
  @discardableResult
  public func add(path: String, now: Date = Date()) throws -> ProjectEntry {
    try change { list in
      if let existing = list.items.first(where: { $0.path == path }) { return (existing, false) }
      let entry = ProjectEntry(id: UUID().uuidString.lowercased(), path: path, addedAt: JS.isoString(now))
      list.entries.append(entry.json)
      return (entry, true)
    }
  }

  /// Notes when a project was opened last. An unknown id writes nothing.
  public func touch(id: String, now: Date = Date()) throws {
    try change { list in
      guard var entry = list.items.first(where: { $0.id == id }) else { return ((), false) }
      entry.lastOpenedAt = JS.isoString(now)
      list.upsert(entry, id: id)
      return ((), true)
    }
  }

  /// Points an entry at the folder it was moved or renamed to; nil for an unknown id.
  @discardableResult
  public func relocate(id: String, to path: String) throws -> ProjectEntry? {
    try change { list in
      guard var entry = list.items.first(where: { $0.id == id }) else { return (nil, false) }
      if list.items.contains(where: { $0.id != id && $0.path == path }) { throw Failure.alreadyRegistered }
      entry.object["path"] = .string(path)
      entry.object["name"] = .string(NodePath.basename(path))
      list.upsert(entry, id: id)
      return (entry, true)
    }
  }

  public func remove(id: String) throws {
    try change { list in
      let before = list.entries.count
      list.removeAll(id: id)
      return ((), list.entries.count != before)
    }
  }

  // MARK: - File

  private func read() -> JSONList<ProjectEntry> {
    JSONList(JSONStore.read(profile.projects, orEmpty: .array))
  }

  /// Read, change, write under one lock. `body` says whether there is anything to write; a file
  /// that would come out the same is left alone (QuartzControl's `removeProject` rewrote it for an
  /// unknown id too, with the same bytes).
  private func change<T>(_ body: (inout JSONList<ProjectEntry>) throws -> (T, Bool)) throws -> T {
    try serial.withLock { _ in
      var list = read()
      let (result, changed) = try body(&list)
      if changed {
        try Posix.mkdirs(profile.path)
        try JSONStore.write(list.json, to: profile.projects)
      }
      return result
    }
  }
}
