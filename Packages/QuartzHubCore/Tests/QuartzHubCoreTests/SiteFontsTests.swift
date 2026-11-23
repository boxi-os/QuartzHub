import CryptoKit
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own styleService.ts: `scripts/site-fonts-golden.mjs` asked
/// collectFontFaces, readPreviewFonts, projectStylesheets and takenClasses about three projects
/// (gui-test's stylesheets, fonts and build CSS; made-up edges; nothing). A theme's fonts come from
/// the build since core 3, which QuartzControl never saw: `theThemesFacesComeFromTheBuild`.
@Suite struct SiteFontsTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  static func strings(_ list: [String]) -> JSONValue { .array(list.map { .string($0) }) }

  @Test func asQuartzControl() throws {
    let cases = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("site-fonts/cases.json"))).arrayValue ?? []
    #expect(cases.count == 3)
    let manager = FileManager.default
    for entry in cases {
      let name = entry["name"]!.stringValue!
      let project = "\(scratch.path)/\(name)"
      try Posix.mkdirs(project)
      if entry["real"] == .bool(true) {
        try Posix.mkdirs("\(project)/quartz")
        try TestFolder.copy(Self.fixtures.appendingPathComponent("variable-graph/real/styles"), to: "\(project)/quartz/styles")
        try TestFolder.copy(Self.fixtures.appendingPathComponent("variable-graph/real/public"), to: "\(project)/public")
        let fonts = "\(project)/quartz/static/fonts"
        try Posix.mkdirs(fonts)
        for file in ["noto-sans-latin-400-700.woff2", "noto-sans-latin-italic-400-700.woff2", "noto-sans-mono-latin-400-700.woff2"] {
          try TestFolder.copy(Self.fixtures.appendingPathComponent("font-file/files/\(file)"), to: "\(fonts)/\(file)")
        }
      }
      let files = entry["files"]?.objectValue ?? JSONObject()
      for path in files.keys {
        let url = "\(project)/\(path)"
        try Posix.mkdirs(NodePath.dirname(url))
        let spec = files[path]!
        if let text = spec.stringValue { try Posix.write(url, Data(text.utf8)) }
        else if let fixture = spec["fixture"]?.stringValue { try TestFolder.copy(Self.fixtures.appendingPathComponent(fixture), to: url) }
        else if let link = spec["link"]?.stringValue { try Posix.symlink(link, url) }
        else { try Posix.write(url, Data(repeating: 7, count: Int(spec["size"]!.numberValue!))) }
      }
      for answer in entry["answers"]?.arrayValue ?? [] {
        let call = answer["call"]!.stringValue!
        let args = answer["args"]?.arrayValue ?? []
        let got: JSONValue
        switch call {
        case "collectFontFaces":
          got = .array(SiteFonts.faces(project: project).map {
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
        var expected = answer["answer"]
        // gui-test's build wrote `index-a4eb4042.css`; QuartzControl looked for `index.css` only and
        // called it unbuilt. QuartzHub finds the hashed name (decided 2026-11-11).
        if call == "readPreviewFonts", name == "gui-test", var object = expected?.objectValue {
          #expect(object["built"] == .bool(false), "QuartzControl's answer changed")
          object["built"] = .bool(true)
          expected = .object(object)
        }
        #expect(StyleFilesTests.masked(got, project) == expected, "\(name): \(call) \(args)")
      }
    }
  }

  /// Quartz's hashed main stylesheet: its fonts count, `index.css` wins where it is there, and of
  /// two hashed ones the newer does.
  @Test func theHashedMainStylesheetIsTheBuilds() throws {
    let project = "\(scratch.path)/hashed"
    try Posix.mkdirs("\(project)/public")
    let face = { (family: String) in Data("@font-face{font-family:\"\(family)\";src:url(static/fonts/x.woff2)}".utf8) }
    try Posix.write("\(project)/public/index-0a1b2c3d.css", face("Alt Sans"))
    let old = Date().addingTimeInterval(-60)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: "\(project)/public/index-0a1b2c3d.css")
    try Posix.write("\(project)/public/index-9f8e7d6c.css", face("Probe Sans"))
    try Posix.write("\(project)/public/index-notahash.css", face("Fremd Sans"))
    #expect(SiteFonts.faces(project: project).filter { $0.origin == "build" }.map(\.family) == ["Probe Sans"])
    #expect(SiteFonts.previewFonts(project: project, families: []).built)
    try Posix.write("\(project)/public/index.css", face("Plain Sans"))
    #expect(SiteFonts.faces(project: project).filter { $0.origin == "build" }.map(\.family) == ["Plain Sans"])
    let empty = "\(scratch.path)/unbuilt"
    try Posix.mkdirs("\(empty)/public")
    #expect(!SiteFonts.previewFonts(project: empty, families: []).built)
  }

  /// core 3's sheet in the build (`static/resource-style-<hash>.css` with `@layer obsidian`, its
  /// files under `static/plugins/quartz-themes/fonts/`), written as Quartz's minifier leaves it.
  @Test func theThemesFacesComeFromTheBuild() throws {
    let project = "\(scratch.path)/core3"
    let statics = "\(project)/public/static"
    try Posix.mkdirs("\(statics)/plugins/quartz-themes/fonts")
    try Posix.write("\(statics)/resource-style-25d3dcfb.css", Data(("@layer quartz-base;@layer obsidian{@font-face{font-family:\"??\";unicode-range:U+0}"
      + "@font-face{font-display:swap;font-family:Vollkorn;font-style:normal;font-weight:400;src:url(plugins/quartz-themes/fonts/625c.woff2)format(\"woff2\");unicode-range:U+460-52F}"
      + "@font-face{font-family:Vollkorn;font-style:italic;font-weight:800;src:url(plugins/quartz-themes/fonts/a8fb.woff2)format(\"woff2\")}"
      + "@font-face{font-family:Escape;src:url(plugins/quartz-themes/fonts/..%2F..%2Fsecret.woff2)}body{--font-text-theme:Vollkorn}}").utf8))
    // Another plugin's inline sheet, and a stylesheet that is not one of Quartz's resources.
    try Posix.write("\(statics)/resource-style-12ad65a1.css", Data("@layer quartz-base{@font-face{font-family:Plugin Sans;src:url(x.woff2)}}".utf8))
    try Posix.write("\(statics)/other.css", Data("@layer obsidian{@font-face{font-family:Other;src:url(plugins/quartz-themes/fonts/625c.woff2)}}".utf8))
    try TestFolder.copy(Self.fixtures.appendingPathComponent("font-file/files/noto-sans-latin-400-700.woff2"), to: "\(statics)/plugins/quartz-themes/fonts/625c.woff2")
    // Where `..%2F..%2Fsecret.woff2` would lead: a name in the sheet names a file in the fonts folder, no other.
    try Posix.write("\(statics)/plugins/secret.woff2", Data("not a font of the theme".utf8))

    let faces = SiteFonts.faces(project: project, theme: true)
    #expect(faces.map(\.family) == ["Vollkorn", "Vollkorn", "Escape"])
    #expect(faces.allSatisfy { $0.origin == "theme" && $0.source == "public/static/resource-style-25d3dcfb.css" })
    #expect(faces[1].weight == "800" && faces[1].style == "italic")
    // A theme that is off leaves its sheet of an earlier build behind; that is not the site's.
    #expect(SiteFonts.faces(project: project).isEmpty)

    let preview = SiteFonts.previewFonts(project: project, families: ["vollkorn", "Escape"], theme: true)
    #expect(preview.faces.map(\.weight) == ["400"])
    #expect(preview.faces.first?.unicodeRange == "U+460-52F")
    #expect(preview.faces.first?.data == FileManager.default.contents(atPath: "\(statics)/plugins/quartz-themes/fonts/625c.woff2"))
    #expect(SiteFonts.previewFonts(project: project, families: ["Vollkorn"]).faces.isEmpty)
    #expect(SiteFonts.themeStylesheets(build: "\(project)/public") == ["\(statics)/resource-style-25d3dcfb.css"])
  }

  @Test func prefixesAreChecked() {
    #expect(throws: SiteFonts.InvalidPrefix.self) { _ = try SiteFonts.takenClasses(project: "/nowhere", prefixes: ["a)|(b"]) }
    #expect(throws: SiteFonts.InvalidPrefix.self) { _ = try SiteFonts.takenClasses(project: "/nowhere", prefixes: Array(repeating: "a-", count: 9)) }
  }
}
