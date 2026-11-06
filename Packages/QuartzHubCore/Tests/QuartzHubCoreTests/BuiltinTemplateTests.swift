import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own builtinTemplateService.ts: `scripts/builtin-template-golden.mjs`
/// ran 25 situations (cache missing, fresh, a day old, torn; answers offline, 404, a captive portal,
/// a ZIP without a manifest, empty, 25 MB and one byte more; the copy missing, damaged, undated)
/// and recorded the answer, the requests and the cache afterwards.
@Suite(.serialized) struct BuiltinTemplateTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/builtin-template")

  @Test func findsAsQuartzControl() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let work = TemplatePackageTests.realpath(scratch.path)
    var packages: [String: Data] = ["bundled": try Posix.read(BuiltinTemplate.bundledCopy)]
    let stored = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("packages.json"))).objectValue!
    for name in stored.keys { packages[name] = Data(base64Encoded: stored[name]!.stringValue!)! }
    // Exactly the ceiling and one byte more, as the golden builds them.
    func sized(_ target: Int) throws -> Data {
      let manifest = Data(#"{"formatVersion":1,"name":"Groß","createdAt":"2026-12-02T00:00:00.000Z"}"#.utf8)
      let make = { (n: Int) in try ZipArchive.create([ZipArchive.Entry(name: "manifest.json", data: manifest, store: true),
                                                      ZipArchive.Entry(name: "filler.bin", data: Data(repeating: 7, count: n), store: true)]) }
      return try make(target - make(0).count)
    }
    packages["atCeiling"] = try sized(25 * 1024 * 1024)
    packages["overCeiling"] = try sized(25 * 1024 * 1024 + 1)
    let served = packages
    let profile = ProfileDirectory("\(work)/userData")
    let bundled = "\(work)/resources/templates/qc-basic.qtpl"
    let cache = "\(profile.path)/templates/qc-basic.qtpl"
    let now = Date()

    struct Net { var requests: [String] = []; var answer: JSONValue = .null }
    let net = Mutex(Net())
    let fetch: FontService.Fetch = { url, _, _ throws(FontService.FetchFailure) in
      let answer = net.withLock { state in
        state.requests.append(url)
        return state.answer
      }
      guard case .object = answer, answer["fail"] != .bool(true) else { throw .unreachable }
      let body = answer["package"]?.stringValue.map { served[$0]! } ?? Data(base64Encoded: answer["base64"]?.stringValue ?? "")!
      return FontService.Response(status: Int(answer["status"]?.numberValue ?? 200), headers: [:], body: body)
    }
    let template = BuiltinTemplate(profile: profile, bundled: bundled, fetch: fetch, now: { now })

    func set(_ url: String, _ name: JSONValue?, ageHours: Double) throws {
      guard let name = name?.stringValue else {
        try? FileManager.default.removeItem(atPath: url)
        return
      }
      try Posix.mkdirs(NodePath.dirname(url))
      try Posix.write(url, packages[name]!)
      try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ageHours * 3600)], ofItemAtPath: url)
    }
    func which(_ data: Data) -> String {
      packages.first { $0.value == data }?.key ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    let steps = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps.json"))).arrayValue ?? []
    #expect(steps.count == 25)
    for step in steps {
      let name = step["name"]!.stringValue!
      let setup = step["setup"]!
      try set(bundled, setup["bundled"], ageHours: 0)
      try set(cache, setup["cached"], ageHours: setup["ageHours"]?.numberValue ?? 0)
      net.withLock { $0 = Net(answer: setup["answer"] ?? .null) }
      let found = await template.find()
      let got: JSONValue = found.map { found in
        .object(JSONObject([("path", .string(found.path.replacingOccurrences(of: work, with: "@W@", options: .literal))), ("source", .string(found.source.rawValue)),
                            ("pages", .number(Double(found.pages)))]))
      } ?? .null
      #expect(got == step["result"], "\(name): \(JSJSON.compact(got))")
      #expect(JSONValue.array(net.withLock { $0.requests }.map(JSONValue.string)) == step["requests"], "\(name): Anfragen")
      let after: JSONValue = FileManager.default.fileExists(atPath: cache) ? .string(which(try Posix.read(cache))) : .null
      #expect(after == step["cacheAfter"], "\(name): Cache \(after)")
      let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: NodePath.dirname(cache))) ?? []).filter { $0 != "qc-basic.qtpl" }
      #expect(leftovers.isEmpty, "\(name): \(leftovers)")
    }
  }

  @Test func theCopyInTheRepositoryIsQuartzControls() throws {
    let files = try ZipArchive.read(contentsOf: BuiltinTemplate.bundledCopy)
    #expect(files[TemplatePackage.manifestFile] != nil)
    #expect(BuiltinTemplate.countPages(files[TemplatePackage.partFile("content")]) == 22)
  }
}
