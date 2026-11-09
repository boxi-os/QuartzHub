import AppKit
import QuartzHubCore
import SwiftUI

/// Text to put in at the cursor, handed to a CodeEditor from outside (a picture, a placeholder).
/// A new value each time, so the same text twice is two insertions.
struct CodeInsertion: Equatable {
  let id = UUID()
  let text: String
}

/// A line to put the cursor on and scroll to (a diagnostic's location). A new value each time.
struct CodeJump: Equatable {
  let id = UUID()
  let line: Int
}

/// The code editor: NSTextView with TextKit 2, no package (decided in 4b, measured in
/// `docs/decisions/phase-4-oberflaeche.md`). Line numbers, colours from `CodeColors` line by line,
/// the system's find bar, light and dark through dynamic system colours.
///
/// - an insertion goes to the cursor only once the user has placed one, otherwise to the end on
///   a line of its own (QuartzControl: position 0 is the editor's default, not a choice)
/// - a new `text` from outside replaces the document in one step and recolours it; typing writes
///   `text` back on every keystroke
struct CodeEditor: NSViewRepresentable {
  @Binding var text: String
  var language: CodeColors.Language?
  var wraps = true
  var lineNumbers = true
  /// Passed as a value, not a binding: a view whose body only hands a binding on is not drawn
  /// again when it changes, and the insertion never arrived (measured in the snippet editor).
  var insertion: CodeInsertion?
  /// The same way in for a jump to a line; the line is clamped, the diagnostic can be older than
  /// the text.
  var jump: CodeJump?
  /// The accessible name of the text area.
  let name: String

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.borderType = .noBorder
    scroll.clipsToBounds = true
    scroll.drawsBackground = true
    let view = scroll.documentView as! NSTextView  // swiftlint:disable:this force_cast
    view.isRichText = false
    view.importsGraphics = false
    view.allowsUndo = true
    view.usesFindBar = true
    view.isIncrementalSearchingEnabled = true
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.isAutomaticSpellingCorrectionEnabled = false
    view.isContinuousSpellCheckingEnabled = false
    view.smartInsertDeleteEnabled = false
    view.font = Coordinator.font
    view.textColor = .textColor
    view.backgroundColor = .textBackgroundColor
    view.textContainerInset = NSSize(width: 4, height: 6)
    view.setAccessibilityLabel(name)
    if !wraps {
      view.isHorizontallyResizable = true
      view.textContainer?.widthTracksTextView = false
      view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      scroll.hasHorizontalScroller = true
    }
    view.delegate = context.coordinator
    view.textStorage?.delegate = context.coordinator
    context.coordinator.view = view
    // An insertion from before this view existed has been made, or was meant for another one.
    context.coordinator.lastInsertion = insertion
    context.coordinator.replace(with: text)
    if let jump { DispatchQueue.main.async { context.coordinator.go(to: jump.line) } }
    context.coordinator.lastJump = jump
    if lineNumbers {
      scroll.verticalRulerView = LineNumberRuler(textView: view)
      scroll.hasVerticalRuler = true
      scroll.rulersVisible = true
    }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    if let view = coordinator.view, view.string != text { coordinator.replace(with: text) }
    if let insertion, insertion != coordinator.lastInsertion {
      coordinator.lastInsertion = insertion
      // After this update: the text written back from inside it is dropped by SwiftUI, and the
      // next update put the old text back (measured: "{{title}}" never reached the file).
      DispatchQueue.main.async { coordinator.insert(insertion.text) }
    }
    if let jump, jump != coordinator.lastJump {
      coordinator.lastJump = jump
      DispatchQueue.main.async { coordinator.go(to: jump.line) }
    }
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    var parent: CodeEditor
    weak var view: NSTextView?
    var lastInsertion: CodeInsertion?
    var lastJump: CodeJump?
    /// The user has set a cursor (typed, clicked, moved it); an outside change resets it.
    private var cursorPlaced = false
    /// A change made here, not by the user: neither a placed cursor nor a write back.
    private var applying = false

    init(_ parent: CodeEditor) { self.parent = parent }

    func replace(with text: String) {
      guard let view else { return }
      applying = true
      // Coloured by didProcessEditing, as every other change.
      view.string = text
      applying = false
      cursorPlaced = false
    }

