import Foundation

/// Which git QuartzHub uses. A port of `electron/main/services/gitRuntime.ts`: the machine's if it
/// answers `git --version`, otherwise the one that travels with QuartzHub. The reverse rule to
/// Node's, for the reverse reason: git has no version floor, but it carries the user's setup
/// (`~/.gitconfig` may name credential helpers only their installation has; the bundle has no
/// `git-credential-osxkeychain`). The source that is sure to meet the requirement wins.
public struct GitRuntime: Sendable, Equatable {
  public enum Source: String, Sendable {
    case host
    case bundled
  }

  public var source: Source
  /// The binary QuartzHub will run.
  public var path: String
  public var version: String?
  /// What the bundled git needs set; empty for the machine's.
  public var variables: [String: String]

  var binDirectory: String { NodePath.dirname(path) }

  /// Answers "which git" once at start. `hostPath` must be resolved already: a git that only the
  /// login shell's PATH reaches is invisible before.
  public static func resolve(
    hostPath: HostPath,
    bundle: String,
    base: [String: String],
    xcodeSelect: String = "/usr/bin/xcode-select"
  ) async -> (runtime: GitRuntime?, failure: BundledGitFailure?) {
    var hostEnvironment = base
    hostEnvironment["PATH"] = hostPath.joined
    // The stub in /usr/bin/git is skipped, not run: `--version` there opens an installer.
    if let host = hostPath.find("git"), !(await HostPath.isCommandLineToolsStub(host, xcodeSelect: xcodeSelect)) {
      let answer = await probe(host, environment: hostEnvironment)
      if let version = answer.version {
        return (GitRuntime(source: .host, path: host, version: version, variables: [:]), nil)
      }
    }

    let path = "\(bundle)/bin/git"
    guard FileManager.default.fileExists(atPath: path) else { return (nil, nil) }
    // Without these two git looks under "/" (measured in Phase 1: "templates not found in
    // //share/git-core/templates"; QuartzControl: "unable to find remote helper for 'https'").
    // Only the Linux bundle has its own certificates; macOS uses the system's.
    let variables = [
      "GIT_EXEC_PATH": "\(bundle)/libexec/git-core",
      "GIT_TEMPLATE_DIR": "\(bundle)/share/git-core/templates"
    ]
    let environment = hostEnvironment.merging(variables) { _, new in new }
    let answer = await probe(path, environment: environment)
    guard let version = answer.version else {
      return (nil, BundledGitFailure(path: path, reason: answer.loaderFailure ? .incompatible : .broken))
    }
    // `--version` loads nothing; cloning needs git-remote-https and what it links.
    guard await httpsHelperLoads(bundle: bundle, environment: environment) else {
      return (nil, BundledGitFailure(path: path, reason: .incompatible))
    }
    return (GitRuntime(source: .bundled, path: path, version: version, variables: variables), nil)
  }

  /// The messages of a loader that could not load the file, as opposed to a program with a fault.
  static func isLoaderFailure(_ text: String) -> Bool {
    let patterns = ["error while loading shared libraries", "cannot open shared object", "dyld: Library not loaded",
                    "Library not loaded:"]
    return patterns.contains { text.contains($0) } || text.range(of: #"version `GLIBC_[\d.]+' not found"#, options: .regularExpression) != nil
  }

  static func probe(_ path: String, environment: [String: String]) async -> (version: String?, loaderFailure: Bool) {
    let answer = await ProcessRunner.run(Command(path, ["--version"], environment: environment, timeout: .seconds(10)))
    if answer.success {
      let line = answer.stdout.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
      return (line.flatMap { $0.isEmpty ? nil : $0 }, false)
    }
    return (nil, answer.termination == .exited(127) || isLoaderFailure(answer.output))
  }

  /// The helper without arguments complains about the missing URL (exit 1, QuartzControl measured)
  /// after the loader has loaded it completely; a missing library ends with 127 before that.
  static func httpsHelperLoads(bundle: String, environment: [String: String]) async -> Bool {
    let helper = "\(bundle)/libexec/git-core/git-remote-https"
    guard FileManager.default.fileExists(atPath: helper) else { return false }
    let answer = await ProcessRunner.run(Command(helper, environment: environment, timeout: .seconds(10)))
    switch answer.termination {
    case .exited(127), .couldNotStart: return false
    default: return !isLoaderFailure(answer.output)
    }
  }

  /// For a git call whose text QuartzHub reads (`explainGitFailure`, "not a git repository"): git
  /// translates the sentences matched there (its po/de.po, v2.53.0). `LC_MESSAGES=C` and nothing
  /// wider, so names and encodings stay the user's; `LANGUAGE` emptied, because gettext asks it
  /// first; a set `LC_ALL` moves to `LC_CTYPE`, because it would override both. A port of
  /// `gitTextEnv` (`runCommand.ts`), measured there against git built with translations.
  public static func textVariables(_ environment: [String: String]) -> [String: String] {
    var variables = ["LC_MESSAGES": "C", "LANGUAGE": ""]
    if let all = environment["LC_ALL"], !all.isEmpty {
      variables["LC_ALL"] = ""
      variables["LC_CTYPE"] = all
    }
    return variables
  }
}

/// Why the bundled git is not used although it is there. `incompatible`: this system cannot load
/// it, and reinstalling does not help. `broken`: anything else, the installation is incomplete.
public struct BundledGitFailure: Sendable, Equatable {
  public enum Reason: String, Sendable {
    case incompatible
    case broken
  }

  public var path: String
  public var reason: Reason
}
