import AppKit
import Foundation
import WebKit

/// The window a document export renders the user's site in (`exportWindow.ts`): never seen, in its
/// own data store in memory, without anything of QuartzHub's in the page.
///
/// What it may load from outside is QuartzControl's rule, not a blanket block (measured there on
/// 2026-11-05: the handbook and Example load KaTeX's stylesheet from jsdelivr, Mermaid from cdnjs):
/// from the export's own origin everything; from outside stylesheets, fonts and images, and scripts
/// only when their address is Mermaid's; everything else refused and counted by host. WebKit blocks
/// with a content rule list, which says nothing about what it blocked, so the counting is done
/// where each kind of request can be seen (measured 2026-11-07 against a second server, which
/// received exactly the five allowed requests of the probe page):
///
/// - what was fetched from outside: the page's resource timing entries (stylesheets, fonts, images,
///   Mermaid), read in the export's own content world;
/// - a refused script, video, audio or object: its element's `error` event, in the same world;
/// - a refused fetch, XMLHttpRequest, beacon, WebSocket or EventSource: wrappers set in the page's
///   world before its first script (the only part the site could see; it reports, it decides
///   nothing);
/// - a refused frame: the navigation policy.
///
/// The page scripts (`Helpers/dist/page-scripts.js`) live in a content world of their own, so the
/// site's scripts can neither call nor change them. Printed and collected light: the window has the
/// light appearance (`prefers-color-scheme: light` with the system dark), and Quartz's
/// `localStorage` theme is set before each page of the own origin. Needs the main run loop turning:
/// in the app it does; tests drive it through `qh-check` (see `runAndExit` there).
@MainActor
public final class ExportWindow: NSObject {
  public static let loadTimeout: Duration = .seconds(60)
  static let world = WKContentWorld.world(name: "quartzhub-export")
  nonisolated static let handler = "quartzHubExport"

  public let origin: String
  public let window: NSWindow
  public let webView: WKWebView
  /// Requests refused under the rule, by `<type> <host>` (Chromium's type names).
  public private(set) var refused: [(key: String, count: Int)] = []
  /// What was fetched from outside under the rule, by host.
  public private(set) var fetched: [(host: String, count: Int)] = []
  /// Addresses whose loading was stopped at the deadline (what had not arrived is missing).
  public private(set) var unfinished: [String] = []

