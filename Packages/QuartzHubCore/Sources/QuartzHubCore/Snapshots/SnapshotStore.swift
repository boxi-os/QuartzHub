import Foundation

/// A port of `electron/main/services/snapshotService.ts`: a project's snapshots, kept in a git
/// repository of the app's own with the project as its work tree,
///
///     git --git-dir=<project>/.quartz-gui/snapshots.git --work-tree=<project>
///
/// Each snapshot is a root commit under `refs/snapshots/<id>`, its subject "<kind> <head> <label>".
/// The store is a format QuartzControl reads and writes as well; measured against its own code
/// (`scripts/snapshots-golden.mjs`) and in both directions (`qc-snapshots.cjs` reads, restores and
/// writes a store QuartzHub wrote, and the other way round).
///
/// What differs, each on purpose:
/// - **An index of its own per operation.** QuartzControl guards the store's one index with a
///   queue in its own process; a second app writing the same store would meet its `index.lock`
///   ("Unable to create index.lock"). Here every operation starts from a copy of that index
///   (`GIT_INDEX_FILE`), because the index decides what a snapshot holds: `git add -A` keeps a file
///   the store already tracks even after the project's `.gitignore` names it (golden step "stays
///   tracked"). Afterwards the copy goes back by a rename, as git puts an index in place, but
///   without taking `index.lock`: QuartzControl's `write-tree` takes that lock too, and meeting it,
///   took git's error for a tree and answered with a snapshot that names nothing (about one in ten
///   full test runs, 2026-11-11). While someone holds the lock, QuartzControl's index stays; one
///   that started writing before the rename replaces ours, as its own next snapshot would.
/// - **Unreachable objects are pruned after ten minutes, not at once** (`gc --prune=10.minutes.ago`
///   after a delete and the thinning). An object one app has just written is unreachable until its
///   ref exists, and QuartzControl's `--prune=now` in the other app would take it. The objects of a
///   deleted snapshot are older than that and go as before. QuartzControl still prunes with `now`,
///   so a snapshot QuartzHub writes at the very moment QuartzControl deletes one can lose objects;
///   that direction is QuartzControl's and stays a known gap.
/// - **The project's HEAD only when git answers.** QuartzControl took the output of `rev-parse HEAD`
///   whatever it said, so a folder without git recorded "fatal: not a git repository …" as the head
///   and the rest of the sentence as the label (golden steps "no repository", "without a commit").
///   Here it is "-", which QuartzControl reads as no head.
/// - **Settings files that say `null`** are read as unwritten (QuartzControl threw a TypeError),
///   and a value that is no boolean counts by JavaScript's truth instead of being passed on.
/// - **Machine answers from stdout**, where QuartzControl read stdout and stderr together; a warning
///   of git on stderr cannot become part of a tree or commit id.
/// - The store's own git identity, written when QuartzHub creates one, is "QuartzHub".
public struct SnapshotStore: Sendable {
  public static let storeDirectory = "snapshots.git"
  public static let refPrefix = "refs/snapshots/"
  static let settingsFile = "snapshot-settings.json"
  static let coalesceWindow: TimeInterval = 15 * 60
  static let day: TimeInterval = 24 * 60 * 60
  /// Only the frequent small saves coalesce; everything else is a deliberate act of its own.
  static let coalescingKinds: Set<String> = ["configChange"]
  /// Never skipped when nothing changed, never thinned.
  static let keptKinds: Set<String> = ["manual", "styleMigration"]
  /// ARG_MAX on macOS took 5000 paths of ~55 characters and failed at 10000 (QuartzControl's
  /// measurement); a selection of up to 20000 goes in parts.
  static let pathBatch = 1000
  static let baseExcludes = [
    "/node_modules/", "/public/", "/prof/", "/.quartz/", "/.quartz-cache/", "/.turbo/", "/.git/",
    "/.quartz-gui/", "/tsconfig.tsbuildinfo", ".DS_Store",
  ]

