import CryptoKit
import Foundation

/// The fonts a project holds itself: a port of `fontService.ts`. An imported font goes into the
/// `fonts` block with the rule its file describes (`FontFile`); the Google fonts the typography
/// names go into a block of their own, `google-fonts`, with the files under quartz/static/fonts and
/// the request they came from as the block's first line. Every writer holds `ProjectLock.styles`.
///
/// Since QuartzControl 1.0.1 "serve fonts locally" means this, not Quartz's `cdnCaching: false`,
/// which pointed the local preview at the published site (all seven files 404 in gui-test before the
/// first publish).
public struct FontService: Sendable {
  // MARK: the network

  public struct Response: Sendable {
    public var status: Int
    /// Header names in lower case.
    public var headers: [String: String]
    public var body: Data
    public init(status: Int, headers: [String: String], body: Data) {
      self.status = status
      self.headers = headers
      self.body = body
    }
  }

  public enum FetchFailure: Error, Sendable { case timedOut, unreachable }

  /// One GET with a deadline over head and body, as QuartzControl's `AbortSignal.timeout` covered
  /// both: a network that hangs, hangs in the middle of a file as readily as before it.
  public typealias Fetch = @Sendable (_ url: String, _ userAgent: String?, _ timeout: Duration) async throws(FetchFailure) -> Response

  /// URLSession with the system's proxy settings and certificate store, the counterpart of
  /// Electron's `net.fetch` (which QuartzControl used for the same two reasons).
  public static let liveFetch: Fetch = { url, userAgent, timeout throws(FetchFailure) in
    guard let target = URL(string: url) else { throw .unreachable }
    var mutable = URLRequest(url: target)
    if let userAgent { mutable.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
    let request = mutable
    do {
      return try await withThrowingTaskGroup(of: Response.self) { group in
        group.addTask {
          let (data, response) = try await URLSession.shared.data(for: request)
          guard let http = response as? HTTPURLResponse else { throw FetchFailure.unreachable }
          var headers: [String: String] = [:]
          for (key, value) in http.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
          return Response(status: http.statusCode, headers: headers, body: data)
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw FetchFailure.timedOut
        }
        let first = try await group.next()!
        group.cancelAll()
        return first
      }
    } catch let failure as FetchFailure {
      throw failure
    } catch {
      throw .unreachable
    }
  }

  let fetch: Fetch
  let readConfig: LayoutFrames.ReadConfig
  let timeout: Duration

  public init(fetch: @escaping Fetch = FontService.liveFetch,
              readConfig: @escaping LayoutFrames.ReadConfig = { try await ConfigFile.read(project: $0) },
              timeout: Duration = .seconds(20)) {
    self.fetch = fetch
    self.readConfig = readConfig
    self.timeout = timeout
  }

  /// A sentence for the page or the log; QuartzControl threw `Error(mainT(…))`.
  public struct Failure: Error, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
  }

  // MARK: importing a font file

  static let formats = ["ttf": "truetype", "otf": "opentype", "woff": "woff", "woff2": "woff2"]

  public struct Imported: Equatable, Sendable {
    public var fileName: String
    public var face: FontFile.Face?
  }

  /// Copies the file into quartz/static/fonts and adds its rule to the `fonts` block, with what the
  /// file says about its weight and slant: without a weight the browser takes 400 and synthesises
  /// every bold cut, and two cuts of one family claim the same identity. A file past the size limit
  /// or one this cannot read gets the rule QuartzControl always wrote.
  public func importFontFile(_ source: URL, family: String, project: URL) async throws -> Imported {
    try await ProjectLock.styles.run(project.path) {
      let ext = String(NodePath.extname(source.path).dropFirst()).lowercased()
      let format = Self.formats[ext] ?? ext
      let dir = FontFaces.projectFontsDirectory(project)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let fileName = NodePath.basename(source.path)
      let target = dir.appendingPathComponent(fileName)
      if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
      try FileManager.default.copyItem(at: source, to: target)
      let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? Int.max
      let face = size <= FontFile.maxFileBytes ? (try? Data(contentsOf: source)).flatMap(FontFile.face) : nil
      var declarations = ["  font-family: \"\(family)\";", "  src: url(\"static/fonts/\(fileName)\") format(\"\(format)\");"]
      if let face { declarations.append("  font-weight: \(face.weight);") }
      if face?.italic == true { declarations.append("  font-style: italic;") }
      declarations.append("  font-display: swap;")
      let rule = "@font-face {\n\(declarations.joined(separator: "\n"))\n}"
      let existing = StyleSheets.managedBody(try StyleSheets.readSources(project: project), "fonts")
      // Rule by rule: the same file imported twice is the same face.
      let changes: [String: String?] = ["fonts": ManagedBlocks.joinUniqueRules([existing ?? "", rule])]
      try StyleSheets.writeManagedBlocksNow(changes, project: project)
      return Imported(fileName: fileName, face: face)
    }
  }

