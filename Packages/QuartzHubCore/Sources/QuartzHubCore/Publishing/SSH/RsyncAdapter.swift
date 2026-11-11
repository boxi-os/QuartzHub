import Foundation
import Synchronization

/// rsync as the transfer of an SFTP target (`deploy/rsync.ts`): it asks the server what is there
/// instead of trusting a manifest, so it also sees a file deleted behind the app's back. macOS ships
/// openrsync (protocol 29, "rsync 2.6.9 compatible"); every flag here exists there: -rlt, --delete,
/// --dry-run, --itemize-changes, --exclude-from, -e, --rsync-path, --list-only, -p. It has no
/// --protect-args, so a remote path with whitespace or a shell character is refused, not quoted.
///
/// ssh is `SSHLogin`'s, behind a wrapper script for `-e` (rsync splits that value on whitespace,
/// and a key file's path may have spaces), with the options quoted inside the script.
public struct RsyncAdapter: DeployAdapter {
  let connections: Connections
  let environment: ToolEnvironment
  let configFile: String?

  public init(connections: Connections, environment: ToolEnvironment, configFile: String? = nil) {
    self.connections = connections
    self.environment = environment
    self.configFile = configFile
  }

  static func blockerMessage(_ reason: RsyncSupport.BlockReason) -> String {
    switch reason {
    case .passwordAuth: L10n.t("main.rsyncPasswordAuth")
    case .keyNotAFile: L10n.t("main.rsyncKeyNotAFile")
    case .noPinnedHostKey: L10n.t("main.rsyncNoPinnedHostKey")
    case .notInstalled: L10n.t("main.rsyncNotInstalled")
    }
  }

  /// The connection, asked again here: rsync can be installed or removed while the app runs.
  func connection(_ context: DeployContext) throws(PublishFailure) -> Connection {
    guard let id = context.target.connectionId, let connection = connections.get(id), connection.kind == .ssh else {
      throw PublishFailure(L10n.t("main.sshNoConnection"))
    }
    let installed = ProcessRunner.resolve("rsync", path: environment.variables["PATH"]) != nil
    if let blocker = RsyncSupport.blockReason(connection, rsyncAvailable: installed) { throw PublishFailure(Self.blockerMessage(blocker)) }
    return connection
  }

  struct Env {
    let login: SSHLogin
    let script: String
    var directory: String { login.directory }
    func cleanup() { login.cleanup() }
  }

  func prepare(_ connection: Connection, secret: String?) throws(PublishFailure) -> Env {
    let login = try SSHLogin.prepare(connection, secret: secret, hostKey: connection.hostKey!, environment: environment.variables, configFile: configFile)
    let quote = { (s: String) in "'\(JSText.split(s, "'").joined(separator: "'\\''"))'" }
    let script = "\(login.directory)/ssh.sh"
    do {
      try Posix.write(script, Data("#!/bin/sh\nexec ssh \(login.options.map(quote).joined(separator: " ")) \"$@\"\n".utf8))
    } catch {
      login.cleanup()
      throw PublishFailure(PublishFailure.message(of: error))
    }
    chmod(script, 0o700)
    return Env(login: login, script: script)
  }

