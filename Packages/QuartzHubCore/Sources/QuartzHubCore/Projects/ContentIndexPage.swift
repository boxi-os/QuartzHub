import Darwin
import Foundation

/// "Startseite anlegen": `content/index.md` with a title and a list of what lies at the top of the
/// content folder (QuartzControl's `createIndexPage` in contentService.ts, measured against it in
/// `scripts/content-index-golden.mjs`). Without it the site's own address is Quartz's 404 page,
/// and a linked vault almost never has one.
///
/// Which notes the build reads is Quartz's to say, so the `content-files` helper asks the project's
/// own globby, run as `quartz/util/glob.ts` runs it; without one installed it walks the folder with
/// QuartzControl's fallback, which reads no `.gitignore`, and says so (`ListSource.fallback`).
///
/// Never overwrites: the file is created exclusively, so an index.md that appeared meanwhile (or
/// in another case) is refused, not replaced. In a linked vault this writes into the user's own
/// notes, which is why it only happens from a dialog that names the folder.
public enum ContentIndexPage {
  public enum ListSource: String, Sendable { case quartz, fallback }

  public struct Created: Equatable, Sendable {
    public var path: String
    public var listSource: ListSource
  }

  public enum Failure: Error, Equatable {
    case noContent
    case exists
    /// npm is still unpacking globby, or stopped halfway (the name it found).
    case unpacking(String)
    /// The project's globby is there and does not load.
    case globbyBroken(String)
    /// The helper did not answer: QuartzHub's fault, not the project's.
    case helper(String)
    case write(String)

    public var message: String {
      switch self {
      case .noContent: L10n.t("main.indexPageNoContent")
      case .exists: L10n.t("main.indexPageExists")
      case .unpacking(let name): L10n.t("main.indexPageGlobbyUnpacking", ["name": name])
      case .globbyBroken(let message): L10n.t("main.indexPageGlobbyBroken", ["message": message])
      case .helper(let reason): L10n.t("content.indexHelperBroken", ["reason": reason])
      case .write(let reason): reason
      }
    }
  }

  public static func create(project: String, title: String, runtime: RuntimeLocation = .current) async throws(Failure) -> Created {
    guard let status = try? ContentFolder.status(project: project),
          status.exists, !(status.isSymlink && status.targetExists != true) else { throw .noContent }
    guard let dir = realpath(ContentFolder.path(project: project), nil).map({ pointer in
      defer { free(pointer) }
      return String(cString: pointer)
    }) else { throw .noContent }
    if ContentFolder.hasIndexPage(dir) { throw .exists }

    // A config that cannot be read still leaves the hidden entries out; the list is a start.
    var patterns: [String] = []
    if let config = try? await ConfigFile.read(project: project, runtime: runtime),
       case .array(let items)? = config.configuration["ignorePatterns"] {
      patterns = items.compactMap(\.stringValue)
    }

    let listed = try await inputFiles(project: project, cwd: ContentFolder.path(project: project), patterns: patterns, runtime: runtime)
    // Quartz's test, not a case-blind one: `endsWith(".md")` in build.ts, so `Note.MD` is an asset.
    let markdown = listed.files.filter { $0.hasSuffix(".md") }
    var notes = markdown.filter { !$0.contains("/") }
    var folders: [String] = []
    for path in markdown where path.contains("/") {
      let first = String(path.split(separator: "/", omittingEmptySubsequences: false)[0])
      if !folders.contains(first) { folders.append(first) }
    }
    // `localeCompare(b, undefined, { numeric: true, sensitivity: 'base' })`.
    let order = { (a: String, b: String) in JS.collate(a, b, locale: "", numeric: true, base: true) }
    JS.sort(&folders, by: order)
    JS.sort(&notes, by: order)

    let lines = folders.map { entryLink($0, "./\($0)/") }
      + notes.map { entryLink(String($0.dropLast(3)), "./\($0)") }
    let frontmatter = try await frontmatter(title: JS.trim(title), runtime: runtime)
    let body = "---\n\(frontmatter)---\n\n" + (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n")
    let path = "\(dir)/index.md"
    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o666)
    guard fd >= 0 else {
      if errno == EEXIST { throw .exists }
      throw .write(Posix.error("open", path).description)
    }
    defer { close(fd) }
    let data = Data(body.utf8)
    let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    guard written == data.count else { throw .write(Posix.error("write", path).description) }
    return Created(path: path, listSource: listed.source)
  }

  /// A markdown link rather than a wikilink, because a folder without index.md has no note to name.
  /// Angle brackets keep spaces and umlauts readable in Obsidian; a name that cannot sit inside
  /// them is percent-encoded instead, which Quartz resolves as well.
  static func entryLink(_ name: String, _ href: String) -> String {
    var text = ""
    for character in name {
      if character == "\\" || character == "[" || character == "]" { text.append("\\") }
      text.append(character)
    }
    let needsEncoding = href.unicodeScalars.contains { $0 == "<" || $0 == ">" || $0 == "\n" || $0 == "\r" }
    let target = needsEncoding
      ? href.split(separator: "/", omittingEmptySubsequences: false).map { encodeURIComponent(String($0)) }.joined(separator: "/")
      : "<\(href)>"
    return "- [\(text)](\(target))"
  }

  /// JavaScript's `encodeURIComponent`: everything but `A–Z a–z 0–9 - _ . ! ~ * ' ( )` as UTF-8
  /// percent escapes. A lone surrogate cannot occur in a Swift string, so it never throws here.
  static func encodeURIComponent(_ text: String) -> String {
    let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()".utf8)
    var out = ""
    for byte in text.utf8 {
      if unreserved.contains(byte) {
        out.append(Character(Unicode.Scalar(byte)))
      } else {
        out += String(format: "%%%02X", byte)
      }
    }
    return out
  }

  /// What Quartz's build reads under `cwd`, as paths with "/".
  static func inputFiles(project: String, cwd: String, patterns: [String], runtime: RuntimeLocation) async throws(Failure)
    -> (files: [String], source: ListSource) {
    // Not tried while npm unpacks: a fast-glob without its package.json reads as broken, and the
    // sentence would name npm install, which does not help then.
    if let unpacking = ProjectDependencies.halfUnpackedModule(project: project, "globby") { throw .unpacking(unpacking) }
    let request = JSONObject([
      ("op", .string("list")), ("project", .string(project)), ("cwd", .string(cwd)),
      ("patterns", .array(patterns.map(JSONValue.string))),
    ])
    let answer: JSONObject
    do {
      answer = try await Helper.call("content-files", request, runtime: runtime, timeout: .seconds(60))
    } catch {
      throw .helper(error.description)
    }
    if let broken = answer["broken"]?.stringValue { throw .globbyBroken(broken) }
    guard let source = answer["source"]?.stringValue.flatMap(ListSource.init(rawValue:)),
          case .array(let files)? = answer["files"] else { throw .helper("no list") }
    return (files.compactMap(\.stringValue), source)
  }

  /// `stringify({ title })` of the yaml package, as QuartzControl wrote it: quoting and folding are
  /// the library's, not to be guessed here.
  static func frontmatter(title: String, runtime: RuntimeLocation) async throws(Failure) -> String {
    let request = JSONObject([("op", .string("frontmatter")), ("value", .object(JSONObject([("title", .string(title))])))])
    let answer: JSONObject
    do {
      answer = try await Helper.call("content-files", request, runtime: runtime)
    } catch {
      throw .helper(error.description)
    }
    guard let text = answer["text"]?.stringValue else { throw .helper("no text") }
    return text
  }
}
