import Foundation
import Testing
@testable import QuartzHubCore

/// The export window in WebKit, through `qh-check export-window`: WebKit needs the main run loop
/// turning, which `swift test` does not (measured 2026-11-06 and 2026-11-07), so the check runs in
/// the executable that `swift test` builds alongside. It opens a window at alpha 0 on the screen;
/// only with `QH_WEBKIT_TESTS=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["QH_WEBKIT_TESTS"] == "1", "QH_WEBKIT_TESTS=1"))
struct ExportWindowTests {
  static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path

  @Test func holdsToTheRuleInWebKit() async throws {
    let tool = "\(Self.package)/.build/debug/qh-check"
    try #require(Posix.exists(tool), "qh-check not built")
    let result = await ProcessRunner.run(Command(tool, ["export-window", "--root", "\(Self.package)/../.."], timeout: .seconds(120)))
    #expect(result.termination == .exited(0), "\(result.stdout)\(result.stderr)")
    #expect(JSText.includes(result.stdout, "export-window: alles wie die Regel"))
  }
}