    func insert(_ text: String) {
      guard let view else { return }
      let string = view.string as NSString
      var piece = text
      var range = view.selectedRange()
      if !cursorPlaced {
        let lead = string.length > 0 && !view.string.hasSuffix("\n") ? "\n" : ""
        piece = lead + text
        range = NSRange(location: string.length, length: 0)
      }
      // Through the text view, so the insertion is one step of undo and reaches the delegate.
      if view.shouldChangeText(in: range, replacementString: piece) {
        view.replaceCharacters(in: range, with: piece)
        view.didChangeText()
      }
      view.setSelectedRange(NSRange(location: range.location + (piece as NSString).length, length: 0))
      view.scrollRangeToVisible(view.selectedRange())
      cursorPlaced = true
      view.window?.makeFirstResponder(view)
    }

    /// The cursor at the start of a line (1-based), scrolled into view; a placed cursor, as a
    /// click would make one.
    func go(to line: Int) {
      guard let view else { return }
      let string = view.string as NSString
      var location = 0
      var current = 1
      while current < max(1, line) {
        let next = string.range(of: "\n", options: .literal, range: NSRange(location: location, length: string.length - location))
        guard next.location != NSNotFound else { break }
        location = next.location + 1
        current += 1
      }
      view.setSelectedRange(NSRange(location: location, length: 0))
      view.scrollRangeToVisible(view.selectedRange())
      cursorPlaced = true
      view.window?.makeFirstResponder(view)
    }

    func textDidChange(_ notification: Notification) {
      guard !applying, let view else { return }
      parent.text = view.string
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      if !applying { cursorPlaced = true }
    }

    nonisolated func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange,
                                 changeInLength delta: Int) {
      guard editedMask.contains(.editedCharacters) else { return }
      // The text view's storage, edited on the main thread: AppKit calls this from there.
      nonisolated(unsafe) let storage = storage
      MainActor.assumeIsolated { self.color(range, in: storage) }
    }

    /// Recolours the lines `range` touches.
    func color(_ range: NSRange, in given: NSTextStorage? = nil) {
      guard let storage = given ?? view?.textStorage else { return }
      let string = storage.string
      let lines = (string as NSString).paragraphRange(for: NSRange(location: min(range.location, storage.length),
                                                                     length: max(0, min(range.length, storage.length - range.location))))
      // Attributes only, outside the edit: changing them inside didProcessEditing is allowed and
      // does not mark the characters edited again.
      storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: lines)
      storage.addAttribute(.font, value: Self.font, range: lines)
      guard let language = parent.language else { return }
      for span in CodeColors.spans(string, in: lines, language: language) {
        storage.addAttribute(.foregroundColor, value: Self.color(span.role), range: span.range)
      }
    }

    static func color(_ role: CodeColors.Role) -> NSColor {
      switch role {
      case .tag: .systemPink
      case .attribute: .systemOrange
      case .string: .systemRed
      case .entity, .marker: .systemTeal
      case .comment: .secondaryLabelColor
      case .heading, .strong: .systemBlue
      case .emphasis: .systemIndigo
      case .code: .systemBrown
      case .link: .linkColor
      case .placeholder: .systemPurple
      }
    }
  }
}

/// Line numbers for a TextKit 2 NSTextView: one per paragraph, at its first layout fragment, so a
/// wrapped line keeps one number (from the 4b harness).
final class LineNumberRuler: NSRulerView {
  weak var textView: NSTextView?

  init(textView: NSTextView) {
    self.textView = textView
    super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
    clientView = textView
    ruleThickness = 36
    // Views do not clip since macOS 14: the ruler's edge ran from the top of the window to the
    // bottom, through everything above the editor (seen on the CSS tab).
    clipsToBounds = true
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSText.didChangeNotification, object: textView)
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSView.boundsDidChangeNotification,
                                           object: textView.enclosingScrollView?.contentView)
  }

  required init(coder: NSCoder) { fatalError("not used") }

  @objc private func changed() { needsDisplay = true }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let view = textView, let layout = view.textLayoutManager, let content = layout.textContentManager else { return }
    let visible = view.visibleRect
    let string = view.string as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor
    ]
    if string.length == 0 {
      draw("1", y: view.textContainerInset.height - visible.minY, attributes)
      return
    }
    var line = -1
    let start = layout.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY))?.rangeInElement.location
    layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
      let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
      if line < 0 {
        line = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: offset), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
      } else {
        line += 1
      }
      self.draw("\(line)", y: fragment.layoutFragmentFrame.minY + view.textContainerInset.height - visible.minY, attributes)
      return fragment.layoutFragmentFrame.minY < visible.maxY
    }
  }

  private func draw(_ label: String, y: CGFloat, _ attributes: [NSAttributedString.Key: Any]) {
    let text = label as NSString
    let size = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: ruleThickness - size.width - 5, y: y + 2), withAttributes: attributes)
  }
}
