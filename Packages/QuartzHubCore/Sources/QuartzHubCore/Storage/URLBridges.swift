import Foundation

// URL forms of services that take string paths now, for the callers that have not moved yet. Each
// goes with its last caller; the file goes at the end of the NFD pass (PathHygieneTests lists it).

extension JSONStore {
  public static func read(_ url: URL) -> ReadResult { read(url.path) }
  public static func peek(_ url: URL) -> ReadResult { peek(url.path) }
  public static func read(_ url: URL, orEmpty shape: Shape) -> JSONValue { read(url.path, orEmpty: shape) }
  public static func write(_ value: JSONValue, to url: URL) throws { try write(value, to: url.path) }
  public static func writeAtomic(_ data: Data, to url: URL) throws { try writeAtomic(data, to: url.path) }
}

extension Command {
  public init(_ executable: String, _ arguments: [String] = [], in directory: URL?,
              environment: [String: String] = ProcessInfo.processInfo.environment, input: Data? = nil, timeout: Duration? = nil) {
    self.init(executable, arguments, in: directory?.path, environment: environment, input: input, timeout: timeout)
  }
}

extension ToolEnvironment {
  public func command(_ executable: String, _ arguments: [String] = [], in directory: URL?,
                      input: Data? = nil, timeout: Duration? = nil) -> Command {
    command(executable, arguments, in: directory?.path, input: input, timeout: timeout)
  }
}

extension QuartzGuiDirectory {
  public init(project: URL) { self.init(project: project.path) }
  public var url: URL { URL(fileURLWithPath: path) }
}

extension ProfileDirectory {
  public init(_ url: URL) { self.init(url.path) }
  public var url: URL { URL(fileURLWithPath: path) }
}

extension ProjectPrefsStore {
  public static func read(project: URL) -> ProjectPrefs { read(project: project.path) }
  public static func write(_ prefs: ProjectPrefs, project: URL) throws { try write(prefs, project: project.path) }
  public static func update(project: URL, _ change: (inout ProjectPrefs) -> Void) throws { try update(project: project.path, change) }
}

extension ProjectPrefs {
  public func buildDirectory(project: URL) -> URL { URL(fileURLWithPath: buildDirectory(project: project.path)) }
}

extension ContentFolder {
  public static func path(project: URL) -> URL { URL(fileURLWithPath: path(project: project.path)) }
  public static func status(project: URL) throws -> Status { try status(project: project.path) }
  public static func withSymlinkParked<T>(project: URL, _ body: () async throws -> T) async throws -> T {
    try await withSymlinkParked(project: project.path, body)
  }
}

extension ConfigFile {
  public static func path(project: URL) -> URL { URL(fileURLWithPath: path(project: project.path)) }
  public static func read(project: URL, runtime: RuntimeLocation = .current) async throws -> QuartzConfig {
    try await read(project: project.path, runtime: runtime)
  }
  public static func write(_ config: QuartzConfig, project: URL, runtime: RuntimeLocation = .current,
                           snapshot: SnapshotStore.Take? = nil) async throws {
    try await write(config, project: project.path, runtime: runtime, snapshot: snapshot)
  }
}

extension FramePaths {
  public static func ownFramePath(project: URL, _ path: String) -> String? { ownFramePath(project: project.path, path) }
}

extension PluginCommands {
  public static func readLockfile(project: URL) throws -> JSONValue? { try readLockfile(project: project.path) }
}

extension ProjectPaths {
  public static func repointProjectPaths(from: URL, to: URL, runtime: RuntimeLocation = .current) async throws {
    try await repointProjectPaths(from: from.path, to: to.path, runtime: runtime)
  }
  public static func repointAuthoredFrames(project: URL, runtime: RuntimeLocation = .current) async throws {
    try await repointAuthoredFrames(project: project.path, runtime: runtime)
  }
}
