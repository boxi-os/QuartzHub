import Compression
import Foundation

/// What a font file says about the cut it holds: a port of `fontFile.ts`. Three numbers out of two
/// tables (OS/2's weight class and fsSelection, head's macStyle) or the `wght` axis of `fvar`,
/// in the three containers a font comes in: sfnt (TTF/OTF), WOFF (zlib per table) and WOFF2 (one
/// brotli stream). Everything it cannot read ends at nil, never at a throw: a font this cannot read
/// is still a font the browser can use.
///
/// **Every decompression has a ceiling the file does not set** (QuartzControl measured an 863-byte
/// WOFF2 that unpacked to 512 MiB and took the main process to 1.1 GB). 64 MiB, or the file's own
/// length where that is smaller; past it the parse is nil. Here the decoder stops at the ceiling and
/// never holds more.
public enum FontFile {
  public struct Face: Equatable, Sendable {
    /// `400`, or `400 700` for the range of a variable font's wght axis.
    public var weight: String
    public var italic: Bool
  }

  public static let maxTableBytes = 64 * 1024 * 1024
  /// The largest font file worth reading.
  public static let maxFileBytes = maxTableBytes

  /// The 63 tags WOFF2 names by index ("Known Table Tags"); the order is the encoding.
  static let knownTags = [
    "cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "cvt ", "fpgm", "glyf", "loca",
    "prep", "CFF ", "VORG", "EBDT", "EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea",
    "vmtx", "BASE", "GDEF", "GPOS", "GSUB", "EBSC", "JSTF", "MATH", "CBDT", "CBLC", "COLR", "CPAL",
    "SVG ", "sbix", "acnt", "avar", "bdat", "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar",
    "gvar", "hsty", "just", "lcar", "mort", "morx", "opbd", "prop", "trak", "Zapf", "Silf", "Glat",
    "Gloc", "Feat", "Sill"
  ]

  struct Unreadable: Error {}

  /// Node's `Buffer` reads: out of range throws.
  struct Bytes {
    let data: [UInt8]
    var count: Int { data.count }
    func u8(_ at: Int) throws -> UInt8 {
      guard at >= 0, at < data.count else { throw Unreadable() }
      return data[at]
    }
    func u16(_ at: Int) throws -> Int {
      guard at >= 0, at + 2 <= data.count else { throw Unreadable() }
      return Int(data[at]) << 8 | Int(data[at + 1])
    }
    func u32(_ at: Int) throws -> Int {
      guard at >= 0, at + 4 <= data.count else { throw Unreadable() }
      return Int(data[at]) << 24 | Int(data[at + 1]) << 16 | Int(data[at + 2]) << 8 | Int(data[at + 3])
    }
    func i32(_ at: Int) throws -> Int {
      let value = try u32(at)
      return value >= 0x8000_0000 ? value - 0x1_0000_0000 : value
    }
    /// `toString('latin1', from, to)`: clamped, never throws.
    func latin1(_ from: Int, _ to: Int) -> String {
      let start = max(0, min(from, data.count)), end = max(start, min(to, data.count))
      return String(data[start..<end].map { Character(Unicode.Scalar($0)) })
    }
    /// `subarray(from, to)`: clamped.
    func sub(_ from: Int, _ to: Int) -> Bytes {
      let start = max(0, min(from, data.count)), end = max(start, min(to, data.count))
      return Bytes(data: Array(data[start..<end]))
    }
  }

  /// WOFF2's variable-length integer: seven bits per byte, the high bit continues, at most five.
  static func base128(_ bytes: Bytes, _ pos: Int) throws -> (Int, Int) {
    var value = 0
    for i in 0..<5 {
      let byte = try bytes.u8(pos + i)
      value = value * 128 + Int(byte & 0x7F)
      if byte & 0x80 == 0 { return (value, pos + i + 1) }
    }
    throw Unreadable()
  }

