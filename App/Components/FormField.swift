import QuartzHubCore
import SwiftUI

/// A control with its hint underneath, QuartzControl's `Field` (`src/components/ui.tsx`) inside a
/// grouped `Form`: the label stays the control's own, the hint is secondary text below it.
struct FormField<Content: View>: View {
  let hint: String?
  @ViewBuilder var content: () -> Content

  init(hint: String? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.hint = hint
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      content()
      if let hint {
        Text(hint)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// A folder chosen with the open panel: the path (or the placeholder), and "Auswählen".
struct FolderField: View {
  let label: String
  let placeholder: String?
  @Binding var path: String
  let start: String?

  var body: some View {
    LabeledContent(label) {
      HStack {
        Text(path.isEmpty ? (placeholder ?? "") : path)
          .foregroundStyle(path.isEmpty ? .tertiary : .primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(path)
        Button(L10n.t("common.select")) {
          if let folder = ProjectsModel.pickFolder(start: path.isEmpty ? start : path) { path = folder }
        }
      }
    }
  }
}
