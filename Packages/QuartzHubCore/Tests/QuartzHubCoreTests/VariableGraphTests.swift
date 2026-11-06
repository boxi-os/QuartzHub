import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own variableGraphService.ts and cssVariables.ts:
/// `scripts/variable-graph-golden.mjs` built eleven projects (gui-test's stylesheets and build CSS,
/// the theme minimal, made-up CSS with the cases the reader learnt) and recorded the graph, and
/// the catalog with its helpers.
@Suite struct VariableGraphTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/variable-graph")

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  static func copy(_ from: URL, _ to: URL) throws {
    try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: from, to: to)
  }

  static func layOut(_ files: JSONValue?, at root: URL) throws {
    let object = files?.objectValue ?? JSONObject()
    for path in object.keys {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(object[path]!.stringValue!.utf8).write(to: url)
    }
  }

  @Test func graphsAsQuartzControl() throws {
    let cases = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("graphs.json"))).arrayValue ?? []
    #expect(cases.count >= 11)
    for entry in cases {
      let name = entry["name"]!.stringValue!
      let project = scratch.url.appendingPathComponent(UUID().uuidString)
      let styles = StyleSheets.stylesDirectory(project)
      try FileManager.default.createDirectory(at: styles.deletingLastPathComponent(), withIntermediateDirectories: true)
      if entry["styles"] == .string("real") { try Self.copy(Self.fixtures.appendingPathComponent("real/styles"), styles) }
      else { try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true); try Self.layOut(entry["styles"], at: styles) }
      let build = project.appendingPathComponent(entry["outputDir"]?.stringValue ?? "public")
      if entry["build"] == .string("real") { try Self.copy(Self.fixtures.appendingPathComponent("real/public"), build) }
      else if entry["build"] != nil { try Self.layOut(entry["build"], at: build) }
      let themes = project.appendingPathComponent("node_modules/@quartz-themes")
      if entry["theme"] == .string("minimal") {
        try Self.copy(Self.fixtures.appendingPathComponent("real/themes/minimal/theme.json"), themes.appendingPathComponent("minimal/theme.json"))
      } else if let given = entry["theme"]?.objectValue {
        for id in given.keys {
          let url = themes.appendingPathComponent("\(id)/theme.json")
          try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
          let text = given[id]!.stringValue ?? JSJSON.compact(given[id]!)
          try Data(text.utf8).write(to: url)
        }
      }
      let graph = try VariableGraph.graph(project: project, themeId: entry["themeId"]?.stringValue, outputDir: entry["outputDir"]?.stringValue)
      let expected = entry["graph"]!
      #expect(JSONValue.object(graph.vars) == expected["vars"], "\(name) vars")
      if JSONValue.object(graph.vars) != expected["vars"], let want = expected["vars"]?.objectValue {
        for key in want.keys where graph.vars[key] != want[key] { Issue.record("\(name): --\(key) got \(graph.vars[key].map(JSJSON.compact) ?? "nothing"), expected \(JSJSON.compact(want[key]!))"); break }
        for key in graph.vars.keys where want[key] == nil { Issue.record("\(name): --\(key) not expected"); break }
      }
      #expect(JSONValue.object(graph.dependents) == expected["dependents"], "\(name) dependents")
      #expect(graph.themeId.map { JSONValue.string($0) } == expected["themeId"], "\(name) themeId")
      #expect(.bool(graph.sources.theme) == expected["sources"]?["theme"] && .bool(graph.sources.build) == expected["sources"]?["build"], "\(name) sources")
    }
  }

  @Test func catalogAsQuartzControl() throws {
    let catalog = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("catalog.json")))
    let variables = catalog["variables"]?.arrayValue ?? []
    #expect(variables.count == CssVariables.all.count)
    for (def, entry) in zip(CssVariables.all, variables) {
      #expect(.string(def.key) == entry["key"] && .string(def.group) == entry["group"] && .string(def.kind) == entry["kind"]
              && def.source.map { JSONValue.string($0) } == entry["source"], "\(def.key)")
    }
    for (callout, entry) in zip(CssVariables.callouts, catalog["callouts"]?.arrayValue ?? []) {
      #expect(.string(callout.type) == entry["type"] && .string(callout.color) == entry["color"] && .string(callout.border) == entry["border"]
              && callout.background.map { JSONValue.string($0) } == entry["bg"], "\(callout.type)")
    }
    for entry in catalog["hsl"]?.arrayValue ?? [] {
      let hsl = CssVariables.hexToHsl(entry["hex"]!.stringValue!)
      #expect(.number(hsl.h) == entry["hsl"]?["h"] && .number(hsl.s) == entry["hsl"]?["s"] && .number(hsl.l) == entry["hsl"]?["l"], "\(entry["hex"]!)")
    }
    let palette = catalog["palette"]!, typography = catalog["typography"]?.objectValue
    for entry in catalog["defaults"]?.arrayValue ?? [] {
      let def = CssVariables.definition(entry["key"]!.stringValue!)!
      let value = CssVariables.defaultValue(def, lightMode: palette["lightMode"]?.objectValue, darkMode: palette["darkMode"]?.objectValue,
                                            typography: typography, dark: entry["mode"] == .string("dark"))
      #expect(.string(value) == entry["value"], "\(def.key) \(entry["mode"]!)")
    }
    for entry in catalog["defaultsWithoutColors"]?.arrayValue ?? [] {
      let def = CssVariables.definition(entry["key"]!.stringValue!)!
      #expect(.string(CssVariables.defaultValue(def, lightMode: nil, darkMode: nil, typography: nil, dark: false)) == entry["value"], "\(def.key)")
    }
    for entry in catalog["writable"]?.arrayValue ?? [] {
      #expect(.bool(CssVariables.isWritable(entry["value"]!.stringValue!)) == entry["writable"], "\(entry["value"]!)")
    }
    for entry in catalog["calloutValues"]?.arrayValue ?? [] {
      let resolved = CssVariables.resolveCalloutValue(entry["value"]?.stringValue, lightMode: palette["lightMode"]?.objectValue,
                                                      darkMode: palette["darkMode"]?.objectValue, dark: entry["mode"] == .string("dark"))
      #expect(.string(resolved) == entry["resolved"], "\(entry["value"]!) \(entry["mode"]!)")
    }
  }
}
