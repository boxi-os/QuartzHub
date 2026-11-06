import Foundation
import Testing
@testable import QuartzHubCore

/// Files QuartzControl wrote into gui-test and Example, masked by scripts/golden-fixtures.mjs
/// (which refuses any file not in QuartzControl's JSON.stringify form). Each one must come back
/// byte for byte through the store and its model, and the models must read what is in them.
@Suite struct GoldenFileTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/quartz-gui")

  static let all: [String] = {
    let manager = FileManager.default
    return ["gui-test", "Example"].flatMap { project in
      ((try? manager.contentsOfDirectory(atPath: fixtures.appendingPathComponent(project).path)) ?? [])
        .filter { $0.hasSuffix(".json") }.sorted().map { "\(project)/\($0)" }
    }
  }()

  func load(_ name: String) throws -> (text: String, value: JSONValue) {
    let text = try String(contentsOf: Self.fixtures.appendingPathComponent(name), encoding: .utf8)
    return (text, try JSJSON.parse(text))
  }

  @Test func fixturesArePresent() {
    #expect(Self.all.count == 13)
  }

  @Test(arguments: all)
  func storeRoundTripIsByteIdentical(_ name: String) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qh-golden-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = Self.fixtures.appendingPathComponent(name)
    let copy = dir.appendingPathComponent(source.lastPathComponent)
    try FileManager.default.copyItem(at: source, to: copy)
    guard case .ok(let value) = JSONStore.read(copy) else {
      Issue.record("not readable")
      return
    }
    try JSONStore.write(value, to: copy)
    #expect(try Data(contentsOf: copy) == Data(contentsOf: source))
  }

  // Through the model views: a view that leaves its object alone writes the same bytes back.
  @Test func modelViewsKeepEveryByte() throws {
    for project in ["gui-test", "Example"] {
      let targets = try load("\(project)/publish-targets.json")
      #expect(JSJSON.stringify(JSONList<PublishTarget>(targets.value).json) == targets.text)
      let presets = try load("\(project)/theme-presets.json")
      #expect(JSJSON.stringify(JSONList<ThemePreset>(presets.value).json) == presets.text)
      let breakpoints = try load("\(project)/layout-breakpoints.json")
      #expect(JSJSON.stringify(FrameBreakpointWidths(object: breakpoints.value.objectValue!).json) == breakpoints.text)
      let pending = try load("\(project)/core-update.json")
      #expect(JSJSON.stringify(PendingInstall(object: pending.value.objectValue!).json) == pending.text)
    }
  }

  @Test func publishTargetsReadEveryDestination() throws {
    let targets = JSONList<PublishTarget>(try load("gui-test/publish-targets.json").value).items
    #expect(targets.count == 7)
    let types = Set(targets.compactMap(\.destinationType))
    #expect(types == [.sftp, .webhook, .ftp, .gitBranch, .folder])
    // folder and git-branch carry no connection.
    for target in targets where target.destinationType == .folder || target.destinationType == .gitBranch {
      #expect(target.connectionId == nil)
    }
    #expect(targets.allSatisfy { !$0.id.isEmpty && $0.destination["type"] != nil })
  }

  @Test func singleFilesReadWithQuartzControlsRules() throws {
    let breakpoints = FrameBreakpointWidths(object: try load("gui-test/layout-breakpoints.json").value.objectValue!)
    #expect(breakpoints.widths == (1200, 900))

    let pending = PendingInstall(object: try load("gui-test/core-update.json").value.objectValue!)
    #expect(pending.head == "" && pending.reinstall.isEmpty && !pending.filesAtHead && pending.putBack.isEmpty)
    #expect(try load("gui-test/core-update.json").text == JSJSON.stringify(PendingInstall.cleared.json))

    let icon = IconMarker(object: try load("Example/project-icon.json").value.objectValue!)
    #expect(icon.custom && icon.hasOriginal && icon.customDark(darkIconExists: false))

    let relay = RelayFile(object: try load("gui-test/forms-relay.json").value.objectValue!)
    // The file has no envelopeSender (written before quartz-forms 0.6.0): the default fills it.
    #expect(relay.settings["envelopeSender"] == .bool(true))
    #expect(relay.settings["subdir"] == .string("forms"))
    #expect(relay.lastUpload?["targetId"] != nil && relay.removedAt == nil)

    let snapshot = SnapshotSettingsFile(object: try load("gui-test/snapshot-settings.json").value.objectValue!)
    #expect(snapshot.includeContent(contentExists: false, contentIsSymlink: false))
    #expect(!snapshot.includeContent(contentExists: true, contentIsSymlink: true))

    let manifest = DeployManifest(try load("gui-test/deploy-manifest-relay-00000000-0000-4000-8000-000000000001.json").value)
    #expect(manifest.paths.contains("send.php") && manifest["send.php"]?.count == 64)
  }

  // Readers with defaults, on hand-made objects for the cases the fixtures do not show.
  @Test func defaultsAndBrokenValues() throws {
    #expect(FrameBreakpointWidths(object: try JSJSON.parse(#"{"tablet":"1000","mobile":700}"#).objectValue!).widths == (1000, 700))
    #expect(FrameBreakpointWidths(object: try JSJSON.parse(#"{"tablet":800,"mobile":800}"#).objectValue!).widths == (1200, 800))
    #expect(FrameBreakpointWidths(object: JSONObject()).widths == (1200, 800))

    let pending = PendingInstall(object: try JSJSON.parse(#"""
      {"installPendingFor":"ABC","reinstall":[{"name":"-x","section":"dependencies","range":"1"},
       {"name":"ok","section":"devDependencies","range":"^1.0.0"},{"name":"y","section":"other","range":"1"}],
       "putBack":["ok","-bad",""],"filesAtHead":"yes"}
      """#).objectValue!)
    #expect(pending.head == "")
    #expect(pending.reinstall == [.init(name: "ok", section: "devDependencies", range: "^1.0.0")])
    #expect(pending.putBack == ["ok"] && !pending.filesAtHead)

    #expect(IconMarker(object: try JSJSON.parse(#"{"custom":true}"#).objectValue!).customDark(darkIconExists: true))
    #expect(!IconMarker(object: try JSJSON.parse(#"{"custom":true,"customDark":false}"#).objectValue!).customDark(darkIconExists: true))
  }
}

/// The profile files, on objects built in the key order QuartzControl's writers use
/// (docs/formats/profil.md). Not from a real profile: that measurement is the migration's.
@Suite struct ProfileFileTests {
  @Test func projectEntryIsWhatAddProjectWrites() {
    var entry = ProjectEntry(id: "0f8b8c1e-0000-4000-8000-000000000000", path: "/Users/x/Quartz/gui-test",
                             addedAt: "2026-11-06T10:00:00.000Z")
    #expect(JSJSON.stringify(entry.json) == """
      {
        "id": "0f8b8c1e-0000-4000-8000-000000000000",
        "name": "gui-test",
        "path": "/Users/x/Quartz/gui-test",
        "addedAt": "2026-11-06T10:00:00.000Z"
      }
      """)
    // touchProject appends lastOpenedAt once and keeps its place afterwards.
    entry.lastOpenedAt = "a"
    entry.lastOpenedAt = "b"
    #expect(entry.object.keys == ["id", "name", "path", "addedAt", "lastOpenedAt"])
  }

  @Test func settingsDefaults() throws {
    let empty = SettingsFile(object: JSONObject())
    #expect(empty.language == .system && empty.theme == .system && empty.nodeRuntime == .embedded && empty.serversOnQuit == .ask)
    let odd = SettingsFile(object: try JSJSON.parse(#"{"theme":"sepia","language":"fr","githubToken":"x","extra":1}"#).objectValue!)
    #expect(odd.theme == .system && odd.language == .system && odd.hasLegacyGithubToken)
  }

  @Test func connectionDefaultsPerKind() throws {
    let list = JSONList<StoredConnection>(try JSJSON.parse(#"""
      [{"id":"a","kind":"ssh","name":"s","encryptedSecret":"djEw"},
       {"id":"b","kind":"ftp","name":"f","secure":1},
       {"id":"c","kind":"webhook","name":"w","encryptedSecret":"","login":"https://hooks.example.org"},
       null]
      """#))
    let items = list.items
    #expect(items.count == 3 && list.entries.count == 4)
    #expect(items[0].port == 22 && items[0].authMethod == .password && items[0].hasSecret)
    #expect(items[1].port == 21 && items[1].secure && !items[1].hasSecret)
    #expect(items[2].login == "https://hooks.example.org" && !items[2].hasSecret)
  }
}
