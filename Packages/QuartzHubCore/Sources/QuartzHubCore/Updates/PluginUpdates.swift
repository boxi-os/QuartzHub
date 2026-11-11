import Foundation

/// Whether each plugin of `quartz.lock.json` has something newer, and the update of one or all.
/// A port of `getPluginsUpdateStatus` and `updatePlugin` (`updateService.ts`), measured against it
/// with real git (`scripts/plugin-updates-golden.mjs`).
///
/// - **`git ls-remote -- <source> <ref>`**, with "--": the source comes from the lockfile, and a
///   leading dash is an option to git (`--upload-pack=<cmd>` runs the command). 20 s each, four at
///   a time, because the Updates tab asks on opening, unprompted; a timeout is "unknown".
/// - **A pinned ref may be a branch or a tag**: a branch wins, then the tag, then whatever matched
///   first.
/// - **Deviation: an annotated tag answers with its commit**, the one Quartz writes into the
///   lockfile (`git rev-parse HEAD` after the checkout). QuartzControl compared the tag object, so
///   such a plugin read as behind forever: a pattern matches the end of a name, and the peeled line
///   is named `refs/tags/v1^{}`, so `v1` alone never lists it. Asked for as a second pattern
///   (`v1^{}`), it is there over protocols 0, 1 and 2; it wins over the tag object of its name.
/// - **Deviation:** an entry that is no object (null) or whose source or ref is no text failed the
///   whole list in QuartzControl (a TypeError, a spawn error); here that entry is local or unknown
///   and the others answer. A lockfile that is `null` reads as no plugins.
public enum PluginUpdates {
  public struct Status: Sendable, Equatable {
    public enum State: String, Sendable { case local, upToDate, behind, unknown }
    public var name: String
    /// The lockfile's `commit` as written, when there is one.
    public var installedCommit: JSONValue?
    /// nil with `unknown`: ls-remote did not answer.
    public var latestCommit: String?
    public var state: State
  }

  static let maxParallelChecks = 4

  public static func status(project: String, core: CoreUpdate) async -> [Status] {
    guard let data = try? Posix.read("\(project)/quartz.lock.json"),
          let lockfile = try? JSJSON.parse(Data(String(decoding: data, as: UTF8.self).utf8)) else { return [] }
    let entries = jsEntries(lockfile["plugins"])
    var results = [Status?](repeating: nil, count: entries.count)
    await withTaskGroup(of: (Int, Status).self) { group in
      var next = 0
      func add() {
        guard next < entries.count else { return }
        let index = next
        next += 1
        group.addTask { (index, await check(entries[index].0, entries[index].1, core)) }
      }
      for _ in 0..<maxParallelChecks { add() }
      for await (index, status) in group {
        results[index] = status
        add()
      }
    }
    return results.compactMap { $0 }
  }

  /// `Object.entries(lockfile.plugins ?? {})`: an object's keys, an array's or a string's indices.
  static func jsEntries(_ value: JSONValue?) -> [(String, JSONValue)] {
    switch value {
    case .object(let object)?: object.keys.map { ($0, object[$0]!) }
    case .array(let items)?: items.enumerated().map { (String($0.offset), $0.element) }
    // By UTF-16 unit, as JavaScript; a character outside the BMP counts twice (it is local either way).
    case .string(let text)?: text.unicodeScalars.flatMap { scalar in Array(repeating: String(scalar), count: String(scalar).utf16.count) }
      .enumerated().map { (String($0.offset), JSONValue.string($0.element)) }
    default: []
    }
  }

  static func check(_ name: String, _ entry: JSONValue, _ core: CoreUpdate) async -> Status {
    let commit = entry["commit"]
    let resolved = entry["resolved"]
    if commit == .string("local") || !JS.truthy(resolved) {
      return Status(name: name, installedCommit: nil, latestCommit: nil, state: .local)
    }
    let installed = commit
    guard let source = resolved?.stringValue else { return Status(name: name, installedCommit: installed, latestCommit: nil, state: .unknown) }
    let latest: String?
    if JS.truthy(entry["ref"]) {
      guard let ref = entry["ref"]?.stringValue else { return Status(name: name, installedCommit: installed, latestCommit: nil, state: .unknown) }
      latest = await lsRemoteRef(core, source, ref)
    } else {
      latest = await core.lsRemoteHead(source)
    }
    guard let latest else { return Status(name: name, installedCommit: installed, latestCommit: nil, state: .unknown) }
    return Status(name: name, installedCommit: installed, latestCommit: latest, state: commit == .string(latest) ? .upToDate : .behind)
  }

  static func lsRemoteRef(_ core: CoreUpdate, _ url: String, _ ref: String) async -> String? {
    let rows = await core.lsRemote(url, ref, "\(ref)^{}")
    // A name's peeled line, when it has one, stands for it. git lists a peeled line right after its
    // own name, so the first line is never one.
    func commit(_ name: String) -> String? { (rows.first { $0.ref == "\(name)^{}" } ?? rows.first { $0.ref == name })?.commit }
    return commit("refs/heads/\(ref)") ?? commit("refs/tags/\(ref)") ?? rows.first.flatMap { commit($0.ref) }
  }

  /// `quartz plugin install --latest [name]`, after a `pluginChange` snapshot; a failed snapshot
  /// stops it, as with `PluginCommands.add`. With the network deadline of the plugin commands,
  /// which QuartzControl did not set.
  public static func update(project: String, name: String? = nil, environment: ToolEnvironment, snapshot: @escaping SnapshotStore.Take,
                            deadline: Duration = PluginCommands.Deadlines().network) async -> PluginCommands.Result {
    await RunningWork.during(.pluginUpdate, project: project) {
      await updateNow(project: project, name: name, environment: environment, snapshot: snapshot, deadline: deadline)
    }
  }

  static func updateNow(project: String, name: String?, environment: ToolEnvironment, snapshot: @escaping SnapshotStore.Take,
                        deadline: Duration) async -> PluginCommands.Result {
    if let failure = await PluginCommands.snapshotFirst(snapshot, project, name ?? "") { return failure }
    var arguments = ["quartz", "plugin", "install", "--latest"]
    if let name, !name.isEmpty { arguments.append(name) }
    let command = environment.command("npx", arguments, in: project, timeout: deadline)
    let result = await ProcessRunner.run(command)
    return PluginCommands.Result(success: result.success, output: result.report(for: command))
  }
}