  // MARK: imported fonts nothing uses

  /// A stylesheet without its comments, strings kept: a comment names a font without using it.
  static func withoutComments(_ text: String) -> String {
    let any = #"[^\n\r\x{2028}\x{2029}]"#
    let pattern = #"("(?:[^"\\\n]|\\"# + any + #")*"|'(?:[^'\\\n]|\\"# + any + #")*')|/\*[\s\S]*?\*/|//[^\n]*"#
    var out = ""
    var last = 0
    for match in JSText.matches(text, pattern) {
      out += JSText.slice(text, last, match.index) + (match.groups[1] ?? " ")
      last = match.end
    }
    return out + JSText.slice(text, last)
  }

  /// JavaScript's case-insensitive comparison of one UTF-16 unit (Canonicalize, non-unicode
  /// mode): its upper case when that is one unit, and not when a non-ASCII unit would become ASCII.
  static func canonical(_ unit: UInt16) -> UInt16 {
    guard let scalar = Unicode.Scalar(unit) else { return unit }
    let upper = Array(String(scalar).uppercased().utf16)
    guard upper.count == 1 else { return unit }
    if unit >= 128 && upper[0] < 128 { return unit }
    return upper[0]
  }

  static func isWordOrDash(_ unit: UInt16) -> Bool {
    (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) || unit == 0x5F || unit == 0x2D
  }

  /// The family as a name of its own, any case: "Inter" in `"Inter", sans-serif`, not in
  /// "Interstate" (`/(^|[^\w-])family(?![\w-])/i`).
  static func mentions(_ text: [UInt16], _ canonicalText: [UInt16], _ family: String) -> Bool {
    let needle = family.utf16.map(canonical)
    guard needle.count <= text.count else { return false }
    if needle.isEmpty { return true }
    var start = 0
    while start + needle.count <= text.count {
      if canonicalText[start..<(start + needle.count)].elementsEqual(needle) {
        let before = start == 0 || !isWordOrDash(text[start - 1])
        let after = start + needle.count == text.count || !isWordOrDash(text[start + needle.count])
        if before && after { return true }
      }
      start += 1
    }
    return false
  }

  public struct Unused: Equatable, Sendable {
    public var family: String
    public var files: [String]
  }

