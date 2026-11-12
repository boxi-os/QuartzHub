import Darwin
import Foundation

/// What has to happen before `quartz build` may empty an output folder (QuartzControl's
/// `buildOutputGuard.ts`, measured in BuildOutputGuardTests).
///
/// `quartz build --output <dir>` begins with `rm(output, { recursive: true, force: true })`
/// (`quartz/build.ts`): no bin, no question. QuartzHub offers a folder picker for that field and
/// takes a relative path, so a handful of folders are refused outright and any other that already
/// holds something which is not a Quartz build is asked about first.
public enum OutputDirVerdict: Sendable, Equatable {
  case ok
  /// Holds something that is not a build; deleting it needs an explicit yes.
  case confirm(entryCount: Int)
  case refused(Refusal)

  public enum Refusal: Sendable, Equatable {
    case project
    /// The folder holds the project (an ancestor, the home that contains it, "/").
    case containsProject
    case home
    /// Inside one of the project's own folders (`content`, `.git`, …), named.
    case protected(String)
  }
}

public enum BuildOutputGuard {
  /// Folders in the project a build must never delete: the notes, Quartz's source, the
  /// repository, the app's folder, Quartz's cache, the dependencies. Named, not derived: "all but
  /// the output" would also refuse `dist/`, a sensible place to build into.
  public static let protectedFolders = ["content", "quartz", ".git", ".quartz-gui", ".quartz-cache", "node_modules"]

  /// Where `quartz build` writes for this `outputDir`: `public/` for none or "", an absolute path
  /// as it is (the export dialog gives one), a relative one joined and normalized like `path.join`
  /// (QuartzControl's `resolveBuildDir`).
  public static func buildDirectory(project: String, outputDir: String?) -> String {
    guard let outputDir, !outputDir.isEmpty else { return resolve(project + "/public") }
    return outputDir.hasPrefix("/") ? outputDir : resolve(project + "/" + outputDir)
  }

  /// A folder that already holds a built site, so a rebuild into it deletes only its own previous
  /// output: `index.html` and one of the other things every build writes. By name, as listed.
  public static func looksLikeQuartzBuild(_ directory: String) -> Bool {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return false }
    let entries = Set(names)
    guard entries.contains("index.html") else { return false }
    return !entries.isDisjoint(with: ["static", "index.xml", "sitemap.xml", "404.html"])
  }

  /// The verdict for building `project` into `outputDir`. `home` is the user's home folder.
  ///
  /// Beyond QuartzControl, the refusals are asked twice: for the path as written, and for the
  /// folder it really reaches (`realPath`). On APFS "Content" is `content`, and a path through a
  /// symlink deletes in the link's target; QuartzControl compared strings and only asked "2
  /// entries?" before Quartz deleted the notes (measured: `rm` of "CONTENT/sub" removed
  /// `content/sub`; of a link itself, only the link). Who asks whether something is still needed
  /// asks broadly (conventions, "Wer fragt, ob etwas noch gebraucht wird, sucht breit").
  public static func assess(project: String, outputDir: String?, home: String = NSHomeDirectory()) -> OutputDirVerdict {
    let written = (dir: resolve(buildDirectory(project: project, outputDir: outputDir)), project: resolve(project), home: resolve(home))
    let real = (dir: realPath(written.dir), project: realPath(written.project), home: realPath(written.home))
    for paths in [written, real] {
      if let refusal = refusal(dir: paths.dir, project: paths.project, home: paths.home) { return .refused(refusal) }
    }

    var isDirectory: ObjCBool = false
    // Does not exist yet: the build makes it.
    guard FileManager.default.fileExists(atPath: written.dir, isDirectory: &isDirectory) else { return .ok }
    // A path that is not a folder is deleted by the same rm: better asked about one file.
    guard isDirectory.boolValue else { return .confirm(entryCount: 1) }
    // Unreadable is "ok", as in QuartzControl: Quartz's rm cannot list it either, and the build
    // ends with its error before anything is gone.
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: written.dir), !entries.isEmpty else { return .ok }
    if looksLikeQuartzBuild(written.dir) { return .ok }
    return .confirm(entryCount: entries.count)
  }

  static func refusal(dir: String, project: String, home: String) -> OutputDirVerdict.Refusal? {
    if dir == project { return .project }
    // Covers every ancestor of the project, a home that contains it among them.
    if isInside(dir, project) { return .containsProject }
    if dir == home { return .home }
    for name in protectedFolders where isInside(project + "/" + name, dir) { return .protected(name) }
    return nil
  }

  /// `child` is `parent` or lies below it; "/tmp/site-old" is not below "/tmp/site".
  static func isInside(_ parent: String, _ child: String) -> Bool {
    child == parent || child.hasPrefix(parent == "/" ? "/" : parent + "/")
  }

  /// `path.resolve` for an absolute path: "." and ".." resolved, no trailing slash, links untouched.
  static func resolve(_ path: String) -> String { FramePaths.resolve(path) }

  /// The folder a path really reaches: `realpath` of the longest part that exists (spelling as on
  /// disk, links followed), the rest appended as written.
  static func realPath(_ path: String) -> String {
    var head = path
    var rest: [Substring] = []
    while true {
      var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
      if realpath(head, &buffer) != nil {
        let found = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return rest.isEmpty ? found : resolve(found + "/" + rest.reversed().joined(separator: "/"))
      }
      guard head != "/", let slash = head.lastIndex(of: "/") else { return path }
      rest.append(head[head.index(after: slash)...])
      head = slash == head.startIndex ? "/" : String(head[..<slash])
    }
  }
}

extension OutputDirVerdict.Refusal {
  /// The sentence QuartzControl's build handler threw for a refused folder (`buildDirRefused` with
  /// its reason); `dir` as `BuildOutputGuard.buildDirectory` resolved it.
  public func message(dir: String) -> String {
    let why = switch self {
    case .project: L10n.t("main.buildDirIsProject")
    case .containsProject: L10n.t("main.buildDirContainsProject")
    case .home: L10n.t("main.buildDirIsHome")
    case .protected: L10n.t("main.buildDirReserved")
    }
    return L10n.t("main.buildDirRefused", ["dir": dir, "why": why])
  }
}
