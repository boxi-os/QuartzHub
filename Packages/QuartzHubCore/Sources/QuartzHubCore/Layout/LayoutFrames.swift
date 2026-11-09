import Darwin
import Foundation
import Synchronization

/// Authored frames: a port of `layoutFrameService.ts`. Each frame is a directory
/// `<project>/.quartz-gui/authored-frames/<id>` that *is* a local Quartz plugin: `quartz plugin
/// add <path>` symlinks it into `.quartz/plugins/<id>` once, and after that rewriting the three
/// files behind the link is all a change takes.
///
/// - `frame.json` — QuartzHub's (and QuartzControl's) own copy of the definition, written back
///   whole, unknown keys included.
/// - `package.json` — the plugin manifest naming the `Frame` export.
/// - `dist/frames.js` — the module Quartz imports (`FrameModule`), with the CSS and the group
///   orderings baked in. Those are copies of what the project's breakpoint widths and
///   `quartz.config.yaml` say, so every frame is rewritten before every build and every dev
///   server start (`writeAllFrames`, a step of `BuildService.preparation`): the one place the copy
///   is read is the build, so that is where it is made true again.
///
/// One writer per project at a time (`ProjectLock.frames`): saving a frame, changing the widths and
/// the refresh before a build write the same files, and "Jetzt bauen" right after "Starten" is two
/// of them within a second. Atomic writes keep each file whole; the lock keeps a set of three from
/// being half one caller's and half another's.
public struct LayoutFrames: Sendable {
  public typealias ReadConfig = @Sendable (String) async throws -> QuartzConfig

  /// The two CLI calls a frame needs, injectable for the tests. `snapshot` is QuartzControl's
  /// `addPlugin` (with one) against `installPluginSource` (without, for a template import that
  /// takes one for the whole import). Removing always takes one: QuartzControl's `deleteFrame`
  /// goes through `removePlugin`, and the question before it says so.
  public struct Plugins: Sendable {
    public var add: @Sendable (_ source: String, _ project: String, _ snapshot: Bool) async -> PluginCommands.Result
    public var remove: @Sendable (_ name: String, _ project: String) async -> PluginCommands.Result

    public init(add: @escaping @Sendable (String, String, Bool) async -> PluginCommands.Result,
                remove: @escaping @Sendable (String, String) async -> PluginCommands.Result) {
      self.add = add
      self.remove = remove
    }

    public static func cli(environment: @escaping @Sendable () async -> ToolEnvironment, snapshot: SnapshotStore.Take?) -> Plugins {
      Plugins(
        add: { source, project, withSnapshot in
          await PluginCommands.shared.add(source: source, project: project, environment: environment(), snapshot: withSnapshot ? snapshot : nil)
        },
        remove: { name, project in
          await PluginCommands.shared.remove(name: name, project: project, environment: environment(), snapshot: snapshot)
        })
    }
  }

  let readConfig: ReadConfig
  let plugins: Plugins?

  /// `plugins` nil: a caller that only rewrites (the build door) needs no CLI.
  public init(readConfig: @escaping ReadConfig = { try await ConfigFile.read(project: $0) }, plugins: Plugins? = nil) {
    self.readConfig = readConfig
    self.plugins = plugins
  }

  public typealias Widths = (tablet: Double, mobile: Double)

  // MARK: where

  static func framesDirectory(_ project: String) -> String {
    QuartzGuiDirectory(project: project).file("authored-frames")
  }

