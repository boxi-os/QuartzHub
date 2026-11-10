import Foundation
import Testing
@testable import QuartzHubCore

/// The parts of `ExportBook` that run without WebKit: the cover's date against Node and the
/// report's sentences. The export itself is measured with `qh-check export-document` and
/// QuartzControl's `check:export -- --files`.
@Suite struct ExportBookTests {
  /// Node 24.22.2's `toLocaleDateString(lang, { day: 'numeric', month: 'long', year: 'numeric' })`
  /// (2026-11-08), at noon local time.
  @Test(arguments: [
    ("de", ["8. November 2026", "1. Januar 2026", "31. Dezember 1999"]),
    ("de-DE", ["8. November 2026", "1. Januar 2026", "31. Dezember 1999"]),
    ("en", ["November 8, 2026", "January 1, 2026", "December 31, 1999"]),
    ("en-GB", ["8 November 2026", "1 January 2026", "31 December 1999"]),
    ("fr", ["8 novembre 2026", "1 janvier 2026", "31 décembre 1999"]),
    ("ja", ["2026年11月8日", "2026年1月1日", "1999年12月31日"]),
    ("pt-BR", ["8 de novembro de 2026", "1 de janeiro de 2026", "31 de dezembro de 1999"]),
    ("nl", ["8 november 2026", "1 januari 2026", "31 december 1999"]),
    ("zh-Hans", ["2026年11月8日", "2026年1月1日", "1999年12月31日"])
  ])
  func coverDateAsNode(lang: String, expected: [String]) {
    let dates = [(2026, 11, 8), (2026, 1, 1), (1999, 12, 31)].map { y, m, d in
      Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    #expect(dates.map { ExportBook.coverDate($0, lang: lang) } == expected)
  }

  @Test func whereTheOrderCameFrom() {
    #expect(ExportBook.sourceLine("quartz-navigations", count: 3) == L10n.t("main.exportReportSource_quartz-navigations", ["count": "3"]))
    #expect(ExportBook.sourceLine("explorer", count: 3) == L10n.t("main.exportReportSource_explorer", ["count": "3"]))
    #expect(ExportBook.sourceLine("links", count: 3) == L10n.t("main.exportReportSource_links", ["count": "3"]))
    #expect(ExportBook.sourceLine("contentIndex", count: 3) == L10n.t("main.exportReportSource_contentIndex", ["count": "3"]))
    #expect(ExportBook.sourceLine("explorer", count: 3) != ExportBook.sourceLine("links", count: 3))
    // One page is "1 Seite", not "1 Seiten" (measured in the report, 2026-11-10).
    #expect(L10n.t(in: "de", "main.exportReportSource_explorer", ["count": "1"], count: 1).hasPrefix("1 Seite,"))
    #expect(L10n.t(in: "en", "main.exportReportSource_explorer", ["count": "1"], count: 1).hasPrefix("1 page,"))
    #expect(L10n.t(in: "de", "main.exportReportMissing", ["count": "1", "pages": "a/b"], count: 1)
      == "1 Seite der eigenen Reihenfolge gibt es im Build nicht mehr: a/b")
  }

  @Test func networkSentences() {
    #expect(ExportBook.networkLines(fetched: [], refused: []).isEmpty)
    let lines = ExportBook.networkLines(
      fetched: [("cdn.jsdelivr.net", 3), ("(data)", 1), ("fonts.gstatic.com", 2)],
      refused: [("script cdn.jsdelivr.net", 414), ("xhr quartzmac.borkel.net", 2), ("frame (about)", 1), ("script cdn.jsdelivr.net-x", 1)])
    #expect(lines == [
      L10n.t("main.exportReportNetwork", ["hosts": "cdn.jsdelivr.net, fonts.gstatic.com"]),
      L10n.t("main.exportReportRefused", ["count": "418", "hosts": "cdn.jsdelivr.net, quartzmac.borkel.net, cdn.jsdelivr.net-x"])
    ])
  }
}
