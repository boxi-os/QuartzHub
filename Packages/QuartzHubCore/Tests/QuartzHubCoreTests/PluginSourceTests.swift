import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's shared/quartzPluginName.ts: `scripts/option-schema-golden.mjs` wrote
/// what it answers for each source.
@Suite struct PluginSourceTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/option-schema/plugin-names.json")

  @Test func sameNameAsQuartzControl() throws {
    let cases = try JSJSON.parse(Data(contentsOf: Self.fixture)).arrayValue ?? []
    #expect(cases.count >= 40, "scripts/option-schema-golden.mjs")
    for entry in cases {
      let expected = entry["name"]?.stringValue
      // Built directly, not through init?: QuartzControl's function answers for sources its
      // channel would have refused ("", "-x", a name of ""), and so does this one.
      let name: String = switch entry["source"]! {
      case .string(let source): PluginSource.quartzName(source)
      case let source: PluginSource.object(repo: source["repo"]!.stringValue!, name: source["name"]?.stringValue).quartzName
      }
      #expect(name == expected, "\(JSJSON.stringify(entry["source"]!))")
    }
  }

  @Test func acceptsWhatTheChannelAccepted() {
    #expect(PluginSource(.string("github:a/b")) == .string("github:a/b"))
    #expect(PluginSource(.string(String(repeating: "a", count: 2048))) != nil)
    #expect(PluginSource(.object(JSONObject([("repo", .string("r")), ("name", .string("n")), ("other", .number(1))]))) == .object(repo: "r", name: "n"))
    #expect(PluginSource(.object(JSONObject([("repo", .string("r")), ("ref", .string("v1"))]))) == .object(repo: "r", name: nil))
    // Counter-checks: what zod refused.
    for refused: JSONValue? in [nil, .null, .number(1), .array([]), .string(""), .string("-x"),
                                .string(String(repeating: "a", count: 2049)),
                                .object(JSONObject()), .object(JSONObject([("repo", .string(""))])),
                                .object(JSONObject([("repo", .number(1))])),
                                .object(JSONObject([("repo", .string("r")), ("name", .string(""))])),
                                .object(JSONObject([("repo", .string("r")), ("name", .number(1))])),
                                .object(JSONObject([("repo", .string("r")), ("ref", .string(String(repeating: "a", count: 256)))])),
                                .object(JSONObject([("repo", .string("r")), ("subdir", .bool(true))]))] {
      #expect(PluginSource(refused) == nil, "\(String(describing: refused))")
    }
  }

  @Test func npmOrNot() {
    #expect(PluginSource.string("@quartz-community/explorer").isNpm)
    #expect(PluginSource.object(repo: "plain", name: "x").isNpm)
    for source in ["github:a/b", "git+https://h/b", "https://h/b", "/abs", "./rel", "../up", "C:\\x", "c:/x"] {
      #expect(!PluginSource.string(source).isNpm, "\(source)")
    }
  }
}
