import Foundation

/// Theme presets of a project, `.quartz-gui/theme-presets.json`: a port of `themePresetsService.ts`.
/// In the project rather than the profile, because a preset belongs to that project's installed
/// themes and should travel with it. Each preset is kept as the object it is (`ThemePreset`).
public enum ThemePresets {
  public static func list(project: URL) -> [JSONValue] {
    JSONStore.read(QuartzGuiDirectory(project: project).themePresets, orEmpty: .array).arrayValue ?? []
  }

  /// Replaces the preset with the same id in its place, or adds it at the end.
  public static func save(_ preset: JSONValue, project: URL) throws {
    var presets = list(project: project)
    if let index = presets.firstIndex(where: { $0["id"] == preset["id"] }) { presets[index] = preset } else { presets.append(preset) }
    try write(presets, project)
  }

  public static func delete(id: String, project: URL) throws {
    try write(list(project: project).filter { $0["id"] != .string(id) }, project)
  }

  static func write(_ presets: [JSONValue], _ project: URL) throws {
    let directory = QuartzGuiDirectory(project: project)
    try directory.create()
    try JSONStore.write(.array(presets), to: directory.themePresets)
  }
}
