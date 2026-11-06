import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// A folder for a test, named with a composed "ä" and "Ü" and made with POSIX, so it has those bytes
/// on disk: a path that Foundation decomposed on its way no longer matches it by bytes, and a mask
/// that replaces it literally leaves it standing.
enum TestFolder {
  static func make(_ prefix: String, umlaut: Bool = true) -> String {
    let base = NSTemporaryDirectory().hasSuffix("/") ? String(NSTemporaryDirectory().dropLast()) : NSTemporaryDirectory()
    let path = "\(base)/\(prefix)-\(umlaut ? "G\u{E4}rten-\u{DC}-" : "")\(UUID().uuidString)"
    precondition(mkdir(path, 0o755) == 0, "mkdir \(path): \(errno)")
    return path
  }
}

/// Paths are strings with the bytes of the disk (see `NodePath`, `Posix`). Foundation decomposes a
/// name wherever a path passes through a `URL` or a FileManager writer; this test keeps those out
/// of the sources. A line that names a `URL` that is no file path says so with "not a file path";
/// `Posix.path(_:)` is the one way in ("path boundary").
@Suite struct PathHygieneTests {
  static let banned = [
    #"URL\(fileURLWithPath"#, #"URL\(filePath"#, #"\.appendingPathComponent\("#, #"\.appending\(path"#,
    #"\.deletingLastPathComponent"#, #"\.lastPathComponent"#, #"\.write\(to:"#, #"\.write\(toFile"#,
    #"createDirectory\("#, #"createFile\("#, #"copyItem\("#, #"moveItem\("#, #"createSymbolicLink\("#,
    #"resolvingSymlinksInPath"#, #"standardizedFileURL"#, #"fileSystemRepresentation"#,
    #"[:>\[(]\s*URL\b(?!\()"#, #"\bURL\?"#,
  ]

  /// Not yet moved to string paths; each service takes itself off when it is. Shrinks to nothing.
  static let pending: Set<String> = [
    "QuartzHubCore/Build/BuildService.swift",
    "QuartzHubCore/Build/RunningServersStore.swift",
    "QuartzHubCore/Build/ServerLog.swift",
    "QuartzHubCore/Build/ServerScan.swift",
    "QuartzHubCore/Checks/I18nCheck.swift",
    "QuartzHubCore/Checks/OptionSchemaCheck.swift",
    "QuartzHubCore/Config/ConfigFile.swift",
    "QuartzHubCore/Config/FramePaths.swift",
    "QuartzHubCore/Environment/GitRuntime.swift",
    "QuartzHubCore/Environment/ToolEnvironment.swift",
    "QuartzHubCore/Formats/ProfileFiles.swift",
    "QuartzHubCore/Formats/QuartzGuiFiles.swift",
    "QuartzHubCore/Git/GitAuth.swift",
    "QuartzHubCore/Git/GitStatus.swift",
    "QuartzHubCore/Git/Sync.swift",
    "QuartzHubCore/Helpers/Helper.swift",
    "QuartzHubCore/L10n/StringCatalog.swift",
    "QuartzHubCore/Layout/LayoutFrames.swift",
    "QuartzHubCore/Locks/ProjectLock.swift",
    "QuartzHubCore/Migration/Coexistence.swift",
    "QuartzHubCore/Migration/ProfileMigration.swift",
    "QuartzHubCore/Plugins/PluginCommands.swift",
    "QuartzHubCore/Plugins/PluginSchemaReader.swift",
    "QuartzHubCore/Process/ProcessRunner.swift",
    "QuartzHubCore/Projects/ContentBackups.swift",
    "QuartzHubCore/Projects/ContentFolder+Source.swift",
    "QuartzHubCore/Projects/ContentFolder.swift",
    "QuartzHubCore/Projects/ProjectCreator.swift",
    "QuartzHubCore/Projects/ProjectDependencies.swift",
    "QuartzHubCore/Projects/ProjectDuplicator.swift",
    "QuartzHubCore/Projects/ProjectIcon.swift",
    "QuartzHubCore/Projects/ProjectPaths.swift",
    "QuartzHubCore/Projects/ProjectPrefsStore.swift",
    "QuartzHubCore/Projects/ProjectStore.swift",
    "QuartzHubCore/Projects/QuartzGuiWriter.swift",
    "QuartzHubCore/Snapshots/SnapshotStore+Restore.swift",
    "QuartzHubCore/Snapshots/SnapshotStore.swift",
    "QuartzHubCore/Storage/URLBridges.swift",
    "QuartzHubCore/Storage/TreeCopy.swift",
    "QuartzHubCore/Styles/FontFaces.swift",
    "QuartzHubCore/Styles/FontService.swift",
    "QuartzHubCore/Styles/ScssCheck.swift",
    "QuartzHubCore/Styles/SiteFonts.swift",
    "QuartzHubCore/Styles/Snippets.swift",
    "QuartzHubCore/Styles/StyleFiles.swift",
    "QuartzHubCore/Styles/StyleSheets.swift",
    "QuartzHubCore/Styles/VariableGraph.swift",
    "QuartzHubCore/Templates/BuiltinTemplate.swift",
    "QuartzHubCore/Templates/LocaleFiles.swift",
    "QuartzHubCore/Templates/TemplatePackage.swift",
    "QuartzHubCore/Templates/ZipArchive.swift",
    "QuartzHubCore/Themes/StyleSettingsSchema.swift",
    "QuartzHubCore/Themes/ThemeMarketplace.swift",
    "QuartzHubCore/Themes/ThemePresets.swift",
    "QuartzHubCore/Updates/CoreUpdate+Abort.swift",
    "QuartzHubCore/Updates/CoreUpdate+Note.swift",
    "QuartzHubCore/Updates/CoreUpdate.swift",
    "QuartzHubCore/Updates/PluginUpdates.swift",
    "qh-check/InlineSvgRun.swift",
    "qh-check/main.swift"
  ]

