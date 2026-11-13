import Foundation

/// QuartzControl's `localizationService.ts`: Quartz's own locale files
/// (`quartz/i18n/locales/*.ts`, without `definition.ts`), read and edited in place. Quartz has no
/// override layer, so an edit goes into its tracked file; `merge=ours` in `.gitattributes` plus the
/// merge driver in the repository's config is what keeps it through a core update.
///
/// The files are TypeScript, and the helper `locale-edit` reads them with the TypeScript compiler
/// of QuartzControl's version, so the entries and the spliced bytes are the same. Everything else
/// happens here: reading and writing the files, the baseline, git.
public struct LocaleFiles: Sendable {
  public enum Kind: String, Sendable { case string, template }

  /// One leaf of the default-exported object: a string, or the source text of anything else
  /// (an arrow function, a call).
  public struct Entry: Sendable, Equatable {
    public var path: [String]
    public var kind: Kind
    public var value: String
  }

  /// The English sentences are QuartzControl's: the channel answered them as they are. `failure`
  /// says the same for the app to put in its own words (review 2026-11-13, nebenbei: the tab
  /// showed these English sentences in German too).
  public struct SaveResult: Sendable, Equatable {
    public var success: Bool
    public var error: String?
    public var failure: Failure?

    public enum Failure: Sendable, Equatable {
      case fileMissing(code: String)
      case noTranslationObject
      case keyMissing(key: String)
      /// TypeScript's message, which has no other words.
      case syntax(String)
    }

    init(success: Bool, error: String?, failure: Failure? = nil) {
      self.success = success
      self.error = error
      self.failure = failure
    }
  }

  /// Where "unchanged" came from: a copy taken before the first edit, git's HEAD, or nowhere.
  /// Told to the user, because "nothing changed" and "cannot tell" are two answers.
  public enum BaselineSource: String, Sendable { case baseline, git, none }

  public struct Customizations: Sendable, Equatable {
    public var code: String
    public var source: BaselineSource
    /// Entries whose value differs from the baseline; empty for `none`, which is "cannot tell".
    public var changed: [Entry]
    public var total: Int
  }

  public let environment: ToolEnvironment

  public init(environment: ToolEnvironment) {
    self.environment = environment
  }

  static let mergeOursLine = "quartz/i18n/locales/*.ts merge=ours"
  static let baselineDirectory = "locale-baseline"

  static func localesDirectory(_ project: String) -> String { "\(project)/quartz/i18n/locales" }
  static func localeFile(_ project: String, _ code: String) -> String { "\(localesDirectory(project))/\(code).ts" }
  static func baselineFile(_ project: String, _ code: String) -> String {
    "\(QuartzGuiDirectory(project: project).path)/\(baselineDirectory)/\(code).ts"
  }

