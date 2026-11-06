// A JSON value as JavaScript holds it after `JSON.parse`, so that QuartzHub can write a file the
// way QuartzControl would (docs/formats.md, "JSON-Dateien").
//
// Why not Codable straight away: QuartzControl writes every store with
// `JSON.stringify(value, null, 2)` from the object it read, so key order and unknown keys survive
// its round trip. Foundation's encoders know neither (JSONEncoder orders keys at random or
// alphabetically, and drops what the model does not declare). A model therefore reads its fields
// out of a `JSONValue` and writes its changes back into the same value, and everything it does not
// know stays where it was.

public enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  // A JavaScript number is a double; integers like `Date.now()` fit exactly below 2^53.
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object(JSONObject)
}

/// A JSON object with JavaScript's key order: array-index keys ("0", "1", "42") first in ascending
/// numeric order, then the other keys in insertion order. `JSON.parse` builds its objects that way,
/// and a duplicate key keeps its first position with the last value.
public struct JSONObject: Equatable, Sendable {
  private var indexKeys: [(UInt32, String)] = []
  private var otherKeys: [String] = []
  private var values: [String: JSONValue] = [:]

  public init() {}

  public init(_ pairs: [(String, JSONValue)]) {
    for (key, value) in pairs { self[key] = value }
  }

  /// Keys in the order `JSON.stringify` emits them.
  public var keys: [String] { indexKeys.map(\.1) + otherKeys }
  public var count: Int { values.count }
  public var isEmpty: Bool { values.isEmpty }

  public subscript(key: String) -> JSONValue? {
    get { values[key] }
    set {
      if let newValue {
        if values.updateValue(newValue, forKey: key) == nil { insertKey(key) }
      } else if values.removeValue(forKey: key) != nil {
        if let index = Self.arrayIndex(key) {
          indexKeys.removeAll { $0.0 == index }
        } else {
          otherKeys.removeAll { $0 == key }
        }
      }
    }
  }

  private mutating func insertKey(_ key: String) {
    guard let index = Self.arrayIndex(key) else {
      otherKeys.append(key)
      return
    }
    let position = indexKeys.firstIndex { $0.0 > index } ?? indexKeys.endIndex
    indexKeys.insert((index, key), at: position)
  }

  /// An array index in ECMAScript's sense: the canonical decimal form of an integer below 2^32 - 1
  /// ("0", "7", "4294967294"; not "07", "-1" or "1.0").
  static func arrayIndex(_ key: String) -> UInt32? {
    guard !key.isEmpty, key.utf8.count <= 10, key.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
      return nil
    }
    if key.utf8.count > 1 && key.utf8.first == 48 { return nil }
    guard let value = UInt64(key), value < 4_294_967_295 else { return nil }
    return UInt32(value)
  }

  public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
    lhs.keys == rhs.keys && lhs.values == rhs.values
  }
}

extension JSONValue {
  public subscript(key: String) -> JSONValue? {
    if case .object(let object) = self { return object[key] }
    return nil
  }

  public var objectValue: JSONObject? {
    if case .object(let object) = self { return object }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let array) = self { return array }
    return nil
  }

  public var stringValue: String? {
    if case .string(let string) = self { return string }
    return nil
  }

  public var boolValue: Bool? {
    if case .bool(let bool) = self { return bool }
    return nil
  }

  public var numberValue: Double? {
    if case .number(let number) = self { return number }
    return nil
  }

  public var isNull: Bool { self == .null }
}
