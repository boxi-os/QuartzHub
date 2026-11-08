import Foundation
import QuartzHubCore

/// What the pages state about something rather than compute from it (QuartzControl's
/// `src/utils/format.ts`), in the language of the catalog.
enum Formats {
  /// `formatBytes`: decimal units, one decimal below 10 from kB on (what a site weighs on a server).
  static func bytes(_ count: Int) -> String {
    let units = ["B", "kB", "MB", "GB"]
    var value = Double(count)
    var unit = 0
    while value >= 1000 && unit < units.count - 1 {
      value /= 1000
      unit += 1
    }
    let digits = unit > 0 && value < 10 ? 1 : 0
    return value.formatted(.number.precision(.fractionLength(0...digits)).locale(Locale(identifier: L10n.language))) + " " + units[unit]
  }

  /// `weekOfMonth`, not `weekOfYear`: the formatter reads only the former (measured: three weeks as
  /// `weekOfYear` came out as "").
  private static let units: [(Calendar.Component, Double)] = [
    (.year, 31_536_000), (.month, 2_592_000), (.weekOfMonth, 604_800), (.day, 86_400), (.hour, 3_600), (.minute, 60)
  ]

  /// `formatRelativeTime`: "vor 12 Minuten", "gestern" (`numeric: 'auto'`), in the largest unit the
  /// distance reaches; nil for no date.
  static func relative(_ date: Date?, now: Date = Date()) -> String? {
    guard let date else { return nil }
    // Math.round: halves go up, also below zero (-2.5 is -2).
    func round(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }
    let seconds = Double(round(date.timeIntervalSince(now)))
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: L10n.language)
    formatter.dateTimeStyle = .named
    for (unit, size) in units where abs(seconds) >= size {
      var components = DateComponents()
      components.setValue(round(seconds / size), for: unit)
      return formatter.localizedString(from: components)
    }
    var components = DateComponents()
    components.second = Int(seconds)
    return formatter.localizedString(from: components)
  }

  /// An ISO 8601 stamp: QuartzControl's `toISOString` (with milliseconds) or git's `%aI` (with an
  /// offset, without them).
  static func date(iso: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: iso) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)
  }

  /// "0:42", the clock of `BuildActivityLine`.
  static func elapsed(since: Date, now: Date = Date()) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(since)))
    return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
  }
}
