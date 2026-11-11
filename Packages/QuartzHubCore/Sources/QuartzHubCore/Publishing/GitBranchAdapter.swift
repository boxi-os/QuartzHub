import Foundation

/// Publishing by pushing the build to a branch of the project's own "origin" (`deploy/gitBranch.ts`):
/// GitHub Pages (gh-pages), Codeberg Pages (pages) and GitLab (a CI job ships the files) differ in
/// the branch's name and what the provider does with it, not in the push.
///
/// Every deploy publishes one root commit and replaces what the branch held: the branch carries
/// only generated output, so a history of it costs size for nothing recoverable. Consequence by
/// design: nothing may live on that branch that the build does not make, except the CNAME GitHub
/// keeps for the domain its Pages settings name (`keepPagesDomain`). Built with plumbing (`write-tree`,
/// `commit-tree` without a parent) in a detached worktree per target, pushed as a sha, so no local
/// branch is left behind.
///
/// Machine answers (FETCH_HEAD, the tree, the commit) are read from stdout, the output shown is
/// git's own as it came (the rule of points 7a and 7b; QuartzControl read both from one stream).
public struct GitBranchAdapter: DeployAdapter {
  /// QuartzControl had none: a push that hung left the page "running" for good (review
  /// 2026-11-11, nebenbei 5). The network ones as Git-Sync's (`Sync.Deadlines`).
  public struct Deadlines: Sendable, Equatable {
    public var fetch: Duration = .seconds(10 * 60)
    /// The whole build goes up on every deploy.
    public var push: Duration = .seconds(30 * 60)
    /// worktree, write-tree, commit-tree: local, but `add -A` over a large build takes a while.
    public var local: Duration = .seconds(10 * 60)
    public init() {}
  }

  /// The custom domain GitHub's Pages settings name for the project's origin: `.some(nil)` none
  /// (or no Pages site), nil unknown (no token, no network, another host).
  public typealias PagesDomain = @Sendable (_ project: String) async -> String??

  let environment: ToolEnvironment
  let token: GitAuth.Token
  let now: @Sendable () -> Date
  let deadlines: Deadlines
  let pagesDomain: PagesDomain

  public init(environment: ToolEnvironment, token: @escaping GitAuth.Token, now: @escaping @Sendable () -> Date = { Date() },
              deadlines: Deadlines = Deadlines(), pagesDomain: @escaping PagesDomain = { _ in nil }) {
    self.environment = environment
    self.token = token
    self.now = now
    self.deadlines = deadlines
    self.pagesDomain = pagesDomain
  }

  struct GitError: Error, CustomStringConvertible {
    let description: String
  }

  /// No hook of the project runs for a deploy: on fetch and push one (pre-push,
  /// reference-transaction) would get the token in its environment and could ask `GIT_ASKPASS`
  /// for it, and the branch holds only generated output, so no hook of the sources is meant for it
  /// (review 2026-11-11, nebenbei 7; QuartzControl ran them). Git-Sync keeps them: there they are
  /// the user's own workflow. Through the environment rather than `-c`, so argv still starts with
  /// the subcommand that a timeout sentence names.
  static let withoutHooks = ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.hooksPath", "GIT_CONFIG_VALUE_0": "/dev/null"]

  func git(_ arguments: [String], in directory: String, _ extra: [String: String] = [:], timeout: Duration? = nil) async -> (CommandResult, String) {
    let command = environment.command("git", arguments, in: directory, timeout: timeout ?? deadlines.local)
      .adding(Self.withoutHooks).adding(extra)
    let result = await ProcessRunner.run(command)
    return (result, result.report(for: command))
  }

  /// Per target: two branch targets (live and staging) would fight over one registration. Inside
  /// .quartz-gui/, which is made with its ignore line first, as QuartzControl's quartzGuiDir did.
  static func worktree(_ context: DeployContext) throws -> String {
    let dir = QuartzGuiDirectory(project: context.project)
    try dir.create()
    return dir.file("branch-worktree-\(context.target.id)")
  }

  struct Staged {
    var tree: String
    var remoteTip: String
    var output: String
  }

