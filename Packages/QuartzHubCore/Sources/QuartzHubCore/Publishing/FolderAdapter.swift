import Foundation

/// Removing the relay takes down the upload of this project, not one that took its place
/// (`deploy/relayGuard.ts`): the adapter reads config.generated.php over its own way and deletes
/// nothing when it names another generation or cannot be read.
public enum RelayGuard {
  /// The relay file that names its upload's generation (quartz-forms writes it on every run).
  public static let generatedFile = "config.generated.php"

  /// What reading it gave: its text, nil when it is not there, or why it could not be read.
  public enum Read: Sendable, Equatable {
    case text(String)
    case missing
    case unreadable(String)
  }

  /// nil: go on. A file that is not there goes on too; one without the line, another relay's or
  /// one that cannot be read is refused.
  public static func refusal(_ read: Read, own: String, folder: String) -> DeployResult? {
    switch read {
    case .missing: return nil
    case .unreadable(let reason):
      return DeployResult(success: false, output: L10n.t("main.relayRemoveUnverified", ["path": folder, "reason": reason]))
    case .text(let text):
      // As send.php reads it: the line in the head of the file.
      let generation = JSText.firstMatch(text, #"'generation' => '([0-9a-f]{16})'"#)?.groups[1]
      if generation == own { return nil }
      if generation == nil { return DeployResult(success: false, output: L10n.t("main.relayRemoveNoGeneration", ["path": folder])) }
      return DeployResult(success: false, output: L10n.t("main.relayRemoveForeign", ["path": folder]))
    }
  }
}

/// A folder target (`deploy/folder.ts`): a finished build copied into a folder with the diff, the
/// exclusions and the deletion of what the build no longer has. Not "build into that folder": a
/// build writes progressively, and a sync client watching the folder would send a half-finished
/// site. Each file goes in under a scratch name and is renamed into place.
public struct FolderAdapter: DeployAdapter {
  let random: @Sendable () -> String

  public init(random: @escaping @Sendable () -> String = { String(format: "%08x", UInt32.random(in: .min ... .max)) }) {
    self.random = random
  }

  /// `child` is `parent` or below it, by `path.relative`, not by prefix: "/tmp/site-old" is no
  /// child of "/tmp/site".
  static func isInside(_ parent: String, _ child: String) -> Bool {
    let rel = NodePath.relative(FramePaths.resolve(parent), FramePaths.resolve(child))
    if rel.isEmpty { return true }
    return rel != ".." && !JSText.startsWith(rel, "../")
  }

  enum FolderState { case missing, unpublished, published }

  /// "unpublished" asks for one of the files this target put there, not for an empty folder: the
  /// bare mount point of a detached share often still holds a .DS_Store.
  static func state(_ dir: String, published: [String]) throws -> FolderState {
    var info = stat()
    if stat(dir, &info) != 0 {
      if errno == ENOENT { return .missing }
      throw Posix.error("scandir", dir)
    }
    guard opendir(dir).map({ closedir($0); return true }) ?? false else {
      if errno == ENOENT { return .missing }
      throw Posix.error("scandir", dir)
    }
    for path in published {
      var entry = stat()
      if lstat("\(dir)/\(path)", &entry) == 0 { return .published }
      if errno != ENOENT && errno != ENOTDIR { throw Posix.error("lstat", "\(dir)/\(path)") }
    }
    return .unpublished
  }

  public func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] {
    try DeployManifests(project: context.project).diff(context.target.id, buildDir: context.buildDir)
  }

