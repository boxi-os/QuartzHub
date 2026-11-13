import Foundation
import Testing
@testable import QuartzHubCore

/// Where the app's handbook links go (`Handbook`, QuartzControl's handbookPages.ts).
@Suite struct HandbookTests {
  /// A tab with a line of its own goes there, another tab to its page's, an unknown place to the
  /// start; the language picks the translated path.
  @Test func placesResolveByTabPageAndLanguage() {
    #expect(Handbook.url(for: "plugins/forms", language: "de").absoluteString == "https://boxi-os.github.io/QuartzHub/4-einrichtung/09-formulare")
    #expect(Handbook.url(for: "plugins/forms", language: "en").absoluteString == "https://boxi-os.github.io/QuartzHub/en/4-setup/09-forms")
    #expect(Handbook.url(for: "plugins/installed", language: "de").absoluteString.hasSuffix("/4-einrichtung/05-plugins"))
    #expect(Handbook.url(for: "nirgends", language: "en").absoluteString == "https://boxi-os.github.io/QuartzHub/en/")
    #expect(Handbook.url(for: nil, language: "de").absoluteString == "https://boxi-os.github.io/QuartzHub/")
    #expect(Handbook.place(page: "styles", tab: "customCss") == "styles/customCss")
    #expect(Handbook.place(page: "server", tab: nil) == "server")
  }

  /// Every page of the project window has a page in the handbook of its own, not the start.
  @Test func everyProjectPageHasAChapter() {
    for page in ["overview", "config", "plugins", "layout", "styles", "templates", "server", "sync", "documents", "publish", "updates", "backups"] {
      #expect(Handbook.page(for: page) != Handbook.start, "\(page)")
    }
    #expect(Handbook.files.contains("index.md") && Handbook.files.contains("en/index.md"))
  }
}
