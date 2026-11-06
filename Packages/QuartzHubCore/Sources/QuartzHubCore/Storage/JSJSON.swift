import Foundation

/// `JSON.parse` and `JSON.stringify(value, null, 2)` as Node 24 does them, for the files
/// QuartzControl writes. Checked against Node itself in `JSJSONTests` (the rule "ein Wert, den ein
/// fremdes Programm vergleicht, wird gegen das fremde Programm geprüft"); what differs on purpose
/// is listed here.
///
/// - A lone UTF-16 surrogate (`"\udc00"`) cannot live in a Swift string; it becomes U+FFFD. Node
///   would keep it and write it back as `\udc00`. QuartzControl writes no such strings.
/// - Bytes that are not UTF-8 become U+FFFD, as with Node's `readFile(path, 'utf-8')`.
public enum JSJSON {
  public struct ParseError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public let offset: Int
    public var description: String { "\(message) at byte \(offset)" }
  }

  // MARK: parse

  public static func parse(_ data: Data) throws(ParseError) -> JSONValue {
    try parse(String(decoding: data, as: UTF8.self))
  }

  public static func parse(_ text: String) throws(ParseError) -> JSONValue {
    var parser = Parser(bytes: Array(text.utf8))
    parser.skipWhitespace()
    let value = try parser.value(depth: 0)
    parser.skipWhitespace()
    guard parser.atEnd else { throw parser.error("Unexpected non-whitespace character after JSON") }
    return value
  }

  private struct Parser {
    let bytes: [UInt8]
    var position = 0

    var atEnd: Bool { position >= bytes.count }

    func error(_ message: String) -> ParseError { ParseError(message: message, offset: position) }

    // JSON whitespace only: a BOM or a no-break space is a syntax error in JSON.parse too.
    mutating func skipWhitespace() {
      while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) { position += 1 }
    }

    mutating func value(depth: Int) throws(ParseError) -> JSONValue {
      // Far deeper than any store; keeps a hostile file from overflowing the stack.
      guard depth < 512 else { throw error("Nesting too deep") }
      guard position < bytes.count else { throw error("Unexpected end of JSON input") }
      switch bytes[position] {
      case UInt8(ascii: "{"): return .object(try object(depth: depth))
      case UInt8(ascii: "["): return .array(try array(depth: depth))
      case UInt8(ascii: "\""): return .string(try string())
      case UInt8(ascii: "t"): try literal("true"); return .bool(true)
      case UInt8(ascii: "f"): try literal("false"); return .bool(false)
      case UInt8(ascii: "n"): try literal("null"); return .null
      case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
      default: throw error("Unexpected token")
      }
    }

    mutating func literal(_ word: String) throws(ParseError) {
      let expected = Array(word.utf8)
      guard position + expected.count <= bytes.count,
            Array(bytes[position..<position + expected.count]) == expected
      else { throw error("Unexpected token") }
      position += expected.count
    }

    mutating func object(depth: Int) throws(ParseError) -> JSONObject {
      position += 1
      var object = JSONObject()
      skipWhitespace()
      if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
        position += 1
        return object
      }
      while true {
        skipWhitespace()
        guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else {
          throw error("Expected property name")
        }
        let key = try string()
        skipWhitespace()
        guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw error("Expected ':'") }
        position += 1
        skipWhitespace()
        object[key] = try value(depth: depth + 1)
        skipWhitespace()
        guard position < bytes.count else { throw error("Unexpected end of JSON input") }
        if bytes[position] == UInt8(ascii: ",") { position += 1; continue }
        if bytes[position] == UInt8(ascii: "}") { position += 1; return object }
        throw error("Expected ',' or '}'")
      }
    }

    mutating func array(depth: Int) throws(ParseError) -> [JSONValue] {
      position += 1
      var items: [JSONValue] = []
      skipWhitespace()
      if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
        position += 1
        return items
      }
      while true {
        skipWhitespace()
        items.append(try value(depth: depth + 1))
        skipWhitespace()
        guard position < bytes.count else { throw error("Unexpected end of JSON input") }
        if bytes[position] == UInt8(ascii: ",") { position += 1; continue }
        if bytes[position] == UInt8(ascii: "]") { position += 1; return items }
        throw error("Expected ',' or ']'")
      }
    }

    mutating func string() throws(ParseError) -> String {
      position += 1
      var units: [UInt16] = []
      var run: [UInt8] = []
      func flush() {
        if !run.isEmpty { units.append(contentsOf: String(decoding: run, as: UTF8.self).utf16); run.removeAll() }
      }
      while true {
        guard position < bytes.count else { throw error("Unterminated string in JSON") }
        let byte = bytes[position]
        if byte == UInt8(ascii: "\"") {
          position += 1
          flush()
          return String(decoding: units, as: UTF16.self)
        }
        if byte < 0x20 { throw error("Bad control character in string literal") }
        if byte != UInt8(ascii: "\\") {
          run.append(byte)
          position += 1
          continue
        }
        flush()
        position += 1
        guard position < bytes.count else { throw error("Unterminated string in JSON") }
        let escape = bytes[position]
        position += 1
        switch escape {
        case UInt8(ascii: "\""): units.append(0x22)
        case UInt8(ascii: "\\"): units.append(0x5C)
        case UInt8(ascii: "/"): units.append(0x2F)
        case UInt8(ascii: "b"): units.append(0x08)
        case UInt8(ascii: "f"): units.append(0x0C)
        case UInt8(ascii: "n"): units.append(0x0A)
        case UInt8(ascii: "r"): units.append(0x0D)
        case UInt8(ascii: "t"): units.append(0x09)
        case UInt8(ascii: "u"):
          guard position + 4 <= bytes.count,
                let unit = UInt16(String(decoding: bytes[position..<position + 4], as: UTF8.self), radix: 16)
          else { throw error("Bad Unicode escape in JSON") }
          units.append(unit)
          position += 4
        default:
          throw error("Bad escaped character in JSON")
        }
      }
    }

    mutating func number() throws(ParseError) -> Double {
      let start = position
      if bytes[position] == UInt8(ascii: "-") { position += 1 }
      guard position < bytes.count, isDigit(bytes[position]) else { throw error("No number after minus sign in JSON") }
      if bytes[position] == UInt8(ascii: "0") {
        position += 1
      } else {
        while position < bytes.count, isDigit(bytes[position]) { position += 1 }
      }
      if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
        position += 1
        guard position < bytes.count, isDigit(bytes[position]) else { throw error("Unterminated fractional number in JSON") }
        while position < bytes.count, isDigit(bytes[position]) { position += 1 }
      }
      if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
        position += 1
        if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") {
          position += 1
        }
        guard position < bytes.count, isDigit(bytes[position]) else { throw error("Exponent part is missing a number in JSON") }
        while position < bytes.count, isDigit(bytes[position]) { position += 1 }
      }
      // Swift's Double(String) rounds like JavaScript (nearest, ties to even) and overflows to inf.
      guard let value = Double(String(decoding: bytes[start..<position], as: UTF8.self)) else {
        throw error("Bad number")
      }
      return value
    }

    func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
  }

  // MARK: stringify

  /// `JSON.stringify(value, null, 2)`: two spaces, `"key": value`, no newline at the end.
  public static func stringify(_ value: JSONValue) -> String {
    var out = ""
    write(value, indent: "", into: &out)
    return out
  }

  private static func write(_ value: JSONValue, indent: String, into out: inout String) {
    switch value {
    case .null: out += "null"
    case .bool(let bool): out += bool ? "true" : "false"
    case .number(let number): out += numberToString(number)
    case .string(let string): quote(string, into: &out)
    case .array(let items):
      guard !items.isEmpty else { out += "[]"; return }
      let inner = indent + "  "
      out += "[\n"
      for (index, item) in items.enumerated() {
        out += inner
        write(item, indent: inner, into: &out)
        out += index == items.count - 1 ? "\n" : ",\n"
      }
      out += indent + "]"
    case .object(let object):
      guard !object.isEmpty else { out += "{}"; return }
      let inner = indent + "  "
      out += "{\n"
      let keys = object.keys
      for (index, key) in keys.enumerated() {
        out += inner
        quote(key, into: &out)
        out += ": "
        write(object[key]!, indent: inner, into: &out)
        out += index == keys.count - 1 ? "\n" : ",\n"
      }
      out += indent + "}"
    }
  }

  // JSON.stringify escapes only '"', '\\' and the C0 controls (short forms where JSON has one);
  // not '/', not U+2028/U+2029, not non-ASCII.
  private static func quote(_ string: String, into out: inout String) {
    out += "\""
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          out += "\\u00" + (scalar.value < 0x10 ? "0" : "") + String(scalar.value, radix: 16)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
  }

  /// ECMAScript's Number::toString(10). Swift's `description` already yields the shortest digits
  /// that round-trip, which is what the spec asks for; only the layout differs ("1e-07" vs
  /// "1e-7", "100.0" vs "100").
  static func numberToString(_ number: Double) -> String {
    guard number.isFinite else { return "null" }  // JSON.stringify(Infinity) === "null"
    if number == 0 { return "0" }  // -0 too
    let negative = number < 0
    let (digits, exponent) = shortestDigits(abs(number))
    let k = digits.count
    let n = exponent  // value = 0.digits × 10^n
    var body: String
    if k <= n && n <= 21 {
      body = digits + String(repeating: "0", count: n - k)
    } else if 0 < n && n <= 21 {
      let split = digits.index(digits.startIndex, offsetBy: n)
      body = digits[..<split] + "." + digits[split...]
    } else if -6 < n && n <= 0 {
      body = "0." + String(repeating: "0", count: -n) + digits
    } else {
      let e = n - 1
      let sign = e < 0 ? "-" : "+"
      let first = String(digits.prefix(1))
      let rest = String(digits.dropFirst())
      body = first + (rest.isEmpty ? "" : "." + rest) + "e" + sign + String(abs(e))
    }
    return negative ? "-" + body : body
  }

  /// The shortest decimal digits of a positive finite double, as (digits without leading or
  /// trailing zeros, n) with value = 0.d1d2… × 10^n.
  private static func shortestDigits(_ number: Double) -> (String, Int) {
    let text = number.description  // "123.45", "1e-07", "1.2345e+21", "5e-324"
    var mantissa = Substring(text)
    var exponent = 0
    if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
      mantissa = text[..<e]
      exponent = Int(text[text.index(after: e)...])!
    }
    let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
    let integerPart = String(parts[0])
    let fractionPart = parts.count > 1 ? String(parts[1]) : ""
    var all = integerPart + fractionPart
    var pointAt = integerPart.count + exponent
    while all.hasPrefix("0") && all.count > 1 {
      all.removeFirst()
      pointAt -= 1
    }
    while all.hasSuffix("0") && all.count > 1 { all.removeLast() }
    return (all, pointAt)
  }
}
