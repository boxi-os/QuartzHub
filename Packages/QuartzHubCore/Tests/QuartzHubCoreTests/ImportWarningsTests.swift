import Foundation
import Testing
@testable import QuartzHubCore

/// QuartzControl's `ImportOutcome.tsx`: grouped by kind, one line per case for kinds whose
/// sentence names the detail (at most six, the sixth with the rest counted), the unknown kind with
/// its name.
@Suite struct ImportWarningsTests {
  @Test func groupsCountsAndListsTheDetails() {
    let lines = ImportWarnings.lines([
      "pluginSkipped:a", "frameFailed:Eins kaputt", "pluginSkipped:b", "pluginSkipped:c",
      "partFailed:fonts:Platte voll", "neuArt:x", "neuArt", "layoutSkipped",
    ], language: "de")
    #expect(lines == [
      "3 vorhandene Plugins blieben unverändert. — a, b, c",
      "Frame konnte nicht angelegt werden: Eins kaputt",
      // Everything after the first colon is the detail, colons included.
      "Ein Baustein ist fehlgeschlagen: fonts:Platte voll",
      "2× neuArt — x, ",
      "Layout und Breakpoints blieben unverändert.",
    ])
  }

  @Test func atMostSixCasesOfADetailKind() {
    let warnings = (1...9).map { "translationFailed:t\($0)" } + (1...8).map { "staticSkipped:s\($0)" }
    let lines = ImportWarnings.lines(warnings, language: "de")
    #expect(lines.count == 7)
    #expect(lines[0] == "Text nicht schreibbar: t1")
    #expect(lines[5] == "Text nicht schreibbar: t6 und 3 weitere Fälle")
    #expect(lines[6] == "8 gleichnamige Dateien unter quartz/static blieben unverändert. — s1, s2, s3, s4, s5, s6 …")
  }

  @Test func noWarningsNoLines() {
    #expect(ImportWarnings.lines([]).isEmpty)
  }
}
