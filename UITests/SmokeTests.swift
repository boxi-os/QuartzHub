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

  /// A throwaway profile directory per run, so no test reads or writes a real profile.
  private func scratchDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qh-ui-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func launch(size: CGSize? = nil, profile: URL? = nil, migrationSource: String = "", open project: URL? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    // A fresh window state every run: no restored page, inspector at its default. The takeover
    // from QuartzControl is off unless a test hands it a source profile.
    // No update check: the overview would ask GitHub on every run (DEBUG only, OverviewModel).
    app.launchArguments += ["-QHLanguage", "de", "-ApplePersistenceIgnoreState", "YES",
                            "-QHMigrationSource", migrationSource, "-QHNoUpdateCheck", "YES"]
    if let profile { app.launchArguments += ["-QHProfileDir", profile.path] }
    if let project { app.launchArguments += ["-QHOpenProject", project.path] }
    if let size { app.launchArguments += ["-QHWindowSize", "\(Int(size.width))x\(Int(size.height))"] }
    app.launch()
    return app
  }

  static let projectName = "smoke-projekt"

  /// A scratch profile and a folder with a quartz.config.yaml in it: enough for the list to call it
  /// a Quartz project and open its window. Nothing of a real profile is read or written.
  private func scratchProject() throws -> (profile: URL, project: URL) {
    let root = try scratchDirectory("project")
    let profile = root.appendingPathComponent("profil")
    let project = root.appendingPathComponent(Self.projectName)
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("configuration:\n  pageTitle: Smoke\n".utf8).write(to: project.appendingPathComponent("quartz.config.yaml"))
    return (profile, project)
  }

  /// The window with the project's sidebar. Not by title: that names the page, not the project
  /// (decisions/ui-ueberarbeitung.md, Titel).
  private func projectWindow(_ app: XCUIApplication) -> XCUIElement {
    app.windows.containing(NSPredicate(format: "identifier == %@", "sidebar")).firstMatch
  }

  /// Small: the minimum (content 900×560; the window adds the toolbar). Large: 1400×860, which
  /// fits a 14" MacBook (1470×923 usable); macOS shrinks a window that does not fit. The app is opened once per size because
  /// dragging edges did not resize the window under XCUITest (see QuartzHubApp.initialSize).
  func testEveryPageAtTwoSizes() throws {
    var widths: [CGFloat] = []
    let (profile, project) = try scratchProject()
    for size in [CGSize(width: 900, height: 560), CGSize(width: 1400, height: 860)] {
      let app = launch(size: size, profile: profile, open: project)
      let window = projectWindow(app)
      XCTAssertTrue(window.waitForExistence(timeout: 10))
      widths.append(window.frame.width)
      for page in Self.pages {
        let row = window.descendants(matching: .any)["sidebar.\(page)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "sidebar row \(page) missing")
        row.click()
        let content = window.descendants(matching: .any)["page.\(page)"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5), "page \(page) did not render at \(window.frame.size)")
        XCTAssertTrue(window.descendants(matching: .any)["inspector.pageContext"].firstMatch.exists,
                      "inspector context missing on \(page) at \(window.frame.size)")
      }
      app.terminate()
    }
    XCTAssertEqual(widths[0], 900, accuracy: 4, "small window is not at the minimum width")
    XCTAssertEqual(widths[1], 1400, accuracy: 4, "large window did not open at 1400: \(widths)")
  }

  /// The overview of the scratch project: no package.json and no base URL, so the band names both,
  /// "Alles ok" is not there, and a section's link moves the window to its page.
  func testOverviewNamesWhatIsMissingAndLinksToItsPage() throws {
    let (profile, project) = try scratchProject()
    let app = launch(profile: profile, open: project)
    let window = projectWindow(app)
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    let any = window.descendants(matching: .any)
    XCTAssertTrue(any["overview.issue.baseurl"].firstMatch.waitForExistence(timeout: 10), "no line for the missing base URL")
    XCTAssertTrue(any["overview.issue.dependencies-unreadable"].firstMatch.exists, "no line for the unreadable package.json")
    XCTAssertFalse(any["overview.allGood"].firstMatch.exists, "\"Alles ok\" beside the band")
    let link = any["overview.link.plugins"].firstMatch
    link.click()
    XCTAssertTrue(any["page.plugins"].firstMatch.waitForExistence(timeout: 5), "the link did not open Plugins")
    // Title and subtitle, as the window gives them to accessibility: "Plugins – Installiert".
    XCTAssertTrue(window.title.hasPrefix("Plugins"), "the title does not name the page: \(window.title)")
    XCTAssertFalse(window.title.contains(Self.projectName), "the title still names the project: \(window.title)")
    // The way back is the history's: the toolbar's back button, then forward again.
    window.buttons["history.back"].firstMatch.click()
    XCTAssertTrue(any["page.overview"].firstMatch.waitForExistence(timeout: 5), "Zurück did not lead to the overview")
    window.buttons["history.forward"].firstMatch.click()
    XCTAssertTrue(any["page.plugins"].firstMatch.waitForExistence(timeout: 5), "Vorwärts did not lead to Plugins")
  }

  /// Vorschau & Build of the scratch project: both consoles there and empty, the scan of this Mac
  /// answers, and an output folder the schema refuses is said and not written, a good one is.
  func testServerPageScansAndRefusesABadOutputFolder() throws {
    let (profile, project) = try scratchProject()
    let app = launch(profile: profile, open: project)
    let window = projectWindow(app)
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    let any = window.descendants(matching: .any)
    any["overview.link.server"].firstMatch.click()
    XCTAssertTrue(any["page.server"].firstMatch.waitForExistence(timeout: 5), "Vorschau & Build did not open")
    XCTAssertTrue(any["server.log.server"].firstMatch.exists, "no server console")
    XCTAssertTrue(any["server.log.build"].firstMatch.exists, "no build console")
    let scan = any["server.discovery.status"].firstMatch
    // A static text's words are its value, not its label (AXValue; the label is empty).
    let answered = expectation(for: NSPredicate(format: "value != %@ AND value != ''", "Suche laufende Server…"), evaluatedWith: scan)
    wait(for: [answered], timeout: 15)

    let prefs = project.appendingPathComponent(".quartz-gui/project-prefs.json")
    let field = any["server.outputDir"].firstMatch
    field.click()
    field.typeText("../x\r")
    XCTAssertTrue(any["server.outputDir.error"].firstMatch.waitForExistence(timeout: 5), "\"../x\" was not refused")
    XCTAssertFalse(FileManager.default.fileExists(atPath: prefs.path), "a refused folder was written")

    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("dist\r")
    let written = expectation(for: NSPredicate { _, _ in
      (try? String(contentsOf: prefs, encoding: .utf8))?.contains("\"dist\"") == true
    }, evaluatedWith: nil)
    wait(for: [written], timeout: 5)
    XCTAssertFalse(any["server.outputDir.error"].firstMatch.exists, "the error stayed after a good folder")
  }

  func testInspectorToggles() throws {
    let (profile, project) = try scratchProject()
    let app = launch(profile: profile, open: project)
    XCTAssertTrue(projectWindow(app).waitForExistence(timeout: 10), "project window did not open")
    // Within the project window: the Projects window has an inspector and a toggle of its own.
    let window = projectWindow(app)
    window.click()
    let toggle = window.descendants(matching: .any)["inspector.toggle"].firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    let context = window.descendants(matching: .any)["inspector.pageContext"].firstMatch
    XCTAssertTrue(context.waitForExistence(timeout: 5))

    toggle.click()
    XCTAssertTrue(context.waitForNonExistence(timeout: 5), "inspector did not hide")
    // The hidden state holds across pages: one setting per window.
    window.descendants(matching: .any)["sidebar.styles"].firstMatch.click()
    XCTAssertTrue(window.descendants(matching: .any)["page.styles"].firstMatch.waitForExistence(timeout: 5))
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

  /// The Projects window: a project in the list opens its own window by double click, and removing
  /// it asks first, then leaves its open window saying so.
  func testProjectsWindowOpensAndRemoves() throws {
    let (profile, project) = try scratchProject()
    let app = launch(profile: profile, open: project)
    XCTAssertTrue(projectWindow(app).waitForExistence(timeout: 10), "project window did not open")
    projectWindow(app).buttons[XCUIIdentifierCloseWindow].click()
    XCTAssertTrue(projectWindow(app).waitForNonExistence(timeout: 5))

    let row = app.descendants(matching: .any)["projects.row.\(Self.projectName)"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "row missing in the Projects window")
    row.doubleClick()
    XCTAssertTrue(projectWindow(app).waitForExistence(timeout: 5), "double click did not open the project")
    XCTAssertTrue(app.descendants(matching: .any)["sidebar.overview"].firstMatch.exists)

    // Back to the list, remove: the safe answer first, then the removal.
    app.typeKey("0", modifierFlags: [.command, .shift])
    row.click()
    let remove = app.descendants(matching: .any)["projects.remove"].firstMatch
    XCTAssertTrue(remove.waitForExistence(timeout: 5), "inspector shows no remove action")
    remove.click()
    // In the windows, not app.buttons: that also finds the Touch Bar's copy of the button.
    let confirm = app.windows.buttons["Aus der Liste entfernen"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no question before removing")
    XCTAssertTrue(app.windows.buttons["Abbrechen"].firstMatch.exists)
    confirm.click()
    XCTAssertTrue(row.waitForNonExistence(timeout: 5), "row still listed")
    XCTAssertTrue(app.descendants(matching: .any)["projects.gettingStarted"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["project.notInList"].firstMatch.waitForExistence(timeout: 5),
                  "the open project window did not notice")
    // The folder stays.
    XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent("quartz.config.yaml").path))
    let list = try String(contentsOf: profile.appendingPathComponent("projects.json"), encoding: .utf8)
    XCTAssertEqual(list.trimmingCharacters(in: .whitespacesAndNewlines), "[]")
  }

  /// File ▸ Neues Projekt… (⌘N) opens the wizard on the Projects window; a name with "/" is refused
  /// before anything runs, and Abbrechen closes it. Nothing is created: that would clone from GitHub.
  func testCreateWizardRefusesABadNameAndCancels() throws {
    let (profile, _) = try scratchProject()
    let app = launch(profile: profile)
    XCTAssertTrue(app.windows["Projekte"].waitForExistence(timeout: 10))
    app.typeKey("n", modifierFlags: .command)
    let name = app.descendants(matching: .any)["create.name"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5), "⌘N did not open the wizard")
    let confirm = app.windows.buttons["create.confirm"].firstMatch
    XCTAssertFalse(confirm.isEnabled, "create enabled without a name")
    name.click()
    name.typeText("a/b")
    XCTAssertTrue(app.staticTexts["Der Name darf kein „/“ enthalten und nicht „.“ oder „..“ sein."].waitForExistence(timeout: 3))
    XCTAssertFalse(confirm.isEnabled, "create enabled with a bad name")
    app.windows.buttons["Abbrechen"].firstMatch.click()
    XCTAssertTrue(name.waitForNonExistence(timeout: 5), "Abbrechen did not close the wizard")
  }

  /// Duplizieren from the inspector: the name is suggested with "-2", a "/" is refused, Abbrechen
  /// closes. Nothing is copied: the copy runs npm install.
  func testDuplicateWizardSuggestsANameAndCancels() throws {
    let (profile, project) = try scratchProject()
    let app = launch(profile: profile, open: project)
    XCTAssertTrue(projectWindow(app).waitForExistence(timeout: 10))
    app.typeKey("0", modifierFlags: [.command, .shift])
    let row = app.descendants(matching: .any)["projects.row.\(Self.projectName)"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.click()
    app.descendants(matching: .any)["projects.duplicate"].firstMatch.click()
    let name = app.descendants(matching: .any)["duplicate.name"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5), "the duplicate wizard did not open")
    XCTAssertEqual(name.value as? String, "\(Self.projectName)-2")
    name.click()
    name.typeKey("a", modifierFlags: .command)
    name.typeText("x/y")
    XCTAssertTrue(app.staticTexts["Der Name darf kein „/“ enthalten und nicht „.“ oder „..“ sein."].waitForExistence(timeout: 3))
    XCTAssertFalse(app.windows.buttons["duplicate.confirm"].firstMatch.isEnabled)
    app.windows.buttons["Abbrechen"].firstMatch.click()
    XCTAssertTrue(name.waitForNonExistence(timeout: 5))
  }

  /// QuartzHub ▸ Einstellungen (⌘,): a choice is written at once and only that field; a folder
  /// that is not a full path is refused with QuartzControl's sentence.
  func testSettingsWriteAtOnce() throws {
    let (profile, _) = try scratchProject()
    try Data(#"{"fremd":true}"#.utf8).write(to: profile.appendingPathComponent("settings.json"))
    let app = launch(profile: profile)
    XCTAssertTrue(app.windows["Projekte"].waitForExistence(timeout: 10))
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["Allgemein"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5), "⌘, did not open the settings")
    settings.radioButtons["Weiterlaufen lassen"].click()
    let written = try String(contentsOf: profile.appendingPathComponent("settings.json"), encoding: .utf8)
    XCTAssertEqual(written, "{\n  \"fremd\": true,\n  \"serversOnQuit\": \"keep\"\n}")
    let field = settings.textFields["settings.directory"]
    field.click()
    field.typeText("Dokumente\r")
    XCTAssertTrue(settings.staticTexts["Das ist kein vollständiger Pfad. Er muss mit „/“ oder „~/“ beginnen, oder du wählst den Ordner aus."]
      .waitForExistence(timeout: 3), "a relative folder was not refused")
  }

  /// The takeover against a QuartzControl profile made here (two projects, no secrets, so no
  /// Keychain prompt): offered, carried out, and not offered again once QuartzHub has a list.
  func testMigrationIsOfferedOnceAndWritesTheProjectList() throws {
    let source = try scratchDirectory("qc")
    let own = try scratchDirectory("qh")
    let projects = """
      [
        {
          "id": "6b0a7c9e-0000-4000-8000-000000000001",
          "name": "eins",
          "path": "/nowhere/eins",
          "addedAt": "2026-11-01T00:00:00.000Z"
        },
        {
          "id": "6b0a7c9e-0000-4000-8000-000000000002",
          "name": "zwei",
          "path": "\(source.path)",
          "addedAt": "2026-11-02T00:00:00.000Z"
        }
      ]
      """
    try Data(projects.utf8).write(to: source.appendingPathComponent("projects.json"))

    let app = launch(profile: own, migrationSource: source.path)
    let sheet = app.descendants(matching: .any)["migration"].firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: 10), "takeover not offered")
    XCTAssertTrue(app.staticTexts["2 Projekte"].exists, "project count missing")
    XCTAssertTrue(app.staticTexts["1 davon wurde nicht mehr gefunden"].exists, "missing folder not named")
    app.buttons["migration.confirm"].click()
    XCTAssertTrue(app.buttons["migration.done"].waitForExistence(timeout: 10), "takeover did not finish")
    app.buttons["migration.done"].click()
    XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    app.terminate()

    let written = try String(contentsOf: own.appendingPathComponent("projects.json"), encoding: .utf8)
    XCTAssertEqual(written, projects, "project list not taken over byte for byte")

    let again = launch(profile: own, migrationSource: source.path)
    XCTAssertTrue(again.windows.firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(again.descendants(matching: .any)["migration"].firstMatch.waitForExistence(timeout: 3),
                   "takeover offered a second time")
  }

  /// Konfiguration owns quartz.config.yaml: an edit says it is unsaved, leaving through the sidebar
  /// asks and "Abbrechen" stays, ⌘S writes the file, and with nothing unsaved leaving asks nothing.
  func testConfigAsksBeforeLeavingAndSavesWithCommandS() throws {
    let (profile, project) = try scratchProject()
    let app = launch(profile: profile, open: project)
    let window = projectWindow(app)
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    let any = window.descendants(matching: .any)
    any["sidebar.config"].firstMatch.click()
    XCTAssertTrue(any["page.config"].firstMatch.waitForExistence(timeout: 5), "Konfiguration did not open")

    // By type, not `any`: each section is a Form of its own, a scroll view in the tree, and `any`
    // once matched that scroll view, below the window, instead of the field (1 run in 4).
    let field = window.textFields["config.pageTitle"].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), "no title field")
    // Speichern says whether there is something to save: off before the edit, on after it.
    let save = window.buttons["config.save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 5), "no Speichern")
    XCTAssertFalse(save.isEnabled, "Speichern is on with nothing to save")
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("Neu")
    let unsaved = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save)
    wait(for: [unsaved], timeout: 5)

    any["sidebar.plugins"].firstMatch.click()
    let cancel = window.sheets.buttons["Abbrechen"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), "leaving with an edit did not ask")
    XCTAssertTrue(window.sheets.buttons["Änderungen verwerfen"].firstMatch.exists, "no way to discard")
    cancel.click()
    XCTAssertTrue(any["page.config"].firstMatch.waitForExistence(timeout: 5), "\"Abbrechen\" left the page")
    XCTAssertFalse(any["page.plugins"].firstMatch.exists, "\"Abbrechen\" opened Plugins")

    let config = project.appendingPathComponent("quartz.config.yaml")
    window.typeKey("s", modifierFlags: .command)
    let written = expectation(for: NSPredicate { _, _ in
      (try? String(contentsOf: config, encoding: .utf8))?.contains("pageTitle: Neu") == true
    }, evaluatedWith: nil)
    wait(for: [written], timeout: 10)
    let saved = expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: save)
    wait(for: [saved], timeout: 5)

    any["sidebar.plugins"].firstMatch.click()
    XCTAssertTrue(any["page.plugins"].firstMatch.waitForExistence(timeout: 5), "a saved page did not let go")
    XCTAssertFalse(window.sheets.firstMatch.exists, "a saved page asked")

    // The second tab: the scratch project ships no locale files, and the tab says so.
    any["sidebar.config"].firstMatch.click()
    let tabs = any["config.tabs"].firstMatch
    XCTAssertTrue(tabs.waitForExistence(timeout: 5), "no tab switcher")
    tabs.radioButtons["Übersetzungen"].firstMatch.click()
    XCTAssertTrue(any["localization.none"].firstMatch.waitForExistence(timeout: 10), "Übersetzungen did not say there are no locale files")
  }


  /// Plugins ▸ Installiert writes at once: Anordnen ▸ Nach unten renumbers the sequence in the
  /// file, the inspector's switch writes `enabled`, and the count says what the list holds.
  func testPluginsReorderAndSwitchWriteTheConfig() throws {
    let (profile, project) = try scratchProject()
    let config = project.appendingPathComponent("quartz.config.yaml")
    try Data("""
      configuration:
        pageTitle: Smoke
      plugins:
        - source: github:quartz-community/alpha
          enabled: true
          order: 10
        - source: github:quartz-community/beta
          enabled: true
          order: 20
        - source: github:quartz-community/gamma
          enabled: false
          layout:
            position: left
            priority: 10

      """.utf8).write(to: config)
    let app = launch(profile: profile, open: project)
    let window = projectWindow(app)
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    let any = window.descendants(matching: .any)
    any["sidebar.plugins"].firstMatch.click()
    let count = any["plugins.count"].firstMatch
    XCTAssertTrue(count.waitForExistence(timeout: 10), "Plugins did not open")
    XCTAssertTrue(count.waitForLabelOrValue("2 von 3 aktiv", timeout: 5), "count: \(count.label) \(String(describing: count.value))")

    any["plugins.row.alpha"].firstMatch.click()
    XCTAssertTrue(any["plugins.inspector.name"].firstMatch.waitForExistence(timeout: 5), "the inspector shows no plugin")
    window.typeKey(.downArrow, modifierFlags: [.option, .command])
    let read = { (try? String(contentsOf: config, encoding: .utf8)) ?? "" }
    let moved = expectation(for: NSPredicate { _, _ in
      let text = read()
      guard let alpha = text.range(of: "alpha"), let beta = text.range(of: "beta") else { return false }
      return text[alpha.upperBound...].hasPrefix("\n    enabled: true\n    order: 20") && text[beta.upperBound...].hasPrefix("\n    enabled: true\n    order: 10")
    }, evaluatedWith: nil)
    wait(for: [moved], timeout: 10)

    any["plugins.inspector.enabled"].firstMatch.click()
    let off = expectation(for: NSPredicate { _, _ in
      let text = read()
      guard let alpha = text.range(of: "alpha") else { return false }
      return text[alpha.upperBound...].hasPrefix("\n    enabled: false")
    }, evaluatedWith: nil)
    wait(for: [off], timeout: 10)
    XCTAssertTrue(count.waitForLabelOrValue("1 von 3 aktiv", timeout: 5), "the count did not follow the switch")
  }
}

private extension XCUIElement {
  /// A static text's words arrive as its value or its label, depending on the SwiftUI view.
  func waitForLabelOrValue(_ text: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if label == text || (value as? String) == text { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    return false
  }
}
