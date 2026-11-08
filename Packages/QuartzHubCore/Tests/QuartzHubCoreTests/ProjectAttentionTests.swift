import Foundation
import Testing
@testable import QuartzHubCore

/// The rules of the overview's band, each from `ProjectDashboard.tsx` (QuartzControl 1.3): the
/// order, the text and target of every line, and when "Alles ok" may stand.
@Suite struct ProjectAttentionTests {
  typealias Reads = ProjectAttention.Reads

  static func config(baseUrl: JSONValue?) -> QuartzConfig {
    QuartzConfig(configuration: JSONObject(baseUrl.map { [("baseUrl", $0)] } ?? []))
  }

  static func content(exists: Bool = true, link: String? = nil, targetExists: Bool? = nil, hasIndex: Bool? = true) -> ContentFolder.Status {
    ContentFolder.Status(path: "/p/content", exists: exists, isSymlink: link != nil, symlinkTarget: link,
                         targetExists: targetExists, fileCount: 3, hasIndex: hasIndex)
  }

  static func git(conflicts: Int = 0, inProgress: GitStatus.Operation? = nil, readError: String? = nil) -> GitStatus {
    var git = GitStatus()
    git.isRepo = true
    git.conflictCount = conflicts
    git.inProgress = inProgress
    git.readError = readError
    return git
  }

  /// Every read answered, nothing wrong.
  static var clean: Reads {
    var reads = Reads()
    reads.missingPackages = .done([])
    reads.missingFrames = []
    reads.content = content()
    reads.git = git()
    reads.scss = .ok
    reads.core = CoreUpdate.Status(currentCommit: "a", latestCommit: "a", state: .upToDate, missingCommits: 0)
    reads.config = config(baseUrl: .string("https://example.org"))
    return reads
  }

  @Test func cleanIsAllGood() {
    #expect(ProjectAttention.issues(Self.clean).isEmpty)
    #expect(ProjectAttention.allGood(Self.clean))
  }

  @Test func everythingAtOnceInQuartzControlsOrder() {
    var reads = Self.clean
    reads.missingPackages = .done(["a", "b"])
    reads.missingFrames = ["f"]
    reads.server = BuildService.ServerStatus(state: .error, error: "spawn ENOENT")
    reads.content = Self.content(link: "../vault", targetExists: false, hasIndex: false)
    reads.git = Self.git(conflicts: 2)
    reads.scss = .error(ScssCheck.Diagnostic(message: "boom", relativePath: "custom.scss", line: 4))
    reads.core = CoreUpdate.Status(currentCommit: "", latestCommit: "b", state: .pending, pendingPackages: ["x"])
    reads.config = Self.config(baseUrl: nil)
    let ids = ProjectAttention.issues(reads).map(\.id)
    #expect(ids == ["dependencies", "frames", "server", "content", "no-index", "git-conflict", "scss", "core-update-pending", "baseurl"])
    #expect(!ProjectAttention.allGood(reads))
  }

  @Test func dependencies() throws {
    var reads = Self.clean
    reads.missingPackages = .done(["a", "b"])
    let missing = try #require(ProjectAttention.issues(reads).first)
    #expect(missing.id == "dependencies" && missing.tone == .red && missing.installs && missing.page == "plugins")
    #expect(missing.title == L10n.t("dashboard.attention.dependenciesMissing", ["count": "2"], count: 2))

    // Installing before the first answer, and after it: one line that says so.
    reads.missingPackages = .reading
    reads.installing = true
    #expect(ProjectAttention.issues(reads).map(\.title) == [L10n.t("dashboard.attention.dependenciesInstallingTitle")])
    reads.missingPackages = .done([])
    #expect(ProjectAttention.issues(reads).map(\.id) == ["dependencies"])

    reads.installing = false
    reads.missingPackages = .failed(nil)
    let unreadable = try #require(ProjectAttention.issues(reads).first)
    #expect(unreadable.id == "dependencies-unreadable" && unreadable.tone == .amber && !unreadable.installs)
    #expect(unreadable.detail == L10n.t("dashboard.attention.dependenciesUnreadableDetail"))
    reads.missingPackages = .failed("EACCES")
    #expect(ProjectAttention.issues(reads).first?.detail == "EACCES")
    // Not read yet: no line, and no "Alles ok" either.
    reads.missingPackages = .reading
    #expect(ProjectAttention.issues(reads).isEmpty)
    #expect(!ProjectAttention.allGood(reads))
  }

