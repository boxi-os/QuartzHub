import AppKit
import QuartzHubCore
import SwiftUI

/// „Konfiguration umstellen“: Quartz's `plugin doctor --fix`, which moves the entries of the plugins
/// that are part of Quartz since 5.1 (crawl-links, remove-draft, content-index, note-properties'
/// delimiters and language) to `configuration.*`, comments kept. Offered, never run on its own
/// (the user's decision of 2026-11-11): Quartz builds the old entries as they are and only warns.
/// A snapshot first, as before every plugin change.
struct BuiltinMigration: View {
  let project: ProjectContext
  /// The entries that would move, by name; nothing is shown without them.
  let pending: [String]
  /// The page holds edits of the same file: they would be lost under Quartz's write.
  var blockedByEdits = false
  /// After a run that wrote: the page reads the file again.
  let done: () async -> Void

  @State private var running = false
  @State private var output: String?
  @State private var failed = false
  @Environment(\.unsavedGuard) private var unsaved

  var body: some View {
    if !pending.isEmpty || output != nil {
      VStack(alignment: .leading, spacing: 6) {
        if !pending.isEmpty {
          Text(L10n.t("builtins.pending", ["names": pending.joined(separator: ", ")]))
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          HStack {
            Button(running ? L10n.t("builtins.migrateRunning") : L10n.t("builtins.migrate")) {
              Task { await run() }
            }
            .disabled(running || blockedByEdits)
            .accessibilityIdentifier("builtins.migrate")
            if blockedByEdits { Text(L10n.t("builtins.saveFirst")).font(.caption).foregroundStyle(.secondary) }
          }
        }
        if let output {
          OutcomeTitle(title: failed ? L10n.t("builtins.migrateFailed") : L10n.t("builtins.migrateDone"), success: !failed)
          RunOutput(text: output, label: L10n.t("builtins.output"), identifier: "builtins.output")
        }
      }
    }
  }

  private func run() async {
    guard await Confirm.ask(L10n.t("builtins.migrateConfirm"),
                            detail: L10n.t("builtins.migrateConfirmDetail", ["names": pending.joined(separator: ", ")]),
                            confirm: L10n.t("builtins.migrateConfirmAction"), window: unsaved?.window) else { return }
    running = true
    defer { running = false }
    let environment = await AppServices.current()
    let result = await PluginCommands.shared.doctor(project: project.path, fix: true, environment: environment,
                                                    snapshot: SnapshotStore.live(environment: environment).take)
    // doctor ends with 1 for problems it found besides the move; whether it moved is the file.
    output = result.output
    await done()
    let left = (try? await ConfigFile.read(project: project.path, runtime: environment.runtime))
      .map { BuiltinProcessing.pendingMigrations($0.plugins) } ?? [0]
    failed = !left.isEmpty
    Announce.post(failed ? L10n.t("builtins.migrateFailed") : L10n.t("builtins.migrateDone"))
  }
}
