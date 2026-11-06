import Foundation

/// The one place that creates `<project>/.quartz-gui/`, a port of `quartzGuiDir` in
/// `electron/main/services/projectDirs.ts`. Readers use `QuartzGuiDirectory.url`/`file(_:)` and
/// never this: "Ein Lesepfad legt nie `.quartz-gui/` an."
///
/// Creating the folder also puts `.quartz-gui/` into the project's `.gitignore`, because the folder
/// sits inside the user's own repository and `quartz sync` pushes everything: the config backups
/// are verbatim copies of `quartz.config.yaml` and would otherwise end up in what is usually a
/// public repo. Only in a repository (`.git` there, as a folder or a worktree's file), and only when
/// no line says so already. What decides that is the rule line, never the comment above it, so a
/// project that got QuartzControl's comment keeps it and gains nothing.
extension QuartzGuiDirectory {
  static let ignoreLine = ".quartz-gui/"

  /// `<project>/.quartz-gui[/sub…]`, created with every folder above it, and the ignore rule.
  @discardableResult
  public func create(_ sub: String...) throws -> String {
    let dir = ([path] + sub).joined(separator: "/")
    try Posix.mkdirs(dir)
    try ensureIgnored()
    return dir
  }

  /// Bytes, not text: QuartzControl read the file as UTF-8 and wrote it back whole, so a byte
  /// that is not UTF-8 came back as U+FFFD. Here the existing bytes stay as they are and the block
  /// is appended; only the check reads them as text.
  func ensureIgnored() throws {
    guard Posix.exists("\(project)/.git") else { return }
    let path = "\(project)/.gitignore"
    let existing = (try? Posix.read(path)) ?? Data()
    // JavaScript's trim() also takes the byte order mark, which a file saved by some editors
    // starts with.
    let blank = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
    // Not `split(separator: "\n")`: "\r\n" is one Character in Swift, so a file with Windows
    // line ends was one long line and got the block again on every call.
    let ignored = String(decoding: existing, as: UTF8.self)
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: blank) }
      .contains { $0 == Self.ignoreLine || $0 == ".quartz-gui" }
    if ignored { return }
    let prefix = !existing.isEmpty && existing.last != UInt8(ascii: "\n") ? "\n" : ""
    // In the app's language: the line is written into the user's repository, and they read it.
    let block = "\(prefix)\n# \(L10n.t("main.gitignoreComment"))\n\(Self.ignoreLine)\n"
    // In place, as writeFileSync: a .gitignore that is a symlink stays one.
    try Posix.write(path, existing + Data(block.utf8))
  }
}
