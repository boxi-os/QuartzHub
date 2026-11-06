import Darwin
import Foundation

/// Node's `fs.cp(from, to, { recursive: true, filter, verbatimSymlinks })`, which QuartzControl's
/// duplicate uses, as far as it matters there:
///
/// - A link is copied as a link. With `verbatimSymlinks` its target stays as written; without, a
///   relative target is made absolute against the link's own folder, as Node does.
/// - A folder it creates gets the source folder's permissions after its content.
/// - `filter` gets the path relative to the root and decides for the entry and all below it.
///
/// One difference, on purpose: a file is cloned (`copyfile` with `COPYFILE_CLONE`), which on APFS
/// costs no space and no time and keeps the file's times; Node writes new ones. A socket or a FIFO
/// fails the copy, as in Node.
enum TreeCopy {
  struct UnsupportedFile: Error, CustomStringConvertible {
    let path: String
    var description: String { "cannot copy \(path): not a file, folder or link" }
  }

  /// Paths as strings: no name passes through `URL` (see `Posix`).
  static func copy(from source: String, to target: String, verbatimSymlinks: Bool,
                   filter: (String) -> Bool = { _ in true }) throws {
    try copyEntry(source, target, relative: "", verbatimSymlinks: verbatimSymlinks, filter: filter)
  }

  private static func copyEntry(_ from: String, _ to: String, relative: String, verbatimSymlinks: Bool,
                                filter: (String) -> Bool) throws {
    guard filter(relative) else { return }
    var info = stat()
    guard lstat(from, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    switch info.st_mode & S_IFMT {
    case S_IFDIR:
      // A folder that is already there (the root, which the caller made) keeps its permissions.
      var exists = stat()
      let create = lstat(to, &exists) != 0
      if create {
        guard mkdir(to, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      }
      for name in try FileManager.default.contentsOfDirectory(atPath: from).sorted() {
        try copyEntry(from + "/" + name, to + "/" + name, relative: relative.isEmpty ? name : relative + "/" + name,
                      verbatimSymlinks: verbatimSymlinks, filter: filter)
      }
      if create, chmod(to, info.st_mode & 0o7777) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    case S_IFLNK:
      // readlink and symlink, not FileManager: that decomposes the link's name ("Über" as
      // U+0055 U+0308), which Node then reads as another name.
      var target = try Posix.readlink(from)
      if !verbatimSymlinks && !target.hasPrefix("/") {
        target = FramePaths.resolve(NodePath.dirname(from) + "/" + target)
      }
      try Posix.symlink(target, to)
    case S_IFREG:
      guard copyfile(from, to, nil, copyfile_flags_t(COPYFILE_CLONE)) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    default:
      throw UnsupportedFile(path: from)
    }
  }
}
