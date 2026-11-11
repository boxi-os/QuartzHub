import Foundation

/// Cancelling a merge the core update left standing, and the sentences for git's refusals.
extension CoreUpdate {
  public func abort(project: String) async throws -> AbortResult {
    let busy = L10n.t("main.updateAlreadyRunning")
    return try await RunningWork.during(.coreUpdate, project: project) {
      try await whileHolding(project, busy: { AbortResult(success: false, output: busy, sentences: [busy]) }) {
        try await ContentFolder.withSymlinkParked(project: project) { await self.abortParked(project) }
      }
    }
  }

  func abortParked(_ project: String) async -> AbortResult {
    let losing = await stagedOutsideMerge(project)
    let uncheckedAfter = losing.unchecked ? [L10n.t("main.updateAbortStagedUnchecked")] : []
    let uncheckedBlocked = losing.unchecked ? [L10n.t("main.updateAbortStagedUncheckedBlocked")] : []
    let result = await git(project, ["merge", "--abort"], env: textVariables)
    if !result.success {
      let why = Self.explain(result.output, editedSinceMerge: await editedSinceMergeStopped(project), ownStaged: losing.files,
                             untrackedInTheWay: await untrackedInTheWay(project), ownStagedOnMerge: losing.onTop,
                             declaredToAdd: await intentToAdd(project))
      let sentences = JSText.split(why, "\n\n").map(JS.trim).filter { !$0.isEmpty } + uncheckedBlocked
      return AbortResult(success: false, output: ([why + result.output] + uncheckedBlocked).joined(separator: "\n\n"), sentences: sentences)
    }
    let popped = await popCoreUpdateStash(project)
    let dropped = losing.files.isEmpty ? [] : [L10n.t("main.updateAbortDroppedStaged", ["files": losing.files.joined(separator: ", ")])]
    let sentences = popped.sentences + dropped + uncheckedAfter + (popped.restored.map { [$0] } ?? [])
    let gitText = [JS.trim(result.output), JS.trim(popped.git)].filter { !$0.isEmpty }.joined(separator: "\n")
    return AbortResult(success: popped.success, output: (sentences + [gitText]).filter { !$0.isEmpty }.joined(separator: "\n\n"),
                       sentences: sentences)
  }

