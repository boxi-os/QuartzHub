import AppKit
import Foundation
import QuartzHubCore
import WebKit

/// `qh-check inline-svg [projekt]`: the sanitizer's results in WebKit, as HTML and (with a project
/// that has quartz-layout-box) through its Markdown chain. Runs without an app: a WKWebView needs
/// only the main run loop (measured 2026-11-06: loads, runs JavaScript, an `onerror` fired).
@MainActor
final class InlineSvgRun: NSObject, WKNavigationDelegate {
  private var webView: WKWebView!
  private var loaded: CheckedContinuation<Void, Never>?
  private var initialLoad = true
  private var navigated = false

  /// One fresh page per rendering, as QuartzControl's check opened one per page.
  func render(_ markup: String) async -> InlineSvgCheck.Rendering {
    webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: WKWebViewConfiguration())
    webView.navigationDelegate = self
    initialLoad = true
    navigated = false
    await load(InlineSvgCheck.page(markup))
    try? await Task.sleep(for: .milliseconds(150))
    let findings = (try? await evaluate(InlineSvgCheck.findingsScript) as? [String]) ?? ["die Seite antwortet nicht"]
    let before = (try? await evaluate(InlineSvgCheck.ranScript) as? Int) ?? 0
    let fromOutside = (try? await evaluate(InlineSvgCheck.loadedScript) as? [String]) ?? []
    let animated = try? await evaluate(InlineSvgCheck.animatedScript) as? String
    _ = try? await evaluate(InlineSvgCheck.clickScript)
    try? await Task.sleep(for: .milliseconds(150))
    let after = (try? await evaluate(InlineSvgCheck.ranScript) as? Int) ?? before
    return InlineSvgCheck.Rendering(findings: findings, ranOnLoad: before, ranOnClick: after - before, navigated: navigated, loaded: fromOutside, animatedTo: animated)
  }

  /// Loads a page and waits for it, at most 10 s: a page that never finishes is a finding of its
  /// own (its scripts then answer nothing), not a check that hangs.
  func load(_ html: String) async {
    await withCheckedContinuation { continuation in
      loaded = continuation
      webView.loadHTMLString(html, baseURL: nil)
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
        MainActor.assumeIsolated {
          self?.loaded?.resume()
          self?.loaded = nil
        }
      }
    }
  }

  func evaluate(_ body: String) async throws -> Any? {
    return try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
  }

  /// A page with the markup, then one script; for the cases that must get through.
  func ask(_ markup: String, _ body: String, wrapped: Bool = true) async -> [String: Any] {
    webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: WKWebViewConfiguration())
    webView.navigationDelegate = self
    initialLoad = true
    await load(wrapped ? InlineSvgCheck.page(markup) : "<!doctype html><title>s</title><body>\(markup)</body>")
    return ((try? await evaluate(body)) as? [String: Any]) ?? [:]
  }

  nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    MainActor.assumeIsolated {
      loaded?.resume()
      loaded = nil
    }
  }

  /// Nothing leaves the page: the first load passes, every later main-frame navigation is noted and
  /// cancelled (a `mailto:` would open the mail program otherwise; a jump to `#` is no navigation).
  nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
    MainActor.assumeIsolated {
      if initialLoad {
        initialLoad = false
        decisionHandler(.allow)
        return
      }
      // A link that leaves to http(s), mailto, tel or ftp is one the sanitizer allows (or remark-gfm
      // makes out of "www.…" and "a@b" in any snippet); QuartzControl's check let those through
      // with preventDefault. Everything is cancelled; only another scheme counts.
      let url = (action.request.url?.absoluteString ?? "").lowercased()
      let stripped = url.components(separatedBy: "#")[0]
      let allowed = ["about:blank", "http:", "https:", "mailto:", "tel:", "ftp:"].contains { stripped.hasPrefix($0) }
      if action.targetFrame?.isMainFrame != false && !allowed && !stripped.isEmpty { navigated = true }
      decisionHandler(.cancel)
    }
  }
}

