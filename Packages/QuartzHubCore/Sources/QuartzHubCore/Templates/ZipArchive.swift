import Compression
import Foundation

/// QuartzControl's `zipArchive.ts`: the minimal ZIP a template package is (and an ePub, later).
/// Hand-rolled as there: the subset is small and fully specified. Deflate is Apple's
/// Compression framework (`COMPRESSION_ZLIB` is a raw deflate stream, ZIP's method 8, as
/// `deflateRawSync` is), the CRC-32 is the table below.
///
/// Not byte-equal to QuartzControl's archives where an entry is deflated: Apple's encoder is zlib
/// at level 5, Node's `deflateRawSync` level 6, so the streams differ (both inflate to the same
/// bytes). Everything else, the headers and the choice between store and deflate included, is
/// QuartzControl's; an archive whose entries are all stored is byte-equal (ZipArchiveTests).
///
/// Not supported, as there: ZIP64 (refused on write), encryption, multi-disk archives, directory
/// entries (a folder is the `/` in a name).
public enum ZipArchive {
  public struct Entry: Sendable {
    public var name: String
    public var data: Data
    /// Uncompressed whatever deflate would gain (an ePub's `mimetype`, EPUB OCF 3.3 §4.3).
    public var store: Bool

    public init(name: String, data: Data, store: Bool = false) {
      self.name = name
      self.data = data
      self.store = store
    }
  }

  /// The files of an archive in the order of its directory, as QuartzControl's `Map`: a name that
  /// comes twice keeps its first place and its last content.
  public struct Files: Sendable {
    public private(set) var names: [String] = []
    public private(set) var contents: [String: Data] = [:]

    public init() {}

    public subscript(name: String) -> Data? { contents[name] }
    public var count: Int { names.count }

    mutating func set(_ name: String, _ data: Data) {
      if contents.updateValue(data, forKey: name) == nil { names.append(name) }
    }
  }

