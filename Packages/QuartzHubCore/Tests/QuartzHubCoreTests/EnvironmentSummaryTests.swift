import Foundation
import Testing
@testable import QuartzHubCore

/// The start page's line about the tools (`toolSummary` and `versionNumber` in QuartzControl).
@Suite struct EnvironmentSummaryTests {
  func report(_ tools: [EnvironmentReport.Tool]) -> EnvironmentReport {
    EnvironmentReport(pathSource: .inherited, addedPaths: [], tools: tools, hostNodeVersion: nil, rsyncAvailable: true)
  }

  @Test func groupedByOrigin() {
    let all = report([
      .init(name: "node", source: .embedded, path: "/a/node", version: "v24.22.2"),
      .init(name: "npm", source: .embedded, path: "/a/npm", version: "11.19.1"),
      .init(name: "git", source: .host, path: "/usr/bin/git", version: "git version 2.50.1 (Apple Git-155)"),
    ])
    #expect(all.toolSummary(language: "de") == "in QuartzHub: node 24.22.2, npm 11.19.1 · vom System: git 2.50.1")
    #expect(all.broken.isEmpty && all.ok)
    let bundledGit = report([.init(name: "git", source: .bundled, path: "/b/git", version: "git version 2.53.0")])
    #expect(bundledGit.toolSummary(language: "en").hasSuffix(": git 2.53.0"))
  }

  @Test func versionNumbers() {
    #expect(EnvironmentReport.versionNumber("v24.22.2") == "24.22.2")
    #expect(EnvironmentReport.versionNumber("git version 2.53.0 (Apple Git-155)") == "2.53.0")
    #expect(EnvironmentReport.versionNumber("kein Wert") == nil)
    #expect(EnvironmentReport.versionNumber(nil) == nil)
  }
}
