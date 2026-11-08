import QuartzHubCore
import SwiftUI

/// View ▸ Show/Hide Inspector, ⌃⌘I.
///
/// Our own instead of SwiftUI's `InspectorCommands`: under macOS 27 that one read „Informationen
/// Hide“ in a German app (measured 2026-11-06 in the packaged app, read through System Events), half
/// German, half English, and „Informationen“ is not the word this app uses
/// (docs/conventions.md, „Ein Wort, ein Name“). Same shortcut as SwiftUI's.
struct InspectorCommand: Commands {
  @FocusedBinding(\.inspectorPresented) private var presented

  var body: some Commands {
    let _ = AppAppearance.shared.revision
    CommandGroup(after: .sidebar) {
      Button(presented == true ? L10n.t("shell.inspector.hide") : L10n.t("shell.inspector.show")) {
        presented?.toggle()
      }
      .keyboardShortcut("i", modifiers: [.control, .command])
      .disabled(presented == nil)
    }
  }
}

extension FocusedValues {
  /// The inspector of the frontmost window's page, published by `PageScaffold`.
  @Entry var inspectorPresented: Binding<Bool>?
}
