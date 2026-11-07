import AppKit
import Darwin
import Foundation
import QuartzHubCore
import Synchronization

/// `qh-check export-window`: whether the export window holds to QuartzControl's rule in WebKit.
/// Two servers on 127.0.0.1 - the export's own site and a second origin standing for the web, which
/// writes down every path that reaches it - and pages that ask for one of each kind of request.
/// What reaches the second server must be exactly what the rule lets through
/// (`ExportWindowRuleTests` holds the rule against QuartzControl's), and the window must have
/// counted it: fetched by host, refused by kind and host. Then a main frame that tries to leave,
/// a page that does not finish in time, a cancel, a throw in a page script, the light theme, dialogs
/// that do not wait, and that the page does not see the page scripts.
@MainActor
func runExportWindowCheck(root: String) async -> Int32 {
  var failures = 0
  func check(_ ok: Bool, _ sentence: String) {
    print(ok ? "ok      \(sentence)" : "FEHLER  \(sentence)")
    if !ok { failures += 1 }
  }
  let scripts: String
  do {
    scripts = try ExportWindow.pageScripts(location: RuntimeLocation(node: "", git: "", helpers: "\(root)/Helpers/dist"))
  } catch {
    print("Helpers/dist/page-scripts.js fehlt: erst scripts/build-helpers.sh (\(error))")
    return 3
  }
  let work = NSTemporaryDirectory() + "qh-export-window-\(getpid())"
  defer { try? FileManager.default.removeItem(atPath: work) }

  // ── the web: a second origin that writes down what reaches it ────────────────────────────────
  let outsideFiles = [
    "s.css": "body{color:#111}", "x.js": "window.__x=1", "pre.js": "window.__pre=1", "mermaid@11/mermaid.min.js": "window.__mermaid=1",
    "data.json": "{}", "xhr": "x", "frame.html": "<p>frame</p>", "f.woff2": "woff2", "i.png": "png", "away.html": "<p>away</p>"
  ]
  let reached = Mutex<[String]>([])
  let site: SiteServer, web: SiteServer
  do {
    for (path, text) in outsideFiles { try write("\(work)/web/\(path)", text) }
    try write("\(work)/web/.keep", "")
    let webServer = try await SiteServer.start(try SiteCopy.make(from: "\(work)/web", tempRoot: work)) { path in reached.withLock { $0.append(path) } }
    web = webServer
    let b = webServer.origin
    try write("\(work)/site/index.html", "<!doctype html><html><head><meta charset=utf-8></head><body><article><p>Start</p></article></body></html>")
    try write("\(work)/site/requests.html", """
      <!doctype html><html><head><meta charset="utf-8">
      <link rel="stylesheet" href="\(b)/s.css">
      <link rel="preload" as="script" href="\(b)/pre.js">
      <style>@font-face{font-family:F;src:url(\(b)/f.woff2)} body{font-family:F} .bg{background:url(\(b)/bg.png)}</style>
      <script src="\(b)/x.js"></script>
      <script src="\(b)/mermaid@11/mermaid.min.js"></script>
      <script src="\(b)/mermaid@11/fehlt.js"></script>
      </head><body><div class="bg">bg</div>
      <img src="\(b)/i.png"><img src="/own.png">
      <iframe src="\(b)/frame.html"></iframe><iframe src="about:blank"></iframe>
      <video src="\(b)/v.mp4" preload="auto"></video><audio src="\(b)/a.mp3" preload="auto"></audio>
      <object data="\(b)/doc.pdf" type="application/pdf"></object>
      <script>
      fetch('\(b)/data.json').catch(() => {});
      fetch('/static/own.json').catch(() => {});
      const x = new XMLHttpRequest(); x.open('GET', '\(b)/xhr'); x.send();
      try { navigator.sendBeacon('\(b)/beacon', 'x') } catch {}
      try { new WebSocket('\(b.replacingOccurrences(of: "http:", with: "ws:"))/ws') } catch {}
      try { new EventSource('\(b)/events') } catch {}
      try { window.open('\(b)/popup.html') } catch {}
      alert('kein Warten'); confirm('auch nicht');
      document.documentElement.dataset.sees = typeof window.__quartzHubExport;
      document.documentElement.dataset.theme = localStorage.getItem('theme') || 'none';
      document.documentElement.dataset.dark = String(matchMedia('(prefers-color-scheme: dark)').matches);
      document.documentElement.dataset.mermaid = String(window.__mermaid || 0);
      document.documentElement.dataset.x = String(window.__x || 0);
      </script></body></html>
      """)
    try write("\(work)/site/away.html", "<!doctype html><html><body><article>bleibt</article><script>setTimeout(() => { location.href = '\(b)/away.html' }, 10)</script></body></html>")
    // about: passes the rule list; only the navigation policy keeps the page (QuartzControl's
    // will-navigate refuses it).
    try write("\(work)/site/blank.html", "<!doctype html><html><body><article>bleibt</article><script>setTimeout(() => { location.href = 'about:blank' }, 10)</script></body></html>")
    try write("\(work)/site/own.png", "png")
    try write("\(work)/site/static/own.json", "{}")
    site = try await SiteServer.start(try SiteCopy.make(from: "\(work)/site", tempRoot: work))
  } catch {
    print("Testseiten nicht angelegt: \(error)")
    return 3
  }
  defer {
    site.close()
    web.close()
  }

  // ── one of each kind ─────────────────────────────────────────────────────────────────────────
  let window = ExportWindow(origin: site.origin, size: CGSize(width: 658, height: 1000), pageScripts: scripts)
  do {
    try await window.prepare()
    let loaded = try await window.load("\(site.origin)/requests.html")
    check(loaded, "die Seite mit allen Arten von Anfragen lädt")
    try await Task.sleep(for: .milliseconds(1500))
    // A Mermaid script that is not there was let through and failed: fetched, not refused.
    let allowed = Set(["/s.css", "/mermaid@11/mermaid.min.js", "/mermaid@11/fehlt.js", "/f.woff2", "/bg.png", "/i.png"])
    let arrived = Set(reached.withLock { $0 })
    check(arrived == allowed, "beim Web kommt genau an, was die Regel durchlässt: \(arrived.sorted().joined(separator: " "))")
    let host = String(web.origin.dropFirst(7))
    check(window.fetched.map { "\($0.host)=\($0.count)" } == ["\(host)=6"], "geholt nach Host: \(window.fetched.map { "\($0.host)=\($0.count)" })")
    let refused = window.refused.map { "\($0.key)=\($0.count)" }.sorted()
    let expected = ["script", "script", "xhr", "xhr", "ping", "webSocket", "xhr", "subFrame", "media", "media", "object"]
    let expectedKeys = Dictionary(expected.map { ("\($0) \(host)", 1) }, uniquingKeysWith: +).map { "\($0.key)=\($0.value)" }.sorted()
    check(refused == expectedKeys, "abgelehnt nach Art und Host: \(refused)")
    let seen = try await window.evaluate("""
      const d = document.documentElement.dataset;
      return { sees: d.sees, theme: d.theme, dark: d.dark, mermaid: d.mermaid, x: d.x };
      """)
    check(seen["sees"] == .string("undefined"), "die Seite sieht die Seitenskripte nicht (\(JSJSON.compact(seen["sees"] ?? .null)))")
    check(seen["theme"] == .string("light") && seen["dark"] == .string("false"), "hell: theme \(JSJSON.compact(seen["theme"] ?? .null)), dunkel \(JSJSON.compact(seen["dark"] ?? .null))")
    check(seen["mermaid"] == .string("1") && seen["x"] == .string("0"), "Mermaid läuft, das fremde Skript nicht")

    // ── the main frame stays ──────────────────────────────────────────────────────────────────
    _ = try await window.load("\(site.origin)/away.html")
    try await Task.sleep(for: .milliseconds(500))
    check(window.webView.url?.absoluteString == "\(site.origin)/away.html" && !reached.withLock { $0 }.contains("/away.html"),
          "die Seite verlässt die eigene Origin nicht (\(window.webView.url?.absoluteString ?? "-"))")

    _ = try await window.load("\(site.origin)/blank.html")
    try await Task.sleep(for: .milliseconds(500))
    check(window.webView.url?.absoluteString == "\(site.origin)/blank.html", "auch nicht nach about:blank (\(window.webView.url?.absoluteString ?? "-"))")

    // ── page scripts ──────────────────────────────────────────────────────────────────────────
    _ = try await window.load("\(site.origin)/index.html")
    let navigation = try await window.run("readNavigation", [])
    check(navigation["source"] == .string("none"), "readNavigation läuft in der eigenen Welt: \(JSJSON.compact(navigation))")
  } catch {
    check(false, "Lauf abgebrochen: \(error)")
  }
  window.close()

  // ── a throw in a page script, a page that does not finish, a cancel ──────────────────────────
  do {
    let throwing = ExportWindow(origin: site.origin, size: CGSize(width: 400, height: 300), pageScripts: scripts)
    try await throwing.prepare()
    _ = try await throwing.load(site.origin + site.copy.setDocument("leer.html", "<!doctype html><p>ohne Artikel</p>"))
    do {
      _ = try await throwing.run("extractArticle", [.object(JSONObject([("slug", .string("leer"))]))], helpers: ["slugFromPathname", "anchorFor", "outsideUrl"])
      check(false, "extractArticle ohne <article> wirft")
    } catch let failure as ExportWindow.ScriptFailure {
      check(failure.description == "no <article> on leer", "ein Wurf im Seitenskript kommt mit seinem Satz: \(failure.description)")
    }
    throwing.close()

    let hang = HangingServer().start()
    let late = ExportWindow(origin: site.origin, size: CGSize(width: 400, height: 300), pageScripts: scripts, loadTimeout: .seconds(2))
    try await late.prepare()
    _ = site.copy.setDocument("late.html", "<!doctype html><img src=\"http://127.0.0.1:\(hang.port)/never.png\">")
    let started = ContinuousClock.now
    let finished = try await late.load(site.origin + "/__quartzcontrol/late.html")
    let took = ContinuousClock.now - started
    check(!finished && late.unfinished == [site.origin + "/__quartzcontrol/late.html"] && took < .seconds(4),
          "eine Seite, die nicht fertig wird, steht nach der Frist (\(took), \(late.unfinished))")
    var stoppedAfter: Duration? = nil
    for step in 0..<20 where stoppedAfter == nil {
      if !late.webView.isLoading { stoppedAfter = .milliseconds(step * 50) } else { try await Task.sleep(for: .milliseconds(50)) }
    }
    check(stoppedAfter != nil, "und ihr Laden ist angehalten (nach \(stoppedAfter.map { "\($0)" } ?? "über 1 s"))")
    let cancelled = Task { @MainActor in try await late.load(site.origin + "/__quartzcontrol/late.html") }
    try await Task.sleep(for: .milliseconds(300))
    let cancelAt = ContinuousClock.now
    cancelled.cancel()
    let outcome = await cancelled.result
    let afterCancel = ContinuousClock.now - cancelAt
    if case .failure(let error) = outcome {
      check(error is CancellationError && afterCancel < .seconds(1), "ein Abbruch beendet das Laden sofort (\(afterCancel))")
    } else {
      check(false, "ein Abbruch beendet das Laden")
    }
    late.close()
    do {
      _ = try await late.evaluate("return 1")
      check(false, "ein geschlossenes Fenster nimmt nichts mehr an")
    } catch {
      check(error is CancellationError, "ein geschlossenes Fenster nimmt nichts mehr an")
    }
    hang.stop()
  } catch {
    check(false, "Lauf abgebrochen: \(error)")
  }
  print(failures == 0 ? "export-window: alles wie die Regel" : "export-window: \(failures) Abweichungen")
  return failures == 0 ? 0 : 1
}

private func write(_ path: String, _ text: String) throws {
  try Posix.mkdirs(NodePath.dirname(path))
  let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
  guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  defer { close(fd) }
  let bytes = Array(text.utf8)
  guard bytes.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == bytes.count else { throw POSIXError(.EIO) }
}

/// A server that accepts and never answers: a picture from it holds a page's load event.
final class HangingServer: @unchecked Sendable {
  let fd: Int32
  let port: UInt16
  private var held: [Int32] = []
  private let lock = NSLock()

  init() {
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(sock, 16)
    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &length) } }
    fd = sock
    port = UInt16(bigEndian: bound.sin_port)
  }

  /// Accepts on a thread of its own and holds every connection open.
  func start() -> HangingServer {
    let socket = fd
    Thread.detachNewThread { [self] in
      while true {
        let connection = accept(socket, nil, nil)
        guard connection >= 0 else { return }
        lock.withLock { held.append(connection) }
      }
    }
    return self
  }

  func stop() {
    close(fd)
    lock.withLock { for c in held { close(c) } }
  }
}
