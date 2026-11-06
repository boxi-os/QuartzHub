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
