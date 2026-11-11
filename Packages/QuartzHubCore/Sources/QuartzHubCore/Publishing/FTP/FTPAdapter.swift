import Foundation

/// An FTP target (`deploy/ftp.ts`), over basic-ftp in the helper (`FTPSession`): the diff against
/// the manifest, the site's folder made but none above it, "~" as the login directory, the relay's
/// folders asked for links, and deletions told apart where FTP answers 550 for everything (missing,
/// refused, a folder): SIZE says "missing" only in a folder the login can enter, CWD finds a folder.
/// FTP has no mode of its own; the relay's are asked for with SITE CHMOD and checked in LIST.
public struct FTPAdapter: DeployAdapter {
  public static let timeoutSeconds = 30

  let connections: Connections
  let runtime: RuntimeLocation
  /// A test server's CA, as Node's `ca`; nil in the app.
  let ca: String?

  public init(connections: Connections, runtime: RuntimeLocation = .current, ca: String? = nil) {
    self.connections = connections
    self.runtime = runtime
    self.ca = ca
  }

  struct Refused {
    var remotePath: String
    var wanted: Int
  }

  public func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] {
    try DeployManifests(project: context.project).diff(context.target.id, buildDir: context.buildDir)
  }

  static func localMode(_ path: String) throws -> Int { Int(try NodeFileError.statFollowing(path).st_mode & 0o777) }

  /// SITE CHMOD, an extension a server may refuse; a refusal is no failure.
  static func siteChmod(_ ftp: FTPSession, _ remotePath: String, _ localPath: String) async throws -> Refused? {
    let wanted = try localMode(localPath)
    if JSText.test(remotePath, "[\r\n]") { return Refused(remotePath: remotePath, wanted: wanted) }
    do {
      try await ftp.send("SITE CHMOD \(String(wanted, radix: 8)) \(remotePath)")
      return nil
    } catch {
      return Refused(remotePath: remotePath, wanted: wanted)
    }
  }

  /// What the server holds for each refused path, one LIST per folder: a line only where it differs.
  static func modeNotes(_ ftp: FTPSession, _ refused: [Refused]) async -> String {
    var folders: [String] = []
    var byFolder: [String: [Refused]] = [:]
    for r in refused {
      let folder = NodePath.dirname(r.remotePath)
      if byFolder[folder] == nil { folders.append(folder) }
      byFolder[folder, default: []].append(r)
    }
    var out = ""
    for folder in folders {
      let listing = (try? await ftp.list(folder)) ?? []
      for r in byFolder[folder]! {
        let mode = String(r.wanted, radix: 8)
        guard let actual = listing.first(where: { $0.name == NodePath.basename(r.remotePath) })?.mode else {
          out += L10n.t("main.ftpChmodRefused", ["mode": mode, "path": r.remotePath]) + "\n"
          continue
        }
        if actual != r.wanted { out += L10n.t("main.modeNotSet", ["mode": mode, "actual": String(actual, radix: 8), "path": r.remotePath]) + "\n" }
      }
    }
    return out
  }

  /// A reply of the server answers; anything else is the connection and ends the run.
  static func answered(_ error: Error) throws -> FTPSession.FTPError {
    guard let reply = error as? FTPSession.FTPError else { throw error }
    return reply
  }

  public func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
    guard context.destination["type"] == .string("ftp") else { throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "FTP"])) }
    guard let id = context.target.connectionId, let connection = connections.get(id), connection.kind == .ftp else {
      throw PublishFailure(L10n.t("main.ftpNoConnection"))
    }
    let manifests = DeployManifests(project: context.project)
    let diff = try manifests.diff(context.target.id, buildDir: context.buildDir)
    let partition = DeployManifests.partition(diff, excluding: excludePaths, deleteRemoved: context.deleteRemoved)
    let remotePath = JS.string(context.destination["remotePath"])
    let ftp = try FTPSession.start(runtime: runtime)
    var output = ""
    do {
      defer { Task { await ftp.close() } }
      try await ftp.access(host: connection.host, port: connection.port, user: connection.username, password: context.secret,
                           secure: connection.secure, ca: ca)

      // A relative path is meant from where the login starts; an absolute one keeps "/".
      var start = "/"
      if !JSText.startsWith(remotePath, "/") {
        do {
          start = try await ftp.pwd()
        } catch {
          let unread = (error as? FTPSession.Failure).flatMap { JSText.firstMatch($0.message, #"\ACan't parse response to command 'PWD': "#) }
          guard error is FTPSession.FTPError || unread != nil else { throw error }
          let text = unread != nil ? JSText.slice((error as! FTPSession.Failure).message, unread!.end) : String(describing: error)
          return DeployResult(success: false, output: L10n.t("main.ftpPwdUnreadable", ["path": remotePath, "reply": JSText.replaceAll(text, #"\.+\z"#, with: "")]))
        }
      }
      guard let root = RemotePath.fromLoginDir(remotePath, loginDir: start, account: connection.username) else {
        return DeployResult(success: false, output: L10n.t("main.deployTildeOtherAccount", ["path": remotePath]))
      }

      if !context.keepLocalModes && !partition.toUpload.isEmpty {
        let parent = NodePath.dirname(JSText.replaceAll(root, "/+\\z", with: ""))
        var found = true
        do { try await ftp.cd(parent) } catch { found = false }
        try await ftp.cd(start)
        if !found { return DeployResult(success: false, output: L10n.t("main.deployParentMissing", ["path": parent])) }
      }

      if context.keepLocalModes {
        for folder in (context.relayFolders ?? [remotePath]).map({ RemotePath.fromLoginDir($0, loginDir: start, account: connection.username) ?? $0 }) {
          var listing: [FTPSession.Entry] = []
          do { listing = try await ftp.list(NodePath.dirname(folder)) } catch { _ = try Self.answered(error) }
          let entry = listing.first { $0.name == NodePath.basename(folder) }
          if entry?.isSymbolicLink == true { return DeployResult(success: false, output: L10n.t("main.relayDirSymlink", ["path": folder])) }
          if entry != nil { continue }
          // A folder that cannot be listed but entered is there, and what it is cannot be said.
          var there = true
          do { try await ftp.cd(folder) } catch {
            _ = try Self.answered(error)
            there = false
          }
          try await ftp.cd(start)
          if there { return DeployResult(success: false, output: L10n.t("main.relayDirUnchecked", ["path": folder, "reason": L10n.t("main.relayDirUnlisted")])) }
          break
        }
      }

      let total = partition.toUpload.count + partition.toDelete.count
      var processed = 0
      var ensured = Set<[UInt8]>()
      var refused: [Refused] = []
      for relPath in partition.toUpload {
        let remote = NodePath.join(root, relPath)
        let remoteDir = NodePath.dirname(remote)
        if ensured.insert(Array(remoteDir.utf8)).inserted {
          try await ftp.ensureDir(remoteDir)
          try await ftp.cd(start)
          if context.keepLocalModes, let r = try await Self.siteChmod(ftp, remoteDir, "\(context.buildDir)/\(NodePath.dirname(relPath))") { refused.append(r) }
        }
        try await ftp.upload("\(context.buildDir)/\(relPath)", to: remote)
        if context.keepLocalModes, let r = try await Self.siteChmod(ftp, remote, "\(context.buildDir)/\(relPath)") { refused.append(r) }
        processed += 1
        context.progress(processed, total, relPath)
        output += "↑ \(relPath)\n"
      }
      if !refused.isEmpty { output += await Self.modeNotes(ftp, refused) }

      // Whether the login can enter a folder: nil when it can or the folder is not there, else the
      // folder it cannot enter and the server's reply (SIZE and LIST answer as for a missing one).
      var closedFolders: [String: (folder: String, reason: String)?] = [:]
      func closedFolder(_ folder: String) async throws -> (folder: String, reason: String)? {
        if let known = closedFolders[folder] { return known }
        var refusal: String?
        do { try await ftp.cd(folder) } catch { refusal = JSText.replaceAll(try Self.answered(error).message, #"\.+\z"#, with: "") }
        try await ftp.cd(start)
        var result: (folder: String, reason: String)?
        if let refusal {
          let above = NodePath.dirname(folder)
          if above == folder {
            result = (folder, refusal)
          } else if let closedAbove = try await closedFolder(above) {
            result = closedAbove
          } else {
            var listing: [FTPSession.Entry] = []
            do { listing = try await ftp.list(above) } catch { _ = try Self.answered(error) }
            result = listing.contains { $0.name == NodePath.basename(folder) } ? (folder, refusal) : nil
          }
        }
        closedFolders[folder] = .some(result)
        return result
      }

      if let own = context.ownGeneration {
        let remote = NodePath.join(root, RelayGuard.generatedFile)
        let read: RelayGuard.Read
        do {
          read = .text(String(decoding: try await ftp.download(remote), as: UTF8.self))
        } catch {
          let reply = try Self.answered(error)
          let reason = JSText.replaceAll(reply.message, #"\.+\z"#, with: "")
          if reply.code != 550 {
            read = .unreadable(reason)
          } else {
            var there = true
            do { _ = try await ftp.size(remote) } catch { there = try Self.answered(error).code != 550 }
            let closed = there ? nil : try await closedFolder(root)
            read = there ? .unreadable(reason) : closed.map { .unreadable("\($0.folder): \($0.reason)") } ?? .missing
          }
        }
        if let refusal = RelayGuard.refusal(read, own: own, folder: root) { return refusal }
      }

      var kept: [String] = []
      var missing = 0
      var unchecked: [(folder: String, reason: String, paths: [String])] = []
      for relPath in partition.toDelete {
        let remote = NodePath.join(root, relPath)
        do {
          try await ftp.remove(remote)
          output += "✗ \(relPath)\n"
        } catch {
          let reply = try Self.answered(error)
          // 550 is missing and refused alike: SIZE tells them apart in a folder the login can enter.
          var gone = false
          if reply.code == 550 {
            do { _ = try await ftp.size(remote) } catch { gone = try Self.answered(error).code == 550 }
          }
          let closed = gone ? try await closedFolder(NodePath.dirname(remote)) : nil
          var folder = false
          if gone && closed == nil {
            do {
              try await ftp.cd(remote)
              folder = true
            } catch { _ = try Self.answered(error) }
          }
          if folder {
            try await ftp.cd(start)
            kept.append(relPath)
            output += context.onlyPaths != nil
              ? L10n.t("main.relayRemoveRefused", ["path": relPath, "reason": L10n.t("main.deleteIsFolder")])
              : L10n.t("main.deployDeleteRefused", ["path": relPath, "reason": L10n.t("main.deleteIsFolder")])
          } else if let closed {
            kept.append(relPath)
            if let index = unchecked.firstIndex(where: { $0.folder == closed.folder }) {
              unchecked[index].paths.append(relPath)
            } else {
              unchecked.append((closed.folder, closed.reason, [relPath]))
            }
          } else if gone && context.onlyPaths != nil {
            missing += 1
          } else if gone {
            output += "✗ \(relPath)\n"
          } else {
            kept.append(relPath)
            let reason = JSText.replaceAll(reply.message, #"\.+\z"#, with: "")
            output += context.onlyPaths != nil
              ? L10n.t("main.relayRemoveRefused", ["path": relPath, "reason": reason])
              : L10n.t("main.deployDeleteRefused", ["path": relPath, "reason": reason])
          }
        }
        processed += 1
        context.progress(processed, total, relPath)
      }
      for entry in unchecked {
        let vars = ["path": entry.paths[0], "paths": entry.paths.joined(separator: ", "), "folder": entry.folder, "reason": entry.reason]
        if entry.paths.count == 1 {
          output += context.onlyPaths != nil ? L10n.t("main.relayRemoveUnchecked", vars) : L10n.t("main.deployDeleteUnchecked", vars)
        } else {
          output += context.onlyPaths != nil ? L10n.t("main.relayRemoveUncheckedMany", vars) : L10n.t("main.deployDeleteUncheckedMany", vars)
        }
      }
      if context.onlyPaths != nil && missing == partition.toDelete.count { output += L10n.t("main.relayRemoveGone", ["path": root]) }

      try manifests.commit(context.target.id, buildDir: context.buildDir, excluding: partition.manifestExcludes + kept)
      if context.onlyPaths != nil && !kept.isEmpty { return DeployResult(success: false, output: output + L10n.t("main.relayRemoveRefusedRest")) }
      return DeployResult(success: true, output: output, kept: kept)
    } catch {
      let text: String
      switch error {
      case let reply as FTPSession.FTPError: text = reply.text
      case let failure as FTPSession.Failure: text = failure.text
      case let failure as PublishFailure: text = "Error: \(failure.message)"
      default: text = "Error: \(PublishFailure.message(of: error))"
      }
      let silent = JSText.test((error as? FTPSession.Failure)?.message ?? "", #"\ATimeout \((control|data) socket\)\z"#)
        ? "\(L10n.t("main.sshSilent", ["host": connection.host, "seconds": String(Self.timeoutSeconds)]))\n\n" : ""
      let unreachable = (error as? FTPSession.Failure)?.nodeCode == "EHOSTUNREACH"
        ? "\(L10n.t("main.hostUnreachableLocalNetwork", ["host": connection.host]))\n\n" : ""
      return DeployResult(success: false, output: "\(output)\n\(silent)\(unreachable)\(text)")
    }
  }
}
