import Foundation

/// What `ssh2-sftp-client` made of the SFTP calls QuartzControl's adapter used, over `SFTPChannel`:
/// the same questions (exists asks lstat, a recursive mkdir asks every folder above), the same
/// answers (a stat's "failure" 4 counts as missing, like 2) and the same error text, because that
/// text reaches the output (a refused deletion's reason, "Error: mkdir: …").
struct SFTPClientCompat {
  /// An answer of the server, in the client's words; `code` is the server's status or nil for the
  /// client's own "not there" ("ENOENT").
  struct Answer: Error, CustomStringConvertible {
    let message: String
    let code: UInt32?
    var description: String { message }
    var missing: Bool { code == nil || code == 2 }
  }

  let channel: SFTPChannel

  /// Rethrows what is no answer of the server (the connection), wraps what is.
  func answered<T>(_ body: () async throws(SFTPChannel.Failure) -> T, _ wrap: (SFTPChannel.Status) -> Answer) async throws -> T {
    do throws(SFTPChannel.Failure) {
      return try await body()
    } catch {
      guard case .status(let status) = error else { throw error }
      throw wrap(status)
    }
  }

  /// `_xstat`: 2 and 4 are "No such file".
  func lstat(_ path: String) async throws -> SFTPChannel.Attributes {
    try await answered({ () async throws(SFTPChannel.Failure) in try await channel.lstat(path) }) { status in
      status.code == 2 || status.code == 4 ? Answer(message: "_xstat: No such file: \(path)", code: nil)
        : Answer(message: "_xstat: \(status.message) \(path)", code: status.code)
    }
  }

  func stat(_ path: String) async throws -> SFTPChannel.Attributes {
    try await answered({ () async throws(SFTPChannel.Failure) in try await channel.stat(path) }) { status in
      status.code == 2 || status.code == 4 ? Answer(message: "_xstat: No such file: \(path)", code: nil)
        : Answer(message: "_xstat: \(status.message) \(path)", code: status.code)
    }
  }

  /// "d", "l", "-" or nil (other kinds are nil too, as `exists` answered false).
  func exists(_ path: String) async throws -> String? {
    if path == "." { return "d" }
    do {
      let info = try await lstat(path)
      return info.isDirectory ? "d" : info.isSymbolicLink ? "l" : info.isFile ? "-" : nil
    } catch let answer as Answer where answer.code == nil {
      return nil
    }
  }

  struct BadPath: Error, CustomStringConvertible {
    let description: String
  }

  /// `mkdir(path, true)`: a folder that is there is fine, anything else in its place is an error,
  /// the folders above are made first.
  func mkdirRecursive(_ path: String) async throws {
    do {
      try await mkdir(path)
    } catch let error as BadPath {
      throw BadPath(description: "mkdir: \(error.description)")
    }
  }

  private func mkdir(_ path: String) async throws {
    let kind = try await exists(path)
    if let kind, kind != "d" { throw BadPath(description: "_mkdir: Bad path: \(path) already exists as a file") }
    if kind != nil { return }
    let dir = NodePath.dirname(path)
    if !dir.isEmpty && dir != "." && dir != path {
      let above = try await exists(dir)
      if above == nil {
        try await mkdir(dir)
      } else if above != "d" {
        throw BadPath(description: "_mkdir: Bad path: \(dir) not a directory")
      }
    }
    try await answered({ () async throws(SFTPChannel.Failure) in try await channel.mkdir(path) }) { status in
      switch status.code {
      case 4: Answer(message: "_doMkdir: Bad path: \(path) permission denied", code: 4)
      case 2: Answer(message: "_doMkdir: Bad path: \(path) parent not a directory or not exist", code: 2)
      default: Answer(message: "_doMkdir: \(status.message) \(path)", code: status.code)
      }
    }
  }

  func chmod(_ path: String, _ mode: UInt32) async throws {
    try await answered({ () async throws(SFTPChannel.Failure) in try await channel.setPermissions(path, mode) }) { status in
      Answer(message: "_chmod: \(status.message) \(path)", code: status.code)
    }
  }