  private let loadTimeout: Duration
  private var ruleStore: WKContentRuleListStore?
  private var ruleStoreFolder: String?
  private var waiting: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]
  private var closed = false
  private let relay = MessageRelay()

  /// The page scripts' source, read once.
  public static func pageScripts(location: RuntimeLocation = .current) throws -> String {
    String(decoding: try Posix.read("\(location.helpers)/page-scripts.js"), as: UTF8.self)
  }

  public init(origin: String, size: CGSize, pageScripts: String, loadTimeout: Duration = ExportWindow.loadTimeout) {
    self.origin = origin
    self.loadTimeout = loadTimeout
    _ = NSApplication.shared
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    let content = configuration.userContentController
    content.addUserScript(WKUserScript(source: Self.observer(origin: origin) + "\n" + pageScripts, injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true, in: Self.world))
    content.addUserScript(WKUserScript(source: Self.pageWrappers, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    content.add(relay, contentWorld: Self.world, name: Self.handler)
    content.add(relay, contentWorld: .page, name: Self.handler)
    webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
    webView.appearance = NSAppearance(named: .aqua)
    // On a screen, at alpha 0: a window far off every screen takes no snapshot (the spike's
    // measurement), and one that is ordered out does not paint.
    window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.isExcludedFromWindowsMenu = true
    window.collectionBehavior = [.transient, .ignoresCycle]
    window.isReleasedWhenClosed = false
    window.contentView = webView
    super.init()
    relay.target = self
    webView.navigationDelegate = self
    webView.uiDelegate = self
    window.orderFrontRegardless()
  }

  /// Compiles the rule for this origin and puts it in place; before the first load.
  public func prepare() async throws {
    let folder = NSTemporaryDirectory() + "quartzhub-export-rules-\(UUID().uuidString.lowercased())"
    try Posix.mkdirs(folder)
    ruleStoreFolder = folder
    guard let store = WKContentRuleListStore(url: URL(fileURLWithPath: folder)) else { return } // path boundary
    ruleStore = store
    let list = try await store.compileContentRuleList(forIdentifier: "export", encodedContentRuleList: Self.rules(origin: origin))
    if let list { webView.configuration.userContentController.add(list) }
  }

  /// QuartzControl's rule as a content rule list: block everything, then let through the own
  /// origin, data:, blob:, stylesheets, fonts and images, and Mermaid's scripts. (The rule list's
  /// regular expressions know no `|`.)
  nonisolated static func rules(origin: String) -> String {
    let own = NSRegularExpression.escapedPattern(for: origin + "/")
    let allow = { (filter: String, types: [String]?) -> String in
      let types = types.map { ",\"resource-type\":[\($0.map { "\"\($0)\"" }.joined(separator: ","))]" } ?? ""
      return "{\"trigger\":{\"url-filter\":\(JSJSON.compact(.string(filter)))\(types)},\"action\":{\"type\":\"ignore-previous-rules\"}}"
    }
    return "[" + ["{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block\"}}",
                  allow("^" + own, nil), allow("^data:", nil), allow("^blob:", nil), allow("^about:", nil),
                  allow(".*", ["style-sheet", "font", "image"]), allow("/mermaid[@/.-]", ["script"])].joined(separator: ",") + "]"
  }

  /// In the export's world, before the page: resource timing for what was fetched, element errors
  /// for what was refused, and the light theme.
  nonisolated static func observer(origin: String) -> String {
    """
    (() => {
      const own = \(JSJSON.compact(.string(origin)));
      const post = (kind, type, url) => { try { window.webkit.messageHandlers.\(handler).postMessage({ kind, type, url: String(url) }) } catch {} };
      try { if (location.origin === own) localStorage.setItem('theme', 'light') } catch {}
      try {
        new PerformanceObserver((list) => { for (const e of list.getEntries()) post('fetched', e.initiatorType, e.name) }).observe({ type: 'resource', buffered: true });
      } catch {}
      const types = { SCRIPT: 'script', VIDEO: 'media', AUDIO: 'media', SOURCE: 'media', TRACK: 'media', OBJECT: 'object', EMBED: 'object' };
      const told = new WeakSet();
      const tell = (t, type, url) => { if (told.has(t)) return; told.add(t); post('failed', type, url) };
      // An object or embed from outside is refused without an error event (measured 2026-11-07):
      // counted by its address once the document is parsed.
      document.addEventListener('DOMContentLoaded', () => {
        for (const t of document.querySelectorAll('object[data], embed[src]')) {
          try { tell(t, 'object', new URL(t.getAttribute('data') || t.getAttribute('src'), location.href).href) } catch {}
        }
      });
      window.addEventListener('error', (e) => {
        const t = e.target;
        if (!t || t === window || !t.tagName) return;
        let type = types[t.tagName];
        if (t.tagName === 'LINK') type = ({ script: 'script', fetch: 'xhr', video: 'media', audio: 'media', track: 'media' })[t.as] || (t.rel === 'stylesheet' || t.as === 'style' || t.as === 'font' || t.as === 'image' ? null : 'other');
        if (type) tell(t, type, t.src || t.href || t.currentSrc || t.data || '');
      }, true);
    })();
    """
  }

  /// In the page's world, before its first script: what the site asks for in code.
  nonisolated static let pageWrappers = """
  (() => {
    // Against the document, as the request goes out: `fetch('/static/x')` is the own origin's.
    const absolute = (url) => { try { return new URL(String(url && url.url || url), location.href).href } catch { return String(url) } };
    const post = (type, url) => { try { window.webkit.messageHandlers.\(handler).postMessage({ kind: 'asked', type, url: absolute(url) }) } catch {} };
    const f = window.fetch;
    if (f) window.fetch = function (input, init) { post('xhr', input); return f.apply(this, arguments) };
    const open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) { post('xhr', url); return open.apply(this, arguments) };
    if (navigator.sendBeacon) { const b = navigator.sendBeacon.bind(navigator); navigator.sendBeacon = function (url, data) { post('ping', url); return b(url, data) } }
    const W = window.WebSocket;
    if (W) { const S = function (url, protocols) { post('webSocket', url); return protocols === undefined ? new W(url) : new W(url, protocols) }; S.prototype = W.prototype; Object.assign(S, W); window.WebSocket = S }
    const E = window.EventSource;
    if (E) { const S = function (url, init) { post('xhr', url); return new E(url, init) }; S.prototype = E.prototype; window.EventSource = S }
  })();
  """

  /// `host` as QuartzControl names it in the report: the host of a web address, the scheme in
  /// parentheses for anything else, the first 40 characters of what cannot be read.
  nonisolated static func host(_ url: String) -> String {
    guard let parts = WebURL(url, numericHosts: true).parts else {
      // WHATWG reads nearly anything after a scheme that is not one of the special ones
      // (chrome-extension://…); a special one that does not parse stays as it was written.
      if let scheme = JSText.firstMatch(url, #"\A([A-Za-z][A-Za-z0-9+.\-]*):"#)?.groups[1]?.lowercased(),
         !["http", "https", "ws", "wss", "ftp", "file"].contains(scheme) { return "(\(scheme))" }
      return JSText.slice(url, 0, 40)
    }
    return JSText.test(parts.protocol, #"\A(https?|wss?):\z"#) ? parts.host : "(\(JSText.slice(parts.protocol, 0, JSText.length(parts.protocol) - 1)))"
  }

  /// What passes without a word: the own origin, data: and blob: (QuartzControl let devtools: through
  /// as well, which WebKit never asks for).
  nonisolated static func passes(_ url: String, origin: String) -> Bool {
    JSText.startsWith(url, origin + "/") || url == origin || JSText.startsWith(url, "data:") || JSText.startsWith(url, "blob:")
  }

  /// Whether a request from outside to `url` of Chromium's `type` passes the rule.
  nonisolated static func allowedFromOutside(_ url: String, type: String) -> Bool {
    ["stylesheet", "font", "image"].contains(type) || (type == "script" && JSText.test(url, #"/mermaid[@/.-]"#))
  }

  /// `will-navigate` and `will-redirect`: the main frame goes to the own documents only (below the
  /// origin's `/`; the bare origin is refused there too).
  nonisolated static func mayNavigate(_ url: String, origin: String) -> Bool { JSText.startsWith(url, origin + "/") }

  /// Not counted: the own origin, data:, blob:, and about: (the empty frame a page makes).
  func isOwn(_ url: String) -> Bool { Self.passes(url, origin: origin) || JSText.startsWith(url, "about:") }

  func allowed(_ url: String, type: String) -> Bool { Self.passes(url, origin: origin) || Self.allowedFromOutside(url, type: type) }

  func count(_ list: inout [(key: String, count: Int)], _ key: String) {
    if let i = list.firstIndex(where: { $0.key == key }) { list[i].count += 1 } else { list.append((key, 1)) }
  }

  /// A message of the observer or the page wrappers.
  func note(kind: String, type: String, url: String) {
    guard !isOwn(url) else { return }
    switch kind {
    case "fetched":
      // Resource timing names what came: an initiator of css, link or img is a stylesheet's, a
      // font's or a picture's request, a script only Mermaid's.
      let host = Self.host(url)
      if let i = fetched.firstIndex(where: { $0.host == host }) { fetched[i].count += 1 } else { fetched.append((host, 1)) }
    case "failed", "asked":
      // An element that failed or a request asked for in code: refused when the rule refuses it
      // (a picture that failed was fetched and answered with an error).
      if !allowed(url, type: type) { count(&refused, "\(type) \(Self.host(url))") }
    default: break
    }
  }

  /// `load(url)`: false when the page did not finish within the deadline; it is then stopped and
  /// stands as it is. A failed load throws its reason.
  @discardableResult
  public func load(_ url: String) async throws -> Bool {
    guard !closed else { throw CancellationError() }
    guard let target = URL(string: url) else { throw PublishFailure(url) }
    let navigation = webView.load(URLRequest(url: target))
    guard let navigation else { return false }
    let key = ObjectIdentifier(navigation)
    let deadline = Task { @MainActor [weak self, loadTimeout] in
      try await Task.sleep(for: loadTimeout)
      guard let self, let continuation = self.waiting.removeValue(forKey: key) else { return }
      self.webView.stopLoading()
      self.unfinished.append(url)
      continuation.resume(throwing: LoadTimedOut())
    }
    defer { deadline.cancel() }
    do {
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in waiting[key] = continuation }
      } onCancel: {
        Task { @MainActor [weak self] in self?.cancelWaiting() }
      }
      return true
    } catch is LoadTimedOut {
      return false
    }
  }

  struct LoadTimedOut: Error {}

  func finish(_ navigation: WKNavigation?, _ error: Error?) {
    guard let navigation, let continuation = waiting.removeValue(forKey: ObjectIdentifier(navigation)) else { return }
    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
  }

  func cancelWaiting() {
    webView.stopLoading()
    let all = waiting
    waiting.removeAll()
    for continuation in all.values { continuation.resume(throwing: CancellationError()) }
  }

  public struct ScriptFailure: Error, CustomStringConvertible, Equatable {
    public let description: String
  }

  /// `run(fn, args, helpers)`: one of the page scripts with JSON arguments, and further page
  /// script functions handed to it as arguments (`slugFromPathname`, `anchorFor`, `outsideUrl`).
  /// A throw in the page comes back with its message.
  public func run(_ function: String, _ arguments: [JSONValue], helpers: [String] = []) async throws -> JSONValue {
    try await evaluate("""
      const h = window.__quartzHubExport;
      return await h[fn](...args, ...helpers.map((n) => h[n]));
      """, arguments: ["fn": .string(function), "args": .array(arguments), "helpers": .array(helpers.map(JSONValue.string))])
  }

  /// A function body of QuartzHub's own in the export's world, its arguments by name as JSON.
  public func evaluate(_ body: String, arguments: [String: JSONValue] = [:]) async throws -> JSONValue {
    guard !closed else { throw CancellationError() }
    let names = arguments.keys.sorted()
    let script = """
      const __args = JSON.parse(__payload);
      const { \(names.joined(separator: ", ")) } = __args;
      try {
        const value = await (async () => { \(body) })();
        return JSON.stringify({ ok: true, value: value === undefined ? null : value });
      } catch (e) {
        return JSON.stringify({ ok: false, error: String((e && e.message) || e) });
      }
      """
    let payload = JSJSON.compact(.object(JSONObject(names.map { ($0, arguments[$0]!) })))
    let raw = try await withTaskCancellationHandler {
      try await webView.callAsyncJavaScript(script, arguments: ["__payload": payload], contentWorld: Self.world)
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelWaiting() }
    }
    try Task.checkCancellation()
    guard let text = raw as? String, let answer = try? JSJSON.parse(text) else { throw ScriptFailure(description: "no answer") }
    if answer["ok"] == .bool(true) { return answer["value"] ?? .null }
    throw ScriptFailure(description: answer["error"]?.stringValue ?? "unknown error")
  }

  /// Closes the window at once, whatever it waits for.
  public func close() {
    guard !closed else { return }
    closed = true
    cancelWaiting()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeAllScriptMessageHandlers()
    window.orderOut(nil)
    window.close()
    if let folder = ruleStoreFolder { try? FileManager.default.removeItem(atPath: folder) }
  }
}

