import Foundation

/// Which fonts the built site will have, the files behind them for the preview, and which class
/// names a project's stylesheets and plugins already use: a port of `collectFontFaces`,
/// `readPreviewFonts`, `projectStylesheets` and `takenClasses` in `styleService.ts`.
public enum SiteFonts {
  /// The flat list the editor offers: custom.scss, `_quartzcontrol.scss`, then the files directly in
  /// custom/ and imported/ (the files QuartzHub writes itself).
  public static func projectStylesheets(project: String) -> [String] {
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project))
    var files = [NodePath.join(styles, "custom.scss"), NodePath.join(styles, ManagedBlocks.managedFile)]
    for dir in StyleSheets.styleDirectories {
      let full = NodePath.join(styles, dir)
      guard FileManager.default.fileExists(atPath: full) else { continue }
      files += StyleFiles.filesOnDisk(full).map { NodePath.join(full, $0) }
    }
    return files.filter { FileManager.default.fileExists(atPath: $0) }
  }

  /// The build's stylesheets that can hold Quartz's @font-face rules: the main stylesheet and the
  /// Fonts plugin's static/fonts/*.css.
  static func buildStylesheets(_ project: String) -> [String] {
    let build = BuildOutputGuard.buildDirectory(project: project, outputDir: nil)
    var files = mainStylesheet(build).map { [$0] } ?? []
    let fonts = NodePath.join(build, "static/fonts")
    if FileManager.default.fileExists(atPath: fonts) {
      files += LayoutFrames.directoryEntriesWithKind(fonts).filter { $0.kind == .file && JSText.endsWith($0.name, ".css") }.map { NodePath.join(fonts, $0.name) }
    }
    return files.filter { FileManager.default.fileExists(atPath: $0) }
  }

  /// Quartz names the main stylesheet `index-<hash>.css` when it hashes its resources
  /// (`componentResources.ts`, `cssSlug`), else `index.css`. QuartzControl's `styleService.ts` read
  /// only `index.css` and so never saw a hashed build's fonts, gui-test's included (its build already
  /// wrote `index-a4eb4042.css`); found on Quartz 5.1, 2026-11-11. A build empties its folder, so
  /// there is one; should a server's rebuilds leave more, the newest counts.
  static func mainStylesheet(_ build: String) -> String? {
    let plain = NodePath.join(build, "index.css")
    if FileManager.default.fileExists(atPath: plain) { return plain }
    var newest: (path: String, time: timespec)?
    for entry in LayoutFrames.directoryEntriesWithKind(build) where entry.kind == .file && JSText.test(entry.name, #"\Aindex-[0-9a-f]+\.css\z"#) {
      let path = NodePath.join(build, entry.name)
      var info = stat()
      guard stat(path, &info) == 0 else { continue }
      let time = info.st_mtimespec
      if let current = newest, (current.time.tv_sec, current.time.tv_nsec) >= (time.tv_sec, time.tv_nsec) { continue }
      newest = (path, time)
    }
    return newest?.path
  }

  public struct Face: Equatable, Sendable {
    public var family: String
    public var weight: String
    public var style: String
    /// `theme`, `project` or `build` (the Google fonts Quartz downloads; no rule before a build).
    public var origin: String
    public var source: String
  }

  struct LocatedFace {
    var face: FontFaces.Face
    var origin: String
    var source: String
    var file: String?
  }

  // MARK: The theme's sheet

  /// `@quartz-themes/core` 3 hands Quartz its CSS inline, and Quartz writes every inline sheet of a
  /// plugin to `static/resource-style-<hash>.css` (`componentResources.ts`); the theme's is the one
  /// with `@layer obsidian` (measured on the demo with Catppuccin, decisions/phase-5-gleichstand.md,
  /// „Schriften und Variablen aus dem Build“). Core 2's `theme.json` in `node_modules` is gone.
  static let themeLayer = "@layer[\(JSText.space)]+obsidian(?![A-Za-z0-9_-])"

  public static func themeStylesheets(build: String) -> [String] {
    let dir = NodePath.join(build, "static")
    guard FileManager.default.fileExists(atPath: dir) else { return [] }
    return LayoutFrames.directoryEntriesWithKind(dir)
      .filter { $0.kind == .file && JSText.test($0.name, #"\Aresource-style-[0-9a-f]+\.css\z"#) }
      .map { NodePath.join(dir, $0.name) }
      .filter { JSText.test((try? StyleSheets.readText($0)) ?? "", themeLayer) }
      .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
  }

  /// Where core moves a theme's embedded fonts; the sheet names them relative to `static/`.
  static let themeFontsDirectory = "static/plugins/quartz-themes/fonts"

  static func themeFontFile(_ build: String, _ url: String?) -> String? {
    guard let url, let match = JSText.firstMatch(url, #"\A(?:\./)?plugins/quartz-themes/fonts/([^/?#]+)(?:[?#][^\n\r]*)?\z"#),
          let encoded = match.groups[1], let name = try? JSURI.decodeComponent(encoded),
          name == NodePath.basename(name), !JSText.startsWith(name, "."), !JSText.includes(name, "\\") else { return nil }
    return NodePath.join(build, themeFontsDirectory, name)
  }

  /// The theme's faces with a source: Obsidian's own `@font-face{font-family:"??"}` (a placeholder in
  /// app.css with nothing to load) is no font of the site.
  static func themeFaces(_ project: String) -> [LocatedFace] {
    let build = BuildOutputGuard.buildDirectory(project: project, outputDir: nil)
    var out: [LocatedFace] = []
    for path in themeStylesheets(build: build) {
      for face in FontFaces.parse((try? StyleSheets.readText(path)) ?? "") where !face.urls.isEmpty {
        out.append(LocatedFace(face: face, origin: "theme", source: NodePath.relative(NodePath.normalize(project), path), file: themeFontFile(build, face.url)))
      }
    }
    return out
  }

  static func projectAndBuildFaces(_ project: String) -> [LocatedFace] {
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project))
    let fonts = NodePath.normalize(FontFaces.projectFontsDirectory(project))
    var out: [LocatedFace] = []
    for path in projectStylesheets(project: project) {
      for face in FontFaces.parse((try? StyleSheets.readText(path)) ?? "") {
        out.append(LocatedFace(face: face, origin: "project", source: NodePath.relative(styles, path), file: FontFaces.fileIn(fonts, face.url)))
      }
    }
    // A family the project declares itself is the project's, also where the build repeats it.
    let own = Set(out.map { $0.face.family.lowercased() })
    let buildFonts = NodePath.join(BuildOutputGuard.buildDirectory(project: project, outputDir: nil), "static/fonts")
    for path in buildStylesheets(project) {
      for face in FontFaces.parse((try? StyleSheets.readText(path)) ?? "") where !own.contains(face.family.lowercased()) {
        out.append(LocatedFace(face: face, origin: "build", source: NodePath.relative(NodePath.normalize(project), path), file: FontFaces.fileIn(buildFonts, face.url)))
      }
    }
    return out
  }

  /// Every @font-face the site will have: the active theme's (from the last build), the project's
  /// own rules, and the rules a build wrote. Quartz downloads fonts only for `fontOrigin:
  /// googleFonts`; under "local" the project's rules are all there is. `theme`: a theme is on, so
  /// the build's theme sheet counts as its; off, a sheet left from an earlier build does not.
  public static func faces(project: String, theme: Bool = false) -> [Face] {
    var out: [Face] = []
    if theme {
      for located in themeFaces(project) {
        out.append(Face(family: located.face.family, weight: located.face.weight, style: located.face.style, origin: located.origin, source: located.source))
      }
    }
    for located in projectAndBuildFaces(project) {
      out.append(Face(family: located.face.family, weight: located.face.weight, style: located.face.style, origin: located.origin, source: located.source))
    }
    return out
  }

  public struct PreviewFace: Equatable, Sendable {
    public var family: String
    public var weight: String
    public var style: String
    public var unicodeRange: String?
    public var data: Data
  }

  /// A ceiling over all faces together; each file is held to `FontFile.maxFileBytes` as well.
  static let maxPreviewBytes = 32 * 1024 * 1024

  /// The files behind the faces of `families`, for the preview to draw the font the site will have
  /// instead of whatever this Mac has installed; with `theme`, the theme's from the last build too. A link is no font file of the project: following
  /// one would hand over the bytes of whatever it points at.
  public static func previewFonts(project: String, families: [String], theme: Bool = false) -> (faces: [PreviewFace], built: Bool) {
    let wanted = Set(families.map { $0.lowercased() })
    var faces: [PreviewFace] = []
    var total = 0
    for located in (theme ? themeFaces(project) : []) + projectAndBuildFaces(project) {
      guard let file = located.file, wanted.contains(located.face.family.lowercased()) else { continue }
      var info = stat()
      guard lstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
      let size = Int(info.st_size)
      if size > FontFile.maxFileBytes || total + size > maxPreviewBytes { continue }
      total += size
      guard let data = FileManager.default.contents(atPath: file) else { continue }
      faces.append(PreviewFace(family: located.face.family, weight: located.face.weight, style: located.face.style, unicodeRange: located.face.unicodeRange, data: data))
    }
    let built = mainStylesheet(BuildOutputGuard.buildDirectory(project: project, outputDir: nil)) != nil
    return (faces, built)
  }

  public struct InvalidPrefix: Error, Equatable { public let prefix: String }

  /// Every class name starting with one of `prefixes` that a stylesheet of the project or the built
  /// code of a plugin names, for a new instance class that must not pick up rules written for
  /// something else. Broad on purpose: one found too many costs a `-2`, one too few a foreign look.
  /// A custom property (`--nav-gap`) is not a class.
  public static func takenClasses(project: String, prefixes: [String]) throws -> [String] {
    for prefix in prefixes where !JSText.test(prefix, #"\A[A-Za-z_][A-Za-z0-9_-]{0,39}\z"#) { throw InvalidPrefix(prefix: prefix) }
    guard !prefixes.isEmpty, prefixes.count <= 8 else {
      if prefixes.count > 8 { throw InvalidPrefix(prefix: prefixes.joined(separator: ",")) }
      return []
    }
    let pattern = "(?<![A-Za-z0-9_-])(?:\(prefixes.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")))[A-Za-z0-9_-]+"
    var files = FontFaces.allStylesheets(project: project)
    func walk(_ dir: String, _ depth: Int) {
      guard depth <= 6, FileManager.default.fileExists(atPath: dir) else { return }
      for entry in LayoutFrames.directoryEntriesWithKind(dir) {
        let full = NodePath.join(dir, entry.name)
        var kind = entry.kind
        if kind == .link {
          var isDirectory: ObjCBool = false
          kind = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory) ? (isDirectory.boolValue ? .directory : .file) : .other
        }
        if kind == .directory { walk(full, depth + 1) } else if kind == .file && JSText.test(entry.name, #"\.(m?js|css)\z"#) { files.append(full) }
      }
    }
    let plugins = NodePath.join(project, ".quartz/plugins")
    if FileManager.default.fileExists(atPath: plugins) {
      for entry in LayoutFrames.directoryEntriesWithKind(plugins) { walk(NodePath.join(plugins, entry.name, "dist"), 0) }
    }
    var found: Set<String> = []
    for file in files {
      let text = (try? StyleSheets.readText(file)) ?? ""
      for match in JSText.matches(text, pattern) { found.insert(JSText.replaceAll(match.groups[0]!, #"-+\z"#, with: "")) }
    }
    return found.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
  }
}
