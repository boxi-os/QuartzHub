import CryptoKit
import Foundation
import Testing
@testable import QuartzHubCore

/// The export window's page scripts are QuartzControl's files, unchanged (Helpers/src/export/):
/// the sha256 of each copy against the one `scripts/page-scripts-golden.mjs` took of QuartzControl's.
@Suite struct PageScriptsTests {
  static let helpers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Helpers").path

  @Test func copiesAreQuartzControls() throws {
    let golden = try JSJSON.parse(Posix.read("\(Self.helpers)/../Packages/QuartzHubCore/Tests/QuartzHubCoreTests/Fixtures/page-scripts/sources.json"))
    for name in ["pageScripts.ts", "exportModel.ts"] {
      let digest = SHA256.hash(data: try Posix.read("\(Self.helpers)/src/export/\(name)")).map { String(format: "%02x", $0) }.joined()
      #expect(.string(digest) == golden[name], "\(name)")
    }
  }
}
