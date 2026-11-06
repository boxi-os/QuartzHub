import Darwin
import Foundation

/// The absolute paths into a project that the project itself records, and pointing them at where
/// the project is now. A port of `projectPaths.ts`.
///
/// An authored frame is a plugin whose source is an absolute path into the project it was authored
/// in, and three places record that path: the plugin entry's `source` in quartz.config.yaml,
/// `source` and `resolved` in quartz.lock.json, and the symlink `.quartz/plugins/<id>` that
/// `quartz plugin add` laid down. Duplicating copies them verbatim (the copy built from the
/// original's frames), and renaming or moving left all three naming a folder that is gone
/// (QuartzControl's BEFUNDE 8). Every path inside the old folder is rewritten, not only the
/// frames; a plugin installed from elsewhere on disk means the same in both places.
public enum ProjectPaths {
  /// After a duplicate or a relocate: every recorded path inside `from` moves to `to`.
  public static func repointProjectPaths(from: URL, to: URL, runtime: RuntimeLocation = .current) async throws {
    let base = FramePaths.resolve(from.path)
    try await rewriteRecordedPaths(project: to, runtime: runtime) { path in
      guard path.hasPrefix("/") else { return nil }
      let absolute = FramePaths.resolve(path)
      let relative: String
      if absolute == base {
        relative = ""
      } else if absolute.hasPrefix(base == "/" ? "/" : base + "/") {
        relative = String(absolute.dropFirst(base == "/" ? 1 : base.count + 1))
        // Node's `relative(...).startsWith('..')`, which also takes a child named `..x` as outside.
        if relative.hasPrefix("..") { return nil }
      } else {
        return nil
      }
      return FramePaths.resolve(to.path + "/" + relative)
    }
  }

  /// The same three places, driven by the frame pattern instead of a prefix, for when there is no
  /// `from`: a restored snapshot (its config and lockfile hold the path of the moment they were
  /// recorded; QuartzControl found it in 8 of 8 and 6 of 7 snapshots of two projects), a folder
  /// copied outside the app, the build door. The rule and its limit are `FramePaths.ownFramePath`.
  public static func repointAuthoredFrames(project: URL, runtime: RuntimeLocation = .current) async throws {
    try await rewriteRecordedPaths(project: project, runtime: runtime) { FramePaths.ownFramePath(project: project, $0) }
  }

  static func rewriteRecordedPaths(project: URL, runtime: RuntimeLocation,
                                   _ rewrite: (String) -> String?) async throws {
    // A folder with no config is not a Quartz project (yet): nothing here to repair.
    guard FileManager.default.fileExists(atPath: ConfigFile.path(project: project).path) else { return }

    // Read and write under the config's lock, or a save in between is undone by this write. The
    // CLI's own writes are not under it; they rewrite the file themselves. No snapshot: this is a
    // repair, and a duplicate has no store to write into yet.
    try await ProjectLock.config.run(project.path) {
      var config = try await ConfigFile.read(project: project, runtime: runtime)
      var changed = false
      for index in config.plugins.indices {
        guard case .string(let source)? = config.plugins[index].source, let next = rewrite(source) else { continue }
        config.plugins[index].object["source"] = .string(next)
        changed = true
      }
      if changed { try await ConfigFile.write(config, project: project, runtime: runtime) }
    }

    try rewriteLockfile(project: project, rewrite)
    try relinkInstalledPlugins(project: project, rewrite)
  }

  /// `source` and `resolved` per entry. A lockfile that cannot be read is not this operation's
  /// problem: the project is no worse off, and `quartz plugin install` is what reports it. Not a
  /// JSONStore file either; it is Quartz's, and nothing here moves it aside.
  static func rewriteLockfile(project: URL, _ rewrite: (String) -> String?) throws {
    let url = project.appendingPathComponent("quartz.lock.json")
    guard let data = try? Data(contentsOf: url), case .object(var lock) = try? JSJSON.parse(data) else { return }
    var changed = false
    func fix(_ entry: JSONValue) -> JSONValue {
      guard case .object(var object) = entry else { return entry }
      for key in ["source", "resolved"] {
        guard case .string(let value)? = object[key], let next = rewrite(value) else { continue }
        object[key] = .string(next)
        changed = true
      }
      return .object(object)
    }
    // `Object.values` of whatever `plugins` is: an object's values or a list's items.
    switch lock["plugins"] {
    case .object(var entries)?:
      for key in entries.keys { entries[key] = fix(entries[key]!) }
      lock["plugins"] = .object(entries)
    case .array(let entries)?:
      lock["plugins"] = .array(entries.map(fix))
    default:
      return
    }
    // In the CLI's own form (writeLockfile in quartz/cli/plugin-data.js), trailing newline included:
    // without it the next CLI write shows up as a change to a file nobody edited.
    guard changed else { return }
    try JSONStore.writeAtomic(Data((JSJSON.stringify(.object(lock)) + "\n").utf8), to: url)
  }

  /// The links under `.quartz/plugins/`, resolved against their own folder (a link may be
  /// relative, and a dangling one still has a target, which is exactly the case repaired here).
  static func relinkInstalledPlugins(project: URL, _ rewrite: (String) -> String?) throws {
    let plugins = project.appendingPathComponent(".quartz/plugins")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: plugins.path) else { return }
    for name in names.sorted() {
      let link = plugins.appendingPathComponent(name)
      var info = stat()
      guard lstat(link.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK,
            let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { continue }
      let absolute = target.hasPrefix("/") ? FramePaths.resolve(target) : FramePaths.resolve(plugins.path + "/" + target)
      guard let next = rewrite(absolute) else { continue }
      try FileManager.default.removeItem(at: link)
      try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: next)
    }
  }
}
