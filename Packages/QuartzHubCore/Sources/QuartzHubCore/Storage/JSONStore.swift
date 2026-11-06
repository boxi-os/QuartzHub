import Foundation
import Synchronization

/// How QuartzHub reads and writes the small JSON stores it shares with QuartzControl. A port of
/// `electron/main/services/jsonStore.ts`; read its header for the incident behind it. In short:
///
/// - Writing goes through a temp file in the same directory, `fsync`, then `rename`, so a reader
///   only ever sees the old file or the new one.
/// - Reading tells "no file yet" from "a file that cannot be read". The second is moved aside as
///   `<name>.corrupt-<timestamp>` and never answered with a default a later write could commit.
///
/// Names and bytes are QuartzControl's, because both apps meet in the same folders: the temp file
/// is `<name>.tmp-<pid>-<8 hex>`, the quarantine timestamp is `toISOString()` with ':' and '.'
/// replaced by '-', and the text is `JSON.stringify(value, null, 2)` without a final newline.
public enum JSONStore {
  public enum ReadResult: Equatable, Sendable {
    case ok(JSONValue)
    /// No file: the normal state before anything has been saved.
    case missing
    /// A file that exists but could not be read or parsed, or holds neither an object nor a list.
    /// `quarantinedAs` is nil when even moving it aside failed.
    case unreadable(quarantinedAs: URL?)
  }

  public enum Shape: Sendable {
    case object
    case array

    var empty: JSONValue { self == .object ? .object(JSONObject()) : .array([]) }

    func matches(_ value: JSONValue) -> Bool {
      switch (self, value) {
      case (.object, .object), (.array, .array): true
      default: false
      }
    }
  }

  public struct QuarantinedFile: Equatable, Sendable {
    public let path: URL
    public let quarantinedAs: URL?
    public let at: Date
  }

  private static let quarantined = Mutex<[QuarantinedFile]>([])

  /// What had to be moved aside during this session, for the settings page to report.
  public static func quarantinedFiles() -> [QuarantinedFile] {
    quarantined.withLock { $0 }
  }

  public static func read(_ url: URL) -> ReadResult {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return .missing
    } catch {
      return .unreadable(quarantinedAs: quarantine(url))
    }
    guard let value = try? JSJSON.parse(data) else {
      return .unreadable(quarantinedAs: quarantine(url))
    }
    switch value {
    case .object, .array: return .ok(value)
    default: return .unreadable(quarantinedAs: quarantine(url))
    }
  }

  /// Reads without moving anything aside: for a file that belongs to someone else, such as
  /// QuartzControl's profile during the takeover. Unreadable is reported, never fixed.
  public static func peek(_ url: URL) -> ReadResult {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return .missing
    } catch {
      return .unreadable(quarantinedAs: nil)
    }
    guard let value = try? JSJSON.parse(data), value.objectValue != nil || value.arrayValue != nil else {
      return .unreadable(quarantinedAs: nil)
    }
    return .ok(value)
  }

  /// The common case, `readJsonFileOr`: one shape, one empty default. A file of the other shape
  /// (a list where an object belongs) is as broken as unparseable JSON and is moved aside too.
  public static func read(_ url: URL, orEmpty shape: Shape) -> JSONValue {
    guard case .ok(let value) = read(url) else { return shape.empty }
    guard shape.matches(value) else {
      _ = quarantine(url)
      return shape.empty
    }
    return value
  }

  public static func write(_ value: JSONValue, to url: URL) throws {
    try writeAtomic(Data(JSJSON.stringify(value).utf8), to: url)
  }

  /// The write half for a file that is not JSON (a generated frame module, say, that Quartz imports
  /// in a process already running).
  public static func writeAtomic(_ data: Data, to url: URL) throws {
    let suffix = UUID().uuidString.lowercased().prefix(8)
    let tmp = url.deletingLastPathComponent()
      .appendingPathComponent("\(url.lastPathComponent).tmp-\(getpid())-\(suffix)")
    do {
      // 0o666 before the umask, as Node's open(path, 'w') does; the rename then gives the target
      // these permissions, exactly as QuartzControl's write does.
      let fd = open(tmp.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
      guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      var failure: Error?
      data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
          let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
          if written < 0 {
            if errno == EINTR { continue }
            failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            return
          }
          offset += written
        }
      }
      // Without this the rename can land before the data does: the one crash window a rename
      // alone does not close.
      if failure == nil && fsync(fd) != 0 { failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      close(fd)
      if let failure { throw failure }
      guard rename(tmp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    } catch {
      unlink(tmp.path)
      throw error
    }
  }

  static func quarantine(_ url: URL, now: Date = Date()) -> URL? {
    let target = url.deletingLastPathComponent()
      .appendingPathComponent("\(url.lastPathComponent).corrupt-\(quarantineStamp(now))")
    let moved = rename(url.path, target.path) == 0
    let entry = QuarantinedFile(path: url, quarantinedAs: moved ? target : nil, at: now)
    quarantined.withLock { $0.append(entry) }
    return moved ? target : nil
  }

  /// `new Date().toISOString().replace(/[:.]/g, '-')`: "2026-11-06T12-34-56-789Z".
  static func quarantineStamp(_ date: Date) -> String {
    JS.isoString(date).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
  }
}
