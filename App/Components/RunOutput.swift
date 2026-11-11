import SwiftUI

/// QuartzHub's sentence about a run, above the files and the text (Updates, Git-Sync).
struct OutcomeTitle: View {
  let title: String?
  let success: Bool
  /// Done, with something left over (files a target would not delete).
  var partial = false

  var body: some View {
    if let title {
      Label(title, systemImage: !success ? "xmark.octagon.fill" : partial ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .foregroundStyle(!success ? .red : partial ? .orange : .green)
    }
  }
}

/// git's and npm's text, selectable. Trailing blank lines are left out: the catalog's sentences
/// end in two line breaks so that git's text stands apart from them.
struct RunOutput: View {
  let text: String
  let label: String
  let identifier: String

  private var trimmed: String {
    String(text.reversed().drop { $0.isWhitespace }.reversed())
  }

  var body: some View {
    if !trimmed.isEmpty {
      ScrollView {
        Text(verbatim: trimmed)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
      }
      .frame(maxHeight: 224)
      .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      .accessibilityLabel(label)
      .accessibilityIdentifier(identifier)
    }
  }
}
