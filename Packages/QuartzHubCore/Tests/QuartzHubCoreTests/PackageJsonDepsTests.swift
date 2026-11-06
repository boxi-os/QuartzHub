import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own shared/packageJsonDeps.ts (`scripts/package-deps-golden.mjs`): 83
/// calls, each with its arguments and answer.
@Suite struct PackageJsonDepsTests {
  static let cases: [JSONValue] = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/package-deps/cases.json"))).arrayValue!

  static func read(_ value: JSONValue) -> PackageJsonDeps.Read {
    value["$unreadable"] == .bool(true) ? .unreadable : .parsed(value)
  }

  static func additions(_ value: JSONValue) -> [PackageJsonDeps.Addition] {
    value.arrayValue!.map { .init(name: $0["name"]!.stringValue!, section: .init(rawValue: $0["section"]!.stringValue!)!, range: $0["range"]!.stringValue!) }
  }

  static func json(_ entries: [PackageJsonDeps.Addition]) -> JSONValue {
    .array(entries.map { .object(JSONObject([("name", .string($0.name)), ("section", .string($0.section.rawValue)), ("range", .string($0.range))])) })
  }

  static func strings(_ items: [String]) -> JSONValue { .array(items.map(JSONValue.string)) }

  @Test func answersAsQuartzControl() {
    #expect(Self.cases.count == 83)
    for item in Self.cases {
      let args = item["args"]!.arrayValue!
      let actual: JSONValue
      switch item["fn"]!.stringValue! {
      case "localPackageChanges":
        let c = PackageJsonDeps.localPackageChanges(base: args[0], ours: args[1], theirs: args[2])
        actual = .object(JSONObject([("reinstall", Self.json(c.reinstall)), ("upstreamWins", Self.strings(c.upstreamWins)),
                                     ("unreproducible", Self.strings(c.unreproducible))]))
      case "reinstallCommands":
        actual = .array(PackageJsonDeps.reinstallCommands(Self.additions(args[0])).map { .object(JSONObject([("args", Self.strings($0))])) })
      case "missingFrom": actual = Self.json(PackageJsonDeps.missingFrom(Self.read(args[0]), Self.additions(args[1])))
      case "absentFrom": actual = Self.json(PackageJsonDeps.absentFrom(Self.read(args[0]), Self.additions(args[1])))
      case "outstandingPackages":
        actual = Self.strings(PackageJsonDeps.outstandingPackages(Self.read(args[0]), Self.additions(args[1]),
                                                                  putBack: args[2].arrayValue!.map { $0.stringValue! }))
      case "dependencyRange":
        actual = PackageJsonDeps.dependencyRange(args[0], .init(rawValue: args[1].stringValue!)!, args[2].stringValue!).map(JSONValue.string) ?? .null
      default:
        Issue.record("unknown fn"); continue
      }
      #expect(actual == item["result"], "\(item["name"]!.stringValue!): \(JSJSON.compact(actual)) vs \(JSJSON.compact(item["result"]!))")
    }
  }
}
