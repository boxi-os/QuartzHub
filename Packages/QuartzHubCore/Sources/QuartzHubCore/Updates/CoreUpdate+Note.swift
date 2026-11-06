import Foundation

/// The note between merge commit and warm-up build, and the stash that holds the two npm-owned
/// files during the merge.
extension CoreUpdate {
  /// What an earlier run left outstanding: the commit it belongs to ("" for nothing), the
  /// project's own packages it took out of package.json, whether the two npm-owned files were
  /// exactly HEAD's when that run started, whether its `npm install` failed, and which names of the
  /// list its npm wrote back before it failed.
  struct PendingInstall {
    var head = ""
    var reinstall: [PackageJsonDeps.Addition] = []
    var filesAtHead = false
    var installFailed = false
    var putBack: [String] = []
  }

  /// Whether a note's list still applies; two of the three end it, only one means somebody
  /// answered the question it asks.
  enum NoteVerdict { case stands, answered, unreadable }

  static let noteFile = "core-update.json"

  func noteURL(_ project: String) -> String { QuartzGuiDirectory(project: project).file(Self.noteFile) }

  /// Read checked, not cast: it lies in the user's project and becomes `npm install name@range`.
  func readPendingInstall(_ project: String) -> PendingInstall {
    let raw = JSONStore.read(noteURL(project), orEmpty: .object)
    var pending = PendingInstall()
    if let head = raw["installPendingFor"]?.stringValue, JSText.test(head, #"\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z"#) {
      pending.head = head
    }
    pending.filesAtHead = raw["filesAtHead"] == .bool(true)
    pending.installFailed = raw["installFailed"] == .bool(true)
    func safe(_ value: JSONValue?) -> String? {
      guard let text = value?.stringValue, !text.isEmpty, !JSText.startsWith(text, "-") else { return nil }
      return text
    }
    pending.reinstall = (raw["reinstall"]?.arrayValue ?? []).compactMap { entry in
      guard entry.objectValue != nil, let name = safe(entry["name"]), let range = safe(entry["range"]),
            let section = entry["section"]?.stringValue.flatMap(PackageJsonDeps.Section.init(rawValue:)) else { return nil }
      return PackageJsonDeps.Addition(name: name, section: section, range: range)
    }
    pending.putBack = (raw["putBack"]?.arrayValue ?? []).compactMap { safe($0) }
    return pending
  }

  func markInstallPending(_ project: String, head: String, reinstall: [PackageJsonDeps.Addition], filesAtHead: Bool,
                          installFailed: Bool = false, putBack: [String] = []) throws {
    let kept = PackageJsonDeps.unique(putBack).filter { name in reinstall.contains { $0.name == name } }
    try writeNote(project, .object(JSONObject([
      ("installPendingFor", .string(head)),
      ("reinstall", .array(reinstall.map { .object(JSONObject([("name", .string($0.name)), ("section", .string($0.section.rawValue)),
                                                               ("range", .string($0.range))])) })),
      ("filesAtHead", .bool(filesAtHead)), ("installFailed", .bool(installFailed)), ("putBack", .array(kept.map(JSONValue.string)))
    ])))
  }

  func clearInstallPending(_ project: String) throws {
    try writeNote(project, .object(JSONObject([("installPendingFor", .string("")), ("reinstall", .array([])), ("filesAtHead", .bool(false)),
                                               ("installFailed", .bool(false)), ("putBack", .array([]))])))
  }

  func writeNote(_ project: String, _ value: JSONValue) throws {
    let dir = try QuartzGuiDirectory(project: project).create()
    try JSONStore.write(value, to: "\(dir)/\(Self.noteFile)")
  }

