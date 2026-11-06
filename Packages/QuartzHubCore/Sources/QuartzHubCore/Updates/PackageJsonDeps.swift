import Foundation

/// What a project changed in its own package.json, measured against the commit the core update
/// merges from. A port of `shared/packageJsonDeps.ts`, measured against it
/// (`scripts/package-deps-golden.mjs`).
///
/// `package.json` and `package-lock.json` are the record of which packages are installed, and both
/// sides write them: Quartz rewrote all its dependencies (3dff48b) while projects had theme
/// packages of their own. A three-way merge is the wrong tool for both files; the core update takes
/// upstream's copy and lets npm write the local additions back in, and this works out which.
/// Pure: three parsed values in, a plan out.
public enum PackageJsonDeps {
  public enum Section: String, Sendable, CaseIterable {
    case dependencies, devDependencies, optionalDependencies, peerDependencies
  }

  /// In this order, everywhere.
  public static let sections: [Section] = [.dependencies, .devDependencies, .optionalDependencies, .peerDependencies]

  public struct Addition: Sendable, Equatable, Hashable {
    public var name: String
    public var section: Section
    /// The range this project asked for, handed to npm as `name@range`.
    public var range: String
    public init(name: String, section: Section, range: String) {
      self.name = name
      self.section = section
      self.range = range
    }
  }

  public struct Changes: Sendable, Equatable {
    /// Added or re-pinned here, and reproducible with `npm install name@range` after the merge.
    public var reinstall: [Addition] = []
    /// Changed here and upstream; upstream wins, and the output says so.
    public var upstreamWins: [String] = []
    /// What the plan cannot reproduce: a locally removed dependency, any edit outside the
    /// dependency sections. Non-empty means hands off: git decides.
    public var unreproducible: [String] = []
    public init() {}
  }

  /// A package.json as the caller read it: parsed, or not readable at all (distinct from any value
  /// JSON can hold, `null` included).
  public enum Read: Sendable, Equatable {
    case parsed(JSONValue)
    case unreadable
  }

  static func isPlainObject(_ value: JSONValue?) -> JSONObject? { value?.objectValue }

  /// The string entries of one section, in the object's order.
  static func section(_ pkg: JSONValue?, _ name: Section) -> [(String, String)] {
    guard let raw = isPlainObject(pkg)?[name.rawValue]?.objectValue else { return [] }
    return raw.keys.compactMap { key in raw[key]?.stringValue.map { (key, $0) } }
  }

  public static func dependencyRange(_ pkg: JSONValue?, _ name: Section, _ dependency: String) -> String? {
    section(pkg, name).first { $0.0 == dependency }?.1
  }

  /// - base: package.json at the merge base; ours: as it is in the working tree; theirs: at the
  ///   commit being merged in.
  public static func localPackageChanges(base: JSONValue?, ours: JSONValue?, theirs: JSONValue?) -> Changes {
    var changes = Changes()
    for name in sections {
      let baseDeps = Dictionary(section(base, name), uniquingKeysWith: { a, _ in a })
      let ourList = section(ours, name)
      let ourDeps = Dictionary(ourList, uniquingKeysWith: { a, _ in a })
      let theirDeps = Dictionary(section(theirs, name), uniquingKeysWith: { a, _ in a })
      for pkg in unique(section(base, name).map(\.0) + ourList.map(\.0)) {
        let baseRange = baseDeps[pkg], ourRange = ourDeps[pkg], theirRange = theirDeps[pkg]
        if ourRange == baseRange { continue }
        guard let ourRange else {
          // npm cannot replay a removal, and a package that comes back unasked is another project.
          changes.unreproducible.append("\(name.rawValue).\(pkg)")
          continue
        }
        if let theirRange, theirRange != baseRange {
          changes.upstreamWins.append(pkg)
          continue
        }
        changes.reinstall.append(Addition(name: pkg, section: name, range: ourRange))
      }
    }
    // Everything that is not a dependency section: scripts, exports, the package's own name.
    let baseKeys = isPlainObject(base) ?? JSONObject(), ourKeys = isPlainObject(ours) ?? JSONObject()
    for key in unique(baseKeys.keys + ourKeys.keys) where Section(rawValue: key) == nil {
      if stringify(baseKeys[key]) != stringify(ourKeys[key]) { changes.unreproducible.append(key) }
    }
    return changes
  }

