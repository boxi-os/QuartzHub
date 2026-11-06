import Foundation

/// What the overview and Git-Sync show about a project's repository. A port of
/// `gitStatusService.ts`, measured against it with real git (`scripts/git-golden.mjs`).
public struct GitStatus: Sendable, Equatable {
  public struct Change: Sendable, Equatable {
    public enum Kind: String, Sendable { case added, deleted, renamed, copied, modified, untracked, conflicted }
    public var path: String
    /// A rename's or copy's original path.
    public var origPath: String?
    public var staged: Bool
    public var unstaged: Bool
    public var status: Kind
  }

  /// An interrupted operation, read from its marker in the git directory: a half-finished one is
  /// exactly the state in which a push does something surprising.
  public enum Operation: String, Sendable { case merge, rebase, cherryPick = "cherry-pick", revert }

  public struct Commit: Sendable, Equatable {
    public var sha: String
    public var shortSha: String
    public var author: String
    /// Strict ISO 8601 (`%aI`).
    public var date: String
    public var subject: String
  }

  public var isRepo = false
  /// "Not a repository" is a state the page can act on; every other failure of `git status` is
  /// "could not read", and the project may be a repository after all.
  public var readError: String?
  public var branch: String?
  public var detached = false
  public var upstream: String?
  /// Both 0 when there is no upstream; `upstream` is what says whether they mean anything.
  public var ahead = 0
  public var behind = 0
  public var remoteUrl: String?
  /// Conflicts first, then the other tracked changes, then untracked, each by path; at most
  /// `maxListedChanges`.
  public var changes: [Change] = []
  /// The real number, for "und N weitere".
  public var changeCount = 0
  public var conflictCount = 0
  public var inProgress: Operation?
  public var lastCommit: Commit?

  public init() {}

  /// A content folder can hold thousands of files, and a symlink swap makes all of them show up at
  /// once.
  public static let maxListedChanges = 500
  /// Local, but not always quick: a repository on a network drive or behind a hung fsmonitor never
  /// answered (QuartzControl's forty-sixth review). Generous: a large content folder takes seconds.
  public static let timeout: Duration = .seconds(30)

  public static func read(project: URL, environment: ToolEnvironment, timeout: Duration = timeout) async -> GitStatus {
    // The sentence matched here is translated by a German git; only the messages change, not the
    // porcelain.
    let command = environment.command("git", ["status", "--porcelain=v2", "--branch", "-z"], in: project, timeout: timeout)
      .adding(GitRuntime.textVariables(environment.variables))
    let result = await ProcessRunner.run(command)
    guard result.success else {
      let report = result.report(for: command)
      if JSText.test(report, "(?i)not a git repository") { return GitStatus() }
      var status = GitStatus()
      let trimmed = JS.trim(report)
      status.readError = trimmed.isEmpty ? "git status failed" : trimmed
      return status
    }

    var status = GitStatus()
    status.isRepo = true
    status.parse(result.stdout)
    status.conflictCount = status.changes.filter { $0.status == .conflicted }.count
    status.changeCount = status.changes.count
    // What the user has to act on survives the cap. V8's sort: two paths the collation calls
    // equal keep git's order.
    func rank(_ change: Change) -> Int { change.status == .conflicted ? 0 : change.status == .untracked ? 2 : 1 }
    JS.sort(&status.changes) { a, b in
      let byRank = Double(rank(a) - rank(b))
      return byRank != 0 ? byRank : JS.localeCompare(a.path, b.path)
    }
    status.changes = Array(status.changes.prefix(maxListedChanges))

    let remote = await ProcessRunner.run(environment.command("git", ["remote", "get-url", "origin"], in: project))
    let url = JS.trim(remote.stdout)
    status.remoteUrl = remote.success && !url.isEmpty ? url : nil
    status.inProgress = await inProgress(project, environment)
    status.lastCommit = await lastCommit(project, environment)
    return status
  }

