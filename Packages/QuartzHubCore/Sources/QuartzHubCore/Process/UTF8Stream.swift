/// Turns bytes that arrive in pieces into text without cutting a character: the bytes of a
/// sequence whose end has not arrived yet are held back for the next piece (Node's
/// `StringDecoder`, which QuartzControl's server-log tail used; its build console used
/// `chunk.toString()` and showed two U+FFFD where a read boundary fell inside "ä").
///
/// The pieces together are exactly `String(decoding: allBytes, as: UTF8.self)`, invalid bytes
/// included: only a prefix that can still become a character is held back, and the decoder starts
/// afresh after anything else.
public struct UTF8Stream: Sendable {
  private var held: [UInt8] = []

  public init() {}

  public mutating func feed(_ bytes: some Collection<UInt8>) -> String {
    var all = held
    all.append(contentsOf: bytes)
    let complete = Self.completeLength(all)
    held = Array(all[complete...])
    return String(decoding: all[..<complete], as: UTF8.self)
  }

  /// What is still held back, at the end of the stream (as U+FFFD: it never got its end).
  public mutating func finish() -> String {
    defer { held = [] }
    return String(decoding: held, as: UTF8.self)
  }

  /// How many bytes from the front can be decoded now: all, unless the last one to three bytes are
  /// the start of a sequence that is still possible (lead byte, the allowed second byte for E0, ED,
  /// F0 and F4, continuation bytes).
  static func completeLength(_ bytes: [UInt8]) -> Int {
    let count = bytes.count
    var start = count - 1
    while start >= 0, count - start <= 3, bytes[start] & 0xC0 == 0x80 { start -= 1 }
    guard start >= 0, count - start <= 3 else { return count }
    let lead = bytes[start]
    let needed = switch lead {
    case 0xC2...0xDF: 2
    case 0xE0...0xEF: 3
    case 0xF0...0xF4: 4
    default: 1
    }
    guard needed > count - start else { return count }
    if count - start >= 2 {
      let second = bytes[start + 1]
      let possible = switch lead {
      case 0xE0: second >= 0xA0
      case 0xED: second <= 0x9F
      case 0xF0: second >= 0x90
      case 0xF4: second <= 0x8F
      default: true
      }
      if !possible { return count }
    }
    return start
  }
}