  /// Whether somebody other than this app has taken package.json in hand since the note: a commit
  /// since its head whose diff touches a line with one of the names (`-G`, in quotes, because a
  /// bare name hits every line that contains it). The app's own amend and a merge commit show no
  /// diff here; a name its npm wrote back is skipped.
  func listTakenInHand(_ project: String, _ pending: PendingInstall) async -> NoteVerdict {
    if pending.head.isEmpty || pending.reinstall.isEmpty { return .stands }
    for entry in pending.reinstall where !pending.putBack.contains(entry.name) {
      let needle = "\"\(JSText.replaceAll(entry.name, #"[\\.*+?^${}()|\[\]]"#, template: #"\\$0"#))\""
      let touched = await git(project, ["log", "--max-count=1", "--format=%H", "-G\(needle)", "\(pending.head)..HEAD", "--", "package.json"])
      guard touched.success else { return .unreadable }
      if !trimmedStdout(touched).isEmpty { return .answered }
    }
    return .stands
  }

  /// The sentence about a list a run let go, with the reason it measured; only for what is
  /// actually gone from package.json.
  func droppedNote(_ project: String, _ verdict: NoteVerdict, _ pending: PendingInstall) async -> String {
    if verdict == .stands || pending.reinstall.isEmpty { return "" }
    let gone = PackageJsonDeps.absentFrom(readPackageJson(project), pending.reinstall)
    if gone.isEmpty { return "" }
    let packages = Self.labels(gone, pending.reinstall)
    return verdict == .unreadable ? L10n.t("main.updatePackagesDroppedUnreadable", ["packages": packages])
                                  : L10n.t("main.updatePackagesDropped", ["packages": packages])
  }

  // MARK: The stash

  enum HeldFiles {
    case held(sha: String)
    case clean
    case failed(output: String)
  }

  func stashMessage(_ mergeCommit: String) -> String { "\(Self.stashName) \(mergeCommit)" }

  func stashRef(_ project: String) async -> String? {
    let ref = await git(project, ["rev-parse", "--verify", "--quiet", "refs/stash"])
    let sha = ref.success ? trimmedStdout(ref) : ""
    return sha.isEmpty ? nil : sha
  }

  /// The commit a stash entry was made on: what `git stash pop` merges its diff against.
  func stashBase(_ project: String, _ entry: String = "refs/stash") async -> String {
    let base = await git(project, ["rev-parse", "\(entry)^"])
    return base.success ? trimmedStdout(base) : ""
  }

  func topStashSubject(_ project: String) async -> String {
    let subject = await git(project, ["log", "-1", "--format=%s", "refs/stash"])
    return subject.success ? trimmedStdout(subject) : ""
  }

  /// Where an entry of the app's stands in `git stash list`, as the `stash@{n}` a command needs;
  /// `from` skips the entry this run wrote itself, always the newest.
  func stashEntry(_ project: String, from: Int = 0) async -> String? {
    let list = await git(project, ["stash", "list", "--format=%s"])
    guard list.success else { return nil }
    let lines = JSText.split(list.stdout, "\n")
    for index in lines.indices where index >= from && JSText.includes(lines[index], Self.stashName) {
      return "stash@{\(index)}"
    }
    return nil
  }

  func holdNpmOwnedFiles(_ project: String, _ tracked: [String], _ mergeCommit: String) async -> HeldFiles {
    let before = await stashRef(project)
    let pushed = await git(project, ["stash", "push", "-m", stashMessage(mergeCommit), "--"] + tracked)
    let after = await stashRef(project)
    if let after, after != before { return .held(sha: after) }
    if !pushed.success { return .failed(output: pushed.output) }
    return .clean
  }

  /// Only the entry this run wrote, and only while it is still the newest.
  func releaseNpmOwnedFiles(_ project: String, _ held: HeldFiles) async -> Bool {
    guard case .held(let sha) = held else { return true }
    guard await stashRef(project) == sha else { return false }
    return await git(project, ["stash", "pop", "--index"]).success
  }

  func dropNpmOwnedFiles(_ project: String, _ held: HeldFiles) async {
    guard case .held(let sha) = held, await stashRef(project) == sha else { return }
    await git(project, ["stash", "drop"])
  }

  struct StashPop {
    var success: Bool
    var sentences: [String]
    var restored: String?
    var git: String
  }

