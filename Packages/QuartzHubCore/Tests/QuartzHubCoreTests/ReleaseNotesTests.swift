import Foundation
import Testing
@testable import QuartzHubCore

/// `ReleaseNotes` and `SemVer` against `changelogSections` of Quartz 5.1's cli/upgrade.js (its
/// upgrade.test.js cases), and `CoreUpdate.versions`/`releaseNotes` against a real git history.
@Suite struct ReleaseNotesTests {
  static let changelog = """
    # @jackyzha0/quartz

    ## 5.2.0-beta.1

    - beta

    ## 5.1.1

    - fix

    ## Unreleased

    - not a version

    ## 5.1.0

    ### Minor Changes

    - built-ins

    ## 5.0.0

    - first
    """

  @Test func sectionsAfterFromUpToTo() {
    let notes = ReleaseNotes.sections(Self.changelog, from: "5.0.0", to: "5.1.1")
    #expect(notes.map(\.version) == ["5.1.1", "5.1.0"])
    #expect(notes[1].body == "### Minor Changes\n\n- built-ins")
    // "## Unreleased" starts no section, and its lines belong to none.
    #expect(!notes[0].body.contains("not a version"))
    // An invalid bound does not limit; newest first, a pre-release above its predecessors.
    #expect(ReleaseNotes.sections(Self.changelog, from: nil, to: "x").map(\.version) == ["5.2.0-beta.1", "5.1.1", "5.1.0", "5.0.0"])
    #expect(ReleaseNotes.sections(Self.changelog, from: "5.1.1", to: "5.1.1").isEmpty)
  }

  /// Versions from package.json at HEAD and at a commit the project has; the notes from the
  /// CHANGELOG at that commit, and nothing for a commit that is not there.
  @Test func versionsAndNotesComeFromTheProjectsGitObjects() async throws {
    let harness = try CoreUpdateTests.Harness()
    let project = "\(harness.work)/p"
    try Posix.mkdirs(project)
    func git(_ args: String...) async throws -> String {
      let result = await harness.git(args, project)
      try #require(result.success, "\(args): \(result.output)")
      return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    _ = try await git("init", "-q", "-b", "v5")
    try Posix.write("\(project)/package.json", Data(#"{"name":"@jackyzha0/quartz","version":"5.0.0"}"#.utf8))
    try Posix.write("\(project)/CHANGELOG.md", Data("## 5.0.0\n\n- first\n".utf8))
    _ = try await git("add", "-A")
    _ = try await git("commit", "-q", "-m", "5.0")
    let old = try await git("rev-parse", "HEAD")
    try Posix.write("\(project)/package.json", Data(#"{"name":"@jackyzha0/quartz","version":"5.1.0"}"#.utf8))
    try Posix.write("\(project)/CHANGELOG.md", Data(Self.changelog.utf8))
    _ = try await git("commit", "-qam", "5.1")
    let new = try await git("rev-parse", "HEAD")
    _ = try await git("reset", "-q", "--hard", old)

    let updater = CoreUpdate(environment: harness.environment, snapshot: { _, _, _ in "" })
    #expect(await updater.versions(project: project, latestCommit: new) == CoreUpdate.Versions(installed: "5.0.0", latest: "5.1.0"))
    #expect(await updater.versions(project: project, latestCommit: String(repeating: "a", count: 40)).latest == nil)
    let notes = await updater.releaseNotes(project: project, revision: new, from: "5.0.0", to: "5.1.0")
    #expect(notes.map(\.version) == ["5.1.0"])
    #expect(await updater.releaseNotes(project: project, revision: String(repeating: "a", count: 40), from: nil, to: nil).isEmpty)
  }
}