  /// `isLocaleCode` of QuartzControl's IPC contract: only what the save path accepts is a locale.
  public static func isLocaleCode(_ code: String) -> Bool {
    let length = code.utf16.count
    guard length >= 2, length <= 35 else { return false }
    let segments = code.split(separator: "-", omittingEmptySubsequences: false)
    let letters = { (s: Substring) in s.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) } }
    let alphanumerics = { (s: Substring) in s.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) } }
    guard (2...3).contains(segments[0].count), letters(segments[0]) else { return false }
    return segments.dropFirst().allSatisfy { (2...8).contains($0.count) && alphanumerics($0) }
  }

  // MARK: - Reading

  /// Every `<code>.ts` but `definition.ts` whose name is a locale code, sorted as `localeCompare`.
  public func list(project: String) throws -> [String] {
    let dir = Self.localesDirectory(project)
    guard FileManager.default.fileExists(atPath: dir) else { return [] }
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
      throw NodeFileError(code: ENOTDIR, syscall: "scandir", path: dir)
    }
    return names.filter { $0.hasSuffix(".ts") && $0 != "definition.ts" }
      .map { String($0.dropLast(3)) }
      .filter(Self.isLocaleCode)
      .sorted(by: Snippets.localeOrder)
  }

  /// `readFileSync(path, 'utf-8')`: a folder fails as in Node, without a path.
  static func readText(_ url: String) throws -> String {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url, isDirectory: &isDirectory), isDirectory.boolValue {
      throw NodeFileError(code: EISDIR, syscall: "read")
    }
    // With the system's reason: `FileManager.contents` gives none, and a locked file read
    // "ENOENT: no such file or directory" where Node says EACCES (measured 2026-11-09).
    return String(decoding: try Posix.read(url), as: UTF8.self)
  }

  /// The entries of several texts in one helper call; nil where the file has no default-exported object.
  func parse(_ texts: [(text: String, fileName: String)]) async throws -> [[Entry]?] {
    guard !texts.isEmpty else { return [] }
    let calls = texts.map { JSONValue.object(JSONObject([("kind", .string("entries")), ("text", .string($0.text)), ("fileName", .string($0.fileName))])) }
    let answer = try await Helper.call("locale-edit", JSONObject([("calls", .array(calls))]), runtime: environment.runtime)
    return (answer["results"]?.arrayValue ?? []).map { result in
      guard let entries = result["entries"]?.arrayValue else { return nil }
      return entries.map { entry in
        Entry(path: (entry["path"]?.arrayValue ?? []).compactMap(\.stringValue), kind: Kind(rawValue: entry["kind"]?.stringValue ?? "") ?? .template,
              value: entry["value"]?.stringValue ?? "")
      }
    }
  }

  /// A code that is no locale code is no file here, whoever asks. QuartzControl's IPC schema
  /// checked it for the Translations page, but its template import passed a package's code on
  /// unchecked, and `../../util/path` reached `quartz/util/path.ts`.
  public func entries(project: String, code: String) async throws -> [Entry] {
    let file = Self.localeFile(project, code)
    guard Self.isLocaleCode(code), FileManager.default.fileExists(atPath: file) else { return [] }
    return try await parse([(try Self.readText(file), file)]).first.flatMap { $0 } ?? []
  }

  // MARK: - Saving

  /// Replaces one value, only its span: everything else in the file stays byte for byte. A string
  /// goes in as JSON, a template as written; the whole result must parse, or nothing is written.
  public func save(project: String, code: String, path: [String], kind: Kind, value: String) async throws -> SaveResult {
    let file = Self.localeFile(project, code)
    guard Self.isLocaleCode(code), FileManager.default.fileExists(atPath: file) else {
      return SaveResult(success: false, error: "Locale file not found: \(code)", failure: .fileMissing(code: code))
    }
    // Before the first edit, not after: once the file is written the untouched version is gone.
    // Also when the save below fails, as in QuartzControl.
    try captureBaseline(project, code)
    let text = try Self.readText(file)
    let replacement = kind == .string ? JSJSON.compact(.string(value)) : value
    let call = JSONObject([("kind", .string("splice")), ("text", .string(text)), ("fileName", .string(file)),
                           ("path", .array(path.map(JSONValue.string))), ("replacement", .string(replacement))])
    let answer = try await Helper.call("locale-edit", JSONObject([("calls", .array([.object(call)]))]), runtime: environment.runtime)
    let result = answer["results"]?.arrayValue?.first ?? .null
    if result["noRoot"] == .bool(true) { return SaveResult(success: false, error: "Could not find the default-exported translation object", failure: .noTranslationObject) }
    if result["notFound"] == .bool(true) { return SaveResult(success: false, error: "Key not found: \(path.joined(separator: "."))", failure: .keyMissing(key: path.joined(separator: "."))) }
    if let syntax = result["syntax"]?.stringValue { return SaveResult(success: false, error: syntax, failure: .syntax(syntax)) }
    guard let next = result["text"]?.stringValue else { throw Helper.Failure.refused("locale-edit answered no text") }
    // In place, as writeFileSync.
    try Posix.write(file, Data(next.utf8))
    await ensureGitAttributes(project: project)
    return SaveResult(success: true, error: nil)
  }

  /// A copy of the file as it was before QuartzHub (or QuartzControl) first edited it: the only
  /// exact answer to "what did the user change", once the edit is committed and merge=ours keeps it.
  func captureBaseline(_ project: String, _ code: String) throws {
    let source = Self.localeFile(project, code)
    guard FileManager.default.fileExists(atPath: source), !FileManager.default.fileExists(atPath: Self.baselineFile(project, code)) else { return }
    let dir = try QuartzGuiDirectory(project: project).create(Self.baselineDirectory)
    // The bytes, as copyFileSync: a locale file that is a symlink is copied as what it points to.
    try Posix.write("\(dir)/\(code).ts", Posix.read(source))
  }

  // MARK: - What the user changed

  /// The second-best baseline: when the working tree differs from HEAD for that file, HEAD holds
  /// the version before the edits. A file equal to HEAD says nothing (the edits may be committed).
  func gitBaseline(_ project: String, _ code: String) async -> String? {
    let relative = "quartz/i18n/locales/\(code).ts"
    let status = await ProcessRunner.run(environment.command("git", ["status", "--porcelain", "--", relative], in: project, timeout: .seconds(30)))
    guard status.success, !JS.trim(status.output).isEmpty else { return nil }
    let show = await ProcessRunner.run(environment.command("git", ["show", "HEAD:\(relative)"], in: project, timeout: .seconds(30)))
    return show.success ? show.output : nil
  }

  public func customizations(project: String) async throws -> [Customizations] {
    var texts: [(text: String, fileName: String)] = []
    var sources: [(code: String, source: BaselineSource)] = []
    for code in try list(project: project) {
      let current = Self.localeFile(project, code)
      texts.append((try Self.readText(current), current))
      let stored = Self.baselineFile(project, code)
      if FileManager.default.fileExists(atPath: stored) {
        texts.append((try Self.readText(stored), stored))
        sources.append((code, .baseline))
      } else if let text = await gitBaseline(project, code) {
        texts.append((text, stored))
        sources.append((code, .git))
      } else {
        sources.append((code, .none))
      }
    }
    var parsed = try await parse(texts)[...]
    var out: [Customizations] = []
    for (code, source) in sources {
      let current = parsed.popFirst().flatMap { $0 } ?? []
      var changed: [Entry] = []
      if source != .none {
        var before: [String: Entry] = [:]
        for entry in parsed.popFirst().flatMap({ $0 }) ?? [] { before[entry.path.joined(separator: ".")] = entry }
        // A key the baseline lacks came with a Quartz update; only a differing value is an edit.
        changed = current.filter { entry in before[entry.path.joined(separator: ".")].map { $0.value != entry.value } ?? false }
      }
      out.append(Customizations(code: code, source: source, changed: changed, total: current.count))
    }
    return out
  }

  // MARK: - merge=ours

  /// `merge=ours` names a driver git does not ship: the line alone is inert (measured in
  /// QuartzControl against git 2.50.1), so both halves count.
  func hasMergeDriver(_ project: String) async -> Bool {
    let result = await ProcessRunner.run(environment.command("git", ["config", "--get", "merge.ours.driver"], in: project, timeout: .seconds(30)))
    return result.success && !JS.trim(result.stdout).isEmpty
  }

  /// Whether the project is (inside) a git work tree. Without one there is no core update to
  /// protect against, and the driver can not be set: "nicht aktiv" then needs its reason
  /// (review 2026-11-13, nebenbei).
  public func isRepository(project: String) async -> Bool {
    let result = await ProcessRunner.run(environment.command("git", ["rev-parse", "--is-inside-work-tree"], in: project, timeout: .seconds(30)))
    return result.success && JS.trim(result.stdout) == "true"
  }

  public func gitAttributesActive(project: String) async -> Bool {
    let path = "\(project)/.gitattributes"
    guard FileManager.default.fileExists(atPath: path), (try? Self.readText(path))?.contains(Self.mergeOursLine) == true else { return false }
    return await hasMergeDriver(project)
  }

  /// Idempotent, after every successful save: the line, then the driver (`true` succeeds without
  /// writing, which git reads as "keep ours"). A project that is no repository gets the line only.
  public func ensureGitAttributes(project: String) async {
    let path = "\(project)/.gitattributes"
    let existing = FileManager.default.fileExists(atPath: path) ? ((try? Self.readText(path)) ?? "") : ""
    if !existing.contains(Self.mergeOursLine) {
      // By scalar: "\r\n" is one Character, and endsWith('\n') is true for it.
      let next = !existing.isEmpty && existing.unicodeScalars.last != "\n" ? "\(existing)\n\(Self.mergeOursLine)\n" : "\(existing)\(Self.mergeOursLine)\n"
      try? Posix.write(path, Data(next.utf8))
    }
    if await hasMergeDriver(project) { return }
    _ = await ProcessRunner.run(environment.command("git", ["config", "merge.ours.driver", "true"], in: project, timeout: .seconds(30)))
  }
}
