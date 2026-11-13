import AppKit
import QuartzHubCore
import SwiftUI
import WebKit

/// The project's site at the width of a device, scaled into the room it has: Vorschau & Build and
/// the plugin editors draw it the same way (decisions/ui-ueberarbeitung.md, Vorschau). Desktop is
/// rendered wider than the tablet band (`desktopWidth`), so the site shows its desktop layout even
/// in a narrow window; "100 %" shows real pixels and scrolls sideways instead.
struct ScaledSite: View {
  let url: URL // not a file path: the dev server's address
  /// A new key loads the site again ("Vorschau neu laden").
  let reloadKey: String
  let width: Double
  let fit: Bool
  let label: String

  /// The scale `fit` gives in a box of `room` points.
  static func scale(width: Double, room: Double, fit: Bool) -> Double {
    fit && room > 0 ? min(1, room / width) : 1
  }

  /// What Desktop renders at: wider than the project's tablet band, never under 1280.
  static func desktopWidth(tablet: Double) -> Double { max(tablet + 1, 1280) }

  /// Host and port: a link elsewhere opens in the browser, not in the preview.
  static func origin(_ url: URL) -> String { // not a file path
    "\(url.host ?? ""):\(url.port ?? 80)"
  }

  var body: some View {
    GeometryReader { geometry in
      let box = geometry.size
      let scale = Self.scale(width: width, room: box.width, fit: fit)
      // One web view in both modes, in a scroll view that only scrolls at real pixels: a second
      // view for "100 %" loaded the site again and lost the page the reader had gone to (measured).
      let frameWidth = fit ? box.width : max(width, box.width)
      ScrollView(.horizontal) {
        MarkedSite(url: url, frameKey: reloadKey, label: label,
                   size: CGSize(width: width, height: box.height / scale),
                   cut: CGRect(x: 0, y: 0, width: frameWidth / scale, height: box.height / scale),
                   offsetX: width * scale < frameWidth ? (frameWidth - width * scale) / 2 : 0,
                   selector: nil, focus: false) { _, _ in }
          .frame(width: frameWidth, height: box.height)
      }
      .scrollDisabled(frameWidth <= box.width)
      .id(reloadKey)
    }
  }
}

/// The site in a web view of the device's width, scaled and moved into the box by a container
/// whose bounds are the cut-out: AppKit draws the web view scaled and turns clicks back into the
/// site's points, as QuartzControl's CSS transform did for the iframe. The web view's own size
/// never changes with the zoom: a new size would be a new viewport.
struct MarkedSite: NSViewRepresentable {
  let url: URL // not a file path: the dev server's address
  let frameKey: String
  let label: String
  let size: CGSize
  let cut: CGRect
  let offsetX: Double
  let selector: String?
  let focus: Bool
  let onReport: (PreviewMarks.Report, String) -> Void

  static let handler = "quartzhubPreview"
  /// The marking script reports to `parent`, which is the site itself here; this hands its
  /// messages on, as text, to QuartzHub. Everything in them is checked by `PreviewMarks.report`.
  static let relay = """
  addEventListener('message', (e) => {
    if (e.source !== window || !e.data || e.data.source !== 'quartzcontrol-preview') return
    try { webkit.messageHandlers.\(handler).postMessage(JSON.stringify(e.data)) } catch {}
  })
  """

  /// Light or dark as QuartzHub shows itself. Quartz's darkmode script keeps the last scheme in
  /// `localStorage["theme"]` (on a click and on every change of the system's) and from then on no
  /// longer asks `prefers-color-scheme`; the preview's store outlives a launch, so the site stayed
  /// dark in a QuartzHub set to light (review 2026-11-13, nebenbei; measured with the plugin's own
  /// script in WebKit: "dark" before, "light" after). Forgotten before the site's script runs.
  static let followAppearance = "try { localStorage.removeItem('theme') } catch {}"

  func makeNSView(context: Context) -> CutView {
    let configuration = WKWebViewConfiguration()
    let scripts = WKUserContentController()
    scripts.addUserScript(WKUserScript(source: Self.relay, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    scripts.addUserScript(WKUserScript(source: Self.followAppearance, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    scripts.add(context.coordinator, name: Self.handler)
    configuration.userContentController = scripts
    let web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
    web.navigationDelegate = context.coordinator
    web.uiDelegate = context.coordinator
    web.setAccessibilityLabel(label)
    context.coordinator.web = web
    let container = CutView()
    container.addSubview(web)
    web.load(URLRequest(url: url))
    return container
  }

  func updateNSView(_ container: CutView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    guard let web = coordinator.web else { return }
    if web.frame.size != size { web.frame = CGRect(origin: .zero, size: size) }
    container.cut = cut
    container.offsetX = offsetX
    container.needsLayout = true
    if coordinator.applied != Coordinator.key(selector, focus) { coordinator.mark() }
  }

  static func dismantleNSView(_ container: CutView, coordinator: Coordinator) {
    coordinator.web?.configuration.userContentController.removeScriptMessageHandler(forName: handler)
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  /// The box: its bounds are the cut-out of the site, so its subview is drawn scaled.
  final class CutView: NSView {
    var cut = CGRect.zero
    var offsetX = 0.0
    override var isFlipped: Bool { true }

    override func layout() {
      super.layout()
      guard cut.width > 0, cut.height > 0 else { return }
      let scale = frame.width / cut.width
      // The bounds' origin moves the cut-out; a phone narrower than the box is centred.
      setBoundsSize(cut.size)
      setBoundsOrigin(CGPoint(x: cut.minX - offsetX / scale, y: cut.minY))
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var parent: MarkedSite
    weak var web: WKWebView?
    var applied: String?
    private var loaded = false

    init(parent: MarkedSite) { self.parent = parent }

    static func key(_ selector: String?, _ focus: Bool) -> String { "\(selector.map { "s" + $0 } ?? "-")|\(focus)" }

    /// Installs the script (again) with the selector shown; it keeps one state per page.
    func mark() {
      guard loaded, let web else { return }
      applied = Self.key(parent.selector, parent.focus)
      web.evaluateJavaScript(PreviewScript.call(selector: parent.selector, focus: parent.focus)) { _, _ in }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      loaded = true
      mark()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
      guard let text = message.body as? String, let data = text.data(using: .utf8), let value = try? JSJSON.parse(data),
            let report = PreviewMarks.report(value) else { return }
      parent.onReport(report, parent.frameKey)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
      guard let target = action.request.url else { return .cancel }
      if target.scheme == "about" || ScaledSite.origin(target) == ScaledSite.origin(parent.url) { return .allow }
      if action.navigationType == .linkActivated { ExternalOpen.open(target) }
      return .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
      if let target = action.request.url { ExternalOpen.open(target) }
      return nil
    }
  }
}
