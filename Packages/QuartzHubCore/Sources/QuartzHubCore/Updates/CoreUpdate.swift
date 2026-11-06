import Foundation
import Synchronization

/// The core update: Quartz upstream merged into the project, a port of `updateService.ts`
/// (`runCoreUpdate`, `abortCoreMerge`, `getCoreUpdateStatus`, `noteInstallSucceeded`), measured
/// against it with real git in 64 steps (`scripts/core-update-golden.mjs`). The reasons for every
/// edge are QuartzControl's measurements (`conventions-full.md`, "Eine Datei, die ein Werkzeug
/// erzeugt", and `snapshots-and-updates.md`); the comments here name them, the decisions file
/// says where QuartzHub does anything else.
///
/// - `package.json` and `package-lock.json` are not merged: a plan (`PackageJsonDeps`) works out
///   what the project added, both files are handed to git (`git stash push`), upstream's copy is
///   taken and npm writes the project's own packages back. What the plan cannot replay it does not
///   touch: git decides and the user reads git's answer.
/// - A note in `.quartz-gui/core-update.json` holds what a run leaves outstanding between the
///   merge commit and the warm-up build, so a later run finishes it instead of saying "Already up
///   to date".
/// - The stash name and the merge message are QuartzControl's, word for word: both apps open the
///   same projects, and each recognises the other's leftovers by them.
public final class CoreUpdate: Sendable {
  public struct Result: Sendable, Equatable {
    public var success: Bool
    public var output: String
    public var snapshotId: String?
    /// The files git left in conflict, when it did.
    public var conflicts: [String]?
  }

  public struct AbortResult: Sendable, Equatable {
    public var success: Bool
    public var output: String
    /// The sentences of `output` that are QuartzHub's, for an announcement; never git's text.
    public var sentences: [String]
  }

  public struct Status: Sendable, Equatable {
    public enum State: String, Sendable { case unknown, upToDate, behind, pending }
    /// The newest upstream commit the project contains, "" when unknown.
    public var currentCommit: String
    public var latestCommit: String
    public var state: State
    public var missingCommits: Int?
    /// With `pending`: the packages an earlier run still owes.
    public var pendingPackages: [String]?
  }

  public struct Deadlines: Sendable, Equatable {
    /// `git fetch` of upstream: it transfers objects, and a project far behind has more of them.
    public var fetch: Duration = .seconds(60)
    /// `git ls-remote`: a timeout answers "unknown", never "aktuell".
    public var lsRemote: Duration = .seconds(20)
    public init() {}
  }

  let environment: ToolEnvironment
  let templateRepository: String
  let snapshot: SnapshotStore.Take
  let deadlines: Deadlines
  /// A run or an abort per project at a time; a second one is answered at once, not queued.
  private let running = Mutex<Set<String>>([])

  public init(environment: ToolEnvironment, snapshot: @escaping SnapshotStore.Take,
              templateRepository: String = ProjectCreator.templateRepository, deadlines: Deadlines = Deadlines()) {
    self.environment = environment
    self.snapshot = snapshot
    self.templateRepository = templateRepository
    self.deadlines = deadlines
  }

  static let stashName = "QuartzControl: core update"
  static let mergeMessage = "Merge quartz-upstream (via QuartzControl)"
  static let npmOwnedFiles = ["package.json", "package-lock.json"]

  // MARK: git

  @discardableResult
  func git(_ project: URL?, _ arguments: [String], env: [String: String] = [:], timeout: Duration? = nil,
           in directory: URL? = nil) async -> CommandResult {
    let command = environment.command("git", arguments, in: directory ?? project, timeout: timeout).adding(env)
    var result = await ProcessRunner.run(command)
    // What is shown carries the deadline's sentence, as QuartzControl's runCommand put it there.
    result.output = result.report(for: command)
    return result
  }

  func trimmedStdout(_ result: CommandResult) -> String { JS.trim(result.stdout) }
  func lines(_ text: String) -> [String] { JSText.split(text, "\n").map(JS.trim).filter { !$0.isEmpty } }
  func records(_ text: String) -> [String] { text.components(separatedBy: "\0").filter { !$0.isEmpty } }
  var textVariables: [String: String] { GitRuntime.textVariables(environment.variables) }

