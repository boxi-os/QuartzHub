import CryptoKit
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own styleService.ts: `scripts/site-fonts-golden.mjs` asked
/// collectFontFaces, readPreviewFonts, projectStylesheets and takenClasses about three projects
/// (gui-test's stylesheets, fonts, build CSS and the theme minimal; made-up edges; nothing).
@Suite struct SiteFontsTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch() }

  static func strings(_ list: [String]) -> JSONValue { .array(list.map { .string($0) }) }

  @Test func asQuartzControl() throws {
    let cases = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("site-fonts/cases.json"))).arrayValue ?? []
    #expect(cases.count == 3)
    let manager = FileManager.default
    for entry in cases {
      let name = entry["name"]!.stringValue!
      let project = scratch.url.appendingPathComponent(name)
      try manager.createDirectory(at: project, withIntermediateDirectories: true)
      if entry["real"] == .bool(true) {
        try manager.createDirectory(at: project.appendingPathComponent("quartz"), withIntermediateDirectories: true)
        try manager.copyItem(at: Self.fixtures.appendingPathComponent("variable-graph/real/styles"), to: project.appendingPathComponent("quartz/styles"))
        try manager.copyItem(at: Self.fixtures.appendingPathComponent("variable-graph/real/public"), to: project.appendingPathComponent("public"))
        let fonts = project.appendingPathComponent("quartz/static/fonts")
        try manager.createDirectory(at: fonts, withIntermediateDirectories: true)
        for file in ["noto-sans-latin-400-700.woff2", "noto-sans-latin-italic-400-700.woff2", "noto-sans-mono-latin-400-700.woff2"] {
          try manager.copyItem(at: Self.fixtures.appendingPathComponent("font-file/files/\(file)"), to: fonts.appendingPathComponent(file))
        }
        let theme = project.appendingPathComponent("node_modules/@quartz-themes/minimal")
        try manager.createDirectory(at: theme, withIntermediateDirectories: true)
        try manager.copyItem(at: Self.fixtures.appendingPathComponent("variable-graph/real/themes/minimal/theme.json"), to: theme.appendingPathComponent("theme.json"))
      }
      let files = entry["files"]?.objectValue ?? JSONObject()
      for path in files.keys {
        let url = project.appendingPathComponent(path)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let spec = files[path]!
        if let text = spec.stringValue { try Data(text.utf8).write(to: url) }
        else if let fixture = spec["fixture"]?.stringValue { try manager.copyItem(at: Self.fixtures.appendingPathComponent(fixture), to: url) }
        else if let link = spec["link"]?.stringValue { try manager.createSymbolicLink(atPath: url.path, withDestinationPath: link) }
        else { try Data(repeating: 7, count: Int(spec["size"]!.numberValue!)).write(to: url) }
      }
      for answer in entry["answers"]?.arrayValue ?? [] {
        let call = answer["call"]!.stringValue!
        let args = answer["args"]?.arrayValue ?? []
        let got: JSONValue
        switch call {
        case "collectFontFaces":
          got = .array(SiteFonts.faces(project: project, themeId: args.first?.stringValue).map {
            .object(JSONObject([("family", .string($0.family)), ("weight", .string($0.weight)), ("style", .string($0.style)), ("origin", .string($0.origin)), ("source", .string($0.source))]))
          })
        case "projectStylesheets": got = Self.strings(SiteFonts.projectStylesheets(project: project))
        case "readPreviewFonts":
          let preview = SiteFonts.previewFonts(project: project, families: (args[0].arrayValue ?? []).compactMap(\.stringValue))
          got = .object(JSONObject([("built", .bool(preview.built)), ("faces", .array(preview.faces.map { face in
            var pairs: [(String, JSONValue)] = [("family", .string(face.family)), ("weight", .string(face.weight)), ("style", .string(face.style))]
            if let range = face.unicodeRange { pairs.append(("unicodeRange", .string(range))) }
            pairs += [("length", .number(Double(face.data.count))), ("sha1", .string(Insecure.SHA1.hash(data: face.data).map { String(format: "%02x", $0) }.joined()))]
            return .object(JSONObject(pairs))
          }))]))
        case "takenClasses": got = Self.strings(try SiteFonts.takenClasses(project: project, prefixes: (args[0].arrayValue ?? []).compactMap(\.stringValue)))
        default: got = .null
        }
        #expect(StyleFilesTests.masked(got, project.path) == answer["answer"], "\(name): \(call) \(args)")
      }
    }
  }

  @Test func prefixesAreChecked() {
    #expect(throws: SiteFonts.InvalidPrefix.self) { _ = try SiteFonts.takenClasses(project: URL(fileURLWithPath: "/nowhere"), prefixes: ["a)|(b"]) }
    #expect(throws: SiteFonts.InvalidPrefix.self) { _ = try SiteFonts.takenClasses(project: URL(fileURLWithPath: "/nowhere"), prefixes: Array(repeating: "a-", count: 9)) }
  }
}
