import CryptoKit
import Darwin
import Foundation
import Synchronization

/// What quartz-forms says about one key of `keys` (`FormsKeyReport`).
public struct FormsKeyReport: Equatable, Sendable {
  public let name: String
  /// `AB12 CD34 …`; empty when the key could not be read.
  public let fingerprint: String
  public let userIds: [String]
  /// `YYYY-MM-DD`; nil when it never expires.
  public let expires: String?
  public let problem: String?
  /// What the owner should know about a key that passes (quartz-forms 0.5.5: gpg cannot read it).
  public let notice: String?
}

/// `forms.check`: the plugin's own verdict, or why there is none.
public enum FormsCheckResult: Equatable, Sendable {
  case checked(problems: [String], hints: [String], keys: [FormsKeyReport])
  case unavailable(reason: String)
}

/// `forms.texts`: quartz-forms' own wording of every text, by locale (each a `{ key: text }`
/// object, in the plugin's order), or why there is none.
public enum FormsTextsResult: Equatable, Sendable {
  case read(locales: JSONObject)
  case unavailable(reason: String)
}

/// `forms.inspectKey`: what a pasted key is, with the public key block alone to store.
public enum FormsKeyInspection: Equatable, Sendable {
  case key(FormsKeyReport, armored: String?)
  case unavailable(String)
}

/// `forms.importKey`: the path written (relative to the site root), or the one already there.
public enum FormsKeyImport: Equatable, Sendable {
  case file(String)
  case exists(String)
}

/// What the Formulare tab asks quartz-forms itself, instead of copying its rules (the first part of
/// QuartzControl's `formsService.ts`): the problems and hints its build would give (`check`), its
/// wording (`texts`) and what a key is (`key`). Each runs the plugin's command line (dist/cli.js,
/// 0.2.0 and later) under the project's Node in a child process; a pasted key travels through the
/// environment, never argv. "Cannot check" is an answer of its own (`unavailable`), never an empty
/// list of problems.
///
/// One deviation: an answer `null` is "cannot check" here; QuartzControl threw a TypeError.
public struct FormsCLI: Sendable {
  /// Where an imported key file goes, relative to the site root: outside content/ and static/, so
  /// the build reads it (keys.<name>.file) and does not publish it as a file.
  public static let keyDirectory = "quartz-forms/keys"
  /// A public key is a few KiB; a file far beyond that is not one, and is not read whole.
  static let maxKeyFileBytes = 256 * 1024

  public let project: String
  public let source: PluginSource
  public let environment: ToolEnvironment
  var timeout: Duration

  public init(project: String, source: PluginSource, environment: ToolEnvironment, timeout: Duration = .seconds(30)) {
    self.project = project
    self.source = source
    self.environment = environment
    self.timeout = timeout
  }

  enum Answer {
    case ok(JSONObject)
    case failed(String, JSONObject?)
  }

  var cliPath: String? {
    guard let dir = PluginSchemaReader.packageDirectory(project: project, source: source) else { return nil }
    let cli = "\(dir)/dist/cli.js"
    return Posix.exists(cli) ? cli : nil
  }

  /// `--lang` from quartz-forms 0.3.0 on, which has its messages in German too; an older one
  /// refuses the flag as an unknown argument. Asked of the package.json Quartz loads; one that
  /// cannot be read gives no flag, and the messages come in English.
  var languageArguments: [String] {
    guard let dir = PluginSchemaReader.packageDirectory(project: project, source: source),
          let data = try? Posix.read("\(dir)/package.json"),
          let package = try? JSJSON.parse(data),
          let version = package["version"]?.stringValue,
          !SemVer.isNewer("0.3.0", than: version) else { return [] }
    return ["--lang", L10n.language]
  }

  /// The plugin's last line on stdout as JSON; `ok: true` or why not.
  func run(_ arguments: [String], variables: [String: String] = [:]) async -> Answer {
    guard let cli = cliPath else { return .failed(L10n.t("main.formsNoCli"), nil) }
    let command = environment.command("node", [cli] + arguments + ["--json"] + languageArguments, in: project, timeout: timeout).adding(variables)
    let result = await ProcessRunner.run(command)
    let output = result.report(for: command)
    let unreadable = L10n.t("main.formsCliOutput", ["output": JSText.slice(JS.trim(output), 0, 400)])
    let last = JSText.split(JS.trim(result.stdout), "\n").last ?? ""
    guard let json = (try? JSJSON.parse(Data(last.utf8)))?.objectValue else { return .failed(unreadable, nil) }
    guard json["ok"] == .bool(true) else { return .failed(json["error"]?.stringValue ?? unreadable, json) }
    return .ok(json)
  }

  static func strings(_ value: JSONValue?) -> [String] { value?.arrayValue?.compactMap(\.stringValue) ?? [] }

  static func keyReport(_ value: JSONValue?) -> FormsKeyReport {
    let r = value?.objectValue ?? JSONObject()
    return FormsKeyReport(name: r["name"]?.stringValue ?? "", fingerprint: r["fingerprint"]?.stringValue ?? "", userIds: strings(r["userIds"]),
                          expires: r["expires"]?.stringValue, problem: r["problem"]?.stringValue, notice: r["notice"]?.stringValue)
  }

