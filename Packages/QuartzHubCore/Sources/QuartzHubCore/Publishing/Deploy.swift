import Foundation

/// The answer of a deploy run (`DeployResult`): whether it worked and the text for the output panel.
public struct DeployResult: Equatable, Sendable {
  public var success: Bool
  public var output: String
  /// Files the target refused to delete and still has (the output names each). A run with these
  /// is a success, not a clean one: the title says so (review 2026-11-11, N5).
  public var kept: [String]
  /// Stopped by the user (a document export's Abbrechen): not a failure, and the page must not
  /// call it "Veröffentlichung fehlgeschlagen" in red (review 2026-11-13, nebenbei).
  public var cancelled: Bool

  public init(success: Bool, output: String, kept: [String] = [], cancelled: Bool = false) {
    self.success = success
    self.output = output
    self.kept = kept
    self.cancelled = cancelled
  }

  /// A run that threw: cancelled when it was the export's own cancellation.
  static func failed(_ error: Error) -> DeployResult {
    DeployResult(success: false, output: PublishFailure.message(of: error),
                 cancelled: (error as? PublishFailure) == PublishFailure(L10n.t("main.exportCancelled")))
  }
}

/// Everything an adapter needs for one preview or run (`DeployContext`).
public struct DeployContext: Sendable {
  public var project: String
  public var target: PublishTarget
  /// The build output being published (or the staging folder with the documents in it).
  public var buildDir: String
  /// The connection's secret, nil when the target needs none.
  public var secret: String?
  /// The modes of the files and folders in `buildDir` are the ones wanted on the server; only the
  /// relay's upload asks for this.
  public var keepLocalModes = false
  /// The relay's folders below the target's own, top first: none may be a link on the server.
  public var relayFolders: [String]?
  /// Removing the relay: only these paths may go, and nothing is sent.
  public var onlyPaths: [String]?
  /// Removing the relay: the generation of the upload it takes down (`RelayGuard`).
  public var ownGeneration: String?
  public var progress: @Sendable (_ processed: Int, _ total: Int, _ currentFile: String?) -> Void = { _, _, _ in }

  public init(project: String, target: PublishTarget, buildDir: String, secret: String? = nil) {
    self.project = project
    self.target = target
    self.buildDir = buildDir
    self.secret = secret
  }

  public var destination: JSONObject { target.destination }
  public var deleteRemoved: Bool { destination["deleteRemoved"] == .bool(true) }
}

/// One way to publish (`DeployAdapter`). `preview` is per adapter because the adapters do not
/// agree on what a diff is: sftp, ftp and folder compare with the manifest, rsync asks the server,
/// a webhook has nothing to compare.
public protocol DeployAdapter: Sendable {
  func preview(_ context: DeployContext) async throws -> [DeployDiffEntry]
  func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult
}

/// The dispatcher (`deploy/index.ts`): finds the target and its adapter, checks what every
/// adapter needs, and applies the target's own exclusions in one place, so preview and run cannot
/// disagree about what is invisible.
public struct Deploy: Sendable {
  public let project: String
  public let connections: Connections
  /// By destination type; "sftp" with `transfer: "rsync"` asks for "rsync". A target whose type
  /// has none here says that there is no adapter for its type, as QuartzControl did for a type it
  /// did not know.
  public let adapters: [String: any DeployAdapter]
  let progress: @Sendable (_ targetId: String, _ processed: Int, _ total: Int, _ currentFile: String?) -> Void

  public init(project: String, connections: Connections, adapters: [String: any DeployAdapter],
              progress: @escaping @Sendable (String, Int, Int, String?) -> Void = { _, _, _, _ in }) {
    self.project = project
    self.connections = connections
    self.adapters = adapters
    self.progress = progress
  }

  static func adapterKey(_ destination: JSONObject) -> String {
    let type = JS.string(destination["type"])
    return type == "sftp" && destination["transfer"] == .string("rsync") ? "rsync" : type
  }

  func context(_ targetId: String, outputDir: String?) throws(PublishFailure) -> (DeployContext, any DeployAdapter) {
    guard let target = PublishTargets(project: project).get(targetId) else {
      throw PublishFailure(L10n.t("main.deployTargetMissing", ["id": targetId]))
    }
    let d = target.destination
    guard let adapter = adapters[Self.adapterKey(d)] else { throw PublishFailure(L10n.t("main.deployNoAdapter", ["type": JS.string(d["type"])])) }
    if let problem = Self.locationProblem(d) { throw PublishFailure(problem) }
    // Here rather than in the adapters, so the preview already offers every file again.
    let type = d["type"]?.stringValue
    if (type == "ftp" || (type == "sftp" && d["transfer"] != .string("rsync"))), let path = d["remotePath"]?.stringValue, JSText.startsWith(path, "~") {
      do {
        try DeployManifests(project: project).reanchorTilde(target.id)
      } catch {
        throw PublishFailure(PublishFailure.message(of: error))
      }
    }
    let secret = try target.connectionId.flatMap { id throws(PublishFailure) in try connections.secret(id) }
    var context = DeployContext(project: project, target: target,
                                buildDir: BuildOutputGuard.buildDirectory(project: project, outputDir: outputDir), secret: secret)
    let report = progress
    let id = target.id
    context.progress = { processed, total, file in report(id, processed, total, file) }
    return (context, adapter)
  }