  /// `JSON.stringify(value)`, with `undefined` for a missing key.
  static func stringify(_ value: JSONValue?) -> String? { value.map(JSJSON.compact) }

  static func unique(_ items: [String]) -> [String] {
    var seen = Set<String>()
    return items.filter { seen.insert($0).inserted }
  }

  /// The npm arguments that put `reinstall` back, one call per section: the flag that decides the
  /// section is a flag on the call.
  public static func reinstallCommands(_ reinstall: [Addition]) -> [[String]] {
    let flags: [Section: String] = [.dependencies: "--save-prod", .devDependencies: "--save-dev",
                                     .optionalDependencies: "--save-optional", .peerDependencies: "--save-peer"]
    return sections.compactMap { name in
      let packages = reinstall.filter { $0.section == name }
      return packages.isEmpty ? nil : ["install", flags[name]!] + packages.map { "\($0.name)@\($0.range)" }
    }
  }

  /// What of the plan the merged package.json does not already say. Unreadable is not "nothing to
  /// do": then all of them, and npm answers.
  public static func missingFrom(_ pkg: Read, _ reinstall: [Addition]) -> [Addition] {
    guard case .parsed(let value) = pkg else { return reinstall }
    return reinstall.filter { dependencyRange(value, $0.section, $0.name) != $0.range }
  }

  /// What of a list is not in package.json at all. A section the list does not claim for the same
  /// name stands in for a missing one (a line moved from `dependencies` to `devDependencies`), but
  /// only one per missing entry: a package can be in two sections at once. Unreadable: nothing,
  /// because a sentence naming packages that may well be there is the worse answer.
  public static func absentFrom(_ pkg: Read, _ entries: [Addition]) -> [Addition] {
    absentIndices(pkg, entries).map { entries[$0] }
  }

  /// `absentFrom` as positions in `entries`: QuartzControl's set holds the entries themselves, so
  /// two equal entries in a list are two.
  static func absentIndices(_ pkg: Read, _ entries: [Addition]) -> [Int] {
    guard case .parsed(let value) = pkg else { return [] }
    func holds(_ section: Section, _ name: String) -> Bool { dependencyRange(value, section, name) != nil }
    var absent: [Int] = []
    for name in unique(entries.map(\.name)) {
      let own = entries.indices.filter { entries[$0].name == name }
      let claimed = Set(own.map { entries[$0].section })
      var moved = sections.filter { !claimed.contains($0) && holds($0, name) }.count
      for index in own where !holds(entries[index].section, name) {
        if moved > 0 { moved -= 1 } else { absent.append(index) }
      }
    }
    return absent
  }

  /// The packages the Updates and Git-Sync pages name as still to be put back, one name per
  /// package. A line this app's npm wrote back (`putBack`) is outstanding only while it is not
  /// there at all; any other line at another range still is.
  public static func outstandingPackages(_ pkg: Read, _ reinstall: [Addition], putBack: [String]) -> [String] {
    // By position: QuartzControl compares the entries themselves (`missingFrom` filters, it does
    // not copy).
    let absent = Set(absentIndices(pkg, reinstall))
    let outstanding = missingIndices(pkg, reinstall).filter { !putBack.contains(reinstall[$0].name) || absent.contains($0) }
    return unique(outstanding.map { reinstall[$0].name })
  }

  static func missingIndices(_ pkg: Read, _ reinstall: [Addition]) -> [Int] {
    guard case .parsed(let value) = pkg else { return Array(reinstall.indices) }
    return reinstall.indices.filter { dependencyRange(value, reinstall[$0].section, reinstall[$0].name) != reinstall[$0].range }
  }
}
