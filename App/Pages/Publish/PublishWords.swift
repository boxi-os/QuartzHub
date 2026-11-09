import QuartzHubCore

/// The words of Veröffentlichen that depend on a value, with the keys spelled out for
/// `qh-check i18n` (QuartzControl built them as `publish.….${value}`).
@MainActor
enum PublishWords {
  /// `destinationTypeLabel`: the words the type picker offers. A type of a later version is named
  /// as such, not as one this version knows.
  static func type(_ type: String) -> String {
    switch type {
    case "sftp": "SFTP"
    case "ftp": "FTP"
    case "folder": L10n.t("publish.targetForm.typeFolder")
    case "webhook": L10n.t("publish.targetForm.typeWebhook")
    case "document": L10n.t("publish.targetForm.typeDocument")
    case "git-branch": L10n.t("publish.targetForm.typeGitBranch")
    default: L10n.t("publish.targetForm.typeUnknown", ["type": type])
    }
  }

  static let types = ["sftp", "ftp", "folder", "webhook", "git-branch", "document"]

  /// `destinationLine`: where a target sends the site, in one line; the row and the inspector say it alike.
  static func destination(_ target: PublishTarget, connections: [Connection]) -> String {
    let d = target.destination
    let connection = target.connectionId.flatMap { id in connections.first { $0.id == id } }
    switch d["type"]?.stringValue {
    case "folder":
      return d["path"]?.stringValue ?? ""
    case "document":
      let book = d["bookId"]?.stringValue ?? ""
      let files = (d["formats"]?.arrayValue ?? []).compactMap(\.stringValue).map { "\(book).\($0)" }
      return "\(d["path"]?.stringValue ?? "") → \(files.joined(separator: ", "))"
    case "git-branch":
      return "origin → \(d["branch"]?.stringValue ?? "")"
    case "webhook":
      if let connection, connection.kind == .webhook, let origin = connection.displayOrigin { return "POST → \(origin)" }
      return L10n.t("publish.webhookNoUrl")
    default:
      let path = d["remotePath"]?.stringValue ?? ""
      if let connection, connection.kind == .ssh || connection.kind == .ftp {
        return "\(connection.username)@\(connection.host):\(connection.port) → \(path)"
      }
      return path
    }
  }

  /// `requiredKind`: the connection a destination needs; a folder, a branch and a document need none.
  static func requiredKind(_ type: String) -> StoredConnection.Kind? {
    switch type {
    case "sftp": .ssh
    case "ftp": .ftp
    case "webhook": .webhook
    default: nil
    }
  }

  static func remotePathError(_ problem: RemotePath.Problem) -> String {
    switch problem {
    case .empty: L10n.t("publish.targetForm.remotePathError.empty")
    case .wholeRoot: L10n.t("publish.targetForm.remotePathError.whole-root")
    case .traversal: L10n.t("publish.targetForm.remotePathError.traversal")
    }
  }

  static func rsyncBlocked(_ reason: RsyncSupport.BlockReason?) -> String {
    switch reason {
    case .passwordAuth: L10n.t("publish.rsyncBlocked.password-auth")
    case .keyNotAFile: L10n.t("publish.rsyncBlocked.key-not-a-file")
    case .noPinnedHostKey: L10n.t("publish.rsyncBlocked.no-pinned-host-key")
    case .notInstalled: L10n.t("publish.rsyncBlocked.not-installed")
    case nil: L10n.t("publish.rsyncBlocked.no-connection")
    }
  }

  static func branchHint(_ provider: String) -> String {
    switch provider {
    case "gitlab": L10n.t("publish.branchHint.gitlab")
    case "codeberg": L10n.t("publish.branchHint.codeberg")
    default: L10n.t("publish.branchHint.github")
    }
  }

  static func status(_ status: DeployDiffEntry.Status) -> String {
    switch status {
    case .added: L10n.t("publish.status.added")
    case .changed: L10n.t("publish.status.changed")
    case .removed: L10n.t("publish.status.removed")
    }
  }

  /// GitHub's build state; one GitHub adds later is said as GitHub says it.
  static func pagesStatus(_ status: String?) -> String {
    switch status {
    case "building": L10n.t("publish.pages.status.building")
    case "built": L10n.t("publish.pages.status.built")
    case "errored": L10n.t("publish.pages.status.errored")
    case nil: L10n.t("publish.pages.status.unknown")
    case let other?: other
    }
  }

  static func format(_ format: String) -> String {
    switch format {
    case "pdf": L10n.t("publish.targetForm.format.pdf")
    case "epub": L10n.t("publish.targetForm.format.epub")
    default: L10n.t("publish.targetForm.format.html")
    }
  }

  static func downloadLink(_ format: String) -> String {
    switch format {
    case "pdf": L10n.t("publish.targetForm.downloadLink.pdf")
    case "epub": L10n.t("publish.targetForm.downloadLink.epub")
    default: L10n.t("publish.targetForm.downloadLink.html")
    }
  }
}
