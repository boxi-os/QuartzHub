import Foundation

/// The parts of a web address as Node's WHATWG `URL` gives them, for the places where
/// QuartzControl read a credential through `new URL()`: a webhook (`https:` only, its `origin` for
/// display, its parts blanked out of what the provider answers) and later the relay's address.
/// Measured against Node over the cases in `scripts/web-url-golden.mjs`.
///
/// The special schemes (http, https, ws, wss, ftp) are parsed: tabs and newlines dropped, a
/// backslash as a slash, any number of slashes after the scheme, the user part up to the last "@",
/// the default port dropped, the host lower-cased, dot segments resolved, path, query and fragment
/// percent-encoded with Node's sets. Every other scheme answers only its protocol.
///
/// Not parsed, on purpose, and answered as `.unsupported`: a host that WHATWG would first decode or
/// map (a "%" or anything beyond ASCII, which IDNA turns into punycode), an IPv6 literal, and an
/// IPv4 address in any form but four plain decimal numbers. Such an address is refused where a
/// credential is entered, rather than sent to a host this parser does not know it names.
///
/// With `numericHosts` (the relay probe, which judges where a redirect goes), IPv6 literals and
/// IPv4 addresses in every form WHATWG reads ("0x7f.1", "2130706433", "0177.0.0.1") are parsed and
/// serialized as Node does ("[::1]", "127.0.0.1"); only "%" and non-ASCII hosts stay unsupported.
public enum WebURL: Equatable, Sendable {
  case parsed(Parts)
  /// Parsed by Node, but only with the host rules left out above.
  case unsupported
  /// A scheme other than the special ones: only `protocol` is known ("mailto:").
  case other(protocol: String)
  /// Node's `new URL()` throws.
  case invalid

  public struct Parts: Equatable, Sendable {
    /// "https:"
    public let `protocol`: String
    public let username: String
    public let password: String
    public let hostname: String
    /// "" for the scheme's default port.
    public let port: String
    public let pathname: String
    /// The query as serialized, without "?"; nil when there was no "?".
    public let query: String?
    /// The fragment as serialized, without "#"; nil when there was no "#".
    public let fragment: String?

    public var host: String { port.isEmpty ? hostname : "\(hostname):\(port)" }
    public var origin: String { "\(`protocol`)//\(host)" }
    public var search: String { (query ?? "").isEmpty ? "" : "?\(query!)" }
    public var hash: String { (fragment ?? "").isEmpty ? "" : "#\(fragment!)" }
    public var href: String {
      let user = username.isEmpty && password.isEmpty ? "" : "\(username)\(password.isEmpty ? "" : ":\(password)")@"
      return "\(`protocol`)//\(user)\(host)\(pathname)\(query.map { "?\($0)" } ?? "")\(fragment.map { "#\($0)" } ?? "")"
    }

