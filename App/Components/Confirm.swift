import AppKit
import QuartzHubCore

/// A yes/no question as a sheet on the window it is about (docs/conventions.md: the safe answer
/// first, the confirming button named after the action). "Abbrechen" is the first button and so
/// the default: Return cancels.
@MainActor
enum Confirm {
  static func ask(_ question: String, detail: String? = nil, confirm: String, destructive: Bool = false,
                  window: NSWindow?) async -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = question
    if let detail { alert.informativeText = detail }
    alert.addButton(withTitle: L10n.t("common.cancel"))
    let proceed = alert.addButton(withTitle: confirm)
    proceed.hasDestructiveAction = destructive
    let response = if let window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
    return response == .alertSecondButtonReturn
  }
}
