import QuartzHubCore
import SwiftUI

/// Snapshots: QuartzControl's `Backups.tsx`. A list page (decisions/ui-ueberarbeitung.md,
/// Seitentypen): in the middle the snapshots as a table across the whole width, its columns coming
/// with the width, below it the set-aside content folders. A new snapshot is made from the toolbar.
/// The open snapshot is compared and restored in the inspector, which without one sums up the
/// store and holds its setting. A file's text diff opens in a sheet: the inspector is too narrow
/// for git's lines.
struct SnapshotsPage: View {
  let project: ProjectContext

  @State private var model: SnapshotsModel
  @Environment(\.unsavedGuard) private var unsaved
  /// The open snapshot, by id. The Updates page sets it for its "Snapshot öffnen" link, under the
  /// same key and with the same type: two types for one key blank the whole window.
  @SceneStorage("backups.open") private var openId: String?
  @SceneStorage("backups.newLabel") private var newLabel = ""
  @State private var creatingOpen = false
  /// Room for the commit column (decisions/ui-ueberarbeitung.md, Snapshots).
  @State private var wide = false

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: SnapshotsModel.shared(project))
  }

  private var openSnapshot: SnapshotStore.Snapshot? {
    guard let openId, !openId.isEmpty else { return nil }
    return model.snapshots?.first { $0.id == openId }
  }

  var body: some View {
    PageScaffold(page: .backups) {
      VStack(alignment: .leading, spacing: 0) {
        messages
        table
        if !model.folders.isEmpty {
          Divider()
          folders
        }
      }
      .onGeometryChange(for: Bool.self) { $0.size.width >= 720 } action: { wide = $0 }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button { creatingOpen = true } label: {
            Label(L10n.t("backups.create"), systemImage: "plus")
          }
          .help(L10n.t("backups.create"))
          .accessibilityIdentifier("backups.new")
          .popover(isPresented: $creatingOpen, arrowEdge: .bottom) { createForm }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.backups")
      .task { await model.appear() }
      // Compared once the list is there: the link from Updates opens a snapshot the list may not
      // have read yet.
      .task(id: openSnapshot?.id) { await model.compare(openSnapshot?.id) }
      .sheet(item: $model.fileDiff) { diff in FileDiffSheet(diff: diff) }
    } inspector: {
      if let snapshot = openSnapshot {
        SnapshotInspector(model: model, snapshot: snapshot, window: unsaved?.window) { openId = nil }
      } else {
        InspectorPageContext(page: .backups) { summary }
      }
    }
  }

  // MARK: The middle

  /// What the last action said, above the table. Outside the list's scrolling, so no
  /// `fixedSize(vertical:)` here: a wrapped text fixed to its height left the whole window blank,
  /// sidebar included (measured; the window's minimum height is asked of the text at its narrowest).
  @ViewBuilder private var messages: some View {
    if model.message != nil || model.error != nil {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if let message = model.message {
          Callout(.info) { Text(message).textSelection(.enabled) }
        }
        if let error = model.error {
          Callout(.error) { Text(error).textSelection(.enabled).lineLimit(12) }
        }
      }
      .padding(.horizontal, Spacing.page)
      .padding(.vertical, Spacing.s)
      .transition(.opacity)
    }
  }

  /// "Snapshot anlegen" from the toolbar: the name, what is kept, the button.
  private var createForm: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      Text(L10n.t("backups.newHeading")).font(.headline)
      TextField(L10n.t("backups.newHeading"), text: $newLabel, prompt: Text(L10n.t("backups.labelPlaceholder")))
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .onSubmit(create)
        .accessibilityIdentifier("backups.label")
      Text(L10n.t("backups.newHint")).font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button(model.creating ? L10n.t("backups.creating") : L10n.t("backups.create"), action: create)
          .keyboardShortcut(.defaultAction)
          .disabled(model.creating)
          .accessibilityIdentifier("backups.create")
      }
    }
    .padding(Spacing.m)
    .frame(width: 360)
  }

  private func create() {
    guard !model.creating else { return }
    Task {
      if await model.create(label: newLabel) {
        newLabel = ""
        creatingOpen = false
      }
    }
  }

  /// With a linked vault the switch is off and stays readable: that is a fact, not a default, and
  /// the sentence under it says why.
  private func contentSetting(_ settings: SnapshotStore.Settings) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle(L10n.t("backups.includeContent"), isOn: Binding(
        get: { settings.includeContent },
        set: { value in Task { await model.saveSettings(includeContent: value) } }))
        .disabled(model.savingSettings || !settings.contentExists || settings.contentIsSymlink)
        .accessibilityIdentifier("backups.includeContent")
      Note(!settings.contentExists ? L10n.t("backups.contentMissing")
        : settings.contentIsSymlink ? L10n.t("backups.contentSymlinkHint") : L10n.t("backups.contentFolderHint"))
    }
  }

  /// Full width, edge to edge. The commit comes in as a column once there is room for it.
  private var table: some View {
    Table(model.snapshots ?? [], selection: $openId) {
      TableColumn(L10n.t("backups.column.when")) { snapshot in
        Text(Self.when(snapshot.createdAt)).monospacedDigit()
      }
      .width(min: 140, ideal: 170, max: 220)
      TableColumn(L10n.t("backups.column.label")) { snapshot in
        if snapshot.label.isEmpty {
          Text(verbatim: "–").foregroundStyle(.tertiary)
        } else {
          Text(snapshot.label).lineLimit(1)
        }
      }
      TableColumn(L10n.t("backups.kind")) { snapshot in
        Self.kindBadge(snapshot.kind).foregroundStyle(.secondary)
      }
      .width(min: 120, ideal: 190)
      if wide {
        // The project's commit when it was taken, the one the reset switch goes back to; it showed
        // the store's own commit, which says nothing outside it (review 2026-11-13, nebenbei).
        TableColumn(L10n.t("backups.column.commit")) { snapshot in
          Text(verbatim: snapshot.projectHead.map { String($0.prefix(7)) } ?? "–").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
        }
        .width(min: 70, ideal: 80, max: 100)
      }
    }
    .contextMenu(forSelectionType: String.self) { ids in
      if let id = ids.first, let snapshot = model.snapshots?.first(where: { $0.id == id }) {
        Button(L10n.t("backups.export")) { Task { await model.export(snapshot, window: unsaved?.window) } }
        Divider()
        Button(L10n.t("common.deleteNamed", ["name": Self.title(snapshot)]), role: .destructive) { delete(snapshot) }
      }
    }
    .onDeleteCommand {
      if let snapshot = openSnapshot { delete(snapshot) }
    }
    .overlay {
      if model.snapshots == nil {
        ProgressView(L10n.t("common.loading"))
      } else if model.snapshots?.isEmpty == true {
        ContentUnavailableView {
          Label(L10n.t("backups.listTitle", ["count": "0"]), systemImage: "archivebox")
        } description: {
          Text(L10n.t("backups.none"))
        } actions: {
          Button(L10n.t("backups.create")) { creatingOpen = true }
        }
      }
    }
    // A Table keeps the columns it was first built with; a column that comes with the width
    // needs a new one (measured: without this the commit never appeared at 1680 pt).
    .id(wide)
    .accessibilityIdentifier("backups.list")
  }

  private func delete(_ snapshot: SnapshotStore.Snapshot) {
    Task {
      if await model.delete(snapshot, window: unsaved?.window), openId == snapshot.id { openId = nil }
    }
  }

  /// Not snapshots: the content folders a switch of the content source moved aside. The only way
  /// back to a replaced folder, and the only copy of it.
  private var folders: some View {
    List {
    Section {
      Note(L10n.t("backups.movedFoldersHint")).fixedSize(horizontal: false, vertical: true)
      ForEach(model.folders, id: \.id) { entry in
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(Self.when(entry.createdAt))
            // A recorded link and a real copy are worlds apart on disk, and the row deletes.
            Text(entry.kind == .link ? L10n.t("backups.folderLink", ["target": entry.target ?? "?"])
              : L10n.t("backups.folderSize", ["count": String(entry.fileCount), "size": Formats.bytes(entry.sizeBytes)], count: entry.fileCount))
              .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
          }
          Spacer(minLength: 8)
          Button(L10n.t("backups.restore")) { Task { await model.restoreFolder(entry, window: unsaved?.window) } }
          Button(role: .destructive) {
            Task { await model.deleteFolder(entry, window: unsaved?.window) }
          } label: {
            Label(L10n.t("common.deleteNamed", ["name": Self.when(entry.createdAt)]), systemImage: "trash")
          }
          .labelStyle(.iconOnly)
          .help(L10n.t("common.deleteNamed", ["name": Self.when(entry.createdAt)]))
        }
        .disabled(model.folderBusy)
        .accessibilityElement(children: .contain)
      }
    } header: {
      Label(L10n.t("backups.movedFoldersHeading"), systemImage: "clock.arrow.circlepath")
    }
    .selectionDisabled()
    }
    .frame(maxHeight: 220)
  }

  // MARK: The inspector without a snapshot

  @ViewBuilder private var summary: some View {
    Section {
      Text(L10n.t("projectLayout.descriptions.backups")).foregroundStyle(.secondary)
      // Both this page and Git-Sync keep old versions of the project; they are not alternatives.
      Text(L10n.t("backups.vsGitSync")).foregroundStyle(.secondary)
    }
    if let settings = model.settings {
      Section { contentSetting(settings) }
    }
    Section(L10n.t("backups.panelEmptyTitle")) {
      Text(L10n.t("backups.panelEmptyText")).foregroundStyle(.secondary)
      if let snapshots = model.snapshots, let newest = snapshots.first, let oldest = snapshots.last {
        LabeledContent(L10n.t("backups.summaryCount"),
                       value: L10n.t("backups.summaryCountValue", ["count": String(snapshots.count),
                                                                   "manual": String(snapshots.filter { $0.kind == "manual" }.count)]))
        LabeledContent(L10n.t("backups.summaryNewest"), value: Self.when(newest.createdAt))
        LabeledContent(L10n.t("backups.summaryOldest"), value: Self.when(oldest.createdAt))
        if let settings = model.settings {
          LabeledContent(L10n.t("backups.summaryContent"), value: !settings.contentExists ? L10n.t("backups.summaryContentMissing")
            : settings.contentIsSymlink ? L10n.t("backups.summaryContentVault")
            : settings.includeContent ? L10n.t("backups.summaryContentIncluded") : L10n.t("backups.summaryContentExcluded"))
        }
      }
    }
  }

  // MARK: Words

  /// `toLocaleString`: date and time with seconds, in the catalog's language.
  static func when(_ iso: String) -> String {
    guard let date = Formats.date(iso: iso) else { return iso }
    return date.formatted(Date.FormatStyle(date: .numeric, time: .standard, locale: Locale(identifier: L10n.language)))
  }

  static func title(_ snapshot: SnapshotStore.Snapshot) -> String {
    snapshot.label.isEmpty ? when(snapshot.createdAt) : snapshot.label
  }

  /// QuartzControl showed an unknown kind as its key; here it is the kind itself.
  static func kind(_ kind: String) -> String {
    switch kind {
    case "manual": L10n.t("backups.kinds.manual")
    case "configChange": L10n.t("backups.kinds.configChange")
    case "contentChange": L10n.t("backups.kinds.contentChange")
    case "coreUpdate": L10n.t("backups.kinds.coreUpdate")
    case "imported": L10n.t("backups.kinds.imported")
    case "pluginChange": L10n.t("backups.kinds.pluginChange")
    case "restore": L10n.t("backups.kinds.restore")
    case "styleChange": L10n.t("backups.kinds.styleChange")
    case "styleMigration": L10n.t("backups.kinds.styleMigration")
    default: kind
    }
  }

  static func kindBadge(_ kind: String) -> some View {
    StateBadge(text: Self.kind(kind), color: kind == "manual" ? .green : .gray)
  }
}