  // MARK: The lock

  func whileHolding<T>(_ project: URL, busy: () -> T, _ body: () async throws -> T) async rethrows -> T {
    let key = ContentFolder.realPath(project.path) ?? FramePaths.resolve(project.path)
    guard running.withLock({ $0.insert(key).inserted }) else { return busy() }
    defer { _ = running.withLock { $0.remove(key) } }
    return try await body()
  }

  // MARK: Status

  /// Asked first: "an earlier run still owes something" is true whatever the network says.
  public func status(project: URL, resolveInstalled: Bool = false) async -> Status {
    let outstanding = await outstandingInstall(project)
    let head = await git(project, ["rev-parse", "HEAD"])
    let latest = await lsRemoteHead(templateRepository) ?? ""
    func pending(_ status: Status) -> Status {
      guard !outstanding.packages.isEmpty || outstanding.unfinished else { return status }
      var copy = status
      copy.state = .pending
      copy.pendingPackages = outstanding.packages
      return copy
    }
    guard head.success, !latest.isEmpty else { return pending(Status(currentCommit: "", latestCommit: latest, state: .unknown)) }
    if await historyContains(project, latest) {
      return pending(Status(currentCommit: latest, latestCommit: latest, state: .upToDate, missingCommits: 0))
    }
    let installed = await installedUpstream(project, latest, allowFetch: resolveInstalled)
    return pending(Status(currentCommit: installed.commit, latestCommit: latest, state: .behind, missingCommits: installed.missing))
  }

  /// `git ls-remote -- <url> <ref>`: the "--" keeps a source from a lockfile from being read as an
  /// option (`--upload-pack=<cmd>` runs the command).
  func lsRemote(_ url: String, _ ref: String) async -> [(commit: String, ref: String)] {
    let result = await git(nil, ["ls-remote", "--", url, ref], timeout: deadlines.lsRemote)
    guard result.success else { return [] }
    return JSText.split(result.stdout, "\n").map(JS.trim).filter { JSText.includes($0, "\t") }.map { line in
      let parts = JSText.split(line, "\t")
      return (JS.trim(parts[0]), JS.trim(parts[1]))
    }
  }

  func lsRemoteHead(_ url: String) async -> String? { await lsRemote(url, "HEAD").first?.commit }

  /// Contained in the history, not equal to HEAD: after the first own commit HEAD is a merge.
  func historyContains(_ project: URL, _ commit: String) async -> Bool {
    guard await git(project, ["cat-file", "-e", "\(commit)^{commit}"]).success else { return false }
    return await git(project, ["merge-base", "--is-ancestor", commit, "HEAD"]).success
  }

  /// The newest upstream commit the project contains: the merge base with upstream's HEAD, which
  /// needs that commit as a local object. Fetched only when the caller asks (the overview reads
  /// this status and must cost nothing to open), into FETCH_HEAD and no ref.
  func installedUpstream(_ project: URL, _ latest: String, allowFetch: Bool) async -> (commit: String, missing: Int?) {
    var known = await git(project, ["cat-file", "-e", "\(latest)^{commit}"]).success
    if !known && allowFetch {
      await git(project, ["fetch", "--no-tags", "--quiet", templateRepository, "HEAD"], timeout: deadlines.fetch)
      known = await git(project, ["cat-file", "-e", "\(latest)^{commit}"]).success
    }
    guard known else { return ("", nil) }
    let base = await git(project, ["merge-base", "HEAD", latest])
    guard base.success else { return ("", nil) }
    let count = await git(project, ["rev-list", "--count", "HEAD..\(latest)"])
    return (trimmedStdout(base), count.success ? Self.parseInt(trimmedStdout(count)) : nil)
  }

  /// `Number.parseInt(text, 10)`: the leading digits, nil for none.
  static func parseInt(_ text: String) -> Int? {
    let digits = text.prefix { $0.isASCII && $0.isNumber }
    return digits.isEmpty ? nil : Int(digits)
  }

