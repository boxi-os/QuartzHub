import Foundation

/// The rules for a target's remote path and the relay's folder below it (QuartzControl's
/// `shared/remotePath.ts`). One copy for the target form and for the services, so the form never
/// offers a value the save or the upload refuses.
///
/// A relative path is allowed: sftp and ftp join it, rsync appends it to `user@host:`, and all
/// three resolve it against the login's own directory, which is how a shared webspace is normally
/// addressed ("httpdocs").
public enum RemotePath {
  public enum Problem: String, Sendable {
    /// Nothing to deploy into.
    case empty
    /// The login's own directory with deletion on: a deploy would empty it.
    case wholeRoot = "whole-root"
    /// A ".." segment; no target needs one.
    case traversal
  }

  /// What is wrong with a remote path, or nil. "/", ".", "~" and "~user" all name the login's own
  /// directory, which is refused only with deletion: some hosts keep the site right there.
  public static func problem(_ path: String, deleteRemoved: Bool) -> Problem? {
    let trimmed = JS.trim(path)
    if trimmed.isEmpty { return .empty }
    let segments = JSText.split(trimmed, "/").filter { !$0.isEmpty && $0 != "." }
    if segments.contains("..") { return .traversal }
    let below = JSText.test(segments.first ?? "", #"\A~[^/]*\z"#) ? Array(segments.dropFirst()) : segments
    if below.isEmpty && deleteRemoved { return .wholeRoot }
    return nil
  }

  /// "~" is left out on purpose: a leading "~/" or "~user/" is meant to expand there. Not to be
  /// loosened: rsync 3.2.4 and later leave wildcards to the remote glob, and openrsync has no
  /// --protect-args, so its remote shell reads the path once more.
  static let shellSpecial = #"['"\\$`;&|<>(){}\[\]*?!#]"#

  /// The first character rsync cannot carry safely, or nil: whitespace (JavaScript's `\s`) before
  /// anything a shell gives a meaning to.
  public static func rsyncUnsafeChar(_ path: String) -> String? {
    JSText.firstMatch(path, "[\(JSText.space)]")?.groups[0] ?? JSText.firstMatch(path, shellSpecial)?.groups[0]
  }

  /// The relay's folder below a target's path, slashes at either end dropped, or nil when it is
  /// not a folder of its own: empty, NUL, or an empty, "." or ".." segment anywhere. With "." the
  /// relay would set the modes of the target's own folder (measured on debian-vm by QuartzControl:
  /// 2750 webroots left 755).
  public static func relaySubdir(_ raw: String) -> String? {
    let subdir = JSText.replaceAll(JS.trim(raw), #"\A/+|/+\z"#, with: "")
    let segments = JSText.split(subdir, "/")
    guard !subdir.isEmpty, !JSText.includes(subdir, "\0"), segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
    return subdir
  }

  /// A path with a leading "~" or "~<the login's own account>" as the folder the login starts in
  /// (which SFTP and FTP ask the server for); any other path as it is; nil for "~" of another
  /// account, which neither can name. Over SFTP and FTP "~" meant something else on every server
  /// before (OpenSSH made a folder "~", vsftpd expanded "~/", Pure-FTPd answered 553).
  public static func fromLoginDir(_ path: String, loginDir: String, account: String) -> String? {
    guard let tilde = JSText.firstMatch(path, #"\A~([^/]*)(?:/+|\z)"#) else { return path }
    let user = tilde.groups[1] ?? ""
    if !user.isEmpty && user != account { return nil }
    let rest = JSText.slice(path, tilde.end)
    let base = JSText.replaceAll(loginDir, #"/+\z"#, with: "")
    return rest.isEmpty ? (base.isEmpty ? "/" : base) : "\(base)/\(rest)"
  }
}
