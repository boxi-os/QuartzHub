import QuartzHubCore
import SwiftUI

extension View {
  /// The inspector on the right with its toolbar button and ⌃⌘I (`InspectorCommand`), the same in
  /// the Projects window and on every page (`PageScaffold`).
  func inspectorColumn<Inspector: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Inspector) -> some View {
    inspector(isPresented: isPresented) {
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("shell.inspector.name"))
        .accessibilityIdentifier("inspector")
        .inspectorColumnWidth(min: 240, ideal: 300, max: 440)
    }
    .focusedSceneValue(\.inspectorPresented, isPresented)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isPresented.wrappedValue.toggle()
        } label: {
          Label(L10n.t("shell.inspector.toggle"), systemImage: "sidebar.trailing")
        }
        .help(L10n.t("shell.inspector.toggle"))
        .accessibilityIdentifier("inspector.toggle")
      }
    }
  }
}
