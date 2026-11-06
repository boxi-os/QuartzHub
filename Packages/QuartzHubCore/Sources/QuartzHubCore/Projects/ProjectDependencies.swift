import Foundation

/// What a fresh clone of a project lacks, asked before a Quartz call so that "missing" gets a
/// sentence of its own instead of Node's stack trace. A port of `projectDependencies.ts`.
///
/// A clone has no `node_modules` (never committed) and none of its authored frames (they live
/// under `.quartz-gui/`, which `.gitignore` keeps out); every Quartz call then died on its first
/// import, or `quartz plugin install` said "local path missing" and ended with 0, while the
/// overview said "Alles ok" (QuartzControl's alpha scenes 2026-10-17, findings 4.1 and 2.1).
public enum ProjectDependencies {
  /// The packages `package.json` names under `dependencies` that `node_modules` does not hold, in
  /// its order; empty when all are there. Nil when package.json cannot be read: "cannot tell", not
  /// "nothing missing", and the callers leave the question to npm and Quartz.
  public static func missingDependencies(project: URL) -> [String]? {
    guard let data = try? Data(contentsOf: project.appendingPathComponent("package.json")),
          let manifest = try? JSJSON.parse(data), manifest != .null else { return nil }
    return keys(manifest["dependencies"], spreadingStrings: false).filter { !hasNodeModule(project: project, $0) }
  }

  /// `hasNodeModule` (templatePackage/shared.ts): resolvable is what a build resolves against,
  /// `node_modules/<name>/package.json`, not the list in package.json.
  public static func hasNodeModule(project: URL, _ name: String) -> Bool {
    FileManager.default.fileExists(atPath: project.appendingPathComponent("node_modules/\(name)/package.json").path)
  }

  /// The first package in `name`'s dependency tree whose folder is there without a readable
  /// package.json, or nil when every folder found is whole. That is the state npm leaves while it
  /// unpacks (all folders within half a second, filled over the whole download). QuartzControl
  /// asked it before requiring a project's package in its own process, because Node remembers a
  /// missing package.json for the life of the process; QuartzHub asks it before the same packages
  /// run in a child, where it still tells "still unpacking" from "broken". Lookup as Node's: the
  /// package's own node_modules, then each one above it up to the project.
  public static func halfUnpackedModule(project: URL, _ name: String) -> String? {
    let projectPath = project.path
    var seen = Set<String>()
    var queue = [(name: name, from: projectPath)]
    while !queue.isEmpty {
      let next = queue.removeFirst()
      guard let dir = moduleDirectory(projectPath, from: next.from, next.name), seen.insert(dir).inserted else { continue }
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: dir + "/package.json")),
            let manifest = try? JSJSON.parse(data) else { return next.name }
      // `{ ...dependencies, ...optionalDependencies }`: the first one's order, new names after.
      var names: [String] = []
      for key in keys(manifest["dependencies"]) + keys(manifest["optionalDependencies"]) where !names.contains(key) {
        names.append(key)
      }
      queue += names.map { (name: $0, from: dir) }
    }
    return nil
  }

  private static func moduleDirectory(_ projectPath: String, from: String, _ name: String) -> String? {
    var dir = from
    while true {
      let candidate = FramePaths.resolve(dir + "/node_modules/" + name)
      if (dir as NSString).lastPathComponent != "node_modules" && FileManager.default.fileExists(atPath: candidate) {
        return candidate
      }
      let parent = (dir as NSString).deletingLastPathComponent
      if dir == projectPath || parent == dir { return nil }
      dir = parent
    }
  }

  /// The keys JavaScript finds in a manifest field: an object's keys and a list's indices ("0",
  /// "1": QuartzControl reported those as missing packages). A spread also takes a string apart
  /// into its UTF-16 indices; `missingDependencies` asks `typeof === 'object'` first and does not.
  private static func keys(_ value: JSONValue?, spreadingStrings: Bool = true) -> [String] {
    switch value {
    case .object(let object)?: object.keys
    case .array(let items)?: items.indices.map(String.init)
    case .string(let string)? where spreadingStrings: (0..<string.utf16.count).map(String.init)
    default: []
    }
  }

  /// The config's entries that name an authored frame whose folder is not there, by name. A frame
  /// copied into this project's `.quartz-gui/` is not missing while the config still names the
  /// other path: the build door repoints it. Nil when the config cannot be read; the overview says
  /// that one on its own.
  public static func missingAuthoredFrames(project: URL, runtime: RuntimeLocation = .current) async -> [String]? {
    guard let config = try? await ConfigFile.read(project: project, runtime: runtime) else { return nil }
    return config.plugins.filter { entry in
      guard case .string(let source)? = entry.source, source.contains(FramePaths.marker),
            !FileManager.default.fileExists(atPath: source) else { return false }
      return FramePaths.ownFramePath(project: project, source) == nil
    }.map(\.name)
  }
}
