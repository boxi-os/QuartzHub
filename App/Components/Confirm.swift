import AppKit
import UniformTypeIdentifiers
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

extension Confirm {
  enum Choice { case cancel, alternative, confirm }

  /// A question with three answers (QuartzControl's askDialog): "Abbrechen" first and default,
  /// then the alternative, then the action, named after what it does.
  static func choose(_ question: String, detail: String? = nil, alternative: String, confirm: String, destructive: Bool = false,
                     window: NSWindow?) async -> Choice {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = question
    if let detail { alert.informativeText = detail }
    alert.addButton(withTitle: L10n.t("common.cancel"))
    alert.addButton(withTitle: alternative)
    let proceed = alert.addButton(withTitle: confirm)
    proceed.hasDestructiveAction = destructive
    let response = if let window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
    switch response {
    case .alertSecondButtonReturn: return .alternative
    case .alertThirdButtonReturn: return .confirm
    default: return .cancel
    }
  }

  /// A catalog text whose first paragraph is the question and the rest its detail.
  static func split(_ text: String) -> (question: String, detail: String?) {
    guard let gap = text.range(of: "\n\n") else { return (text, nil) }
    return (String(text[..<gap.lowerBound]), String(text[gap.upperBound...]))
  }
}

/// One file from the open panel, as a path with the disk's bytes (Posix.path), or nil.
@MainActor
enum FilePick {
  static func one(extensions: [String], message: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
    panel.message = message
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return Posix.path(url)
  }
}