  public func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
    guard context.destination["type"] == .string("folder") else {
      throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "Ordner"]))
    }
    let dest = FramePaths.resolve(JS.string(context.destination["path"]))
    // Both directions copy the tree into itself.
    if Self.isInside(context.buildDir, dest) || Self.isInside(dest, context.buildDir) {
      return DeployResult(success: false, output: L10n.t("main.folderOverlapsBuild", ["dest": dest, "build": context.buildDir]))
    }
    if Array(dest.utf8) == Array(FramePaths.resolve(context.project).utf8) {
      return DeployResult(success: false, output: L10n.t("main.folderIsProject"))
    }

    let manifests = DeployManifests(project: context.project)
    var output = ""
    do {
      let diff = try manifests.diff(context.target.id, buildDir: context.buildDir)
      let partition = DeployManifests.partition(diff, excluding: excludePaths, deleteRemoved: context.deleteRemoved)
      let total = partition.toUpload.count + partition.toDelete.count
      var processed = 0
      var ensuredDirs = Set<[UInt8]>()

      // A target published before whose folder is gone or holds none of its files is not looking
      // at that folder: a disk not connected, or the bare mount point it leaves.
      let published = manifests.read(context.target.id).paths
      if !published.isEmpty {
        let state = try Self.state(dest, published: published)
        if state == .missing && context.onlyPaths != nil {
          if Posix.exists(NodePath.dirname(dest)) { return DeployResult(success: true, output: L10n.t("main.relayRemoveGone", ["path": dest])) }
          return DeployResult(success: false, output: L10n.t("main.relayRemoveFolderMissing", ["dest": dest]))
        }
        if state == .missing { return DeployResult(success: false, output: L10n.t("main.folderMissing", ["dest": dest])) }
        if state == .unpublished {
          if context.onlyPaths != nil { return DeployResult(success: true, output: L10n.t("main.relayRemoveGone", ["path": dest])) }
          return DeployResult(success: false, output: L10n.t("main.folderNotPublished", ["dest": dest]))
        }
      }

      if let own = context.ownGeneration {
        let read: RelayGuard.Read
        do {
          read = .text(String(decoding: try Posix.read("\(dest)/\(RelayGuard.generatedFile)"), as: UTF8.self))
        } catch let error as NodeFileError where error.code == ENOENT || error.code == ENOTDIR {
          read = .missing
        } catch {
          read = .unreadable(JSText.split(PublishFailure.message(of: error), ",")[0])
        }
        if let refusal = RelayGuard.refusal(read, own: own, folder: dest) { return refusal }
      }

      for relPath in partition.toUpload {
        let target = "\(dest)/\(relPath)"
        let parent = NodePath.dirname(target)
        try Posix.mkdirs(parent)
        // The relay's folders get their modes as over SFTP: a copy carries a file's mode, and a
        // folder that was there kept its own.
        if context.keepLocalModes && ensuredDirs.insert(Array(parent.utf8)).inserted {
          let wanted = try NodeFileError.statFollowing("\(context.buildDir)/\(NodePath.dirname(relPath))").st_mode & 0o7777
          _ = chmod(parent, wanted)
          let actual = try NodeFileError.statFollowing(parent).st_mode & 0o7777
          if actual != wanted {
            output += L10n.t("main.folderModeNotSet", ["mode": String(wanted, radix: 8), "actual": String(actual, radix: 8), "path": parent]) + "\n"
          }
        }
        let scratch = "\(target).qc-\(random())"
        do {
          try Posix.copyFile("\(context.buildDir)/\(relPath)", scratch)
          try Posix.rename(scratch, target)
        } catch {
          try? Posix.unlink(scratch)
          throw error
        }
        processed += 1
        context.progress(processed, total, relPath)
        output += "→ \(relPath)\n"
      }

      // A refused deletion is said per file and the others are still tried; the file stays in the
      // manifest. A file that is already gone is no error, and while removing the relay it is not
      // said deleted either.
      var kept: [String] = []
      var missing = 0
      for relPath in partition.toDelete {
        let path = "\(dest)/\(relPath)"
        if Posix.kind(path) == .directory {
          kept.append(relPath)
          let key = context.onlyPaths != nil ? "main.relayRemoveRefused" : "main.deployDeleteRefused"
          output += key == "main.relayRemoveRefused"
            ? L10n.t("main.relayRemoveRefused", ["path": relPath, "reason": L10n.t("main.deleteIsFolder")])
            : L10n.t("main.deployDeleteRefused", ["path": relPath, "reason": L10n.t("main.deleteIsFolder")])
        } else if unlink(path) == 0 {
          output += "✗ \(relPath)\n"
        } else if errno == ENOENT {
          if context.onlyPaths != nil { missing += 1 } else { output += "✗ \(relPath)\n" }
        } else if errno == EACCES || errno == EPERM {
          let reason = JSText.split(PublishFailure.message(of: Posix.error("unlink", path)), ",")[0]
          kept.append(relPath)
          output += context.onlyPaths != nil
            ? L10n.t("main.relayRemoveRefused", ["path": relPath, "reason": reason])
            : L10n.t("main.deployDeleteRefused", ["path": relPath, "reason": reason])
        } else {
          throw Posix.error("unlink", path)
        }
        processed += 1
        context.progress(processed, total, relPath)
      }
      if context.onlyPaths != nil && missing == partition.toDelete.count { output += L10n.t("main.relayRemoveGone", ["path": dest]) }

      try manifests.commit(context.target.id, buildDir: context.buildDir, excluding: partition.manifestExcludes + kept)
      if context.onlyPaths != nil && !kept.isEmpty { return DeployResult(success: false, output: output + L10n.t("main.relayRemoveRefusedRest")) }
      return DeployResult(success: true, output: output.isEmpty ? L10n.t("main.deployNothingToDo") : output)
    } catch {
      // Without a leading empty line: the relay's panel announces the first line.
      let trimmed = JSText.replaceAll(output, "[\(JSText.space)]+\\z", with: "")
      return DeployResult(success: false, output: [trimmed, String(describing: error)].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
  }
}
