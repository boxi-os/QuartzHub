import XCTest

/// The inspector in steps (docs/plan-assistenten.md) at the running app, on a navigation: the
/// first run of a new entry ends with that entry, a cancel takes back exactly what ➕ wrote, and
/// the setup takes one snapshot. Review 2026-11-16, M1, N1, N2.
///
/// The project is a scratch folder with one navigation of quartz-navigations; the plugin's package
/// is not there, so the steps of its options say they cannot be read. The steps QuartzHub draws
/// itself (variant, place, summary) do not need it.
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

    """

  private func project() throws -> (profile: URL, project: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("qh-ui-setup-\(UUID().uuidString)")
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    let profile = root.appendingPathComponent("profil")
    let project = root.appendingPathComponent("setup-projekt")
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data(Self.config.utf8).write(to: project.appendingPathComponent("quartz.config.yaml"))
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
  /// were gone. Needs the box's schema: quartz-layout-box's package.json from the core's fixtures.
  func testRenamingTheClassKeepsTheFirstRun() throws {
    let (profile, project) = try project()
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Packages/QuartzHubCore/Tests/QuartzHubCoreTests/Fixtures/option-schema/real/.quartz/plugins/quartz-layout-box")
    let plugin = project.appendingPathComponent(".quartz/plugins/quartz-layout-box")
    try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixture.appendingPathComponent("package.json"), to: plugin.appendingPathComponent("package.json"))
    let (_, window) = open(profile, project, tab: "Zusätzliche Inhalte", list: "extras.list")
    let any = window.descendants(matching: .any)
    any["extras.add"].firstMatch.click()
    waitFor("the new box written") { self.read(project).contains("className: layout-box-neue-box-2") }
    any["steps.step.finish"].firstMatch.click()
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
    // ➕ placed the bar after the search; the placement step moves it in front, which renumbers
    // the search.
    let earlier = window.buttons["Früher"].firstMatch
    XCTAssertTrue(earlier.waitForExistence(timeout: 5), "the first run does not start in the placement step")
    earlier.click()
    waitFor("the search renumbered") {
      let text = self.read(project)
      return text.range(of: "community/search").map { text[$0.upperBound...].contains("priority: 30") } ?? false
    }
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
}
