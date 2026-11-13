import AppKit
import QuartzHubCore
import SwiftUI

/// What the Snapshots page reads and does (QuartzControl's `Backups.tsx`).
///
/// One model per project, as on Updates: a restore that brings back package.json runs `npm install`
/// and can take minutes, and the page opened again should show it still going or how it ended.
/// The list is read again on every opening.
@MainActor @Observable
final class SnapshotsModel {
  private static var models: [String: SnapshotsModel] = [:]

  static func shared(_ project: ProjectContext) -> SnapshotsModel {
    if let model = models[project.path] { return model }
    let model = SnapshotsModel(project: project)
    models[project.path] = model
    return model
  }

  /// One file's text diff, shown in a sheet.
  struct FileDiff: Identifiable, Equatable {
    var path: String
    var text: String
    var id: String { path }
  }

  let project: ProjectContext
  var snapshots: [SnapshotStore.Snapshot]?
  var settings: SnapshotStore.Settings?
  var folders: [ContentBackups.Entry] = []
  var currentHead: String?

  /// The comparison of the open snapshot with the project as it is now.
  private(set) var comparedId: String?
  var changes: [SnapshotStore.FileChange]?
  var picked: Set<String> = []
  var resetHead = false
  var fileDiff: FileDiff?
  private var compareRound = 0

  var creating = false
  var restoring = false
  var savingSettings = false
  var folderBusy = false
  /// The last answer of an action: a sentence of QuartzHub's or what git and npm said.
  var message: String?
  var error: String?

  private init(project: ProjectContext) {
    self.project = project
  }

  private var path: String { project.path }

  private func store() async -> SnapshotStore {
    SnapshotStore.live(environment: await AppServices.shared.environment.value)
  }

  private static func text(_ error: Error) -> String {
    (error as? SnapshotStore.Failure)?.message ?? (error as? ContentBackups.Failure)?.message ?? String(describing: error)
  }

  // MARK: Reading

  /// The page opened: the last action's answer belongs to the visit that caused it.
  func appear() async {
    message = nil
    error = nil
    await reload()
  }

  /// The old config backups become snapshots first, as in QuartzControl: this is the one place a
  /// user reaches them. Without a legacy folder it touches nothing.
  func reload() async {
    let store = await store()
    let environment = await AppServices.shared.environment.value
    let path = path
    do { _ = try await store.migrateConfigBackups(project: path) } catch { self.error = Self.text(error) }
    async let list = store.list(project: path)
    async let git = GitStatus.read(project: path, environment: environment)
    let folders = await Task.detached { ContentBackups.list(project: path) }.value
    let (snapshots, status) = await (list, git)
    self.snapshots = snapshots
    settings = store.settings(project: path)
    self.folders = folders
    currentHead = status.lastCommit?.sha
  }

  /// Opening a snapshot is what compares it; the list stays cheap, since a comparison stages the
  /// whole project. Only the newest request's answer is kept.
  func compare(_ id: String?) async {
    compareRound += 1
    let mine = compareRound
    comparedId = id
    changes = nil
    picked = []
    resetHead = false
    fileDiff = nil
    guard let id else { return }
    // The project's HEAD again: a commit since the page opened decides whether moving it back is
    // offered (measured: one commit after opening the page, and the switch was missing).
    let environment = await AppServices.shared.environment.value
    currentHead = await GitStatus.read(project: path, environment: environment).lastCommit?.sha
    do {
      let result = try await (await store()).diff(project: path, id: id)
      guard mine == compareRound else { return }
      changes = result
    } catch {
      guard mine == compareRound else { return }
      changes = []
      self.error = Self.text(error)
    }
  }

  func showDiff(_ file: String) async {
    guard let id = comparedId else { return }
    do {
      fileDiff = FileDiff(path: file, text: try await (await store()).fileDiff(project: path, id: id, path: file))
    } catch {
      self.error = Self.text(error)
    }
  }

  /// Moving the project's branch back is offered only where it changes something: the snapshot
  /// recorded a commit and the project has moved on from it.
  func headDiffers(_ snapshot: SnapshotStore.Snapshot) -> Bool {
    guard let head = snapshot.projectHead, let currentHead else { return false }
    return head != currentHead
  }

  // MARK: Snapshots

