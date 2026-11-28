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
/// - The stash name and the merge message are QuartzHub's own since 1.1, the message with the
///   release it brings ("Merge Quartz 5.2.0 (via QuartzHub)"); QuartzControl's names are still
///   recognised, because projects carry its merge commits and may carry its stash entries
///   (decisions/phase-5-gleichstand.md, "Merge-Betreff"). `.branchHead` writes QuartzControl's.
/// - **Releases, not the branch** (decisions/phase-5-gleichstand.md, "Kern aus Releases"): the
///   update goes to Quartz's newest release of the project's major version, the tag `vX.Y.Z`, not
///   to the newest commit of its default branch as in QuartzControl. `.branchHead` is
///   QuartzControl's way and stays for the replay of its steps.
public final class CoreUpdate: Sendable {
  /// What an update goes to.
  public enum Target: Sendable { case latestRelease, branchHead }

  /// The newest Quartz release QuartzHub has been checked against, raised with each QuartzHub
  /// release that was measured on a newer one (docs/release.md). A newer release is still offered,
  /// with a word that it is not checked yet: Quartz releases about weekly, and QuartzHub reads what
  /// it can from the project itself (decision of the user, 2026-11-28: a hint, no lock).
  public static let testedQuartz = "5.3.1"

  /// `release` when it is newer than `testedQuartz`, else nil.
  public static func untested(_ release: String?) -> String? {
    guard let release, SemVer.isNewer(release, than: testedQuartz) else { return nil }
    return release
  }

  /// A release of Quartz: its tag, the commit the tag names, the version.
  public struct Release: Sendable, Equatable {
    public var tag: String
    public var commit: String
    public var version: String
  }
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
    /// The version of the release `latestCommit` is, with `.latestRelease`.
    public var release: String?
    /// A release of a later major version than the project's, which is not offered.
    public var newerMajor: String?
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
  let target: Target
  let snapshot: SnapshotStore.Take
  let deadlines: Deadlines
  /// A run or an abort per project at a time; a second one is answered at once, not queued. One
  /// set for the process, as QuartzControl's module-level `coreUpdatesRunning`: a page that is left
  /// and opened again makes a new instance while the first run goes on.
  private static let running = Mutex<Set<String>>([])

  public init(environment: ToolEnvironment, snapshot: @escaping SnapshotStore.Take,
              templateRepository: String = ProjectCreator.templateRepository, deadlines: Deadlines = Deadlines(),
              target: Target = .latestRelease) {
    self.environment = environment
    self.snapshot = snapshot
    self.templateRepository = templateRepository
    self.target = target
    self.deadlines = deadlines
  }

  static let stashName = "QuartzHub: core update"
  static let quartzControlStashName = "QuartzControl: core update"
  static let quartzControlMergeMessage = "Merge quartz-upstream (via QuartzControl)"

  /// The merge commit's subject: the release it brings, or QuartzControl's for the branch.
  static func mergeMessage(_ release: Release?) -> String {
    release.map { "Merge Quartz \($0.version) (via QuartzHub)" } ?? quartzControlMergeMessage
  }

  /// The name this run gives its stash entry: QuartzControl's for its way, `.branchHead`.
  var writtenStashName: String { target == .branchHead ? Self.quartzControlStashName : Self.stashName }

  /// Whether a stash entry is either app's own.
  static func isOwnStash(_ subject: String) -> Bool {
    JSText.includes(subject, stashName) || JSText.includes(subject, quartzControlStashName)
  }

  /// Whether a commit subject is either app's merge commit.
  static func isOwnMergeSubject(_ subject: String) -> Bool {
    subject == quartzControlMergeMessage || (subject.hasPrefix("Merge Quartz ") && subject.hasSuffix(" (via QuartzHub)"))
  }
  static let npmOwnedFiles = ["package.json", "package-lock.json"]

  // MARK: git

