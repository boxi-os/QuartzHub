import Foundation

/// What QuartzHub found, for the start page and the settings. A port of `getEnvironmentInfo`
/// (`environmentService.ts`). Not cached: whoever installs a tool because this told them to expects
/// the answer to change without a restart.
public struct EnvironmentReport: Sendable, Equatable {
  public struct Tool: Sendable, Equatable {
    public enum Source: String, Sendable {
      /// Travels with QuartzHub: a machine without it is the normal case, not a problem.
      case embedded
      case host
      case bundled
    }

    public var name: String
    public var source: Source
    /// nil: not on PATH at all.
    public var path: String?
    /// nil: there but does not answer (or the command line tools stub).
    public var version: String?
    /// The bundled git that this system cannot load (`BundledGitFailure.Reason.incompatible`).
    public var incompatible = false
  }

  public var pathSource: HostPath.Source
  public var addedPaths: [String]
  public var tools: [Tool]
  /// What a `node` on the user's own PATH answers, leaving QuartzHub's out: what switching to
  /// "system" would get.
  public var hostNodeVersion: String?
  /// Only a PATH lookup and not part of `ok`: only an SFTP target with rsync transfer needs it.
  public var rsyncAvailable: Bool

  /// Every tool exists and runs.
  public var ok: Bool { tools.allSatisfy { $0.version != nil } }

  public static func probe(_ environment: ToolEnvironment) async -> EnvironmentReport {
    let path = HostPath(entries: environment.path, source: environment.hostPath.source, added: environment.hostPath.added)
    let variables = environment.variables
    let nodeSource: Tool.Source = environment.nodeMode == .embedded ? .embedded : .host

    func tool(_ name: String, _ source: Tool.Source, in path: HostPath) async -> Tool {
      guard let found = path.find(name) else { return Tool(name: name, source: source, path: nil, version: nil) }
      if await HostPath.isCommandLineToolsStub(found) { return Tool(name: name, source: source, path: found, version: nil) }
      let answer = await ProcessRunner.run(Command(found, ["--version"], environment: variables, timeout: .seconds(10)))
      let line = answer.success ? answer.stdout.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } : nil
      return Tool(name: name, source: source, path: found, version: line.flatMap { $0.isEmpty ? nil : $0 })
    }

    let node = await tool("node", nodeSource, in: path)
    let npm = await tool("npm", nodeSource, in: path)
    let gitSource: Tool.Source = environment.git?.source == .bundled ? .bundled : .host
    var git = await tool("git", gitSource, in: path)
    // The bundled git that does not run never comes onto PATH, so a lookup would say "not found"
    // for a file that is in the package; what the start measured counts then.
    if git.path == nil, let failure = environment.bundledGitFailure {
      git = Tool(name: "git", source: .bundled, path: failure.path, version: nil, incompatible: failure.reason == .incompatible)
    }

    let hostNode: String?
    if let ours = environment.nodeBinDirectory {
      hostNode = await tool("node", .host, in: HostPath(entries: path.entries.filter { $0 != ours }, source: path.source, added: [])).version
    } else {
      hostNode = node.version
    }
    return EnvironmentReport(pathSource: path.source, addedPaths: path.added, tools: [node, npm, git],
                             hostNodeVersion: hostNode, rsyncAvailable: path.find("rsync") != nil)
  }
}