  func create(label: String) async -> Bool {
    creating = true
    defer { creating = false }
    error = nil
    do {
      let created = try await (await store()).create(project: path, kind: "manual", label: label)
      message = created != nil ? L10n.t("backups.created") : nil
      if let message { Announce.post(message) }
      await reload()
      return true
    } catch {
      self.error = Self.text(error)
      return false
    }
  }

  /// Answers whether the snapshot is to be closed: a restore changes what it is compared with.
  func restore(_ id: String, files: [String]?, window: NSWindow?) async -> Bool {
    let text = files.map { L10n.t("backups.confirmRestoreFiles", ["count": String($0.count)], count: $0.count) } ?? L10n.t("backups.confirmRestoreAll")
    let (question, detail) = Confirm.split(text)
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("backups.confirmRestoreAction"), destructive: true,
                            window: window) else { return false }
    restoring = true
    defer { restoring = false }
    error = nil
    message = nil
    do {
      let result = try await (await store()).restore(project: path, id: id, paths: files, resetProjectHead: resetHead)
      if result.success {
        message = L10n.t("backups.restored")
        // The vault sentence comes after git's text: it is the one thing a success has to add.
        let vault = L10n.t("main.snapshotVaultUntouched")
        if result.output.contains(vault) { message = (message ?? "") + "\n" + vault }
      } else {
        error = result.output
      }
      Announce.post(result.success ? L10n.t("backups.restored") : result.output.split(separator: "\n").first.map(String.init) ?? "")
    } catch {
      self.error = Self.text(error)
    }
    await reload()
    return true
  }

  func delete(_ snapshot: SnapshotStore.Snapshot, window: NSWindow?) async -> Bool {
    guard await Confirm.ask(L10n.t("backups.confirmDelete"), confirm: L10n.t("backups.confirmDeleteAction"), destructive: true,
                            window: window) else { return false }
    error = nil
    do {
      try await (await store()).delete(project: path, id: snapshot.id)
    } catch {
      self.error = Self.text(error)
    }
    await reload()
    return true
  }

  /// The target is chosen here, in a save panel, as QuartzControl chose it in the main process.
  /// The panel remembers its own last folder.
  func export(_ snapshot: SnapshotStore.Snapshot, window: NSWindow?) async {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(snapshot.id).zip"
    panel.allowedContentTypes = [.zip]
    let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
    guard response == .OK, let url = panel.url else { return }
    error = nil
    do {
      try await (await store()).export(project: path, id: snapshot.id, to: Posix.path(url))
      message = L10n.t("backups.exported")
      Announce.post(L10n.t("backups.exported"))
    } catch {
      self.error = Self.text(error)
    }
  }

  func saveSettings(includeContent: Bool) async {
    savingSettings = true
    defer { savingSettings = false }
    do {
      settings = try await (await store()).saveSettings(project: path, includeContent: includeContent)
    } catch {
      self.error = Self.text(error)
    }
  }

  // MARK: Set-aside content folders

  func restoreFolder(_ entry: ContentBackups.Entry, window: NSWindow?) async {
    guard await Confirm.ask(L10n.t("backups.confirmRestoreFolder"), confirm: L10n.t("backups.confirmRestoreFolderAction"),
                            destructive: true, window: window) else { return }
    // A restore like any other: quitting while the folder is being copied back asks (RunningWork),
    // as it does for a snapshot (review 2026-11-13, handbook, N6). No snapshot of its own: the
    // folder it replaces is set aside first, which the question says.
    let id = entry.id
    await folderAction { project in
      try await RunningWork.during(.restore, project: project) {
        try ContentBackups.restore(project: project, content: ContentFolder.path(project: project), id: id, now: Date())
      }
    }
  }

  /// The only copy there is, so the question names its size.
  func deleteFolder(_ entry: ContentBackups.Entry, window: NSWindow?) async {
    let (question, detail) = Confirm.split(L10n.t("backups.confirmDeleteFolder", ["size": Formats.bytes(entry.sizeBytes)]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("backups.confirmDeleteFolderAction"), destructive: true,
                            window: window) else { return }
    await folderAction { try ContentBackups.delete(project: $0, id: entry.id) }
  }

  /// A copy or a removal of a whole folder, off the main thread.
  private func folderAction(_ body: @escaping @Sendable (String) async throws -> Void) async {
    folderBusy = true
    defer { folderBusy = false }
    error = nil
    let path = path
    do {
      try await Task.detached { try await body(path) }.value
    } catch {
      self.error = Self.text(error)
    }
    await reload()
  }
}