  @discardableResult
  func git(_ project: String?, _ arguments: [String], env: [String: String] = [:], timeout: Duration? = nil,
           in directory: String? = nil) async -> CommandResult {
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

  func whileHolding<T>(_ project: String, busy: () -> T, _ body: () async throws -> T) async rethrows -> T {
    let key = ContentFolder.realPath(project) ?? FramePaths.resolve(project)
    guard Self.running.withLock({ $0.insert(key).inserted }) else { return busy() }
    defer { _ = Self.running.withLock { $0.remove(key) } }
    return try await body()
  }

  // MARK: Status

  /// Asked first: "an earlier run still owes something" is true whatever the network says.
  /// The project's `quartz-upstream` when it points somewhere other than the repository the
  /// status asks: the run fetches from that remote, the status does not (decision of the user,
  /// 2026-11-13: said, not changed). Only the local git config is read, nothing goes out; nil when
  /// the remote is missing (the run adds it) or is the same repository.
  public func divergingUpstream(project: String) async -> String? {
    let result = await git(project, ["remote", "get-url", "quartz-upstream"])
    guard result.success else { return nil }
    let url = JS.trim(result.stdout)
    return Self.sameRepository(url, templateRepository) ? nil : url
  }

  /// One repository written two ways: with or without ".git" or a trailing "/", any case.
  static func sameRepository(_ a: String, _ b: String) -> Bool {
    func normal(_ url: String) -> String {
      var text = JS.trim(url).lowercased()
      while text.hasSuffix("/") { text.removeLast() }
      if text.hasSuffix(".git") { text.removeLast(4) }
      return text
    }
    return normal(a) == normal(b)
  }

  public func status(project: String, resolveInstalled: Bool = false) async -> Status {
    let outstanding = await outstandingInstall(project)
    let head = await git(project, ["rev-parse", "HEAD"])
    let aim = await aim(project)
    let latest = aim.commit
    func pending(_ status: Status) -> Status {
      var copy = status
      copy.release = aim.release?.version
      copy.newerMajor = aim.newerMajor
      guard !outstanding.packages.isEmpty || outstanding.unfinished else { return copy }
      copy.state = .pending
      copy.pendingPackages = outstanding.packages
      return copy
    }
    guard head.success, !latest.isEmpty else { return pending(Status(currentCommit: "", latestCommit: latest, state: .unknown)) }
    // A project newer than the release (made from the branch) is up to date: never a step back.
    if await historyContains(project, latest) {
      return pending(Status(currentCommit: latest, latestCommit: latest, state: .upToDate, missingCommits: 0))
    }
    let installed = await installedUpstream(project, latest, ref: aim.ref, allowFetch: resolveInstalled)
    return pending(Status(currentCommit: installed.commit, latestCommit: latest, state: .behind, missingCommits: installed.missing))
  }

  /// Where an update goes: the commit ("" when it cannot be asked), the ref to fetch it by, and
  /// with `.latestRelease` the release and a newer major version that is only named.
  struct Aim {
    var commit: String
    var ref: String
    var release: Release?
    var newerMajor: String?
  }

  func aim(_ project: String) async -> Aim {
    switch target {
    case .branchHead:
      return Aim(commit: await lsRemoteHead(templateRepository) ?? "", ref: "HEAD")
    case .latestRelease:
      let releases = Self.releases(await lsRemote(templateRepository, "refs/tags/v*"))
      let major = await packageVersion(project, "HEAD").flatMap(SemVer.major)
      guard let release = Self.newest(releases, major: major) else { return Aim(commit: "", ref: "") }
      var newer: String?
      if let major, let newest = Self.newest(releases, major: nil), let newestMajor = SemVer.major(newest.version), newestMajor > major {
        newer = newest.version
      }
      return Aim(commit: release.commit, ref: "refs/tags/\(release.tag)", release: release, newerMajor: newer)
    }
  }

  /// The newest release in `url`, of `major` when given: the tags `vX.Y.Z` without a prerelease.
  public func latestRelease(_ url: String, major: Int? = nil) async -> Release? {
    Self.newest(Self.releases(await lsRemote(url, "refs/tags/v*")), major: major)
  }

  /// The releases among `ls-remote`'s tags. An annotated tag names a tag object; the commit is on
  /// its peeled line (`refs/tags/v5.2.0^{}`), which wins. A lightweight tag names the commit.
  static func releases(_ refs: [(commit: String, ref: String)]) -> [Release] {
    var commits: [String: String] = [:]
    var peeled: Set<String> = []
    for (commit, ref) in refs where ref.hasPrefix("refs/tags/") {
      var tag = String(ref.dropFirst("refs/tags/".count))
      if tag.hasSuffix("^{}") {
        tag.removeLast(3)
        commits[tag] = commit
        peeled.insert(tag)
      } else if !peeled.contains(tag) {
        commits[tag] = commit
      }
    }
    return commits.compactMap { tag, commit in
      guard tag.hasPrefix("v"), let parsed = SemVer.parse(String(tag.dropFirst())), parsed.pre.isEmpty else { return nil }
      return Release(tag: tag, commit: commit, version: String(tag.dropFirst()))
    }
  }

  static func newest(_ releases: [Release], major: Int?) -> Release? {
    releases.filter { major == nil || SemVer.major($0.version) == major }
      .max { SemVer.isNewer($1.version, than: $0.version) }
  }

  /// `git ls-remote -- <url> <pattern>…`: the "--" keeps a source from a lockfile from being read
  /// as an option (`--upload-pack=<cmd>` runs the command).
  func lsRemote(_ url: String, _ patterns: String...) async -> [(commit: String, ref: String)] {
    let result = await git(nil, ["ls-remote", "--", url] + patterns, timeout: deadlines.lsRemote)
    guard result.success else { return [] }
    return JSText.split(result.stdout, "\n").map(JS.trim).filter { JSText.includes($0, "\t") }.map { line in
      let parts = JSText.split(line, "\t")
      return (JS.trim(parts[0]), JS.trim(parts[1]))
    }
  }

  func lsRemoteHead(_ url: String) async -> String? { await lsRemote(url, "HEAD").first?.commit }

  /// Contained in the history, not equal to HEAD: after the first own commit HEAD is a merge.
  func historyContains(_ project: String, _ commit: String) async -> Bool {
    guard await git(project, ["cat-file", "-e", "\(commit)^{commit}"]).success else { return false }
    return await git(project, ["merge-base", "--is-ancestor", commit, "HEAD"]).success
  }

  /// The newest upstream commit the project contains: the merge base with the release (or
  /// upstream's HEAD), which needs that commit as a local object. Fetched only when the caller asks
  /// (the overview reads this status and must cost nothing to open), into FETCH_HEAD and no ref.
  func installedUpstream(_ project: String, _ latest: String, ref: String, allowFetch: Bool) async -> (commit: String, missing: Int?) {
    var known = await git(project, ["cat-file", "-e", "\(latest)^{commit}"]).success
    if !known && allowFetch {
      await git(project, ["fetch", "--no-tags", "--quiet", templateRepository, ref], timeout: deadlines.fetch)
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
  func outstandingInstall(_ project: String) async -> (packages: [String], unfinished: Bool) {
    let pending = readPendingInstall(project)
    let unfinished = !pending.head.isEmpty && pending.installFailed
    if pending.head.isEmpty || pending.reinstall.isEmpty { return ([], unfinished) }
    if await listTakenInHand(project, pending) != .stands { return ([], unfinished) }
    return (PackageJsonDeps.outstandingPackages(readPackageJson(project), pending.reinstall, putBack: pending.putBack), unfinished)
  }

  // MARK: The run

  public func run(project: String) async throws -> Result {
    try await RunningWork.during(.coreUpdate, project: project) { try await runHolding(project) }
  }

  func runHolding(_ project: String) async throws -> Result {
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

  func runFrom(_ project: String) async throws -> Result {
    if await mergeInProgress(project) {
      return Result(success: false, output: L10n.t("main.updateMergeUnfinished"), conflicts: await conflictedFiles(project))
    }
    // The release is asked before anything is written: without it there is nothing to go to.
    var release: Release?
    if target == .latestRelease {
      let major = await packageVersion(project, "HEAD").flatMap(SemVer.major)
      release = await latestRelease(templateRepository, major: major)
      if release == nil { return Result(success: false, output: L10n.t("updates.core.noRelease")) }
    }
    let snapshotId = try await snapshot(project, "coreUpdate", "")

    if !(await git(project, ["remote", "get-url", "quartz-upstream"])).success {
      let added = await git(project, ["remote", "add", "quartz-upstream", templateRepository])
      if !added.success { return Result(success: false, output: added.output, snapshotId: snapshotId) }
    }
    let fetchArguments = release.map { ["fetch", "--no-tags", "quartz-upstream", "refs/tags/\($0.tag)"] } ?? ["fetch", "quartz-upstream", "HEAD"]
    let fetch = await git(project, fetchArguments, timeout: deadlines.fetch)
    if !fetch.success {
      // A quartz-upstream that is a fork may not carry Quartz's tags.
      let missing = release.map { "\n\n" + L10n.t("updates.core.releaseMissing", ["tag": $0.tag]) } ?? ""
      return Result(success: false, output: fetch.output + missing, snapshotId: snapshotId)
    }
    // An annotated tag fetches its tag object into FETCH_HEAD; what is merged is its commit.
    let fetched = await git(project, ["rev-parse", "FETCH_HEAD^{commit}"])
    let mergeCommit = fetched.success ? trimmedStdout(fetched) : ""
    // QuartzControl's merge of FETCH_HEAD for the branch; for a release the commit itself, since
    // git merges a tag object always with a merge commit.
    let mergeRef = release != nil && !mergeCommit.isEmpty ? mergeCommit : "FETCH_HEAD"

    return try await ContentFolder.withSymlinkParked(project: project) {
      try await self.merge(project, mergeCommit: mergeCommit, mergeRef: mergeRef, message: Self.mergeMessage(release), snapshotId: snapshotId)
    }
  }

  // swiftlint:disable:next function_body_length
  func merge(_ project: String, mergeCommit: String, mergeRef: String, message: String, snapshotId: String?) async throws -> Result {
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
    let merge = await git(project, ["merge", mergeRef, "-m", message], env: textVariables)
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
      if Self.isOwnMergeSubject(subject) { resuming = !(await headIsPushed(project)) }
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

  func headSubject(_ project: String) async -> String {
    let subject = await git(project, ["log", "-1", "--format=%s"])
    return subject.success ? trimmedStdout(subject) : ""
  }

  /// Whether HEAD stands in a remote-tracking ref: what can be asked without the network. Not
  /// knowing is not permission.
  func headIsPushed(_ project: String) async -> Bool {
    let contains = await git(project, ["branch", "-r", "--contains", "HEAD"])
    return !contains.success || !trimmedStdout(contains).isEmpty
  }

  func mergeInProgress(_ project: String) async -> Bool {
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
  func planPackageFiles(_ project: String) async -> PackagePlan {
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

  func jsonAt(_ project: String, _ revision: String, _ file: String) async -> JSONValue? {
    let shown = await git(project, ["show", "\(revision):\(file)"])
    guard shown.success else { return nil }
    return try? JSJSON.parse(Data(shown.stdout.utf8))
  }

  func readPackageJson(_ project: String) -> PackageJsonDeps.Read {
    guard let data = try? Posix.read("\(project)/package.json"),
          let value = try? JSJSON.parse(Data(String(decoding: data, as: UTF8.self).utf8)) else { return .unreadable }
    return .parsed(value)
  }

  /// Which of the two files git tracks: `git checkout -- a b` is all or nothing.
  func trackedNpmOwnedFiles(_ project: String) async -> [String] {
    let listed = await git(project, ["ls-files", "--"] + Self.npmOwnedFiles)
    return listed.success ? lines(listed.stdout) : []
  }

  /// HEAD, the index and the working tree all different: the stash would carry what the plan
  /// cannot name. Could not look is not "all clear".
  func stagedApartFromWorkingTree(_ project: String, _ tracked: [String]) async -> Bool {
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
  func packageLines(_ project: String, _ entries: [PackageJsonDeps.Addition]) -> [String: String]? {
    guard case .parsed(let pkg) = readPackageJson(project) else { return nil }
    var map: [String: String] = [:]
    for entry in entries {
      map[entry.name] = PackageJsonDeps.sections.compactMap { section in
        PackageJsonDeps.dependencyRange(pkg, section, entry.name).map { "\(section.rawValue):\($0)" }
      }.joined(separator: " ")
    }
    return map
  }

  func diffNames(_ project: String, _ arguments: String...) async -> [String] {
    await diffNames(project, arguments)
  }

  func diffNames(_ project: String, _ arguments: [String]) async -> [String] {
    let result = await git(project, ["diff", "--name-only", "-z"] + arguments)
    return result.success ? records(result.stdout) : []
  }

  func conflictedFiles(_ project: String) async -> [String] { await diffNames(project, "--diff-filter=U") }

  // MARK: Plugins' snapshot

  /// `noteInstallSucceeded`: the project's own `npm install` got through after a failed run.
  public func noteInstallSucceeded(project: String) throws {
    let pending = readPendingInstall(project)
    guard !pending.head.isEmpty, pending.installFailed else { return }
    try markInstallPending(project, head: pending.head, reinstall: pending.reinstall, filesAtHead: pending.filesAtHead,
                           installFailed: false, putBack: pending.putBack)
  }
}
