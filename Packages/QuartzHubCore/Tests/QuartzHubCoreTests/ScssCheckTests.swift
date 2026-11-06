import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own styleService.ts: `scripts/scss-check-golden.mjs` ran checkStyles,
/// checkStyleSource and readQuartzFrameMeasures on 20 projects, each with node_modules/sass linked
/// to the sass in Helpers/node_modules (gui-test's version). Here the same projects go through the
/// sass-check helper.
enum ProjectSass {
  static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  /// The stand-in for a project's sass: the one in Helpers/node_modules, gui-test's version.
  static let sass = root.appendingPathComponent("../../../../Helpers/node_modules/sass").standardizedFileURL
  static let available = HelperRuntime.available
    && FileManager.default.fileExists(atPath: HelperRuntime.runtime.helpers.appendingPathComponent("sass-check.cjs").path)
    && FileManager.default.fileExists(atPath: sass.appendingPathComponent("package.json").path)
}

@Suite(.enabled(if: ProjectSass.available, "Runtime/, Helpers/dist oder Helpers/node_modules/sass fehlt"))
struct ScssCheckTests {
  static let fixtures = ProjectSass.root.appendingPathComponent("Fixtures/scss-check")
  static let sass = ProjectSass.sass

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  static func json(_ name: String) throws -> JSONValue { try JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent(name))) }

  static func result(_ result: ScssCheck.Result) -> JSONValue {
    switch result {
    case .ok: return .object(JSONObject([("status", .string("ok"))]))
    case .unavailable(let reason): return .object(JSONObject([("status", .string("unavailable")), ("reason", .string(reason))]))
    case .error(let d):
      var pairs: [(String, JSONValue)] = [("message", .string(d.message))]
      if let path = d.relativePath { pairs.append(("relativePath", .string(path))) }
      if let line = d.line { pairs.append(("line", .number(Double(line)))) }
      if let column = d.column { pairs.append(("column", .number(Double(column)))) }
      if d.nestedImportBlock { pairs.append(("nestedImportBlock", .bool(true))) }
      if d.managedFileMissing { pairs.append(("managedFileMissing", .bool(true))) }
      return .object(JSONObject([("status", .string("error")), ("diagnostic", .object(JSONObject(pairs)))]))
    }
  }

  static func measures(_ result: ScssCheck.MeasuresResult) -> JSONValue {
    switch result {
    case .unavailable(let reason): return .object(JSONObject([("status", .string("unavailable")), ("reason", .string(reason))]))
    case .ok(let m):
      var grids = JSONObject()
      for breakpoint in ["desktop", "tablet", "mobile"] {
        let grid = m.grids[breakpoint]!
        grids[breakpoint] = .object(JSONObject([("columns", .array(grid.columns.map { .string($0) })), ("rowGap", .string(grid.rowGap)), ("columnGap", .string(grid.columnGap))]))
      }
      let breakpoints = JSONValue.object(JSONObject([("mobile", .number(m.breakpoints.mobile)), ("desktop", .number(m.breakpoints.desktop))]))
      return .object(JSONObject([("status", .string("ok")), ("measures", .object(JSONObject([("grids", .object(grids)), ("breakpoints", breakpoints),
                                                                                              ("pageMaxWidth", m.pageMaxWidth.map { .string($0) } ?? .null)])))]))
    }
  }

  @Test func asQuartzControl() async throws {
    let gui = try Self.json("gui-test.json"), example = try Self.json("example.json")
    let cases = try Self.json("cases.json").arrayValue ?? []
    #expect(cases.count >= 20)
    for entry in cases {
      let name = entry["name"]!.stringValue!
      let project = scratch.url.appendingPathComponent(name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ":", with: ""))
      let styles = StyleSheets.stylesDirectory(project)
      try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
      let tree = entry["tree"]?.objectValue ?? JSONObject()
      for path in tree.keys {
        let value = tree[path]!
        let text = value["gui"].flatMap { gui[$0.stringValue!]?.stringValue } ?? value["example"].flatMap { example[$0.stringValue!]?.stringValue } ?? value.stringValue!
        let url = styles.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
      }
      try Data("{ \"name\": \"golden\", \"private\": true }\n".utf8).write(to: project.appendingPathComponent("package.json"))
      switch entry["sass"]?.stringValue {
      case "none": break
      case "half": try FileManager.default.createDirectory(at: project.appendingPathComponent("node_modules/sass"), withIntermediateDirectories: true)
      default:
        try FileManager.default.createDirectory(at: project.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("node_modules/sass"), withDestinationURL: Self.sass)
      }
      for answer in entry["answers"]?.arrayValue ?? [] {
        let call = answer["call"]!.stringValue!
        let args = answer["args"]?.arrayValue ?? []
        let got: JSONValue
        switch call {
        case "checkStyles": got = Self.result(await ScssCheck.check(project: project, runtime: HelperRuntime.runtime))
        case "checkStyleSource":
          got = Self.result(try await ScssCheck.checkSource(args[0].stringValue!, args[1].stringValue!, project: project, runtime: HelperRuntime.runtime))
        case "readQuartzFrameMeasures": got = Self.measures(await ScssCheck.frameMeasures(project: project, runtime: HelperRuntime.runtime))
        default: got = .null
        }
        #expect(got == FontServiceTests.rendered(answer["answer"] ?? .null), "\(name): \(call)")
      }
    }
  }
}