  public struct Snapshot: Equatable, Sendable {
    public var id: String
    public var commit: String
    public var createdAt: String
    /// As the subject says; QuartzControl reads an unknown kind as it stands.
    public var kind: String
    public var label: String
    /// The project's own HEAD when it was taken (`resetProjectHead`).
    public var projectHead: String?
  }

  public struct FileChange: Equatable, Sendable {
    /// Relative to the project as it is now: `addedSince` exists now and not in the snapshot, so a
    /// restore deletes it.
    public enum Status: String, Sendable { case addedSince, removedSince, modified }
    public var path: String
    public var status: Status
  }

  public struct Settings: Equatable, Sendable {
    public var includeContent: Bool
    public var contentExists: Bool
    public var contentIsSymlink: Bool
  }

  public struct Failure: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var description: String { message }
  }

  /// `npm install` in the project, after a restore that moved package.json or its lockfile.
  public typealias Npm = @Sendable (_ project: String) async -> PluginCommands.Result
  /// `repointAuthoredFrames`, after a restore that touched the config or the lockfile.
  public typealias Repoint = @Sendable (_ project: String) async throws -> Void

  public struct Clock: Sendable {
    public var now: @Sendable () -> Date
    /// The four hex digits after an id (`randomBytes(2)`).
    public var tail: @Sendable () -> String
    /// Gives git `now` as the date of a snapshot's commit (the tests); otherwise git's own clock.
    public var pinsGit: Bool

    public init(now: @escaping @Sendable () -> Date, tail: @escaping @Sendable () -> String, pinsGit: Bool) {
      self.now = now
      self.tail = tail
      self.pinsGit = pinsGit
    }

    public static let system = Clock(now: { Date() }, tail: { String(format: "%04x", UInt16.random(in: .min ... .max)) }, pinsGit: false)
  }

  /// One operation on a store at a time per project, as QuartzControl's `serialize`. Ordered
  /// before the config lock: a restore ends in the frame repair, which takes that one, so nothing
  /// holding the config lock waits here.
  public static let lock = ProjectLock(name: "snapshots")

  let environment: ToolEnvironment
  let npm: Npm
  let repoint: Repoint
  let clock: Clock
  /// What `gc --prune=` keeps (see above).
  let pruneExpiry: String
  /// Every git call of the store, local as they are: a hung one would hold the project's lock and
  /// every writer behind it (review 2026-11-11, nebenbei 5; QuartzControl had none). Far above a
  /// `git add -A` over a large project.
  let gitDeadline: Duration

  public init(environment: ToolEnvironment, npm: @escaping Npm, repoint: @escaping Repoint, clock: Clock = .system,
              pruneExpiry: String = "10.minutes.ago", gitDeadline: Duration = .seconds(10 * 60)) {
    self.environment = environment
    self.npm = npm
    self.repoint = repoint
    self.clock = clock
    self.pruneExpiry = pruneExpiry
    self.gitDeadline = gitDeadline
  }

  /// What a writer asks for before it writes: a snapshot of `kind`, its id, nil when it was skipped
  /// because nothing changed. A failure stops the writer before it writes, as in QuartzControl.
  public typealias Take = @Sendable (_ project: String, _ kind: String, _ label: String) async throws -> String?

  public var take: Take {
    { project, kind, label in try await create(project: project, kind: kind, label: label)?.id }
  }

  public static func live(environment: ToolEnvironment) -> SnapshotStore {
    SnapshotStore(
      environment: environment,
      npm: { project in
        // The install after a restore that changed package.json, with the plugins' network deadline.
        let command = environment.command("npm", ["install"], in: project, timeout: PluginCommands.Deadlines().network)
        let result = await ProcessRunner.run(command)
        return PluginCommands.Result(success: result.success, output: result.report(for: command))
      },
      repoint: { project in try await ProjectPaths.repointAuthoredFrames(project: project, runtime: environment.runtime) })
  }

  static func store(_ project: String) -> String {
    "\(QuartzGuiDirectory(project: project).path)/\(storeDirectory)"
  }

  // MARK: - git

  /// One operation's view of the store: its own index file, a copy of the store's.
  final class Operation: @unchecked Sendable {
    let project: String
    let store: String
    let index: String

    init(project: String) {
      self.project = project
      store = SnapshotStore.store(project)
      index = "\(store)/qh-index-\(UUID().uuidString)"
    }
  }

  @discardableResult
  func git(_ op: Operation, _ arguments: [String], env: [String: String] = [:], input: Data? = nil) async -> CommandResult {
    var command = environment.command("git", ["--git-dir", op.store, "--work-tree", op.project] + arguments,
                                      in: op.project, input: input, timeout: gitDeadline)
    command = command.adding(env.merging(["GIT_INDEX_FILE": op.index]) { _, new in new })
    return await ProcessRunner.run(command)
  }

  /// git in the project's own repository (its HEAD, a reset), never with the store's index.
  func projectGit(_ project: String, _ arguments: [String]) async -> (CommandResult, Command) {
    let command = environment.command("git", arguments, in: project, timeout: gitDeadline)
    return (await ProcessRunner.run(command), command)
  }

  /// Runs `body` with an index of its own and puts it back afterwards (see the type).
  func withIndex<T>(_ project: String, _ body: (Operation) async throws -> T) async throws -> T {
    let op = Operation(project: project)
    let manager = FileManager.default
    let shared = "\(op.store)/index"
    Self.removeStaleIndexes(op.store, now: clock.now())
    if manager.fileExists(atPath: shared) { try? Posix.copyFile(shared, op.index) }
    defer {
      if manager.fileExists(atPath: op.index) {
        if !manager.fileExists(atPath: "\(op.store)/index.lock") { rename(op.index, shared) }
        try? manager.removeItem(atPath: op.index)
      }
    }
    return try await body(op)
  }

  /// What a run that ended without its `defer` (a crash) left behind, after an hour.
  static func removeStaleIndexes(_ store: String, now: Date) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: store) else { return }
    for name in names where name.hasPrefix("qh-index-") {
      let path = "\(store)/\(name)"
      if let modified = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date,
         now.timeIntervalSince(modified) > 60 * 60 {
        try? FileManager.default.removeItem(atPath: path)
      }
    }
  }

  // MARK: - The store

  /// Derived state about a remote, the dev server's log, a publish's staging: nothing to restore.
  static func isSnapshotWorthy(_ name: String) -> Bool {
    // content-link.json: a run's note of the vault link it parked, gone when the run ends.
    if name == storeDirectory || name == settingsFile || name == "content-link.json" { return false }
    if name == "backups" || name == "content-backups" || name == "logs" || name == "staging" { return false }
    return !name.hasPrefix("deploy-manifest-")
  }

  func writeExcludes(_ project: String, _ settings: Settings) throws {
    var lines = Self.baseExcludes
    if !settings.includeContent { lines.append("/content/") }
    let info = "\(Self.store(project))/info"
    try Posix.mkdirs(info)
    try Posix.write("\(info)/exclude", Data((lines.joined(separator: "\n") + "\n").utf8))
  }

  func ensureStore(_ op: Operation) async throws -> Settings {
    if !FileManager.default.fileExists(atPath: "\(op.store)/HEAD") {
      try QuartzGuiDirectory(project: op.project).create()
      _ = await ProcessRunner.run(environment.command("git", ["init", "--bare", "--quiet", op.store], timeout: gitDeadline))
      // A bare repository refuses a work tree; everything else about "bare" is what is wanted.
      for (key, value) in [("core.bare", "false"), ("user.name", "QuartzHub"), ("user.email", "snapshots@quartzhub.local")] {
        _ = await ProcessRunner.run(environment.command("git", ["--git-dir", op.store, "config", key, value], timeout: gitDeadline))
      }
    }
    let settings = settings(project: op.project)
    try writeExcludes(op.project, settings)
    return settings
  }

  /// The project into the index: everything not excluded, the worthwhile parts of `.quartz-gui/`
  /// forced back in, and content/ dropped explicitly when it is off (an ignore rule only governs
  /// untracked files).
  func stage(_ op: Operation, _ settings: Settings) async throws {
    let added = await git(op, ["add", "-A"])
    guard added.success else { throw Failure(message: "\(L10n.t("main.snapshotStageFailed"))\n\(added.output)") }
    let names = try FileManager.default.contentsOfDirectory(atPath: QuartzGuiDirectory(project: op.project).path)
    let entries = names.filter(Self.isSnapshotWorthy).map { ".quartz-gui/\($0)" }
    if !entries.isEmpty { await git(op, ["add", "-f", "--"] + entries) }
    if !settings.includeContent {
      await git(op, ["rm", "-r", "--cached", "--quiet", "--ignore-unmatch", "--", "content"])
    }
  }

  // MARK: - Settings

  /// A symlinked content folder is never included: git does not follow links, so a snapshot would
  /// hold the link and not one note, and a comparison would report nothing after a note changed.
  public func settings(project: String) -> Settings {
    var info = stat()
    let content = ContentFolder.path(project: project)
    let contentExists = lstat(content, &info) == 0
    let contentIsSymlink = contentExists && (info.st_mode & S_IFMT) == S_IFLNK
    var stored: JSONValue?
    if let data = try? Posix.read(QuartzGuiDirectory(project: project).file(Self.settingsFile)),
       let parsed = try? JSJSON.parse(data), case .object(let object) = parsed {
      stored = object["includeContent"]
    }
    let includeContent: Bool
    if contentIsSymlink {
      includeContent = false
    } else if let stored, stored != .null {
      includeContent = JS.truthy(stored)
    } else {
      includeContent = contentExists
    }
    return Settings(includeContent: includeContent, contentExists: contentExists, contentIsSymlink: contentIsSymlink)
  }

  public func saveSettings(project: String, includeContent: Bool) async throws -> Settings {
    try await Self.lock.run(project) {
      let isLink = settings(project: project).contentIsSymlink
      let dir = try QuartzGuiDirectory(project: project).create()
      // JSON.stringify(…, null, 2), no newline at the end.
      try JSONStore.writeAtomic(Data("{\n  \"includeContent\": \(isLink ? false : includeContent)\n}".utf8), to: "\(dir)/\(Self.settingsFile)")
      let settings = settings(project: project)
      try writeExcludes(project, settings)
      return settings
    }
  }

  // MARK: - Creating and listing

  /// Sortable and ref-safe (no ":"), with a random tail for two snapshots in one millisecond.
  func newId() -> String {
    "\(JS.isoString(clock.now()).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-"))-\(clock.tail())"
  }

  public func create(project: String, kind: String, label: String = "") async throws -> Snapshot? {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in try await createUnlocked(op, kind: kind, label: label) }
    }
  }

  /// An automatic snapshot is skipped when nothing changed since the newest, and a burst of config
  /// saves collapses into its first; a manual one is always kept.
  func createUnlocked(_ op: Operation, kind: String, label rawLabel: String) async throws -> Snapshot? {
    // The label rides in the commit subject, one line by definition.
    let label = JSText.slice(JS.trim(JSText.replaceAll(rawLabel, "[\(JSText.space)]+", with: " ")), 0, 120)
    let settings = try await ensureStore(op)
    try await stage(op, settings)

    let tree = JS.trim(await git(op, ["write-tree"]).stdout)
    guard !tree.isEmpty else { throw Failure(message: L10n.t("main.snapshotWriteTreeFailed")) }

    if !Self.keptKinds.contains(kind) {
      let existing = await listUnlocked(op)
      if let newest = existing.first {
        let previous = JS.trim(await git(op, ["rev-parse", "\(newest.commit)^{tree}"]).stdout)
        if previous == tree { return nil }
      }
      if Self.coalescingKinds.contains(kind) {
        let now = clock.now()
        let recent = existing.first { entry in
          guard entry.kind == kind, let created = Self.date(entry.createdAt) else { return false }
          return now.timeIntervalSince(created) < Self.coalesceWindow
        }
        if recent != nil { return nil }
      }
    }

    // The project's HEAD, because a core update leaves a merge commit in its history.
    let (headResult, _) = await projectGit(op.project, ["rev-parse", "HEAD"])
    let head = headResult.success ? JS.trim(headResult.stdout) : ""
    let subject = "\(kind) \(head.isEmpty ? "-" : head)\(label.isEmpty ? "" : " \(label)")"
    let now = clock.now()
    let dates = clock.pinsGit ? ["GIT_AUTHOR_DATE": JS.isoString(now), "GIT_COMMITTER_DATE": JS.isoString(now)] : [:]
    // Checked, unlike QuartzControl: without them the writer got an id that names nothing and wrote
    // on without a way back.
    let committed = await git(op, ["commit-tree", tree, "-m", subject], env: dates)
    let commit = JS.trim(committed.stdout)
    guard committed.success, !commit.isEmpty else { throw Failure(message: "\(L10n.t("snapshots.saveFailed"))\n\(committed.output)") }
    let id = newId()
    let referenced = await git(op, ["update-ref", "\(Self.refPrefix)\(id)", commit])
    guard referenced.success else { throw Failure(message: "\(L10n.t("snapshots.saveFailed"))\n\(referenced.output)") }
    // Loose objects cost a disk block each; `--auto` works only past git's own threshold.
    await git(op, ["gc", "--auto", "--quiet"])
    if !Self.keptKinds.contains(kind) { _ = await pruneUnlocked(op) }
    return Snapshot(id: id, commit: commit, createdAt: JS.isoString(now), kind: kind, label: label, projectHead: head.isEmpty ? nil : head)
  }

  /// Newest first. Reads refs only, outside the lock (as in QuartzControl).
  public func list(project: String) async -> [Snapshot] {
    await listUnlocked(Operation(project: project))
  }

  func listUnlocked(_ op: Operation) async -> [Snapshot] {
    guard FileManager.default.fileExists(atPath: "\(op.store)/HEAD") else { return [] }
    let format = "%(refname) %(objectname) %(creatordate:iso-strict) %(subject)"
    let result = await git(op, ["for-each-ref", "--format=\(format)", Self.refPrefix])
    guard result.success else { return [] }
    return result.stdout.components(separatedBy: "\n")
      .map(JS.trim)
      .filter { $0.hasPrefix(Self.refPrefix) }
      .map { line in
        // "<kind> <head> <label>": only the label can hold spaces.
        let fields = line.components(separatedBy: " ")
        let field = { (i: Int) in i < fields.count ? fields[i] : "" }
        let head = field(4)
        return Snapshot(id: String(field(0).dropFirst(Self.refPrefix.count)), commit: field(1), createdAt: field(2),
                        kind: field(3).isEmpty ? "manual" : field(3), label: fields.dropFirst(5).joined(separator: " "),
                        projectHead: head.isEmpty || head == "-" ? nil : head)
      }
      // By id, not by commit date: that has seconds, and ids carry milliseconds at a fixed width.
      .sorted { $0.id > $1.id }
  }

  /// An imported entry holds one file, the config copy of the old backups; compared and restored
  /// as that file only, never as the whole project (342 files "added since" on a real project).
  static func isPartial(_ kind: String) -> Bool { kind == "imported" }

  func snapshotPaths(_ op: Operation, _ commit: String) async -> [String] {
    await git(op, ["ls-tree", "-r", "--name-only", "-z", commit]).stdout.components(separatedBy: "\0").filter { !$0.isEmpty }
  }

  func find(_ op: Operation, _ id: String) async -> Snapshot? {
    await listUnlocked(op).first { $0.id == id }
  }

  func commitFor(_ op: Operation, _ id: String) async throws -> String {
    let result = await git(op, ["rev-parse", "\(Self.refPrefix)\(id)"])
    let commit = JS.trim(result.stdout)
    guard result.success, !commit.isEmpty else { throw Failure(message: L10n.t("main.snapshotMissing", ["id": id])) }
    return commit
  }

  static func date(_ iso: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: iso) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: iso)
  }
}
