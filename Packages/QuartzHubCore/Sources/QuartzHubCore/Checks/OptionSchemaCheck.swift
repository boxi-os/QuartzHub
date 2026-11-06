import Foundation

/// How many options of each plugin QuartzHub can show, per plugin of a real project: the
/// successor of QuartzControl's `npm run check:option-schema` (scripts/check-option-schema.mjs),
/// with the same table and the same sentences, so that both can be run against the same project
/// and compared line by line.
///
/// It exists because a missing field shows as an error on no screen: the plugin page shows what it
/// knows and is silent about the rest. Counted against the union of what knows about a plugin's
/// options (the keys under `options:` in the config, `defaultOptions`, `optionSchema`,
/// `configSchema`, and what the reader made of its chosen source), and sorted by what the reader
/// makes of each key: a field, only text (JSON), or invisible. Top-level keys only.
///
/// The reader is loaded, not rebuilt (`PluginSchemaReader`, `OptionSchema`), and the config is read
/// as QuartzControl's script read it: the whole YAML value, entries without a source counted and
/// passed over (`ConfigFile.read` would refuse the file).
public enum OptionSchemaCheck {
  public struct Report: Sendable {
    public var text: String
    /// Entries or packages that could not be read: counted and named, never "all good".
    public var unreadable: Int
  }

  public enum Failure: Error, CustomStringConvertible {
    case noConfig(String)
    case config(String)

    public var description: String {
      switch self {
      case .noConfig(let project): "Keine quartz.config.yaml unter \(project)"
      case .config(let reason): "quartz.config.yaml nicht lesbar: \(reason)"
      }
    }
  }

