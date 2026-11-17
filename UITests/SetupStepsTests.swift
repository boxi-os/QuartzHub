import XCTest

/// The inspector in steps (docs/plan-assistenten.md) at the running app, in all four editors: the
/// first run of a new entry ends with that entry, a cancel takes back exactly what ➕ and the steps
/// wrote, and a setup takes one snapshot. Review 2026-11-16, M1 to M4, N1, N2, nebenbei 4 to 6.
///
/// The test project (`project()`) has one entry of each of QuartzHub's four plugins, with their
/// packages from the core's fixtures (`Fixtures/option-schema/real/.quartz/plugins`: package.json and
/// the `.d.ts` files), so every step has its options. What needs the plugins' code or the project's
/// `node_modules` (quartz-forms' own check, the scan for pages with a form) only says it could not
/// run; no step depends on it.
final class SetupStepsTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  static let config = """
    configuration:
      pageTitle: Smoke
    plugins:
      - source: github:boxi-os/quartz-navigations
        enabled: true
        options:
          variant: bar
          className: nav-bar
        layout:
          position: header
          priority: 10
      - source: github:boxi-os/quartz-multilanguage
        enabled: true
        options:
          languages:
            - code: de
              label: German
              native: Deutsch
              locale: de-DE
          defaultLanguage: de
        layout:
          position: header
          priority: 15
      - source: github:quartz-community/search
        enabled: true
        layout:
          position: header
          priority: 20
      - source: github:boxi-os/quartz-layout-box
        enabled: true
        options:
          title: Info
          html: <p>x</p>
          className: layout-box-neue-box
        layout:
          position: left
          priority: 10
      - source: github:boxi-os/quartz-forms
        enabled: true
        options:
          forms:
            kontakt:
              template: contact
          layoutForm: kontakt

    """

  /// The core's copies of the four plugins' packages.
  static let plugins = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Packages/QuartzHubCore/Tests/QuartzHubCoreTests/Fixtures/option-schema/real/.quartz/plugins")

  /// A scratch profile and the test project: the config above, the four packages under
  /// `.quartz/plugins`, one page.
  private func project(config: String = SetupStepsTests.config) throws -> (profile: URL, project: URL) {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("qh-ui-setup-\(UUID().uuidString)")
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    let profile = root.appendingPathComponent("profil")
    let project = root.appendingPathComponent("setup-projekt")
    try files.createDirectory(at: profile, withIntermediateDirectories: true)
    try files.createDirectory(at: project.appendingPathComponent(".quartz/plugins"), withIntermediateDirectories: true)
    for name in ["quartz-navigations", "quartz-layout-box", "quartz-forms", "quartz-multilanguage"] {
      try files.copyItem(at: Self.plugins.appendingPathComponent(name), to: project.appendingPathComponent(".quartz/plugins/\(name)"))
    }
    try files.createDirectory(at: project.appendingPathComponent("content"), withIntermediateDirectories: true)
    try Data("# Start\n".utf8).write(to: project.appendingPathComponent("content/index.md"))
    try Data(config.utf8).write(to: project.appendingPathComponent("quartz.config.yaml"))
    return (profile, project)
  }

  /// The project's window on a tab of Plugins, Navigationen unless said otherwise.
  private func open(_ profile: URL, _ project: URL, tab name: String = "Navigationen",
                    list: String = "navigations.list") -> (XCUIApplication, XCUIElement) {
    let app = XCUIApplication()
    app.launchArguments += ["-QHLanguage", "de", "-ApplePersistenceIgnoreState", "YES", "-QHNoUpdateCheck", "YES",
                            "-QHProfileDir", profile.path, "-QHOpenProject", project.path, "-QHWindowSize", "1400x860"]
    app.launch()
    let window = app.windows.containing(NSPredicate(format: "identifier == %@", "sidebar")).firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    window.descendants(matching: .any)["sidebar.plugins"].firstMatch.click()
    let tab = window.radioButtons[name].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 10), "no tab \(name)")
    tab.click()
    XCTAssertTrue(window.descendants(matching: .any)[list].firstMatch.waitForExistence(timeout: 10), "no \(list)")
    return (app, window)
  }

  private func read(_ project: URL) -> String {
    (try? String(contentsOf: project.appendingPathComponent("quartz.config.yaml"), encoding: .utf8)) ?? ""
  }

  /// The snapshots in the project's store: one ref each, loose or packed.
  private func snapshots(_ project: URL) -> Int {
    let git = project.appendingPathComponent(".quartz-gui/snapshots.git")
    let loose = (try? FileManager.default.contentsOfDirectory(atPath: git.appendingPathComponent("refs/snapshots").path))?.count ?? 0
    let packed = ((try? String(contentsOf: git.appendingPathComponent("packed-refs"), encoding: .utf8)) ?? "")
      .split(separator: "\n").filter { $0.contains(" refs/snapshots/") }.count
    return loose + packed
  }

  private func waitFor(_ what: String, timeout: TimeInterval = 10, _ check: @escaping () -> Bool) {
    let done = expectation(for: NSPredicate { _, _ in check() }, evaluatedWith: nil)
    done.expectationDescription = what
    wait(for: [done], timeout: timeout)
  }

  /// Whether `text` holds `what` in the block after the first `marker`.
  private func after(_ marker: String, in text: String, has what: String) -> Bool {
    guard let range = text.range(of: marker) else { return false }
    let rest = text[range.upperBound...]
    let block = rest.range(of: "\n  - source:").map { rest[..<$0.lowerBound] } ?? rest
    return block.contains(what)
  }

  /// A switch by its test identifier: SwiftUI's Toggle in the inspector's form has no name of its
  /// own for XCUITest (its words are a text beside it).
  private func toggle(_ window: XCUIElement, _ identifier: String) -> XCUIElement {
    window.switches.matching(identifier: identifier).firstMatch
  }

  /// The heading of the steps says this ("2 von 7").
  private func heading(_ window: XCUIElement, says text: String) -> Bool {
    let heading = window.descendants(matching: .any)["steps.heading"].firstMatch
    guard heading.waitForExistence(timeout: 5) else { return false }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if heading.label.contains(text) || (heading.value as? String)?.contains(text) == true { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    return false
  }

  /// Into a step from the list, until the heading says it (a click can still meet a list that is
  /// being laid out anew).
  private func go(_ window: XCUIElement, to step: String, heading text: String) {
    let row = window.descendants(matching: .any)["steps.step.\(step)"].firstMatch
    // An existing entry's list of steps is folded: the heading opens it.
    if !row.waitForExistence(timeout: 2) { window.descendants(matching: .any)["steps.heading"].firstMatch.click() }
    for _ in 0..<3 {
      XCTAssertTrue(row.waitForExistence(timeout: 5), "no step \(step)")
      row.click()
      if heading(window, says: text) { return }
    }
    XCTFail("step \(step) not reached")
  }

  /// ➕ Leiste: the new navigation gets the class `nav-bar-2` and its first run.
  private func addBar(_ window: XCUIElement, _ project: URL) {
    let any = window.descendants(matching: .any)
    any["navigations.add"].firstMatch.click()
    let tile = any["navigations.variant.bar"].firstMatch
    XCTAssertTrue(tile.waitForExistence(timeout: 5), "no tiles under ➕")
    tile.click()
    waitFor("nav-bar-2 written") { self.read(project).contains("className: nav-bar-2") }
    XCTAssertTrue(any["steps.cancel"].firstMatch.waitForExistence(timeout: 5), "the new navigation is not in its first run")
  }

  /// A button in a list row, by its name.
  private func rowButton(_ window: XCUIElement, _ row: String, _ name: String) -> XCUIElement {
    window.buttons.matching(identifier: row).matching(NSPredicate(format: "label == %@", name)).firstMatch
  }

  /// M1: removed from its row, the new box's run ends with it. Before the fix, a copy of the old
  /// box got the freed class `layout-box-neue-box-2` as its own and with it the run: „Einrichten
  /// abbrechen …“ beside an entry that was not new, and cancelling would have removed it.
  func testTheFirstRunEndsWithItsEntry() throws {
    let (profile, project) = try project()
    let (_, window) = open(profile, project, tab: "Zusätzliche Inhalte", list: "extras.list")
    let any = window.descendants(matching: .any)
    any["extras.add"].firstMatch.click()
    waitFor("the new box written") { self.read(project).contains("className: layout-box-neue-box-2") }
    XCTAssertTrue(any["steps.cancel"].firstMatch.waitForExistence(timeout: 5), "the new box is not in its first run")
    let remove = rowButton(window, "extras.row.2", "„Neue Box“ entfernen")
    XCTAssertTrue(remove.waitForExistence(timeout: 5), "no remove button in row 2")
    remove.click()
    let confirm = window.sheets.buttons["Entfernen"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no question before removing")
    confirm.click()
    waitFor("the new box removed") { !self.read(project).contains("layout-box-neue-box-2") }

    let duplicate = rowButton(window, "extras.row.1", "„Info“ duplizieren")
    XCTAssertTrue(duplicate.waitForExistence(timeout: 5), "no duplicate button in row 1")
    duplicate.click()
    waitFor("the copy's own class is the freed one") { self.read(project).contains("className: layout-box-neue-box layout-box-neue-box-2") }
    XCTAssertTrue(any["steps.heading"].firstMatch.waitForExistence(timeout: 5), "the copy is not in the inspector")
    XCTAssertFalse(any["steps.cancel"].firstMatch.waitForExistence(timeout: 2), "the copy took over the removed box's first run")
  }

  /// M3: the class changed in the summary, the box stays in its first run and in that step.
  /// Before the fix the inspector fell back to step 1 and „Fertig“ and „Einrichten abbrechen …“
  /// were gone.
  func testRenamingTheClassKeepsTheFirstRun() throws {
    let (profile, project) = try project()
    let (_, window) = open(profile, project, tab: "Zusätzliche Inhalte", list: "extras.list")
    let any = window.descendants(matching: .any)
    any["extras.add"].firstMatch.click()
    waitFor("the new box written") { self.read(project).contains("className: layout-box-neue-box-2") }
    go(window, to: "finish", heading: "6 von 6")
    let field = window.textFields.matching(NSPredicate(format: "value == %@", "layout-box-neue-box-2")).firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), "no field with the class in the summary")
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("layout-box-hallo\r")
    waitFor("the new class written") { self.read(project).contains("className: layout-box-hallo") }
    let heading = any["steps.heading"].firstMatch
    XCTAssertTrue(heading.waitForExistence(timeout: 5))
    XCTAssertTrue(heading.label.contains("6 von 6") || (heading.value as? String)?.contains("6 von 6") == true,
                  "the inspector left the summary: \(heading.label)")
    XCTAssertTrue(any["steps.done"].firstMatch.waitForExistence(timeout: 5), "„Fertig“ is gone")
    XCTAssertTrue(any["steps.cancel"].firstMatch.exists, "the first run ended with the new class")
  }

  /// A text typed without Return is written when its window goes behind another app: the focus
  /// stays in the field then, and before the fix the text was never written (gui-test,
  /// 2026-11-16: `dividers` held "" while the field showed „komponenten“).
  func testATypedTextIsWrittenWhenTheWindowIsLeft() throws {
    let (profile, project) = try project()
    let (app, window) = open(profile, project, tab: "Zusätzliche Inhalte", list: "extras.list")
    window.descendants(matching: .any)["extras.add"].firstMatch.click()
    waitFor("the new box written") { self.read(project).contains("className: layout-box-neue-box-2") }
    go(window, to: "finish", heading: "6 von 6")
    let field = window.textFields.matching(NSPredicate(format: "value == %@", "layout-box-neue-box-2")).firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), "no field with the class in the summary")
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("layout-box-ohne-return")
    XCTAssertFalse(read(project).contains("layout-box-ohne-return"), "written before the window was left")
    XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
    waitFor("the typed class written") { self.read(project).contains("className: layout-box-ohne-return") }
    app.activate()
  }

  /// Review 2026-11-17, N5: the other fields that write when they are left do so when their window
  /// goes behind another app too (Vorschau & Build's output folder), and a text in a field that
  /// writes at once is written when QuartzHub quits.
  func testTypedTextsAreWrittenAtWindowChangeAndQuit() throws {
    let (profile, project) = try project()
    let prefs = project.appendingPathComponent(".quartz-gui/project-prefs.json")
    let (app, window) = open(profile, project, tab: "Zusätzliche Inhalte", list: "extras.list")
    let any = window.descendants(matching: .any)
    any["sidebar.server"].firstMatch.click()
    let output = any["server.outputDir"].firstMatch
    XCTAssertTrue(output.waitForExistence(timeout: 10), "no output folder on Vorschau & Build")
    output.click()
    output.typeText("ausgabe-ohne-return")
    XCTAssertFalse(((try? String(contentsOf: prefs, encoding: .utf8)) ?? "").contains("ausgabe-ohne-return"), "written before the window was left")
    XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
    waitFor("the typed output folder written") { ((try? String(contentsOf: prefs, encoding: .utf8)) ?? "").contains("ausgabe-ohne-return") }
    app.activate()

    any["sidebar.plugins"].firstMatch.click()
    window.descendants(matching: .any)["extras.add"].firstMatch.click()
    waitFor("the new box written") { self.read(project).contains("className: layout-box-neue-box-2") }
    go(window, to: "finish", heading: "6 von 6")
    let field = window.textFields.matching(NSPredicate(format: "value == %@", "layout-box-neue-box-2")).firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), "no field with the class in the summary")
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("layout-box-beim-beenden")
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "QuartzHub did not quit")
    XCTAssertTrue(read(project).contains("className: layout-box-beim-beenden"), "the typed class was lost at quit")
  }

  /// Options are edited under Plugins only (docs/plan-eine-stelle.md): from a navigation to its
  /// place on the stage and back by „In „Navigationen“ bearbeiten“, the same navigation selected.
  func testLayoutLeadsBackToTheNavigationsOptions() throws {
    let (profile, project) = try project()
    // From Installiert, so that arriving on Navigationen is the jump's doing, not the tab the page
    // remembered.
    let (_, window) = open(profile, project, tab: "Installiert", list: "plugins.search")
    let any = window.descendants(matching: .any)
    let row = any["plugins.row.quartz-navigations"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no quartz-navigations in the list")
    row.click()
    let show = window.buttons["Auf der Bühne zeigen"].firstMatch
    XCTAssertTrue(show.waitForExistence(timeout: 5), "no „Auf der Bühne zeigen“")
    show.click()
    let edit = any["layout.inspector.editOptions"].firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 10), "the stage did not select the navigation")
    // The form comes after its schema is read, so this waits for it; its search stands above every
    // form with eight options or more, and testInstalledLeadsAnOwnPluginToItsTab sees it appear
    // for the same plugin. Checked at once for a field, this could hardly fail (review 2026-11-17, N3).
    XCTAssertFalse(any["options.search"].firstMatch.waitForExistence(timeout: 3), "the options form is still on the Layout page")
    edit.click()
    XCTAssertTrue(any["page.plugins.navigations"].firstMatch.waitForExistence(timeout: 10), "not on Plugins ▸ Navigationen")
    XCTAssertTrue(heading(window, says: "von 8"), "no navigation in the inspector")
  }

  /// Review 2026-11-17, M1: the Layout page hands over its draft. With a box removed there and the
  /// question answered „Änderungen verwerfen“, Plugins selected the box after the one asked for
  /// („Website“ for „Handbuch“): the draft's index was read in the file's list.
  func testLayoutLeadsToTheSameBoxAfterDiscarding() throws {
    let box = SetupStepsTests.config.components(separatedBy: "  - source: github:boxi-os/quartz-layout-box\n")[1]
      .components(separatedBy: "  - source: github:boxi-os/quartz-forms")[0]
    let boxes = ["Mark", "Website", "Handbuch"].map { title in
      "  - source: github:boxi-os/quartz-layout-box\n" + box.replacingOccurrences(of: "title: Info", with: "title: \(title)")
        .replacingOccurrences(of: "className: layout-box-neue-box", with: "className: layout-box-\(title.lowercased())")
    }.joined()
    let config = SetupStepsTests.config.replacingOccurrences(of: "  - source: github:boxi-os/quartz-layout-box\n" + box, with: boxes)
    XCTAssertTrue(config.contains("title: Handbuch") && config.contains("title: Mark"), "the config has not three boxes")
    let (profile, project) = try project(config: config)
    let before = read(project)
    let (_, window) = open(profile, project, tab: "Installiert", list: "plugins.search")
    let any = window.descendants(matching: .any)
    let row = any["plugins.row.quartz-layout-box#2"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no second box in the list")
    row.click()
    let show = window.buttons["Auf der Bühne zeigen"].firstMatch
    XCTAssertTrue(show.waitForExistence(timeout: 5), "no „Auf der Bühne zeigen“")
    show.click()
    let remove = window.buttons["Duplikat entfernen"].firstMatch
    XCTAssertTrue(remove.waitForExistence(timeout: 10), "the stage did not select the second box")
    remove.click()
    // „Handbuch“, the third box of the file, is the second of the draft.
    let chip = any["layout.chip.quartz-layout-box #2"].firstMatch
    XCTAssertTrue(chip.waitForExistence(timeout: 5), "no second box on the stage")
    chip.click()
    let edit = any["layout.inspector.editOptions"].firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 5), "no „In … bearbeiten“")
    edit.click()
    let discard = window.buttons["Änderungen verwerfen"].firstMatch
    XCTAssertTrue(discard.waitForExistence(timeout: 5), "leaving the edited Layout page did not ask")
    discard.click()
    XCTAssertTrue(any["page.plugins.extras"].firstMatch.waitForExistence(timeout: 10), "not on Zusätzliche Inhalte")
    let name = any["extras.inspector.name"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 10), "no box in the inspector")
    let says = "\(name.label) \(name.value as? String ?? "") \(name.title)"
    XCTAssertTrue(says.contains("Handbuch"), "another box than the one on the stage: \(says)")
    XCTAssertEqual(read(project), before, "the discarded draft was written")
  }

  /// Review 2026-11-17, M2: a text typed on the Layout page and not yet left is an edit like any
  /// other. Before the fix „In „Navigationen“ bearbeiten“ and the sidebar left without asking, and
  /// the text was gone; the field writes into the draft only when it is left. ⌘W as the third door.
  func testATypedTextOnLayoutAsksBeforeLeaving() throws {
    for door in ["editOptions", "sidebar", "close"] {
      let grouped = SetupStepsTests.config.replacingOccurrences(of: "      position: header\n      priority: 10\n",
                                                                with: "      position: header\n      priority: 10\n      group: brand\n")
      XCTAssertTrue(grouped.contains("group: brand"), "the navigation is in no group")
      let (profile, project) = try project(config: grouped)
      let (app, window) = open(profile, project, tab: "Installiert", list: "plugins.search")
      let any = window.descendants(matching: .any)
      let row = any["plugins.row.quartz-navigations"].firstMatch
      XCTAssertTrue(row.waitForExistence(timeout: 10), "no quartz-navigations in the list")
      row.click()
      let show = window.buttons["Auf der Bühne zeigen"].firstMatch
      XCTAssertTrue(show.waitForExistence(timeout: 5), "no „Auf der Bühne zeigen“")
      show.click()
      let basis = window.textFields["Grundbreite"].firstMatch
      XCTAssertTrue(basis.waitForExistence(timeout: 10), "no „Grundbreite“ for the grouped navigation")
      basis.click()
      basis.typeText("12rem")
      if door == "editOptions" {
        any["layout.inspector.editOptions"].firstMatch.click()
      } else if door == "sidebar" {
        any["sidebar.overview"].firstMatch.click()
      } else {
        basis.typeKey("w", modifierFlags: .command)
      }
      let save = window.sheets.buttons["Speichern"].firstMatch
      XCTAssertTrue(save.waitForExistence(timeout: 5), "\(door): left the page with a typed text without asking")
      save.click()
      waitFor("\(door): the typed width saved") { self.read(project).contains("basis: 12rem") }
      app.terminate()
    }
  }

  /// Review 2026-11-17, N1: „Abbrechen“ in the leave question leaves no hand-over behind. Before the
  /// fix it stayed, and the next visit of Plugins opened Navigationen instead of the tab it kept.
  func testACancelledJumpLeavesNothingForTheNextVisit() throws {
    let (profile, project) = try project()
    let (_, window) = open(profile, project, tab: "Installiert", list: "plugins.search")
    let any = window.descendants(matching: .any)
    let row = any["plugins.row.quartz-navigations"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no quartz-navigations in the list")
    row.click()
    let show = window.buttons["Auf der Bühne zeigen"].firstMatch
    XCTAssertTrue(show.waitForExistence(timeout: 5), "no „Auf der Bühne zeigen“")
    show.click()
    let duplicate = window.buttons["Duplizieren"].firstMatch
    XCTAssertTrue(duplicate.waitForExistence(timeout: 10), "the stage did not select the navigation")
    duplicate.click()
    any["layout.inspector.editOptions"].firstMatch.click()
    let cancel = window.sheets.buttons["Abbrechen"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), "leaving the edited Layout page did not ask")
    cancel.click()
    any["sidebar.overview"].firstMatch.click()
    let discard = window.sheets.buttons["Änderungen verwerfen"].firstMatch
    XCTAssertTrue(discard.waitForExistence(timeout: 5), "no question for the duplicate")
    discard.click()
    XCTAssertTrue(any["page.overview"].firstMatch.waitForExistence(timeout: 10), "not on Übersicht")
    any["sidebar.plugins"].firstMatch.click()
    XCTAssertTrue(any["plugins.search"].firstMatch.waitForExistence(timeout: 10), "Plugins did not open on Installiert, the tab it kept")
    XCTAssertFalse(any["page.plugins.navigations"].firstMatch.exists, "the cancelled jump opened Navigationen")
  }

  /// Review 2026-11-17, nebenbei 4 and 5: the summary says what a box shows, on Installiert and on
  /// Layout; „Früher“ and „Später“ are found by their own names, not both as „Reihenfolge“.
  func testTheBoxSummaryAndTheOrderButtons() throws {
    let (profile, project) = try project()
    let (_, window) = open(profile, project, tab: "Installiert", list: "plugins.search")
    let any = window.descendants(matching: .any)
    let row = any["plugins.row.quartz-layout-box"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no quartz-layout-box in the list")
    row.click()
    let kind = window.staticTexts["Inhalt"].firstMatch
    XCTAssertTrue(kind.waitForExistence(timeout: 5), "the summary on Installiert does not say what the box shows")
    window.buttons["Auf der Bühne zeigen"].firstMatch.click()
    XCTAssertTrue(any["layout.inspector.editOptions"].firstMatch.waitForExistence(timeout: 10), "the stage did not select the box")
    XCTAssertTrue(window.staticTexts["Inhalt"].firstMatch.exists, "the summary on Layout does not say what the box shows")
    XCTAssertTrue(window.buttons["Früher"].firstMatch.exists, "no button named „Früher“")
    XCTAssertTrue(window.buttons["Später"].firstMatch.exists, "no button named „Später“")
  }

  /// Installiert, an own plugin: its options lead to its tab, the whole form is folded.
  func testInstalledLeadsAnOwnPluginToItsTab() throws {
    let (profile, project) = try project()
    let (_, window) = open(profile, project, tab: "Installiert", list: "plugins.search")
    let any = window.descendants(matching: .any)
    let row = any["plugins.row.quartz-navigations"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no quartz-navigations in the list")
    row.click()
    let edit = any["plugins.inspector.editOnTab"].firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 10), "no way to the tab")
    // The form's search stands above every plugin's form with eight options or more.
    let search = any["options.search"].firstMatch
    XCTAssertFalse(search.exists, "the form is open before „Alle Optionen“")
    let fold = any["plugins.inspector.allOptions"].firstMatch
    XCTAssertTrue(fold.waitForExistence(timeout: 5), "no „Alle Optionen“")
    fold.click()
    XCTAssertTrue(search.waitForExistence(timeout: 5), "„Alle Optionen“ shows no form")
    edit.click()
    XCTAssertTrue(any["page.plugins.navigations"].firstMatch.waitForExistence(timeout: 10), "not on Navigationen")
    XCTAssertTrue(heading(window, says: "von 8"), "no navigation in the inspector")
  }

  /// N1: choosing another entry ends the run; coming back shows the steps of an existing entry.
  func testChoosingAnotherEntryEndsTheFirstRun() throws {
    let (profile, project) = try project()
    let (_, window) = open(profile, project)
    addBar(window, project)
    let any = window.descendants(matching: .any)
    window.staticTexts.matching(identifier: "navigations.row.1").firstMatch.click()
    XCTAssertFalse(any["steps.cancel"].firstMatch.waitForExistence(timeout: 2), "the first run shows on another entry")
    window.staticTexts.matching(identifier: "navigations.row.2").firstMatch.click()
    XCTAssertTrue(any["steps.heading"].firstMatch.waitForExistence(timeout: 5), "the new navigation is not in the inspector")
    XCTAssertFalse(any["steps.cancel"].firstMatch.waitForExistence(timeout: 2), "the first run outlived leaving the entry")
  }

  /// N2, the plan's smoke test: ➕, every step, a move in the placement step, cancel. The file is
  /// what it was, byte for byte, and the setup took one snapshot.
  func testEveryStepThenCancelLeavesTheFileAsItWas() throws {
    let (profile, project) = try project()
    let (_, window) = open(profile, project)
    let original = read(project)
    let snapshotsBefore = snapshots(project)
    addBar(window, project)
    let any = window.descendants(matching: .any)
    // ➕ placed the bar last in the header; "Früher" moves it before the search, which renumbers
    // the language switcher and the search: cancelling must put both back.
    let added = read(project)
    let earlier = window.buttons["Früher"].firstMatch
    XCTAssertTrue(earlier.waitForExistence(timeout: 5), "the first run does not start in the placement step")
    earlier.click()
    waitFor("the header renumbered") { self.after("community/search", in: self.read(project), has: "priority: 40") }
    XCTAssertNotEqual(read(project), added)
    let next = any["steps.next"].firstMatch
    var guardSteps = 0
    while next.exists, guardSteps < 10 {
      next.click()
      guardSteps += 1
    }
    XCTAssertTrue(any["steps.done"].firstMatch.waitForExistence(timeout: 5), "no „Fertig“ in the last step")
    any["steps.cancel"].firstMatch.click()
    let confirm = window.sheets.buttons["Navigation entfernen"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no question before cancelling")
    confirm.click()
    waitFor("the file as it was") { self.read(project) == original }
    XCTAssertEqual(snapshots(project), snapshotsBefore + 1, "a setup takes one snapshot")
  }

  // MARK: Forms

  /// ➕ Formular „Kontakt“: the new form is `kontakt-2`, in its first run.
  private func addForm(_ app: XCUIApplication, _ window: XCUIElement, _ project: URL) {
    let any = window.descendants(matching: .any)
    any["forms.add"].firstMatch.click()
    let create = app.popovers.buttons["Anlegen"].firstMatch
    XCTAssertTrue(create.waitForExistence(timeout: 5), "no popover under ➕")
    create.click()
    waitFor("kontakt-2 written") { self.read(project).contains("kontakt-2:") }
    XCTAssertTrue(any["steps.cancel"].firstMatch.waitForExistence(timeout: 5), "the new form is not in its first run")
  }

  /// The steps stay where they are when „Gespeichert“ goes, two seconds after a write: on a line
  /// of its own it moved them up by a line, and a click aimed at one step hit the next.
  func testTheStepsStayPutWhenTheSavedWordGoes() throws {
    let (profile, project) = try project()
    let (app, window) = open(profile, project, tab: "Formulare", list: "forms.list")
    let any = window.descendants(matching: .any)
    any["forms.add"].firstMatch.click()
    let create = app.popovers.buttons["Anlegen"].firstMatch
    XCTAssertTrue(create.waitForExistence(timeout: 5), "no popover under ➕")
    create.click()
    let row = any["steps.step.embed"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let before = row.frame
    // Measured while the word is there, or the comparison says nothing.
    let saved = window.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", "Gespeichert", "Gespeichert")).firstMatch
    XCTAssertTrue(saved.exists && saved.isHittable, "„Gespeichert“ is not shown right after ➕")
    sleep(3)
    XCTAssertEqual(row.frame, before, "the steps moved when „Gespeichert“ went")
  }

  /// M4: „Als Layout-Formular verwenden“ in the new form's first run, then cancel: the old layout
  /// form is back, the file byte for byte as before, one snapshot. Before the fix `layoutForm`
  /// was left empty.
  func testFormLayoutFormThenCancelLeavesTheFileAsItWas() throws {
    let (profile, project) = try project()
    let (app, window) = open(profile, project, tab: "Formulare", list: "forms.list")
    let original = read(project)
    let snapshotsBefore = snapshots(project)
    addForm(app, window, project)
    let any = window.descendants(matching: .any)
    go(window, to: "embed", heading: "6 von 7")
    let layout = toggle(window, "forms.inspector.layoutForm")
    XCTAssertTrue(layout.waitForExistence(timeout: 5), "no switch for the layout form")
    layout.click()
    waitFor("the new form is the layout form") { self.read(project).contains("layoutForm: kontakt-2") }
    any["steps.cancel"].firstMatch.click()
    let confirm = window.sheets.buttons["Formular entfernen"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no question before cancelling")
    confirm.click()
    waitFor("the file as it was") { self.read(project) == original }
    XCTAssertEqual(snapshots(project), snapshotsBefore + 1, "a setup takes one snapshot")
  }

  /// Nebenbei 5: renamed in its first run, the form keeps the run, its step and the check marks
  /// of the steps seen, and takes no snapshot of its own. Both broke before: the inspectors built a
  /// new run instead of renaming it, and asked for the snapshot after the rename.
  func testRenamingAFormKeepsTheRunAndItsMarks() throws {
    let (profile, project) = try project()
    let (app, window) = open(profile, project, tab: "Formulare", list: "forms.list")
    let snapshotsBefore = snapshots(project)
    addForm(app, window, project)
    let any = window.descendants(matching: .any)
    any["steps.next"].firstMatch.click()
    XCTAssertTrue(heading(window, says: "2 von 7"))
    let field = any["forms.inspector.id"].firstMatch
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("anfrage\r")
    // Without the scan (no node_modules) QuartzHub cannot say which pages name the form, and asks.
    let rename = window.sheets.buttons["Kennung ändern"].firstMatch
    if rename.waitForExistence(timeout: 3) { rename.click() }
    waitFor("the form renamed") { self.read(project).contains("anfrage:") }
    XCTAssertTrue(heading(window, says: "2 von 7"), "the step did not follow the rename")
    XCTAssertTrue(any["steps.cancel"].firstMatch.waitForExistence(timeout: 5), "the first run ended with the rename")
    let general = any["steps.step.general"].firstMatch
    XCTAssertTrue(general.waitForExistence(timeout: 5))
    XCTAssertEqual(general.value as? String, "erledigt", "the check mark of the first step is gone")
    // The rename belongs to the setup: no second snapshot.
    XCTAssertEqual(snapshots(project), snapshotsBefore + 1, "the rename took a snapshot of its own")
  }

  // MARK: Languages

  /// M4: ➕ Sprache „fr“, made the default in its first run, then cancel: the default is „de“
  /// again, the file byte for byte as before, one snapshot.
  func testLanguageMadeDefaultThenCancelLeavesTheFileAsItWas() throws {
    let (profile, project) = try project()
    let (app, window) = open(profile, project, tab: "Mehrsprachigkeit", list: "multilanguage.list")
    let original = read(project)
    let snapshotsBefore = snapshots(project)
    let any = window.descendants(matching: .any)
    any["multilanguage.add"].firstMatch.click()
    let code = app.popovers.textFields.firstMatch
    XCTAssertTrue(code.waitForExistence(timeout: 5), "no popover under ➕")
    code.click()
    code.typeText("fr\r")
    waitFor("fr written") { self.read(project).contains("- code: fr") || self.read(project).contains("- fr") }
    XCTAssertTrue(any["steps.cancel"].firstMatch.waitForExistence(timeout: 5), "the new language is not in its first run")
    go(window, to: "publish", heading: "3 von 4")
    let isDefault = toggle(window, "multilanguage.inspector.default")
    XCTAssertTrue(isDefault.waitForExistence(timeout: 5), "no switch for the default language")
    isDefault.click()
    waitFor("fr is the default") { self.read(project).contains("defaultLanguage: fr") }
    any["steps.cancel"].firstMatch.click()
    let confirm = window.sheets.buttons["Sprache entfernen"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no question before cancelling")
    confirm.click()
    waitFor("the file as it was") { self.read(project) == original }
    XCTAssertEqual(snapshots(project), snapshotsBefore + 1, "a setup takes one snapshot")
  }

  /// Nebenbei 6 and 4: in the site's setup, Anordnen ▸ Nach unten moves the language switcher
  /// (the placement step's ⌥⌘↓, not the list's); left from the summary through a button under
  /// „Weitere Bereiche“, the next setup starts with the languages, not in the summary.
  func testSiteSetupMovesTheSwitcherAndStartsAgainAtTheLanguages() throws {
    let (profile, project) = try project()
    let (app, window) = open(profile, project, tab: "Mehrsprachigkeit", list: "multilanguage.list")
    let any = window.descendants(matching: .any)
    let start = any["multilanguage.site.start"].firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 5), "no „Mehrsprachigkeit einrichten“ with one language")
    start.click()
    XCTAssertTrue(heading(window, says: "1 von 5"))
    go(window, to: "switcher", heading: "4 von 5")
    let menu = app.menuBars.menuBarItems["Anordnen"].firstMatch
    menu.click()
    let down = menu.menuItems["Nach unten"].firstMatch
    XCTAssertTrue(down.waitForExistence(timeout: 5) && down.isEnabled, "Anordnen ▸ Nach unten is not there")
    down.click()
    waitFor("the switcher after the search") { self.after("quartz-multilanguage", in: self.read(project), has: "priority: 30") }

    go(window, to: "finish", heading: "5 von 5")
    let more = window.buttons["Hinweise"].firstMatch
    XCTAssertTrue(more.waitForExistence(timeout: 5), "no „Hinweise“ under „Weitere Bereiche“")
    more.click()
    XCTAssertFalse(any["steps.heading"].firstMatch.waitForExistence(timeout: 2), "the setup is still in the inspector")
    // Back to the overview: choose the language, then take the choice away again.
    let row = window.staticTexts.matching(identifier: "multilanguage.language.de").firstMatch
    row.click()
    // Taken away only once the language is in the inspector: a ⌘-click right after the click met
    // the list before the choice had settled, once in a full run.
    XCTAssertTrue(any["multilanguage.inspector.name"].firstMatch.waitForExistence(timeout: 5), "the language is not in the inspector")
    XCUIElement.perform(withKeyModifiers: .command) { row.click() }
    XCTAssertTrue(start.waitForExistence(timeout: 5), "the overview is not back")
    start.click()
    XCTAssertTrue(heading(window, says: "1 von 5"), "the next setup did not start with the languages")
  }
}
