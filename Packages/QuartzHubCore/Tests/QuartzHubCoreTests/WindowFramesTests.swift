import Foundation
import Testing
@testable import QuartzHubCore

/// Test and measurement launches keep the user's window frames aside and the user's next start puts
/// them back (review 2026-11-11, nebenbei 11).
@Suite struct WindowFramesTests {
  @Test func aTestLaunchLeavesTheUsersFramesForTheNextStart() throws {
    let suite = "qh-window-frames-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let mine = ["NSWindow Frame Projekte": "245 300 980 640 0 0 1710 1069 ", "NSWindow Frame ProjectWindow-AppWindow-1": "10 20 1400 860 0 0 1710 1069 "]
    for (key, value) in mine { defaults.set(value, forKey: key) }
    func frames() -> [String: String] {
      defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("NSWindow Frame ") }.compactMapValues { $0 as? String }
    }

    WindowFrames.prepare(.pinnedSize, defaults: defaults)
    #expect(frames().isEmpty, "the size asked for wins")
    defaults.set("0 0 1500 950 0 0 1710 1069 ", forKey: "NSWindow Frame Projekte")
    WindowFrames.prepare(.scratch, defaults: defaults)
    #expect(frames() == ["NSWindow Frame Projekte": "0 0 1500 950 0 0 1710 1069 "], "a scratch launch keeps what it finds")
    WindowFrames.prepare(.pinnedSize, defaults: defaults)
    defaults.set("1 1 1200 780 0 0 1710 1069 ", forKey: "NSWindow Frame Projekte")

    WindowFrames.prepare(.own, defaults: defaults)
    #expect(frames() == mine)
    // The user's start after that changes nothing more.
    defaults.set("5 5 900 600 0 0 1710 1069 ", forKey: "NSWindow Frame Projekte")
    WindowFrames.prepare(.own, defaults: defaults)
    #expect(frames()["NSWindow Frame Projekte"] == "5 5 900 600 0 0 1710 1069 ")
  }

  @Test func theLaunchIsReadFromTheArguments() {
    #expect(WindowFrames.launch(arguments: ["app"]) == .own)
    #expect(WindowFrames.launch(arguments: ["app", "-QHProfileDir", "/tmp/p"]) == .scratch)
    #expect(WindowFrames.launch(arguments: ["app", "-QHProfileDir", "/tmp/p", "-QHWindowSize", "1500x950"]) == .pinnedSize)
  }
}