  /// What an earlier run left owing, in the names the user reads; `unfinished` when its npm did
  /// not get through, which no hand-written line answers. The note is never ended here: a read
  /// path does not write into `.quartz-gui/`.
  func outstandingInstall(_ project: URL) async -> (packages: [String], unfinished: Bool) {
    let pending = readPendingInstall(project)
    let unfinished = !pending.head.isEmpty && pending.installFailed
    if pending.head.isEmpty || pending.reinstall.isEmpty { return ([], unfinished) }
    if await listTakenInHand(project, pending) != .stands { return ([], unfinished) }
    return (PackageJsonDeps.outstandingPackages(readPackageJson(project), pending.reinstall, putBack: pending.putBack), unfinished)
  }

  // MARK: The run

  public func run(project: URL) async throws -> Result {
    try await whileHolding(project, busy: { Result(success: false, output: L10n.t("main.updateAlreadyRunning")) }) {
      let before = await stashEntry(project) != nil ? await stashRef(project) : nil
      let result = try await runFrom(project)
      guard before != nil else { return result }
      let note = await leftoverStashNote(project, before: before)
      if note.isEmpty { return result }
      var copy = result
      copy.output = "\(result.output)\n\n\(note)"
      return copy
    }
  }

  func runFrom(_ project: URL) async throws -> Result {
    if await mergeInProgress(project) {
      return Result(success: false, output: L10n.t("main.updateMergeUnfinished"), conflicts: await conflictedFiles(project))
    }
    let snapshotId = try await snapshot(project, "coreUpdate", "")

    if !(await git(project, ["remote", "get-url", "quartz-upstream"])).success {
      let added = await git(project, ["remote", "add", "quartz-upstream", templateRepository])
      if !added.success { return Result(success: false, output: added.output, snapshotId: snapshotId) }
    }
    let fetch = await git(project, ["fetch", "quartz-upstream", "HEAD"], timeout: deadlines.fetch)
    if !fetch.success { return Result(success: false, output: fetch.output, snapshotId: snapshotId) }
    let fetched = await git(project, ["rev-parse", "FETCH_HEAD"])
    let mergeCommit = fetched.success ? trimmedStdout(fetched) : ""

    return try await ContentFolder.withSymlinkParked(project: project) {
      try await self.merge(project, mergeCommit: mergeCommit, snapshotId: snapshotId)
    }
  }