    /// `[...url.searchParams.values()]`: application/x-www-form-urlencoded, "+" as a space.
    public var searchParamValues: [String] {
      guard let query, !query.isEmpty else { return [] }
      return JSText.split(query, "&").filter { !$0.isEmpty }.map { pair in
        let value = JSText.indexOf(pair, "=").map { JSText.slice(pair, $0 + 1) } ?? ""
        return WebURL.percentDecode(JSText.replaceAll(value, #"\+"#, with: " "))
      }
    }
  }

  public var parts: Parts? {
    if case .parsed(let parts) = self { return parts }
    return nil
  }

  /// `new URL(text).protocol`, nil when Node throws or the host is beyond this parser.
  public var `protocol`: String? {
    switch self {
    case .parsed(let parts): parts.protocol
    case .other(let value): value
    case .unsupported, .invalid: nil
    }
  }

  static let defaultPorts = ["http": "80", "https": "443", "ws": "80", "wss": "443", "ftp": "21"]

  public init(_ input: String, numericHosts: Bool = false) {
    var scalars = Array(input.unicodeScalars)
    while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
    while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
    scalars.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }
    let text = String(String.UnicodeScalarView(scalars))

    guard let match = JSText.firstMatch(text, #"\A([A-Za-z][A-Za-z0-9+.\-]*):"#) else {
      self = .invalid
      return
    }
    let scheme = match.groups[1]!.lowercased()
    guard let defaultPort = Self.defaultPorts[scheme] else {
      // A non-special URL Node accepts whatever follows the scheme, as long as it has none of the
      // things only an authority can get wrong; this parser needs no more than its protocol.
      self = .other(protocol: "\(scheme):")
      return
    }
    var rest = Array(JSText.slice(text, match.end).unicodeScalars).map { $0 == "\\" ? "/" : $0 }
    var start = 0
    while start < rest.count, rest[start] == "/" { start += 1 }
    rest = Array(rest[start...])

    let authorityEnd = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.count
    let authority = Array(rest[..<authorityEnd])
    var tail = Array(rest[authorityEnd...])

    var username = "", password = ""
    var hostAndPort = authority[...]
    if let at = authority.lastIndex(of: "@") {
      var seenColon = false
      for scalar in authority[..<at] {
        if scalar == ":" && !seenColon {
          seenColon = true
          continue
        }
        let encoded = scalar == "@" ? "%40" : Self.encode(scalar, Self.inUserinfoSet)
        if seenColon { password += encoded } else { username += encoded }
      }
      hostAndPort = authority[(at + 1)...]
      if hostAndPort.isEmpty {
        self = .invalid
        return
      }
    }
    var bracketed: String?
    if hostAndPort.first == "[" {
      guard numericHosts else {
        self = .unsupported
        return
      }
      guard let close = hostAndPort.firstIndex(of: "]"),
            let address = Self.ipv6(String(String.UnicodeScalarView(hostAndPort[hostAndPort.index(after: hostAndPort.startIndex)..<close]))) else {
        self = .invalid
        return
      }
      bracketed = "[\(address)]"
      let after = hostAndPort[hostAndPort.index(after: close)...]
      guard after.isEmpty || after.first == ":" else {
        self = .invalid
        return
      }
      hostAndPort = after
    }
    var hostScalars = hostAndPort
    var port = ""
    if let colon = hostAndPort.firstIndex(of: ":") {
      hostScalars = hostAndPort[..<colon]
      let digits = hostAndPort[(colon + 1)...]
      guard digits.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) else {
        self = .invalid
        return
      }
      if !digits.isEmpty {
        let significant = digits.drop(while: { $0 == "0" })
        let value = Int(String(String.UnicodeScalarView(significant))) ?? 0
        guard significant.count <= 5, value <= 65535 else {
          self = .invalid
          return
        }
        port = String(value) == defaultPort ? "" : String(value)
      }
    }
    let host: String
    if let bracketed {
      host = bracketed
    } else {
      guard !hostScalars.isEmpty else {
        self = .invalid
        return
      }
      if hostScalars.contains(where: { $0.value > 0x7E || $0 == "%" }) {
        self = .unsupported
        return
      }
      // Forbidden domain code points that can still be here (the terminators and "@" are gone).
      if hostScalars.contains(where: { $0.value < 0x21 || $0.value == 0x7F || "<>[]^|".unicodeScalars.contains($0) }) {
        self = .invalid
        return
      }
      let hostname = String(String.UnicodeScalarView(hostScalars)).lowercased()
      if numericHosts {
        guard let parsed = Self.hostOrAnyIPv4(hostname) else {
          self = .invalid
          return
        }
        host = parsed
      } else {
        guard let plain = Self.hostOrIPv4(hostname) else {
          self = .unsupported
          return
        }
        host = plain
      }
    }

    // Path, query and fragment, each up to the next part.
    var query: String?, fragment: String?
    if let hashAt = tail.firstIndex(of: "#") {
      fragment = Self.encodeAll(tail[(hashAt + 1)...], Self.inFragmentSet)
      tail = Array(tail[..<hashAt])
    }
    if let questionAt = tail.firstIndex(of: "?") {
      query = Self.encodeAll(tail[(questionAt + 1)...], Self.inSpecialQuerySet)
      tail = Array(tail[..<questionAt])
    }
    let pathname = GitHubRemote.pathname(String(String.UnicodeScalarView(tail)), special: true)
    self = .parsed(Parts(protocol: "\(scheme):", username: username, password: password, hostname: host, port: port,
                         pathname: pathname, query: query, fragment: fragment))
  }