/// The Markdown chain of the project's quartz-layout-box, through scripts/lib/layout-box-markdown.mjs.
func layoutBoxMarkdown(project: String?, root: URL, inputs: [String]) -> (outputs: [String]?, chain: String) {
  guard let project else { return (nil, "nicht geprüft: kein Projekt genannt") }
  let node = root.appendingPathComponent("Runtime/node/bin/node").path
  let script = root.appendingPathComponent("scripts/lib/layout-box-markdown.mjs").path
  let process = Process()
  process.executableURL = URL(fileURLWithPath: node)
  process.arguments = [script]
  let input = Pipe(), output = Pipe()
  process.standardInput = input
  process.standardOutput = output
  do { try process.run() } catch { return (nil, "nicht geprüft: \(node) startet nicht") }
  let request = JSONObject([("project", .string(URL(fileURLWithPath: project).standardizedFileURL.path)), ("inputs", .array(inputs.map { .string($0) }))])
  input.fileHandleForWriting.write(Data(JSJSON.compact(.object(request)).utf8))
  try? input.fileHandleForWriting.close()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard let answer = try? JSJSON.parse(data) else { return (nil, "nicht geprüft: die Kette antwortete nicht") }
  if let error = answer["error"]?.stringValue { return (nil, "nicht geprüft: \(error)") }
  let outputs = (answer["outputs"]?.arrayValue ?? []).compactMap(\.stringValue)
  return (outputs, "aus quartz-layout-box \(answer["version"]?.stringValue ?? "?") (\(URL(fileURLWithPath: project).lastPathComponent))")
}