  /// The branch fetched, the build staged, a tree written: what preview and run share.
  func stage(_ context: DeployContext, branch: String, worktree: String, auth: GitAuth) async throws -> Staged {
    var output = ""
    // A worktree from an interrupted deploy is cleared first: `worktree add` refuses a path that
    // is still registered.
    _ = await git(["worktree", "prune"], in: context.project)
    _ = await git(["worktree", "remove", "--force", worktree], in: context.project)
    try? FileManager.default.removeItem(atPath: worktree)

    // With the credential: a private repo would otherwise say "no such branch", and the deploy
    // would push a first root commit over an existing branch without the lease.
    // A full refspec behind "--": the name is never an option, and never a tag of that name.
    let (fetch, fetchText) = await git(["fetch", "origin", "--", "refs/heads/\(branch)"], in: context.project,
                                       auth.variables,
                                       timeout: deadlines.fetch)
    // A fetch that never answered says nothing about the branch; the push would only hang as well.
    if fetch.termination == .timedOut || fetch.termination == .cancelled { throw GitError(description: fetchText) }
    var remoteTip = ""
    if fetch.success {
      remoteTip = JS.trim((await git(["rev-parse", "FETCH_HEAD"], in: context.project)).0.stdout)
    }

    let (add, addText) = await git(["worktree", "add", "--detach", worktree], in: context.project)
    output += addText
    if !add.success { throw GitError(description: output) }

    for entry in Posix.entries(worktree) ?? [] where entry.name != ".git" {
      try? FileManager.default.removeItem(atPath: "\(worktree)/\(entry.name)")
    }
    try Posix.mkdirs(worktree)
    for entry in Posix.entries(context.buildDir) ?? [] {
      try TreeCopy.copy(from: "\(context.buildDir)/\(entry.name)", to: "\(worktree)/\(entry.name)", verbatimSymlinks: false)
    }
    if let domain = try await keepPagesDomain(context, remoteTip: remoteTip, worktree: worktree) {
      output += "\(L10n.t("main.branchKeptDomain", ["domain": domain]))\n"
    }

    // --force: whatever ignore rules there are (the worktree shares .git/info/exclude, and
    // core.excludesFile is global) must not drop a file from the live site.
    let (staged, stagedText) = await git(["add", "-A", "--force"], in: worktree)
    output += stagedText
    if !staged.success { throw GitError(description: output) }
    let (tree, treeText) = await git(["write-tree"], in: worktree)
    output += treeText
    if !tree.success { throw GitError(description: output) }
    return Staged(tree: JS.trim(tree.stdout), remoteTip: remoteTip, output: output)
  }

  /// GitHub keeps a custom domain of a branch site as a file: setting it (here or in GitHub's
  /// settings) commits "Create CNAME" onto the branch, and a deploy that replaces the branch
  /// without it drops the domain (measured 2026-11-11 against a test repository: the card showed
  /// github.io again, pages under the domain answered 404). QuartzControl assumed a domain set
  /// through the API survived; it does not. So the published CNAME is carried into each deploy
  /// unless the build brings its own.
  ///
  /// Only while GitHub's settings name the same domain: a CNAME that a build used to bring, or one
  /// another tool left on the branch, would otherwise stay for good, and GitHub would send the
  /// github.io address to a domain given up long ago (Review 2026-11-11 (2), N3). When GitHub
  /// cannot be asked, the file is carried as before; dropping it would drop a live domain.
  /// Returns the domain carried, for the run's output.
  func keepPagesDomain(_ context: DeployContext, remoteTip: String, worktree: String) async throws -> String? {
    guard !remoteTip.isEmpty, context.destination["provider"] == .string("github"),
          Posix.kind("\(worktree)/CNAME") == nil else { return nil }
    let (published, _) = await git(["cat-file", "blob", "\(remoteTip):CNAME"], in: context.project)
    guard published.success else { return nil }
    let domain = JS.trim(published.stdout)
    if case .some(let configured) = await pagesDomain(context.project),
       JS.trim(configured ?? "").lowercased() != domain.lowercased() || domain.isEmpty { return nil }
    try Posix.write("\(worktree)/CNAME", Data(published.stdout.utf8))
    return domain
  }

  func assertOrigin(_ project: String) async throws {
    if !(await git(["remote", "get-url", "origin"], in: project)).0.success {
      throw PublishFailure(L10n.t("main.branchNoOrigin"))
    }
  }

