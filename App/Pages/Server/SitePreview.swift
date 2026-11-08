import AppKit
import QuartzHubCore
import SwiftUI
import WebKit

/// The width the preview is drawn at, per band (QuartzControl's `previewWidthPx`): real device
/// widths, a phone (390) and an iPad upright (820), pulled into the project's own bands; with a
/// mobile band up to 900, 820 is a phone. nil is the whole width.
enum PreviewWidth {
  enum Mode: String, CaseIterable, Identifiable {
    case desktop, tablet, mobile
    var id: String { rawValue }

    var title: String {
      switch self {
      case .desktop: L10n.t("buildServer.viewport.desktop")
      case .tablet: L10n.t("buildServer.viewport.tablet")
      case .mobile: L10n.t("buildServer.viewport.mobile")
      }
    }
  }

  static let phone = 390.0
  static let tabletPortrait = 820.0

  static func points(_ mode: Mode, widths: (tablet: Double, mobile: Double)) -> Double? {
    switch mode {
    case .desktop: nil
    case .mobile: min(phone, widths.mobile)
    case .tablet: max(min(tabletPortrait, widths.tablet), widths.mobile + 1)
    }
  }

  /// "390 px", as JavaScript writes the number.
  static func text(_ width: Double?) -> String {
    guard let width else { return L10n.t("buildServer.viewport.full") }
    return (width == width.rounded() ? String(Int(width)) : String(width)) + " px"
  }
}

/// The site as the dev server serves it, at real CSS pixels: the view's width is the viewport the
/// site's media queries see, so a narrow window scrolls sideways instead of scaling. QuartzControl's
/// sandboxed iframe kept the site from navigating the app window; here the site stays in its own
/// view, and a link to anywhere but the server opens in the browser.
struct SitePreview: NSViewRepresentable {
  let url: URL // not a file path: the dev server's address
  let label: String

  func makeNSView(context: Context) -> WKWebView {
    let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    view.navigationDelegate = context.coordinator
    view.uiDelegate = context.coordinator
    view.setAccessibilityLabel(label)
    view.load(URLRequest(url: url))
    return view
  }

  func updateNSView(_ view: WKWebView, context: Context) {
    context.coordinator.origin = Self.origin(url)
  }

  func makeCoordinator() -> Coordinator { Coordinator(origin: Self.origin(url)) }

  static func origin(_ url: URL) -> String { // not a file path
    "\(url.host ?? ""):\(url.port ?? 80)"
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var origin: String

    init(origin: String) { self.origin = origin }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
      guard let target = action.request.url else { return .cancel }
      if target.scheme == "about" || SitePreview.origin(target) == origin { return .allow }
      if action.navigationType == .linkActivated { NSWorkspace.shared.open(target) }
      return .cancel
    }

    /// `target="_blank"`: in the browser, not in a second view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
      if let target = action.request.url { NSWorkspace.shared.open(target) }
      return nil
    }
  }
}