  func put(_ local: String, _ remote: String, mode: UInt32) async throws {
    try await answered({ () async throws(SFTPChannel.Failure) in try await channel.writeFile(local: local, remote: remote, mode: mode) }) { status in
      Answer(message: "_put: Write stream error: \(status.message) \(remote)", code: status.code)
    }
  }

  func get(_ path: String) async throws -> Data {
    try await answered({ () async throws(SFTPChannel.Failure) in try await channel.readFile(path) }) { status in
      Answer(message: "get: \(status.message) \(path)", code: status.code)
    }
  }

  func delete(_ path: String) async throws {
    try await answered({ () async throws(SFTPChannel.Failure) in try await channel.remove(path) }) { status in
      Answer(message: "delete: \(status.message) \(path)", code: status.code)
    }
  }
}

/// An SFTP target (`deploy/sftp.ts`): the diff against the manifest, files sent with mode 0644 (ssh2
/// opened every file 0666 and set that with fchmod, so the server's umask never applied: a site went
/// up writable by every account on the host), a deletion counted only when the server says the file
/// is missing, the relay's own modes and its guard, and once per target the files up to 1.1.0 left
/// at 0666 set to 0644. Over ssh (`SSHLogin`, `SFTPChannel`) instead of ssh2.
public struct SFTPAdapter: DeployAdapter {
  static let chmodConcurrency = 8

  let connections: Connections
  let environment: ToolEnvironment
  let confirm: HostKeyCheck.Confirm
  let configFile: String?

  public init(connections: Connections, environment: ToolEnvironment, confirm: @escaping HostKeyCheck.Confirm, configFile: String? = nil) {
    self.connections = connections
    self.environment = environment
    self.confirm = confirm
    self.configFile = configFile
  }

  static func connection(_ context: DeployContext, _ connections: Connections) throws(PublishFailure) -> Connection {
    guard let id = context.target.connectionId, let connection = connections.get(id), connection.kind == .ssh else {
      throw PublishFailure(L10n.t("main.sshNoConnection"))
    }
    return connection
  }

