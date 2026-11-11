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

  /// QuartzHub's boxes and navigations are one entry each on purpose: Quartz's finding stays,
  /// marked as intended; a real duplicate is not.
  @Test func intendedInstancesAreMarked() throws {
    let report = PluginDoctorReport.parse(String(decoding: try Posix.read(Self.fixture), as: UTF8.self))
    let boxes = report.findings(for: "quartz-layout-box")
    #expect(boxes.count == 6 && boxes.allSatisfy { $0.intended })
    let navigations = report.findings(for: "quartz-navigations")
    #expect(navigations.count == 1 && navigations.allSatisfy { $0.intended })
    let excalidraw = report.findings(for: "obsidian-plugin-excalidraw")
    #expect(excalidraw.count == 1 && excalidraw.first?.intended == false)
    #expect(report.findings(for: "crawl-links").allSatisfy { !$0.intended })
    #expect(report.intendedPlugins == ["quartz-layout-box", "quartz-navigations"])
    #expect(PluginDoctorReport.parse("✗ obsidian-plugin-excalidraw: configured twice (also as x) — both copies would be loaded").intendedPlugins.isEmpty)
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

  /// Review 2026-11-11 (2), N2: a run that never got to its first line is "could not check", and
  /// findings without a plugin are kept for the page to show.
  @Test func aRunThatDidNotCheckAndFindingsWithoutAPlugin() throws {
    #expect(PluginDoctorReport.parse(String(decoding: try Posix.read(Self.fixture), as: UTF8.self)).ran)
    let crashed = PluginDoctorReport.parse("Error: Cannot find module '/x/quartz/bootstrap-cli.mjs'\n")
    #expect(!crashed.ran && crashed.findings.isEmpty)
    #expect(!PluginDoctorReport.parse("").ran)
    let broken = PluginDoctorReport.parse("""
      Checking plugins (Quartz 5.1.0)...

      ✗ quartz.lock.json: is not valid JSON
      ✗ plugins[3]: has no source
      ⚠ crawl-links: is built into Quartz now (configuration.links); this entry is applied automatically
      """)
    #expect(broken.ran)
    #expect(broken.unassigned(names: ["crawl-links", "quartz-layout-box"]).map(\.subject) == ["quartz.lock.json", "plugins[3]"])
  }

  /// After a core update: QuartzHub's intended duplicates and warnings are no reason to say the
  /// next build may fail; any other error is.
  @Test func errorsBesidesTheIntendedOnes() {
    let twice = "✗ quartz-layout-box: configured twice (also as github:boxi-os/quartz-layout-box) — both copies would be loaded\n"
    let warning = "⚠ crawl-links: is built into Quartz now (configuration.links); this entry is applied automatically\n"
    #expect(!PluginDoctorReport.parse(twice + warning).hasErrors)
    #expect(PluginDoctorReport.parse(twice + "✗ obsidian-plugin-excalidraw: configured twice (also as x) — both copies would be loaded\n").hasErrors)
    #expect(PluginDoctorReport.parse(twice + "✗ quartz.lock.json: is not valid JSON\n").hasErrors)
  }

  /// Review 2026-11-11 (2), N6: "configured twice" is intended only while every entry of the
  /// plugin has the source doctor names; a fork beside QuartzHub's entry is a finding again.
  @Test func intendedOnlyForOneSource() throws {
    let report = PluginDoctorReport.parse(String(decoding: try Posix.read(Self.fixture), as: UTF8.self))
    func entry(_ name: String, _ source: JSONValue) -> PluginEntry {
      PluginEntry(object: JSONObject([("name", .string(name)), ("source", source)]))
    }
    let same = report.with(plugins: (0..<7).map { _ in entry("quartz-layout-box", .string("github:boxi-os/quartz-layout-box")) })
    #expect(same.findings(for: "quartz-layout-box").allSatisfy { $0.intended })
    #expect(same.intendedPlugins.contains("quartz-layout-box"))
    let forked = report.with(plugins: [entry("quartz-layout-box", .string("github:boxi-os/quartz-layout-box")),
                                       entry("quartz-layout-box", .string("github:someone/quartz-layout-box"))])
    #expect(!forked.findings(for: "quartz-layout-box").contains { $0.intended })
    #expect(!forked.intendedPlugins.contains("quartz-layout-box"))
    #expect(forked.hasErrors)
    // Quartz's spelling of an object source.
    #expect(PluginDoctorReport.formatSource(.object(JSONObject([("repo", .string("github:a/b")), ("subdir", .string("x"))]))) == "github:a/b (subdir: x)")
  }
}
