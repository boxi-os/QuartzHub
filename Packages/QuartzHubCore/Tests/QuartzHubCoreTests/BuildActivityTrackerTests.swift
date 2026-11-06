import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own followQuartzOutput and setActivity: `scripts/build-activity-golden.mjs`
/// drove them through each scenario and wrote, per step, the activity and the events it emitted.
@Suite struct BuildActivityTrackerTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/build-activity/scenarios.json")

  /// Where QuartzHub answers otherwise: a line is read when it is whole, so one cut by a read
  /// boundary still counts (QuartzControl matched each chunk on its own). Per step: the activity.
  static let deviations: [String: [JSONValue]] = [
    "a-line-in-two-chunks": [show("build", "parsing", "kept"), show("build", "parsing", "kept"), show("build", "emitting", "kept")],
    "a-colour-code-in-two-chunks": [.null, show("rebuild", "parsing", "new")]
  ]

  static func show(_ kind: String, _ phase: String, _ started: String) -> JSONValue {
    .object(JSONObject([("kind", .string(kind)), ("phase", .string(phase)), ("startedAt", .string(started))]))
  }

  static let t0 = Date(timeIntervalSince1970: 1_000)

  static func show(_ activity: BuildActivity?) -> JSONValue {
    guard let activity else { return .null }
    return show(activity.kind.rawValue, activity.phase.rawValue, activity.startedAt == t0 ? "kept" : "new")
  }

  @Test func sameAsQuartzControl() throws {
    let scenarios = try #require(JSJSON.parse(Data(contentsOf: Self.fixture)).arrayValue)
    #expect(scenarios.count == 12, "scripts/build-activity-golden.mjs")
    var deviated: Set<String> = []
    for scenario in scenarios {
      let name = scenario["name"]!.stringValue!
      var tracker = BuildActivityTracker()
      for (index, step) in scenario["steps"]!.arrayValue!.enumerated() {
        var events: [BuildActivity?] = []
        if let set = step["set"] {
          let next = BuildActivity(kind: .init(rawValue: set["kind"]!.stringValue!)!, startedAt: Self.t0,
                                   phase: .init(rawValue: set["phase"]!.stringValue!)!)
          if tracker.set(next) { events.append(next) }
        } else if step["clear"] != nil {
          if tracker.set(nil) { events.append(nil) }
        } else {
          let source: BuildActivityTracker.Source = step["feed"]!.stringValue! == "build" ? .build : .server
          events = tracker.follow(step["text"]!.stringValue!, from: source, now: Date())
        }
        let expected = step["expected"]!
        if let ours = Self.deviations[name] {
          deviated.insert(name)
          #expect(Self.show(tracker.current) == ours[index], "\(name) step \(index)")
          continue
        }
        #expect(Self.show(tracker.current) == expected["activity"], "\(name) step \(index)")
        #expect(JSONValue.array(events.map(Self.show)) == expected["events"], "\(name) step \(index)")
      }
      if let ours = Self.deviations[name] {
        let theirs = scenario["steps"]!.arrayValue!.map { $0["expected"]!["activity"]! }
        #expect(theirs != ours, "\(name): QuartzControl answers the same now")
      }
    }
    #expect(deviated == Set(Self.deviations.keys))
  }

  @Test func theLastLineIsReadAtTheEnd() {
    var tracker = BuildActivityTracker()
    tracker.set(BuildActivity(kind: .rebuild, startedAt: Self.t0, phase: .emitting))
    #expect(tracker.follow("Done rebuilding in 3ms", from: .server, now: Date()).isEmpty, "held until its end")
    #expect(tracker.flush(.build, now: Date()).isEmpty, "the other source holds nothing")
    #expect(tracker.flush(.server, now: Date()) == [nil])
    #expect(tracker.current == nil)
  }
}
