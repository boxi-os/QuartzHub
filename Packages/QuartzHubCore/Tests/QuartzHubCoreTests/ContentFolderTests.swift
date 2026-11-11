import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct ContentFolderTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  var project: String { "\(scratch.path)/project" }
  var content: String { ContentFolder.path(project: project) }

  @discardableResult
  func file(_ relative: String, _ text: String = "x") throws -> String {
    let path = "\(scratch.path)/\(relative)"
    try Posix.mkdirs(NodePath.dirname(path))
    try Posix.write(path, Data(text.utf8))
    return path
  }

  func link(_ relative: String, to target: String) throws {
    let path = "\(scratch.path)/\(relative)"
    try Posix.mkdirs(NodePath.dirname(path))
    try Posix.symlink(target, path)
  }

  func target(_ link: String) throws -> [UInt8] { Array(try Posix.readlink(link).utf8) }

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
    try link("project/content/Verlinkt", to: "\(scratch.path)/elsewhere")
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
    try Posix.unlink("\(content)/Index.MD")
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

  @Test func aLinkTargetKeepsItsBytes() throws {
    try file("G\u{E4}rten/eins.md")
    try link("project/content", to: "../G\u{E4}rten")
    let status = try ContentFolder.status(project: project)
    #expect(status.symlinkTarget.map { Array($0.utf8) } == Array("../G\u{E4}rten".utf8))
    #expect(status.fileCount == 1)
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
    let note = try file("G\u{E4}rten/note.md", "meine Notiz")
    try link("project/content", to: "../G\u{E4}rten")
    let seen = try await ContentFolder.withSymlinkParked(project: project) { () -> Bool in
      let free = Posix.kind(content) == nil
      // What git would do: check out a real content/ with a file of its own.
      try file("project/content/.gitkeep", "")
      return free
    }
    #expect(seen, "the link was still there while parked")
    // Back with the bytes it had: a decomposed target names another folder for Node.
    #expect(try target(content) == Array("../G\u{E4}rten".utf8))
    #expect(String(decoding: try Posix.read(note), as: UTF8.self) == "meine Notiz")
    #expect(!Posix.exists("\(scratch.path)/G\u{E4}rten/.gitkeep"))
  }

  @Test func aFailingBodyStillGetsTheLinkBack() async throws {
    struct Boom: Error {}
    try file("vault/note.md")
    try link("project/content", to: "\(scratch.path)/vault")
    await #expect(throws: Boom.self) {
      try await ContentFolder.withSymlinkParked(project: project) { throw Boom() }
    }
    #expect(try target(content) == Array("\(scratch.path)/vault".utf8))
  }

  @Test func aRealFolderIsNotParked() async throws {
    try file("project/content/note.md")
    let ran = try await ContentFolder.withSymlinkParked(project: project) {
      Posix.exists("\(content)/note.md")
    }
    #expect(ran)
    #expect(Posix.exists("\(content)/note.md"))
  }

  // MARK: - A link a run never put back (review 2026-11-11, M1)

  var record: String { "\(project)/.quartz-gui/content-link.json" }

  @Test func parkingWritesTheTargetDownAndRemovesItAfterwards() async throws {
    try file("G\u{E4}rten/note.md")
    try link("project/content", to: "../Ga\u{308}rten")
    let written = try await ContentFolder.withSymlinkParked(project: project) {
      try JSJSON.parse(try Posix.read(record))["target"]?.stringValue
    }
    // The bytes as the link had them, decomposed or not.
    #expect(written.map { Array($0.utf8) } == Array("../Ga\u{308}rten".utf8))
    #expect(!Posix.exists(record))
    #expect(try target(content) == Array("../Ga\u{308}rten".utf8))
  }

  /// The crash: the record is there, the link is not.
  @Test func aLostLinkIsPutBackOnOpening() throws {
    try file("vault/note.md")
    try file("project/.quartz-gui/content-link.json", #"{"target":"../vault"}"#)
    #expect(try ContentFolder.recoverParkedLink(project: project) == .relinked(target: "../vault"))
    #expect(try target(content) == Array("../vault".utf8))
    #expect(!Posix.exists(record))
    // Nothing left to do the second time.
    #expect(try ContentFolder.recoverParkedLink(project: project) == nil)
  }

  /// What git checked out in its place is moved aside, never deleted.
  @Test func whatGitLeftThereIsMovedAside() throws {
    try file("vault/note.md")
    try file("project/content/.gitkeep", "von git")
    try file("project/.quartz-gui/content-link.json", #"{"target":"../vault"}"#)
    guard case .relinkedAfterMovingAside(let target, let id)? = try ContentFolder.recoverParkedLink(project: project, now: Date(timeIntervalSince1970: 1_800_000_000)) else {
      Issue.record("not moved aside")
      return
    }
    #expect(target == "../vault")
    #expect(try self.target(content) == Array("../vault".utf8))
    #expect(String(decoding: try Posix.read("\(project)/.quartz-gui/content-backups/\(id)/content/.gitkeep"), as: UTF8.self) == "von git")
    #expect(!Posix.exists(record))
  }

  /// A link that is back (the run finished putting it back, or the user set one) is left alone.
  @Test func aLinkThatIsThereIsLeftAlone() throws {
    try file("other/note.md")
    try link("project/content", to: "../other")
    try file("project/.quartz-gui/content-link.json", #"{"target":"../vault"}"#)
    #expect(try ContentFolder.recoverParkedLink(project: project) == nil)
    #expect(try target(content) == Array("../other".utf8))
    #expect(!Posix.exists(record))
  }

  /// The counter-check: while this process holds the link parked, the record is no leftover.
  @Test func aRunningRunIsNotRecoveredFrom() async throws {
    try file("vault/note.md")
    try link("project/content", to: "../vault")
    let during = try await ContentFolder.withSymlinkParked(project: project) {
      (try ContentFolder.recoverParkedLink(project: project), Posix.kind(content) == nil, Posix.exists(record))
    }
    #expect(during.0 == nil && during.1 && during.2)
    #expect(try target(content) == Array("../vault".utf8))
  }

  @Test func runningWorkIsListedWhileItRuns() async {
    let inside = await RunningWork.during(.restore, project: project) {
      RunningWork.current.contains(RunningWork.Entry(kind: .restore, project: project))
    }
    #expect(inside)
    #expect(!RunningWork.current.contains { $0.project == project })
  }
}