  /// A domain as it is (lower-cased ASCII), a plain dotted IPv4 address as it is, nil for a host
  /// that WHATWG would read as a number in another form ("0x7f.1", "010.0.0.1", "1.2.3").
  static func hostOrIPv4(_ host: String) -> String? {
    var labels = JSText.split(host, ".")
    if labels.count > 1, labels.last == "" { labels.removeLast() }
    let last = labels.last ?? ""
    let endsInNumber = (!last.isEmpty && last.allSatisfy(\.isASCIIDigitScalar))
      || JSText.test(last, #"\A0[xX][0-9A-Fa-f]*\z"#)
    guard endsInNumber else { return host }
    // The IPv4 parser drops a trailing dot, and so does its serialization.
    guard labels.count == 4, labels.allSatisfy({ JSText.test($0, #"\A(?:0|[1-9][0-9]{0,2})\z"#) && Int($0)! <= 255 }) else { return nil }
    return labels.joined(separator: ".")
  }

  /// WHATWG's IPv4 parser where the host ends in a number: up to four parts, each decimal, octal
  /// ("0…") or hex ("0x…"), the last one filling the remaining bytes. Nil where Node throws.
  static func hostOrAnyIPv4(_ host: String) -> String? {
    var parts = JSText.split(host, ".")
    if parts.count > 1, parts.last == "" { parts.removeLast() }
    let last = parts.last ?? ""
    let endsInNumber = (!last.isEmpty && last.allSatisfy(\.isASCIIDigitScalar)) || ipv4Number(last) != nil && JSText.test(last, #"\A0[xX]"#)
    guard endsInNumber else { return host }
    guard parts.count <= 4 else { return nil }
    var numbers: [UInt64] = []
    for part in parts {
      guard let number = ipv4Number(part) else { return nil }
      numbers.append(number)
    }
    for number in numbers.dropLast() where number > 255 { return nil }
    guard numbers.last! < UInt64(1) << (8 * (5 - numbers.count)) else { return nil }
    var address = numbers.last!
    for (i, number) in numbers.dropLast().enumerated() { address += number << (8 * (3 - i)) }
    return (0..<4).map { String((address >> (8 * (3 - $0))) & 255) }.joined(separator: ".")
  }

  static func ipv4Number(_ part: String) -> UInt64? {
    guard !part.isEmpty else { return nil }
    var digits = Substring(part), radix = 10
    if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
      digits = digits.dropFirst(2)
      radix = 16
    } else if digits.count >= 2, digits.hasPrefix("0") {
      digits = digits.dropFirst()
      radix = 8
    }
    if digits.isEmpty { return 0 }
    guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit && Int(String($0), radix: 16)! < radix }) else { return nil }
    // Beyond 2^32 is a failure for every part; the cap keeps the arithmetic in range.
    var value: UInt64 = 0
    for digit in digits { value = min(value * UInt64(radix) + UInt64(Int(String(digit), radix: 16)!), UInt64(1) << 40) }
    return value
  }

  /// WHATWG's IPv6 parser and serializer: eight pieces, "::" for the first longest run of two or
  /// more zero pieces, lower-case hex without leading zeros; a dotted IPv4 tail as two pieces.
  static func ipv6(_ input: String) -> String? {
    let c = Array(input.lowercased().unicodeScalars)
    var pieces = [UInt16](repeating: 0, count: 8)
    var index = 0, pointer = 0
    var compress: Int?
    func hexValue(_ s: Unicode.Scalar) -> UInt16? { UInt16(String(s), radix: 16) }
    if pointer < c.count, c[pointer] == ":" {
      guard pointer + 1 < c.count, c[pointer + 1] == ":" else { return nil }
      pointer += 2
      index += 1
      compress = index
    }
    while pointer < c.count {
      guard index < 8 else { return nil }
      if c[pointer] == ":" {
        guard compress == nil else { return nil }
        pointer += 1
        index += 1
        compress = index
        continue
      }
      var value: UInt16 = 0, length = 0
      while length < 4, pointer < c.count, let digit = hexValue(c[pointer]) {
        value = value * 16 + digit
        pointer += 1
        length += 1
      }
      if pointer < c.count, c[pointer] == "." {
        guard length > 0 else { return nil }
        pointer -= length
        guard index <= 6 else { return nil }
        var seen = 0
        while pointer < c.count {
          var number: Int?
          if seen > 0 {
            guard c[pointer] == ".", seen < 4 else { return nil }
            pointer += 1
          }
          guard pointer < c.count, ("0"..."9").contains(c[pointer]) else { return nil }
          while pointer < c.count, ("0"..."9").contains(c[pointer]) {
            let digit = Int(c[pointer].value - 0x30)
            if number == 0 { return nil }
            number = (number ?? 0) * 10 + digit
            guard number! <= 255 else { return nil }
            pointer += 1
          }
          pieces[index] = pieces[index] * 0x100 + UInt16(number!)
          seen += 1
          if seen == 2 || seen == 4 { index += 1 }
        }
        guard seen == 4 else { return nil }
        break
      } else if pointer < c.count, c[pointer] == ":" {
        pointer += 1
        guard pointer < c.count else { return nil }
      } else if pointer < c.count {
        return nil
      }
      pieces[index] = value
      index += 1
    }
    if let compress {
      var swaps = index - compress
      index = 7
      while index != 0, swaps > 0 {
        pieces.swapAt(index, compress + swaps - 1)
        index -= 1
        swaps -= 1
      }
    } else if index != 8 {
      return nil
    }
    // Serialize: the first longest run of zeros, if longer than one.
    var best: (start: Int, length: Int)?
    var i = 0
    while i < 8 {
      if pieces[i] == 0 {
        var j = i
        while j < 8, pieces[j] == 0 { j += 1 }
        if j - i > 1, j - i > (best?.length ?? 0) { best = (i, j - i) }
        i = j
      } else {
        i += 1
      }
    }
    var out = ""
    var ignore0 = false
    for k in 0..<8 {
      if ignore0, pieces[k] == 0 { continue }
      ignore0 = false
      if let best, best.start == k {
        out += k == 0 ? "::" : ":"
        ignore0 = true
        continue
      }
      out += String(pieces[k], radix: 16)
      if k != 7 { out += ":" }
    }
    return out
  }

  // Node's percent-encode sets (the path set is GitHubRemote.encode's).
  static func inUserinfoSet(_ v: UInt32) -> Bool {
    v <= 0x20 || v >= 0x7F || "\"#<>?^`{}/:;=@[\\]|".unicodeScalars.contains { $0.value == v }
  }

  static func inSpecialQuerySet(_ v: UInt32) -> Bool { v <= 0x20 || v >= 0x7F || "\"#<>'".unicodeScalars.contains { $0.value == v } }

  static func inFragmentSet(_ v: UInt32) -> Bool { v <= 0x20 || v >= 0x7F || "\"<>`".unicodeScalars.contains { $0.value == v } }

  static func encode(_ scalar: Unicode.Scalar, _ set: (UInt32) -> Bool) -> String {
    guard set(scalar.value) else { return String(scalar) }
    return String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
  }

  static func encodeAll(_ scalars: ArraySlice<Unicode.Scalar>, _ set: (UInt32) -> Bool) -> String {
    scalars.map { encode($0, set) }.joined()
  }

  /// Percent-decoding to bytes, then UTF-8 with U+FFFD for what does not decode, as
  /// URLSearchParams does.
  static func percentDecode(_ text: String) -> String {
    var bytes: [UInt8] = []
    let utf8 = Array(text.utf8)
    var i = 0
    func hex(_ b: UInt8) -> UInt8? {
      switch b {
      case 0x30...0x39: b - 0x30
      case 0x41...0x46: b - 0x37
      case 0x61...0x66: b - 0x57
      default: nil
      }
    }
    while i < utf8.count {
      if utf8[i] == 0x25, i + 2 < utf8.count, let high = hex(utf8[i + 1]), let low = hex(utf8[i + 2]) {
        bytes.append(high << 4 | low)
        i += 3
      } else {
        bytes.append(utf8[i])
        i += 1
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }
}

extension Character {
  fileprivate var isASCIIDigitScalar: Bool { unicodeScalars.count == 1 && ("0"..."9").contains(unicodeScalars.first!) }
}