  // swiftlint:disable:next function_body_length
  func merge(_ project: URL, mergeCommit: String, snapshotId: String?) async throws -> Result {
    let plan = await planPackageFiles(project)
    let pending = readPendingInstall(project)
    let noteOverruled = await listTakenInHand(project, pending)
    let tracked = await trackedNpmOwnedFiles(project)
    var npmFilesAtHead = false
    if !tracked.isEmpty, await git(project, ["diff", "--quiet", "HEAD", "--"] + tracked).success {
      npmFilesAtHead = await git(project, ["diff", "--quiet", "--cached", "HEAD", "--"] + tracked).success
    }
    var planApplies = plan.reproducible && !tracked.isEmpty && !mergeCommit.isEmpty
    if planApplies { planApplies = !(await stagedApartFromWorkingTree(project, tracked)) }
    var held = HeldFiles.clean
    if planApplies {
      held = await holdNpmOwnedFiles(project, tracked, mergeCommit)
      if case .failed = held { planApplies = false }
    }

    let headBefore = trimmedStdout(await git(project, ["rev-parse", "HEAD"]))
    let merge = await git(project, ["merge", "FETCH_HEAD", "-m", Self.mergeMessage], env: textVariables)
    var mergeOutput = merge.output
    var ourMergeCommit = false
    if !merge.success {
      let conflictFiles = await conflictedFiles(project)
      let onlyNpmOwned = !conflictFiles.isEmpty && conflictFiles.allSatisfy { Self.npmOwnedFiles.contains($0) }
      if planApplies && onlyNpmOwned {
        // Upstream's copy of what git tracks; a file the project no longer tracks stays deleted
        // rather than coming back as upstream's.
        let takeTheirs = conflictFiles.filter { tracked.contains($0) }
        let keepDeleted = conflictFiles.filter { !tracked.contains($0) }
        var resolved = true
        if !takeTheirs.isEmpty { resolved = await git(project, ["checkout", "--theirs", "--"] + takeTheirs).success }
        var dropped = true
        if !keepDeleted.isEmpty { dropped = await git(project, ["rm", "--cached", "--force", "--"] + keepDeleted).success }
        var staged = resolved && dropped
        if staged && !takeTheirs.isEmpty { staged = await git(project, ["add", "--"] + takeTheirs).success }
        let committed = staged ? await git(project, ["commit", "--no-edit"]) : nil
        guard let committed, committed.success else {
          let why = committed.map { "\n\($0.output)" } ?? ""
          return Result(success: false, output: Self.explain(merge.output) + merge.output + why, snapshotId: snapshotId, conflicts: conflictFiles)
        }
        mergeOutput = "\(merge.output)\n\(committed.output)"
        ourMergeCommit = true
      } else {
        let inProgress = await mergeInProgress(project)
        let restored = inProgress ? false : await releaseNpmOwnedFiles(project, held)
        return Result(success: false, output: Self.explain(merge.output) + merge.output + pendingSentence(restored, held, plan),
                      snapshotId: snapshotId, conflicts: conflictFiles)
      }
    }

    let headAfter = trimmedStdout(await git(project, ["rev-parse", "HEAD"]))
    // A merge commit of this run: HEAD moved, and not onto what was fetched (a fast-forward).
    if merge.success && !headAfter.isEmpty && !mergeCommit.isEmpty && headAfter != headBefore && headAfter != mergeCommit {
      ourMergeCommit = true
    }
    let pendingFor = pending.head
    // Nothing fetched and nothing outstanding: the shortcut.
    if !headBefore.isEmpty && headAfter == headBefore && pendingFor.isEmpty {
      let restored = await releaseNpmOwnedFiles(project, held)
      return Result(success: true, output: mergeOutput + pendingSentence(restored, held, plan), snapshotId: snapshotId)
    }

    var noteFailure = ""
    func noteFailed(_ error: Error) {
      noteFailure = "\n\n\(L10n.t("main.updateNoteUnwritable", ["reason": "\(error)"]))"
    }
    let takenOut = planApplies ? plan.reinstall : []
    // The note is written before it is read, so it holds what the next run needs.
    let carried = !pendingFor.isEmpty && noteOverruled == .stands ? pending.reinstall : []
    let carriedPutBack = carried.isEmpty ? [] : pending.putBack
    let filesAtHead = !pendingFor.isEmpty && pendingFor == headAfter ? pending.filesAtHead : npmFilesAtHead
    let wanted = takenOut + carried.filter { entry in !takenOut.contains { $0.name == entry.name && $0.section == entry.section } }
    do { try markInstallPending(project, head: headAfter, reinstall: wanted, filesAtHead: filesAtHead, putBack: carriedPutBack) } catch { noteFailed(error) }

    let missingNow = wanted.isEmpty ? [] : PackageJsonDeps.missingFrom(readPackageJson(project), wanted)
    let installCalls = missingNow.isEmpty ? [["install"]] : PackageJsonDeps.reinstallCommands(missingNow)
    let linesBefore = missingNow.isEmpty ? nil : packageLines(project, missingNow)
    var installOutput = ""
    for call in installCalls {
      let command = environment.command("npm", call, in: project)
      let install = await ProcessRunner.run(command)
      installOutput += install.report(for: command)
      guard install.success else {
        await dropNpmOwnedFiles(project, held)
        // "Put back" is "the line moved in this run": npm writes the range it resolves.
        let linesAfter = linesBefore != nil ? packageLines(project, missingNow) : nil
        var putBack = carriedPutBack
        if let linesAfter {
          putBack += missingNow.filter { linesAfter[$0.name] != "" && linesAfter[$0.name] != linesBefore?[$0.name] }.map(\.name)
        }
        do {
          try markInstallPending(project, head: headAfter, reinstall: wanted, filesAtHead: filesAtHead, installFailed: true, putBack: putBack)
        } catch { noteFailed(error) }
        let gone = wanted.isEmpty ? [] : PackageJsonDeps.absentFrom(readPackageJson(project), wanted)
        let missing = gone.isEmpty ? "" : "\n\n\(L10n.t("main.updatePackagesMissing", ["packages": Self.labels(gone, wanted)]))"
        let droppedHere = await droppedNote(project, noteOverruled, pending)
        return Result(success: false,
                      output: "\(mergeOutput)\n\n\(L10n.t("main.npmInstallFailed"))\n\(installOutput)\(missing)\(droppedHere.isEmpty ? "" : "\n\n\(droppedHere)")\(noteFailure)",
                      snapshotId: snapshotId)
      }
    }

    do { try markInstallPending(project, head: headAfter, reinstall: [], filesAtHead: filesAtHead) } catch { noteFailed(error) }

    // The run that finishes an earlier one may amend that run's merge commit, if it is still the
    // app's own and has not left the machine.
    var resuming = false
    if !ourMergeCommit && !pendingFor.isEmpty && pendingFor == headAfter {
      let subject = await headSubject(project)
      if subject == Self.mergeMessage { resuming = !(await headIsPushed(project)) }
    }
    // Both halves: the note's account of the files before the merge, and this run's own measure.
    var amendWorth = (ourMergeCommit || resuming) && filesAtHead && npmFilesAtHead && !tracked.isEmpty
    if amendWorth { amendWorth = !(await git(project, ["diff", "--quiet", "HEAD", "--"] + tracked)).success }
    if amendWorth { await git(project, ["commit", "--amend", "--no-edit", "--only", "--"] + tracked) }

    let dropped = await droppedNote(project, noteOverruled, pending)
    let packageNotes = [
      missingNow.isEmpty ? "" : L10n.t("main.updatePackagesReinstalled", ["packages": Self.labels(missingNow)]),
      planApplies && !plan.upstreamWins.isEmpty ? L10n.t("main.updatePackagesUpstreamWins", ["packages": plan.upstreamWins.joined(separator: ", ")]) : "",
      dropped
    ].filter { !$0.isEmpty }.joined(separator: "\n")

    await dropNpmOwnedFiles(project, held)

    let build = environment.command("npx", ["quartz", "build"], in: project)
    let warmup = await ProcessRunner.run(build)
    let warmupNote = warmup.success ? "" : "\n\n\(L10n.t("main.warmupBuild"))\n\(warmup.report(for: build))"

    do { try clearInstallPending(project) } catch { noteFailed(error) }
    return Result(success: true,
                  output: "\(mergeOutput)\n\(installOutput)\(packageNotes.isEmpty ? "" : "\n\(packageNotes)")\(warmupNote)\(noteFailure)",
                  snapshotId: snapshotId)
  }

