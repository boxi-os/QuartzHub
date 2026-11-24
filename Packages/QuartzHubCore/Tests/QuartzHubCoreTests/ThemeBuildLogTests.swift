import Testing
@testable import QuartzHubCore

/// `ThemeBuildLog`: the lines of a real build (Quartz 5.2.2, core 3.1.1, `theme: Minmal`,
/// 2026-11-24), with their colour codes.
struct ThemeBuildLogTests {
  static let reason = #"theme "Minmal" is not in Obsidian's community theme registry. Did you mean: "Minimal", "Mia", "Mimir"? A theme outside the registry can be used by GitHub repo ("owner/repo"), URL, or local path."#
  static let failed = [
    "\u{1B}[1m Quartz v5.2.2 \u{1B}[22m v5.2.2-9-g59f1127c-dirty",
    "",
    "\u{1B}[31m✗\u{1B}[39m @quartz-themes/core@3.1.1 was skipped: it failed to initialise: \(reason)",
    "    → source: @quartz-themes/core",
    "Emitted 433 files to `public` in 12s",
    "✗ 1 error — the build continued, but parts of the site may be missing:",
    "  [plugins] @quartz-themes/core@3.1.1 was skipped: it failed to initialise: \(reason)"
  ]

  @Test func findsTheSkippedTheme() {
    #expect(ThemeBuildLog.skippedReason(Self.failed.map { $0 + "\n" }) == Self.reason)
    // As the console holds it: chunks of the process's output, a line cut between two.
    let text = Self.failed.joined(separator: "\n") + "\n"
    let cut = text.index(text.firstRange(of: "was skipped")!.lowerBound, offsetBy: 4)
    #expect(ThemeBuildLog.skippedReason([String(text[..<cut]), String(text[cut...])]) == Self.reason)
  }

  @Test func onlyTheNewestRunCounts() {
    let fixed = (Self.failed + [" Quartz v5.2.2  v5.2.2-9", "Emitted 433 files to `public` in 12s"]).map { $0 + "\n" }
    #expect(ThemeBuildLog.skippedReason(fixed) == nil)
    #expect(ThemeBuildLog.skippedReason(fixed + Self.failed.map { $0 + "\n" }) == Self.reason)
  }

  @Test func anotherPluginIsNotTheTheme() {
    #expect(ThemeBuildLog.skippedReason(["✗ @quartz-community/explorer@1.0.0 was skipped: it failed to initialise: x"]) == nil)
    #expect(ThemeBuildLog.skippedReason(["✗ @quartz-themes/core-extra@1.0.0 was skipped: x"]) == nil)
    #expect(ThemeBuildLog.skippedReason([]) == nil)
  }
}
