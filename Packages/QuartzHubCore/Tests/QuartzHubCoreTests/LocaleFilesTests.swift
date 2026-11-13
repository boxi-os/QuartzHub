import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own localizationService.ts: `scripts/locales-golden.mjs` built a git
/// project with gui-test's de-DE and en-US and locale files of every odd shape, ran 51 steps
/// (list, read, save, baseline, git's baseline, merge=ours) and recorded each answer, the changed
/// files and git's `merge.ours.driver`. Needs Runtime/ and the helper `locale-edit`.
@Suite(.enabled(if: HelperRuntime.available && FileManager.default.fileExists(atPath: "\(HelperRuntime.runtime.helpers)/locale-edit.cjs"),
                "Runtime/ oder Helpers/dist/locale-edit.cjs fehlt: scripts/fetch-runtime.sh, scripts/build-helpers.sh"))
struct LocaleFilesTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/locales")

  static func put(_ root: String, _ files: JSONValue?) throws {
    guard case .object(let object)? = files else { return }
    for path in object.keys {
      let url = "\(root)/\(path)"
      try Posix.mkdirs(NodePath.dirname(url))
      try Posix.write(url, Data(object[path]!.stringValue!.utf8))
    }
  }

  static func tree(_ root: String, _ prefix: String) -> [String: String] {
    var out: [String: String] = [:]
    for path in (try? FileManager.default.subpathsOfDirectory(atPath: root)) ?? [] where path != ".git" && !path.hasPrefix(".git/") {
      var isDirectory: ObjCBool = false
      let full = "\(root)/\(path)"
      guard FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
      out[prefix + path] = String(decoding: FileManager.default.contents(atPath: full) ?? Data(), as: UTF8.self)
    }
    return out
  }

  static func json(_ entry: LocaleFiles.Entry) -> JSONValue {
    .object(JSONObject([("path", .array(entry.path.map(JSONValue.string))), ("kind", .string(entry.kind.rawValue)), ("value", .string(entry.value))]))
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let roots = ["project": "\(scratch.path)/project", "plain": "\(scratch.path)/plain"]
    let start = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("start.json")))
    let environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    func git(_ arguments: [String], in root: String) async -> CommandResult {
      await ProcessRunner.run(environment.command("git", arguments, in: root, timeout: .seconds(30)))
    }
    let project = roots["project"]!
    try Self.put(project, start["committed"])
    for arguments in [["init", "-q"], ["config", "user.email", "golden@example.invalid"], ["config", "user.name", "golden"], ["add", "-A"], ["commit", "-q", "-m", "start"]] {
      let result = await git(arguments, in: project)
      #expect(result.success, "git \(arguments): \(result.output)")
    }
    try Self.put(project, start["edited"])
    try Self.put(roots["plain"]!, start["plain"])
    try Posix.mkdirs("\(roots["plain"]!)/quartz/i18n/locales/xy.ts")

    let locales = LocaleFiles(environment: environment)
    func snapshot() -> [String: String] { Self.tree(roots["project"]!, "project/").merging(Self.tree(roots["plain"]!, "plain/")) { a, _ in a } }
    var before = snapshot()
    let steps = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps.json"))).arrayValue ?? []
    #expect(steps.count == 51)
    for (index, step) in steps.enumerated() {
      let on = step["on"]!.stringValue!, call = step["call"]!.stringValue!
      let root = roots[on]!
      let args = step["args"]?.arrayValue ?? []
      let label = "\(index) \(on) \(call) \(JSJSON.compact(.array(args)))"
      var got: JSONValue = .null
      do {
        switch call {
        case "listLocales": got = .array(try locales.list(project: root).map { .object(JSONObject([("code", .string($0))])) })
        case "getLocaleEntries": got = .array(try await locales.entries(project: root, code: args[0].stringValue!).map(Self.json))
        case "saveLocaleEntry":
          let result = try await locales.save(project: root, code: args[0].stringValue!, path: (args[1].arrayValue ?? []).compactMap(\.stringValue),
                                              kind: LocaleFiles.Kind(rawValue: args[2].stringValue!)!, value: args[3].stringValue!)
          got = .object(JSONObject([("success", .bool(result.success))] + (result.error.map { [("error", JSONValue.string($0))] } ?? [])))
        case "getTranslationCustomizations":
          got = .array(try await locales.customizations(project: root).map { item in
            .object(JSONObject([("code", .string(item.code)), ("source", .string(item.source.rawValue)), ("changed", .array(item.changed.map(Self.json))),
                                ("total", .number(Double(item.total)))]))
          })
        case "getGitAttributesStatus": got = .bool(await locales.gitAttributesActive(project: root))
        case "ensureGitAttributes": await locales.ensureGitAttributes(project: root)
        case "writeFile": try Posix.write("\(root)/\(args[0].stringValue!)", Data(args[1].stringValue!.utf8))
        case "git": _ = await git(args.compactMap(\.stringValue), in: root)
        default: Issue.record("\(label): unbekannter Schritt")
        }
      } catch {
        let text = String(describing: error)
        got = .object(JSONObject([("threw", .string(text.hasPrefix("Error: ") ? String(text.dropFirst(7)) : text))]))
      }
      #expect(JSJSON.compact(got) == JSJSON.compact(step["result"] ?? .null), "\(label)")

      let after = snapshot()
      var changed: [String: String?] = [:]
      for path in Set(before.keys).union(after.keys) where before[path] != after[path] { changed[path] = after[path] }
      before = after
      var wanted: [String: String?] = [:]
      if case .object(let files)? = step["changed"] { for key in files.keys { wanted[key] = files[key]!.stringValue.map { QC.render($0, mask: "") } } }
      #expect(changed == wanted, "\(label): Dateien \(changed.keys.sorted()) statt \(wanted.keys.sorted())")

      let driver = await git(["config", "--get", "merge.ours.driver"], in: root)
      let value: JSONValue = driver.success ? .string(JS.trim(driver.stdout)) : .null
      #expect(value == step["driver"], "\(label): merge.ours.driver")
    }
  }

  /// QuartzControl's template import handed a package's locale code on unchecked; here a code
  /// that is no locale code reads nothing and writes nothing, even where the file exists.
  /// The protection's reason: a folder is no repository until `git init`, and then is one.
  @Test func aFolderIsARepositoryOnlyAfterGitInit() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    let locales = LocaleFiles(environment: environment)
    #expect(await locales.isRepository(project: scratch.path) == false)
    let initialized = await ProcessRunner.run(environment.command("git", ["init", "-q"], in: scratch.path, timeout: .seconds(30)))
    #expect(initialized.success)
    #expect(await locales.isRepository(project: scratch.path))
  }

  @Test func aCodeThatIsNoLocaleCodeIsNoFile() async throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let project = "\(scratch.path)/project"
    let target = "\(project)/quartz/util/path.ts"
    try Posix.mkdirs(NodePath.dirname(target))
    try Posix.mkdirs(LocaleFiles.localesDirectory(project))
    let text = "export default { title: \"x\" }\n"
    try Posix.write(target, Data(text.utf8))
    let locales = LocaleFiles(environment: await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded))
    #expect(try await locales.entries(project: project, code: "../../util/path").isEmpty)
    let saved = try await locales.save(project: project, code: "../../util/path", path: ["title"], kind: .string, value: "y")
    #expect(saved == LocaleFiles.SaveResult(success: false, error: "Locale file not found: ../../util/path", failure: .fileMissing(code: "../../util/path")))
    #expect(String(decoding: try Posix.read(target), as: UTF8.self) == text)
    #expect(!FileManager.default.fileExists(atPath: "\(project)/.quartz-gui"))
  }

  /// Node's `readFileSync` names why a file could not be read; a locked file is no missing one.
  @Test func anUnreadableFileSaysWhy() throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let file = "\(scratch.path)/de-DE.ts"
    try Posix.write(file, Data("export default {}\n".utf8))
    #expect(try LocaleFiles.readText(file) == "export default {}\n")
    chmod(file, 0)
    defer { chmod(file, 0o644) }
    #expect(throws: NodeFileError.self) { try LocaleFiles.readText(file) }
    do {
      _ = try LocaleFiles.readText(file)
    } catch {
      #expect(String(describing: error) == "Error: EACCES: permission denied, open '\(file)'")
    }
    #expect(String(describing: (try? LocaleFiles.readText("\(scratch.path)/fehlt.ts")) ?? "") == "")
    do {
      _ = try LocaleFiles.readText("\(scratch.path)/fehlt.ts")
    } catch {
      #expect(String(describing: error) == "Error: ENOENT: no such file or directory, open '\(scratch.path)/fehlt.ts'")
    }
  }

  @Test func localeCodes() {
    for code in ["de", "de-DE", "deu", "tlh-Latn", "zh-Hant-TW", "ab-12345678", "Ab"] { #expect(LocaleFiles.isLocaleCode(code), "\(code)") }
    for code in ["d", "deut", "de-", "-de", "de--DE", "de-D", "de-123456789", "dé", "de_DE", "1a", String(repeating: "ab-", count: 12) + "ab", ""] {
      #expect(!LocaleFiles.isLocaleCode(code), "\(code)")
    }
  }
}
