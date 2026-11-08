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

extension EnvironmentReport {
  /// The tools that are there but do not answer, or are not there (QuartzControl's band).
  public var broken: [Tool] { tools.filter { $0.version == nil } }

  /// The start page's reassurance line, grouped by origin: "in QuartzHub: node 24.22.2, npm 11.19.1,
  /// git 2.53.0 · vom System: …" (`toolSummary` in `Home.tsx`). Only the number of each answer:
  /// the full answer belongs to the band, when something is missing.
  public func toolSummary(language: String = L10n.language) -> String {
    let groups: [(String, Set<Tool.Source>)] = [
      (L10n.t(in: language, "home.environment.bundled"), [.embedded, .bundled]),
      (L10n.t(in: language, "home.environment.fromSystem"), [.host]),
    ]
    return groups.compactMap { label, sources in
      let members = tools.filter { sources.contains($0.source) }
      guard !members.isEmpty else { return nil }
      return "\(label): " + members.map { "\($0.name) \(Self.versionNumber($0.version) ?? "")" }.joined(separator: ", ")
    }.joined(separator: " · ")
  }

  /// `versionNumber`: the number in what a tool answers to `--version` ("v24.22.2", a bare
  /// "11.19.1", "git version 2.53.0 (Apple Git-155)").
  public static func versionNumber(_ version: String?) -> String? {
    guard let version, let match = version.firstMatch(of: /\d+(?:\.\d+)*/) else { return nil }
    return String(match.output)
  }
}
