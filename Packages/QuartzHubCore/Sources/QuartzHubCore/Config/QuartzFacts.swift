import Darwin
import Foundation
import Synchronization

/// What a project's Quartz says about itself, read from its source by the helper `quartz-facts`
/// (TypeScript's parser, nothing run): the built-ins' option defaults, order and absorbed plugins
/// (`BUILTINS`), and the layout conditions it knows. QuartzHub carried these as its own constants,
/// and a Quartz release that changed one made it show something wrong: 5.3 turned links'
/// `disableBrokenWikilinks` on and added `is-index`, `is-folder-index` and `not-<any>` (plan
/// „Quartz-Updates ohne ständiges Nachziehen“, 2026-11-28).
///
/// The constants stay as the fallback (`BuiltinProcessing.Builtin.defaults`,
/// `LayoutBoard.builtinConditions`): for a Quartz without these files, for a key whose default is
/// no literal, and when the helper cannot be asked. What could not be read is in `problems`, which
/// `qh-check quartz-facts` reports with exit 3.
public struct QuartzFacts: Equatable, Sendable {
  public enum Section<Value: Equatable & Sendable>: Equatable, Sendable {
    case read(Value)
    /// The file is not there: an older Quartz.
    case missing
    /// It is there in a shape the helper does not know.
    case unknown(String)

    public var value: Value? { if case .read(let value) = self { value } else { nil } }
  }

  public struct Builtin: Equatable, Sendable {
    public var configKey: String
    public var order: Double?
    public var absorbs: [String]?
    /// nil when `defaults` is no object literal the helper could follow.
    public var defaults: JSONObject?
    public var absorbedDefaults: JSONObject?
    /// Defaults that are `undefined` in Quartz: no value, as there.
    public var undefinedKeys: [String]
    /// Keys whose default is no literal ("*": the whole object), which keep QuartzHub's own value.
    public var unresolved: [String]
  }

  public struct Conditions: Equatable, Sendable {
    public var names: [String]
    /// `not-<name>` negates any condition (Quartz 5.3).
    public var negation: Bool
  }

  public var builtins: Section<[Builtin]>
  public var conditions: Section<Conditions>

  public init(builtins: Section<[Builtin]> = .missing, conditions: Section<Conditions> = .missing) {
    self.builtins = builtins
    self.conditions = conditions
  }

  // MARK: answers, with QuartzHub's constants where Quartz did not say

  func builtin(_ builtin: BuiltinProcessing.Builtin) -> Builtin? {
    builtins.value?.first { $0.configKey == builtin.configKey }
  }

  /// The built-in's option defaults: Quartz's, with QuartzHub's for what could not be read.
  public func defaults(_ builtin: BuiltinProcessing.Builtin) -> JSONObject {
    guard let read = self.builtin(builtin), var defaults = read.defaults, !read.unresolved.contains("*") else { return builtin.defaults }
    let fallback = builtin.defaults
    for key in read.unresolved where defaults[key] == nil {
      if let value = fallback[key] { defaults[key] = value }
    }
    return defaults
  }

  public func order(_ builtin: BuiltinProcessing.Builtin) -> Double {
    self.builtin(builtin)?.order ?? builtin.defaultOrder
  }

  func absorbedDefaults(_ builtin: BuiltinProcessing.Builtin) -> JSONObject {
    guard let read = self.builtin(builtin) else { return builtin.absorbedDefaults }
    return read.unresolved.contains("absorbedDefaults") ? builtin.absorbedDefaults : (read.absorbedDefaults ?? JSONObject())
  }

  /// The conditions a layout entry can name, in Quartz's order.
  public var conditionNames: [String] { conditions.value?.names ?? LayoutBoard.builtinConditions }

  /// Whether `not-` turns any condition into its negation.
  public var negatesAnyCondition: Bool { conditions.value?.negation ?? false }

  /// What was not read, one line each; empty when everything came from Quartz or was not there.
  public var problems: [String] {
    var out: [String] = []
    if case .unknown(let reason) = builtins { out.append("builtins: \(reason)") }
    for entry in builtins.value ?? [] where !entry.unresolved.isEmpty {
      out.append("builtins.\(entry.configKey): \(entry.unresolved.joined(separator: ", "))")
    }
    if case .unknown(let reason) = conditions { out.append("conditions: \(reason)") }
    return out
  }

  // MARK: reading

  /// Asks the helper, once per state of the files it reads: a page that loads again gets the
  /// answer without a process (a call costs some 150 ms, mostly loading TypeScript).
  public static func read(project: String, runtime: RuntimeLocation = .current) async throws(Helper.Failure) -> QuartzFacts {
    let stamp = fingerprint(project)
    if let cached = cache.withLock({ $0[project] }), cached.stamp == stamp { return cached.facts }
    let answer = try await Helper.call("quartz-facts", JSONObject([("project", .string(project))]), runtime: runtime)
    let facts = parse(answer)
    cache.withLock { $0[project] = (stamp, facts) }
    return facts
  }

  /// `read`, and the constants when the helper cannot be asked: what a page shows then is what
  /// QuartzHub showed before it asked.
  public static func readOrFallback(project: String, runtime: RuntimeLocation = .current) async -> QuartzFacts {
    (try? await read(project: project, runtime: runtime)) ?? QuartzFacts()
  }

  private static let cache = Mutex<[String: (stamp: String, facts: QuartzFacts)]>([:])

  /// The files the helper reads, by name, size and modification time.
  static func fingerprint(_ project: String) -> String {
    let builtins = NodePath.join(project, "quartz", "plugins", "builtins")
    var files = (Posix.entries(builtins) ?? []).filter { $0.name.hasSuffix(".ts") }.map { NodePath.join(builtins, $0.name) }
    files.append(NodePath.join(project, "quartz", "plugins", "loader", "conditions.ts"))
    return files.map { file in
      var info = stat()
      guard stat(file, &info) == 0 else { return "\(file):-" }
      return "\(file):\(info.st_size):\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
    }.joined(separator: "\n")
  }

  static func parse(_ answer: JSONObject) -> QuartzFacts {
    func section<T>(_ value: JSONValue?, _ read: (JSONObject) -> T?) -> Section<T> {
      guard let object = value?.objectValue else { return .unknown("no answer") }
      switch object["state"]?.stringValue {
      case "missing": return .missing
      case "unknown": return .unknown(object["reason"]?.stringValue ?? "")
      case "read": return read(object).map { .read($0) } ?? .unknown("answer not understood")
      default: return .unknown("answer not understood")
      }
    }
    let strings = { (value: JSONValue?) in value?.arrayValue?.compactMap(\.stringValue) }
    return QuartzFacts(
      builtins: section(answer["builtins"]) { object in
        object["entries"]?.arrayValue?.compactMap { entry -> Builtin? in
          guard let key = entry["configKey"]?.stringValue else { return nil }
          return Builtin(configKey: key, order: entry["order"]?.numberValue, absorbs: strings(entry["absorbs"]),
                         defaults: entry["defaults"]?.objectValue, absorbedDefaults: entry["absorbedDefaults"]?.objectValue,
                         undefinedKeys: strings(entry["undefinedKeys"]) ?? [], unresolved: strings(entry["unresolved"]) ?? [])
        }
      },
      conditions: section(answer["conditions"]) { object in
        strings(object["names"]).map { Conditions(names: $0, negation: object["negation"] == .bool(true)) }
      })
  }
}
