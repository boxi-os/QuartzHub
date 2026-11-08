import Foundation

/// The overview's band "Handlungsbedarf": what in a project needs the user, in QuartzControl's
/// order, and when the page may say "Alles ok" instead (`ProjectDashboard.tsx`, the `issues` list
/// and the condition under it). Kept here rather than in the page so every rule has a test; each
/// one came from a review or an alpha scene there, named at the rule.
///
/// The reads are the page's: each may still be under way, and one that failed must not read as
/// "nothing wrong".
public enum ProjectAttention {
  public struct Issue: Equatable, Sendable, Identifiable {
    public enum Tone: Sendable { case red, amber }

    /// Stable, QuartzControl's ids ("dependencies", "git-conflict", …); the page picks its symbol by it.
    public var id: String
    public var tone: Tone
    public var title: String
    public var detail: String?
    /// The page that owns it, by its sidebar id, and the tab there when it has one.
    public var page: String
    public var tab: String?
    public var linkLabel: String
    /// The missing packages: the overview offers "Installieren" in place of the link.
    public var installs: Bool = false
  }

  /// A read that may still be under way or may have failed (with what was said, when anything).
  public enum Read<Value: Sendable & Equatable>: Sendable, Equatable {
    case reading
    case failed(String?)
    case done(Value)

    var value: Value? { if case .done(let value) = self { value } else { nil } }
  }

  public struct Reads: Sendable, Equatable {
    /// The packages `package.json` names that `node_modules` lacks; failed when it cannot be read.
    public var missingPackages: Read<[String]> = .reading
    /// An install from here or from Plugins ▸ Wartung is running.
    public var installing = false
    public var missingFrames: [String]?
    public var server = BuildService.ServerStatus(state: .stopped)
    public var content: ContentFolder.Status?
    public var git: GitStatus?
    public var scss: ScssCheck.Result?
    public var core: CoreUpdate.Status?
    public var config: QuartzConfig?

    public init() {}
  }

  /// `config.configuration.baseUrl`, trimmed; "" when it is no text.
  public static func baseUrl(_ config: QuartzConfig?) -> String {
    JS.trim(config?.configuration["baseUrl"]?.stringValue ?? "")
  }

