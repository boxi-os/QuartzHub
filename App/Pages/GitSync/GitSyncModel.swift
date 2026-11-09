import AppKit
import QuartzHubCore
import SwiftUI

/// What the Git-Sync page reads and runs (QuartzControl's `GitSync.tsx`).
///
/// One model per project, as on Updates: a push or a pull talks to another host and can take
/// minutes, and the page opened again should show it still going or how it ended. The status is
/// read again on every opening.
@MainActor @Observable
final class GitSyncModel {
  private static var models: [String: GitSyncModel] = [:]

  static func shared(_ project: ProjectContext) -> GitSyncModel {
    if let model = models[project.path] { return model }
    let model = GitSyncModel(project: project)
    models[project.path] = model
    return model
  }

  struct Outcome: Equatable {
    var success: Bool
    var output: String
  }

  /// A sentence that belongs to the moment after a click and to nothing after it (QuartzControl's
  /// `abortNote`): the next step taken on the page takes it down.
  struct Notice: Equatable {
    var text: String
    var isError = false
    /// git's or GitHub's text, shown as it came.
    var verbatim = false
  }

  let project: ProjectContext
  var status: GitStatus?
  /// The github.com repository behind origin, for "Auf GitHub öffnen"; nil for any other host.
  var repo: GitHubAPI.RepoRef?
  private var round = 0
  private var reads = 0
  var refreshing: Bool { reads > 0 }

  var busy: Sync.Direction?
  var result: Outcome?
  var aborting = false
  var notice: Notice?

  /// Who the GitHub token belongs to; nil until asked, and when there is no token that works.
  var viewer: GitHubAPI.Account?
  var creating = false
  var createResult: Outcome?

  private init(project: ProjectContext) {
    self.project = project
  }

  private var path: String { project.path }

  private func environment() async -> ToolEnvironment {
    await AppServices.shared.environment.value
  }

  private func github(_ environment: ToolEnvironment) -> GitHubAPI {
    GitHubAPI(environment: environment, token: AppDeploy.connections().gitToken)
  }

  // MARK: Reading

  /// The page opened: the last click's sentence belongs to the visit that caused it. The run's
  /// result stays, as on Updates: it is what the page opened again is for.
  func appear() async {
    notice = nil
    await reload()
  }

  /// "Aktualisieren" is a step of its own, so it takes the sentence down as well.
  func refresh() async {
    notice = nil
    await reload()
  }

  /// `GitStatus.read` does not throw: a failed `git status` is its `readError`, so a status is
  /// always there after the first read and never one from before (QuartzControl cleared it on a
  /// throw for that reason). Only the newest read's answer is kept.
  func reload() async {
    round += 1
    let mine = round
    reads += 1
    defer { reads -= 1 }
    let environment = await environment()
    async let status = GitStatus.read(project: path, environment: environment)
    async let repo = github(environment).originRepo(path)
    let answers = await (status, repo)
    guard mine == round else { return }
    (self.status, self.repo) = answers
  }

  /// All three directions end in `git pull origin` or `git push origin`, so without an origin a
  /// click only produced git's error. "Cannot tell" (not read yet, `readError`) is not "no".
  var noOrigin: Bool {
    guard let status, status.readError == nil else { return false }
    return !status.isRepo || status.remoteUrl == nil
  }

  // MARK: Sync

  func run(_ direction: Sync.Direction, commit: Bool, message: String) async {
    busy = direction
    result = nil
    notice = nil
    let environment = await environment()
    let answer = await Sync.run(project: path, direction: direction, options: Sync.Options(commit: commit, message: message),
                                environment: environment, token: AppDeploy.connections().gitToken)
    result = Outcome(success: answer.success, output: answer.output)
    busy = nil
    Announce.post(answer.success ? L10n.t("gitSync.success") : L10n.t("gitSync.failed"))
    // A sync is exactly what changes ahead, behind and the file list.
    await reload()
  }

  /// `quartz sync --pull` merges, so a conflict leaves a half-finished merge here. The abort is the
  /// one Updates uses: a plain `git merge --abort` with the content symlink parked. It answers with
  /// a sentence rather than a throw, and what is said is QuartzHub's sentences, never git's text
  /// (QuartzControl's twenty-seventh and twenty-ninth reviews).
  func abortMerge() async {
    aborting = true
    notice = nil
    let environment = await environment()
    let updater = CoreUpdate(environment: environment, snapshot: SnapshotStore.live(environment: environment).take)
    do {
      let answer = try await updater.abort(project: path)
      let output = answer.output.trimmingCharacters(in: .whitespacesAndNewlines)
      // Outside the banner: half of what the abort answers is said after the merge is gone.
      notice = output.isEmpty ? nil : Notice(text: output, isError: !answer.success, verbatim: true)
      let said = answer.sentences.isEmpty
        ? output.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        : answer.sentences.joined(separator: " ")
      if !said.isEmpty { Announce.post(said) }
    } catch {
      notice = Notice(text: String(describing: error), isError: true)
    }
    aborting = false
    await reload()
  }

  // MARK: A repository on GitHub

  /// A missing or rejected token, and a request that failed on the way, are all "no account": the
  /// card then says so instead of failing on the click.
  func loadViewer() async {
    viewer = try? await github(await environment()).viewer()
  }

  func createRepo(name: String, isPrivate: Bool) async {
    creating = true
    createResult = nil
    notice = nil
    do {
      let answer = try await github(await environment()).createRepo(path, name: name, isPrivate: isPrivate)
      if answer.success {
        // The card goes with the origin it just set, so its answer is said where the origin is.
        notice = Notice(text: answer.output, verbatim: true)
      } else {
        createResult = Outcome(success: false, output: answer.output)
      }
      Announce.post(answer.output.split(separator: "\n").first.map(String.init) ?? "")
    } catch {
      createResult = Outcome(success: false, output: String(describing: error))
    }
    creating = false
    await reload()
  }
}
