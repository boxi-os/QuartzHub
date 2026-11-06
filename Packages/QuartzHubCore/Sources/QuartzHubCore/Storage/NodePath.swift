import Foundation

/// Paths in QuartzHub are strings with the bytes of the disk, never `URL`s: Foundation decomposes a
/// name on the way in (`URL(fileURLWithPath:)` already, every `appendingPathComponent`, every
/// FileManager writer), and Node, Quartz and git read the bytes. See `Posix` and
/// `PathHygieneTests`.
///
/// Node's `path` for POSIX paths, as far as the ports need it.
public enum NodePath {
  /// `path.basename`: the last segment, trailing slashes ignored.
  public static func basename(_ path: String) -> String {
    var trimmed = path
    while trimmed.count > 1 && JSText.endsWith(trimmed, "/") { trimmed = JSText.slice(trimmed, 0, JSText.length(trimmed) - 1) }
    if trimmed == "/" { return "" }
    return JSText.split(trimmed, "/").last ?? trimmed
  }

  /// `path.dirname` for POSIX: everything before the last segment, "/" for the root, "." for none.
  public static func dirname(_ path: String) -> String {
    guard !path.isEmpty else { return "." }
    var trimmed = path
    while JSText.length(trimmed) > 1 && JSText.endsWith(trimmed, "/") { trimmed = JSText.slice(trimmed, 0, JSText.length(trimmed) - 1) }
    guard let slash = (trimmed as NSString).range(of: "/", options: [.literal, .backwards]).location as Int?, slash != NSNotFound else { return "." }
    if slash == 0 { return "/" }
    var head = JSText.slice(trimmed, 0, slash)
    while JSText.length(head) > 1 && JSText.endsWith(head, "/") { head = JSText.slice(head, 0, JSText.length(head) - 1) }
    return head
  }

  /// `path.extname`: from the last dot of the basename, unless that dot leads it.
  public static func extname(_ path: String) -> String {
    let base = basename(path)
    guard let dot = (base as NSString).range(of: ".", options: [.literal, .backwards]).location as Int?, dot != NSNotFound, dot > 0 else { return "" }
    let leading = JSText.slice(base, 0, dot)
    if leading.allSatisfy({ $0 == "." }) { return "" }
    return JSText.slice(base, dot)
  }

  /// `path.join` + `normalize` for POSIX: `.` and `..` resolved, repeated slashes folded.
  public static func join(_ parts: String...) -> String {
    normalize(parts.filter { !$0.isEmpty }.joined(separator: "/"))
  }

  public static func normalize(_ path: String) -> String {
    guard !path.isEmpty else { return "." }
    let absolute = JSText.startsWith(path, "/")
    let trailing = JSText.endsWith(path, "/")
    var out: [String] = []
    for segment in JSText.split(path, "/") {
      switch segment {
      case "", ".": continue
      case "..":
        if let last = out.last, last != ".." { out.removeLast() } else if !absolute { out.append("..") }
      default: out.append(segment)
      }
    }
    var result = (absolute ? "/" : "") + out.joined(separator: "/")
    if result.isEmpty { result = absolute ? "/" : "." }
    if trailing && result != "/" { result += "/" }
    return result
  }
}

extension NodePath {
  /// `path.relative(from, to)` for absolute, normalised paths.
  public static func relative(_ from: String, _ to: String) -> String {
    let a = JSText.split(normalize(from), "/").filter { !$0.isEmpty }
    let b = JSText.split(normalize(to), "/").filter { !$0.isEmpty }
    var common = 0
    // By bytes, as Node compares: Swift's == takes "Ü" and "U\u{308}" for one name.
    while common < a.count && common < b.count && Array(a[common].utf8) == Array(b[common].utf8) { common += 1 }
    return (Array(repeating: "..", count: a.count - common) + b[common...]).joined(separator: "/")
  }
}
