import Foundation

// The few pieces of JavaScript's semantics a port needs when it reads a file nothing has checked:
// a generated frame module is built from whatever frame.json holds (GridFrameCss), and QuartzControl
// read those values with JavaScript's coercions, not with a schema.

extension JS {
  /// `String(value)` for a JSON value; `undefined` (a missing key) is "undefined".
  static func string(_ value: JSONValue?) -> String {
    guard let value else { return "undefined" }
    switch value {
    case .null: return "null"
    case .bool(let bool): return bool ? "true" : "false"
    case .number(let number): return JSJSON.numberToString(number)
    case .string(let string): return string
    case .array(let items): return join(items, ",")
    case .object: return "[object Object]"
    }
  }

  /// `Array.prototype.join`: null and undefined become "", everything else `String()`.
  static func join(_ items: [JSONValue?], _ separator: String) -> String {
    items.map { item in
      guard let item, item != .null else { return "" }
      return string(item)
    }.joined(separator: separator)
  }

  static func join(_ items: [JSONValue], _ separator: String) -> String {
    join(items.map { Optional($0) }, separator)
  }

  /// The characters `String.prototype.trim` takes: WhiteSpace and LineTerminator of ECMAScript.
  static func isTrimmed(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
      return true
    default:
      return false
    }
  }

  static func trim(_ text: String) -> String {
    let scalars = text.unicodeScalars
    guard let start = scalars.firstIndex(where: { !isTrimmed($0) }) else { return "" }
    let end = scalars.lastIndex(where: { !isTrimmed($0) })!
    return String(scalars[start...end])
  }

  /// JavaScript's truthiness of a JSON value; `undefined` is falsy.
  static func truthy(_ value: JSONValue?) -> Bool {
    switch value {
    case nil, .null?, .bool(false)?: return false
    case .number(let number)?: return number != 0 && !number.isNaN
    case .string(let string)?: return !string.isEmpty
    default: return true
    }
  }

  /// `typeof value === 'object' && value !== null`: objects and arrays.
  static func isObject(_ value: JSONValue?) -> Bool {
    switch value {
    case .object?, .array?: return true
    default: return false
    }
  }

  /// `Object.keys(value).length`.
  static func keyCount(_ value: JSONValue) -> Int {
    switch value {
    case .object(let object): return object.count
    case .array(let items): return items.count
    case .string(let string): return string.utf16.count
    default: return 0
    }
  }

  /// `Math.round`: halves go up.
  /// `a.localeCompare(b)`: ICU collation, as -1, 0 or 1.
  static func localeCompare(_ a: String, _ b: String) -> Double {
    switch a.compare(b, options: [], range: nil, locale: Locale(identifier: "de")) {
    case .orderedAscending: -1
    case .orderedSame: 0
    case .orderedDescending: 1
    }
  }

  static func round(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

  /// A TypeError as `String(error)` prints it.
  struct TypeError: Error, CustomStringConvertible, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { "TypeError: \(message)" }
  }

  /// How V8 names a value in "Cannot read properties of …".
  static func readError(_ value: JSONValue?, _ property: String) -> TypeError {
    TypeError("Cannot read properties of \(value == nil ? "undefined" : "null") (reading '\(property)')")
  }

  /// `Array.prototype.sort` with a comparator, as V8 runs it: TimSort, whose order for an array of
  /// fewer than 64 elements is one natural run plus binary insertion. That matters only for a
  /// comparator that is not consistent (one that answers NaN, which V8 takes as 0): a priority that
  /// is missing in quartz.config.yaml sorts where V8 put it. Longer arrays are sorted stably, which
  /// for a consistent comparator is the same result.
  static func sort<T>(_ array: inout [T], by compare: (T, T) -> Double) {
    func order(_ a: T, _ b: T) -> Double {
      let value = compare(a, b)
      return value.isNaN ? 0 : value
    }
    let count = array.count
    guard count >= 2 else { return }
    guard count < 64 else {
      array = mergeSorted(array, { order($0, $1) })
      return
    }
    // CountAndMakeRun
    var run = 2
    let descending = order(array[1], array[0]) < 0
    var previous = array[1]
    var index = 2
    while index < count {
      let current = array[index]
      let result = order(current, previous)
      if descending ? result >= 0 : result < 0 { break }
      previous = current
      run += 1
      index += 1
    }
    if descending { array[0..<run].reverse() }
    // BinaryInsertionSort from the end of the run
    var start = run
    while start < count {
      var left = 0, right = start
      let pivot = array[start]
      while left < right {
        let mid = left + ((right - left) >> 1)
        if order(pivot, array[mid]) < 0 { right = mid } else { left = mid + 1 }
      }
      var position = start
      while position > left {
        array[position] = array[position - 1]
        position -= 1
      }
      array[left] = pivot
      start += 1
    }
  }

  private static func mergeSorted<T>(_ items: [T], _ order: (T, T) -> Double) -> [T] {
    guard items.count > 1 else { return items }
    let middle = items.count / 2
    let left = mergeSorted(Array(items[..<middle]), order)
    let right = mergeSorted(Array(items[middle...]), order)
    var merged: [T] = []
    merged.reserveCapacity(items.count)
    var i = 0, j = 0
    while i < left.count && j < right.count {
      if order(right[j], left[i]) < 0 { merged.append(right[j]); j += 1 } else { merged.append(left[i]); i += 1 }
    }
    merged.append(contentsOf: left[i...])
    merged.append(contentsOf: right[j...])
    return merged
  }
}
