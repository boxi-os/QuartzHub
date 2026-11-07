import Foundation
import Testing
@testable import QuartzHubCore

/// ExportWindow's rule against QuartzControl's exportWindow.ts (`scripts/export-window-golden.mjs`):
/// 46 requests by address and Chromium's type, whether each passes, what is counted under which
/// host, and 16 navigations of the main frame. Without WebKit: whether the window holds to it is
/// measured through `qh-check export-window`.
///
/// Two requests of the golden are none in a browser and left out here, said so: `about:blank` as a
/// frame (QuartzControl's handler counted what Chromium never asks for; QuartzHub counts no
/// about:), and a host in Unicode (QuartzHub reads addresses as WebKit wrote them, in Punycode).
@Suite struct ExportWindowRuleTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/export-window/rule.json")))
  static let notRequests = ["about:blank", "https://gärten.example/p.png"]

  @Test func decidesAndCountsAsQuartzControl() {
    let origin = Self.golden["origin"]!.stringValue!
    let decisions = Self.golden["decisions"]!.arrayValue!
    #expect(decisions.count == 46)
    var refused: [(String, Int)] = [], fetched: [(String, Int)] = []
    func add(_ list: inout [(String, Int)], _ key: String) {
      if let i = list.firstIndex(where: { $0.0 == key }) { list[i].1 += 1 } else { list.append((key, 1)) }
    }
    for d in decisions {
      let url = d["url"]!.stringValue!, type = d["resourceType"]!.stringValue!
      guard !Self.notRequests.contains(url) else { continue }
      let passes = ExportWindow.passes(url, origin: origin) || JSText.startsWith(url, "devtools:")
      let allowed = passes || ExportWindow.allowedFromOutside(url, type: type)
      #expect(allowed == !d["cancel"]!.boolValue!, "\(type) \(url)")
      if passes { continue }
      if allowed { add(&fetched, ExportWindow.host(url)) } else { add(&refused, "\(type) \(ExportWindow.host(url))") }
    }
    let expectedRefused = Self.golden["refused"]!.arrayValue!.map { ($0.arrayValue![0].stringValue!, Int($0.arrayValue![1].numberValue!)) }
      .filter { $0.0 != "subFrame (about)" }
    let expectedFetched = Self.golden["fetched"]!.arrayValue!.map { ($0.arrayValue![0].stringValue!, Int($0.arrayValue![1].numberValue!)) }
      .map { $0.0 == "xn--grten-gra.example" ? ($0.0, $0.1 - 1) : $0 }
    #expect(refused.map { "\($0.0)=\($0.1)" } == expectedRefused.map { "\($0.0)=\($0.1)" }, "\(refused)\n\(expectedRefused)")
    #expect(fetched.map { "\($0.0)=\($0.1)" } == expectedFetched.map { "\($0.0)=\($0.1)" })
  }

  @Test func navigatesAsQuartzControl() {
    let origin = Self.golden["origin"]!.stringValue!
    for n in Self.golden["navigations"]!.arrayValue! {
      let url = n["url"]!.stringValue!
      #expect(ExportWindow.mayNavigate(url, origin: origin) == !n["prevented"]!.boolValue!, "\(n["event"]!) \(url)")
    }
    #expect(Self.golden["windowOpen"]!["action"] == .string("deny") && Self.golden["permissionGranted"] == .bool(false))
  }
}
