import AppKit
import QuartzHubCore
import SwiftUI

/// „Konfiguration umstellen“: Quartz's `plugin doctor --fix`, which moves the entries of the plugins
/// that are part of Quartz since 5.1 (crawl-links, remove-draft, content-index, note-properties'
/// delimiters and language) to `configuration.*`, comments kept. Offered, never run on its own
/// (the user's decision of 2026-11-11): Quartz builds the old entries as they are and only warns.
/// A snapshot first, as before every plugin change. Quartz 5.2's fonts, off only by an old
/// quartz-fonts entry, go on with the move, the site's fonts kept (`FontDelivery.withFontsOnAsBefore`).
struct BuiltinMigration: View {
  let project: ProjectContext
  /// The entries that would move, by name; nothing is shown without them.
  let pending: [String]
  /// The page holds edits of the same file: they would be lost under Quartz's write.
  var blockedByEdits = false
  /// On the Konfiguration page the settings move "here"; elsewhere they move to the configuration.
  var onConfigPage = false
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
          Text(onConfigPage ? L10n.t("builtins.pending", ["names": pending.joined(separator: ", ")])
               : L10n.t("builtins.pendingElsewhere", ["names": pending.joined(separator: ", ")]))
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
    let environment = await AppServices.current()
    let path = project.path
    let features = await Task.detached { QuartzFeatures.read(project: path) }.value
    // Fonts off only by an old quartz-fonts entry go on with the move: doctor would carry the
    // entry's "off" over and the interface and heading fonts went dark (FontDelivery).
    let fontsOn = (try? await ConfigFile.read(project: path, runtime: environment.runtime))
      .map { FontDelivery.fontsOffOnlyByOldEntry($0, features) } ?? false
    var detail = L10n.t("builtins.migrateConfirmDetail", ["names": pending.joined(separator: ", ")])
    if fontsOn { detail += " " + L10n.t("builtins.migrateFontsOn") }
    guard await Confirm.ask(L10n.t("builtins.migrateConfirm"), detail: detail,
                            confirm: L10n.t("builtins.migrateConfirmAction"), window: unsaved?.window) else { return }
    running = true
    defer { running = false }
    let result = await PluginCommands.shared.doctor(project: path, fix: true, environment: environment,
                                                    snapshot: SnapshotStore.live(environment: environment).take)
    // doctor ends with 1 for problems it found besides the move; whether it moved is the file.
    output = result.output
    // Only once the entry is gone; doctor's snapshot holds the file from before both.
    if fontsOn, let moved = try? await ConfigFile.read(project: path, runtime: environment.runtime),
       FontDelivery.fontsBuiltin(moved, features)?.absorbed == nil {
      do {
        try await ConfigFile.write(FontDelivery.withFontsOnAsBefore(moved), project: path, runtime: environment.runtime)
        // doctor's own line says "moved enabled: false"; this one says what holds now.
        output = (output ?? "") + "\n" + L10n.t("builtins.migrateFontsOnDone")
      } catch {
        output = (output ?? "") + "\n" + L10n.t("builtins.migrateFontsOnFailed", ["error": error.localizedDescription])
      }
    }
    await done()
    let left = (try? await ConfigFile.read(project: path, runtime: environment.runtime))
      .map { BuiltinProcessing.pendingMigrations($0.plugins, features: features) } ?? [0]
    failed = !left.isEmpty
    Announce.post(failed ? L10n.t("builtins.migrateFailed") : L10n.t("builtins.migrateDone"))
  }
}
