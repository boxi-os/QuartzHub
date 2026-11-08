import Foundation
import Testing
@testable import QuartzHubCore

/// Every change keeps the fields it does not touch, in their place; an emptied folder leaves the
/// file, as `undefined` did.
@Suite struct SettingsStoreTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  @Test func aChangeKeepsTheOtherFields() throws {
    let profile = ProfileDirectory("\(scratch.path)/Profil")
    try Posix.mkdirs(profile.path)
    try Posix.write(profile.settings, Data(#"{"language":"de","theme":"dark","fremd":{"x":1},"defaultProjectDirectory":"/a"}"#.utf8))
    try SettingsStore.update(profile) { $0.theme = .light }
    try SettingsStore.update(profile) { $0.nodeRuntime = .system }
    try SettingsStore.update(profile) { $0.defaultProjectDirectory = nil }
    let text = String(decoding: try Posix.read(profile.settings), as: UTF8.self)
    #expect(text == """
      {
        "language": "de",
        "theme": "light",
        "fremd": {
          "x": 1
        },
        "nodeRuntime": "system"
      }
      """)
    #expect(SettingsStore.read(profile).nodeRuntime == .system)
  }

  @Test func theFolderFieldAsQuartzControlTookIt() throws {
    #expect(try SettingsStore.projectDirectory("  ~/Dokumente/Gärten ", home: "/Users/x/") == "/Users/x/Dokumente/Gärten")
    #expect(try SettingsStore.projectDirectory("~", home: "/Users/x") == "/Users/x")
    #expect(try SettingsStore.projectDirectory("  ", home: "/Users/x") == nil)
    #expect(throws: SettingsStore.Failure.notAbsolute) { try SettingsStore.projectDirectory("Dokumente", home: "/Users/x") }
    #expect(throws: SettingsStore.Failure.notAbsolute) { try SettingsStore.projectDirectory("~x", home: "/Users/x") }
  }
}