  public static func issues(_ reads: Reads) -> [Issue] {
    var issues: [Issue] = []
    let plugins = L10n.t("projectLayout.tabs.plugins")
    // First, because nothing else works until it is fixed: a clone has no node_modules, and every
    // Quartz call died on its first import while the band said "Alles ok" (alpha scenes
    // 2026-10-17, finding 4.1).
    let missing = reads.missingPackages.value
    if missing?.isEmpty == false || reads.installing {
      let count = missing?.count ?? 0
      issues.append(Issue(
        id: "dependencies", tone: .red,
        title: reads.installing ? L10n.t("dashboard.attention.dependenciesInstallingTitle")
          : L10n.t("dashboard.attention.dependenciesMissing", ["count": String(count)], count: count),
        detail: L10n.t("dashboard.attention.dependenciesMissingDetail"), page: "plugins", linkLabel: plugins, installs: true))
    } else if case .failed(let why) = reads.missingPackages {
      issues.append(Issue(
        id: "dependencies-unreadable", tone: .amber, title: L10n.t("dashboard.attention.dependenciesUnreadable"),
        detail: why ?? L10n.t("dashboard.attention.dependenciesUnreadableDetail"), page: "plugins", linkLabel: plugins))
    }
    // A clone has no authored frames (they stay in .quartz-gui/ on the machine that made them),
    // and the build was green with the layout gone (alpha scenes 2026-10-17, finding 2.1).
    if let frames = reads.missingFrames, !frames.isEmpty {
      issues.append(Issue(
        id: "frames", tone: .amber,
        title: L10n.t("dashboard.attention.framesMissing", ["count": String(frames.count)], count: frames.count),
        detail: L10n.t("dashboard.attention.framesMissingDetail"), page: "layout", linkLabel: L10n.t("projectLayout.tabs.layout")))
    }
    if reads.server.state == .error {
      issues.append(Issue(
        id: "server", tone: .red, title: L10n.t("dashboard.attention.serverError"), detail: serverErrorText(reads.server),
        page: "server", linkLabel: L10n.t("projectLayout.tabs.server")))
    }
    let contentTab = L10n.t("dashboard.contentTab")
    if let content = reads.content {
      if content.isSymlink && content.targetExists == false {
        issues.append(Issue(
          id: "content", tone: .red, title: L10n.t("dashboard.attention.contentTargetMissing"), detail: content.symlinkTarget,
          page: "config", tab: "site", linkLabel: contentTab))
      }
      if !content.exists {
        issues.append(Issue(
          id: "content-missing", tone: .amber, title: L10n.t("dashboard.attention.contentMissing"),
          page: "config", tab: "site", linkLabel: contentTab))
      }
      if content.hasIndex == false {
        issues.append(Issue(
          id: "no-index", tone: .amber, title: L10n.t("dashboard.attention.noIndex"),
          detail: L10n.t("dashboard.attention.noIndexDetail"), page: "config", tab: "site", linkLabel: contentTab))
      }
    }
    let sync = L10n.t("projectLayout.tabs.sync")
    if let git = reads.git {
      if git.conflictCount > 0 {
        issues.append(Issue(
          id: "git-conflict", tone: .red,
          title: L10n.t("dashboard.attention.gitConflicts", ["count": String(git.conflictCount)], count: git.conflictCount),
          detail: L10n.t("dashboard.attention.gitConflictsDetail"), page: "sync", linkLabel: sync))
      } else if let operation = git.inProgress {
        issues.append(Issue(
          id: "git-progress", tone: .amber, title: L10n.t("dashboard.attention.gitInProgress", ["operation": operation.rawValue]),
          page: "sync", linkLabel: sync))
      } else if let error = git.readError {
        // "Alles ok" waits for git, so without this line an unreadable git left the band empty,
        // neither "Alles ok" nor a reason (forty-sixth review, Niedrig 3).
        issues.append(Issue(
          id: "git-unreadable", tone: .amber, title: L10n.t("dashboard.attention.gitUnreadable"), detail: error,
          page: "sync", linkLabel: sync))
      }
    }
    if case .error(let diagnostic) = reads.scss {
      // `[path, line, message].filter(Boolean)`: an empty text drops out as well.
      let parts = [diagnostic.relativePath, diagnostic.line.map { L10n.t("dashboard.attention.line", ["line": String($0)]) },
                   diagnostic.message].compactMap { $0 }.filter { !$0.isEmpty }
      // The tab "customCss", Styles' own name for it (twenty-eighth review).
      issues.append(Issue(
        id: "scss", tone: .amber, title: L10n.t("dashboard.attention.scssError"), detail: parts.joined(separator: " · "),
        page: "styles", tab: "customCss", linkLabel: L10n.t("projectLayout.tabs.styles")))
    }
    // A core update that merged and stopped before npm put the project's own packages back
    // (twenty-third review, finding 1); two states under one title (twenty-sixth, finding 2).
    if let core = reads.core, core.state == .pending {
      let packages = core.pendingPackages ?? []
      issues.append(Issue(
        id: "core-update-pending", tone: .amber, title: L10n.t("dashboard.attention.coreUpdatePending"),
        detail: packages.isEmpty ? L10n.t("dashboard.attention.coreUpdatePendingInstallDetail")
          : L10n.t("dashboard.attention.coreUpdatePendingDetail", ["packages": packages.joined(separator: ", ")]),
        page: "updates", linkLabel: L10n.t("projectLayout.tabs.updates")))
    }
    if reads.config != nil && baseUrl(reads.config).isEmpty {
      issues.append(Issue(
        id: "baseurl", tone: .amber, title: L10n.t("dashboard.attention.noBaseUrl"),
        detail: L10n.t("dashboard.attention.noBaseUrlDetail"), page: "config", tab: "site",
        linkLabel: L10n.t("projectLayout.tabs.config")))
    }
    return issues
  }

  /// "Alles ok" names content, git, CSS and the configuration, so it waits for all of them, and
  /// for the package check, which flashed "Alles ok" before the red dependency line when git
  /// answered first (alpha scenes 2026-10-17, scene 6).
  public static func allGood(_ reads: Reads) -> Bool {
    guard issues(reads).isEmpty, reads.config != nil, reads.content != nil, reads.missingPackages.value != nil,
          let git = reads.git, git.readError == nil, let scss = reads.scss else { return false }
    if case .unavailable = scss { return false }
    return true
  }

  /// Why a dev server is in the error state, or nil when it is not (QuartzControl's
  /// `serverErrorText`, shared by the overview and Vorschau & Build): what the system said about a
  /// failed start as it was said, otherwise the exit code of a process that started and died.
  public static func serverErrorText(_ status: BuildService.ServerStatus) -> String? {
    guard status.state == .error else { return nil }
    if let error = status.error { return error }
    if case .exited(let code)? = status.ended { return L10n.t("buildServer.exitedWithCode", ["code": String(code)]) }
    return L10n.t("buildServer.exitedUnexpectedly")
  }
}
