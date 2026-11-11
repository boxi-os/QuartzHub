import Foundation

/// Where Node, git and the helpers that travel with QuartzHub are. In the package they sit in
/// `Contents/Resources/{node,git,helpers}` (`scripts/package.sh`); in a development build they are
/// in the repository (`Runtime/`, `Helpers/dist/`), found from this source file's path, the same way
/// the tests find `Runtime/node`.
public struct RuntimeLocation: Sendable, Equatable {
  /// The Node tree: `bin/node`, `bin/npm`, `bin/npx`, `lib/node_modules/npm`.
  public var node: String
  /// The git tree from dugite-native: `bin/git`, `libexec/git-core`, `share/git-core/templates`.
  public var git: String
  public var helpers: String

  public init(node: String, git: String, helpers: String) {
    self.node = node
    self.git = git
    self.helpers = helpers
  }

  public static let current: RuntimeLocation = {
    #if DEBUG
    if !bundled.isComplete { return repository }
    #endif
    // A release build knows only its bundle: an incomplete package says so at the start
    // (`isComplete`) instead of finding Node in the repository of the Mac it was built on
    // (review 2026-11-11, N4).
    return bundled
  }()

  /// Inside the app: `Contents/Resources/{node,git,helpers}`.
  public static let bundled: RuntimeLocation = {
    let resources = Bundle.main.resourceURL.map { Posix.path($0) } ?? ""
    return RuntimeLocation(node: "\(resources)/node", git: "\(resources)/git", helpers: "\(resources)/helpers")
  }()

  /// The repository's copies, for development builds and tests. In a release build the bundle's,
  /// so no path of the build machine is in the binary.
  public static let repository: RuntimeLocation = {
    #if DEBUG
    var root = #filePath
    for _ in 0..<6 { root = NodePath.dirname(root) }
    return RuntimeLocation(node: "\(root)/Runtime/node", git: "\(root)/Runtime/git", helpers: "\(root)/Helpers/dist")
    #else
    return bundled
    #endif
  }()

  /// Node, git and the helpers are all there.
  public var isComplete: Bool {
    FileManager.default.isExecutableFile(atPath: "\(node)/bin/node") && FileManager.default.isExecutableFile(atPath: "\(git)/bin/git")
      && FileManager.default.fileExists(atPath: helpers)
  }

  public var nodeBin: String { "\(node)/bin" }

  /// The version of the npm that travels with Node, from its package.json.
  public var npmVersion: String? {
    guard case .ok(let value) = JSONStore.peek("\(node)/lib/node_modules/npm/package.json") else { return nil }
    return value["version"]?.stringValue
  }
}

/// The environment every child process gets: the machine's PATH (`HostPath`), with QuartzHub's Node
/// in front unless the user chose their own, and git's variables when the bundled git is used. A
/// port of what `nodeRuntime.ts` and `gitRuntime.ts` did to `process.env`, as a value.
///
/// No shims: QuartzControl needed `node`/`npm`/`npx` scripts that start Electron as Node. Here the
/// three are in `node/bin`, and npm's `#!/usr/bin/env node` finds the `node` next to it because
/// that directory is first on PATH (decisions/phase-1-geruest.md).
public struct ToolEnvironment: Sendable, Equatable {
  /// `settings.json` `nodeRuntime`, as QuartzControl writes it.
  public enum NodeMode: String, Sendable {
    /// Quartz and npm run on the Node that travels with QuartzHub. The default: Node has a hard
    /// floor (Quartz needs >= 22), and a project's `.node-version` would let a version manager pick
    /// per directory something nobody of us wrote (`nodeRuntime.ts`).
    case embedded
    case system
  }

  public var base: [String: String]
  public var hostPath: HostPath
  public var nodeMode: NodeMode
  public var runtime: RuntimeLocation
  public var git: GitRuntime?
  /// The bundled git that is there and does not run; nil when it was not needed or is not there.
  public var bundledGitFailure: BundledGitFailure?

  public init(base: [String: String], hostPath: HostPath, nodeMode: NodeMode, runtime: RuntimeLocation,
              git: GitRuntime?, bundledGitFailure: BundledGitFailure?) {
    self.base = base
    self.hostPath = hostPath
    self.nodeMode = nodeMode
    self.runtime = runtime
    self.git = git
    self.bundledGitFailure = bundledGitFailure
  }

  /// Once at start: PATH first, then git (a git only the login shell knows must be visible by
  /// then), then Node. The same order as QuartzControl's `index.ts`.
  public static func resolve(
    base: [String: String] = ProcessInfo.processInfo.environment,
    runtime: RuntimeLocation = .current,
    nodeMode: NodeMode
  ) async -> ToolEnvironment {
    let hostPath = await HostPath.resolve(base)
    let git = await GitRuntime.resolve(hostPath: hostPath, bundle: runtime.git, base: base)
    return ToolEnvironment(base: base, hostPath: hostPath, nodeMode: nodeMode, runtime: runtime,
                           git: git.runtime, bundledGitFailure: git.failure)
  }

  /// The directory in front of PATH for Node, or nil when the machine's own is used.
  public var nodeBinDirectory: String? { nodeMode == .embedded ? runtime.nodeBin : nil }

  public var path: [String] {
    var entries: [String] = []
    if let nodeBinDirectory { entries.append(nodeBinDirectory) }
    if let git, git.source == .bundled { entries.append(git.binDirectory) }
    for entry in hostPath.entries where !entries.contains(entry) { entries.append(entry) }
    return entries
  }

  /// The whole environment of a child.
  public var variables: [String: String] {
    var variables = base
    variables["PATH"] = path.joined(separator: ":")
    if let git { variables.merge(git.variables) { _, new in new } }
    return variables
  }

  /// A command in this environment.
  public func command(_ executable: String, _ arguments: [String] = [], in directory: String? = nil,
                      input: Data? = nil, timeout: Duration? = nil) -> Command {
    Command(executable, arguments, in: directory, environment: variables, input: input, timeout: timeout)
  }

  /// After the setting changed. Only later commands see it; a running dev server keeps the
  /// environment it was started with (the setting says so, as in QuartzControl).
  public func with(nodeMode: NodeMode) -> ToolEnvironment {
    var copy = self
    copy.nodeMode = nodeMode
    return copy
  }
}
