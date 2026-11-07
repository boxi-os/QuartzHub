import Foundation

/// QuartzControl's `shared/semver.ts`: whether one version is later than another, prereleases
/// included (`1.0.0` after `1.0.0-beta.2`, `beta.10` after `beta.9`). Anything either side cannot
/// parse counts as "not newer", the safe direction.
public enum SemVer {
  struct Parsed {
    var numbers: [Double]
    var pre: [String]
  }

  static func parse(_ version: String) -> Parsed? {
    guard let m = JSText.firstMatch(JS.trim(version), "^([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:-([0-9A-Za-z.-]+))?$") else { return nil }
    let numbers = (1...3).map { Double(m.groups[$0] ?? "") ?? 0 }
    let pre = m.groups[4].map { JSText.split($0, ".") } ?? []
    return Parsed(numbers: numbers, pre: pre)
  }

  /// `isNewerVersion(candidate, current)`.
  public static func isNewer(_ candidate: String, than current: String) -> Bool {
    guard let a = parse(candidate), let b = parse(current) else { return false }
    for i in 0..<3 where a.numbers[i] != b.numbers[i] { return a.numbers[i] > b.numbers[i] }
    if a.pre.isEmpty { return !b.pre.isEmpty }
    if b.pre.isEmpty { return false }
    for i in 0..<max(a.pre.count, b.pre.count) {
      guard i < a.pre.count else { return false }
      guard i < b.pre.count else { return true }
      let x = a.pre[i], y = b.pre[i]
      if x == y { continue }
      let digits = "^[0-9]+$"
      if JSText.test(x, digits) && JSText.test(y, digits) { return (Double(x) ?? 0) > (Double(y) ?? 0) }
      // JavaScript's `>` on strings: by UTF-16 code units.
      return Array(y.utf16).lexicographicallyPrecedes(Array(x.utf16))
    }
    return false
  }
}