  /// After an abort: the app's entry goes back only when it is the newest and was made on HEAD.
  func popCoreUpdateStash(_ project: String) async -> StashPop {
    let subject = await topStashSubject(project)
    let head = trimmedStdout(await git(project, ["rev-parse", "HEAD"]))
    let base = await stashBase(project)
    if !JSText.includes(subject, Self.stashName) || head.isEmpty || base != head {
      let entry = await stashEntry(project)
      return StashPop(success: true, sentences: entry.map { [L10n.t("main.updateStashLeftover", ["entry": $0])] } ?? [], restored: nil, git: "")
    }
    let popped = await git(project, ["stash", "pop", "--index"])
    guard popped.success else {
      let entry = await stashEntry(project) ?? "stash@{0}"
      return StashPop(success: false, sentences: [L10n.t("main.updateStashPopFailed", ["entry": entry])], restored: nil, git: popped.output)
    }
    let restored = L10n.t("main.updateStashRestored")
    guard let older = await stashEntry(project) else { return StashPop(success: true, sentences: [], restored: restored, git: popped.output) }
    let olderBase = head.isEmpty ? "" : await stashBase(project, older)
    let fits = !head.isEmpty && olderBase == head
    let blocked = fits ? await stashTouchesChangedFiles(project, older) : false
    let note = !fits ? L10n.t("main.updateStashLeftover", ["entry": older])
      : blocked ? L10n.t("main.updateStashUnderRestored", ["entry": older]) : L10n.t("main.updateStashFitsHeadBesides", ["entry": older])
    return StashPop(success: true, sentences: [note], restored: restored, git: popped.output)
  }

  func stashTouchesChangedFiles(_ project: String, _ entry: String) async -> Bool {
    let shown = await git(project, ["stash", "show", "--name-only", "-z", entry])
    guard shown.success else { return true }
    let changed = Set(await diffNames(project, "HEAD"))
    return records(shown.stdout).contains { changed.contains($0) }
  }

  enum StashAfterAbort {
    case free
    case occupied(files: [String])
    case abortRefused
  }

  /// Whether the abort button would carry the app's stash back: first whether it runs at all
  /// (git refuses over any file staged and changed again since), then whether a file of the stash
  /// would be in the way, unstaged and not in conflict.
  func abortOutcomeForStash(_ project: String) async -> StashAfterAbort {
    if !(await editedSinceMergeStopped(project)).isEmpty { return .abortRefused }
    let stashed = await git(project, ["stash", "show", "--name-only", "-z", "refs/stash"])
    guard stashed.success else { return .occupied(files: []) }
    let paths = records(stashed.stdout)
    if paths.isEmpty { return .free }
    let conflicted = await diffNames(project, "--diff-filter=U")
    let unstaged = (await diffNames(project, ["--", ] + paths)).filter { !conflicted.contains($0) }
    return unstaged.isEmpty ? .free : .occupied(files: unstaged)
  }

  /// What a run says about an entry of the app's it found before it began.
  func leftoverStashNote(_ project: String, before: String?) async -> String {
    let mine = await stashRef(project) != before
    guard let entry = await stashEntry(project, from: mine ? 1 : 0) else { return "" }
    let leftover = L10n.t("main.updateStashLeftover", ["entry": entry])
    if mine { return leftover }
    let head = trimmedStdout(await git(project, ["rev-parse", "HEAD"]))
    let ours = JSText.includes(await topStashSubject(project), Self.stashName)
    if !ours || head.isEmpty { return leftover }
    if await stashBase(project) != head { return leftover }
    if !(await mergeInProgress(project)) { return L10n.t("main.updateStashFitsHead", ["entry": entry]) }
    switch await abortOutcomeForStash(project) {
    case .free: return L10n.t("main.updateStashMine")
    case .abortRefused: return L10n.t("main.updateStashMineBlocked")
    case .occupied(let files):
      return files.isEmpty ? leftover : L10n.t("main.updateStashMineOccupied", ["entry": entry, "files": files.joined(separator: ", ")])
    }
  }
}