/// A table's rows need an identity: the snapshot's own id in the store.
extension SnapshotStore.Snapshot: @retroactive Identifiable {}

/// The open snapshot against the project as it is now: what differs, and the way back.
private struct SnapshotInspector: View {
  @Bindable var model: SnapshotsModel
  let snapshot: SnapshotStore.Snapshot
  let window: NSWindow?
  let close: () -> Void

  var body: some View {
    Form {
      Section {
        LabeledContent(L10n.t("backups.panelLabel")) {
          Text(SnapshotsPage.title(snapshot)).textSelection(.enabled)
        }
        .accessibilityIdentifier("backups.inspector")
        if !snapshot.label.isEmpty { LabeledContent(L10n.t("backups.createdAt"), value: SnapshotsPage.when(snapshot.createdAt)) }
        LabeledContent(L10n.t("backups.kind")) { SnapshotsPage.kindBadge(snapshot.kind) }
      }
      comparison
      Section {
        Button(L10n.t("backups.export")) { Task { await model.export(snapshot, window: window) } }
        Button(L10n.t("backups.confirmDeleteAction"), role: .destructive) {
          Task { if await model.delete(snapshot, window: window) { close() } }
        }
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder private var comparison: some View {
    Section {
      if let changes = model.changes, model.comparedId == snapshot.id {
        Text(changes.isEmpty ? L10n.t("backups.identical")
             : L10n.t("backups.changeCount", ["count": String(changes.count)], count: changes.count))
          .accessibilityIdentifier("backups.compared")
        // Where the misunderstanding arose: a changed note in a vault never shows here, and without
        // this line that reads as "nothing changed".
        if model.settings?.contentIsSymlink == true {
          Note(L10n.t("backups.vaultNotCompared"))
        } else if let settings = model.settings, settings.contentExists, !settings.includeContent {
          // Nor restored: the snapshot taken before a restore would not hold the notes.
          Note(L10n.t("backups.contentNotCompared"))
        }
        ForEach(changes, id: \.path) { change in fileRow(change) }
        // Also with no file to restore: the project's commit may still differ, and the switch that
        // sets it back was out of reach (review 2026-11-13, nebenbei).
        if !changes.isEmpty || model.headDiffers(snapshot) { restore(filesDiffer: !changes.isEmpty) }
      } else {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Note(L10n.t("backups.comparing"))
        }
      }
    } header: {
      Text(L10n.t("backups.compareHeading"))
    }
  }

  private func fileRow(_ change: SnapshotStore.FileChange) -> some View {
    HStack(spacing: 6) {
      Toggle(isOn: Binding(
        get: { model.picked.contains(change.path) },
        set: { on in if on { model.picked.insert(change.path) } else { model.picked.remove(change.path) } })) {
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: change.path).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
          Text(Self.status(change.status)).font(.caption).foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.checkbox)
      .help(change.path)
      Spacer(minLength: 4)
      if change.status == .modified {
        Button {
          Task { await model.showDiff(change.path) }
        } label: {
          Label(L10n.t("backups.showDiff", ["path": change.path]), systemImage: "doc.text.magnifyingglass")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(L10n.t("backups.showDiff", ["path": change.path]))
      }
    }
  }

  @ViewBuilder private func restore(filesDiffer: Bool) -> some View {
    // Moving the project's own branch back is its own decision, off by default: it rewrites git
    // history rather than files.
    if model.headDiffers(snapshot), let head = snapshot.projectHead {
      VStack(alignment: .leading, spacing: 2) {
        Toggle(L10n.t("backups.resetProjectHead", ["commit": String(head.prefix(7))]), isOn: $model.resetHead)
        Note(L10n.t("backups.resetProjectHeadHint")).fixedSize(horizontal: false, vertical: true)
      }
    }
    // One under the other: side by side they were cut off at the inspector's width.
    VStack(alignment: .leading, spacing: 6) {
      Button(L10n.t("backups.restoreAll")) { run(nil) }
        .disabled(model.restoring || (!filesDiffer && !model.resetHead))
        .accessibilityIdentifier("backups.restoreAll")
      Button(L10n.t("backups.restoreSelected", ["count": String(model.picked.count)])) { run(model.picked.sorted()) }
        .disabled(model.restoring || model.picked.isEmpty)
        .accessibilityIdentifier("backups.restoreSelected")
    }
    if model.restoring {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Note(L10n.t("backups.restoring"))
      }
    }
  }

  private func run(_ files: [String]?) {
    Task { if await model.restore(snapshot.id, files: files, window: window) { close() } }
  }

  static func status(_ status: SnapshotStore.FileChange.Status) -> String {
    switch status {
    case .addedSince: L10n.t("backups.status.addedSince")
    case .removedSince: L10n.t("backups.status.removedSince")
    case .modified: L10n.t("backups.status.modified")
    }
  }
}

/// git's diff of one file against the snapshot, selectable; an empty one is a binary file.
private struct FileDiffSheet: View {
  let diff: SnapshotsModel.FileDiff
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(verbatim: diff.path).font(.system(.headline, design: .monospaced)).textSelection(.enabled)
      if diff.text.isEmpty {
        Note(L10n.t("backups.noDiff"))
        Spacer()
      } else {
        ScrollView([.horizontal, .vertical]) {
          Text(verbatim: diff.text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .accessibilityLabel(L10n.t("backups.diffLabel"))
        .accessibilityIdentifier("backups.diff")
      }
      HStack {
        Spacer()
        Button(L10n.t("common.close")) { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(minWidth: 620, idealWidth: 760, minHeight: 380, idealHeight: 520)
  }
}
