import QuartzHubCore
import SwiftUI

/// A repository's README as `ReadmeText` read it: native text, never HTML. Links open in the
/// browser; an image shows its alt text in brackets.
struct ReadmeView: View {
  let blocks: [ReadmeText.Block]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        view(block)
      }
    }
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private func view(_ block: ReadmeText.Block) -> some View {
    switch block {
    case .paragraph(let parts):
      Text(Self.attributed(parts)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    case .heading(let level, let parts):
      Text(Self.attributed(parts))
        .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
        .padding(.top, 4)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    case .code(let text):
      preformatted(text, font: .system(.caption, design: .monospaced))
    case .table(let text):
      preformatted(text, font: .system(.caption2, design: .monospaced))
    case .list(let ordered, let items):
      VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, parts in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: ordered ? "\(index + 1)." : "•").monospacedDigit()
            Text(Self.attributed(parts)).fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .foregroundStyle(.secondary)
      .padding(.leading, 4)
    }
  }

  private func preformatted(_ text: String, font: Font) -> some View {
    ScrollView(.horizontal) {
      Text(verbatim: text).font(font).padding(8).fixedSize()
    }
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
  }

  /// One run of inline parts. A link that is not an address on the web stays words.
  static func attributed(_ parts: [ReadmeText.Inline]) -> AttributedString {
    var out = AttributedString()
    for part in parts {
      switch part {
      case .text(let text):
        out += AttributedString(text)
      case .code(let text):
        var run = AttributedString(text)
        run.inlinePresentationIntent = .code
        out += run
      case .strong(let text):
        var run = AttributedString(text)
        run.inlinePresentationIntent = .stronglyEmphasized
        out += run
      case .image(let alt):
        var run = AttributedString("[\(alt)]")
        run.foregroundColor = .secondary
        out += run
      case .link(let href, let inner):
        var run = attributed(inner)
        // Not a file path: an address on github.com or wherever the README points.
        if let href, let url = URL(string: href) { run.link = url }
        out += run
      }
    }
    return out
  }
}