  /// Where a target read from the file points, checked before preview and upload: the file
  /// travels with the project, so a target written by hand or by another tool never passed the
  /// form, and an empty rsync path is the server's root, with --delete (review 2026-11-11, M2;
  /// QuartzControl 1.3 checked only the whole root). A path saved before the rule knew "~" lands
  /// here too.
  static func locationProblem(_ d: JSONObject) -> String? {
    switch d["type"]?.stringValue {
    case "sftp", "ftp":
      let path = d["remotePath"]?.stringValue ?? ""
      switch RemotePath.problem(path, deleteRemoved: JS.truthy(d["deleteRemoved"])) {
      case .empty?: return L10n.t("main.deployEmptyPath")
      case .traversal?: return L10n.t("main.deployTraversalPath", ["path": path])
      case .wholeRoot?: return L10n.t("main.deployWholeRoot", ["path": path])
      case nil: return nil
      }
    case "git-branch":
      // It reaches `git fetch` and `git push`; one starting with "-" would be an option there
      // (review 2026-11-11, N2).
      return SavePublishTargetInput.isBranchName(d["branch"]) ? nil : L10n.t("main.deployBadBranch", ["branch": JS.string(d["branch"] ?? .string(""))])
    case "folder", "document":
      return SavePublishTargetInput.isAbsolutePath(d["path"]) ? nil : L10n.t("main.deployFolderPath", ["path": JS.string(d["path"] ?? .string(""))])
    default:
      return nil
    }
  }

  /// A git-branch target replaces the branch with one root commit, so leaving a file out would
  /// delete it from the live site; the form does not offer the field there.
  static func persistentExcludes(_ context: DeployContext) -> [String] {
    context.destination["type"] == .string("git-branch") ? [] : context.target.excludes
  }

  /// Every file adapter walks the build; a project never built gets a sentence, not "scandir".
  static func assertBuildExists(_ context: DeployContext) throws(PublishFailure) {
    if context.destination["type"] == .string("webhook") { return }
    if Posix.exists(context.buildDir) { return }
    throw PublishFailure(L10n.t("main.deployNoBuild", ["dir": context.buildDir]))
  }

  /// `previewDeploy`: the adapter's diff without the target's own exclusions, against the build
  /// plus its documents when it takes any along.
  public func preview(_ targetId: String, outputDir: String? = nil) async throws(PublishFailure) -> [DeployDiffEntry] {
    var (context, adapter) = try context(targetId, outputDir: outputDir)
    try Self.assertBuildExists(context)
    let staging = try DeployStaging.stage(project: project, target: context.target, buildDir: context.buildDir)
    defer { staging?.remove() }
    if let staging { context.buildDir = staging.dir }
    let hidden = Set(Self.persistentExcludes(context).map { Array($0.utf8) })
    let diff: [DeployDiffEntry]
    do {
      diff = try await adapter.preview(context)
    } catch {
      throw PublishFailure(PublishFailure.message(of: error))
    }
    return hidden.isEmpty ? diff : diff.filter { !hidden.contains(Array($0.path.utf8)) }
  }

  /// `runDeploy`: every failure becomes the output of a failed run, so it arrives in the same panel
  /// as the transfer's own errors.
  public func run(_ targetId: String, outputDir: String? = nil, excluding excludePaths: [String] = []) async -> DeployResult {
    await RunningWork.during(.deploy, project: project) { await runNow(targetId, outputDir: outputDir, excluding: excludePaths) }
  }

  func runNow(_ targetId: String, outputDir: String?, excluding excludePaths: [String]) async -> DeployResult {
    do throws(PublishFailure) {
      var (context, adapter) = try context(targetId, outputDir: outputDir)
      try Self.assertBuildExists(context)
      let staging = try DeployStaging.stage(project: project, target: context.target, buildDir: context.buildDir)
      defer { staging?.remove() }
      if let staging { context.buildDir = staging.dir }
      var excluded = excludePaths
      for path in Self.persistentExcludes(context) where !excluded.contains(where: { Array($0.utf8) == Array(path.utf8) }) { excluded.append(path) }
      var seen = Set<[UInt8]>()
      excluded = excluded.filter { seen.insert(Array($0.utf8)).inserted }
      let result: DeployResult
      do {
        result = try await adapter.run(context, excluding: excluded)
      } catch {
        return DeployResult.failed(error)
      }
      guard let notes = staging?.notes, !notes.isEmpty else { return result }
      return DeployResult(success: result.success, output: (notes + ["", result.output]).joined(separator: "\n"), kept: result.kept)
    } catch {
      return DeployResult(success: false, output: error.message)
    }
  }