extension ExportWindow: WKNavigationDelegate, WKUIDelegate {
  public nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                                  decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
    MainActor.assumeIsolated {
      let url = action.request.url?.absoluteString ?? ""
      let main = action.targetFrame?.isMainFrame ?? true
      if main {
        decisionHandler(Self.mayNavigate(url, origin: origin) ? .allow : .cancel)
        return
      }
      if isOwn(url) || url.isEmpty { return decisionHandler(.allow) }
      count(&refused, "subFrame \(Self.host(url))")
      decisionHandler(.cancel)
    }
  }

  public nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    MainActor.assumeIsolated { finish(navigation, nil) }
  }

  public nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    MainActor.assumeIsolated { finish(navigation, error) }
  }

  public nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    MainActor.assumeIsolated { finish(navigation, error) }
  }

  public nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    MainActor.assumeIsolated {
      let all = waiting
      waiting.removeAll()
      for continuation in all.values { continuation.resume(throwing: ScriptFailure(description: "web content process terminated")) }
    }
  }

  // No new windows, no dialogs that wait for a click, no permission ever granted.
  public nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                                  for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

  public nonisolated func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                                  initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
    MainActor.assumeIsolated { completionHandler() }
  }

  public nonisolated func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                                  initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
    MainActor.assumeIsolated { completionHandler(false) }
  }

  public nonisolated func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                                  initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
    MainActor.assumeIsolated { completionHandler(nil) }
  }

  public nonisolated func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                                  type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
    MainActor.assumeIsolated { decisionHandler(.deny) }
  }

  public nonisolated func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
                                  completionHandler: @escaping @MainActor ([URL]?) -> Void) { // not a file path: WebKit's signature
    MainActor.assumeIsolated { completionHandler(nil) }
  }
}

/// The script message handler, apart from the window so the content controller's strong hold on
/// it does not keep the window alive.
@MainActor
final class MessageRelay: NSObject, WKScriptMessageHandler {
  weak var target: ExportWindow?

  nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    MainActor.assumeIsolated {
      guard let body = message.body as? [String: Any], let kind = body["kind"] as? String, let url = body["url"] as? String else { return }
      target?.note(kind: kind, type: body["type"] as? String ?? "other", url: url)
    }
  }
}