  /// porcelain=v2 with `-z`: paths raw, not C-quoted, and a rename's original path is the next
  /// record. From stdout alone: a git warning on stderr glued itself to a record in QuartzControl's
  /// merged output. A record not recognised is skipped, never parsed by position.
  mutating func parse(_ raw: String) {
    let records = raw.components(separatedBy: "\0")
    var i = 0
    while i < records.count {
      defer { i += 1 }
      let record = records[i]
      if record.isEmpty { continue }
      if let head = Self.after(record, "# branch.head ") {
        detached = head == "(detached)"
        branch = detached ? nil : head
      } else if let name = Self.after(record, "# branch.upstream ") {
        upstream = name
      } else if let counts = Self.after(record, "# branch.ab ") {
        // "+3 -1"; absent when the branch has no upstream.
        let parts = JSText.split(counts, " ")
        ahead = Self.count(parts[0])
        behind = Self.count(parts.count > 1 ? parts[1] : nil)
      } else if JSText.startsWith(record, "1 ") {
        changes.append(Self.change(record, path: Self.path(after: 8, in: record)))
      } else if JSText.startsWith(record, "2 ") {
        var change = Self.change(record, path: Self.path(after: 9, in: record))
        change.origPath = i + 1 < records.count ? records[i + 1] : ""
        i += 1
        changes.append(change)
      } else if JSText.startsWith(record, "u ") {
        changes.append(Change(path: Self.path(after: 10, in: record), staged: false, unstaged: true, status: .conflicted))
      } else if let path = Self.after(record, "? ") {
        changes.append(Change(path: path, staged: false, unstaged: true, status: .untracked))
      }
    }
  }

  static func after(_ record: String, _ prefix: String) -> String? {
    JSText.startsWith(record, prefix) ? JSText.slice(record, JSText.length(prefix)) : nil
  }

  /// `Math.abs(Number(text)) || 0`.
  static func count(_ text: String?) -> Int {
    guard let text else { return 0 }
    let number = abs(JS.toNumber(.string(text)))
    return number.isFinite ? Int(number) : 0
  }

  /// X is the index against HEAD, Y the working tree against the index; "." is "unchanged here".
  static func change(_ record: String, path: String) -> Change {
    let x = JSText.slice(record, 2, 3), y = JSText.slice(record, 3, 4)
    return Change(path: path, staged: x != ".", unstaged: y != ".", status: kind(x == "." ? y : x))
  }

  static func kind(_ code: String) -> Change.Kind {
    switch code {
    case "A": .added
    case "D": .deleted
    case "R": .renamed
    case "C": .copied
    default: .modified
    }
  }

  /// Everything after the first `fields` spaces: the path itself may contain spaces.
  static func path(after fields: Int, in record: String) -> String {
    var index = 0
    for _ in 0..<fields {
      guard let next = JSText.indexOf(record, " ", from: index) else { return "" }
      index = next + 1
    }
    return JSText.slice(record, index)
  }

  /// `--git-path`, not `<project>/.git/<name>`: in a linked worktree the git directory is not
  /// `.git` (the Pages deploy makes one).
  static func inProgress(_ project: URL, _ environment: ToolEnvironment) async -> Operation? {
    let markers: [(Operation, [String])] = [
      (.merge, ["MERGE_HEAD"]), (.rebase, ["rebase-merge", "rebase-apply"]), (.cherryPick, ["CHERRY_PICK_HEAD"]), (.revert, ["REVERT_HEAD"])
    ]
    for (operation, names) in markers {
      for name in names {
        let result = await ProcessRunner.run(environment.command("git", ["rev-parse", "--git-path", name], in: project))
        guard result.success else { continue }
        let path = JS.trim(result.stdout)
        if path.isEmpty { continue }
        if Posix.exists(path.hasPrefix("/") ? path : FramePaths.resolve(project.path + "/" + path)) { return operation }
      }
    }
    return nil
  }

  /// NUL-separated, so no subject can contain the separator.
  static func lastCommit(_ project: URL, _ environment: ToolEnvironment) async -> Commit? {
    let result = await ProcessRunner.run(environment.command("git", ["log", "-1", "--format=%H%x00%h%x00%an%x00%aI%x00%s"], in: project))
    guard result.success else { return nil }
    let fields = result.stdout.components(separatedBy: "\0")
    guard !fields[0].isEmpty else { return nil }
    func field(_ index: Int) -> String { index < fields.count ? fields[index] : "" }
    var subject = field(4)
    if JSText.endsWith(subject, "\n") { subject = JSText.slice(subject, 0, JSText.length(subject) - 1) }
    return Commit(sha: JS.trim(fields[0]), shortSha: field(1), author: field(2), date: field(3), subject: subject)
  }
}
