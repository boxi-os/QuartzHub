import Foundation

/// The settings under `configuration` that the project's Quartz describes and QuartzHub has no
/// field of its own for, from Quartz's own JSON Schema (`quartz/plugins/quartz-plugins.schema.json`,
/// the file `quartz.config.yaml` names in its first line). Konfiguration ▸ Website shows them under
/// „Weitere Einstellungen“ with the plugins' options form, so a setting a Quartz release adds is
/// there without a QuartzHub release: Quartz 5.3's `slugs.stripDiacritics` was the first (plan
/// „Quartz-Updates ohne ständiges Nachziehen“, 2026-11-28).
public enum QuartzConfigSchema {
  /// The keys a field of QuartzHub's own edits: Konfiguration (site settings, statistics, ignore
  /// patterns, processing), Stile (`theme`), and `fonts`, which Quartz's schema does not name yet.
  public static let ownKeys: Set<String> = [
    "pageTitle", "pageTitleSuffix", "enableSPA", "enablePopovers", "prefetch", "locale", "baseUrl", "theme", "analytics",
    "ignorePatterns", "publishAssets", "frontmatter", "links", "drafts", "contentIndex", "fonts",
  ]

  static let maxBytes = 4 * 1024 * 1024

  public static func path(project: String) -> String {
    NodePath.join(project, "quartz", "plugins", "quartz-plugins.schema.json")
  }

  /// The schema of `configuration`, with the fields QuartzHub shows itself left out; nil when the
  /// project has no such file or it cannot be read (an older Quartz: the section is not there).
  public static func moreSettings(project: String) -> NormalizedOptionSchema? {
    guard let data = try? Posix.read(path(project: project)), data.count <= maxBytes,
          let root = (try? JSJSON.parse(data))?.objectValue else { return nil }
    return moreSettings(schema: root)
  }

  static func moreSettings(schema root: JSONObject) -> NormalizedOptionSchema? {
    guard case .object(var configuration)? = root["properties"]?.objectValue?["configuration"] else { return nil }
    // A `$ref` inside resolves against the root's definitions.
    for key in ["$defs", "definitions"] where configuration[key] == nil {
      if let defs = root[key] { configuration[key] = defs }
    }
    var schema = OptionSchema.normalize(jsonSchema: .object(configuration), source: .configSchema)
    schema.fields = schema.fields.filter { !ownKeys.contains($0.key) }
    schema.notes = schema.notes.filter { note in note.path.first.map { !ownKeys.contains($0) } ?? true }
    return schema
  }

  /// The part of `configuration` the section edits: every key QuartzHub has no field for, the
  /// ones Quartz does not describe too, so they are seen rather than lost.
  public static func values(_ configuration: JSONObject) -> JSONObject {
    JSONObject(configuration.keys.filter { !ownKeys.contains($0) }.map { ($0, configuration[$0]!) })
  }

  /// `configuration` with the section's keys replaced by `next`: a key keeps its place, one that
  /// is gone from `next` goes, a new one comes last.
  public static func applying(_ next: JSONObject?, to configuration: JSONObject) -> JSONObject {
    let next = next ?? JSONObject()
    var out = configuration
    for key in configuration.keys where !ownKeys.contains(key) && next[key] == nil { out[key] = nil }
    for key in next.keys where !ownKeys.contains(key) { out[key] = next[key] }
    return out
  }
}
