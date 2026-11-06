import XCTest

/// The successor of QuartzControl's `npm run smoke`: opens every page at two window sizes and
/// checks that it renders, that the inspector is there and can be hidden. Like smoke, it asserts
/// little about content: it finds crashes and empty pages, not wrong texts.
///
/// Pinned to German (-QHLanguage de) so the run does not depend on the Mac's language.
final class SmokeTests: XCTestCase {
  static let pages = ["overview", "config", "plugins", "layout", "styles", "templates",
                      "server", "sync", "documents", "publish", "updates", "backups"]

  override func setUp() {
    continueAfterFailure = false
  }

  private func launch(size: CGSize? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    // A fresh window state every run: no restored page, inspector at its default.
    app.launchArguments += ["-QHLanguage", "de", "-ApplePersistenceIgnoreState", "YES"]
    if let size { app.launchArguments += ["-QHWindowSize", "\(Int(size.width))x\(Int(size.height))"] }
    app.launch()
    return app
  }

  /// Small: the minimum (content 900×560; the window adds the toolbar). Large: 1400×860, which
  /// fits a 14" MacBook (1470×923 usable); macOS shrinks a window that does not fit. The app is opened once per size because
  /// dragging edges did not resize the window under XCUITest (see QuartzHubApp.initialSize).
  func testEveryPageAtTwoSizes() throws {
    var widths: [CGFloat] = []
    for size in [CGSize(width: 900, height: 560), CGSize(width: 1400, height: 860)] {
      let app = launch(size: size)
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: 10))
      widths.append(window.frame.width)
      for page in Self.pages {
        let row = app.descendants(matching: .any)["sidebar.\(page)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "sidebar row \(page) missing")
        row.click()
        let content = app.descendants(matching: .any)["page.\(page)"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5), "page \(page) did not render at \(window.frame.size)")
        XCTAssertTrue(app.descendants(matching: .any)["inspector.pageContext"].firstMatch.exists,
                      "inspector context missing on \(page) at \(window.frame.size)")
      }
      app.terminate()
    }
    XCTAssertEqual(widths[0], 900, accuracy: 4, "small window is not at the minimum width")
    XCTAssertEqual(widths[1], 1400, accuracy: 4, "large window did not open at 1400: \(widths)")
  }

  func testInspectorToggles() throws {
    let app = launch()
    let toggle = app.descendants(matching: .any)["inspector.toggle"].firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    let context = app.descendants(matching: .any)["inspector.pageContext"].firstMatch
    XCTAssertTrue(context.waitForExistence(timeout: 5))

    toggle.click()
    XCTAssertTrue(context.waitForNonExistence(timeout: 5), "inspector did not hide")
    // The hidden state holds across pages: one setting per window.
    app.descendants(matching: .any)["sidebar.styles"].firstMatch.click()
    XCTAssertTrue(app.descendants(matching: .any)["page.styles"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(context.exists, "inspector came back on another page")

    toggle.click()
    XCTAssertTrue(context.waitForExistence(timeout: 5), "inspector did not come back")

    // View menu: our own item with our word, and its shortcut ⌃⌘I.
    XCTAssertTrue(app.menuItems["Inspektor ausblenden"].exists, "menu item missing or misnamed")
    app.typeKey("i", modifierFlags: [.control, .command])
    XCTAssertTrue(context.waitForNonExistence(timeout: 5), "⌃⌘I did not hide the inspector")
    XCTAssertTrue(app.menuItems["Inspektor einblenden"].exists, "menu item did not change its title")
    app.typeKey("i", modifierFlags: [.control, .command])
    XCTAssertTrue(context.waitForExistence(timeout: 5), "⌃⌘I did not show the inspector")
  }
}