  @Test func serverErrorText() {
    typealias Status = BuildService.ServerStatus
    #expect(ProjectAttention.serverErrorText(Status(state: .running)) == nil)
    #expect(ProjectAttention.serverErrorText(Status(state: .error, error: "Port belegt")) == "Port belegt")
    #expect(ProjectAttention.serverErrorText(Status(state: .error, ended: .exited(3)))
              == L10n.t("buildServer.exitedWithCode", ["code": "3"]))
    // A signal is no exit code, as Node's null.
    #expect(ProjectAttention.serverErrorText(Status(state: .error, ended: .signaled(9))) == L10n.t("buildServer.exitedUnexpectedly"))
    #expect(ProjectAttention.serverErrorText(Status(state: .error)) == L10n.t("buildServer.exitedUnexpectedly"))
  }

  @Test func content() {
    var reads = Self.clean
    reads.content = Self.content(link: "/Volumes/Weg/vault", targetExists: false, hasIndex: nil)
    let dangling = ProjectAttention.issues(reads)
    #expect(dangling.map(\.id) == ["content"])
    #expect(dangling.first?.detail == "/Volumes/Weg/vault" && dangling.first?.tone == .red)
    #expect(dangling.first?.page == "config" && dangling.first?.tab == "site")

    reads.content = Self.content(exists: false, hasIndex: nil)
    #expect(ProjectAttention.issues(reads).map(\.id) == ["content-missing"])
    reads.content = Self.content(hasIndex: false)
    #expect(ProjectAttention.issues(reads).map(\.id) == ["no-index"])
    // A link that reaches its target is no line.
    reads.content = Self.content(link: "../vault", targetExists: true)
    #expect(ProjectAttention.issues(reads).isEmpty)
  }

  @Test func gitConflictsOutrankAnOperationAndAnUnreadableState() {
    var reads = Self.clean
    reads.git = Self.git(conflicts: 1, inProgress: .merge, readError: "x")
    #expect(ProjectAttention.issues(reads).map(\.id) == ["git-conflict"])
    reads.git = Self.git(inProgress: .rebase, readError: "x")
    #expect(ProjectAttention.issues(reads).map(\.title) == [L10n.t("dashboard.attention.gitInProgress", ["operation": "rebase"])])
    reads.git = Self.git(readError: "fatal: bad index")
    #expect(ProjectAttention.issues(reads).map(\.detail) == ["fatal: bad index"])
    #expect(!ProjectAttention.allGood(reads))
    reads.git = nil
    #expect(ProjectAttention.issues(reads).isEmpty)
    #expect(!ProjectAttention.allGood(reads), "git not read yet")
  }

  @Test func scssDetailDropsEmptyParts() {
    var reads = Self.clean
    reads.scss = .error(ScssCheck.Diagnostic(message: "expected \";\"", relativePath: "", line: 3))
    let issue = ProjectAttention.issues(reads).first
    #expect(issue?.detail == L10n.t("dashboard.attention.line", ["line": "3"]) + " · expected \";\"")
    #expect(issue?.page == "styles" && issue?.tab == "customCss")
    reads.scss = .error(ScssCheck.Diagnostic(message: "boom"))
    #expect(ProjectAttention.issues(reads).first?.detail == "boom")
    // Without node_modules there is no sass: no line, and no "Alles ok".
    reads.scss = .unavailable("no sass")
    #expect(ProjectAttention.issues(reads).isEmpty)
    #expect(!ProjectAttention.allGood(reads))
  }

  @Test func coreUpdatePending() {
    var reads = Self.clean
    reads.core = CoreUpdate.Status(currentCommit: "", latestCommit: "b", state: .pending, pendingPackages: ["a", "b"])
    #expect(ProjectAttention.issues(reads).first?.detail
              == L10n.t("dashboard.attention.coreUpdatePendingDetail", ["packages": "a, b"]))
    reads.core?.pendingPackages = []
    #expect(ProjectAttention.issues(reads).first?.detail == L10n.t("dashboard.attention.coreUpdatePendingInstallDetail"))
    reads.core?.state = .behind
    #expect(ProjectAttention.issues(reads).isEmpty, "an update to have is no problem")
    // The network check is not waited for.
    reads.core = nil
    #expect(ProjectAttention.allGood(reads))
  }

  @Test func baseUrl() {
    var reads = Self.clean
    for value in [JSONValue.string("  "), .number(3), .null] {
      reads.config = Self.config(baseUrl: value)
      #expect(ProjectAttention.issues(reads).map(\.id) == ["baseurl"], "\(value)")
    }
    reads.config = Self.config(baseUrl: nil)
    #expect(ProjectAttention.issues(reads).map(\.id) == ["baseurl"])
    #expect(ProjectAttention.baseUrl(Self.config(baseUrl: .string(" https://x.org "))) == "https://x.org")
    // Config not read: no line, no "Alles ok".
    reads.config = nil
    #expect(ProjectAttention.issues(reads).isEmpty)
    #expect(!ProjectAttention.allGood(reads))
  }

  @Test func allGoodWaitsForEveryRead() {
    var reads = Self.clean
    reads.content = nil
    #expect(!ProjectAttention.allGood(reads))
    reads = Self.clean
    reads.scss = nil
    #expect(!ProjectAttention.allGood(reads))
    // Frames and the server are not waited for (QuartzControl's condition names neither).
    reads = Self.clean
    reads.missingFrames = nil
    #expect(ProjectAttention.allGood(reads))
  }
}