  static func sfntTables(_ bytes: Bytes) throws -> [String: Bytes] {
    let count = try bytes.u16(4)
    var tables: [String: Bytes] = [:]
    for i in 0..<count {
      let entry = 12 + i * 16
      let tag = bytes.latin1(entry, entry + 4)
      let offset = try bytes.u32(entry + 8), length = try bytes.u32(entry + 12)
      if offset + length <= bytes.count { tables[tag] = bytes.sub(offset, offset + length) }
    }
    return tables
  }

  static func woffTables(_ bytes: Bytes) throws -> [String: Bytes] {
    let count = try bytes.u16(12)
    var tables: [String: Bytes] = [:]
    for i in 0..<count {
      let entry = 44 + i * 20
      let tag = bytes.latin1(entry, entry + 4)
      let offset = try bytes.u32(entry + 4), compressed = try bytes.u32(entry + 8), original = try bytes.u32(entry + 12)
      let raw = bytes.sub(offset, offset + compressed)
      if compressed == original {
        tables[tag] = raw
      } else {
        guard let inflated = inflateZlib(raw.data, limit: min(original, maxTableBytes)) else { throw Unreadable() }
        tables[tag] = Bytes(data: inflated)
      }
    }
    return tables
  }

  /// One brotli stream, the tables in directory order. glyf and loca invert the version rule:
  /// there 0 *is* the transform and 3 is none; for every other table 0 is untransformed.
  static func woff2Tables(_ bytes: Bytes) throws -> [String: Bytes] {
    let count = try bytes.u16(12)
    var pos = 48
    var directory: [(tag: String, length: Int)] = []
    for _ in 0..<count {
      let flags = Int(try bytes.u8(pos))
      pos += 1
      let known = flags & 0x3F
      let tag: String
      if known == 0x3F {
        tag = bytes.latin1(pos, pos + 4)
        pos += 4
      } else {
        tag = known < knownTags.count ? knownTags[known] : "?\(known)"
      }
      let version = (flags >> 6) & 0x03
      var length: Int
      (length, pos) = try base128(bytes, pos)
      let transformed = tag == "glyf" || tag == "loca" ? version == 0 : version != 0
      if transformed { (length, pos) = try base128(bytes, pos) }
      directory.append((tag, length))
    }
    let expected = directory.reduce(0) { $0 + $1.length }
    guard let stream = decompress(Array(bytes.data[min(pos, bytes.count)...]), COMPRESSION_BROTLI, limit: min(expected, maxTableBytes)) else {
      throw Unreadable()
    }
    var tables: [String: Bytes] = [:]
    var offset = 0
    for (tag, length) in directory {
      if offset + length <= stream.count { tables[tag] = Bytes(data: Array(stream[offset..<(offset + length)])) }
      offset += length
    }
    return tables
  }

  static func tables(_ bytes: Bytes) throws -> [String: Bytes] {
    switch bytes.latin1(0, 4) {
    case "wOF2": try woff2Tables(bytes)
    case "wOFF": try woffTables(bytes)
    default: try sfntTables(bytes)
    }
  }

  /// `Math.round`: half up, toward +∞.
  static func jsRound(_ value: Double) -> Double {
    let floor = value.rounded(.down)
    return value - floor >= 0.5 ? floor + 1 : floor
  }

