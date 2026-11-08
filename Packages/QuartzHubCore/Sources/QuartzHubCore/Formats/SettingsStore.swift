import Foundation
import Synchronization

/// `settings.json` of QuartzHub's profile, read and changed as a whole. QuartzControl sent the whole
/// object on every write (`settingsService` overwrites), so a section never cleared the fields
/// another one owns; here every change reads the file, changes the one field and writes it back.
public enum SettingsStore {
  private static let serial = Mutex<Void>(())

  public static func read(_ profile: ProfileDirectory) -> SettingsFile {
    SettingsFile(object: JSONStore.read(profile.settings, orEmpty: .object).objectValue ?? JSONObject())
  }

  @discardableResult
  public static func update(_ profile: ProfileDirectory, _ change: (inout SettingsFile) -> Void) throws -> SettingsFile {
    try serial.withLock { _ in
      var file = read(profile)
      change(&file)
      try Posix.mkdirs(profile.path)
      try JSONStore.write(file.json, to: profile.settings)
      return file
    }
  }

  /// The default folder for new projects as the field takes it (`expandHome`, then absolute or
  /// nothing): "~" and "~/…" become the home folder, an empty field removes the setting.
  public static func projectDirectory(_ typed: String, home: String = NSHomeDirectory()) throws -> String? {
    let trimmed = JS.trim(typed)
    var expanded = trimmed
    if trimmed == "~" || trimmed.hasPrefix("~/") {
      var base = home
      if base.hasSuffix("/") { base.removeLast() }
      expanded = trimmed == "~" ? base : "\(base)/\(trimmed.dropFirst(2))"
    }
    if expanded.isEmpty { return nil }
    guard expanded.hasPrefix("/") else { throw Failure.notAbsolute }
    return expanded
  }

  public enum Failure: Error, Equatable {
    case notAbsolute
    public var message: String { L10n.t("settings.projects.mustBeAbsolute") }
  }
}
