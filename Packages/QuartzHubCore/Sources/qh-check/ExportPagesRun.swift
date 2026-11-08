import AppKit
import Foundation
import QuartzHubCore

/// `qh-check export-pages <build> <chrome.json> [--out <webkit.json>]`: the export's page scripts in
/// WebKit on the build `scripts/export-pages-golden.mjs` ran them on in Chrome, with the same
/// arguments, compared step by step - the start page's navigation, each page's settlePage and
/// extractArticle, then epubChapters over the collected pages. Nothing goes to the network (both
/// sides refuse everything from outside; for Mermaid and KaTeX see `scripts/cdn-build.mjs`). The
/// engine is what differs; the report says where. A Mermaid diagram is compared by structure
/// (`DiagramCompare`).
@MainActor
func runExportPagesCheck(root: String, build: String, golden: String, out: String?) async -> Int32 {
  let chrome: JSONValue
  let scripts: String
  do {
    chrome = try JSJSON.parse(try Data(contentsOf: URL(fileURLWithPath: golden))) // path boundary: a file the caller names
    scripts = try ExportWindow.pageScripts(location: RuntimeLocation(node: "", git: "", helpers: "\(root)/Helpers/dist"))
  } catch {
    print("Aufnahme oder page-scripts.js nicht lesbar: \(error)")
    return 2
  }
  let server: SiteServer
  do {
    server = try await SiteServer.start(try SiteCopy.make(from: build))
  } catch {
    print("Build nicht ausgeliefert: \(error)")
    return 2
  }
  defer { server.close() }
  let window = ExportWindow(origin: server.origin, size: CGSize(width: 658, height: 1000), pageScripts: scripts, outside: false)
  defer { window.close() }
  let theirs = chrome["origin"]!.stringValue!
  /// Chrome's answer with its origin written as this run's.
  func mine(_ value: JSONValue) -> JSONValue {
    (try? JSJSON.parse(JSJSON.compact(value).replacingOccurrences(of: theirs, with: server.origin))) ?? value
  }
  func outcome(_ work: () async throws -> JSONValue) async -> JSONValue {
    do { return .object(JSONObject([("ok", .bool(true)), ("value", try await work())])) } catch {
      return .object(JSONObject([("ok", .bool(false)), ("error", .string((error as? ExportWindow.ScriptFailure)?.description ?? "\(error)"))]))
    }
  }

  var record = JSONObject([("engine", .string("webkit")), ("origin", .string(server.origin))])
  var differences: [String] = []
  var same = 0
  // Pages and diagrams equal only in structure (`DiagramCompare`).
  var shapedPages = 0, shapedDiagrams = 0
  do {
    try await window.prepare()
    try await window.load("\(server.origin)/index")
    let homeSettled = await outcome { try await window.run("settlePage", [.object(JSONObject([("navigation", .bool(true)), ("timeoutMs", .number(15000))]))]) }
    let navigation = await outcome { try await window.run("readNavigation", []) }
    record["homeSettled"] = homeSettled
    record["navigation"] = navigation
    if navigation != mine(chrome["navigation"]!) { differences.append("Navigation der Startseite: \(JSJSON.compact(navigation).prefix(300))") }
    if homeSettled != chrome["homeSettled"]! { differences.append("settlePage der Startseite: \(JSJSON.compact(homeSettled)) statt \(JSJSON.compact(chrome["homeSettled"]!))") }

    var pages: [JSONValue] = []
    for page in chrome["pages"]!.arrayValue! {
      let slug = page["slug"]!.stringValue!
      _ = try await window.load("\(server.origin)/\(slug)")
      let settled = await outcome { try await window.run("settlePage", [.object(JSONObject([("navigation", .bool(false)), ("timeoutMs", .number(15000))]))]) }
      let extracted = await outcome { try await window.run("extractArticle", [page["args"]!], helpers: ["slugFromPathname", "anchorFor", "outsideUrl"]) }
      pages.append(.object(JSONObject([("slug", .string(slug)), ("settled", settled), ("extracted", extracted)])))
      let expected = mine(page["extracted"]!)
      if extracted == expected && settled == page["settled"]! { same += 1; continue }
      if settled == page["settled"]!, extracted["ok"] == expected["ok"],
         ["title", "lang", "images", "counts"].allSatisfy({ extracted["value"]?[$0] == expected["value"]?[$0] }),
         let a = extracted["value"]?["html"]?.stringValue, let b = expected["value"]?["html"]?.stringValue {
        switch DiagramCompare.compare(a, b) {
        case .equal: same += 1; continue
        case .sameShape(let n): same += 1; shapedPages += 1; shapedDiagrams += n; continue
        case .different: break
        }
      }
      if settled != page["settled"]! { differences.append("\(slug): settlePage \(JSJSON.compact(settled)) statt \(JSJSON.compact(page["settled"]!))") }
      for key in ["title", "lang", "images", "counts", "html"] where extracted["value"]?[key] != expected["value"]?[key] {
        if key == "html", let a = extracted["value"]?["html"]?.stringValue, let b = expected["value"]?["html"]?.stringValue,
           let where_ = DiagramCompare.locate(a, b) {
          differences.append("\(slug): html \(where_)")
          continue
        }
        let a = JSJSON.compact(extracted["value"]?[key] ?? .null), b = JSJSON.compact(expected["value"]?[key] ?? .null)
        let at = zip(a, b).prefix { $0 == $1 }.count
        differences.append("\(slug): \(key) weicht ab bei Zeichen \(at): WebKit …\(a.dropFirst(max(0, at - 60)).prefix(160))… Chrome …\(b.dropFirst(max(0, at - 60)).prefix(160))…")
      }
      if extracted["ok"] != expected["ok"] { differences.append("\(slug): \(JSJSON.compact(extracted).prefix(200))") }
    }
    record["pages"] = .array(pages)

    // epubChapters over WebKit's own pages, in a page of the copy.
    var inputs: [JSONValue] = []
    for (i, page) in pages.enumerated() where page["extracted"]?["ok"] == .bool(true) {
      let value = page["extracted"]!["value"]!
      let slug = page["slug"]!.stringValue!
      let args = chrome["pages"]!.arrayValue![i]["args"]!
      inputs.append(.object(JSONObject([
        ("file", .string(String(format: "text/c%04d.xhtml", inputs.count + 1))), ("slug", .string(slug)), ("anchor", .string(ExportModel.anchor(slug))),
        ("level", args["level"]!), ("title", value["title"]!), ("html", value["html"]!)
      ])))
    }
    _ = try await window.load(server.origin + server.copy.setDocument("epub.html", "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>"))
    let chapters = await outcome {
      try await window.run("epubChapters", [.object(JSONObject([
        ("chapters", .array(inputs)), ("imageNames", .object(JSONObject())), ("imageExtensions", .array(["png", "jpg", "jpeg", "gif", "svg", "webp"].map(JSONValue.string))),
        ("formulaAlt", .string("@@formula@@")), ("diagramAlt", .string("@@diagram@@"))
      ]))])
    }
    record["chapters"] = chapters
    let expectedChapters = mine(chrome["chapters"]!)
    let ours = chapters["value"]?["chapters"]?.arrayValue ?? [], theirsChapters = expectedChapters["value"]?["chapters"]?.arrayValue ?? []
    var sameChapters = 0
    for (a, b) in zip(ours, theirsChapters) {
      if a == b { sameChapters += 1; continue }
      for key in ["body", "images", "hasMath", "hasSvg", "parseError"] where a[key] != b[key] {
        let x = JSJSON.compact(a[key] ?? .null), y = JSJSON.compact(b[key] ?? .null)
        let at = zip(x, y).prefix { $0 == $1 }.count
        differences.append("Kapitel \(a["file"]!.stringValue!): \(key) bei \(at): WebKit …\(x.dropFirst(max(0, at - 60)).prefix(160))… Chrome …\(y.dropFirst(max(0, at - 60)).prefix(160))…")
      }
    }
    if ours.count != theirsChapters.count { differences.append("Kapitel: \(ours.count) statt \(theirsChapters.count)") }
    // The drawings (formulas and diagrams the ePub takes as pictures) by name, a diagram by structure.
    let drawings = chapters["value"]?["drawings"]?.arrayValue ?? [], theirDrawings = expectedChapters["value"]?["drawings"]?.arrayValue ?? []
    var shapedDrawings = 0
    if drawings.count != theirDrawings.count { differences.append("Zeichnungen: \(drawings.count) statt \(theirDrawings.count)") }
    for (a, b) in zip(drawings, theirDrawings) where a != b {
      let name = a["name"]?.stringValue ?? "?"
      guard a["name"] == b["name"], let x = a["html"]?.stringValue, let y = b["html"]?.stringValue else {
        differences.append("Zeichnung \(name) statt \(b["name"]?.stringValue ?? "?")")
        continue
      }
      switch DiagramCompare.compare(x, y) {
      case .equal: continue
      case .sameShape: shapedDrawings += 1
      case .different: differences.append("Zeichnung \(name): \(DiagramCompare.locate(x, y) ?? "weicht ab")")
      }
    }
    if chapters["value"]?["counts"] != expectedChapters["value"]?["counts"] {
      differences.append("epubChapters counts: WebKit \(JSJSON.compact(chapters["value"]?["counts"] ?? .null)) Chrome \(JSJSON.compact(expectedChapters["value"]?["counts"] ?? .null))")
    }
    print("Seiten gleich: \(same) von \(pages.count); Kapitel gleich: \(sameChapters) von \(theirsChapters.count); Zeichnungen: \(drawings.count)")
    if shapedPages + shapedDrawings > 0 {
      print("Mermaid-Diagramme nur im Aufbau gleich (Elemente, Text; die Geometrie misst jede Engine selbst): \(shapedDiagrams) auf \(shapedPages) Seiten, \(shapedDrawings) Zeichnungen")
    }
  } catch {
    print("Lauf abgebrochen: \(error)")
    return 3
  }
  if let out {
    try? JSJSON.stringify(.object(record)).write(toFile: out, atomically: true, encoding: .utf8) // path boundary: a file the caller names
  }
  for line in differences { print("ABWEICHUNG  \(line)") }
  print(differences.isEmpty ? "export-pages: WebKit wie Chrome" : "export-pages: \(differences.count) Abweichungen")
  return differences.isEmpty ? 0 : 1
}
