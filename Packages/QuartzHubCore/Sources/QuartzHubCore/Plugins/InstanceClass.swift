import Foundation

/// The CSS class a navigation or a layout box gets from QuartzHub, so a stylesheet and the
/// preview's marks can tell one instance from its siblings (QuartzControl's
/// `routes/Plugins/instanceClass.ts`, measured against it in NavigationsTests). Set when the
/// instance is created, duplicated, or on "Eigene Klasse vergeben"; never renamed afterwards: a
/// stylesheet aims at the class, and a class that followed the title would leave its rules aiming
/// at nothing.
///
/// Always behind a prefix: a navigation titled "Explorer" would otherwise pick up every rule for
/// Quartz's explorer.
public enum InstanceClass {
  public static let navigationPrefix = "nav-"
  public static let boxPrefix = "layout-box-"
  /// The prefixes of the classes QuartzHub gives, for `SiteFonts.takenClasses`.
  public static let prefixes = [navigationPrefix, boxPrefix]

  private static let prefix = ["quartz-navigations": navigationPrefix, "quartz-layout-box": boxPrefix]
  private static let fallback = ["quartz-navigations": "navigation", "quartz-layout-box": "box"]

  /// The classes of an entry's `className` option, in order.
  public static func tokens(_ entry: PluginEntry) -> [String] {
    guard case .string(let own)? = entry.object["options"]?["className"] else { return [] }
    return splitWhitespace(own)
  }

  /// The entry's own class: the last one, if a selector can name it safely.
  public static func own(_ entry: PluginEntry) -> String? {
    guard let last = tokens(entry).last, isClass(last) else { return nil }
    return last
  }

  /// `/^[A-Za-z_][\w-]*$/`.
  static func isClass(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    guard let first = scalars.first, isLetter(first) || first == "_" else { return false }
    return scalars.dropFirst().allSatisfy { isLetter($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }
  }

  private static func isLetter(_ s: Unicode.Scalar) -> Bool { ("a"..."z").contains(s) || ("A"..."Z").contains(s) }

  /// `text.split(/\s+/).filter(Boolean)` with JavaScript's whitespace.
  static func splitWhitespace(_ text: String) -> [String] {
    var out: [String] = []
    var current: [UInt16] = []
    for unit in text.utf16 {
      if ReadmeText.isSpace(unit) {
        if !current.isEmpty { out.append(String(decoding: current, as: UTF16.self)); current = [] }
      } else {
        current.append(unit)
      }
    }
    if !current.isEmpty { out.append(String(decoding: current, as: UTF16.self)) }
    return out
  }

  /// A name a user sees, made into a class: lower case, umlauts spelled out, accents dropped,
  /// everything else a hyphen, at most 40 characters.
  static func slug(_ text: String) -> String {
    var s = text.lowercased()
      .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
      .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
    s = s.decomposedStringWithCompatibilityMapping
    s = String(String.UnicodeScalarView(s.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }))
    var out = ""
    var hyphen = false
    for scalar in s.unicodeScalars {
      if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
        if hyphen { out.append("-"); hyphen = false }
        out.unicodeScalars.append(scalar)
      } else {
        hyphen = true
      }
    }
    if hyphen { out.append("-") }
    // `^-+|-+$` away, then 40 characters, then a hyphen at the cut away.
    while out.hasPrefix("-") { out.removeFirst() }
    while out.hasSuffix("-") { out.removeLast() }
    out = String(out.prefix(40))
    while out.hasSuffix("-") { out.removeLast() }
    return out
  }

  /// `candidate`, or with -2, -3 … until neither an entry of the config nor `styled` has it. A
  /// trailing number is a counter only when the name without it is taken too.
  public static func unique(_ candidate: String, plugins: [PluginEntry], styled: Set<String> = []) -> String {
    let taken = Set(plugins.flatMap(tokens)).union(styled)
    if !taken.contains(candidate) { return candidate }
    let counted = candidate.replacing(/-[0-9]+$/, with: "")
    let stem = counted != candidate && taken.contains(counted) ? counted : candidate
    var n = 2
    while taken.contains("\(stem)-\(n)") { n += 1 }
    return "\(stem)-\(n)"
  }

  /// A new class from a name the user sees (a title, a variant, a file), prefixed and unique.
  public static func suggest(prefix: String, name: String, fallback: String, plugins: [PluginEntry], styled: Set<String> = []) -> String {
    let slugged = slug(name)
    return unique(prefix + (slugged.isEmpty ? fallback : slugged), plugins: plugins, styled: styled)
  }

  /// The options with `cls` appended to their className.
  public static func with(_ options: JSONObject?, _ cls: String) -> JSONObject {
    var next = options ?? JSONObject()
    let before: String = if case .string(let text)? = options?["className"] { ReadmeText.trim(text) } else { "" }
    next["className"] = .string(before.isEmpty ? cls : "\(before) \(cls)")
    return next
  }

  /// The class a copy of `entry` gets: its own one counted up, or one from its name.
  public static func forCopy(_ entry: PluginEntry, prefix: String, name: String, fallback: String, plugins: [PluginEntry],
                             styled: Set<String> = []) -> String {
    if let own = own(entry) { return unique(own, plugins: plugins, styled: styled) }
    return suggest(prefix: prefix, name: name, fallback: fallback, plugins: plugins, styled: styled)
  }

  /// What a class of an entry's own is made from: the title, else the navigation's variant or the
  /// box's file. Untranslated on purpose: the same entry gets the same class in either language.
  public static func source(_ entry: PluginEntry) -> String {
    let options = entry.object["options"]?.objectValue ?? JSONObject()
    if case .string(let title)? = options["title"], !ReadmeText.trim(title).isEmpty { return title }
    if case .string(let variant)? = options["variant"] { return variant }
    if case .string(let file)? = options["file"] {
      return file.replacing(/^.*[\\\/]/, with: "").replacing(/\.[^.]*$/, with: "")
    }
    return ""
  }

  /// `copy` of `source` with a class of its own appended, for the two plugins whose class lands on
  /// the rendered root; every other copy comes back as it is.
  public static func withOwnForCopy(_ copy: PluginEntry, source: PluginEntry, plugins: [PluginEntry], styled: Set<String> = []) -> PluginEntry {
    guard let prefix = prefix[source.name] else { return copy }
    let cls = forCopy(source, prefix: prefix, name: self.source(source), fallback: fallback[source.name] ?? "", plugins: plugins, styled: styled)
    var object = copy.object
    object["options"] = .object(with(copy.object["options"]?.objectValue, cls))
    return PluginEntry(object: object)
  }
}