  static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Sources").path

  static func offending() throws -> [String: [String]] {
    let pattern = try NSRegularExpression(pattern: banned.joined(separator: "|"))
    var found: [String: [String]] = [:]
    let files = try FileManager.default.subpathsOfDirectory(atPath: sources).filter { $0.hasSuffix(".swift") }
    for file in files {
      let text = try String(contentsOfFile: "\(sources)/\(file)", encoding: .utf8)
      for (number, line) in text.components(separatedBy: "\n").enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || line.contains("not a file path") || line.contains("path boundary") { continue }
        if pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
          found[file, default: []].append("\(number + 1): \(trimmed)")
        }
      }
    }
    return found
  }

  @Test func noDecomposingPathOutsideThePendingFiles() throws {
    let found = try Self.offending()
    for (file, lines) in found.sorted(by: { $0.key < $1.key }) where !Self.pending.contains(file) {
      Issue.record("\(file) decomposes paths:\n\(lines.joined(separator: "\n"))")
    }
    for file in Self.pending.sorted() where found[file] == nil {
      Issue.record("\(file) is clean now: take it off `pending`")
    }
  }

  @Test func theScannerSeesEachBannedForm() throws {
    let pattern = try NSRegularExpression(pattern: Self.banned.joined(separator: "|"))
    let samples = ["URL(fileURLWithPath: p)", "URL(filePath: p)", "u.appendingPathComponent(\"x\")", "u.appending(path: \"x\")",
                   "u.deletingLastPathComponent()", "u.lastPathComponent", "try d.write(to: u)", "try s.write(toFile: p, atomically: true)",
                   "fm.createDirectory(atPath: p)", "fm.createFile(atPath: p)", "fm.copyItem(atPath: a, toPath: b)",
                   "fm.moveItem(atPath: a, toPath: b)", "fm.createSymbolicLink(atPath: a, withDestinationPath: b)",
                   "u.resolvingSymlinksInPath()", "u.standardizedFileURL", "s.fileSystemRepresentation",
                   "func f(project: URL)", "-> URL {", "[URL]", "let u: URL? = nil"]
    for sample in samples {
      #expect(pattern.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)) != nil, "\(sample)")
    }
    for fine in ["URL(string: s)", "URLSession.shared", "URLRequest(url: u)", "let path: String"] {
      #expect(pattern.firstMatch(in: fine, range: NSRange(fine.startIndex..., in: fine)) == nil, "\(fine)")
    }
  }

  @Test func onDiskGivesTheBytesOfTheDisk() throws {
    let root = TestFolder.make("qh-ondisk")
    defer { try? FileManager.default.removeItem(atPath: root) }
    try Posix.mkdirs("\(root)/\u{DC}ber/Gr\u{FC}n")
    try Posix.symlink("\(root)/\u{DC}ber", "\(root)/L\u{E4}nk")
    let decomposed = URL(fileURLWithPath: "\(root)/\u{DC}ber/Gr\u{FC}n/neu").path
    #expect(Array(decomposed.utf8) != Array("\(root)/\u{DC}ber/Gr\u{FC}n/neu".utf8), "Foundation decomposes")
    #expect(Array(Posix.onDisk(decomposed).utf8) == Array("\(root)/\u{DC}ber/Gr\u{FC}n/neu".utf8))
    // A link stays a link, a missing tail stays as given, and a decomposed name on disk stays decomposed.
    #expect(Array(Posix.onDisk("\(root)/La\u{308}nk/x").utf8) == Array("\(root)/L\u{E4}nk/x".utf8))
    #expect(Array(Posix.onDisk("\(root)/U\u{308}ber/").utf8) == Array("\(root)/\u{DC}ber/".utf8))
    try Posix.mkdirs("\(root)/Zo\u{308}gern")
    #expect(Array(Posix.onDisk("\(root)/Z\u{F6}gern").utf8) == Array("\(root)/Zo\u{308}gern".utf8))
    #expect(Array(Posix.onDisk("\(root)/\u{FC}ber").utf8) == Array("\(root)/\u{FC}ber".utf8), "case counts")
    #expect(Posix.onDisk("relative/U\u{308}") == "relative/U\u{308}")
    #expect(Posix.onDisk("/") == "/")
  }

  /// Node compares the bytes of two segments.
  @Test func relativeComparesBytes() {
    #expect(Array(NodePath.relative("/a/U\u{308}ber", "/a/\u{DC}ber/x").utf8) == Array("../\u{DC}ber/x".utf8))
    #expect(NodePath.relative("/a/\u{DC}ber", "/a/\u{DC}ber/x") == "x")
  }
}