  /// The branch is typed by hand and every deploy force-pushes over it: the checked-out branch and
  /// origin's default are refused, a pages branch is never either.
  func assertBranchSafe(_ project: String, _ branch: String) async throws {
    let current = await git(["rev-parse", "--abbrev-ref", "HEAD"], in: project).0
    let originHead = await git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: project).0
    var protected: [String] = []
    if current.success { protected.append(JS.trim(current.stdout)) }
    if originHead.success { protected.append(JSText.replaceAll(JS.trim(originHead.stdout), #"\Aorigin/"#, with: "")) }
    if protected.contains(where: { Array($0.utf8) == Array(branch.utf8) }) {
      throw PublishFailure(L10n.t("main.branchProtected", ["branch": branch]))
    }
  }

  /// `-z` and `--no-renames`: without -z git quotes "ä.html", and a rename would be one line with
  /// two paths.
  static func parseNameStatus(_ raw: String) -> [DeployDiffEntry] {
    var entries: [DeployDiffEntry] = []
    let fields = JSText.split(raw, "\0")
    var i = 0
    while i + 1 < fields.count {
      let code = fields[i], path = fields[i + 1]
      i += 2
      if code.isEmpty || path.isEmpty { continue }
      if JSText.startsWith(code, "A") { entries.append(.init(path: path, status: .added)) }
      else if JSText.startsWith(code, "D") { entries.append(.init(path: path, status: .removed)) }
      else if JSText.startsWith(code, "M") || JSText.startsWith(code, "T") { entries.append(.init(path: path, status: .changed)) }
    }
    return entries
  }

  func branch(_ context: DeployContext) throws -> String {
    guard context.destination["type"] == .string("git-branch") else { throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "Branch"])) }
    // Deploy checks it too; this adapter is also called on its own.
    guard SavePublishTargetInput.isBranchName(context.destination["branch"]) else {
      throw PublishFailure(L10n.t("main.deployBadBranch", ["branch": JS.string(context.destination["branch"] ?? .string(""))]))
    }
    return JS.string(context.destination["branch"])
  }

  /// A real diff against what is published: the branch fetched, the written tree compared with the
  /// remote one. Costs a fetch, so it runs when asked.
  public func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] {
    let branch = try branch(context)
    try await assertOrigin(context.project)
    try await assertBranchSafe(context.project, branch)
    let worktree = try Self.worktree(context)
    let auth = try await GitAuth.forOrigin(project: context.project, environment: environment, token: token)
    defer { auth.cleanup() }
    do {
      let staged = try await stage(context, branch: branch, worktree: worktree, auth: auth)
      if staged.remoteTip.isEmpty {
        let (listing, text) = await git(["ls-tree", "-r", "--name-only", "-z", staged.tree], in: context.project)
        if !listing.success { throw GitError(description: text) }
        _ = await git(["worktree", "remove", "--force", worktree], in: context.project)
        return JSText.split(listing.stdout, "\0").filter { !$0.isEmpty }.map { .init(path: $0, status: .added) }
      }
      let (diff, text) = await git(["diff", "--name-status", "-z", "--no-renames", "\(staged.remoteTip)^{tree}", staged.tree], in: context.project)
      if !diff.success { throw GitError(description: text) }
      var entries = Self.parseNameStatus(diff.stdout)
      JS.sort(&entries) { JS.localeCompare($0.path, $1.path) }
      _ = await git(["worktree", "remove", "--force", worktree], in: context.project)
      return entries
    } catch {
      _ = await git(["worktree", "remove", "--force", worktree], in: context.project)
      throw error
    }
  }

  /// The exclusions are ignored on purpose: the branch is replaced by one root commit, so leaving
  /// a file out would delete it from the live site.
  public func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
    let branch = try branch(context)
    try await assertOrigin(context.project)
    try await assertBranchSafe(context.project, branch)
    let worktree = try Self.worktree(context)
    let auth = try await GitAuth.forOrigin(project: context.project, environment: environment, token: token)
    defer { auth.cleanup() }
    var output = ""
    let result: DeployResult
    do {
      let staged = try await stage(context, branch: branch, worktree: worktree, auth: auth)
      output += staged.output
      // Equal trees are an exact "already published"; a new root commit would always be new.
      if !staged.remoteTip.isEmpty {
        let remoteTree = await git(["rev-parse", "\(staged.remoteTip)^{tree}"], in: context.project).0
        if remoteTree.success && JS.trim(remoteTree.stdout) == staged.tree {
          _ = await git(["worktree", "remove", "--force", worktree], in: context.project)
          return DeployResult(success: true, output: "\(output)\n\(L10n.t("main.branchUnchanged"))")
        }
      }
      context.progress(0, 1, branch)
      let (commit, commitText) = await git(["commit-tree", staged.tree, "-m", "Deploy \(JS.isoString(now()))"], in: worktree)
      output += commitText
      if !commit.success {
        result = DeployResult(success: false, output: output)
      } else {
        let sha = JS.trim(commit.stdout)
        // A root commit never descends from the previous tip, so an existing branch needs force,
        // leased to the tip fetched above.
        let push = staged.remoteTip.isEmpty
          ? ["push", "origin", "\(sha):refs/heads/\(branch)"]
          : ["push", "--force-with-lease=refs/heads/\(branch):\(staged.remoteTip)", "origin", "\(sha):refs/heads/\(branch)"]
        let (pushed, pushText) = await git(push, in: worktree, auth.variables, timeout: deadlines.push)
        output += pushText
        context.progress(1, 1, branch)
        result = DeployResult(success: pushed.success, output: output)
      }
    } catch {
      result = DeployResult(success: false, output: "\(output)\n\(PublishFailure.message(of: error))")
    }
    _ = await git(["worktree", "remove", "--force", worktree], in: context.project)
    return result
  }
}