  /// `runDirectoryUpload`: a folder that is not the build (the quartz-forms relay) through an
  /// existing target's way, below its path. The adapter does the work; what differs: a manifest of
  /// its own (`manifestKey`), never deletion on an upload (the relay's folder also holds what the
  /// server writes), none of the site's exclusions, sftp, ftp and folder only, and every file on
  /// every run with its local mode. With `remove`, only those paths are deleted, and with
  /// `ownGeneration` only while the relay there is still that upload's.
  public func directoryUpload(targetId: String, localDir: String, subdir: String, manifestKey: String,
                              remove: [String]? = nil, ownGeneration: String? = nil) async -> DeployResult {
    guard let target = PublishTargets(project: project).get(targetId) else {
      return DeployResult(success: false, output: L10n.t("main.deployTargetMissing", ["id": targetId]))
    }
    // keepLocalModes sets the mode of the folder it uploads into, which must not be the target's own.
    guard RemotePath.relaySubdir(subdir).map({ Array($0.utf8) == Array(subdir.utf8) }) ?? false else {
      return DeployResult(success: false, output: L10n.t("main.relaySubdirInvalid", ["subdir": subdir]))
    }
    let d = target.destination
    let type = JS.string(d["type"])
    guard ["sftp", "ftp", "folder"].contains(type) else { return DeployResult(success: false, output: L10n.t("main.relayTargetType", ["type": type])) }
    guard let adapter = adapters[Self.adapterKey(d)] else { return DeployResult(success: false, output: L10n.t("main.deployNoAdapter", ["type": type])) }
    // The adapter refuses the whole path and advises SFTP, where another folder would do; the
    // target's own path it says itself.
    if type == "sftp", d["transfer"] == .string("rsync"), RemotePath.rsyncUnsafeChar(JS.string(d["remotePath"])) == nil,
       let unsafe = RemotePath.rsyncUnsafeChar(subdir) {
      return DeployResult(success: false, output: JSText.test(unsafe, "[\(JSText.space)]")
        ? L10n.t("main.relaySubdirRsyncSpace", ["subdir": subdir])
        : L10n.t("main.relaySubdirRsyncChar", ["subdir": subdir, "char": unsafe]))
    }
    var destination = d
    destination["deleteRemoved"] = .bool(remove != nil)
    if type == "folder" {
      destination["path"] = .string(NodePath.join(JS.string(d["path"]), subdir))
    } else {
      destination["remotePath"] = .string(NodePath.join(JS.string(d["remotePath"]), subdir))
    }
    // A mode is no change a manifest sees, so it is forgotten first; then one of its own from the
    // first run (an unclaimed legacy manifest belongs to the site's target), or to remove, exactly
    // the paths to delete.
    let manifests = DeployManifests(project: project)
    manifests.forget(manifestKey)
    do {
      let dir = QuartzGuiDirectory(project: project)
      try dir.create()
      let file = dir.deployManifest(manifestKey)
      if let remove {
        let object = JSONObject(remove.map { ($0, .string("remove")) })
        try JSONStore.writeAtomic(Data(JSJSON.stringify(.object(object)).utf8), to: file)
      } else if !Posix.exists(file) {
        try JSONStore.writeAtomic(Data("{}\n".utf8), to: file)
      }
      let secret = try target.connectionId.flatMap { id throws(PublishFailure) in try connections.secret(id) }
      var object = target.object
      object["id"] = .string(manifestKey)
      object["destination"] = .object(destination)
      object["excludes"] = .array([])
      var context = DeployContext(project: project, target: PublishTarget(object: object), buildDir: localDir, secret: secret)
      // Also to remove: each folder on the way is asked whether it is a link, and the one-time
      // 0666 pass of a site's target stays off the relay's files.
      context.keepLocalModes = true
      context.onlyPaths = remove
      if remove != nil { context.ownGeneration = ownGeneration }
      if type != "folder" {
        let segments = JSText.split(subdir, "/")
        context.relayFolders = segments.indices.map { i in NodePath.join(([JS.string(d["remotePath"])] + segments[...i]).joined(separator: "/")) }
      }
      let report = progress
      context.progress = { processed, total, file in report(manifestKey, processed, total, file) }
      return try await adapter.run(context, excluding: [])
    } catch {
      return DeployResult(success: false, output: PublishFailure.message(of: error))
    }
  }
}
