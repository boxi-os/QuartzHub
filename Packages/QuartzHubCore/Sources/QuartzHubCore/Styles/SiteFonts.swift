import Foundation

/// Which fonts the built site will have, the files behind them for the preview, and which class
/// names a project's stylesheets and plugins already use: a port of `collectFontFaces`,
/// `readPreviewFonts`, `projectStylesheets` and `takenClasses` in `styleService.ts`.
public enum SiteFonts {
  /// The flat list the editor offers: custom.scss, `_quartzcontrol.scss`, then the files directly in
  /// custom/ and imported/ (the files QuartzHub writes itself).
  public static func projectStylesheets(project: URL) -> [String] {
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project).path)
    var files = [NodePath.join(styles, "custom.scss"), NodePath.join(styles, ManagedBlocks.managedFile)]
    for dir in StyleSheets.styleDirectories {
      let full = NodePath.join(styles, dir)
      guard FileManager.default.fileExists(atPath: full) else { continue }
      files += StyleFiles.filesOnDisk(URL(fileURLWithPath: full)).map { NodePath.join(full, $0) }
    }
    return files.filter { FileManager.default.fileExists(atPath: $0) }
  }

  /// The build's stylesheets that can hold Quartz's @font-face rules: index.css and the Fonts
  /// plugin's static/fonts/*.css.
  static func buildStylesheets(_ project: URL) -> [String] {
    let build = BuildOutputGuard.buildDirectory(project: project.path, outputDir: nil)
    var files = [NodePath.join(build, "index.css")]
    let fonts = NodePath.join(build, "static/fonts")
    if FileManager.default.fileExists(atPath: fonts) {
      files += LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: fonts).path).filter { $0.kind == .file && JSText.endsWith($0.name, ".css") }.map { NodePath.join(fonts, $0.name) }
    }
    return files.filter { FileManager.default.fileExists(atPath: $0) }
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

  static func projectAndBuildFaces(_ project: URL) -> [LocatedFace] {
    let styles = NodePath.normalize(StyleSheets.stylesDirectory(project).path)
    let fonts = NodePath.normalize(FontFaces.projectFontsDirectory(project).path)
    var out: [LocatedFace] = []
    for path in projectStylesheets(project: project) {
      for face in FontFaces.parse((try? StyleSheets.readText(URL(fileURLWithPath: path))) ?? "") {
        out.append(LocatedFace(face: face, origin: "project", source: NodePath.relative(styles, path), file: FontFaces.fileIn(fonts, face.url)))
      }
    }
    // A family the project declares itself is the project's, also where the build repeats it.
    let own = Set(out.map { $0.face.family.lowercased() })
    let buildFonts = NodePath.join(BuildOutputGuard.buildDirectory(project: project.path, outputDir: nil), "static/fonts")
    for path in buildStylesheets(project) {
      for face in FontFaces.parse((try? StyleSheets.readText(URL(fileURLWithPath: path))) ?? "") where !own.contains(face.family.lowercased()) {
        out.append(LocatedFace(face: face, origin: "build", source: NodePath.relative(NodePath.normalize(project.path), path), file: FontFaces.fileIn(buildFonts, face.url)))
      }
    }
    return out
  }

  /// Every @font-face the site will have: the active theme's font files (`meta.fontFiles` of its
  /// theme.json), the project's own rules, and the rules a build wrote. Quartz downloads fonts only
  /// for `fontOrigin: googleFonts`; under "local" the project's rules are all there is.
  public static func faces(project: URL, themeId: String? = nil) -> [Face] {
    var out: [Face] = []
    if let themeId {
      let path = NodePath.join(project.path, "node_modules/@quartz-themes", themeId, "theme.json")
      // A malformed theme.json is the theme's problem, not a reason to show nothing.
      if let data = FileManager.default.contents(atPath: path), let parsed = try? JSJSON.parse(data) {
        for file in parsed[safe: "meta"]?[safe: "fontFiles"]?.arrayValue ?? [] {
          guard let family = file[safe: "family"], JS.truthy(family) else { continue }
          // `file.weight ?? '400'`: null and a missing key alike.
          let given = { (key: String) in file[safe: key].flatMap { $0 == .null ? nil : JS.string($0) } }
          out.append(Face(family: JS.string(family), weight: given("weight") ?? "400", style: given("style") ?? "normal",
                          origin: "theme", source: "@quartz-themes/\(themeId)"))
        }
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
  /// instead of whatever this Mac has installed. A link is no font file of the project: following
  /// one would hand over the bytes of whatever it points at.
  public static func previewFonts(project: URL, families: [String]) -> (faces: [PreviewFace], built: Bool) {
    let wanted = Set(families.map { $0.lowercased() })
    var faces: [PreviewFace] = []
    var total = 0
    for located in projectAndBuildFaces(project) {
      guard let file = located.file, wanted.contains(located.face.family.lowercased()) else { continue }
      var info = stat()
      guard lstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
      let size = Int(info.st_size)
      if size > FontFile.maxFileBytes || total + size > maxPreviewBytes { continue }
      total += size
      guard let data = FileManager.default.contents(atPath: file) else { continue }
      faces.append(PreviewFace(family: located.face.family, weight: located.face.weight, style: located.face.style, unicodeRange: located.face.unicodeRange, data: data))
    }
    let built = FileManager.default.fileExists(atPath: NodePath.join(BuildOutputGuard.buildDirectory(project: project.path, outputDir: nil), "index.css"))
    return (faces, built)
  }

  public struct InvalidPrefix: Error, Equatable { public let prefix: String }

  /// Every class name starting with one of `prefixes` that a stylesheet of the project or the built
  /// code of a plugin names, for a new instance class that must not pick up rules written for
  /// something else. Broad on purpose: one found too many costs a `-2`, one too few a foreign look.
  /// A custom property (`--nav-gap`) is not a class.
  public static func takenClasses(project: URL, prefixes: [String]) throws -> [String] {
    for prefix in prefixes where !JSText.test(prefix, #"\A[A-Za-z_][A-Za-z0-9_-]{0,39}\z"#) { throw InvalidPrefix(prefix: prefix) }
    guard !prefixes.isEmpty, prefixes.count <= 8 else {
      if prefixes.count > 8 { throw InvalidPrefix(prefix: prefixes.joined(separator: ",")) }
      return []
    }
    let pattern = "(?<![A-Za-z0-9_-])(?:\(prefixes.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")))[A-Za-z0-9_-]+"
    var files = FontFaces.allStylesheets(project: project)
    func walk(_ dir: String, _ depth: Int) {
      guard depth <= 6, FileManager.default.fileExists(atPath: dir) else { return }
      for entry in LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: dir).path) {
        let full = NodePath.join(dir, entry.name)
        var kind = entry.kind
        if kind == .link {
          var isDirectory: ObjCBool = false
          kind = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory) ? (isDirectory.boolValue ? .directory : .file) : .other
        }
        if kind == .directory { walk(full, depth + 1) } else if kind == .file && JSText.test(entry.name, #"\.(m?js|css)\z"#) { files.append(full) }
      }
    }
    let plugins = NodePath.join(project.path, ".quartz/plugins")
    if FileManager.default.fileExists(atPath: plugins) {
      for entry in LayoutFrames.directoryEntriesWithKind(URL(fileURLWithPath: plugins).path) { walk(NodePath.join(plugins, entry.name, "dist"), 0) }
    }
    var found: Set<String> = []
    for file in files {
      let text = (try? StyleSheets.readText(URL(fileURLWithPath: file))) ?? ""
      for match in JSText.matches(text, pattern) { found.insert(JSText.replaceAll(match.groups[0]!, #"-+\z"#, with: "")) }
    }
    return found.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
  }
}
