import XCTest

/// NSAlert gives its buttons identifiers of its own (`action-button-1` …, measured on macOS 27),
/// so they are found by title.
///
/// The questions about dev servers, in the running app with a real Quartz server: Cmd+Q while one
/// runs asks, "Abbrechen" keeps the app, "Weiterlaufen lassen" quits and leaves the server; the
/// next start asks about it as an orphan, and "Beenden" stops it.
///
/// Needs a Quartz project the test may run a server in, outside the runner's sandbox:
/// `TEST_RUNNER_QH_SERVER_PROJECT=<copy of gui-test> xcodebuild … test -only-testing:QuartzHubUITests/ServerQuestionsTests`.
final class ServerQuestionsTests: XCTestCase {
  /// The server to kill if the test ends early.
  final class LeftOver: @unchecked Sendable { var pid: Int32? }

  override func setUp() { continueAfterFailure = false }

  private func launch(profile: URL, startServerFor project: String?) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-QHLanguage", "de", "-ApplePersistenceIgnoreState", "YES", "-QHMigrationSource", "",
                            "-QHProfileDir", profile.path]
    if let project { app.launchArguments += ["-QHStartServerFor", project] }
    app.launch()
    return app
  }

  private func recorded(_ profile: URL) -> (pid: Int32, port: Int)? {
    guard let data = try? Data(contentsOf: profile.appendingPathComponent("running-servers.json")),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
          let entry = object.values.first, let pid = entry["pid"] as? Int, let port = entry["port"] as? Int else { return nil }
    return (Int32(pid), port)
  }

  private func answers(_ port: Int) -> Bool {
    let done = expectation(description: "probe")
    var ok = false
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
    request.timeoutInterval = 2
    URLSession.shared.dataTask(with: request) { _, response, _ in
      ok = (response as? HTTPURLResponse) != nil
      done.fulfill()
    }.resume()
    wait(for: [done], timeout: 4)
    return ok
  }

  private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if condition() { return true }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return condition()
  }

  func testQuitQuestionThenOrphanQuestion() throws {
    guard let project = ProcessInfo.processInfo.environment["QH_SERVER_PROJECT"] else {
      throw XCTSkip("TEST_RUNNER_QH_SERVER_PROJECT not set")
    }
    let profile = FileManager.default.temporaryDirectory.appendingPathComponent("qh-ui-servers-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    let left = LeftOver()
    addTeardownBlock {
      if let pid = left.pid { killpg(pid, SIGKILL) }
      try? FileManager.default.removeItem(at: profile)
    }

    // 1. A server runs; Cmd+Q asks.
    var app = launch(profile: profile, startServerFor: project)
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(waitUntil(20) { recorded(profile) != nil }, "no server recorded")
    let server = try XCTUnwrap(recorded(profile))
    left.pid = server.pid
    XCTAssertTrue(waitUntil(90) { answers(server.port) }, "the server never answered on \(server.port)")

    app.typeKey("q", modifierFlags: .command)
    let cancel = app.dialogs.buttons["Abbrechen"]
    if !cancel.waitForExistence(timeout: 10) {
      print("QH-MEASURE state after Cmd+Q: \(app.state.rawValue)")
      print("QH-MEASURE tree: \(app.debugDescription)")
    }
    XCTAssertTrue(cancel.exists, "no question at quit")
    XCTAssertTrue(app.dialogs.staticTexts["Es laufen noch Dev-Server."].exists)
    XCTAssertTrue(app.dialogs.buttons["Weiterlaufen lassen"].exists && app.dialogs.buttons["Server beenden"].exists)
    XCTAssertTrue(app.dialogs.checkBoxes["Nicht mehr fragen"].exists)
    // Escape: measured, not assumed.
    app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    let escapeCancels = waitUntil(2) { !cancel.exists }
    print("QH-MEASURE escape closes the quit question: \(escapeCancels)")
    if !escapeCancels { cancel.click() }
    XCTAssertTrue(waitUntil(5) { !cancel.exists })
    XCTAssertEqual(app.state, .runningForeground, "cancel quit the app")

    // 2. "Weiterlaufen lassen": the app goes, the server stays.
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.dialogs.buttons["Weiterlaufen lassen"].waitForExistence(timeout: 10))
    app.dialogs.buttons["Weiterlaufen lassen"].click()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "the app did not quit")
    XCTAssertEqual(kill(server.pid, 0), 0, "the server went with the app")
    XCTAssertTrue(answers(server.port))

    // 3. The next start asks about it; "Beenden" stops it.
    app = launch(profile: profile, startServerFor: nil)
    let quit = app.dialogs.buttons["Beenden"]
    XCTAssertTrue(quit.waitForExistence(timeout: 15), "no orphan question")
    XCTAssertTrue(app.dialogs.staticTexts["Laufende Server gefunden"].exists)
    XCTAssertTrue(app.dialogs.buttons["Weiterlaufen lassen"].exists)
    quit.click()
    XCTAssertTrue(waitUntil(10) { kill(server.pid, 0) != 0 }, "the orphan survived Beenden")
    XCTAssertTrue(waitUntil(10) { !answers(server.port) })
    left.pid = nil
    XCTAssertNil(recorded(profile))

    // 4. Asked once: the next start is quiet, and Cmd+Q quits without a question.
    app.terminate()
    app = launch(profile: profile, startServerFor: nil)
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(app.dialogs.buttons["Beenden"].waitForExistence(timeout: 3))
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
  }
}