  /// A frame id becomes a directory name and the plugin name `quartz plugin add` derives, so it is a
  /// plain slug; unchecked, ".." in an id from a `.qtpl` would let `deleteFrame` remove a folder
  /// outside the project.
  static func isSlug(_ text: String) -> Bool { text.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9-]{0,63}/) != nil }

  struct FrameIdInvalid: Error, CustomStringConvertible {
    let id: String
    var description: String { "Error: " + L10n.t("main.frameIdInvalid", ["id": id]) }
  }

  /// Node's `ERR_INVALID_ARG_TYPE` from `join()`, for an id that is no string but reads like a slug.
  struct InvalidPathArgument: Error, CustomStringConvertible {
    let received: String
    var description: String { "TypeError [ERR_INVALID_ARG_TYPE]: The \"path\" argument must be of type string. Received \(received)" }
  }

  /// The directory of frame `id`, or why there is none.
  public static func frameDirectory(project: String, id: String) throws -> String {
    try frameDirectory(project, .string(id))
  }

  static func frameDirectory(_ project: String, _ id: JSONValue?) throws -> String {
    let text = JS.string(id)
    guard isSlug(text) else { throw FrameIdInvalid(id: text) }
    switch id {
    case .string(let id)?: return "\(framesDirectory(project))/\(id)"
    case nil: throw InvalidPathArgument(received: "undefined")
    case .null?: throw InvalidPathArgument(received: "null")
    case .number(let number)?: throw InvalidPathArgument(received: "type number (\(JSJSON.numberToString(number)))")
    case .bool(let bool)?: throw InvalidPathArgument(received: "type boolean (\(bool))")
    default: throw InvalidPathArgument(received: "an instance of Object")
    }
  }

  // MARK: breakpoint widths

  /// One file per project, not a field per frame: two frames that disagree about where "mobile"
  /// starts would reflow one site at two widths. Absent, unreadable or inconsistent means Quartz's
  /// own numbers; a broken file must not make the frames unbuildable.
  public static func widths(project: String) -> Widths {
    let raw = JSONStore.read(QuartzGuiDirectory(project: project).layoutBreakpoints, orEmpty: .object)
    return FrameBreakpointWidths(object: raw.objectValue ?? JSONObject()).widths
  }

  /// The widths are baked into each frame's media queries, so every frame is rewritten with them.
  public func saveWidths(_ widths: Widths, project: String) async throws {
    let file = "\(try QuartzGuiDirectory(project: project).create())/layout-breakpoints.json"
    try JSONStore.write(.object(JSONObject([("tablet", .number(widths.tablet)), ("mobile", .number(widths.mobile))])), to: file)
    try await ProjectLock.frames.run(project) {
      let groupLayouts = await readGroupLayouts(project, problems: nil)
      for def in Self.listFrames(project: project) {
        try write(def, project: project, widths: widths, groupLayouts: groupLayouts)
      }
    }
  }

  // MARK: list

  /// Every readable frame of the project, in the order the directory lists them, each in the
  /// current shape. A frame.json that does not parse is left out and left alone: moving it aside
  /// would take the frame's directory apart while its plugin entry still points at it.
  public static func listFrames(project: String) -> [JSONValue] {
    let dir = framesDirectory(project)
    return directoryEntries(dir).filter(\.isDirectory).compactMap { entry -> JSONValue? in
      let file = "\(dir)/\(entry.name)/frame.json"
      guard let data = try? Posix.read(file), let raw = try? JSJSON.parse(data),
            let def = try? GridFrameCss.migrate(raw), def != .null else { return nil }
      return def
    }
  }

  /// `readdir(dir, { withFileTypes: true })`: sorted by the bytes of the name, as libuv's
  /// `scandir` sorts for Node (strcmp), not in the order the file system gives; a symlink is not a
  /// directory.
  static func directoryEntries(_ dir: String) -> [(name: String, isDirectory: Bool)] {
    directoryEntriesWithKind(dir).map { ($0.name, $0.kind == .directory) }
  }

  enum EntryKind { case directory, file, link, other }

  /// The same with the Dirent's kind: a link is a link, not what it points at.
  /// (Measured: the 22 files of a plugin came back in the file system's hash order, Node's in
  /// name order.)
  static func directoryEntriesWithKind(_ dir: String) -> [(name: String, kind: EntryKind)] {
    guard let stream = opendir(dir) else { return [] }
    defer { closedir(stream) }
    var result: [(String, EntryKind)] = []
    while let entry = readdir(stream) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
        String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
      }
      if name == "." || name == ".." { continue }
      let kind: EntryKind
      switch Int32(entry.pointee.d_type) {
      case DT_DIR: kind = .directory
      case DT_REG: kind = .file
      case DT_LNK: kind = .link
      default: kind = .other
      }
      result.append((name, kind))
    }
    return result.sorted { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }
  }

  // MARK: write

  typealias GroupLayoutsFor = @Sendable (JSONValue?) throws -> [GroupLayouts.Candidate]

  /// Unreadable config means no groups rather than a failed write: a frame that shows every
  /// position undivided still builds. But "no groups" and "could not tell" render the same, so the
  /// difference is said where it is known, in the build log.
  func readGroupLayouts(_ project: String, problems: ProblemList?) async -> GroupLayoutsFor {
    do {
      let config = try await readConfig(project)
      let plugins = config.plugins.map(\.object)
      let layout = config.layout
      return { frameName in try GroupLayouts.candidates(plugins: plugins, layout: layout, frameName: frameName) }
    } catch {
      problems?.append(L10n.t("main.frameGroupsUnreadable", ["error": Self.errorText(error)]))
      return { _ in [GroupLayouts.Candidate(pageType: nil, order: JSONObject())] }
    }
  }

  /// The three files of one frame. All three contents are made before the first is written: a
  /// definition whose module cannot be generated gets none of them, where QuartzControl had started
  /// two atomic writes before the third threw and left their temporary files behind.
  func write(_ def: JSONValue, project: String, widths: Widths, groupLayouts: GroupLayoutsFor) throws {
    if def == .null { throw JS.readError(.null, "id") }
    let dir = try Self.frameDirectory(project, def["id"])
    let package = JSJSON.stringify(.object(GridFrameCss.present([
      ("name", def["id"]), ("version", .string("1.0.0")), ("private", .bool(true)), ("type", .string("module")),
      ("quartz", .object(JSONObject([("frames", .object(JSONObject([("Frame", .object(JSONObject([("exportName", .string("Frame"))])))])))])))
    ])))
    let layouts = try groupLayouts(def["frameName"])
    let module = FrameModule.source(frameName: def["frameName"], areas: def["areas"], groupLayouts: layouts,
                                    css: try GridFrameCss.frameCss(def, widths: widths))
    try QuartzGuiDirectory(project: project).create("authored-frames")
    try Posix.mkdirs("\(dir)/dist")
    try JSONStore.write(def, to: "\(dir)/frame.json")
    try JSONStore.writeAtomic(Data(package.utf8), to: "\(dir)/package.json")
    try JSONStore.writeAtomic(Data(module.utf8), to: "\(dir)/dist/frames.js")
  }

  /// Rewrites every frame against the config and the widths as they stand now. Never throws and
  /// returns at once for a project without frames, because it sits in front of every build; what
  /// went wrong comes back as sentences for the build log. Silence would read "built with the
  /// frames as they were", which looks exactly like success.
  public func writeAllFrames(project: String) async -> [String] {
    let problems = ProblemList()
    do {
      guard !Self.listFrames(project: project).isEmpty else { return [] }
      // Read inside the queue: reading first leaves a window in which the caller with the older
      // config writes last.
      try await ProjectLock.frames.run(project) {
        let frames = Self.listFrames(project: project)
        let widths = Self.widths(project: project)
        let groupLayouts = await readGroupLayouts(project, problems: problems)
        for def in frames {
          try write(def, project: project, widths: widths, groupLayouts: groupLayouts)
        }
      }
    } catch {
      problems.append(L10n.t("main.frameRefreshFailed", ["error": Self.errorText(error)]))
    }
    return problems.items
  }

  /// `String(err)` as QuartzControl put it into the sentence: "Error: …", "TypeError: …".
  static func errorText(_ error: Error) -> String {
    switch error {
    case let error as JS.TypeError: error.description
    case let error as FrameIdInvalid: error.description
    case let error as InvalidPathArgument: error.description
    case let error as ConfigFile.Failure: "Error: " + error.message
    default: "Error: " + String(describing: error)
    }
  }

  // MARK: save and delete

  /// Why a definition cannot be written, or nil (`FrameDefinitionCheck`).
  public static func problem(_ raw: JSONValue?) -> String? {
    FrameDefinitionCheck.problem(raw)
  }

  /// Writes a frame; a new one is also registered with `quartz plugin add <dir>`, an existing one
  /// only rewritten. `snapshot: false` for a template import (see `Plugins`).
  public func saveFrame(_ raw: JSONValue, project: String, snapshot: Bool = true) async throws -> PluginCommands.Result {
    if let problem = Self.problem(raw) { return PluginCommands.Result(success: false, output: problem) }
    let def = try GridFrameCss.migrate(raw)
    let dir = try Self.frameDirectory(project, def["id"])
    let isNew = !FileManager.default.fileExists(atPath: dir)
    try await ProjectLock.frames.run(project) {
      try write(def, project: project, widths: Self.widths(project: project), groupLayouts: await readGroupLayouts(project, problems: nil))
    }
    guard isNew else { return PluginCommands.Result(success: true, output: "") }
    guard let plugins else { return PluginCommands.Result(success: false, output: "no plugin commands") }
    return await plugins.add(dir, project, snapshot)
  }

  /// Unregisters the frame and removes its directory. The id is checked before the CLI runs.
  public func deleteFrame(id: String, project: String) async throws -> PluginCommands.Result {
    let dir = try Self.frameDirectory(project: project, id: id)
    guard let plugins else { return PluginCommands.Result(success: false, output: "no plugin commands") }
    let result = await plugins.remove(id, project)
    // `rmSync(dir, { recursive: true, force: true })`: a missing directory is fine, one that
    // cannot be removed is not.
    if FileManager.default.fileExists(atPath: dir) { try FileManager.default.removeItem(atPath: dir) }
    return result
  }
}

/// The sentences a write pass collects, handed into the lock's body.
final class ProblemList: Sendable {
  private let list = Mutex<[String]>([])
  var items: [String] { list.withLock { $0 } }
  func append(_ item: String) { list.withLock { $0.append(item) } }
}
