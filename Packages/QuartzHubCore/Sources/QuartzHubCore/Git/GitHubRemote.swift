import Foundation

/// `parseGithubRemote` (`githubService.ts`): the owner and name of a repository on github.com, from
/// a remote as git holds it. It decides whether QuartzHub's GitHub token goes anywhere (`GitAuth`),
/// so a host that is not exactly github.com or www.github.com is nothing.
///
/// QuartzControl parsed the URL form with the WHATWG `URL` of Node. That is ported here as far as
/// the answer depends on it, measured against Node over 110 remotes (`scripts/git-golden.mjs`):
/// tabs and newlines dropped, a backslash as a slash for the special schemes, any number of slashes
/// after `https:`, the user part up to the last "@", the port checked, the host lower-cased for
/// the special schemes and kept as written for the others (`ssh://git@GitHub.com/…` is nothing),
/// dot segments resolved and the path percent-encoded as Node does.
///
/// One deviation, on purpose: a host is compared as written (lower-cased for the special schemes),
/// not decoded and mapped first as WHATWG does (percent-decoding, IDNA). `https://ｇithub.com/o/r`
/// and `https://github%2Ecom/o/r` were github.com there; here they are nothing and get no token.
public enum GitHubRemote {
  public struct Repo: Sendable, Equatable {
    public var owner: String
    public var repo: String
  }

  public static func parse(_ remote: String) -> Repo? {
    var cleaned = JS.trim(remote)
    if JSText.endsWith(cleaned, ".git") { cleaned = JSText.slice(cleaned, 0, JSText.length(cleaned) - 4) }
    // scp form, `/^[^@]+@github\.com:([^/]+)\/(.+)$/`: JavaScript's "." stops only at four line ends.
    if let scp = JSText.firstMatch(cleaned, #"\A[^@]+@github\.com:([^/]+)/([^\n\r\x{2028}\x{2029}]+)\z"#) {
      return Repo(owner: scp.groups[1]!, repo: scp.groups[2]!)
    }
    guard let pathname = githubPathname(cleaned) else { return nil }
    let parts = JSText.split(JSText.startsWith(pathname, "/") ? JSText.slice(pathname, 1) : pathname, "/")
    guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return Repo(owner: parts[0], repo: parts[1])
  }

  static let special: Set<String> = ["http", "https", "ws", "wss", "ftp", "file"]

  /// The URL's pathname when its hostname is github.com or www.github.com, else nil (also for
  /// everything WHATWG would refuse).
  static func githubPathname(_ input: String) -> String? {
    // Leading and trailing C0 controls and spaces go, and every tab and newline anywhere.
    var scalars = Array(input.unicodeScalars)
    while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
    while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
    scalars.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }
    let text = String(String.UnicodeScalarView(scalars))

    guard let match = JSText.firstMatch(text, #"\A([A-Za-z][A-Za-z0-9+.\-]*):"#) else { return nil }
    let scheme = match.groups[1]!.lowercased()
    let isSpecial = special.contains(scheme)
    // By scalar, not by Character: "/" followed by a combining mark is one Character.
    var rest = Array(JSText.slice(text, match.end).unicodeScalars)
    // Query and fragment are not part of the pathname.
    if let cut = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = Array(rest[..<cut]) }
    if isSpecial { rest = rest.map { $0 == "\\" ? "/" : $0 } }

    var start = 0
    if isSpecial && scheme != "file" {
      while start < rest.count, rest[start] == "/" { start += 1 }
    } else if rest.count >= 2, rest[0] == "/", rest[1] == "/" {
      start = 2
    } else {
      return nil // no host at all
    }
    let authorityEnd = rest[start...].firstIndex(of: "/") ?? rest.count
    let authority = Array(rest[start..<authorityEnd])
    let path = String(String.UnicodeScalarView(rest[authorityEnd...]))

    var hostAndPort = authority[...]
    if scheme == "file" {
      // A file URL has neither user nor port; either is a failure.
      if authority.contains("@") || authority.contains(":") { return nil }
    } else if let at = authority.lastIndex(of: "@") {
      hostAndPort = authority[(at + 1)...]
    }
    var host = hostAndPort
    if let colon = hostAndPort.firstIndex(of: ":") {
      host = hostAndPort[..<colon]
      let port = hostAndPort[(colon + 1)...]
      guard port.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) else { return nil }
      let digits = String(String.UnicodeScalarView(port.drop { $0 == "0" }))
      if digits.count > 5 || (Int(digits) ?? 0) > 65535 { return nil }
    }
    let written = String(String.UnicodeScalarView(host))
    let name = isSpecial ? written.lowercased() : written
    guard name == "github.com" || name == "www.github.com" else { return nil }
    return pathname(path, special: isSpecial)
  }

  /// WHATWG's path state: dot segments resolved, each segment percent-encoded with the path set.
  static func pathname(_ path: String, special: Bool) -> String {
    guard !path.isEmpty else { return special ? "/" : "" }
    var segments: [String] = []
    let pieces = JSText.split(JSText.slice(path, 1), "/")
    for (index, piece) in pieces.enumerated() {
      let last = index == pieces.count - 1
      switch piece.lowercased() {
      case "..", ".%2e", "%2e.", "%2e%2e":
        if !segments.isEmpty { segments.removeLast() }
        if last { segments.append("") }
      case ".", "%2e":
        if last { segments.append("") }
      default:
        segments.append(encode(piece))
      }
    }
    return "/" + segments.joined(separator: "/")
  }

  /// The path percent-encode set as Node 24 applies it: C0 controls, space, `"`, `#`, `<`, `>`,
  /// `?`, `^`, `` ` ``, `{`, `}`, DEL and everything above it, as UTF-8 in upper-case hex.
  static func encode(_ segment: String) -> String {
    var out = ""
    for scalar in segment.unicodeScalars {
      let v = scalar.value
      if v <= 0x20 || v >= 0x7F || "\"#<>?^`{}".unicodeScalars.contains(scalar) {
        for byte in String(scalar).utf8 { out += String(format: "%%%02X", byte) }
      } else {
        out.unicodeScalars.append(scalar)
      }
    }
    return out
  }
}