  /// One itemized line, "YXcstpoguax path": files only, a folder's line is noise in a diff.
  static func parseItemized(_ line: String) -> DeployDiffEntry? {
    if JSText.startsWith(line, "*deleting ") { return DeployDiffEntry(path: JS.trim(JSText.slice(line, 10)), status: .removed) }
    guard let match = JSText.firstMatch(line, #"\A([<>ch.])([fdLDS])([^ ]*) ([^\n\r\x{2028}\x{2029}]+)\z"#), match.groups[2] == "f" else { return nil }
    return DeployDiffEntry(path: JS.trim(match.groups[4]!), status: JSText.startsWith(match.groups[3]!, "+++") ? .added : .changed)
  }

  /// The failure text of one run: QuartzControl's sentence for ssh's failure, ssh's own text, or
  /// the exit code when there is none.
  static func failureMessage(_ output: String, _ connection: Connection, _ code: String) -> String {
    if let translated = SSHFailure.translate(output, connection: connection) { return translated }
    let raw = JS.trim(output)
    return raw.isEmpty ? L10n.t("main.rsyncExitCode", ["code": code]) : raw
  }

  struct Run {
    var code: String
    var success: Bool
    var entries: [DeployDiffEntry]
    var output: String
  }

  /// rsync without a shell; the itemized lines read as they come, for the progress.
  func runRsync(_ arguments: [String], env: Env, onEntry: (@Sendable (DeployDiffEntry) -> Void)? = nil) async -> Run {
    let collected = Mutex<(entries: [DeployDiffEntry], pending: String)>(([], ""))
    // The C locale: openrsync escapes bytes 0x80 to 0x9F of a name in a UTF-8 locale ("Über" is C3 9C
    // and became "\u{FFFD}\\#234ber" in the diff), in C it prints the bytes as they are (measured
    // with /usr/bin/rsync, macOS 27.2). QuartzControl's names depended on the locale it was started in.
    let command = environment.command("rsync", arguments).adding(env.login.variables).adding(["LC_ALL": "C"])
    let result = await ProcessRunner.run(command) { stream, text in
      guard stream == .stdout else { return }
      let found = collected.withLock { state -> [DeployDiffEntry] in
        let lines = JSText.split(state.pending + text, "\n")
        state.pending = lines.last ?? ""
        let entries = lines.dropLast().compactMap(Self.parseItemized)
        state.entries += entries
        return entries
      }
      for entry in found { onEntry?(entry) }
    }
    let (entries, pending) = collected.withLock { ($0.entries, $0.pending) }
    var all = entries
    if let last = Self.parseItemized(pending) {
      all.append(last)
      onEntry?(last)
    }
    let code: String = switch result.termination {
    case .exited(let status): String(status)
    default: "?"
    }
    let output = result.success ? result.output : result.report(for: command)
    return Run(code: code, success: result.success, entries: all, output: output)
  }

  /// Single quotes for the remote shell; a leading "~/" or "~user/" stays outside them.
  static func remoteShellPath(_ path: String) -> String {
    let home = JSText.firstMatch(path, #"\A~[A-Za-z0-9._+@-]*/"#)?.groups[0] ?? ""
    let rest = JSText.slice(path, JSText.length(home))
    return "\(home)'\(JSText.split(rest, "'").joined(separator: "'\\''"))'"
  }

  /// The receiver makes only the last folder of the path.
  static let missingParent = #"\bmkdir "([^\n\r\x{2028}\x{2029}]*)" failed: No such file or directory"#
  /// A deletion the receiver was refused (rsync 3.2.4 and later with "[generator] ").
  static let deleteRefused = #"(?m)delete_file: unlink\(([^\n\r\x{2028}\x{2029}]*)\) failed: ([^\n\r\x{2028}\x{2029}]*?)(?: \(\d+\))?$"#
  static let nonEmptyFolder = #"(?m)^cannot delete non-empty directory: ([^\n\r\x{2028}\x{2029}]*)$"#

  static func remoteSpec(_ connection: Connection, _ remotePath: String) throws(PublishFailure) -> String {
    try SSHLogin.refuseUnsafe(connection)
    if let unsafe = RemotePath.rsyncUnsafeChar(remotePath) {
      throw PublishFailure(JSText.test(unsafe, "[\(JSText.space)]") ? L10n.t("main.rsyncPathWithSpace") : L10n.t("main.rsyncPathWithSpecial", ["char": unsafe]))
    }
    let withSlash = JSText.endsWith(remotePath, "/") ? remotePath : "\(remotePath)/"
    // A path starting with "-" would be read as an option by the server's rsync.
    return "\(connection.username)@\(connection.host):\(JSText.startsWith(withSlash, "-") ? "./\(withSlash)" : withSlash)"
  }

  func arguments(_ context: DeployContext, _ connection: Connection, remotePath: String, deleteRemoved: Bool, excludePaths: [String], env: Env,
                 dryRun: Bool, makeParents: Bool = false) throws(PublishFailure) -> [String] {
    var arguments = ["-rlt", "--itemize-changes", "--no-motd", "-e", env.script]
    if makeParents { arguments.append("--rsync-path=mkdir -p -- \(Self.remoteShellPath(remotePath)) && rsync") }
    // -rlt, not -a: -a would push this machine's owner, group and modes onto the site; -p only for
    // an upload that brings its own modes, not when removing.
    if context.keepLocalModes && context.onlyPaths == nil { arguments.append("-p") }
    if deleteRemoved { arguments.append("--delete") }
    if dryRun { arguments.append("--dry-run") }
    do {
      if let only = context.onlyPaths {
        // Removing the relay: --delete may take these and nothing else.
        let file = "\(env.directory)/only"
        let lines = only.map { "+ /\(JSText.replaceAll($0, #"\A/+"#, with: ""))" } + ["- *"]
        try Posix.write(file, Data((lines.joined(separator: "\n") + "\n").utf8))
        arguments.append("--exclude-from=\(file)")
      } else if !excludePaths.isEmpty {
        // A leading slash anchors each pattern at the root of the transfer.
        let file = "\(env.directory)/excludes"
        try Posix.write(file, Data((excludePaths.map { "/\(JSText.replaceAll($0, #"\A/+"#, with: ""))" }.joined(separator: "\n") + "\n").utf8))
        arguments.append("--exclude-from=\(file)")
      }
    } catch {
      throw PublishFailure(PublishFailure.message(of: error))
    }
    arguments += ["\(context.buildDir)/", try Self.remoteSpec(connection, remotePath)]
    return arguments
  }

  public func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] {
    guard context.destination["type"] == .string("sftp") else { throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "rsync"])) }
    let connection = try connection(context)
    let env = try prepare(connection, secret: context.secret)
    defer { env.cleanup() }
    let run = await runRsync(try arguments(context, connection, remotePath: JS.string(context.destination["remotePath"]),
                                           deleteRemoved: context.deleteRemoved, excludePaths: [], env: env, dryRun: true), env: env)
    if !run.success { throw PublishFailure(Self.failureMessage(run.output, connection, run.code)) }
    var entries = run.entries
    JS.sort(&entries) { JS.localeCompare($0.path, $1.path) }
    return entries
  }

  public func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
    guard context.destination["type"] == .string("sftp") else { throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "rsync"])) }
    let connection = try connection(context)
    let env = try prepare(connection, secret: context.secret)
    defer { env.cleanup() }
    let remotePath = JS.string(context.destination["remotePath"])

    // The relay's folders: none may be a link, asked with rsync itself (an account limited to
    // rsync allows that), down to the first that is not there.
    if context.keepLocalModes {
      for folder in context.relayFolders ?? [remotePath] {
        let spec = JSText.replaceAll(try Self.remoteSpec(connection, folder), "/+\\z", with: "")
        let listed = await runRsync(["--list-only", "--no-motd", "-e", env.script, spec], env: env)
        if JSText.test(listed.output, "(?m)^l") { return DeployResult(success: false, output: L10n.t("main.relayDirSymlink", ["path": folder])) }
        if listed.success { continue }
        if JSText.test(listed.output, #"link_stat "[^\n]*" failed: No such file or directory"#) {
          if context.onlyPaths != nil { return DeployResult(success: true, output: L10n.t("main.relayRemoveGone", ["path": folder])) }
          break
        }
        let first = JSText.split(JS.trim(listed.output), "\n")[0]
        let reason = first.isEmpty ? L10n.t("main.rsyncExitCode", ["code": listed.code]) : first
        let unchecked = JSText.test(listed.output, "rrsync error: reading from write-only server")
          ? L10n.t("main.relayDirWriteOnly", ["path": folder, "reason": reason])
          : L10n.t("main.relayDirUnchecked", ["path": folder, "reason": reason])
        return DeployResult(success: false, output: SSHFailure.translate(listed.output, connection: connection) ?? unchecked)
      }
    }

    // Removing the relay: only this upload's, fetched with rsync itself.
    if let own = context.ownGeneration {
      guard let local = try? SSHLogin.temporaryFolder("qh-relay-guard") else { throw PublishFailure("mkdtemp") }
      defer { try? FileManager.default.removeItem(atPath: local) }
      let spec = JSText.replaceAll(try Self.remoteSpec(connection, NodePath.join(remotePath, RelayGuard.generatedFile)), "/+\\z", with: "")
      let fetched = await runRsync(["--no-motd", "-e", env.script, spec, "\(local)/"], env: env)
      let said = { () -> String in
        let first = JSText.split(JS.trim(fetched.output), "\n")[0]
        return SSHFailure.translate(fetched.output, connection: connection) ?? (first.isEmpty ? L10n.t("main.rsyncExitCode", ["code": fetched.code]) : first)
      }
      let read: RelayGuard.Read
      if fetched.success {
        read = (try? Posix.read("\(local)/\(RelayGuard.generatedFile)")).map { .text(String(decoding: $0, as: UTF8.self)) } ?? .unreadable(said())
      } else if JSText.test(fetched.output, #"link_stat "[^\n]*" failed: No such file or directory"#) {
        read = .missing
      } else {
        read = .unreadable(said())
      }
      if let refusal = RelayGuard.refusal(read, own: own, folder: remotePath) { return refusal }
    }

    // A dry run first, for the total of the progress.
    let plan = await runRsync(try arguments(context, connection, remotePath: remotePath, deleteRemoved: context.deleteRemoved,
                                            excludePaths: excludePaths, env: env, dryRun: true), env: env)
    if !plan.success { return DeployResult(success: false, output: Self.failureMessage(plan.output, connection, plan.code)) }
    let total = plan.entries.count
    if total == 0 && !context.keepLocalModes { return DeployResult(success: true, output: L10n.t("main.deployNothingToDo")) }

    let processed = Mutex(0)
    let send = { (makeParents: Bool) async throws(PublishFailure) -> Run in
      await self.runRsync(try self.arguments(context, connection, remotePath: remotePath, deleteRemoved: context.deleteRemoved,
                                             excludePaths: excludePaths, env: env, dryRun: false, makeParents: makeParents), env: env) { entry in
        let count = processed.withLock { $0 += 1; return $0 }
        context.progress(count, total, entry.path)
      }
    }
    var result = try await send(false)
    var firstFailure = ""
    // Only for the relay, whose folder below the target is QuartzHub's to make.
    if context.keepLocalModes && context.onlyPaths == nil && !result.success && JSText.test(result.output, Self.missingParent) {
      firstFailure = Self.failureMessage(result.output, connection, result.code)
      result = try await send(true)
    }
    if !context.keepLocalModes && !result.success, let missing = JSText.firstMatch(result.output, Self.missingParent) {
      return DeployResult(success: false, output: L10n.t("main.deployParentMissing", ["path": NodePath.dirname(missing.groups[1]!)]))
    }

    let summary = result.entries.map { "\($0.status == .removed ? "✗" : "↑") \($0.path)" }.joined(separator: "\n")
    if context.onlyPaths != nil {
      var refused: [(String, String)] = []
      if !result.success { refused += JSText.matches(result.output, Self.deleteRefused).map { ($0.groups[1]!, $0.groups[2]!) } }
      refused += JSText.matches(result.output, Self.nonEmptyFolder).map { ($0.groups[1]!, L10n.t("main.deleteIsFolder")) }
      if !refused.isEmpty {
        let removed = result.entries.filter { $0.status == .removed }.map { "✗ \($0.path)\n" }
        let said = refused.map { L10n.t("main.relayRemoveRefused", ["path": $0.0, "reason": $0.1]) }
        return DeployResult(success: false, output: (removed + said + [L10n.t("main.relayRemoveRefusedRest")]).joined())
      }
    }
    if result.success {
      let text = !summary.isEmpty ? "\(summary)\n" : context.onlyPaths != nil ? L10n.t("main.relayRemoveGone", ["path": remotePath]) : L10n.t("main.deployNothingToDo")
      return DeployResult(success: true, output: text)
    }
    return DeployResult(success: false, output: [firstFailure, Self.failureMessage(result.output, connection, result.code)].filter { !$0.isEmpty }.joined(separator: "\n"))
  }
}
