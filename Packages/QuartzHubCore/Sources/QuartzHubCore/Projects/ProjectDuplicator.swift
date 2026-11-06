import Foundation

/// Copying a project, a port of `duplicateService.ts`. Not `cp -r`: four kinds of thing live in a
/// project folder and only two may travel.
///
/// - The project itself (quartz, config, stylesheets, installed plugins, the git repository) comes
///   along, and so do the parts of `.quartz-gui/` that are the design (authored frames, theme
///   presets, breakpoints).
/// - What belongs to the original's past or its outside world stays: the snapshot store, the
///   set-aside content folders, the publish targets and everything keyed to them. The targets
///   matter most: their credentials are app-wide, and a copy that inherited them could overwrite
///   the original's live site with its first "Veröffentlichen".
/// - What is derived and large (node_modules, the build output) is reinstalled and rebuilt.
///
/// The git repository comes along with only `origin` removed: `git init` instead would leave a
/// history that shares no commit with Quartz, and the core update merges from Quartz.
public enum ProjectDuplicator {
  /// Relative to the project root; everything else is copied. The reasons are QuartzControl's,
  /// at `SKIP` in duplicateService.ts; a new directory under `.quartz-gui/` must be decided here.
  static let skip: Set<String> = [
    "node_modules",
    "public",
    "content",
    ".quartz-gui/snapshots.git",
    ".quartz-gui/content-backups",
    ".quartz-gui/publish-targets.json",
    ".quartz-gui/deploy-manifest.json",
    // An absolute output directory pointing where the original exports its site: inherited, the
    // copy's first build emptied that folder (`quartz build --output` clears it first).
    ".quartz-gui/project-prefs.json",
    // The dev server's logs: a server that ran in the original.
    ".quartz-gui/logs",
    // A publish's build plus documents, normally gone after the run.
    ".quartz-gui/staging",
    // The forms relay's settings name one of the original's publish targets.
    ".quartz-gui/forms-relay.json"
  ]
  /// Deploy manifests per target (what lies on a server the copy never uploaded to) and a branch
  /// worktree a broken-off deploy left, whose `.git` file points into the original.
  /// Deliberately not skipped: `core-update.json` (its commit came along; see `afterInstallSucceeded`).
  static let skipPrefixes = [".quartz-gui/deploy-manifest-", ".quartz-gui/branch-worktree-"]

  public enum Content: Sendable, Equatable {
    /// One `index.md` with the project's name: an empty folder builds a site whose home page is a 404.
    case blank
    case copy(from: String)
    case symlink(to: String)
  }

  public struct Options: Sendable, Equatable {
    public var source: URL
    public var target: URL
    public var content: Content

    public init(source: URL, target: URL, content: Content) {
      self.source = source
      self.target = target
      self.content = content
    }
  }

  public static func duplicate(
    _ options: Options,
    environment: ToolEnvironment,
    installDeadline: Duration = ProjectCreator.Deadlines().install
  ) async -> ProjectCreator.Result {
    let source = URL(fileURLWithPath: FramePaths.resolve(options.source.path), isDirectory: true)
    let target = URL(fileURLWithPath: FramePaths.resolve(options.target.path), isDirectory: true)
    let manager = FileManager.default
    func refuse(_ sentence: String) -> ProjectCreator.Result {
      ProjectCreator.Result(success: false, output: sentence)
    }

    guard manager.fileExists(atPath: ConfigFile.path(project: source).path) else {
      return refuse(L10n.t("main.duplicateSourceNotAProject", ["path": source.path]))
    }
    // Asked before the copy: read after it, a config the app will not read left a half copy behind
    // carrying the original's remote (QuartzControl's twenty-first review, finding 6).
    do {
      _ = try await ConfigFile.read(project: source, runtime: environment.runtime)
    } catch {
      return refuse(L10n.t("main.duplicateSourceConfigUnreadable", ["path": source.path, "reason": message(of: error)]))
    }
    // A file at the target counts as taken too; QuartzControl's readdir threw on it.
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: target.path, isDirectory: &isDirectory),
       !isDirectory.boolValue || !((try? manager.contentsOfDirectory(atPath: target.path)) ?? []).isEmpty {
      return refuse(L10n.t("main.createTargetExists", ["path": target.path]))
    }
    if contains(source.path, target.path) || contains(target.path, source.path) {
      return refuse(L10n.t("main.duplicateNested"))
    }
    switch options.content {
    case .blank: break
    case .copy(let from), .symlink(let from):
      let resolved = from.isEmpty ? "" : FramePaths.resolve(absolute(from))
      if resolved.isEmpty || !manager.fileExists(atPath: resolved) {
        return refuse(L10n.t("main.contentSourceMissing", ["path": from]))
      }
      if contains(resolved, target.path) {
        return refuse(L10n.t("main.contentTargetInsideSource", ["target": target.path]))
      }
    }