  /// The weight and slant of a font file, or nil. A variable font's wght axis wins over the static
  /// weight: it is the range the browser can use, and without it every bold cut is synthesised.
  public static func face(_ data: Data) -> Face? {
    guard let tables = try? tables(Bytes(data: Array(data))) else { return nil }
    let os2 = tables["OS/2"], head = tables["head"], fvar = tables["fvar"]
    do {
      var weight: String?
      if let fvar, fvar.count >= 16 {
        let axesOffset = try fvar.u16(4), axisCount = try fvar.u16(8), axisSize = try fvar.u16(10)
        for i in 0..<axisCount {
          let axis = axesOffset + i * axisSize
          if axis + 20 > fvar.count { break }
          if fvar.latin1(axis, axis + 4) != "wght" { continue }
          // Fixed 16.16; rounding keeps `400 700` out of `399.99902 700`.
          let low = jsRound(Double(try fvar.i32(axis + 4)) / 65536), high = jsRound(Double(try fvar.i32(axis + 12)) / 65536)
          if low > 0 && high >= low { weight = low == high ? JSJSON.numberToString(low) : "\(JSJSON.numberToString(low)) \(JSJSON.numberToString(high))" }
          break
        }
      }
      if weight == nil, let os2, os2.count >= 6 {
        let weightClass = try os2.u16(4)
        if (1...1000).contains(weightClass) { weight = String(weightClass) }
      }
      // Two places say it, and they disagree in the wild: either is enough.
      let italicByOs2 = os2.map { $0.count >= 64 ? ((try? $0.u16(62)) ?? 0) & 0x01 != 0 : false } ?? false
      let italicByHead = head.map { $0.count >= 46 ? ((try? $0.u16(44)) ?? 0) & 0x02 != 0 : false } ?? false
      guard let weight else { return nil }
      return Face(weight: weight, italic: italicByOs2 || italicByHead)
    } catch {
      return nil
    }
  }

  // MARK: decompression

  /// A zlib stream (header, raw deflate, Adler-32) as Node's `inflateSync` reads it: a bad header, a
  /// preset dictionary, a cut stream or a wrong checksum fail.
  static func inflateZlib(_ input: [UInt8], limit: Int) -> [UInt8]? {
    guard input.count >= 6 else { return nil }
    let cmf = Int(input[0]), flg = Int(input[1])
    guard cmf & 0x0F == 8, (cmf << 8 | flg) % 31 == 0, flg & 0x20 == 0 else { return nil }
    guard let output = decompress(Array(input[2...]), COMPRESSION_ZLIB, limit: limit) else { return nil }
    let stored = input.suffix(4).reduce(0) { $0 << 8 | UInt32($1) }
    return adler32(output) == stored ? output : nil
  }

  static func adler32(_ data: [UInt8]) -> UInt32 {
    var a: UInt32 = 1, b: UInt32 = 0
    for chunk in stride(from: 0, to: data.count, by: 5552) {
      for byte in data[chunk..<min(chunk + 5552, data.count)] {
        a += UInt32(byte)
        b += a
      }
      a %= 65521
      b %= 65521
    }
    return b << 16 | a
  }

  /// Decodes a whole stream, nil when it is not one, ends early, or would pass `limit` bytes.
  static func decompress(_ input: [UInt8], _ algorithm: compression_algorithm, limit: Int) -> [UInt8]? {
    let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    defer { stream.deallocate() }
    guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, algorithm) == COMPRESSION_STATUS_OK else { return nil }
    defer { compression_stream_destroy(stream) }
    let chunk = 64 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    defer { buffer.deallocate() }
    var output: [UInt8] = []
    // An empty stream is no stream (Node: "unexpected end of file").
    guard !input.isEmpty else { return nil }
    return input.withUnsafeBufferPointer { source -> [UInt8]? in
      stream.pointee.src_ptr = source.baseAddress!
      stream.pointee.src_size = source.count
      while true {
        stream.pointee.dst_ptr = buffer
        stream.pointee.dst_size = chunk
        let before = stream.pointee.src_size
        let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
        let produced = chunk - stream.pointee.dst_size
        if output.count + produced > limit { return nil }
        output.append(contentsOf: UnsafeBufferPointer(start: buffer, count: produced))
        switch status {
        case COMPRESSION_STATUS_END: return output
        case COMPRESSION_STATUS_OK:
          if produced == 0 && stream.pointee.src_size == before { return nil }
        default: return nil
        }
      }
    }
  }
}
