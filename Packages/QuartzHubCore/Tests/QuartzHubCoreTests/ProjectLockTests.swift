import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

@Suite struct ProjectLockTests {
  final class Journal: Sendable {
    private let entries = Mutex<[String]>([])
    func note(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
  }

  /// Fails instead of hanging when a lock waits for itself: the body runs in a task of its own,
  /// which is left behind at the deadline (a task group would wait for it).
  static func within<T: Sendable>(_ limit: Duration, _ body: @escaping @Sendable () async -> T) async -> T? {
    let result = Mutex<T?>(nil)
    let work = Task { let value = await body(); result.withLock { $0 = value } }
    let clock = ContinuousClock(), end = clock.now + limit
    while clock.now < end {
      if let value = result.withLock({ $0 }) { return value }
      try? await Task.sleep(for: .milliseconds(10))
    }
    _ = work
    return nil
  }

  @Test func oneProjectRunsOneAtATimeInOrder() async throws {
    let lock = ProjectLock(name: "test")
    let journal = Journal()
    let scratch = try HostPathTests.Scratch()
    let project = scratch.url.path
    await withTaskGroup(of: Void.self) { group in
      for name in ["A", "B", "C"] {
        group.addTask {
          await lock.run(project) {
            journal.note("\(name) start")
            try? await Task.sleep(for: .milliseconds(40))
            journal.note("\(name) end")
          }
        }
        // The order of arrival is the order of the queue.
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
    #expect(journal.all == ["A start", "A end", "B start", "B end", "C start", "C end"])
    #expect(lock.queuedProjects == 0)
  }

  @Test func twoSpellingsOfOneFolderAreOneKey() async throws {
    let scratch = try HostPathTests.Scratch()
    let real = try scratch.dir("project")
    let link = scratch.url.appendingPathComponent("link").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
    #expect(ProjectLock.key(link) == ProjectLock.key(real + "/."))
    // /var is a symlink to /private/var: the temporary folder has two spellings by itself.
    #expect(ProjectLock.key(real) == ProjectLock.key(real.replacingOccurrences(of: "/private/var/", with: "/var/")))

    let lock = ProjectLock(name: "test")
    let journal = Journal()
    async let first: Void = lock.run(real) {
      journal.note("real start")
      try? await Task.sleep(for: .milliseconds(60))
      journal.note("real end")
    }
    try await Task.sleep(for: .milliseconds(15))
    await lock.run(link) { journal.note("link") }
    await first
    #expect(journal.all == ["real start", "real end", "link"])
  }

  @Test func otherProjectsDoNotWait() async throws {
    let lock = ProjectLock(name: "test")
    let journal = Journal()
    let scratch = try HostPathTests.Scratch()
    let one = try scratch.dir("one"), two = try scratch.dir("two")
    async let first: Void = lock.run(one) {
      journal.note("one start")
      try? await Task.sleep(for: .milliseconds(80))
      journal.note("one end")
    }
    try await Task.sleep(for: .milliseconds(15))
    await lock.run(two) { journal.note("two") }
    await first
    #expect(journal.all == ["one start", "two", "one end"])
  }

  @Test func reentrantForTheSameProjectAndLock() async throws {
    let lock = ProjectLock(name: "test")
    let scratch = try HostPathTests.Scratch()
    let project = scratch.url.path
    let answer = await Self.within(.seconds(2)) {
      await lock.run(project) {
        await lock.run(project + "/.") { 42 }
      }
    }
    #expect(answer == 42, "nested run waited for itself")
    // Another lock is another queue: holding styles does not count as holding config. A folder
    // of its own, so a hung first half cannot block this one.
    let project2 = try scratch.dir("second")
    let other = ProjectLock(name: "other")
    let journal = Journal()
    async let outside: Void = other.run(project2) {
      journal.note("other start")
      try? await Task.sleep(for: .milliseconds(60))
      journal.note("other end")
    }
    try await Task.sleep(for: .milliseconds(15))
    await lock.run(project2) { await other.run(project2) { journal.note("nested other") } }
    await outside
    #expect(journal.all == ["other start", "other end", "nested other"])
  }

  @Test func aFailureDoesNotBreakTheQueue() async throws {
    struct Boom: Error {}
    let lock = ProjectLock(name: "test")
    let scratch = try HostPathTests.Scratch()
    let project = scratch.url.path
    let failing = Task {
      try await lock.run(project) {
        try await Task.sleep(for: .milliseconds(30))
        throw Boom()
      }
    }
    try await Task.sleep(for: .milliseconds(10))
    let after = await lock.run(project) { "ran" }
    #expect(after == "ran")
    await #expect(throws: Boom.self) { try await failing.value }
    #expect(lock.queuedProjects == 0)
  }

  @Test func detachedWorkWaitsInTheQueue() async throws {
    // What QuartzControl measured with a timer, here with a detached task: it is not a holder.
    let lock = ProjectLock(name: "test")
    let journal = Journal()
    let scratch = try HostPathTests.Scratch()
    let project = scratch.url.path
    var late: Task<Void, Never>?
    await lock.run(project) {
      journal.note("A start")
      late = Task.detached {
        await lock.run(project) { journal.note("late") }
      }
      try? await Task.sleep(for: .milliseconds(30))
      journal.note("A end")
    }
    await late?.value
    #expect(journal.all == ["A start", "A end", "late"])
  }
}
