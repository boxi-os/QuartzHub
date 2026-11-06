import Foundation

/// Reading and writing `quartz.config.yaml`, a port of QuartzControl's `configService.ts`. The YAML
/// itself goes through the helper `yaml-edit` (the same `yaml` 2.9.0, the same calls), because
/// keeping comments, key order and the CLI's line width is that library's document API and nothing
/// in Swift has one. What is around it is here: the file, the lock, the frame paths, the sentences.
///
/// - **An empty file is a valid config**, read as one without any key.
/// - **Three ways to be unreadable, three sentences:** a syntax error (yaml does not throw on one,
///   it collects them, and a half-read file once showed as a half-empty configuration), no mapping,
///   and `plugins:` that is not a list. A fourth here: an entry whose source names nothing, where
///   QuartzControl stopped on a raw TypeError.
/// - **A write asks the file again**, because it does not come through `read`: between the read and
///   the save the file can have become something else, a hand edit being the ordinary way there.
/// - **A snapshot before a save** (`configChange`, coalesced over 15 minutes), when the caller
///   hands one over and the file has content. Before the lock, never under it: a restore holds
///   the snapshot queue and takes the config lock at its end (QuartzControl's forty-third review,
///   finding 2). The repair of frame paths and the template parts write without one.
public enum ConfigFile {
  public static let fileName = "quartz.config.yaml"

  public enum Failure: Error, Equatable {
    case missing
    case notParseable(reason: String)
    case notAMapping
    case pluginsNotAList
    /// 1-based, as the sentence says it.
    case pluginEntryInvalid(index: Int)

    public var message: String {
      switch self {
      case .missing: L10n.t("main.configMissing")
      case .notParseable(let reason): L10n.t("main.configNotParseable", ["reason": reason])
      case .notAMapping: L10n.t("main.configNotAMapping")
      case .pluginsNotAList: L10n.t("main.configPluginsNotAList")
      case .pluginEntryInvalid(let index): L10n.t("main.configPluginEntryInvalid", ["index": String(index)])
      }
    }
  }

  public static func path(project: String) -> String { "\(project)/\(fileName)" }

  // MARK: read

  public static func read(project: String, runtime: RuntimeLocation = .current) async throws -> QuartzConfig {
    let text: String
    do {
      text = String(decoding: try Posix.read(path(project: project)), as: UTF8.self)
    } catch let error as NodeFileError where error.code == ENOENT {
      throw Failure.missing
    }
    let answer = try await Helper.call("yaml-edit", JSONObject([("op", .string("read")), ("text", .string(text))]),
                                       runtime: runtime)
    if let reason = firstError(answer) { throw Failure.notParseable(reason: reason) }
    switch answer["kind"]?.stringValue {
    case "empty": return QuartzConfig()
    case "mapping": break
    default: throw Failure.notAMapping
    }
    guard case .object(let file)? = answer["value"] else { throw Failure.notAMapping }
    return try shape(file)
  }

  /// readConfig's `{ theme, ...configuration }` and the plugin map, from the file's value.
  ///
  /// Where a key holds the wrong kind of thing QuartzControl spread it anyway and failed on the
  /// next save (`configuration: abc` became `{ 0: "a", … }`, which `setIn` cannot put under a
  /// string) or on the read itself (`layout:` empty is `null`, and `null.groups` threw). Here such
  /// a key reads as absent, and the write then leaves it where it is.
  static func shape(_ file: JSONObject) throws -> QuartzConfig {
    var configuration = file["configuration"]?.objectValue ?? JSONObject()
    let theme = configuration["theme"]?.objectValue ?? JSONObject()
    configuration["theme"] = nil

    var plugins: [PluginEntry] = []
    switch file["plugins"] {
    case nil, .null?: break
    case .array(let entries)?:
      for (index, entry) in entries.enumerated() {
        guard case .object(var object) = entry, let name = PluginEntry.derivedName(object["source"]) else {
          throw Failure.pluginEntryInvalid(index: index + 1)
        }
        object["name"] = .string(name)
        object["enabled"] = .bool(JS.truthy(object["enabled"] ?? .null))
        plugins.append(PluginEntry(object: object))
      }
    default:
      throw Failure.pluginsNotAList
    }
    return QuartzConfig(configuration: configuration, theme: theme, plugins: plugins,
                        layout: file["layout"]?.objectValue)
  }

  /// yaml's first message as a sentence that can stand inside one of ours: its first line (the
  /// rest is a source excerpt with a caret, for a terminal) without the colon it ends in, which
  /// came out as "at line 3, column 18:. Repariere" (QuartzControl's twenty-third review).
  static func yamlReason(_ message: String) -> String {
    var line = Substring(message.components(separatedBy: "\n").first ?? "")
    while let last = line.last, last.isWhitespace || last == ":" { line.removeLast() }
    return String(line)
  }

  private static func firstError(_ answer: JSONObject) -> String? {
    guard let first = answer["errors"]?.arrayValue?.first else { return nil }
    return yamlReason(first["message"]?.stringValue ?? "")
  }

  // MARK: write

  /// `writeConfig`, under the config lock: a repair of the frame paths at the build door reads and
  /// writes in one go, and a save waits for it instead of landing in between.
  public static func write(_ config: QuartzConfig, project: String, runtime: RuntimeLocation = .current,
                           snapshot: SnapshotStore.Take? = nil) async throws {
    var info = stat()
    if let snapshot, stat(path(project: project), &info) == 0, info.st_size > 0 {
      _ = try await snapshot(project, "configChange", "")
    }
    try await ProjectLock.config.run(project) {
      try await writeNow(config, project: project, runtime: runtime)
    }
  }

  static func writeNow(_ config: QuartzConfig, project: String, runtime: RuntimeLocation) async throws {
    let url = path(project: project)
    let existing = Posix.exists(url) ? String(decoding: try Posix.read(url), as: UTF8.self) : ""

    // A page holds the config it read when it opened, and the build door may have pointed a frame
    // path at this project since; whatever a writer hands over names this project's frames
    // (QuartzControl's forty-second review, finding 6).
    let plugins: [JSONValue] = config.plugins.map { entry in
      var object = entry.object
      object["name"] = nil
      if case .string(let source)? = object["source"], let own = FramePaths.ownFramePath(project: project, source) {
        object["source"] = .string(own)
      }
      return .object(object)
    }
    var request = JSONObject([("op", .string("write")), ("text", .string(existing)),
                              ("configuration", .object(config.configuration)), ("theme", .object(config.theme)),
                              ("plugins", .array(plugins))])
    if let layout = config.layout { request["layout"] = .object(layout) }

    let answer = try await Helper.call("yaml-edit", request, runtime: runtime)
    if let reason = firstError(answer) { throw Failure.notParseable(reason: reason) }
    if answer["notAMapping"] == .bool(true) { throw Failure.notAMapping }
    guard let text = answer["text"]?.stringValue else { throw Helper.Failure.broken("no text in \(answer.keys)") }
    try JSONStore.writeAtomic(Data(text.utf8), to: url)
  }
}
