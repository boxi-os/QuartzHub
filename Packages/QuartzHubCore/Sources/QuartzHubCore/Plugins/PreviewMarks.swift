import Foundation

/// The arithmetic and the words of the preview beside the plugin editors (QuartzControl's
/// `utils/sitePreview.ts` and the helpers of `components/SitePreview.tsx`, measured against them in
/// SitePreviewTests). The marking script itself is `PreviewScript`.
public enum PreviewMarks {
  public struct Rect: Sendable, Equatable {
    public var x, y, width, height: Double
  }

  /// What the marking script reports: how many elements the selector found, how many of them are
  /// visible, and where they are together.
  public struct Report: Sendable, Equatable {
    public var selector: String?
    public var found: Int
    public var visible: Int
    public var rect: Rect?
    public var viewport: (width: Double, height: Double)

    public static func == (a: Report, b: Report) -> Bool {
      a.selector == b.selector && a.found == b.found && a.visible == b.visible && a.rect == b.rect
        && a.viewport.width == b.viewport.width && a.viewport.height == b.viewport.height
    }
  }

  /// `parsePreviewReport`: the site's own scripts can post a message too, so every field is
  /// checked and anything else is no report.
  public static func report(_ data: JSONValue?) -> Report? {
    guard case .object(let d)? = data, d["source"] == .string("quartzcontrol-preview") else { return nil }
    let selector: String?
    switch d["selector"] {
    case .null?: selector = nil
    case .string(let text)?: selector = text
    default: return nil
    }
    func count(_ v: JSONValue?) -> Int? {
      guard case .number(let n)? = v, n.isFinite, n == n.rounded(), n >= 0, n < 10_000 else { return nil }
      return Int(n)
    }
    func number(_ v: JSONValue?) -> Double? {
      guard case .number(let n)? = v, n.isFinite else { return nil }
      return n
    }
    guard let found = count(d["found"]), let visible = count(d["visible"]), visible <= found else { return nil }
    guard case .object(let vp)? = d["viewport"], let vw = number(vp["width"]), let vh = number(vp["height"]) else { return nil }
    var rect: Rect?
    if d["rect"] != .null {
      guard case .object(let r)? = d["rect"], let x = number(r["x"]), let y = number(r["y"]),
            let w = number(r["width"]), let h = number(r["height"]), w > 0, h > 0 else { return nil }
      rect = Rect(x: x, y: y, width: w, height: h)
    }
    return Report(selector: selector, found: found, visible: visible, rect: rect, viewport: (vw, vh))
  }

  /// Room around the element, in the site's pixels.
  static let pad = 24.0
  /// Beyond one and a half times real size a component shows its type, not its layout.
  static let maxScale = 1.5

  /// `zoomOnto`: the scale, and the top-left corner of the cut-out in the site's pixels. Never
  /// below the scale the whole page is shown at, never above 1.5; an element taller than the box
  /// is cut at the bottom rather than shrunk below real size.
  public static func zoom(onto rect: Rect, frame: (width: Double, height: Double), box: (width: Double, height: Double),
                          baseScale: Double) -> (scale: Double, x: Double, y: Double) {
    let fitWidth = box.width / (rect.width + 2 * pad)
    let fitHeight = box.height / (rect.height + 2 * pad)
    let scale = max(baseScale, min(maxScale, fitWidth, max(fitHeight, 1)))
    let view = (width: box.width / scale, height: box.height / scale)
    func along(_ start: Double, _ length: Double, _ viewLength: Double, _ frameLength: Double) -> Double {
      let ideal = length + 2 * pad <= viewLength ? start + length / 2 - viewLength / 2 : start - pad
      return min(max(0, ideal), max(0, frameLength - viewLength))
    }
    return (scale, along(rect.x, rect.width, view.width, frame.width), along(rect.y, rect.height, view.height, frame.height))
  }

  /// Two page paths are the same without their slashes at either end.
  /// Compared by their bytes, as JavaScript compares: `==` would take "Über" in NFC and NFD for one page.
  public static func samePage(_ a: String, _ b: String) -> Bool {
    a.trimmingCharacters(in: CharacterSet(charactersIn: "/")).utf8.elementsEqual(b.trimmingCharacters(in: CharacterSet(charactersIn: "/")).utf8)
  }

  /// `nearestPage`: the page of `list` with the most leading folders in common with the one shown,
  /// the list's order among equals (a site in several languages keeps each in its folder).
  public static func nearestPage(_ list: [String], to page: String) -> String? {
    func folders(_ p: String) -> [Substring] {
      var path = Substring(p)
      while path.hasPrefix("/") { path = path.dropFirst() }
      return Array(path.split(separator: "/", omittingEmptySubsequences: false).dropLast())
    }
    let shown = folders(page)
    func shared(_ p: String) -> Int {
      let own = folders(p)
      var n = 0
      while n < own.count, n < shown.count, own[n].utf8.elementsEqual(shown[n].utf8) { n += 1 }
      return n
    }
    guard var best = list.first else { return nil }
    for p in list where shared(p) > shared(best) { best = p }
    return best
  }

  /// Which sentence stands under the preview (`markSentence`), as its key; the caller fills
  /// `name` (and `count` for the two with several marks).
  public enum Sentence: Equatable, Sendable {
    case notFound, stale, hidden, marked
    case shared(count: Int), noClass(count: Int)
  }

  public static func sentence(_ report: Report, matches: Int, ownClass: Bool, pages: [String]?, page: String) -> Sentence {
    if report.found == 0 {
      // The editor's list says this page has it, the page does not: the list is older than the page.
      return (pages ?? []).contains { samePage($0, page) } ? .stale : .notFound
    }
    if report.visible == 0 { return .hidden }
    if matches > 1 { return ownClass ? .shared(count: report.visible) : .noClass(count: report.visible) }
    return .marked
  }
}