  /// The families of the `fonts` block nothing names: no typography slot (`draftFamilies` are the
  /// slots as the page shows them, unsaved included), no stylesheet under quartz/styles,
  /// quartz/components/styles or quartz/static, no variable. With the files that would go with them.
  public func unusedImportedFonts(project: URL, draftFamilies: [String]) async throws -> [Unused] {
    let sources = try StyleSheets.readSources(project: project)
    guard let body = StyleSheets.managedBody(sources, "fonts"), !body.isEmpty else { return [] }
    var texts = [Self.withoutComments(StyleSheets.sourcesWithout(sources, "fonts"))]
    let custom = NodePath.normalize(StyleSheets.customScss(project).path), managed = NodePath.normalize(StyleSheets.managedScss(project).path)
    for path in FontFaces.allStylesheets(project: project) where path != custom && path != managed {
      texts.append(Self.withoutComments(try StyleSheets.readText(URL(fileURLWithPath: path))))
    }
    var typography: [JSONValue] = []
    if let config = try? await readConfig(project.path) {
      switch config.theme["typography"] {
      case .object(let object)?: typography = object.keys.map { object[$0]! }
      case .array(let items)?: typography = items
      case .string(let text)?: typography = text.utf16.map { .string(String(decoding: [$0], as: UTF16.self)) }
      default: break
      }
    }
    for spec in typography + draftFamilies.map({ .string($0) }) {
      if case .string(let name) = spec { texts.append(name) }
      else if case .string(let name)? = spec[safe: "name"] { texts.append(name) }
    }
    let everything = Array(texts.joined(separator: "\n").utf16)
    let canonicalEverything = everything.map(Self.canonical)

    var order: [String] = []
    var rulesOf: [String: [String]] = [:]
    for rule in ManagedBlocks.splitRules(body) {
      var seen: [String] = []
      for face in FontFaces.parse(rule) where !seen.contains(face.family) { seen.append(face.family) }
      for family in seen {
        if rulesOf[family] == nil { order.append(family) }
        rulesOf[family, default: []].append(rule)
      }
    }
    return try order.filter { !Self.mentions(everything, canonicalEverything, $0) }.map { family in
      let rules = rulesOf[family]!
      let stillNamed = try fontFilesStillNamed(project, except: rules)
      var files: [String] = []
      for file in fontFilesNamed(project, rules.joined(separator: "\n"), protecting: false) where !stillNamed.contains(file) {
        let name = NodePath.basename(file)
        if !files.contains(name) { files.append(name) }
      }
      return Unused(family: family, files: files)
    }
  }

  /// Takes a family's rules out of the `fonts` block and deletes the files only they named.
  public func removeImportedFont(_ family: String, project: URL) async throws -> [String] {
    try await ProjectLock.styles.run(project.path) {
      let body = StyleSheets.managedBody(try StyleSheets.readSources(project: project), "fonts") ?? ""
      let rules = ManagedBlocks.splitRules(body)
      let wanted = family.lowercased()
      let isFamily = { (rule: String) in FontFaces.parse(rule).contains { $0.family.lowercased() == wanted } }
      let removed = rules.filter(isFamily)
      if removed.isEmpty { return [] }
      let changes: [String: String?] = ["fonts": ManagedBlocks.joinUniqueRules(rules.filter { !isFamily($0) })]
      try StyleSheets.writeManagedBlocksNow(changes, project: project)
      return try deleteUnreferencedFontFiles(project, removed.joined(separator: "\n"))
    }
  }

