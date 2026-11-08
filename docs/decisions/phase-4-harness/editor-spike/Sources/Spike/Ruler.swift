import AppKit

/// Line numbers for a TextKit 2 NSTextView: one label per paragraph, at its first layout fragment.
final class LineNumberRuler: NSRulerView {
  weak var textView: NSTextView?
  init(textView: NSTextView) {
    self.textView = textView
    super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
    clientView = textView
    ruleThickness = 44
    NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in self?.needsDisplay = true }
  }
  required init(coder: NSCoder) { fatalError() }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let tv = textView, let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager else { return }
    let visible = tv.visibleRect
    let string = tv.string as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
    var line = -1
    tlm.enumerateTextLayoutFragments(from: tlm.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY))?.rangeInElement.location, options: [.ensuresLayout]) { fragment in
      let offset = tcm.offset(from: tcm.documentRange.location, to: fragment.rangeInElement.location)
      if line < 0 {  // count newlines once, before the first visible paragraph
        line = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: offset), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
      } else { line += 1 }
      let y = fragment.layoutFragmentFrame.minY + tv.textContainerInset.height - visible.minY
      let label = "\(line)" as NSString
      let size = label.size(withAttributes: attrs)
      label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y + 2), withAttributes: attrs)
      return fragment.layoutFragmentFrame.minY < visible.maxY
    }
  }
}
