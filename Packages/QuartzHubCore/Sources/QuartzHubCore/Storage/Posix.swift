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
public enum Posix {
  enum Kind: Sendable { case file, directory, link, other }

  static func error(_ syscall: String, _ path: String) -> NodeFileError { NodeFileError(code: errno, syscall: syscall, path: path) }

  /// A path from outside (a `URL` from a panel, a path typed or decomposed by Foundation) with the
  /// bytes the disk has: each segment that exists is replaced by its name as stored, when Swift
  /// takes the two for equal ("Ü" for "U\u{308}"; case still counts). Links are not followed,
  /// unlike `realpath`, and the segments from the first one that is not there stay as they came.
  public static func onDisk(_ path: String) -> String {
    guard path.hasPrefix("/") else { return path }
    var built = ""
    var parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
    while let part = parts.first {
      parts.removeFirst()
      // ASCII has one form; only the other names are asked for.
      if part.utf8.allSatisfy({ $0 < 0x80 }) {
        built += "/" + part
        continue
      }
      guard let name = storedName(built + "/" + part), name == part else {
        return ([built] + [part] + parts).joined(separator: "/")
      }
      built += "/" + name
    }
    return built.isEmpty ? "/" : built
  }

  /// The last segment of a path as the volume stores it (`getattrlist`, `ATTR_CMN_NAME`, the entry
  /// itself, not a link's target), without reading the folder.
  static func storedName(_ path: String) -> String? {
    var request = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0, commonattr: attrgroup_t(ATTR_CMN_NAME),
                           volattr: 0, dirattr: 0, fileattr: 0, forkattr: 0)
    var buffer = [UInt8](repeating: 0, count: 4 + 8 + 4 * Int(NAME_MAX) + 1)
    guard getattrlist(path, &request, &buffer, buffer.count, UInt32(FSOPT_NOFOLLOW)) == 0 else { return nil }
    return buffer.withUnsafeBytes { raw in
      let reference = raw.baseAddress! + 4
      let offset = Int(reference.loadUnaligned(as: Int32.self))
      let length = Int(reference.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
      guard length > 0, 4 + offset + length <= raw.count else { return nil }
      return String(decoding: UnsafeRawBufferPointer(start: reference + offset, count: length - 1), as: UTF8.self)
    }
  }

  /// The one way from a file `URL` to a path: `onDisk` of its decomposed `path`.
  public static func path(_ url: URL) -> String { onDisk(url.path) } // path boundary

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
  public static func mkdirs(_ path: String) throws {
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

  /// `copyItem` for one file without the decomposed name: data and metadata (`COPYFILE_ALL`), and
  /// a target that is there is refused (`COPYFILE_EXCL`), as FileManager does.
  static func copyFile(_ from: String, _ to: String) throws {
    guard copyfile(from, to, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_EXCL)) == 0 else { throw error("copyfile", to) }
  }

  /// `moveItem` without the decomposed name: refuses a target that is there (EEXIST), as
  /// FileManager does, instead of replacing it as rename(2) would.
  static func move(_ from: String, _ to: String) throws {
    if kind(to) != nil {
      errno = EEXIST
      throw error("rename", to)
    }
    try rename(from, to)
  }
}
