import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own shared/remotePath.ts (`scripts/remote-path-golden.mjs`): 437 calls,
/// each with its arguments and answer, compared by UTF-8 bytes.
@Suite struct RemotePathTests {
  static let cases: [JSONValue] = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/remote-path/cases.json"))).arrayValue!

  static func bytes(_ value: JSONValue) -> [UInt8]? { value.stringValue.map { Array($0.utf8) } }

  @Test func answersAsQuartzControl() {
    #expect(Self.cases.count == 437)
    for item in Self.cases {
      let args = item["args"]!.arrayValue!
      let text = args[0].stringValue!
      let actual: JSONValue
      switch item["fn"]!.stringValue! {
      case "remotePathProblem":
        actual = RemotePath.problem(text, deleteRemoved: args[1].boolValue!).map { .string($0.rawValue) } ?? .null
      case "rsyncUnsafeChar": actual = RemotePath.rsyncUnsafeChar(text).map(JSONValue.string) ?? .null
      case "relaySubdir": actual = RemotePath.relaySubdir(text).map(JSONValue.string) ?? .null
      case "fromLoginDir":
        actual = RemotePath.fromLoginDir(text, loginDir: args[1].stringValue!, account: args[2].stringValue!).map(JSONValue.string) ?? .null
      default:
        Issue.record("unknown fn"); continue
      }
      let expected = item["result"]!
      #expect(Self.bytes(actual) == Self.bytes(expected) && (actual == .null) == (expected == .null),
              "\(item["fn"]!.stringValue!)(\(JSJSON.compact(.array(args)))): \(JSJSON.compact(actual)) vs \(JSJSON.compact(expected))")
    }
  }
}
