import Darwin
import Foundation

/// File operations on paths as strings, for writers whose names must reach the disk as they are.
///
/// Foundation decomposes a path on its way to the file system: `URL(fileURLWithPath:).path`,
/// `Data.write(to:)`, `createFile`, `createDirectory`, `copyItem`, `moveItem` and
/// `createSymbolicLink` all turn "Über" into U+0055 U+0308 (measured on APFS, macOS 27, through
/// `readdir`). APFS finds the file under either form, but the name that is stored is the bytes that
/// were given, and Node reads those: Quartz would make another slug of a page QuartzHub wrote than
/// of the same page QuartzControl wrote. POSIX takes the UTF-8 of the string as it is.
enum Posix {
  enum Kind: Sendable { case file, directory, link, other }

  static func error(_ syscall: String, _ path: String) -> NodeFileError { NodeFileError(code: errno, syscall: syscall, path: path) }

  /// `lstat`: the entry itself; nil when there is none.
  static func kind(_ path: String) -> Kind? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    switch info.st_mode & S_IFMT {
    case S_IFREG: return .file
    case S_IFDIR: return .directory
    case S_IFLNK: return .link
    default: return .other
    }
  }

  /// `existsSync`: follows a link, so a dangling one is not there.
  static func exists(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0
  }

  /// The names in a folder, as `readdir` gives them, sorted by their bytes (libuv's scandir sorts
  /// the same way); nil when it cannot be read.
  static func entries(_ dir: String) -> [(name: String, kind: Kind)]? {
    guard let stream = opendir(dir) else { return nil }
    defer { closedir(stream) }
    var result: [(String, Kind)] = []
    while let entry = readdir(stream) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
        String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
      }
      if name == "." || name == ".." { continue }
      let kind: Kind = switch Int32(entry.pointee.d_type) {
      case DT_DIR: .directory
      case DT_REG: .file
      case DT_LNK: .link
      default: .other
      }
      result.append((name, kind))
    }
    return result.sorted { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }
  }

  /// `mkdir -p`.
  static func mkdirs(_ path: String) throws {
    var built = path.hasPrefix("/") ? "" : "."
    for part in path.split(separator: "/") {
      built += "/\(part)"
      if mkdir(built, 0o777) != 0, errno != EEXIST { throw error("mkdir", built) }
    }
  }

  static func read(_ path: String) throws -> Data {
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else { throw error("open", path) }
    defer { close(fd) }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
      let n = Darwin.read(fd, &buffer, buffer.count)
      if n < 0 { throw error("read", path) }
      if n == 0 { return data }
      data.append(buffer, count: n)
    }
  }

  static func write(_ path: String, _ data: Data) throws {
    let fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0o666)
    guard fd >= 0 else { throw error("open", path) }
    defer { close(fd) }
    try data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
        if n < 0 { throw error("write", path) }
        offset += n
      }
    }
  }

  static func readlink(_ path: String) throws -> String {
    var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
    let n = Darwin.readlink(path, &buffer, buffer.count)
    guard n >= 0 else { throw error("readlink", path) }
    return String(decoding: buffer.prefix(n), as: UTF8.self)
  }

  static func symlink(_ target: String, _ path: String) throws {
    guard Darwin.symlink(target, path) == 0 else {
      let code = errno
      throw NodeFileError(code: code, syscall: "symlink '\(target)' ->", path: path)
    }
  }

  static func unlink(_ path: String) throws {
    guard Darwin.unlink(path) == 0 else { throw error("unlink", path) }
  }

  static func rename(_ from: String, _ to: String) throws {
    guard Darwin.rename(from, to) == 0 else { throw error("rename", from) }
  }
}
