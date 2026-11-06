import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct ProjectStoreTests {
  static func store() throws -> (ProjectStore, HostPathTests.Scratch) {
    let scratch = try HostPathTests.Scratch()
    // A profile folder that does not exist yet: the first write creates it.
    return (ProjectStore(profile: ProfileDirectory(scratch.url.appendingPathComponent("Profile"))), scratch)
  }

  static func file(_ store: ProjectStore) throws -> [JSONValue] {
    try #require(JSJSON.parse(Data(contentsOf: store.profile.projects)).arrayValue)
  }

  @Test func addWritesQuartzControlsFormAndOnlyOnce() throws {
    let (store, _) = try Self.store()
    #expect(store.list().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.profile.url.path), "reading created the profile")

    let now = Date(timeIntervalSince1970: 1_793_000_000.123)
    let first = try store.add(path: "/Users/x/Quartz/Mein Garten", now: now)
    #expect(first.name == "Mein Garten")
    #expect(first.addedAt == "2026-10-26T07:33:20.123Z")
    #expect(first.id.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/) != nil, "\(first.id)")
    #expect(try Self.file(store).first?.objectValue?.keys == ["id", "name", "path", "addedAt"])

    let again = try store.add(path: "/Users/x/Quartz/Mein Garten")
    #expect(again == first)
    #expect(try Self.file(store).count == 1)
  }

  @Test func onePathInEitherUnicodeFormButCaseCounts() throws {
    let (store, _) = try Self.store()
    let composed = try store.add(path: "/Users/x/G\u{e4}rten")
    // As NSOpenPanel or a drag from Finder may hand it over: a + combining diaeresis.
    let decomposed = try store.add(path: "/Users/x/Ga\u{308}rten")
    #expect(decomposed.id == composed.id)
    // The entry keeps the form it was added in.
    #expect(try Self.file(store).first?["path"]?.stringValue?.unicodeScalars.count == "/Users/x/G\u{e4}rten".unicodeScalars.count)
    // Counter-check: case is not folded, as in QuartzControl.
    let upper = try store.add(path: "/Users/x/G\u{c4}RTEN")
    #expect(upper.id != composed.id)
    #expect(store.list().count == 2)
  }

  @Test func relocateKeepsTheIdAndWhatItDoesNotKnow() throws {
    let (store, _) = try Self.store()
    // A file as QuartzControl leaves it, with a key a later version might add and a stray entry.
    try FileManager.default.createDirectory(at: store.profile.url, withIntermediateDirectories: true)
    try Data("""
    [
      {
        "id": "6f1c1b54-0a51-4b8e-9d3a-6f2f6a1d2c11",
        "name": "alt",
        "path": "/p/alt",
        "addedAt": "2026-01-01T00:00:00.000Z",
        "lastOpenedAt": "2026-02-01T00:00:00.000Z",
        "pinned": true
      },
      null,
      {
        "id": "0d3e8a3c-1f42-4e5b-8a77-2b9d3c4e5f60",
        "name": "andere",
        "path": "/p/andere",
        "addedAt": "2026-01-02T00:00:00.000Z"
      }
    ]
    """.utf8).write(to: store.profile.projects)

    let moved = try #require(try store.relocate(id: "6f1c1b54-0a51-4b8e-9d3a-6f2f6a1d2c11", to: "/q/neu"))
    #expect(moved.name == "neu" && moved.path == "/q/neu")
    let entries = try Self.file(store)
    #expect(entries.count == 3)
    #expect(entries[0].objectValue?.keys == ["id", "name", "path", "addedAt", "lastOpenedAt", "pinned"])
    #expect(entries[0]["pinned"] == .bool(true))
    #expect(entries[1] == .null)

    #expect(throws: ProjectStore.Failure.alreadyRegistered) {
      try store.relocate(id: "6f1c1b54-0a51-4b8e-9d3a-6f2f6a1d2c11", to: "/p/andere")
    }
    #expect(store.project(id: "6f1c1b54-0a51-4b8e-9d3a-6f2f6a1d2c11")?.path == "/q/neu", "a refused move changed the entry")
    // Onto its own path again is not a collision.
    #expect(try store.relocate(id: "6f1c1b54-0a51-4b8e-9d3a-6f2f6a1d2c11", to: "/q/neu")?.path == "/q/neu")
    #expect(try store.relocate(id: "00000000-0000-4000-8000-000000000000", to: "/x") == nil)
  }

  @Test func touchAndRemove() throws {
    let (store, _) = try Self.store()
    try store.touch(id: "nobody")
    #expect(!FileManager.default.fileExists(atPath: store.profile.projects.path), "an unknown id wrote the file")

    let a = try store.add(path: "/p/a"), b = try store.add(path: "/p/b")
    try store.touch(id: b.id, now: Date(timeIntervalSince1970: 0))
    #expect(store.project(id: b.id)?.lastOpenedAt == "1970-01-01T00:00:00.000Z")
    #expect(try Self.file(store)[1].objectValue?.keys.last == "lastOpenedAt")

    try store.remove(id: a.id)
    #expect(store.list().map(\.id) == [b.id])
  }

  @Test func concurrentChangesAllLand() async throws {
    let (store, _) = try Self.store()
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<64 {
        group.addTask { _ = try? store.add(path: "/p/\(index)") }
      }
    }
    #expect(store.list().count == 64)
  }

  @Test func anUnreadableFileIsMovedAsideNotOverwritten() throws {
    let (store, _) = try Self.store()
    try FileManager.default.createDirectory(at: store.profile.url, withIntermediateDirectories: true)
    try Data("[{\"id\": ".utf8).write(to: store.profile.projects)
    #expect(store.list().isEmpty)
    let names = try FileManager.default.contentsOfDirectory(atPath: store.profile.url.path)
    #expect(names.contains { $0.hasPrefix("projects.json.corrupt-") }, "\(names)")
  }
}
