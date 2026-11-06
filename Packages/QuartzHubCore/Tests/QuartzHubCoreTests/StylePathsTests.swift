import Foundation
import Testing
@testable import QuartzHubCore

/// The style writers that name files after what the user hands them keep those names' bytes:
/// FileManager stored "Schöne.woff2" decomposed while the rule named it composed, and a web
/// server that compares bytes answered with a 404. Node keeps the bytes, so the expectation is the
/// name as given.
@Suite struct StylePathsTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  var project: String { "\(scratch.path)/projekt" }
  func names(_ dir: String) -> [[UInt8]] { (Posix.entries(dir) ?? []).map { Array($0.name.utf8) } }

  @Test func anImportedStylesheetKeepsItsName() async throws {
    try Posix.mkdirs(StyleSheets.stylesDirectory(project))
    let source = "\(scratch.path)/Sch\u{F6}n.scss"
    try Posix.write(source, Data(".a {}\n".utf8))
    let imported = try await StyleFiles.importFile(source, project: project)
    #expect(names("\(StyleSheets.stylesDirectory(project))/imported") == [Array("Sch\u{F6}n.scss".utf8)])
    #expect(Array(imported.relativePath.utf8) == Array("imported/Sch\u{F6}n.scss".utf8))
  }

  @Test func anImportedFontKeepsTheNameItsRuleUses() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/font-file/files/noto-sans-latin-400-700.woff2")
    let source = "\(scratch.path)/Sch\u{F6}ne.woff2"
    try TestFolder.copy(fixture, to: source)
    try Posix.mkdirs(StyleSheets.stylesDirectory(project))
    try Posix.write(StyleSheets.customScss(project), Data())
    try Posix.write(StyleSheets.managedScss(project), Data())
    _ = try await FontService().importFontFile(source, family: "Sch\u{F6}n", project: project)
    #expect(names(FontFaces.projectFontsDirectory(project)) == [Array("Sch\u{F6}ne.woff2".utf8)])
    let managed = try Posix.read(StyleSheets.managedScss(project))
    #expect(Array(managed).firstRange(of: Array("static/fonts/Sch\u{F6}ne.woff2".utf8)) != nil)
  }

  /// What a template import writes (fonts, static files) keeps the names the package gives.
  @Test func aTemplateFileKeepsItsName() throws {
    try TemplatePackage.write(Data("x".utf8), to: "\(project)/quartz/static/Gr\u{FC}\u{DF}e/Sch\u{F6}ne.woff2")
    #expect(names("\(project)/quartz/static") == [Array("Gr\u{FC}\u{DF}e".utf8)])
    #expect(names("\(project)/quartz/static/Gr\u{FC}\u{DF}e") == [Array("Sch\u{F6}ne.woff2".utf8)])
  }

  /// A font a template package brings, as the import writes it.
  @Test func aTemplateFontKeepsItsName() async throws {
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"],
                                      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    let read: LayoutFrames.ReadConfig = { _ in QuartzConfig() }
    let templates = TemplatePackage(runtime: .repository, locales: LocaleFiles(environment: environment), frames: LayoutFrames(readConfig: read),
                                    fonts: FontService(readConfig: read), npm: { _, _ in .init(success: true, output: "") },
                                    addPlugin: { _, _ in .init(success: true, output: "") }, head: { _ in nil }, snapshot: { _, _, _ in },
                                    app: ("QuartzHub", "0"))
    try Posix.mkdirs(StyleSheets.stylesDirectory(project))
    try Posix.write(StyleSheets.customScss(project), Data())
    try Posix.write(StyleSheets.managedScss(project), Data())
    var files = ZipArchive.Files()
    files.set("files/fonts/Sch\u{F6}ne.woff2", Data("x".utf8))
    let run = TemplatePackage.Run(project: project, strategy: .packageWins, files: files)
    try await templates.applyFonts(.object(JSONObject([("files", .array([.string("Sch\u{F6}ne.woff2")]))])), run)
    #expect(names(FontFaces.projectFontsDirectory(project)) == [Array("Sch\u{F6}ne.woff2".utf8)])
  }

  @Test func aSnippetFolderKeepsItsName() throws {
    try Posix.mkdirs("\(project)/snippets")
    let written = try Snippets().writeSnippet(project: project, dir: "snippets", file: "Gr\u{FC}\u{DF}e.md", content: "x", overwrite: false)
    #expect(written == .written("Gr\u{FC}\u{DF}e.md"))
    #expect(names("\(project)/snippets") == [Array("Gr\u{FC}\u{DF}e.md".utf8)])
  }
}
