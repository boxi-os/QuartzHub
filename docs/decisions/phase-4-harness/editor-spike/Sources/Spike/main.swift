import AppKit
import Shared
import STTextView

let args = CommandLine.arguments
let mode = args[1]  // "ns" | "st"
let text = try! String(contentsOfFile: args[2], encoding: .utf8)
let edits = 200
let noHighlight = args.count > 3 && args[3] == "nohl"

func rss() -> String {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
  _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
  return "\(info.resident_size / 1_000_000) MB"
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  app.setActivationPolicy(.regular)
  let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.title = "spike-\(mode)"
  let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
  print("mode \(mode), \(text.split(separator: "\n", omittingEmptySubsequences: false).count) lines, rss before \(rss())")

  var insert: (Int) -> Void = { _ in }
  var highlightAll: () -> Void = {}
  var highlightAround: (Int) -> Void = { _ in }
  var view: NSView!

  if mode == "ns" {
    let scroll = NSTextView.scrollableTextView()
    let tv = scroll.documentView as! NSTextView
    print("textLayoutManager:", tv.textLayoutManager != nil ? "TextKit 2" : "TextKit 1")
    tv.font = font
    tv.isRichText = false
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.usesFindBar = true
    tv.isIncrementalSearchingEnabled = true
    tv.setAccessibilityIdentifier("editor")
    if args.contains("ruler") {
      scroll.verticalRulerView = LineNumberRuler(textView: tv)
      scroll.hasVerticalRuler = true
      scroll.rulersVisible = true
    }
    let t = ContinuousClock.now
    tv.string = text
    window.contentView = scroll
    window.makeKeyAndOrderFront(nil)
    window.displayIfNeeded()
    print("open+first display:", ms(t))
    highlightAll = { SCSSHighlight.apply(to: tv.textStorage!, range: NSRange(location: 0, length: tv.textStorage!.length)) }
    highlightAround = { SCSSHighlight.apply(to: tv.textStorage!, range: NSRange(location: $0, length: 1)) }
    insert = { tv.insertText("x", replacementRange: NSRange(location: $0, length: 0)) }
    view = tv
  } else {
    let scroll = STTextView.scrollableTextView()
    let tv = scroll.documentView as! STTextView
    tv.font = font
    tv.showsLineNumbers = true
    tv.highlightSelectedLine = true
    tv.isIncrementalSearchingEnabled = true
    tv.setAccessibilityIdentifier("editor")
    let t = ContinuousClock.now
    tv.text = text
    window.contentView = scroll
    window.makeKeyAndOrderFront(nil)
    window.displayIfNeeded()
    print("open+first display:", ms(t))
    let ns = { (tv.text ?? "") }
    highlightAll = {
      let s = ns()
      for (r, c) in SCSSHighlight.spans(s, range: NSRange(location: 0, length: (s as NSString).length)) { tv.addAttributes([.foregroundColor: c], range: r) }
    }
    highlightAround = { at in
      let s = ns()
      let r = (s as NSString).paragraphRange(for: NSRange(location: at, length: 1))
      tv.addAttributes([.foregroundColor: NSColor.labelColor], range: r)
      for (r, c) in SCSSHighlight.spans(s, range: r) { tv.addAttributes([.foregroundColor: c], range: r) }
    }
    insert = { tv.insertText("x", replacementRange: NSRange(location: $0, length: 0)) }
    view = tv
  }
  window.makeFirstResponder(view)
  app.activate(ignoringOtherApps: true)

  DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    var t = ContinuousClock.now
    print("rss after open:", rss()); if !noHighlight { highlightAll() }; window.displayIfNeeded()
    print("full highlight+display:", ms(t))
    let mid = (text as NSString).length / 2
    t = ContinuousClock.now
    for i in 0..<edits { insert(mid + i); if !noHighlight { highlightAround(mid + i) }; window.displayIfNeeded() }
    let total = ContinuousClock.now - t
    print(String(format: "per edit (insert+rehighlight+display): %.2f ms", (Double(total.components.seconds) * 1000 + Double(total.components.attoseconds) / 1e15) / Double(edits)))
    print("rss after:", rss())
    print("pid", ProcessInfo.processInfo.processIdentifier)
    fflush(stdout)
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 25) { exit(0) }
  app.run()

}