  public struct Failure: Error, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { "Error: " + message }
  }

  static let localSignature: UInt32 = 0x0403_4B50
  static let centralSignature: UInt32 = 0x0201_4B50
  static let endSignature: UInt32 = 0x0605_4B50
  /// Bit 11: the name is UTF-8, not CP437 ("teile/schriften/Ünicode.woff2" survives).
  static let utf8Flag: UInt16 = 0x0800
  static let methodDeflate: UInt16 = 8
  static let methodStore: UInt16 = 0
  /// The whole size field; without ZIP64 a larger entry is refused, not wrapped.
  static let maxSize = 0xFFFF_FFFF

  /// What a whole package may unpack to, checked against the directory's declared sizes before
  /// the first byte is unpacked (QuartzControl's reasons: every entry is held in memory at once,
  /// and a 522-KB file reaches it at deflate's 1000:1).
  public static let maxUnpackedBytes = 256 * 1024 * 1024

  // MARK: - Writing

  /// ZIP's MS-DOS date and time: two-second steps, no zone (local time, as `getHours()`), the
  /// year clamped to 1980…2107 and nothing else.
  static func dosDateTime(_ date: Date, calendar: Calendar = .current) -> (time: UInt16, date: UInt16) {
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let year = min(max(c.year!, 1980), 2107)
    return (UInt16(c.hour! << 11 | c.minute! << 5 | c.second! / 2), UInt16((year - 1980) << 9 | c.month! << 5 | c.day!))
  }

  public static func create(_ entries: [Entry], modified: Date = Date()) throws -> Data {
    let (time, date) = dosDateTime(modified)
    var locals: [UInt8] = []
    var centrals: [UInt8] = []
    for entry in entries {
      let name = Array(entry.name.utf8)
      let raw = [UInt8](entry.data)
      let deflated = deflateRaw(raw)
      // An already-compressed payload (a woff2, a png) routinely deflates to more than it was.
      let useDeflate = !entry.store && deflated.count < raw.count
      let body = useDeflate ? deflated : raw
      let method = useDeflate ? methodDeflate : methodStore
      if raw.count > maxSize || body.count > maxSize {
        throw Failure(message: L10n.t("main.zipEntryTooLarge", ["name": entry.name]))
      }
      let checksum = crc32(raw)
      let offset = locals.count
      guard offset <= maxSize else { throw Failure(message: L10n.t("main.zipEntryTooLarge", ["name": entry.name])) }

      locals.put32(localSignature)
      locals.put16(20) // version needed: 2.0, i.e. deflate
      locals.put16(utf8Flag)
      locals.put16(method)
      locals.put16(time)
      locals.put16(date)
      locals.put32(checksum)
      locals.put32(UInt32(body.count))
      locals.put32(UInt32(raw.count))
      locals.put16(UInt16(name.count))
      locals.put16(0) // no extra field
      locals += name
      locals += body

      centrals.put32(centralSignature)
      centrals.put16(20) // version made by
      centrals.put16(20) // version needed
      centrals.put16(utf8Flag)
      centrals.put16(method)
      centrals.put16(time)
      centrals.put16(date)
      centrals.put32(checksum)
      centrals.put32(UInt32(body.count))
      centrals.put32(UInt32(raw.count))
      centrals.put16(UInt16(name.count))
      centrals.put16(0) // extra
      centrals.put16(0) // comment
      centrals.put16(0) // disk number start
      centrals.put16(0) // internal attributes
      // The unix mode in the high 16 bits: 0o644 extracts readable and not executable.
      centrals.put32(UInt32(0o100644) << 16)
      centrals.put32(UInt32(offset))
      centrals += name
    }
    var end: [UInt8] = []
    end.put32(endSignature)
    end.put16(0) // this disk
    end.put16(0) // disk with the central directory
    end.put16(UInt16(truncatingIfNeeded: entries.count))
    end.put16(UInt16(truncatingIfNeeded: entries.count))
    end.put32(UInt32(truncatingIfNeeded: centrals.count))
    end.put32(UInt32(truncatingIfNeeded: locals.count))
    end.put16(0) // comment length
    return Data(locals + centrals + end)
  }

  public static func write(_ entries: [Entry], to url: String) throws {
    try Posix.write(url, create(entries))
  }

  // MARK: - Reading

  /// Through the central directory, not by scanning local headers: only the directory is
  /// authoritative (a local header may carry zeroed sizes with a trailing data descriptor).
  ///
  /// Where QuartzControl's reader ran past the end of the buffer (an offset that points outside),
  /// Node threw a `RangeError` no user could act on; here that is the damaged directory or header
  /// it is, whichever was being read.
  public static func read(_ data: Data) throws -> Files {
    let buffer = [UInt8](data)
    // The end record sits last but before a comment of up to 65535 bytes, so it is searched backwards.
    var end = -1
    if buffer.count >= 22 {
      let lowest = max(0, buffer.count - 22 - 0xFFFF)
      for i in stride(from: buffer.count - 22, through: lowest, by: -1) where buffer.le32(i) == endSignature {
        end = i
        break
      }
    }
    guard end >= 0 else { throw Failure(message: L10n.t("main.zipNotAPackage")) }
    let badDirectory = Failure(message: L10n.t("main.zipBadDirectory"))
    let badHeader = Failure(message: L10n.t("main.zipBadHeader"))

    let count = Int(buffer.le16(end + 10)!)
    var cursor = Int(buffer.le32(end + 16)!)
    var files = Files()
    var unpacked = 0
    for _ in 0..<count {
      guard buffer.le32(cursor) == centralSignature, let method = buffer.le16(cursor + 10), let expectedCrc = buffer.le32(cursor + 16),
            let compressedSize = buffer.le32(cursor + 20).map(Int.init), let uncompressedSize = buffer.le32(cursor + 24).map(Int.init),
            let nameLength = buffer.le16(cursor + 28).map(Int.init), let extraLength = buffer.le16(cursor + 30).map(Int.init),
            let commentLength = buffer.le16(cursor + 32).map(Int.init), let localOffset = buffer.le32(cursor + 42).map(Int.init)
      else { throw badDirectory }
      // Node's toString clamps at the end of the buffer; so does this.
      let name = String(decoding: buffer.clamped(cursor + 46, cursor + 46 + nameLength), as: UTF8.self)
      cursor += 46 + nameLength + extraLength + commentLength

      // A directory entry carries no payload.
      if name.hasSuffix("/") { continue }
      guard isSafeEntryName(name) else { throw Failure(message: L10n.t("main.zipEntryUnsafeName", ["name": name])) }

      guard buffer.le32(localOffset) == localSignature else { throw badHeader }
      // The local header's own lengths locate the data: its extra field is often padded differently.
      guard let localNameLength = buffer.le16(localOffset + 26).map(Int.init), let localExtraLength = buffer.le16(localOffset + 28).map(Int.init)
      else { throw badHeader }
      let start = localOffset + 30 + localNameLength + localExtraLength
      let body = buffer.clamped(start, start + compressedSize)

      // Both ceilings before the first byte is unpacked: the entry's own claim (a low lie is
      // caught below), the sum over all entries for the whole package.
      unpacked += uncompressedSize
      guard unpacked <= maxUnpackedBytes else {
        throw Failure(message: L10n.t("main.zipTooLarge", ["limit": String(maxUnpackedBytes / 1024 / 1024)]))
      }

      let corrupt = Failure(message: L10n.t("main.zipEntryCorrupt", ["name": name]))
      let content: [UInt8]
      switch method {
      case methodStore: content = Array(body)
      case methodDeflate:
        // An empty file is not unpacked (Python deflates it to `03 00`, the others store it).
        if uncompressedSize == 0 { content = [] }
        else {
          guard let inflated = FontFile.decompress(Array(body), COMPRESSION_ZLIB, limit: uncompressedSize) else { throw corrupt }
          content = inflated
        }
      default: throw Failure(message: L10n.t("main.zipUnsupportedMethod", ["method": String(method)]))
      }
      guard content.count == uncompressedSize, crc32(content) == expectedCrc else { throw corrupt }
      files.set(name, Data(content))
    }
    return files
  }

  public static func read(contentsOf url: String) throws -> Files {
    guard FileManager.default.fileExists(atPath: url) else { throw Failure(message: L10n.t("main.zipFileMissing")) }
    return try read(Posix.read(url))
  }

  /// Nothing QuartzHub writes has an absolute name, a `..` segment, a drive letter or a NUL; an
  /// archive that does was written by something else and is refused whole.
  static func isSafeEntryName(_ name: String) -> Bool {
    if name.isEmpty || name.hasPrefix("/") || name.contains("\0") { return false }
    let units = Array(name.utf16)
    if units.count >= 2, units[1] == 0x3A, (0x41...0x5A).contains(units[0]) || (0x61...0x7A).contains(units[0]) { return false }
    return !name.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..")
  }

  // MARK: - Deflate and CRC-32

  /// A raw deflate stream of the whole input (Apple's zlib encoder).
  static func deflateRaw(_ input: [UInt8]) -> [UInt8] {
    let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    defer { stream.deallocate() }
    guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return input + [0, 0] }
    defer { compression_stream_destroy(stream) }
    let chunk = 64 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    defer { buffer.deallocate() }
    var output: [UInt8] = []
    input.withUnsafeBufferPointer { source in
      // An empty input still needs a valid pointer.
      var empty: UInt8 = 0
      withUnsafePointer(to: &empty) { fallback in
        stream.pointee.src_ptr = source.baseAddress ?? fallback
        stream.pointee.src_size = source.count
        while true {
          stream.pointee.dst_ptr = buffer
          stream.pointee.dst_size = chunk
          let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
          output.append(contentsOf: UnsafeBufferPointer(start: buffer, count: chunk - stream.pointee.dst_size))
          if status != COMPRESSION_STATUS_OK { break }
        }
      }
    }
    return output
  }

  static let crcTable: [UInt32] = (0..<256).map { n in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
  }

  static func crc32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFF_FFFF
  }
}

extension [UInt8] {
  fileprivate mutating func put16(_ value: UInt16) {
    append(UInt8(value & 0xFF))
    append(UInt8(value >> 8))
  }

  fileprivate mutating func put32(_ value: UInt32) {
    for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
  }

  /// nil past the end, where Node's readUInt16LE throws.
  fileprivate func le16(_ at: Int) -> UInt16? {
    guard at >= 0, at + 2 <= count else { return nil }
    return UInt16(self[at]) | UInt16(self[at + 1]) << 8
  }

  fileprivate func le32(_ at: Int) -> UInt32? {
    guard at >= 0, at + 4 <= count else { return nil }
    return UInt32(self[at]) | UInt32(self[at + 1]) << 8 | UInt32(self[at + 2]) << 16 | UInt32(self[at + 3]) << 24
  }

  /// `subarray(start, end)`: both ends clamped to the buffer.
  fileprivate func clamped(_ start: Int, _ end: Int) -> ArraySlice<UInt8> {
    let lower = Swift.min(Swift.max(start, 0), count)
    return self[lower..<Swift.max(lower, Swift.min(end, count))]
  }
}
