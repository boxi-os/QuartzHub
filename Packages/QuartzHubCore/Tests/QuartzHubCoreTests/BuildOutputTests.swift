import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own `getBuildOutput` (buildService.ts): `scripts/build-last-output-golden.mjs`
/// laid out each case under a fresh folder W, set the times it wrote into the fixture, and recorded
/// the answer. The same tree, the same times, the same answer, with W in a folder named "Gärten-Ü".
@Suite struct BuildOutputTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/build-output/last-output.json")

  static func workspace() throws -> String {
    let made = FileManager.default.temporaryDirectory.appendingPathComponent("qh-last-output-\(UUID().uuidString)/Gärten-Ü")
    try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
    return Posix.path(made)
  }

  /// `utimesSync(path, ms / 1000, ms / 1000)`.
  static func setTime(_ path: String, milliseconds: Double) {
    let seconds = (milliseconds / 1000).rounded(.down)
    let nanoseconds = Int(((milliseconds / 1000 - seconds) * 1_000_000_000).rounded())
    let time = timespec(tv_sec: Int(seconds), tv_nsec: nanoseconds)
    _ = [time, time].withUnsafeBufferPointer { utimensat(AT_FDCWD, path, $0.baseAddress, 0) }
  }

  static func expected(_ json: JSONValue, _ w: String) -> BuildOutput.Info? {
    if json["rejected"] != nil { return nil }
    return BuildOutput.Info(
      dir: json["dir"]!.stringValue!.replacingOccurrences(of: "@W@", with: w, options: .literal),
      exists: json["exists"]!.boolValue!, builtAt: json["builtAt"]?.stringValue,
      fileCount: Int(json["fileCount"]!.numberValue!), sizeBytes: Int(json["sizeBytes"]!.numberValue!),
      looksLikeBuild: json["looksLikeBuild"]!.boolValue!)
  }

  @Test func sameAsQuartzControl() throws {
    let cases = try #require(JSJSON.parse(Data(contentsOf: Self.fixture)).arrayValue)
    #expect(cases.count == 15, "scripts/build-last-output-golden.mjs")
    for item in cases {
      let name = item["name"]!.stringValue!
      let w = try Self.workspace()
      let tree = item["tree"]!
      let fill = { (text: String) in text.replacingOccurrences(of: "@W@", with: w, options: .literal) }
      try ProjectDuplicatorTests.layOut(tree, at: w, fill)
      let times = item["times"]!.objectValue!
      for path in times.keys.sorted(by: { $0.split(separator: "/").count > $1.split(separator: "/").count })
      where tree[path]?["dir"]?.numberValue != 0 {
        Self.setTime("\(w)/\(path)", milliseconds: times[path]!.numberValue!)
      }

      var answer: BuildOutput.Info?
      var rejected = false
      do {
        answer = try BuildOutput.info(project: "\(w)/proj", outputDir: item["outputDir"]?.stringValue.map(fill))
      } catch {
        rejected = true
      }
      BuildOutputGuardTests.cleanUp(URL(fileURLWithPath: w), tree) // path boundary

      if let quartzControl = Self.expected(item["expected"]!, w) {
        #expect(answer == quartzControl, "\(name)")
      } else {
        #expect(rejected, "\(name): QuartzControl rejected")
      }
    }
  }

  /// Gegenprobe: a file written after the walk's newest moves `builtAt`, and the count with it.
  @Test func aNewerFileIsTheBuildTime() throws {
    let w = try Self.workspace()
    defer { try? FileManager.default.removeItem(atPath: w) }
    try Posix.mkdirs("\(w)/proj/public")
    try Posix.write("\(w)/proj/public/index.html", Data("a".utf8))
    Self.setTime("\(w)/proj/public/index.html", milliseconds: 1_600_000_000_000)
    let before = try BuildOutput.info(project: "\(w)/proj")
    try Posix.write("\(w)/proj/public/neu.html", Data("bb".utf8))
    Self.setTime("\(w)/proj/public/neu.html", milliseconds: 1_700_000_000_500)
    let after = try BuildOutput.info(project: "\(w)/proj")
    #expect(before.builtAt == "2020-09-13T12:26:40.000Z")
    #expect(after.builtAt == "2023-11-14T22:13:20.500Z")
    #expect(after.builtDate == Date(timeIntervalSince1970: 1_700_000_000.5))
    #expect((before.fileCount, before.sizeBytes) == (1, 1))
    #expect((after.fileCount, after.sizeBytes) == (2, 3))
  }
}
