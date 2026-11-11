import Foundation

/// A switch for tests and measurements, from this launch's arguments only. UserDefaults also reads
/// the app's persistent domain, so one `defaults write … QHProfileDir` sent every later session into
/// another profile, and `QHWindowSize` there cleared the window frames at every start (review
/// 2026-11-11, N4). The release build keeps the four profile and window switches, so the package can
/// be measured against throwaway profiles; the test-only ones stay `#if DEBUG`.
public enum LaunchArgument {
  public static func string(_ name: String, arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
    guard let index = arguments.firstIndex(of: "-\(name)"), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
  }
}