  /// The project's own packages that a stash git did not give back are named.
  func pendingSentence(_ restored: Bool, _ held: HeldFiles, _ plan: PackagePlan) -> String {
    guard !restored, case .held = held, !plan.localEdits.reinstall.isEmpty else { return "" }
    return "\n\n\(L10n.t("main.updatePackagesPending", ["packages": Self.labels(plan.localEdits.reinstall)]))"
  }

  func headSubject(_ project: URL) async -> String {
    let subject = await git(project, ["log", "-1", "--format=%s"])
    return subject.success ? trimmedStdout(subject) : ""
  }

  /// Whether HEAD stands in a remote-tracking ref: what can be asked without the network. Not
  /// knowing is not permission.
  func headIsPushed(_ project: URL) async -> Bool {
    let contains = await git(project, ["branch", "-r", "--contains", "HEAD"])
    return !contains.success || !trimmedStdout(contains).isEmpty
  }

  func mergeInProgress(_ project: URL) async -> Bool {
    await git(project, ["rev-parse", "-q", "--verify", "MERGE_HEAD"]).success
  }

  // MARK: The plan

  struct PackagePlan {
    var changes: PackageJsonDeps.Changes
    /// HEAD against the working tree: what the stash holds, in packages.
    var localEdits: PackageJsonDeps.Changes
    /// False: not all sides readable, or something the plan cannot replay. Git decides.
    var reproducible: Bool
    var reinstall: [PackageJsonDeps.Addition] { changes.reinstall }
    var upstreamWins: [String] { changes.upstreamWins }
  }

