import AppKit
import SwiftUI

/// Where a page was scrolled to, kept while QuartzHub runs (QuartzControl's `useRestoreScroll` in
/// `ProjectLayout.tsx`; user, 2026-11-09). Each visit to a page builds it anew, so without this it
/// opened at the top every time.
///
/// Keyed by project and page, not persisted: QuartzControl's ask was "beim Wechseln der Seiten",
/// not "nach einem Neustart". The page's own scroll view is the largest one inside the page's
/// frame, by overlap (the inspector is outside it): a page does not hand its scroller out, and SwiftUI does not
/// say which one a `Form` or `List` became.
///
/// A page reaches its height only once its data has loaded, so during its first five seconds
/// the saved offset is applied again whenever the document grows or something other than the user
/// moves it, as QuartzControl did with a ResizeObserver. Only the user's own scrolling is saved.
///
/// In a `List` (an outline view) the place is the row at the top and how far into it, brought back
/// with `scrollRowToVisible`: the list knows the heights of rows it has not drawn only as estimates,
/// and the same offset landed a section away (measured on Plugins, 2026-11-09,
/// docs/decisions/phase-5-gleichstand.md).
struct ScrollMemory: NSViewRepresentable {
  let key: String

  /// The offset, or in a list the row at the top and how far into it.
  struct Place { var offset: CGFloat; var row: Int?; var fraction: CGFloat }

  @MainActor static var places: [String: Place] = [:]

  func makeNSView(context: Context) -> Probe {
    let probe = Probe()
    probe.key = key
    return probe
  }

  func updateNSView(_ probe: Probe, context: Context) {
    probe.key = key
  }

  @MainActor final class Probe: NSView {
    var key = ""
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []
    private var restoring = false
    private var scans = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil {
        detach()
      } else {
        scans = 0
        // Not at once: the page left behind still has its scroller in the window for a moment.
        DispatchQueue.main.async { [weak self] in self?.scan() }
      }
    }

    /// SwiftUI makes the page's scroller a moment after the page appears, and a loading page may
    /// show a spinner first: look again for about five seconds (Plugins reads its config for more than one and a half).
    private func scan() {
      guard window != nil else { return }
      if let found = mainScrollView(), found !== scrollView || scrollView?.window == nil { attach(found) }
      scans += 1
      guard scans < Self.settleScans else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.scan() }
    }

    private func mainScrollView() -> NSScrollView? {
      guard let root = window?.contentView else { return nil }
      let frame = convert(bounds, to: nil)
      var best: (view: NSScrollView, area: CGFloat)?
      func walk(_ view: NSView) {
        if let scroll = view as? NSScrollView, !scroll.isHidden {
          // Overlap, not containment: a Form's scroller reaches up under the toolbar.
          let overlap = scroll.convert(scroll.bounds, to: nil).intersection(frame)
          let area = overlap.isNull ? 0 : overlap.width * overlap.height
          if area > (best?.area ?? 0) { best = (scroll, area) }
        }
        view.subviews.forEach(walk)
      }
      walk(root)
      return best?.view
    }

    private func attach(_ scroll: NSScrollView) {
      detach()
      scrollView = scroll
      let clip = scroll.contentView
      clip.postsBoundsChangedNotifications = true
      observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.save() }
      })
      if let document = scroll.documentView {
        document.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: document, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.settling() }
        })
      }
      restore()
    }

    private func detach() {
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
      scrollView = nil
    }

    /// Only what the user scrolled: SwiftUI puts a `Form` back to its top inset once more after it
    /// appeared, and saved, that move erased the place it was meant to come back to (measured on
    /// Übersicht). While the page settles, such a move is undone instead.
    private func save() {
      guard !restoring, let scroll = scrollView else { return }
      if byUser(NSApp.currentEvent, scroll) {
        ScrollMemory.places[key] = place(scroll)
      } else if scans < Self.settleScans {
        DispatchQueue.main.async { [weak self] in self?.restore() }
      }
    }

    private static let settleScans = 40

    /// The document grew while the page loaded in. Later growth (a log, a list filling) leaves the
    /// place alone: by then it is the user's.
    ///
    /// Not inside the notification: a list posts it from its own row update, and `restore` lays the
    /// window out, so SwiftUI moved rows in a table that was still updating, and AppKit threw
    /// (`moveRowsInRange:toIndex:`; Plugins, coming back while plugin doctor's findings changed row
    /// heights, measured 2026-11-11). Once afterwards, however often the document grew meanwhile.
    private func settling() {
      guard scans < Self.settleScans, !restorePending else { return }
      restorePending = true
      DispatchQueue.main.async { [weak self] in
        self?.restorePending = false
        self?.restore()
      }
    }

    private var restorePending = false

    /// A wheel, a drag of the scroller or a key aimed at this scroller. The click in the sidebar that
    /// opened the page is an event too, and the page's first layout happens under it.
    private func byUser(_ event: NSEvent?, _ scroll: NSScrollView) -> Bool {
      guard let event, event.window === window else { return false }
      switch event.type {
      case .scrollWheel, .leftMouseDragged, .swipe:
        return scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil))
      case .keyDown:
        return (window?.firstResponder as? NSView)?.isDescendant(of: scroll) ?? false
      default:
        return false
      }
    }

    private func place(_ scroll: NSScrollView) -> Place {
      let offset = scroll.contentView.bounds.origin.y
      guard let table = scroll.documentView as? NSTableView else { return Place(offset: offset, row: nil, fraction: 0) }
      let top = offset + scroll.contentInsets.top
      // By `rect(ofRow:)`, the measure `restore` places with: SwiftUI's outline answered
      // `row(at:)` with a row that ended above the point (measured on Plugins).
      let visible = table.rows(in: scroll.contentView.documentVisibleRect)
      guard let row = (visible.lowerBound..<max(visible.upperBound, visible.lowerBound)).first(where: { table.rect(ofRow: $0).maxY > top })
      else { return Place(offset: offset, row: nil, fraction: 0) }
      let rect = table.rect(ofRow: row)
      return Place(offset: offset, row: row, fraction: rect.height > 0 ? min(max((top - rect.minY) / rect.height, 0), 1) : 0)
    }

    private func restore() {
      guard let scroll = scrollView, let saved = ScrollMemory.places[key] else { return }
      let clip = scroll.contentView
      var target = saved.offset
      if let row = saved.row, let table = scroll.documentView as? NSTableView {
        guard row < table.numberOfRows else { return }
        restoring = true
        table.scrollRowToVisible(row)
        scroll.window?.layoutIfNeeded()
        restoring = false
        let rect = table.rect(ofRow: row)
        target = rect.minY + saved.fraction * rect.height - scroll.contentInsets.top
      }
      guard abs(clip.bounds.origin.y - target) > 0.5 else { return }
      restoring = true
      clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
      scroll.reflectScrolledClipView(clip)
      restoring = false
    }
  }
}
