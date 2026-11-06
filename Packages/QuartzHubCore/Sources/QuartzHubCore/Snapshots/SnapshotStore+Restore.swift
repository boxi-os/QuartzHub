import Foundation

extension SnapshotStore {
  // MARK: - Comparing

  /// Against the project as it is now, which needs the current state in the index first.
  public func diff(project: String, id: String) async throws -> [FileChange] {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in try await diffUnlocked(op, id) }
    }
  }

  func diffUnlocked(_ op: Operation, _ id: String) async throws -> [FileChange] {
    let commit = try await commitFor(op, id)
    let snapshot = await find(op, id)
    try await stage(op, try await ensureStore(op))
    let limitTo = snapshot.map { Self.isPartial($0.kind) } == true ? ["--"] + (await snapshotPaths(op, commit)) : []
    let result = await git(op, ["diff-index", "--cached", "--name-status", "-z", commit] + limitTo)
    guard result.success else { return [] }
    let parts = result.stdout.components(separatedBy: "\0").filter { !$0.isEmpty }
    var changes: [FileChange] = []
    var i = 0
    while i + 1 < parts.count {
      // <commit> -> index: "A" exists now and not in the snapshot.
      let status: FileChange.Status = switch parts[i].first {
      case "A": .addedSince
      case "D": .removedSince
      default: .modified
      }
      changes.append(FileChange(path: parts[i + 1], status: status))
      i += 2
    }
    return changes.sorted { Self.localeOrder($0.path, $1.path) }
  }

  /// `a.localeCompare(b)`: ICU collation.
  static func localeOrder(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [], range: nil, locale: Locale(identifier: "de")) == .orderedAscending
  }

  public func fileDiff(project: String, id: String, path: String) async throws -> String {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in
        let commit = try await commitFor(op, id)
        try await stage(op, try await ensureStore(op))
        return await git(op, ["diff", "--cached", commit, "--", path]).output
      }
    }
  }

  // MARK: - Restoring, deleting, exporting

  /// A snapshot of the current state first, so a restore can be undone. `paths` restores only
  /// these files; without it the whole snapshot (for an imported one, the file it holds), which
  /// also removes what the snapshot does not have. `resetProjectHead` also moves the project's own
  /// branch back to the commit the snapshot recorded.
  public func restore(project: String, id: String, paths: [String]? = nil, resetProjectHead: Bool = false) async throws -> PluginCommands.Result {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in try await restoreUnlocked(op, id, paths: paths, resetProjectHead: resetProjectHead) }
    }
  }

  func restoreUnlocked(_ op: Operation, _ id: String, paths: [String]?, resetProjectHead: Bool) async throws -> PluginCommands.Result {
    let project = op.project
    let commit = try await commitFor(op, id)
    let snapshot = await find(op, id)
    let effectivePaths: [String]? = if let paths, !paths.isEmpty {
      paths
    } else if let snapshot, Self.isPartial(snapshot.kind) {
      await snapshotPaths(op, commit)
    } else {
      nil
    }
    let touched: [String]
    if let effectivePaths {
      touched = effectivePaths
    } else {
      touched = try await diffUnlocked(op, id).map(\.path)
    }
    let settings = settings(project: project)
    _ = try await createUnlocked(op, kind: "restore", label: "")
    try await stage(op, settings)

    var output: [String] = []
    // git writes through a symlinked content folder: the link is parked for the write phase and
    // what git put under content/ is thrown away; a vault is not overwritten from a snapshot.
    let touchesContent = touched.contains { $0 == "content" || $0.hasPrefix("content/") }
    let write = { () async throws -> PluginCommands.Result? in
      if resetProjectHead, let head = snapshot?.projectHead {
        let (reset, command) = await projectGit(project, ["reset", "--hard", head])
        guard reset.success else { return PluginCommands.Result(success: false, output: reset.report(for: command)) }
        output.append(reset.output)
      }
      guard let effectivePaths else {
        let read = await git(op, ["read-tree", "-u", "--reset", commit])
        guard read.success else { return PluginCommands.Result(success: false, output: read.output) }
        output.append(read.output)
        return nil
      }
      // checkout brings files back but cannot delete one the snapshot never had.
      let inSnapshot = Set(await snapshotPaths(op, commit))
      let toRestore = effectivePaths.filter { inSnapshot.contains($0) }
      let toDelete = effectivePaths.filter { !inSnapshot.contains($0) }
      for batch in Self.batches(toRestore) {
        let checkout = await git(op, ["checkout", commit, "--"] + batch)
        guard checkout.success else { return PluginCommands.Result(success: false, output: checkout.output) }
        output.append(checkout.output)
      }
      for doomed in toDelete { try Self.removeFile("\(project)/\(doomed)") }
      for batch in Self.batches(toDelete) { await git(op, ["rm", "--cached", "--quiet", "--"] + batch) }
      return nil
    }
    let failure = resetProjectHead || touchesContent
      ? try await ContentFolder.withSymlinkParked(project: project) { try await write() }
      : try await write()
    if let failure { return failure }

    if settings.contentIsSymlink && touchesContent { output.append(L10n.t("main.snapshotVaultUntouched")) }
    // A snapshot holds the project's absolute paths of its moment; the repair needs no record of
    // where the project used to be.
    if touched.contains(where: { $0 == "quartz.config.yaml" || $0 == "quartz.lock.json" }) {
      try await repoint(project)
    }
    // node_modules is never in a snapshot.
    if touched.contains(where: { $0 == "package.json" || $0 == "package-lock.json" }) {
      let install = await npm(project)
      output.append(install.output)
      if !install.success { return PluginCommands.Result(success: false, output: output.joined(separator: "\n")) }
    }
    return PluginCommands.Result(success: true, output: JS.trim(output.joined(separator: "\n")))
  }

  static func batches(_ paths: [String]) -> [[String]] {
    stride(from: 0, to: paths.count, by: pathBatch).map { Array(paths[$0 ..< min($0 + pathBatch, paths.count)]) }
  }

  /// `fs.rm(path, { force: true })`: a missing file is fine, a folder is not.
  static func removeFile(_ url: String) throws {
    var info = stat()
    guard lstat(url, &info) == 0 else { return }
    if (info.st_mode & S_IFMT) == S_IFDIR { throw NodeFileError(code: EISDIR, syscall: "rm", path: url) }
    if unlink(url) != 0, errno != ENOENT { throw NodeFileError(code: errno, syscall: "rm", path: url) }
  }

  public func delete(project: String, id: String) async throws {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in
        await git(op, ["update-ref", "-d", "\(Self.refPrefix)\(id)"])
        // The commit is unreachable now; without a prune its objects stay for good.
        await git(op, ["gc", "--prune=\(pruneExpiry)", "--quiet"])
      }
    }
  }

  public func export(project: String, id: String, to target: String) async throws {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in
        let commit = try await commitFor(op, id)
        let result = await git(op, ["archive", "--format=zip", "--prefix=\(id)/", "-o", target, commit])
        guard result.success else { throw Failure(message: result.output) }
      }
    }
  }

  // MARK: - Migration

  /// The config backups of old (`.quartz-gui/backups/<timestamp>.yaml`) as snapshots of that one
  /// file, oldest first, each with its own date. The rename claims the work before it starts:
  /// only one caller wins it, and a crash after it leaves the files intact under `.migrated`.
  public func migrateConfigBackups(project: String) async throws -> Int {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in try await migrateUnlocked(op) }
    }
  }

  func migrateUnlocked(_ op: Operation) async throws -> Int {
    let legacy = "\(QuartzGuiDirectory(project: op.project).path)/backups"
    let claimed = legacy + ".migrated"
    guard rename(legacy, claimed) == 0 else { return 0 }
    _ = try await ensureStore(op)

    let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z\.yaml\z"#
    let files = (try FileManager.default.contentsOfDirectory(atPath: claimed)).filter { JSText.test($0, pattern) }.sorted()
    var imported = 0
    for file in files {
      let id = String(file.dropLast(".yaml".count))
      let hash = await ProcessRunner.run(environment.command(
        "git", ["--git-dir", op.store, "hash-object", "-w", "\(claimed)/\(file)"], in: op.project))
      let blob = JS.trim(hash.stdout)
      if blob.isEmpty { continue }
      let made = await ProcessRunner.run(environment.command(
        "git", ["--git-dir", op.store, "mktree"], in: op.project, input: Data("100644 blob \(blob)\tquartz.config.yaml\n".utf8)))
      let tree = JS.trim(made.stdout)
      if tree.isEmpty { continue }
      // The backup's own time, so the list keeps the history it imports.
      let when = Self.idToIsoDate(id)
      let env = when.map { ["GIT_AUTHOR_DATE": $0, "GIT_COMMITTER_DATE": $0] } ?? [:]
      let commit = JS.trim(await git(op, ["commit-tree", tree, "-m", "imported -"], env: env).stdout)
      if commit.isEmpty { continue }
      await git(op, ["update-ref", "\(Self.refPrefix)\(id)-0000", commit])
      imported += 1
    }
    _ = await pruneUnlocked(op)
    return imported
  }

  /// "2026-08-22T10-00-00-000Z" → "2026-08-22T10:00:00.000Z".
  static func idToIsoDate(_ id: String) -> String? {
    guard let match = JSText.matches(id, #"^(\d{4}-\d{2}-\d{2}T\d{2})-(\d{2})-(\d{2})-(\d{3})Z\z"#).first else { return nil }
    let g = match.groups.map { $0 ?? "" }
    return "\(g[1]):\(g[2]):\(g[3]).\(g[4])Z"
  }

  // MARK: - Retention

  /// Automatic snapshots thinned to a resolution that falls with age: all of the last day, one per
  /// day for a week, one per week up to eight, then one per month. Manual ones are never touched.
  public func pruneAutomatic(project: String) async throws -> Int {
    try await Self.lock.run(project) {
      try await withIndex(project) { op in await pruneUnlocked(op) }
    }
  }

  static func retentionBucket(age: TimeInterval, createdAt: Date) -> String? {
    if age < day { return nil }
    let iso = JS.isoString(createdAt)
    if age < 7 * day { return "day-\(iso.prefix(10))" }
    if age < 56 * day { return "week-\(Int((createdAt.timeIntervalSince1970 * 1000 / (7 * day * 1000)).rounded(.down)))" }
    return "month-\(iso.prefix(7))"
  }

  func pruneUnlocked(_ op: Operation) async -> Int {
    let now = clock.now()
    var kept: Set<String> = []
    var doomed: [String] = []
    // Newest first: the first to claim a bucket survives it.
    for snapshot in await listUnlocked(op) where !Self.keptKinds.contains(snapshot.kind) {
      guard let createdAt = Self.date(snapshot.createdAt),
            let bucket = Self.retentionBucket(age: now.timeIntervalSince(createdAt), createdAt: createdAt) else { continue }
      if kept.contains(bucket) { doomed.append(snapshot.id) } else { kept.insert(bucket) }
    }
    for id in doomed { await git(op, ["update-ref", "-d", "\(Self.refPrefix)\(id)"]) }
    if !doomed.isEmpty { await git(op, ["gc", "--prune=\(pruneExpiry)", "--quiet"]) }
    return doomed.count
  }
}
