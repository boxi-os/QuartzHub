import Foundation

/// A model that is a view on one JSON object: it reads its fields with QuartzControl's rules and
/// writes changes back into the same object, so key order and keys it does not know survive
/// (docs/decisions/phase-2-formate.md). Setting a field to nil removes the key, as an `undefined`
/// does in `JSON.stringify`; a new key goes to the end, as in JavaScript.
public protocol JSONView: Equatable, Sendable {
  var object: JSONObject { get set }
  init(object: JSONObject)
}

extension JSONView {
  public var json: JSONValue { .object(object) }

  func string(_ key: String) -> String? { object[key]?.stringValue }
  /// `raw.x === true`: QuartzControl's way of reading a flag that an older file may not carry.
  func isTrue(_ key: String) -> Bool { object[key] == .bool(true) }
  func number(_ key: String) -> Double? { object[key]?.numberValue }
  func strings(_ key: String) -> [String]? { object[key]?.arrayValue?.compactMap(\.stringValue) }

  mutating func set(_ key: String, _ value: String?) { object[key] = value.map { .string($0) } }
  mutating func set(_ key: String, _ value: Bool?) { object[key] = value.map { .bool($0) } }
  mutating func set(_ key: String, _ value: Double?) { object[key] = value.map { .number($0) } }
  mutating func set(_ key: String, _ value: [String]?) { object[key] = value.map { .array($0.map { .string($0) }) } }
}

/// A file that holds a list (`projects.json`, `publish-targets.json`, …). Entries that are not
/// objects are kept as they are, so a round trip never drops what it did not understand; the
/// views see only the objects.
public struct JSONList<Item: JSONView>: Equatable, Sendable {
  public var entries: [JSONValue]

  public init(_ value: JSONValue) { entries = value.arrayValue ?? [] }
  public init(items: [Item]) { entries = items.map(\.json) }

  public var items: [Item] {
    entries.compactMap { $0.objectValue.map(Item.init(object:)) }
  }

  public var json: JSONValue { .array(entries) }

  /// Replaces the entry whose `id` matches, or appends: `savePreset`, `saveTarget`.
  public mutating func upsert(_ item: Item, id: String) {
    if let index = entries.firstIndex(where: { $0["id"]?.stringValue == id }) {
      entries[index] = item.json
    } else {
      entries.append(item.json)
    }
  }

  public mutating func removeAll(id: String) {
    entries.removeAll { $0["id"]?.stringValue == id }
  }
}

enum JS {
  /// ECMAScript ToNumber for the values JSON can hold, as `Number(raw.x)` applies it. Arrays and
  /// objects give NaN here; JavaScript would turn `[]` into 0 and `[5]` into 5.
  static func toNumber(_ value: JSONValue?) -> Double {
    switch value {
    case .number(let number): return number
    case .bool(let bool): return bool ? 1 : 0
    case .null: return 0
    case .string(let string):
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return 0 }
      if trimmed.lowercased().hasPrefix("0x"), let hex = UInt64(trimmed.dropFirst(2), radix: 16) { return Double(hex) }
      if trimmed == "Infinity" || trimmed == "+Infinity" { return .infinity }
      if trimmed == "-Infinity" { return -.infinity }
      // Swift accepts "inf", "nan" and hex floats, JavaScript does not.
      guard trimmed.allSatisfy({ "0123456789+-.eE".contains($0) }), let number = Double(trimmed) else { return .nan }
      return number
    default: return .nan
    }
  }

  /// JavaScript truthiness, for a `stored.x ?? fallback` whose stored value is used as a condition.
  static func truthy(_ value: JSONValue) -> Bool {
    switch value {
    case .null: false
    case .bool(let bool): bool
    case .number(let number): number != 0 && !number.isNaN
    case .string(let string): !string.isEmpty
    case .array, .object: true
    }
  }
}
