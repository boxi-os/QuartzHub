import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own runningServersStore.ts: `scripts/running-servers-golden.mjs` ran
/// each scenario there and wrote, per step, the answer, the file's text and how many files were
/// moved aside.
@Suite struct RunningServersStoreTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/running-servers/scenarios.json")
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  func store(_ name: String) -> RunningServersStore {
    RunningServersStore(profile: ProfileDirectory("\(scratch.path)/\(name)/Profil \u{DC}"))
  }

  static func quarantined(_ store: RunningServersStore) -> Int {
    ((try? FileManager.default.contentsOfDirectory(atPath: store.profile.path)) ?? []).filter { $0.contains(".corrupt-") }.count
  }

  @Test func sameAsQuartzControl() throws {
    let scenarios = try #require(JSJSON.parse(Data(contentsOf: Self.fixture)).arrayValue)
    #expect(scenarios.count == 7, "scripts/running-servers-golden.mjs")
    for scenario in scenarios {
      let name = scenario["name"]!.stringValue!
      let store = store(name)
      if let text = scenario["file"]?.stringValue {
        try Posix.mkdirs(store.profile.path)
        try Posix.write(store.profile.runningServers, Data(text.utf8))
      }
      for (index, step) in scenario["steps"]!.arrayValue!.enumerated() {
        let id = step["id"]?.stringValue ?? ""
        var answer = JSONValue.null
        switch step["op"]!.stringValue! {
        case "record": try store.record(projectId: id, server: TrackedServer(object: step["server"]!.objectValue!))
        case "remove": try store.remove(projectId: id)
        default: answer = try store.takeAll().json
        }
        let expected = step["expected"]!
        let file = (try? Posix.read(store.profile.runningServers)).map { String(decoding: $0, as: UTF8.self) }
        #expect(answer == expected["answer"], "\(name) step \(index)")
        #expect(file.map(JSONValue.string) ?? .null == expected["file"], "\(name) step \(index)")
        #expect(Double(Self.quarantined(store)) == expected["quarantined"]?.numberValue, "\(name) step \(index)")
      }
    }
  }

  /// The profile folder the first write makes keeps the composed name.
  @Test func theProfileFolderKeepsItsBytes() throws {
    let store = store("bytes")
    try store.record(projectId: "p", server: TrackedServer(object: JSONObject([("pid", .number(1)), ("port", .number(8080))])))
    #expect(Posix.entries("\(scratch.path)/bytes")?.map { Array($0.name.utf8) } == [Array("Profil \u{DC}".utf8)])
  }

  @Test func theNewEntryIsInQuartzControlsOrder() {
    #expect(TrackedServer(pid: 4711, port: 8080, startedAt: "t").object.keys == ["pid", "port", "startedAt"])
    #expect(TrackedServer(pid: 4711, port: 8080, startedAt: "t").pid == 4711)
  }

  @Test func removeWithAPidTakesOnlyThatProcesssEntry() throws {
    let store = store("pid")
    try store.record(projectId: "a", server: TrackedServer(pid: 200, port: 8080, startedAt: "second start"))
    // The first server of the project ends after the second has started.
    try store.remove(projectId: "a", pid: 100)
    #expect(try store.takeAll()["a"]?.pid == 200)
    try store.record(projectId: "a", server: TrackedServer(pid: 200, port: 8080, startedAt: "t"))
    try store.remove(projectId: "a", pid: 200)
    #expect(try store.takeAll().keys.isEmpty)
  }

  @Test func changesAtOnceAreAllKept() throws {
    let store = store("parallel")
    DispatchQueue.concurrentPerform(iterations: 64) { index in
      try? store.record(projectId: "p\(index)", server: TrackedServer(pid: Int32(1000 + index), port: 8080 + index, startedAt: "t"))
    }
    #expect(try store.takeAll().keys.count == 64)
  }
}
