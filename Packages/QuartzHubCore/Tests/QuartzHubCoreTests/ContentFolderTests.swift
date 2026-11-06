import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct ContentFolderTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  var project: URL { scratch.url.appendingPathComponent("project") }
  var content: URL { ContentFolder.path(project: project) }

  @discardableResult
  func file(_ relative: String, _ text: String = "x") throws -> URL {
    let url = scratch.url.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
  }

  func link(_ relative: String, to target: String) throws {
    let url = scratch.url.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
  }

  @Test func noContentFolder() throws {
    _ = try scratch.dir("project")
    #expect(try ContentFolder.status(project: project) == .init(path: content, exists: false, isSymlink: false))
  }

  @Test func countsWhatQuartzWouldSee() throws {
    try file("project/content/index.md")
    try file("project/content/Notizen/Äpfel & Birnen.md")
    try file("project/content/Notizen/tief/x.png")
    // Hidden: neither the files nor what is inside the folders.
    try file("project/content/.obsidian/workspace.json")
    try file("project/content/.git/HEAD")
    try file("project/content/Notizen/.DS_Store")
    // A linked folder counts by what is in it, not as one file.
    try file("elsewhere/a.md")
    try file("elsewhere/b.md")
    try link("project/content/Verlinkt", to: scratch.url.appendingPathComponent("elsewhere").path)
    // A link back to an ancestor is cut, a dangling one counts as nothing.
    try link("project/content/Notizen/zurück", to: "..")
    try link("project/content/weg", to: "/nowhere/at/all")
    let status = try ContentFolder.status(project: project)
    #expect(!status.isSymlink)
    #expect(status.fileCount == 5)
    #expect(status.hasIndex == true)
  }

  @Test func theStartPageInAnyCase() throws {
    try file("project/content/Index.MD")
    #expect(try ContentFolder.status(project: project).hasIndex == true)
    try FileManager.default.removeItem(at: content.appendingPathComponent("Index.MD"))
    try file("project/content/sub/index.md")
    #expect(try ContentFolder.status(project: project).hasIndex == false, "only the top counts")
  }

  @Test func aRelativeLinkIsResolvedFromTheProject() throws {
    try file("vault/eins.md")
    try file("vault/zwei.md")
    try link("project/content", to: "../vault")
    let status = try ContentFolder.status(project: project)
    #expect(status.isSymlink && status.symlinkTarget == "../vault")
    #expect(status.targetExists == true)
    #expect(status.fileCount == 2)
    #expect(status.hasIndex == false)
  }

  @Test func aDanglingLinkIsStillALink() throws {
    // A vault on a drive that is not mounted.
    try link("project/content", to: "/Volumes/QH-not-mounted/vault")
    let status = try ContentFolder.status(project: project)
    #expect(status.exists && status.isSymlink)
    #expect(status.targetExists == false)
    #expect(status.fileCount == nil && status.hasIndex == nil)
  }

  @Test func parkingTakesTheLinkAwayAndPutsItBack() async throws {
    let note = try file("vault/note.md", "meine Notiz")
    try link("project/content", to: "../vault")
    let seen = try await ContentFolder.withSymlinkParked(project: project) { () -> Bool in
      let free = (try? FileManager.default.destinationOfSymbolicLink(atPath: content.path)) == nil
        && !FileManager.default.fileExists(atPath: content.path)
      // What git would do: check out a real content/ with a file of its own.
      try file("project/content/.gitkeep", "")
      return free
    }
    #expect(seen, "the link was still there while parked")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: content.path) == "../vault")
    #expect(try String(contentsOf: note, encoding: .utf8) == "meine Notiz")
    #expect(!FileManager.default.fileExists(atPath: scratch.url.appendingPathComponent("vault/.gitkeep").path))
  }

  @Test func aFailingBodyStillGetsTheLinkBack() async throws {
    struct Boom: Error {}
    try file("vault/note.md")
    try link("project/content", to: scratch.url.appendingPathComponent("vault").path)
    await #expect(throws: Boom.self) {
      try await ContentFolder.withSymlinkParked(project: project) { throw Boom() }
    }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: content.path) == scratch.url.appendingPathComponent("vault").path)
  }

  @Test func aRealFolderIsNotParked() async throws {
    try file("project/content/note.md")
    let ran = try await ContentFolder.withSymlinkParked(project: project) {
      FileManager.default.fileExists(atPath: content.appendingPathComponent("note.md").path)
    }
    #expect(ran)
    #expect(FileManager.default.fileExists(atPath: content.appendingPathComponent("note.md").path))
  }
}