  public func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] {
    try DeployManifests(project: context.project).diff(context.target.id, buildDir: context.buildDir)
  }

  /// A server answered (an `Answer`), or the client's own check; everything else is the connection.
  static func serverAnswered(_ error: Error) -> Bool { error is SFTPClientCompat.Answer }

  public func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
    guard context.destination["type"] == .string("sftp") else { throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "SFTP"])) }
    let connection = try Self.connection(context, connections)
    let manifests = DeployManifests(project: context.project)
    let diff = try manifests.diff(context.target.id, buildDir: context.buildDir)
    let partition = DeployManifests.partition(diff, excluding: excludePaths, deleteRemoved: context.deleteRemoved)
    var output = ""
    var channel: SFTPChannel?
    defer { if let channel { Task { await channel.close() } } }
    do {
      let key = try await HostKeyCheck.trusted(connection, connections: connections, environment: environment, confirm: confirm, configFile: configFile)
      let login = try SSHLogin.prepare(connection, secret: context.secret, hostKey: key, environment: environment.variables, configFile: configFile)
      defer { login.cleanup() }
      let opened = try await SFTPChannel.open(login, environment: environment)
      channel = opened
      let client = SFTPClientCompat(channel: opened)
      let loginDir = try await opened.realpath(".")
      let remotePath = JS.string(context.destination["remotePath"])
      guard let root = RemotePath.fromLoginDir(remotePath, loginDir: loginDir, account: connection.username) else {
        return DeployResult(success: false, output: L10n.t("main.deployTildeOtherAccount", ["path": remotePath]))
      }

      // A site's folder is made, the folders above it are not, as rsync's receiver does.
      if !context.keepLocalModes && !partition.toUpload.isEmpty {
        let parent = NodePath.dirname(JSText.replaceAll(root, "/+\\z", with: ""))
        if try await client.exists(parent) == nil { return DeployResult(success: false, output: L10n.t("main.deployParentMissing", ["path": parent])) }
      }

      // The relay's folders below the target: none may be a link on the server.
      if context.keepLocalModes {
        for folder in (context.relayFolders ?? [remotePath]).map({ RemotePath.fromLoginDir($0, loginDir: loginDir, account: connection.username) ?? $0 }) {
          let info: SFTPChannel.Attributes
          do {
            info = try await client.lstat(folder)
          } catch let answer as SFTPClientCompat.Answer {
            if answer.code == nil { break }
            return DeployResult(success: false, output: L10n.t("main.relayDirUnchecked", ["path": folder, "reason": answer.message]))
          }
          if info.isSymbolicLink { return DeployResult(success: false, output: L10n.t("main.relayDirSymlink", ["path": folder])) }
        }
      }

      if let own = context.ownGeneration {
        let read: RelayGuard.Read
        do {
          read = .text(String(decoding: try await client.get(NodePath.join(root, RelayGuard.generatedFile)), as: UTF8.self))
        } catch let answer as SFTPClientCompat.Answer {
          read = answer.missing ? .missing : .unreadable(answer.message)
        }
        if let refusal = RelayGuard.refusal(read, own: own, folder: root) { return refusal }
      }

      let settle = !context.keepLocalModes && !manifests.modesSettled(context.target.id)
      let skip = Set((partition.toUpload + partition.toDelete + excludePaths).map { Array($0.utf8) })
      let earlier = settle ? manifests.read(context.target.id).paths.filter { !skip.contains(Array($0.utf8)) } : []
      let total = partition.toUpload.count + partition.toDelete.count + earlier.count
      var processed = 0
      var ensured = Set<[UInt8]>()

      for relPath in partition.toUpload {
        let remote = NodePath.join(root, relPath)
        let remoteDir = NodePath.dirname(remote)
        if ensured.insert(Array(remoteDir.utf8)).inserted {
          try await client.mkdirRecursive(remoteDir)
          // mkdir leaves a folder that is there as it is; the relay's needs its mode every time.
          if context.keepLocalModes {
            let wanted = UInt32(try NodeFileError.statFollowing("\(context.buildDir)/\(NodePath.dirname(relPath))").st_mode & 0o777)
            try? await client.chmod(remoteDir, wanted)
            output += await Self.modeNote(client, remoteDir, wanted)
          }
        }
        let mode = context.keepLocalModes ? UInt32(try NodeFileError.statFollowing("\(context.buildDir)/\(relPath)").st_mode & 0o777) : 0o644
        try await client.put("\(context.buildDir)/\(relPath)", remote, mode: mode)
        if context.keepLocalModes { output += await Self.modeNote(client, remote, mode) }
        processed += 1
        context.progress(processed, total, relPath)
        output += "↑ \(relPath)\n"
      }

      // Only the server saying the file is missing means it is gone; a dropped connection fails
      // the run and the manifest stays as it was.
      var kept: [String] = []
      var missing = 0
      for relPath in partition.toDelete {
        do {
          try await client.delete(NodePath.join(root, relPath))
          output += "✗ \(relPath)\n"
        } catch let answer as SFTPClientCompat.Answer {
          if answer.code == 2 {
            if context.onlyPaths != nil { missing += 1 } else { output += "✗ \(relPath)\n" }
          } else {
            kept.append(relPath)
            let isFolder = (try? await client.stat(NodePath.join(root, relPath)))?.isDirectory ?? false
            let reason = isFolder ? L10n.t("main.deleteIsFolder") : answer.message
            output += context.onlyPaths != nil
              ? L10n.t("main.relayRemoveRefused", ["path": relPath, "reason": reason])
              : L10n.t("main.deployDeleteRefused", ["path": relPath, "reason": reason])
          }
        }
        processed += 1
        context.progress(processed, total, relPath)
      }
      if context.onlyPaths != nil && missing == partition.toDelete.count { output += L10n.t("main.relayRemoveGone", ["path": root]) }

      // Up to 1.1.0 every file went up as 0666, and the manifest never sends an unchanged file
      // again: once per target every earlier file gets its mode alone, only a regular file at
      // exactly 0666 (lstat: a link is not followed), eight requests at a time.
      if settle {
        let outcome = await Self.settle(client, root: root, earlier: earlier) { label in
          processed += 1
          context.progress(processed, total, L10n.t("main.sftpModesProgress", ["path": label]))
        }
        let left = earlier.count - outcome.answered
        if left > 0 {
          output += L10n.t("main.sftpModesUnfinished", ["count": String(outcome.set), "total": String(earlier.count), "left": String(left)])
        } else if outcome.set > 0 {
          output += L10n.t("main.sftpModesSettled", ["count": String(outcome.set), "total": String(earlier.count)])
        }
        if outcome.refused > 0 { output += L10n.t("main.sftpModesRefused", ["count": String(outcome.refused), "total": String(earlier.count)]) }
        if left == 0 { try manifests.settleModes(context.target.id) }
      }

      try manifests.commit(context.target.id, buildDir: context.buildDir, excluding: partition.manifestExcludes + kept)
      if context.onlyPaths != nil && !kept.isEmpty { return DeployResult(success: false, output: output + L10n.t("main.relayRemoveRefusedRest")) }
      return DeployResult(success: true, output: output)
    } catch let failure as PublishFailure {
      return DeployResult(success: false, output: "\(output)\n\(failure.message)")
    } catch let failure as SFTPChannel.Failure {
      // The connection: ssh's own words, as QuartzControl's sentences where there is one.
      let text = failure.description
      return DeployResult(success: false, output: "\(output)\n\(SSHFailure.translate(text, connection: connection, sftp: true) ?? text)")
    } catch {
      return DeployResult(success: false, output: "\(output)\nError: \(PublishFailure.message(of: error))")
    }
  }

  /// A server may refuse a mode (internal-sftp -P setstat); what it holds is asked and said when it
  /// differs, special bits included. A stat it refuses says nothing about the upload.
  static func modeNote(_ client: SFTPClientCompat, _ path: String, _ wanted: UInt32) async -> String {
    guard let actual = (try? await client.stat(path))?.mode else {
      return L10n.t("main.modeUnchecked", ["mode": String(wanted, radix: 8), "path": path]) + "\n"
    }
    return actual == wanted ? "" : L10n.t("main.modeNotSet", ["mode": String(wanted, radix: 8), "actual": String(actual, radix: 8), "path": path]) + "\n"
  }

  struct Settled {
    var set = 0
    var refused = 0
    var answered = 0
  }

  static func settle(_ client: SFTPClientCompat, root: String, earlier: [String], progress: @escaping (String) -> Void) async -> Settled {
    var result = Settled()
    var next = 0
    var stopped = false
    // Eight at a time on the one channel; a connection that drops stops the rest for the next upload.
    while next < earlier.count && !stopped {
      let batch = Array(earlier[next..<min(next + chmodConcurrency, earlier.count)])
      next += batch.count
      let answers = await withTaskGroup(of: (Int, Int, Int, Bool).self) { group in
        for path in batch {
          group.addTask {
            let remote = NodePath.join(root, path)
            do {
              let info = try await client.lstat(remote)
              if info.isFile && info.mode == 0o666 {
                do {
                  try await client.chmod(remote, 0o644)
                  return (1, 0, 1, false)
                } catch {
                  if !serverAnswered(error) { throw error }
                  return (0, 1, 1, false)
                }
              }
              return (0, 0, 1, false)
            } catch {
              return serverAnswered(error) ? (0, 0, 1, false) : (0, 0, 0, true)
            }
          }
        }
        var collected: [(Int, Int, Int, Bool)] = []
        for await answer in group { collected.append(answer) }
        return collected
      }
      for (index, answer) in answers.enumerated() {
        result.set += answer.0
        result.refused += answer.1
        result.answered += answer.2
        if answer.3 { stopped = true }
        progress(batch[min(index, batch.count - 1)])
      }
    }
    return result
  }
}
