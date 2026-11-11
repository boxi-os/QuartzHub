import Foundation
import Testing
@testable import QuartzHubCore

/// `PluginDoctorReport` against what `quartz plugin doctor` of Quartz 5.1.0 printed for a copy of
/// gui-test right after the core update (2026-11-11, `Fixtures/doctor/gui-test-5.1.0.txt`).
@Suite struct PluginDoctorReportTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/doctor/gui-test-5.1.0.txt").path

  @Test func itReadsQuartzsLines() throws {
    let report = PluginDoctorReport.parse(String(decoding: try Posix.read(Self.fixture), as: UTF8.self))
    // 13 errors and 5 warnings, as its last line says.
    #expect(report.findings.filter { $0.severity == .error }.count == 13)
    #expect(report.findings.filter { $0.severity == .warning }.count == 5)
    let crawl = report.findings(for: "crawl-links")
    #expect(crawl.count == 1)
    #expect(crawl.first?.severity == .warning)
    #expect(crawl.first?.hint?.hasPrefix("Run 'npx quartz plugin doctor --fix'") == true)
    // An npm package is labelled by its whole name, in the message itself.
    let breaks = report.findings(for: "hard-line-breaks")
    #expect(breaks.count == 1 && breaks.first?.subject == nil && breaks.first?.message.contains("is deprecated") == true)
    #expect(report.findings(for: "frame-focus").first?.message == "has no built entry point (dist/ missing)")
  }

  /// QuartzHub's boxes and navigations are one entry each on purpose; a real duplicate still shows.
  @Test func intendedInstancesAreNoFinding() throws {
    let report = PluginDoctorReport.parse(String(decoding: try Posix.read(Self.fixture), as: UTF8.self))
    #expect(report.findings(for: "quartz-layout-box").isEmpty)
    #expect(report.findings(for: "quartz-navigations").isEmpty)
    #expect(report.findings(for: "obsidian-plugin-excalidraw").count == 1)
  }

  @Test func versionsAndColoursDoNotHideThePlugin() {
    let report = PluginDoctorReport.parse("""
      \u{1b}[31m✗ graph@1.2.0 requires Quartz >=5.2.0, but this is Quartz 5.1.0.\u{1b}[39m
      \u{1b}[90m    → Update Quartz (npx quartz upgrade), or use an older version of graph that supports 5.1.0.\u{1b}[39m
      ⚠ @someone/graph-extra@0.1.0 is deprecated: use graph
      ℹ explorer: package.json has no `quartz` manifest
      """)
    #expect(report.findings(for: "graph").map(\.severity) == [.error])
    #expect(report.findings(for: "graph").first?.hint?.hasPrefix("Update Quartz") == true)
    #expect(report.findings(for: "graph-extra").count == 1)
    #expect(report.findings(for: "explorer").isEmpty)
    #expect(report.findings(for: "").isEmpty)
  }
}
