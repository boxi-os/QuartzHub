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
/// Paths are strings with the bytes of the disk (`NodePath`).
public enum JSONStore {
  public enum ReadResult: Equatable, Sendable {
    case ok(JSONValue)
    /// No file: the normal state before anything has been saved.
    case missing
    /// A file that exists but could not be read or parsed, or holds neither an object nor a list.
    /// `quarantinedAs` is nil when even moving it aside failed.
    case unreadable(quarantinedAs: String?)
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
    public let path: String
    public let quarantinedAs: String?
    public let at: Date
  }

  private static let quarantined = Mutex<[QuarantinedFile]>([])

  /// What had to be moved aside during this session, for the settings page to report.
  public static func quarantinedFiles() -> [QuarantinedFile] {
    quarantined.withLock { $0 }
  }

  public static func read(_ path: String) -> ReadResult {
    let data: Data
    do {
      data = try Posix.read(path)
    } catch let error as NodeFileError where error.code == ENOENT {
      return .missing
    } catch {
      return .unreadable(quarantinedAs: quarantine(path))
    }
    guard let value = try? JSJSON.parse(data) else {
      return .unreadable(quarantinedAs: quarantine(path))
    }
    switch value {
    case .object, .array: return .ok(value)
    default: return .unreadable(quarantinedAs: quarantine(path))
    }
  }

  /// Reads without moving anything aside: for a file that belongs to someone else, or one only
  /// looked at. Unreadable is reported, never fixed.
  public static func peek(_ path: String) -> ReadResult {
    let data: Data
    do {
      data = try Posix.read(path)
    } catch let error as NodeFileError where error.code == ENOENT {
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
  public static func read(_ path: String, orEmpty shape: Shape) -> JSONValue {
    guard case .ok(let value) = read(path) else { return shape.empty }
    guard shape.matches(value) else {
      _ = quarantine(path)
      return shape.empty
    }
    return value
  }

  public static func write(_ value: JSONValue, to path: String) throws {
    try writeAtomic(Data(JSJSON.stringify(value).utf8), to: path)
  }

  /// The write half for a file that is not JSON (a generated frame module, say, that Quartz imports
  /// in a process already running). Fails with Node's error, as QuartzControl's `writeFileAtomic`
  /// did (`EACCES: permission denied, open '<path>.tmp-<pid>-<8 hex>'`).
  public static func writeAtomic(_ data: Data, to path: String) throws {
    let suffix = UUID().uuidString.lowercased().prefix(8)
    let tmp = "\(path).tmp-\(getpid())-\(suffix)"
    do {
      // 0o666 before the umask, as Node's open(path, 'w') does; the rename then gives the target
      // these permissions, exactly as QuartzControl's write does.
      let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
      guard fd >= 0 else { throw NodeFileError(code: errno, syscall: "open", path: tmp) }
      var failure: Error?
      data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
          let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
          if written < 0 {
            if errno == EINTR { continue }
            failure = NodeFileError(code: errno, syscall: "write", path: nil)
            return
          }
          offset += written
        }
      }
      // Without this the rename can land before the data does: the one crash window a rename
      // alone does not close.
      if failure == nil && fsync(fd) != 0 { failure = NodeFileError(code: errno, syscall: "fsync", path: nil) }
      close(fd)
      if let failure { throw failure }
      guard rename(tmp, path) == 0 else { throw NodeFileError(code: errno, syscall: "rename", path: "\(tmp)' -> '\(path)") }
    } catch {
      unlink(tmp)
      throw error
    }
  }

  static func quarantine(_ path: String, now: Date = Date()) -> String? {
    let target = "\(path).corrupt-\(quarantineStamp(now))"
    let moved = rename(path, target) == 0
    let entry = QuarantinedFile(path: path, quarantinedAs: moved ? target : nil, at: now)
    quarantined.withLock { $0.append(entry) }
    return moved ? target : nil
  }

  /// `new Date().toISOString().replace(/[:.]/g, '-')`: "2026-11-06T12-34-56-789Z".
  static func quarantineStamp(_ date: Date) -> String {
    JS.isoString(date).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
  }
}
