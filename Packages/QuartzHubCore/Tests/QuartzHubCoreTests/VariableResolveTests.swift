import Foundation
import Testing
@testable import QuartzHubCore

/// VariableResolve against QuartzControl's variableGraph.ts and swatch.ts, run in Chrome
/// (`scripts/variable-resolve-golden.mjs`).
struct VariableResolveTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

  static func load() throws -> (cases: JSONValue, graphs: [String: JSONObject]) {
    let cases = try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("variable-resolve/cases.json")))
    var graphs: [String: JSONObject] = [:]
    for entry in try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("variable-graph/graphs.json"))).arrayValue ?? [] {
      if let name = entry["name"]?.stringValue, case .object(let vars)? = entry["graph"]?["vars"] { graphs[name] = vars }
    }
    return (cases, graphs)
  }

  static func context(_ entry: JSONValue, _ cases: JSONValue, _ graphs: [String: JSONObject]) -> VariableResolve.Context {
    let palette = cases["palettes"]?.arrayValue?.first { $0["name"] == entry["palette"] }
    var overrides: [(key: String, value: VariableResolve.Override)] = []
    if case .object(let set)? = cases["overrideSets"]?[entry["overrides"]?.stringValue ?? ""] {
      for key in set.keys {
        let o = set[key]
        overrides.append((key, VariableResolve.Override(light: o?["light"]?.stringValue ?? "", dark: o?["dark"]?.stringValue ?? "",
                                                         lightOnly: o?["lightOnly"] == .bool(true))))
      }
    }
    return VariableResolve.Context(vars: entry["graph"]?.stringValue.flatMap { graphs[$0] }, overrides: overrides,
                                   colors: palette?["colors"]?.objectValue ?? JSONObject(), typography: palette?["typography"]?.objectValue)
  }

  static func string(_ value: JSONValue?) -> String? {
    if case .string(let text)? = value { return text }
    return nil
  }

  @Test func everyKeyInEveryContext() throws {
    let (cases, graphs) = try Self.load()
    let contexts = cases["contexts"]?.arrayValue ?? []
    #expect(contexts.count == 10)
    var mismatches: [String] = []
    var rows = 0
    for entry in contexts {
      let ctx = Self.context(entry, cases, graphs)
      let label = "\(entry["graph"]?.stringValue ?? "no graph")/\(entry["palette"]?.stringValue ?? "")/\(entry["overrides"]?.stringValue ?? "")"
      let keys = (entry["keys"]?.arrayValue ?? []).compactMap(\.stringValue)
      if VariableResolve.allKnownKeys(ctx) != keys { mismatches.append("\(label): allKnownKeys") }
      for row in entry["rows"]?.arrayValue ?? [] {
        rows += 1
        let key = row["key"]?.stringValue ?? ""
        for mode in VariableResolve.Mode.allCases {
          let want = row[mode.rawValue]
          func check(_ what: String, _ got: String?, _ expected: JSONValue?) {
            if got != Self.string(expected) { mismatches.append("\(label) \(key) \(mode) \(what): \(String(describing: expected)), here \(got ?? "nil")") }
          }
          check("effective", VariableResolve.effectiveValue(key, mode, ctx), want?["effective"])
          check("base", VariableResolve.baseValue(key, mode, ctx), want?["base"])
          check("resolved", VariableResolve.resolvedValue(key, mode, ctx), want?["resolved"])
          let chain = VariableResolve.resolveChain(key, mode, ctx).map { "\($0.key)=\($0.value)" }
          let expected = (want?["chain"]?.arrayValue ?? []).map { "\($0["key"]?.stringValue ?? "")=\($0["value"]?.stringValue ?? "")" }
          if chain != expected { mismatches.append("\(label) \(key) \(mode) chain: \(expected), here \(chain)") }
        }
        if VariableResolve.originOf(key, ctx) != row["origin"]?.stringValue { mismatches.append("\(label) \(key) origin") }
        if VariableResolve.baseOriginOf(key, ctx) != row["baseOrigin"]?.stringValue { mismatches.append("\(label) \(key) baseOrigin") }
        if VariableResolve.groupOf(key) != row["group"]?.stringValue { mismatches.append("\(label) \(key) group") }
        if VariableResolve.isColorVariable(key, ctx, shown: false) != (row["colorBase"] == .bool(true)) { mismatches.append("\(label) \(key) colour (base)") }
        if VariableResolve.isColorVariable(key, ctx, shown: true) != (row["colorShown"] == .bool(true)) { mismatches.append("\(label) \(key) colour (shown)") }
      }
      for literal in entry["literals"]?.arrayValue ?? [] {
        let value = literal["value"]?.stringValue ?? ""
        for mode in VariableResolve.Mode.allCases where VariableResolve.resolveValueLiteral(value, mode, ctx) != Self.string(literal[mode.rawValue]) {
          mismatches.append("\(label) literal \(value) \(mode): \(String(describing: literal[mode.rawValue]))")
        }
      }
      for mode in VariableResolve.Mode.allCases where VariableResolve.pageGround(mode, ctx) != entry["pageGround"]?[mode.rawValue]?.stringValue {
        mismatches.append("\(label) pageGround \(mode)")
      }
    }
    #expect(rows > 4000)
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(mismatches.prefix(30).joined(separator: "\n"))")
  }

  @Test func aliasesReferencesQueriesAndPalettes() throws {
    let (cases, _) = try Self.load()
    for entry in cases["pureAlias"]?.arrayValue ?? [] {
      let value = entry["value"]?.stringValue ?? ""
      let alias = VariableResolve.pureAlias(value)
      #expect(alias?.target == entry["alias"]?["target"]?.stringValue, "\(value)")
      #expect(alias?.fallback == Self.string(entry["alias"]?["fallback"]), "\(value)")
    }
    for entry in cases["referenced"]?.arrayValue ?? [] {
      let value = entry["value"]?.stringValue ?? ""
      #expect(VariableResolve.referencedVariables(value) == (entry["names"]?.arrayValue ?? []).compactMap(\.stringValue), "\(value)")
    }
    for entry in cases["queries"]?.arrayValue ?? [] {
      #expect(VariableResolve.normalizeQuery(entry["query"]?.stringValue ?? "") == entry["normalized"]?.stringValue)
    }
    #expect(cases["paletteGrounds"]?.arrayValue?.count == 6)
    for entry in cases["paletteGrounds"]?.arrayValue ?? [] {
      let palette = entry["palette"]?.objectValue
      #expect(VariableResolve.paletteGround(.light, palette) == entry["light"]?.stringValue)
      #expect(VariableResolve.paletteGround(.dark, palette) == entry["dark"]?.stringValue)
    }
  }
}