  /// Worked out before the merge: afterwards the working tree no longer holds "ours".
  func planPackageFiles(_ project: URL) async -> PackagePlan {
    let handsOff = PackagePlan(changes: .init(), localEdits: .init(), reproducible: false)
    let mergeBase = await git(project, ["merge-base", "HEAD", "FETCH_HEAD"])
    guard mergeBase.success else { return handsOff }
    guard let base = await jsonAt(project, trimmedStdout(mergeBase), "package.json"),
          let theirs = await jsonAt(project, "FETCH_HEAD", "package.json"),
          let head = await jsonAt(project, "HEAD", "package.json"),
          case .parsed(let ours) = readPackageJson(project) else { return handsOff }
    let changes = PackageJsonDeps.localPackageChanges(base: base, ours: ours, theirs: theirs)
    // HEAD on both sides: what the reset to HEAD takes away (a removal after a commit).
    let localEdits = PackageJsonDeps.localPackageChanges(base: head, ours: ours, theirs: head)
    return PackagePlan(changes: changes, localEdits: localEdits,
                       reproducible: changes.unreproducible.isEmpty && localEdits.unreproducible.isEmpty)
  }

  func jsonAt(_ project: URL, _ revision: String, _ file: String) async -> JSONValue? {
    let shown = await git(project, ["show", "\(revision):\(file)"])
    guard shown.success else { return nil }
    return try? JSJSON.parse(Data(shown.stdout.utf8))
  }

  func readPackageJson(_ project: URL) -> PackageJsonDeps.Read {
    guard let data = try? Data(contentsOf: project.appendingPathComponent("package.json")),
          let value = try? JSJSON.parse(Data(String(decoding: data, as: UTF8.self).utf8)) else { return .unreadable }
    return .parsed(value)
  }

  /// Which of the two files git tracks: `git checkout -- a b` is all or nothing.
  func trackedNpmOwnedFiles(_ project: URL) async -> [String] {
    let listed = await git(project, ["ls-files", "--"] + Self.npmOwnedFiles)
    return listed.success ? lines(listed.stdout) : []
  }

  /// HEAD, the index and the working tree all different: the stash would carry what the plan
  /// cannot name. Could not look is not "all clear".
  func stagedApartFromWorkingTree(_ project: URL, _ tracked: [String]) async -> Bool {
    let staged = await git(project, ["diff", "--name-only", "--cached", "HEAD", "--"] + tracked)
    let unstaged = await git(project, ["diff", "--name-only", "--"] + tracked)
    guard staged.success, unstaged.success else { return true }
    let differsFromHead = Set(lines(staged.stdout))
    return lines(unstaged.stdout).contains { differsFromHead.contains($0) }
  }

  /// By name, with the section where the same name stands in the list more than once.
  static func labels(_ entries: [PackageJsonDeps.Addition], _ list: [PackageJsonDeps.Addition]? = nil) -> String {
    let list = list ?? entries
    let labels = entries.map { entry in
      list.filter { $0.name == entry.name }.count > 1 ? "\(entry.name) (\(entry.section.rawValue))" : entry.name
    }
    return PackageJsonDeps.unique(labels).joined(separator: ", ")
  }

  /// Where each name stands in package.json now, across all sections; only ever compared with
  /// itself, before and after npm.
  func packageLines(_ project: URL, _ entries: [PackageJsonDeps.Addition]) -> [String: String]? {
    guard case .parsed(let pkg) = readPackageJson(project) else { return nil }
    var map: [String: String] = [:]
    for entry in entries {
      map[entry.name] = PackageJsonDeps.sections.compactMap { section in
        PackageJsonDeps.dependencyRange(pkg, section, entry.name).map { "\(section.rawValue):\($0)" }
      }.joined(separator: " ")
    }
    return map
  }

  func diffNames(_ project: URL, _ arguments: String...) async -> [String] {
    await diffNames(project, arguments)
  }

  func diffNames(_ project: URL, _ arguments: [String]) async -> [String] {
    let result = await git(project, ["diff", "--name-only", "-z"] + arguments)
    return result.success ? records(result.stdout) : []
  }

  func conflictedFiles(_ project: URL) async -> [String] { await diffNames(project, "--diff-filter=U") }

  // MARK: Plugins' snapshot

  /// `noteInstallSucceeded`: the project's own `npm install` got through after a failed run.
  public func noteInstallSucceeded(project: URL) throws {
    let pending = readPendingInstall(project)
    guard !pending.head.isEmpty, pending.installFailed else { return }
    try markInstallPending(project, head: pending.head, reinstall: pending.reinstall, filesAtHead: pending.filesAtHead,
                           installFailed: false, putBack: pending.putBack)
  }
}