  /// The files the rules in `css` point at, as paths in the fonts folder, every url() of a rule.
  /// `protecting` adds the bare file name of any url(), resolving or not: `url("#{$f}/x.woff2")` is
  /// a path Sass builds, and a name too many protects a file nobody uses where one too few deletes
  /// one the site needs.
  func fontFilesNamed(_ project: URL, _ css: String, protecting: Bool) -> [String] {
    let dir = NodePath.normalize(FontFaces.projectFontsDirectory(project).path)
    var files: [String] = []
    func add(_ file: String) { if !files.contains(file) { files.append(file) } }
    for face in FontFaces.parse(css) {
      for url in face.urls {
        if let file = FontFaces.fileIn(dir, url) { add(file) }
        guard protecting else { continue }
        let named = JSText.split(JSText.replaceAll(url, #"\\"#, with: "/"), "/").last ?? ""
        if !named.isEmpty { add(NodePath.join(dir, named)) }
      }
    }
    return files
  }

  /// Every file any stylesheet still points at; `except` are rules taken out of the two managed
  /// files first (the ones about to go), each rule on its own.
  func fontFilesStillNamed(_ project: URL, except: [String] = []) throws -> Set<String> {
    var named: Set<String> = []
    let custom = NodePath.normalize(StyleSheets.customScss(project).path), managed = NodePath.normalize(StyleSheets.managedScss(project).path)
    for path in FontFaces.allStylesheets(project: project) {
      var css = try StyleSheets.readText(URL(fileURLWithPath: path))
      if path == custom || path == managed {
        for rule in except { css = (css as NSString).replacingOccurrences(of: rule, with: "", options: .literal, range: NSRange(location: 0, length: JSText.length(css))) }
      }
      named.formUnion(fontFilesNamed(project, css, protecting: true))
    }
    return named
  }

  /// The files a template import would delete by replacing the rules `previous` with `incoming`;
  /// only reads.
  public func fontFilesReplacedRulesWouldRemove(previous: String, incoming: String, project: URL) throws -> [String] {
    var stillNamed = try fontFilesStillNamed(project, except: ManagedBlocks.splitRules(previous))
    stillNamed.formUnion(fontFilesNamed(project, incoming, protecting: true))
    var out: [String] = []
    for file in fontFilesNamed(project, previous, protecting: false) {
      let name = NodePath.basename(file)
      if stillNamed.contains(file) || out.contains(name) || !FileManager.default.fileExists(atPath: file) { continue }
      out.append(name)
    }
    return out
  }

  public func deleteFontFilesOfReplacedRules(_ previous: String, project: URL) async throws -> [String] {
    try await ProjectLock.styles.run(project.path) { try deleteUnreferencedFontFiles(project, previous) }
  }

  /// Deletes the files the rules in `css` pointed at that no rule in any stylesheet still names.
  func deleteUnreferencedFontFiles(_ project: URL, _ css: String) throws -> [String] {
    let stillNamed = try fontFilesStillNamed(project)
    var removed: [String] = []
    for file in fontFilesNamed(project, css, protecting: false) {
      let name = NodePath.basename(file)
      if stillNamed.contains(file) || removed.contains(name) { continue }
      try? FileManager.default.removeItem(atPath: file)
      removed.append(name)
    }
    return removed
  }

  // MARK: Google fonts

  /// Google answers with the format the User-Agent reads: a browser gets woff2 split by
  /// unicode-range. QuartzControl's string, kept.
  static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  static let gstaticUrl = "url\\([\(JSText.space)]*(https://fonts\\.gstatic\\.com/[^)\(JSText.space)'\"]+)[\(JSText.space)]*\\)"
  /// Dots inside the name (Google names a CJK slice `<hash>.<n>.woff2`), never a leading one.
  static let fontFileName = #"\A[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\.(?:woff2|woff|ttf|otf)\z"#
  /// What four CJK families cost (439 to 495 files measured), with room; the bytes are the ceiling
  /// with room to spare (all 124 files of Noto Sans JP are 5.4 MB).
  static let maxFiles = 800
  static let maxTotalBytes = 128 * 1024 * 1024
  /// One rule of Google's answer with the comment above it.
  static let googleRule = #"(?:/\*[^*]*\*/["# + JSText.space + #"]*)?@font-face["# + JSText.space + #"]*\{[^}]*\}["# + JSText.space + #"]*"#
  /// Both sentences are part of the block's format: both apps read them back (`ownPrintOf`, the
  /// comparison with `nothingFromGoogle`), so they keep QuartzControl's wording.
  static let nothingFromGoogle = "/* QuartzControl: every family is declared by the project itself, nothing is fetched from Google */"
  static let ownRulesNote = "QuartzControl: left out what the project's own rules cover"

  public struct Fetched: Equatable, Sendable {
    public var changed: Bool
    public var files: [String] = []
    public var removedFiles: [String] = []
    public var removedFamilies: [String] = []
    public var missingFamilies: [String] = []
    public var ownFamilies: [String] = []
    public var coveredFamilies: [String] = []
  }

  static func hasGoogleBlock(_ sources: StyleSheets.Sources) -> Bool {
    StyleSheets.managedBody(sources, "google-fonts") != nil
  }

  static func requestOf(_ body: String?) -> String? {
    guard let body, !body.isEmpty else { return nil }
    return JSText.firstMatch(body, #"\A["# + JSText.space + #"]*/\*["# + JSText.space + #"]*(https://fonts\.googleapis\.com/[^"# + JSText.space + #"]+)["# + JSText.space + #"]*\*/"#)?.groups[1]
  }

  static func ownPrintOf(_ body: String) -> String {
    JSText.firstMatch(body, "left out what the project's own rules cover ([0-9a-f]+)")?.groups[1] ?? ""
  }

  /// "The file is there" is not "the file can be read": a zero-byte file under the right name is
  /// fetched again.
  static func usableFile(_ path: String) -> Bool {
    ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0) > 0
  }

  func allFilesPresent(_ project: URL, _ body: String) -> Bool {
    let dir = NodePath.normalize(FontFaces.projectFontsDirectory(project).path)
    return FontFaces.parse(body).allSatisfy { face in FontFaces.fileIn(dir, face.url).map(Self.usableFile) ?? false }
  }

  /// One file, written beside its name and renamed into place, so a broken-off download never
  /// leaves a torso the next call would take for the file.
  func download(_ url: String, to target: String) async throws -> Int {
    let file = NodePath.basename(target)
    let response: Response
    do {
      response = try await fetch(url, nil, timeout)
    } catch {
      throw Failure(message: error == .timedOut ? L10n.t("main.googleFontsFileTimedOut", ["file": file]) : L10n.t("main.googleFontsFileUnreachable", ["file": file]))
    }
    guard (200..<300).contains(response.status) else {
      throw Failure(message: L10n.t("main.googleFontsFileFailed", ["file": file, "status": String(response.status)]))
    }
    let declared = JS.toNumber(.string(response.headers["content-length"] ?? "0"))
    if declared > Double(FontFile.maxFileBytes) || response.body.count > FontFile.maxFileBytes {
      throw Failure(message: L10n.t("main.googleFontsFileTooLarge", ["file": file]))
    }
    let temp = NodePath.join(NodePath.normalize((target as NSString).deletingLastPathComponent), ".\(file).download")
    try response.body.write(to: URL(fileURLWithPath: temp))
    if FileManager.default.fileExists(atPath: target) { try FileManager.default.removeItem(atPath: target) }
    try FileManager.default.moveItem(atPath: temp, toPath: target)
    return response.body.count
  }

  /// Fetches the Google fonts the typography names into the project and writes their block. Does
  /// nothing when the block answers the same request and all its files are there, which makes it
  /// cheap enough for every build. Files the previous block named and no rule names any more go.
  public func fetchGoogleFonts(_ typography: JSONObject, project: URL) async throws -> Fetched {
    try await ProjectLock.styles.run(project.path) { try await fetchGoogleFontsNow(typography, project: project) }
  }

  func fetchGoogleFontsNow(_ typography: JSONObject, project: URL) async throws -> Fetched {
    guard GoogleFontRequest.css2Url(typography) != nil else { throw Failure(message: L10n.t("main.googleFontsNoFamily")) }
    let current = try StyleSheets.readSources(project: project)
    // What the project declares itself is not asked of Google again; but "declares the family" is
    // not "covers what Google would send": a family with an own rule *without* unicode-range is
    // left out whole, any other is asked, and out of the answer go only the rules an own rule
    // already covers (a Latin-only template rule must not take Cyrillic off the site).
    let ownFaces = FontFaces.parse(StyleSheets.sourcesWithout(current, "google-fonts"))
    let own = Set(ownFaces.map { $0.family.lowercased() })
    var ownFamiliesAsked: [String] = []
    var wanted = typography
    for role in GoogleFontRequest.roles {
      guard let family = GoogleFontRequest.request(role, typography[role]).map({ JS.trim($0.family) }), !family.isEmpty else { continue }
      if ownFaces.contains(where: { $0.family.lowercased() == family.lowercased() && $0.unicodeRange == nil }) {
        wanted[role] = nil
        if !ownFamiliesAsked.contains(family) { ownFamiliesAsked.append(family) }
      }
    }
    let request = GoogleFontRequest.css2Url(wanted)
    let before = StyleSheets.managedBody(current, "google-fonts")
    guard let request else {
      if let before, JS.trim(before) == Self.nothingFromGoogle { return Fetched(changed: false, ownFamilies: ownFamiliesAsked) }
      let previous = StyleSheets.managedBody(try StyleSheets.readSources(project: project), "google-fonts") ?? ""
      let changes: [String: String?] = ["google-fonts": Self.nothingFromGoogle]
      try StyleSheets.writeManagedBlocksNow(changes, project: project)
      return Fetched(changed: true, removedFiles: try deleteUnreferencedFontFiles(project, previous),
                     removedFamilies: FontFaces.families(previous).filter { !own.contains($0.lowercased()) }, ownFamilies: ownFamiliesAsked)
    }
    let askedFamilies = Set(GoogleFontRequest.roles.compactMap { GoogleFontRequest.request($0, wanted[$0]).map { JS.trim($0.family).lowercased() } }.filter { !$0.isEmpty })
    let relevantOwn = ownFaces.filter { askedFamilies.contains($0.family.lowercased()) }
    let ownPrint = Self.ownRulesPrint(relevantOwn)
    if let before, !before.isEmpty, Self.requestOf(before) == request, Self.ownPrintOf(before) == ownPrint, allFilesPresent(project, before) {
      return Fetched(changed: false, missingFamilies: Self.notDelivered(typography, before, StyleSheets.sourcesWithout(current, "google-fonts")),
                     ownFamilies: ownFamiliesAsked)
    }

    // "Not reachable" and "refused" are two ways to fail and get two sentences.
    let response: Response
    do {
      response = try await fetch(request, Self.browserUserAgent, timeout)
    } catch {
      throw Failure(message: error == .timedOut ? L10n.t("main.googleFontsTimedOut") : L10n.t("main.googleFontsUnreachable"))
    }
    guard (200..<300).contains(response.status) else {
      throw Failure(message: L10n.t("main.googleFontsRequestFailed", ["status": String(response.status)]))
    }
    let css = String(decoding: response.body, as: UTF8.self)
    if JSText.matches(css, Self.gstaticUrl).isEmpty { throw Failure(message: L10n.t("main.googleFontsNothingFound")) }

    var coveredFamilies: [String] = []
    var answer = ""
    var last = 0
    for match in JSText.matches(css, Self.googleRule) {
      let rule = match.groups[0]!
      answer += JSText.slice(css, last, match.index)
      if let face = FontFaces.parse(rule).first, Self.coveredByOwn(face, relevantOwn) {
        if !coveredFamilies.contains(face.family) { coveredFamilies.append(face.family) }
      } else {
        answer += rule
      }
      last = match.end
    }
    answer += JSText.slice(css, last)

    var urls: [(url: String, name: String)] = []
    for match in JSText.matches(answer, Self.gstaticUrl) {
      let url = match.groups[1]!
      let name: String
      do {
        name = try JSURI.decodeComponent(JSText.split(url, "/").last ?? "")
      } catch {
        throw Failure(message: "URI malformed")
      }
      // A name this cannot use is an error: skipped, its rule kept Google's address, and the site
      // that "serves locally" loaded from Google on every build.
      if !JSText.test(name, Self.fontFileName) {
        throw Failure(message: L10n.t("main.googleFontsBadFileName", ["name": JSText.slice(name, 0, 80)]))
      }
      if let index = urls.firstIndex(where: { $0.url == url }) { urls[index].name = name } else { urls.append((url, name)) }
    }
    if urls.count > Self.maxFiles {
      throw Failure(message: L10n.t("main.googleFontsTooManyFiles", ["count": String(urls.count), "max": String(Self.maxFiles)]))
    }

    let dir = NodePath.normalize(FontFaces.projectFontsDirectory(project).path)
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    // Google's names are content hashes: a readable file of that name is the same file. What this
    // run wrote goes again when it breaks off, so half a set never stands under no rule.
    var total = 0
    var written: [String] = []
    do {
      for (url, name) in urls {
        let target = NodePath.join(dir, name)
        if Self.usableFile(target) { continue }
        total += try await download(url, to: target)
        written.append(target)
        if total > Self.maxTotalBytes { throw Failure(message: L10n.t("main.googleFontsTooLarge")) }
      }
    } catch {
      for file in written { try? FileManager.default.removeItem(atPath: file) }
      throw error
    }

    var body = answer
    for (url, name) in urls {
      body = (body as NSString).replacingOccurrences(of: url, with: "static/fonts/\(name)", options: .literal, range: NSRange(location: 0, length: JSText.length(body)))
    }
    let head = ownPrint.isEmpty ? "/* \(request) */" : "/* \(request) */\n/* \(Self.ownRulesNote) \(ownPrint) */"
    let trimmedBody = JS.trim(body)
    let block = trimmedBody.isEmpty ? head : "\(head)\n\(trimmedBody)"
    // Read again: the downloads took a while, the stylesheets may have been written meanwhile.
    let latest = try StyleSheets.readSources(project: project)
    let previous = StyleSheets.managedBody(latest, "google-fonts") ?? ""
    let changes: [String: String?] = ["google-fonts": block]
    try StyleSheets.writeManagedBlocksNow(changes, project: project)
    let kept = Set(FontFaces.families(block).map { $0.lowercased() }).union(own)
    let removedFiles = try deleteUnreferencedFontFiles(project, previous)
    return Fetched(changed: true, files: urls.map(\.name), removedFiles: removedFiles,
                   removedFamilies: FontFaces.families(previous).filter { !kept.contains($0.lowercased()) },
                   missingFamilies: Self.notDelivered(typography, block, StyleSheets.sourcesWithout(latest, "google-fonts")),
                   ownFamilies: ownFamiliesAsked, coveredFamilies: coveredFamilies)
  }

  /// The own rules that can leave something out, as a short fingerprint in the block's head: when
  /// they change, the same request has a different answer.
  static func ownRulesPrint(_ faces: [FontFaces.Face]) -> String {
    guard !faces.isEmpty else { return "" }
    var rows = faces.map { [$0.family.lowercased(), $0.style.lowercased(), $0.weight, $0.unicodeRange ?? ""].joined(separator: "|") }
    rows.sort { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    let digest = Insecure.SHA1.hash(data: Data(rows.joined(separator: "\n").utf8))
    return String(digest.map { String(format: "%02x", $0) }.joined().prefix(12))
  }

  /// Whether the project's own rules cover a rule of Google's answer: same family and style, its
  /// weight inside theirs, its characters inside the union of their ranges. Every doubt keeps it.
  static func coveredByOwn(_ face: FontFaces.Face, _ own: [FontFaces.Face]) -> Bool {
    guard let weight = weightRange(face.weight), case .some(let chars) = unicodeIntervals(face.unicodeRange) else { return false }
    let matching = own.filter { candidate in
      guard let range = weightRange(candidate.weight) else { return false }
      return candidate.family.lowercased() == face.family.lowercased() && candidate.style.lowercased() == face.style.lowercased()
        && range.0 <= weight.0 && weight.1 <= range.1
    }
    var union: [(Double, Double)] = []
    for candidate in matching {
      switch unicodeIntervals(candidate.unicodeRange) {
      case .some(nil): return true
      case .some(let ranges?): union.append(contentsOf: ranges)
      case nil: break
      }
    }
    guard let chars else { return false }
    return coveredByUnion(chars, union)
  }

  static func coveredByUnion(_ inner: [(Double, Double)], _ outer: [(Double, Double)]) -> Bool {
    var sorted = outer
    JS.sort(&sorted) { $0.0 - $1.0 }
    var merged: [(Double, Double)] = []
    for (a, b) in sorted {
      if let last = merged.last, a <= last.1 + 1 { merged[merged.count - 1].1 = max(last.1, b) } else { merged.append((a, b)) }
    }
    return inner.allSatisfy { lo, hi in merged.contains { a, b in a <= lo && hi <= b } }
  }

  /// `.some(nil)` for a rule without unicode-range (it covers everything), nil if unreadable.
  static func unicodeIntervals(_ range: String?) -> [(Double, Double)]?? {
    guard let range else { return .some(nil) }
    var out: [(Double, Double)] = []
    for token in JSText.split(range, ",") {
      guard let match = JSText.firstMatch(token, #"\A["# + JSText.space + #"]*[Uu]\+([0-9A-Fa-f?]{1,6})(?:-([0-9A-Fa-f]{1,6}))?["# + JSText.space + #"]*\z"#),
            let first = match.groups[1] else { return nil }
      let lo = Double(Int(first.replacingOccurrences(of: "?", with: "0"), radix: 16) ?? 0)
      let hi = match.groups[2].map { Double(Int($0, radix: 16) ?? 0) } ?? Double(Int(first.replacingOccurrences(of: "?", with: "F"), radix: 16) ?? 0)
      out.append((lo, hi))
    }
    return .some(out)
  }

  static func weightRange(_ weight: String) -> (Double, Double)? {
    // `weight.trim().split(/\s+/)`: an empty weight is one empty token, which Number() reads as 0.
    let parts = JSText.matches(JS.trim(weight), "[^\(JSText.space)]+").map { $0.groups[0]! }
    let tokens = parts.isEmpty ? [""] : parts
    let values = tokens.map { token -> Double in
      switch token.lowercased() {
      case "normal": 400
      case "bold": 700
      default: JS.toNumber(.string(token))
      }
    }
    guard !values.isEmpty, values.count <= 2, values.allSatisfy(\.isFinite) else { return nil }
    return (values[0], values[values.count - 1])
  }

  /// The families asked for that are not in the answer and not declared by the project itself: a
  /// misspelt name comes back as a silent omission (Google answers 200 when one family matches).
  static func notDelivered(_ typography: JSONObject, _ block: String, _ ownCss: String) -> [String] {
    var delivered = Set(FontFaces.families(block).map { $0.lowercased() })
    for family in FontFaces.families(ownCss) { delivered.insert(family.lowercased()) }
    var asked: [String] = []
    for role in GoogleFontRequest.roles {
      guard let family = GoogleFontRequest.request(role, typography[role]).map({ JS.trim($0.family) }), !family.isEmpty else { continue }
      if !asked.contains(family) { asked.append(family) }
    }
    return asked.filter { !delivered.contains($0.lowercased()) }
  }

  public struct Dropped: Equatable, Sendable {
    public var dropped: Bool
    public var removedFiles: [String]
    public var removedFamilies: [String]
  }

  /// Removes the Google block and every file of it no other rule names.
  public func dropGoogleFonts(project: URL) async throws -> Dropped {
    try await ProjectLock.styles.run(project.path) {
      guard let body = StyleSheets.managedBody(try StyleSheets.readSources(project: project), "google-fonts") else {
        return Dropped(dropped: false, removedFiles: [], removedFamilies: [])
      }
      let none: String? = nil
      let changes: [String: String?] = ["google-fonts": none]
      try StyleSheets.writeManagedBlocksNow(changes, project: project)
      return Dropped(dropped: true, removedFiles: try deleteUnreferencedFontFiles(project, body), removedFamilies: FontFaces.families(body))
    }
  }

  /// The build door's guard: a project that holds its Google fonts (`fontOrigin: local` and the
  /// block) gets them in line with the config, which reaches the typography through more doors
  /// than the Basis tab. Never throws: a failed fetch is a sentence, and the build goes on with the
  /// files that are there. Under the lock from the first read: a template import takes the block
  /// out for the length of two writes.
  public func refreshGoogleFonts(project: URL) async -> (failed: Bool, text: String)? {
    do {
      return try await ProjectLock.styles.run(project.path) { () async throws -> (failed: Bool, text: String)? in
        guard Self.hasGoogleBlock(try StyleSheets.readSources(project: project)) else { return nil }
        let config = try await readConfig(project.path)
        guard config.theme["fontOrigin"] == .string("local") else { return nil }
        let result = try await fetchGoogleFontsNow(config.theme["typography"]?.objectValue ?? JSONObject(), project: project)
        guard result.changed else { return nil }
        // A run that deletes says so, also when it fetched nothing.
        var own = result.ownFamilies
        for family in result.coveredFamilies where !own.contains(family) { own.append(family) }
        var sentences: [String] = []
        if !result.files.isEmpty { sentences.append(L10n.t("main.googleFontsRefreshed", ["count": String(result.files.count)])) }
        if !own.isEmpty { sentences.append(L10n.t("main.googleFontsRefreshOwn", ["families": own.joined(separator: ", ")])) }
        if !result.removedFiles.isEmpty { sentences.append(L10n.t("main.googleFontsRefreshRemoved", ["count": String(result.removedFiles.count)])) }
        return sentences.isEmpty ? nil : (false, sentences.joined(separator: " "))
      }
    } catch {
      let message: String
      switch error {
      case let failure as Failure: message = failure.message
      case let failure as ConfigFile.Failure: message = failure.message
      default: message = error.localizedDescription
      }
      return (true, L10n.t("main.googleFontsRefreshFailed", ["message": message]))
    }
  }
}