@MainActor
func runInlineSvgCheck(project: String?, root: URL) async -> Int32 {
  let run = InlineSvgRun()
  var failures = 0
  func check(_ ok: Bool, _ sentence: String) {
    print("\(ok ? "✓" : "✗") \(sentence)")
    if !ok { failures += 1 }
  }
  // Every harmful result, then all of them through the Markdown chain in one call.
  let cleaned = InlineSvgCheck.harmful.map { InlineSvg.clean($0.input, fileName: "test-icon.svg") }
  let inputs = cleaned.flatMap { result in result.map { markup in InlineSvgCheck.markdownLayers.map { $0.wrap(markup.markup) } } ?? [] }
  let (rendered, chain) = layoutBoxMarkdown(project: project, root: root, inputs: inputs)
  print("Markdown-Kette: \(chain)")
  var skipped = 0
  var next = 0
  for (harmful, result) in zip(InlineSvgCheck.harmful, cleaned) {
    guard let result else {
      check(true, "\(harmful.name): abgelehnt")
      continue
    }
    var layers = [("HTML", result.markup)]
    if let rendered {
      for (index, layer) in InlineSvgCheck.markdownLayers.enumerated() { layers.append((layer.name, rendered[next + index])) }
      next += InlineSvgCheck.markdownLayers.count
    } else {
      skipped += InlineSvgCheck.markdownLayers.count
    }
    var problems: [String] = []
    for (layer, html) in layers {
      let found = await run.render(html).problems
      if !found.isEmpty { problems.append("\(layer): \(found.joined(separator: ", "))") }
    }
    if harmful.counts && result.removed == 0 { problems.append("„0 entfernt“ gemeldet") }
    check(problems.isEmpty, "\(harmful.name): \(problems.isEmpty ? "\(result.removed) entfernt, auf der Seite nichts" : problems.joined(separator: "; "))")
  }

  // What must get through.
  if let icon = InlineSvg.clean(InlineSvgCheck.ordinaryIcon, fileName: "Mein Logo.svg") {
    check(icon.removed == 0, "ein gewöhnliches Icon: \(icon.removed) entfernt")
    let info = await run.ask(icon.markup, InlineSvgCheck.ordinaryScript)
    check(info["cls"] as? String == "eigen svg-mein-logo", "die Wurzel trägt ihre Klasse und svg-mein-logo (\(info["cls"] ?? "nichts"))")
    check((info["viewBox"] as? Int) == 24 || (info["viewBox"] as? Double) == 24, "viewBox wird gelesen")
    let uses = info["uses"] as? [String] ?? []
    check(uses.count == 2 && uses.allSatisfy { $0 == "symbol" }, "<use> auf ein Symbol der Datei bleibt (\(uses.joined(separator: ", ")))")
    check(info["title"] as? String == "Logo & Name", "Text bleibt Text (\(info["title"] ?? "nichts"))")
    let style = info["style"] as? String ?? ""
    check(info["gradient"] as? Bool == true && style.range(of: #"url\(#[\w-]*-g\)"#, options: .regularExpression) != nil, "Verläufe und url(#…) bleiben")
    check(info["animate"] as? String == "opacity", "eine Animation auf etwas anderes als einen Verweis bleibt")
    check(info["link"] as? String == "https://example.com/", "ein Link nach https bleibt")
    check(info["blank"] as? Bool == false, "keine Leerzeile, die einen Markdown-Block beendet")
  } else {
    check(false, "ein gewöhnliches Icon: abgelehnt")
  }
  let illustrator = InlineSvg.clean(InlineSvgCheck.illustrator, fileName: "test-icon.svg")
  check(illustrator?.removed == 1 && illustrator?.styled == true, "ein <style> aus Illustrator wird als solcher gemeldet (\(illustrator?.removed ?? -1) entfernt)")
  let script = InlineSvg.clean(InlineSvgCheck.harmful[0].input, fileName: "test-icon.svg")
  check(script?.styled == false, "ohne <style> kein Satz über Farben")
  if let red = InlineSvg.clean(InlineSvgCheck.sameIds("red"), fileName: "rot.svg"), let blue = InlineSvg.clean(InlineSvgCheck.sameIds("blue"), fileName: "blau.svg") {
    let ids = await run.ask(red.markup + blue.markup, InlineSvgCheck.idsScript)
    let twice = ids["twice"] as? [String] ?? ["?"], foreign = ids["foreign"] as? [String] ?? ["?"]
    check(twice.isEmpty && foreign.isEmpty, "zwei Dateien mit denselben Ids auf einer Seite: \(twice.count) doppelt, \(foreign.count) Verweise ins andere SVG")
  } else {
    check(false, "zwei Dateien mit denselben Ids: abgelehnt")
  }
  if let spellings = InlineSvg.clean(InlineSvgCheck.spellings, fileName: "formen.svg") {
    let targets = await run.ask(spellings.markup, InlineSvgCheck.spellingsScript, wrapped: false)
    let missed = targets.filter { ($0.value as? Bool) != true }.map(\.key).sorted()
    check(!targets.isEmpty && missed.isEmpty, "vier Schreibweisen eines Verweises zeigen nach dem Präfix auf ihr Ziel\(missed.isEmpty ? "" : " (daneben: \(missed.joined(separator: ", ")))")")
  } else {
    check(false, "vier Schreibweisen eines Verweises: abgelehnt")
  }
  check(InlineSvg.clean("<html/>", fileName: "x.svg") == nil && InlineSvg.clean("kein xml", fileName: "x.svg") == nil, "was kein SVG ist, wird abgelehnt")

  if skipped > 0 { print("\n\(skipped) Markdown-Lagen ausgelassen — \(chain).") }
  if failures > 0 {
    print("\n✗ \(failures) Prüfung(en) fehlgeschlagen")
    return 1
  }
  print(skipped > 0 ? "\n✓ alle Prüfungen bestanden, die laufen konnten" : "\n✓ alle Prüfungen bestanden")
  return skipped > 0 ? 3 : 0
}