  public static func run(project given: String, only: String? = nil, dump: Bool = false,
                         runtime: RuntimeLocation = .current) async throws(Failure) -> Report {
    // `path.join(projekt, 'quartz.config.yaml')` for the head line, `path.resolve` for the rest.
    let configPath = normalizedJoin(given, "quartz.config.yaml")
    let project = URL(fileURLWithPath: FramePaths.resolve(given.hasPrefix("/") ? given : FileManager.default.currentDirectoryPath + "/" + given))
    guard let data = FileManager.default.contents(atPath: configPath) else { throw .noConfig(given) }
    let answer: JSONObject
    do {
      answer = try await Helper.call("yaml-edit", JSONObject([("op", .string("read")), ("text", .string(String(decoding: data, as: UTF8.self)))]),
                                     runtime: runtime)
    } catch {
      throw .config(error.description)
    }
    if let first = answer["errors"]?.arrayValue?.first { throw .config(first["message"]?.stringValue ?? "YAML") }
    let entries = answer["value"]?.objectValue?["plugins"]?.arrayValue ?? []

    var out: [String] = []
    var unreadable = 0
    var seen: [String: Int] = [:]
    struct Row {
      var name: String
      var enabled: Bool
      var location: String
      var source: String
      var notes: [OptionSchemaNote]
      var counts: [Int]
      var invisible: [String]
      var invisibleInConfig: [String]
      var strangers: [String]
    }
    var rows: [Row] = []
    let reader = PluginSchemaReader()

    var counted: [(name: String, object: JSONObject, source: PluginSource?)] = []
    for entry in entries {
      guard case .object(let object) = entry, let rawSource = object["source"], let base = PluginEntry.derivedName(rawSource) else {
        unreadable += 1
        continue
      }
      seen[base, default: 0] += 1
      if let only, base != only { continue }
      // Several instances of one plugin are named as on the plugin page: from the second on, `#n`.
      let name = seen[base]! > 1 ? "\(base)#\(seen[base]!)" : base
      // As the script handed the source over: unchecked, no channel in between.
      let source: PluginSource? = switch rawSource {
      case .string(let text): .string(text)
      case .object(let o): o["repo"]?.stringValue.map { .object(repo: $0, name: o["name"]?.stringValue) }
      default: nil
      }
      counted.append((name, object, source))
    }
    // One helper call for the whole project, as the plugin page makes it.
    var results = await reader.optionSchemas(project: project.path, sources: counted.compactMap(\.source), runtime: runtime).makeIterator()

    for (name, object, source) in counted {
      let manifest = source.map { readManifest(project: project, source: $0) } ?? (location: "keine package.json", quartz: nil)
      if manifest.location.hasPrefix("unlesbar") { unreadable += 1 }
      let quartz = manifest.quartz ?? JSONObject()
      let options = object["options"]?.objectValue ?? JSONObject()
      let result = source == nil ? PluginOptionSchemaResult() : results.next()!
      if result.unreadable != nil { unreadable += 1 }
      // As the page does: this entry's values on top, so a key no schema names still shows.
      let fields = OptionSchema.withPresentKeys(result.schema ?? NormalizedOptionSchema(source: .defaults, fields: [], notes: []), .object(options)).fields
      if dump {
        var shown = result
        shown.schema?.fields = fields
        out.append("--- \(name)\n\(JSJSON.stringify(shown.canonicalJSON))")
      }

      let keys = { (value: JSONValue?) in value?.objectValue?.keys ?? [] }
      let sources: [(String, [String])] = [
        ("config", options.keys),
        ("vorgaben", keys(quartz["defaultOptions"])),
        ("optionSchema", keys(quartz["optionSchema"])),
        ("configSchema", keys(quartz["configSchema"]?.objectValue?["properties"])),
        // What the reader has from its chosen source, without what only the defaults added.
        ("schema", fields.filter { $0.origin == .schema }.map(\.key))
      ]
      var all: [String] = []
      for (_, list) in sources { for key in list where !all.contains(key) { all.append(key) } }
      var by: [String: [String]] = ["Feld": [], "Text": [], "unsichtbar": []]
      for key in all {
        let shownAs = fields.first { $0.key == key }.map { $0.node == .json ? "Text" : "Feld" } ?? "unsichtbar"
        by[shownAs]!.append(key)
      }
      // A source that shares no option with config and defaults: the fingerprint of a wrongly
      // chosen interface (multilanguage once read `SeoOptions`).
      let config = sources[0].1, defaults = sources[1].1, schema = sources[4].1
      let known = Set(config + defaults)
      let wrongInterface = !known.isEmpty && !schema.isEmpty && !schema.contains(where: known.contains)

      rows.append(Row(
        name: name, enabled: object["enabled"] != .bool(false), location: manifest.location,
        source: result.schema?.source.rawValue ?? (result.unreadable != nil ? "unlesbar" : "–"),
        notes: result.schema?.notes ?? [],
        counts: sources.map(\.1.count) + [all.count, by["Feld"]!.count, by["Text"]!.count, by["unsichtbar"]!.count],
        invisible: by["unsichtbar"]!, invisibleInConfig: by["unsichtbar"]!.filter(config.contains),
        strangers: wrongInterface ? schema : []))
    }

    out.append("\(configPath)\n")
    out.append(pad("Plugin", 32) + pad("Quelle", 13)
               + ["config", "vorg.", "optS.", "confS.", "Schema", "alle", "Feld", "Text", "unsi."].map { padStart($0, 7) }.joined())
    for row in rows {
      out.append(pad(row.name + (row.enabled ? "" : " (aus)"), 32) + pad(row.source, 13)
                 + row.counts.map { "  " + padStart(String($0), 5) }.joined())
    }
    let sum = { (index: Int) in rows.reduce(0) { $0 + $1.counts[index] } }
    out.append("\n\(rows.count) Plugins, \(sum(5)) Optionen: \(sum(6)) als Feld, \(sum(7)) nur als Text, \(sum(8)) unsichtbar.")
    var bySource: [(String, Int)] = []
    for row in rows {
      if let index = bySource.firstIndex(where: { $0.0 == row.source }) { bySource[index].1 += 1 } else { bySource.append((row.source, 1)) }
    }
    out.append("Gelesen aus: \(bySource.map { "\($0.0) \($0.1)" }.joined(separator: ", ")).")
    let noteCount = rows.reduce(0) { $0 + $1.notes.count }
    if noteCount > 0 {
      out.append("\(noteCount) Stellen konnte der Leser nicht lesen oder nicht verstehen (als Text angeboten oder fürs Formular übergangen) — Liste unten.")
    }
    if unreadable > 0 {
      out.append("\(unreadable) Einträge nicht lesbar (Eintrag ohne source oder package.json kaputt) — nicht gezählt.")
    }
    out.append("\nUnsichtbar oder nicht lesbar, je Plugin:")
    var any = false
    for row in rows where !row.invisible.isEmpty || !row.strangers.isEmpty || !row.notes.isEmpty {
      any = true
      out.append("  \(row.name) [\(row.location)]")
      if !row.invisible.isEmpty {
        out.append("    unsichtbar: \(row.invisible.joined(separator: ", "))")
        if !row.invisibleInConfig.isEmpty { out.append("    davon in der Config gesetzt: \(row.invisibleInConfig.joined(separator: ", "))") }
      }
      if !row.strangers.isEmpty {
        out.append("    Schema teilt keine Option mit Config und Vorgaben (falsches Interface?): \(row.strangers.joined(separator: ", "))")
      }
      for note in row.notes {
        let path = note.path.joined(separator: ".")
        out.append("    nicht lesbar: \(path.isEmpty ? "(Wurzel)" : path) — \(note.reason)")
      }
    }
    if !any { out.append("  keine") }
    return Report(text: out.joined(separator: "\n") + "\n", unreadable: unreadable)
  }

  /// Where the package.json lies and its `quartz` block, as the script's `readManifest` said it.
  static func readManifest(project: URL, source: PluginSource) -> (location: String, quartz: JSONObject?) {
    guard let dir = PluginSchemaReader.packageDirectory(project: project.path, source: source) else { return ("keine package.json", nil) }
    let path = "\(dir)/package.json"
    guard FileManager.default.fileExists(atPath: path) else { return ("keine package.json", nil) }
    do {
      let value = try JSJSON.parse(try PluginSchemaReader.readFile(path))
      let location = String(dir.dropFirst(project.path.count + 1))
      return (location, value.objectValue?["quartz"]?.objectValue)
    } catch {
      return ("unlesbar: \(error)", nil)
    }
  }

  /// `path.join`: the parts joined with "/", then "." and ".." resolved; a relative path stays
  /// relative.
  static func normalizedJoin(_ base: String, _ name: String) -> String {
    let joined = base + "/" + name
    if joined.hasPrefix("/") { return FramePaths.resolve(joined) }
    var parts: [String] = []
    for part in joined.split(separator: "/", omittingEmptySubsequences: true) {
      if part == "." { continue }
      if part == "..", let last = parts.last, last != ".." { parts.removeLast() } else { parts.append(String(part)) }
    }
    return parts.joined(separator: "/")
  }

  // `padEnd`/`padStart` count UTF-16 code units, as JavaScript does.
  static func pad(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.utf16.count))
  }

  static func padStart(_ text: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - text.utf16.count)) + text
  }
}