    do {
      try manager.createDirectory(at: target, withIntermediateDirectories: true)
      try TreeCopy.copy(from: source, to: target, verbatimSymlinks: true) { relative in
        relative.isEmpty || (!skip.contains(relative) && !skipPrefixes.contains { relative.hasPrefix($0) })
      }
      try await ProjectPaths.repointProjectPaths(from: source, to: target, runtime: environment.runtime)

      // The copy must not push where the original pushes. Non-zero when there is no origin,
      // which is not a failure here.
      _ = await ProcessRunner.run(environment.command("git", ["remote", "remove", "origin"], in: target,
                                                      timeout: ProjectCreator.Deadlines().local))

      let content = ContentFolder.path(project: target)
      if (try? manager.destinationOfSymbolicLink(atPath: content.path)) != nil || manager.fileExists(atPath: content.path) {
        try manager.removeItem(at: content)
      }
      switch options.content {
      case .symlink(let to):
        try manager.createSymbolicLink(atPath: content.path, withDestinationPath: FramePaths.resolve(absolute(to)))
      case .copy(let from):
        try manager.createDirectory(at: content, withIntermediateDirectories: true)
        try TreeCopy.copy(from: URL(fileURLWithPath: FramePaths.resolve(absolute(from))), to: content, verbatimSymlinks: false)
      case .blank:
        try manager.createDirectory(at: content, withIntermediateDirectories: true)
        let page = "---\ntitle: \(target.lastPathComponent)\n---\n\n\(L10n.t("main.duplicateBlankContent"))\n"
        try Data(page.utf8).write(to: content.appendingPathComponent("index.md"))
      }
    } catch {
      return ProjectCreator.Result(success: false, output: message(of: error))
    }

    let install = environment.command("npm", ["install"], in: target, timeout: installDeadline)
    let installed = await ProcessRunner.run(install)
    guard installed.success else {
      return ProjectCreator.Result(success: false,
                                   output: "\(L10n.t("main.createInstallFailed"))\n\(installed.report(for: install))")
    }
    // Not worth failing a finished copy over: at worst the copy keeps the original's sentence.
    let gui = QuartzGuiDirectory(project: target)
    if let note = PendingInstall(object: JSONStore.read(gui.coreUpdate, orEmpty: .object).objectValue ?? JSONObject())
      .afterInstallSucceeded() {
      try? JSONStore.write(.object(note.object), to: gui.coreUpdate)
    }
    return ProjectCreator.Result(success: true, output: installed.report(for: install))
  }

  /// Neither direction of containment: copying a folder into itself loops or writes into what it
  /// reads. As Node's `relative`: by the text of the resolved paths.
  static func contains(_ parent: String, _ child: String) -> Bool {
    let parent = FramePaths.resolve(parent)
    let child = FramePaths.resolve(child)
    if parent == child { return true }
    guard child.hasPrefix(parent == "/" ? "/" : parent + "/") else { return false }
    return !child.dropFirst(parent == "/" ? 1 : parent.count + 1).hasPrefix("..")
  }

  private static func absolute(_ path: String) -> String {
    path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
  }

  private static func message(of error: Error) -> String {
    if let failure = error as? ConfigFile.Failure { return failure.message }
    if let failure = error as? Helper.Failure { return failure.description }
    return (error as NSError).localizedDescription
  }
}
