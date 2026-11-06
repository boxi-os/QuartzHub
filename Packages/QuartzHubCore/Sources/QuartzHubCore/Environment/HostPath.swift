import Foundation

/// The PATH of the machine, made good enough to find git and rsync. A port of `ensureToolPath`,
/// `findExecutable` and `isCommandLineToolsStub` from `electron/main/services/environmentService.ts`.
///
/// An app started from the Dock or Finder inherits launchd's PATH (`/usr/bin:/bin:/usr/sbin:/sbin`),
/// where Homebrew's and MacPorts' tools are not. So when the inherited PATH finds no working git,
/// the user's login shell is asked, then a list of usual places. Unlike QuartzControl this does not
/// patch QuartzHub's own environment: it is a value, and `ToolEnvironment` builds the children's
/// environment from it.
public struct HostPath: Sendable, Equatable {
  public enum Source: String, Sendable {
    case inherited
    case loginShell = "login-shell"
    case probed
  }

  public var entries: [String]
  public var source: Source
  /// Directories added beyond what QuartzHub inherited.
  public var added: [String]

  public var joined: String { entries.joined(separator: ":") }

  /// What QuartzHub inherited, unchanged.
  public static func inherited(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> HostPath {
    HostPath(entries: split(environment["PATH"]), source: .inherited, added: [])
  }

  /// `ensureToolPath`: the inherited PATH if it finds a working git, otherwise extended by the
  /// login shell's PATH and then by the usual places. `xcodeSelect` and `candidates` are there for
  /// the tests.
  public static func resolve(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    xcodeSelect: String = "/usr/bin/xcode-select",
    candidates: [String]? = nil
  ) async -> HostPath {
    var path = inherited(environment)
    if await path.usableGit(xcodeSelect: xcodeSelect) != nil { return path }

    var known = Set(path.entries)
    // `known` grows inside the loop: a login shell's PATH lists the same directory twice often
    // enough (~/.local/bin from two dotfiles, measured by QuartzControl).
    func add(_ directories: [String]) -> [String] {
      var fresh: [String] = []
      for directory in directories where !directory.isEmpty && !known.contains(directory) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
        known.insert(directory)
        fresh.append(directory)
      }
      path.entries += fresh
      return fresh
    }

    let fromShell = add(await loginShellPath(environment))
    if await path.usableGit(xcodeSelect: xcodeSelect) != nil {
      path.source = .loginShell
      path.added = fromShell
      return path
    }
    let probed = add(candidates ?? candidateDirectories(home: environment["HOME"] ?? NSHomeDirectory()))
    path.source = await path.usableGit(xcodeSelect: xcodeSelect) != nil ? .probed : .inherited
    path.added = fromShell + probed
    return path
  }

  /// `findExecutable`: the absolute path of `name` on this PATH, like `command -v`. `skipping`
  /// leaves one directory out, which answers "what would the user's own node be?" while
  /// QuartzHub's runtime is in front.
  public func find(_ name: String, skipping: String? = nil) -> String? {
    let entries = skipping.map { skip in entries.filter { $0 != skip } } ?? entries
    return ProcessRunner.resolve(name, path: entries.joined(separator: ":"))
  }

  /// git on this PATH that is really git, not the macOS stub.
  func usableGit(xcodeSelect: String) async -> String? {
    guard let git = find("git") else { return nil }
    return await Self.isCommandLineToolsStub(git, xcodeSelect: xcodeSelect) ? nil : git
  }

  /// `/usr/bin/git` on a Mac without the command line tools opens Apple's installer instead of
  /// answering `--version`. `xcode-select -p` asks the same without the dialog: it prints the
  /// developer directory or fails. Only that one path is guarded; not cached, so installing the
  /// tools changes the answer without a restart. Not measured on a Mac without the tools (none at
  /// hand, neither for QuartzControl).
  public static func isCommandLineToolsStub(_ path: String, xcodeSelect: String = "/usr/bin/xcode-select") async -> Bool {
    guard path == "/usr/bin/git" else { return false }
    let answer = await ProcessRunner.run(Command(xcodeSelect, ["-p"], timeout: .seconds(5)))
    return !answer.success
  }

  /// The login shell's PATH: the only way to find a version manager's directories. `-ilc` reads
  /// both ~/.zprofile and ~/.zshrc; the marker skips whatever the dotfiles print; the timeout
  /// covers a shell that waits for input.
  public static func loginShellPath(_ environment: [String: String]) async -> [String] {
    guard let shell = environment["SHELL"], FileManager.default.isExecutableFile(atPath: shell) else { return [] }
    let answer = await ProcessRunner.run(Command(shell, ["-ilc", #"printf "__QH_PATH__%s\n" "$PATH""#],
                                                 environment: environment, timeout: .seconds(5)))
    guard answer.success,
          let line = answer.stdout.split(separator: "\n").first(where: { $0.hasPrefix("__QH_PATH__") })
    else { return [] }
    return split(String(line.dropFirst("__QH_PATH__".count)))
  }

  /// Where the common installers put things. Version-manager shims stay in the list: on a Mac
  /// without the command line tools, git often comes from Homebrew, MacPorts or Nix.
  public static func candidateDirectories(home: String) -> [String] {
    [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/opt/local/bin",
      "/nix/var/nix/profiles/default/bin",
      home + "/.nix-profile/bin",
      home + "/.local/bin",
      home + "/.volta/bin",
      home + "/.asdf/shims",
      home + "/.local/share/mise/shims",
      home + "/Library/Application Support/fnm",
      home + "/.local/share/fnm",
      home + "/.bun/bin"
    ]
  }

  static func split(_ path: String?) -> [String] {
    (path ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
  }
}
