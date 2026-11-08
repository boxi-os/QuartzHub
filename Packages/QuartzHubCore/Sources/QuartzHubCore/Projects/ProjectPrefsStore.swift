import Foundation

/// `<project>/.quartz-gui/project-prefs.json`, a port of `projectPrefsService.ts`: what belongs to
/// one project and to the app rather than to Quartz, so it travels with the folder and is in the
/// snapshots. One entry so far, the build output folder (`ProjectPrefs.outputDir`).
///
/// Reading never creates `.quartz-gui/`. A file of the wrong shape is moved aside like any other
/// store (`JSONStore.read(_:orEmpty:)`). Writing goes into the object that was read, so a key a
/// later version adds survives this one; QuartzControl wrote the renderer's object whole, which
/// held `outputDir` only.
public enum ProjectPrefsStore {
  public static func read(project: String) -> ProjectPrefs {
    let value = JSONStore.read(QuartzGuiDirectory(project: project).projectPrefs, orEmpty: .object)
    return ProjectPrefs(object: value.objectValue ?? JSONObject())
  }

  public static func write(_ prefs: ProjectPrefs, project: String) throws {
    let dir = QuartzGuiDirectory(project: project)
    try dir.create()
    try JSONStore.write(prefs.json, to: dir.projectPrefs)
  }

  /// Read, change, write: the usual way to set one field.
  public static func update(project: String, _ change: (inout ProjectPrefs) -> Void) throws {
    var prefs = read(project: project)
    change(&prefs)
    try write(prefs, project: project)
  }
}

extension ProjectPrefs {
  /// Where `quartz build` writes, as `resolveBuildDir` in projectDirs.ts answers: Quartz's own
  /// `public/` for '', an absolute folder untouched (the export dialog gives one, and a plain join
  /// would put "/export" under the project), a relative one joined and normalized as `path.join`
  /// does ("../site" is next to the project).
  public func buildDirectory(project: String) -> String {
    BuildOutputGuard.buildDirectory(project: project, outputDir: outputDir)
  }
}

extension ProjectPrefs {
  /// Whether `value` may be stored as `outputDir`: QuartzControl's `projectPrefs.save` schema
  /// (`z.union([z.literal(''), buildOutputDir])` in `ipc/schemas.ts`). Empty, an absolute path of
  /// at most 4096 UTF-16 units, or a relative one of at most 1024 without a ".." segment (split at
  /// "/" and "\", as the schema does). QuartzControl showed zod's own message; here it is one
  /// sentence in the user's language, nil when the value is fine.
  public static func outputDirProblem(_ value: String) -> String? {
    if value.isEmpty { return nil }
    let length = value.utf16.count
    if value.hasPrefix("/") { return length <= 4096 ? nil : L10n.t("buildServer.exportDirInvalid") }
    let segments = value.split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "\\" }
    return length <= 1024 && !segments.contains("..") ? nil : L10n.t("buildServer.exportDirInvalid")
  }
}
