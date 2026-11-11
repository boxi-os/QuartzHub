import Foundation

/// The window frames macOS saves ("NSWindow Frame …") live in the app's one defaults domain, which
/// a test or measurement launch shares with the debug build the user works with. Such a launch
/// (`-QHProfileDir` or `-QHWindowSize`) used to clear every frame and then save its own over them
/// (review 2026-11-11, nebenbei 11). Now the first such launch keeps the user's frames aside, and
/// the next launch without either switch puts them back, whatever the launches in between saved.
/// A key in the defaults rather than a step at quit: XCUITest ends the app without one.
public enum WindowFrames {
  static let prefix = "NSWindow Frame "
  static let keptKey = "QHUserWindowFrames"

  public enum Launch: Equatable, Sendable {
    /// The user's own start.
    case own
    /// A throwaway profile: its frames may be saved, they are not the user's.
    case scratch
    /// As `scratch`, and every frame cleared, so `defaultSize` (the size asked for) wins.
    case pinnedSize
  }

  public static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Launch {
    if LaunchArgument.string("QHWindowSize", arguments: arguments) != nil { return .pinnedSize }
    if LaunchArgument.string("QHProfileDir", arguments: arguments) != nil { return .scratch }
    return .own
  }

  /// Before the first window: from `App.init`.
  public static func prepare(_ launch: Launch, defaults: UserDefaults = .standard) {
    let frames = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }
    switch launch {
    case .own:
      guard let kept = defaults.object(forKey: keptKey) as? [String: String] else { return }
      for key in frames.keys { defaults.removeObject(forKey: key) }
      for (key, value) in kept where key.hasPrefix(prefix) { defaults.set(value, forKey: key) }
      defaults.removeObject(forKey: keptKey)
    case .scratch, .pinnedSize:
      if defaults.object(forKey: keptKey) == nil {
        defaults.set(frames.compactMapValues { $0 as? String }, forKey: keptKey)
      }
      if launch == .pinnedSize { for key in frames.keys { defaults.removeObject(forKey: key) } }
    }
  }
}
