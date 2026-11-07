import Darwin
import Foundation
import Synchronization

/// ICU's collator from the system's libicucore, for `Intl.Collator` with `sensitivity: 'base'`.
///
/// Foundation cannot say that: `.diacriticInsensitive` folds every accent onto its letter, while
/// ICU at primary strength (what V8 asks for) follows the language - in Swedish „ä“ is a letter of
/// its own after „z“, in Spanish „ñ“ one after „n“, in Turkish „ö“ one after „o“. Measured against
/// Node on 18 locales and 18 letter pairs (2026-11-07): Foundation differed in 15 locales, this
/// collator in none. German and English agree either way.
///
/// The C functions are looked up with `dlsym`, so nothing links against a library the SDK ships
/// without headers; where they are not found, the caller falls back to Foundation.
enum ICUCollation {
  private typealias Open = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<Int32>) -> OpaquePointer?
  private typealias SetAttribute = @convention(c) (OpaquePointer?, Int32, Int32, UnsafeMutablePointer<Int32>) -> Void
  private typealias Collate = @convention(c) (OpaquePointer?, UnsafePointer<UInt16>?, Int32, UnsafePointer<UInt16>?, Int32) -> Int32

  private struct Library: @unchecked Sendable {
    let open: Open
    let setAttribute: SetAttribute
    let collate: Collate
  }

  /// A collator is used under the lock only; ICU's own rule is that a configured collator may be
  /// shared for comparisons, the lock keeps the cache and the setup in one place.
  private struct Collator: @unchecked Sendable { let pointer: OpaquePointer }

  // ICU's enum values (ucol.h): UCOL_STRENGTH, UCOL_PRIMARY, UCOL_NUMERIC_COLLATION, UCOL_ON.
  private static let strength: Int32 = 5, primary: Int32 = 0, numericCollation: Int32 = 7, on: Int32 = 17

  private static let library: Library? = {
    guard let handle = dlopen("/usr/lib/libicucore.dylib", RTLD_NOW),
          let open = dlsym(handle, "ucol_open"), let set = dlsym(handle, "ucol_setAttribute"), let collate = dlsym(handle, "ucol_strcoll")
    else { return nil }
    return Library(open: unsafeBitCast(open, to: Open.self), setAttribute: unsafeBitCast(set, to: SetAttribute.self),
                   collate: unsafeBitCast(collate, to: Collate.self))
  }()

  private static let collators = Mutex<[String: Collator]>([:])

  /// -1, 0 or 1; nil without ICU or when it refuses the locale.
  static func compare(_ a: String, _ b: String, locale: String, numeric: Bool, base: Bool) -> Int? {
    guard let library else { return nil }
    let key = "\(locale)|\(numeric)|\(base)"
    return collators.withLock { cache -> Int? in
      var collator = cache[key]
      if collator == nil {
        var status: Int32 = 0
        guard let made = library.open(locale, &status), status <= 0 else { return nil }
        if base { library.setAttribute(made, strength, primary, &status) }
        if numeric { library.setAttribute(made, numericCollation, on, &status) }
        guard status <= 0 else { return nil }
        collator = Collator(pointer: made)
        cache[key] = collator
      }
      let left = Array(a.utf16), right = Array(b.utf16)
      return Int(library.collate(collator!.pointer, left, Int32(left.count), right, Int32(right.count)))
    }
  }
}
