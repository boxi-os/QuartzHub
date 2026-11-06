import Foundation

/// An authored frame lives at `<project>/.quartz-gui/authored-frames/<id>` and nowhere else, so the
/// id is its identity and the prefix in front of the marker is noise. A port of `framePaths.ts`.
public enum FramePaths {
  static let marker = "/.quartz-gui/authored-frames/"

  /// The path of this project's own frame that `path` means, or nil when there is nothing to
  /// change: not a frame path, already this project's, or a frame this project does not have.
  ///
  /// The last one is the limit of the rule. A project that names another project's frame on
  /// purpose keeps it, unless it has a frame with the same id itself. Ids are `frame-<timestamp>`
  /// or `frame-<name>`, and the second kind can repeat between projects; accepted, because naming
  /// another project's frame by absolute path is what a copy does by accident and nobody does on
  /// purpose (QuartzControl's forty-second review, finding 6).
  ///
  /// Paths are compared as Node's `resolve` does, by their text: no `realpath`.
  ///
  /// By bytes, as `===`: a project path that differs only in its Unicode form is another text to
  /// QuartzControl, which repoints it; Swift's `==` would leave it.
  public static func ownFramePath(project: String, _ path: String) -> String? {
    guard path.hasPrefix("/") else { return nil }
    let absolute = resolve(path)
    guard let at = absolute.range(of: marker) else { return nil }
    let projectPath = resolve(project)
    if Array(resolve(String(absolute[..<at.lowerBound])).utf8) == Array(projectPath.utf8) { return nil }
    let next = resolve(projectPath + "/" + absolute[absolute.index(after: at.lowerBound)...])
    return FileManager.default.fileExists(atPath: next) ? next : nil
  }

  /// `path.resolve` for an absolute path: `.` and `..` resolved, repeated and trailing slashes gone.
  static func resolve(_ path: String) -> String {
    var parts: [Substring] = []
    for part in path.split(separator: "/") {
      switch part {
      case ".": continue
      case "..": _ = parts.popLast()
      default: parts.append(part)
      }
    }
    return "/" + parts.joined(separator: "/")
  }
}
