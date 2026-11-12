import AppKit
import QuartzHubCore
import SwiftUI

/// A process's output (QuartzControl's `LogConsole`): named, because Vorschau & Build has two; empty
/// it is one line, not a 288-point box of nothing; "Ausgabe leeren" when there is something to clear.
///
/// A read-only NSTextView rather than a list of `Text`s: output is selected and copied across lines,
/// and a busy server appends what is new instead of the view drawing up to 999 lines again. Red is
/// the process's own stderr, orange a sentence of QuartzHub's about a run that went on (`warn`).
struct LogConsole: View {
  let lines: ProjectLogs.Lines
  let label: String
  let identifier: String
  /// In a panel of its own (Vorschau & Build's output): as high as the panel, not 288 pt.
  var fills = false
  let clear: () -> Void

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      if lines.lines.isEmpty {
        Text(L10n.t("logConsole.noOutput"))
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          // Filling, the empty console shows how high the pane is (Vorschau & Build).
          .frame(maxHeight: fills ? .infinity : nil, alignment: .topLeading)
          .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
          .accessibilityLabel(label)
          .accessibilityValue(L10n.t("logConsole.noOutput"))
          .accessibilityIdentifier(identifier)
      } else {
        Button(L10n.t("logConsole.clear"), action: clear)
          .buttonStyle(.link)
          .font(.callout)
        LogTextView(lines: lines, label: label, identifier: identifier)
          .frame(height: fills ? nil : 288)
          .frame(maxHeight: fills ? .infinity : nil)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      }
    }
  }
}

private struct LogTextView: NSViewRepresentable {
  let lines: ProjectLogs.Lines
  let label: String
  let identifier: String

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.hasHorizontalScroller = false
    scroll.drawsBackground = true
    let text = scroll.documentView as! NSTextView
    text.isEditable = false
    text.isSelectable = true
    text.isRichText = false
    text.drawsBackground = true
    text.backgroundColor = .textBackgroundColor
    text.textContainerInset = NSSize(width: 6, height: 6)
    text.setAccessibilityLabel(label)
    text.setAccessibilityIdentifier(identifier)
    context.coordinator.watch(scroll)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
    text.setAccessibilityLabel(label)
    let shown = context.coordinator
    let new = lines.total - shown.total
    storage.beginEditing()
    // Cleared, or more new lines than the cap keeps: drawn again from what is there.
    if lines.generation != shown.generation || new < 0 || new > lines.lines.count {
      storage.setAttributedString(NSAttributedString())
      shown.lengths = []
      append(lines.lines, to: storage, shown)
    } else if new > 0 {
      append(Array(lines.lines.suffix(new)), to: storage, shown)
    }
    // The cap drops lines at the front; the view drops the same ones.
    let excess = shown.lengths.count - lines.lines.count
    if excess > 0 {
      let length = shown.lengths.prefix(excess).reduce(0, +)
      storage.deleteCharacters(in: NSRange(location: 0, length: length))
      shown.lengths.removeFirst(excess)
    }
    storage.endEditing()
    shown.total = lines.total
    shown.generation = lines.generation
    // Through the range, not the frame: TextKit 2 lays new lines out lazily, so the document's
    // height is still the old one here (measured: the console stayed at the first screen).
    if shown.following { text.scrollRangeToVisible(NSRange(location: storage.length, length: 0)) }
  }

  private func append(_ lines: [LogLine], to storage: NSTextStorage, _ shown: Coordinator) {
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    for line in lines {
      // A chunk as it arrived: its own trailing line ends go, one is added.
      var body = line.text
      while body.hasSuffix("\n") || body.hasSuffix("\r") { body.removeLast() }
      let color: NSColor = switch line.stream {
      case .stdout: .textColor
      case .stderr: .systemRed
      case .warn: .systemOrange
      }
      let piece = NSAttributedString(string: body + "\n", attributes: [.font: font, .foregroundColor: color])
      storage.append(piece)
      shown.lengths.append(piece.length)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  /// Following the end only while the reader is there: someone who scrolled up to read is not
  /// pulled down by every line a running server prints. Decided when the reader scrolls; growing
  /// text moves no bounds and so changes nothing.
  @MainActor
  final class Coordinator: NSObject {
    var following = true

    func watch(_ scroll: NSScrollView) {
      scroll.contentView.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification,
                                             object: scroll.contentView)
    }

    @objc private func scrolled(_ note: Notification) {
      guard let clip = note.object as? NSClipView, let document = clip.documentView else { return }
      following = clip.bounds.maxY >= document.frame.height - 20
    }

    var total = 0
    var generation = 0
    /// UTF-16 length of each shown line, to drop the first ones.
    var lengths: [Int] = []
  }
}