  /// git's own wording for the failures a user can act on is buried in other output or points at a
  /// state QuartzHub repaired behind their back. The names come from the lists the abort asks for
  /// itself: git stops at the first entry it cannot reset.
  static func explain(_ output: String, editedSinceMerge: [String] = [], ownStaged: [String] = [], untrackedInTheWay: [String] = [],
                      ownStagedOnMerge: [String] = [], declaredToAdd: [String] = []) -> String {
    if JSText.test(output, "beyond a symbolic link") { return L10n.t("main.updateBlockedBySymlink") }
    if JSText.test(output, "(?i)local changes to the following files would be overwritten") { return L10n.t("main.updateBlockedByLocalChanges") }
    if JSText.test(output, "(?i)unmerged files|MERGE_HEAD exists|not possible because you have") { return L10n.t("main.updateMergeUnfinished") }
    guard JSText.test(output, #"(?i)not uptodate\. Cannot merge|Could not reset index file"#) else { return "" }

    // `/^…$/gm` and JavaScript's ".": a line, and no line end inside it.
    let line = #"[^\n\r\x{2028}\x{2029}]"#
    let end = #"(?=[\n\r\x{2028}\x{2029}]|\z)"#
    let named = { (pattern: String) in JSText.matches(output, JSText.lineStart + pattern + end).compactMap { $0.groups[1] } }
    let untracked = PackageJsonDeps.unique(named("error: Untracked working tree file '(\(line)+)' would be overwritten by merge\\.") + untrackedInTheWay)
    let untrackedSentence = untracked.isEmpty ? [] : [L10n.t("main.updateAbortBlockedByUntracked", ["files": untracked.joined(separator: ", ")])]
    let declaredSentence = declaredToAdd.isEmpty ? [] : [L10n.t("main.updateAbortBlockedByIntentToAdd", ["files": declaredToAdd.joined(separator: ", ")])]
    let files = PackageJsonDeps.unique(named("error: Entry '(\(line)+)' not uptodate\\. Cannot merge\\.") + editedSinceMerge)
      .filter { !declaredToAdd.contains($0) }
    if files.isEmpty {
      let rest = untrackedSentence + declaredSentence
      return rest.isEmpty ? L10n.t("main.updateAbortBlockedByEdit") : rest.joined()
    }
    // Three classes: the merge's own files, files the user staged, and the merge's files with
    // something staged on top.
    let onMerge = files.filter { ownStagedOnMerge.contains($0) }
    let own = files.filter { ownStaged.contains($0) && !ownStagedOnMerge.contains($0) }
    let merged = files.filter { !ownStaged.contains($0) }
    var sentences: [String] = []
    if !merged.isEmpty { sentences.append(L10n.t("main.updateAbortBlockedByEditNamed", ["files": merged.joined(separator: ", ")])) }
    if !own.isEmpty { sentences.append(L10n.t("main.updateAbortBlockedByOwnStaged", ["files": own.joined(separator: ", ")])) }
    if !onMerge.isEmpty { sentences.append(L10n.t("main.updateAbortBlockedByOwnStagedOnMerge", ["files": onMerge.joined(separator: ", ")])) }
    return (sentences + untrackedSentence + declaredSentence).joined()
  }

  /// What `merge --abort` (`reset --merge`) takes away: a file staged that is not the merge's, or
  /// the merge's with something staged on top. `unchecked`: a file whose question had no answer.
  func stagedOutsideMerge(_ project: String) async -> (files: [String], onTop: [String], unchecked: Bool) {
    let staged = await diffNames(project, "--cached", "--no-renames", "HEAD")
    if staged.isEmpty { return ([], [], false) }
    let conflicted = Set(await diffNames(project, "--diff-filter=U"))
    let fromMerge = Set(await diffNames(project, "--no-renames", "HEAD...MERGE_HEAD"))
    let candidates = staged.filter { fromMerge.contains($0) && !conflicted.contains($0) }
    let answer = await stagedOnTopOfMerge(project, candidates)
    let onTop = PackageJsonDeps.unique(answer.onTop)
    return (staged.filter { (!fromMerge.contains($0) && !conflicted.contains($0)) || onTop.contains($0) }, onTop, !answer.unchecked.isEmpty)
  }

  static let oidPattern = #"\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z"#

  /// Mode and object of each path, from `ls-files -s -z` or `ls-tree -z`.
  func entries(_ project: String, _ arguments: [String], _ paths: [String], pick: ([String]) -> String) async -> [String: String]? {
    let result = await git(project, arguments + ["--"] + paths)
    guard result.success else { return nil }
    var map: [String: String] = [:]
    for record in records(result.stdout) {
      let tab = JSText.indexOf(record, "\t") ?? -1
      map[JSText.slice(record, tab + 1)] = pick(JSText.split(JSText.slice(record, 0, max(tab, 0)), " "))
    }
    return map
  }

  func stagedOnTopOfMerge(_ project: String, _ files: [String]) async -> (onTop: [String], unchecked: [String]) {
    if files.isEmpty { return ([], []) }
    func field(_ fields: [String], _ i: Int) -> String { i < fields.count ? fields[i] : "undefined" }
    let index = await entries(project, ["ls-files", "-s", "-z"], files) { "\(field($0, 0)) \(field($0, 1))" }
    let theirs = await entries(project, ["ls-tree", "-z", "MERGE_HEAD"], files) { "\(field($0, 0)) \(field($0, 2))" }
    let rest = index != nil && theirs != nil ? files.filter { index![$0] != theirs![$0] } : files
    if rest.isEmpty { return ([], []) }
    let merged = await git(project, ["merge-tree", "--write-tree", "HEAD", "MERGE_HEAD"])
    guard let tree = JSText.split(merged.stdout, "\n").map(JS.trim).first(where: { JSText.test($0, Self.oidPattern) }) else {
      return ([], await plainThreeWayMatches(project, rest, index))
    }
    guard let result = await entries(project, ["ls-tree", "-z", tree], rest, pick: { "\(field($0, 0)) \(field($0, 2))" }), let index else {
      return ([], rest)
    }
    return (rest.filter { result[$0] != index[$0] }, [])
  }

  /// Without `merge-tree --write-tree`: each file merged by hand with `merge-file` and compared
  /// with what is staged; a file that cannot be asked stays unchecked.
  func plainThreeWayMatches(_ project: String, _ files: [String], _ index: [String: String]?) async -> [String] {
    guard let index else { return files }
    func oid(_ text: String) -> String? { JSText.split(text, "\n").map(JS.trim).first { JSText.test($0, Self.oidPattern) } }
    let base = await git(project, ["merge-base", "HEAD", "MERGE_HEAD"])
    guard base.success, let baseRev = oid(base.stdout) else { return files }
    func trees(_ rev: String) async -> [String: String]? {
      await entries(project, ["ls-tree", "-z", rev], files) { fields in
        "\(fields.count > 0 ? fields[0] : "undefined") \(fields.count > 2 ? fields[2] : "undefined")"
      }
    }
    guard let ours = await trees("HEAD"), let theirs = await trees("MERGE_HEAD"), let ancestors = await trees(baseRev) else { return files }
    var template = Array("\(NSTemporaryDirectory())quartzhub-merge-XXXXXX".utf8CString)
    guard let made = mkdtemp(&template) else { return files }
    let dir = String(cString: made)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let env = ["GIT_DIR": "\(project)/.git"]
    var unchecked: [String] = []
    for file in files {
      let sides = [ours[file], ancestors[file], theirs[file]]
      let mode = { (entry: String) in JSText.split(entry, " ")[0] }
      guard let staged = index[file], sides.allSatisfy({ $0 != nil && mode($0!) == mode(staged) }) else {
        unchecked.append(file)
        continue
      }
      var unpacked: [String] = []
      for side in sides {
        let result = await git(nil, ["unpack-file", JSText.split(side!, " ")[1]], env: env, in: dir)
        if result.success, let name = JSText.split(result.stdout, "\n").map(JS.trim).first(where: { JSText.startsWith($0, ".merge_file_") }) {
          unpacked.append(name)
        }
      }
      if unpacked.count < 3 {
        unchecked.append(file)
        continue
      }
      let mergedFile = await git(nil, ["merge-file"] + unpacked, env: env, in: dir)
      let hashed = mergedFile.success ? await git(nil, ["hash-object", unpacked[0]], env: env, in: dir) : nil
      if hashed == nil || !hashed!.success || oid(hashed!.stdout) != JSText.split(staged, " ")[1] { unchecked.append(file) }
    }
    return unchecked
  }

  /// What git refuses the abort over: staged, changed again since, not unmerged, not declared.
  func editedSinceMergeStopped(_ project: String) async -> [String] {
    let unmerged = Set(await diffNames(project, "--diff-filter=U"))
    let staged = Set(await diffNames(project, "--cached"))
    let declared = Set(await intentToAdd(project))
    return (await diffNames(project, "--diff-filter=d")).filter { staged.contains($0) && !unmerged.contains($0) && !declared.contains($0) }
  }

  func intentToAdd(_ project: String) async -> [String] { await diffNames(project, "--diff-filter=A") }

  /// A file HEAD has, taken out of the index and still in the folder: the reset would write over it.
  func untrackedInTheWay(_ project: String) async -> [String] {
    let gone = await diffNames(project, "--cached", "--no-renames", "--diff-filter=D", "HEAD")
    if gone.isEmpty { return [] }
    let result = await git(project, ["ls-files", "--others", "-z", "--"] + gone)
    return result.success ? records(result.stdout) : []
  }
}