  /// The plugin's own verdict on the options as they stand in quartz.config.yaml.
  public func check() async -> FormsCheckResult {
    switch await run(["check", "--site", project]) {
    case .failed(let reason, _): return .unavailable(reason: reason)
    case .ok(let json):
      return .checked(problems: Self.strings(json["problems"]), hints: Self.strings(json["hints"]),
                      keys: json["keys"]?.arrayValue?.map { Self.keyReport($0) } ?? [])
    }
  }

  // The wording changes only with the plugin, and each open of the Texte section asked it again in
  // a child process. Kept per command line and keyed by its content, not its mtime: npm gives every
  // file of a package the same one. The texts live in a chunk that cli.js imports by a name holding
  // the chunk's hash, so new texts are a new cli.js.
  static let textsCache = Mutex<[String: (stamp: String, result: FormsTextsResult)]>([:])

  static func textsStamp(_ cli: String) -> String? {
    guard let data = try? Posix.read(cli) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// The plugin's own wording of every text, by locale (`texts`, after 0.5.8). An answer without
  /// one locale of strings is not the answer asked for, and says so.
  public func texts() async -> FormsTextsResult {
    let cli = cliPath
    let stamp = cli.flatMap(Self.textsStamp)
    if let cli, let stamp, let cached = Self.textsCache.withLock({ $0[cli] }), cached.stamp == stamp { return cached.result }
    let result = await readTexts()
    if let cli, let stamp, case .read = result { Self.textsCache.withLock { $0[cli] = (stamp, result) } }
    return result
  }

  /// `Object.entries` of an object or an array.
  static func entries(_ value: JSONValue?) -> [(String, JSONValue)] {
    if let object = value?.objectValue { return object.keys.map { ($0, object[$0]!) } }
    if let array = value?.arrayValue { return array.enumerated().map { (String($0.offset), $0.element) } }
    return []
  }

  func readTexts() async -> FormsTextsResult {
    let json: JSONObject
    switch await run(["texts"]) {
    case .failed(let reason, _): return .unavailable(reason: reason)
    case .ok(let answer): json = answer
    }
    var locales = JSONObject()
    for (locale, entries) in Self.entries(json["locales"]) {
      let own = Self.entries(entries).filter { $0.1.stringValue != nil }
      if !own.isEmpty { locales[locale] = .object(JSONObject(own)) }
    }
    if locales.keys.isEmpty {
      return .unavailable(reason: L10n.t("main.formsCliOutput", ["output": JSText.slice(JSJSON.compact(.object(json)), 0, 400)]))
    }
    return .read(locales: locales)
  }

  /// What a pasted key is, and the public key block alone to store (never the text around it).
  public func inspectKey(_ armored: String) async -> FormsKeyInspection {
    switch await run(["key"], variables: ["QF_KEY_ARMORED": armored]) {
    case .failed(let reason, _): return .unavailable(reason)
    case .ok(let json): return .key(Self.keyReport(json["key"]), armored: json["armored"]?.stringValue)
    }
  }

  /// Copies a key file into the project under quartz-forms/keys/<name>.asc. A file that holds a
  /// private key block is refused before anything is written: it would land in the project, its
  /// snapshots and its repository. An existing file is not overwritten unless asked.
  ///
  /// As QuartzControl: only the segments below `keys/` are checked for links, so a linked
  /// `quartz-forms/` is written through (noted as a finding of QuartzControl's, docs/decisions).
  public static func importKeyFile(project: String, from sourcePath: String, name: String, overwrite: Bool) throws(PublishFailure) -> FormsKeyImport {
    guard JSText.test(name, "^[A-Za-z0-9_-]{1,64}$") else { throw PublishFailure(L10n.t("main.formsKeyName")) }
    do {
      let info = try NodeFileError.statFollowing(sourcePath)
      guard info.st_mode & S_IFMT == S_IFREG else { throw PublishFailure(L10n.t("main.formsKeyNotAFile")) }
      guard info.st_size <= maxKeyFileBytes else { throw PublishFailure(L10n.t("main.formsKeyTooLarge")) }
      let text = String(decoding: try Posix.read(sourcePath), as: UTF8.self)
      guard !JSText.includes(text, "-----BEGIN PGP PRIVATE KEY BLOCK-----") else { throw PublishFailure(L10n.t("main.formsKeyPrivate")) }
      guard JSText.includes(text, "-----BEGIN PGP PUBLIC KEY BLOCK-----") else { throw PublishFailure(L10n.t("main.formsKeyNoPublic")) }
      let dir = NodePath.join(project, keyDirectory)
      try Posix.mkdirs(dir)
      guard let target = PackagePaths.writable(dir, "\(name).asc") else { throw PublishFailure(L10n.t("main.formsKeyName")) }
      let relative = NodePath.relative(project, target)
      if Posix.exists(target) && !overwrite { return .exists(relative) }
      let temp = "\(target).tmp-\(getpid())"
      try Posix.write(temp, Data(text.utf8))
      guard Darwin.rename(temp, target) == 0 else {
        throw NodeFileError(code: errno, syscall: "rename '\(temp)' ->", path: target)
      }
      return .file(relative)
    } catch let failure as PublishFailure {
      throw failure
    } catch {
      throw PublishFailure(PublishFailure.message(of: error))
    }
  }
}
