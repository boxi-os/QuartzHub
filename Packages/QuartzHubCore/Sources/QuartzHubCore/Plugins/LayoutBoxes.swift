import Foundation

/// What the Zusätzliche-Inhalte editor knows about quartz-layout-box (QuartzControl's
/// `routes/Plugins/layoutBoxes.ts`, the form extras `boxSilenced` and `layoutBoxRoot` of
/// `optionFormExtras.ts` and the small rules of `PluginOptionsForm/snippets.tsx`; measured against
/// them in LayoutBoxesTests).
///
/// Read from the plugin's LayoutBox.tsx rather than its README: a key whose value is null counts as
/// not written (base options and each byLang entry), `html` wins over `file` as soon as it is set
/// (an empty string included), a byLang entry is merged over the base options, and a box without
/// either reads `snippet.html` from `quartz/static/snippets`. Only a missing key falls back to the
/// default: an empty `dir` is the project itself, an empty `file` the folder, and a value that is
/// neither null nor a string makes the component throw. Before 0.4.1 null threw as well.
///
/// Options are taken as the config holds them (`JSONValue?`), not as an object: what JavaScript's
/// spread does with an array or a string is part of what is measured.
public enum LayoutBoxes {
  public static let plugin = "quartz-layout-box"
  /// The version whose LayoutBox.tsx the rules are read from.
  public static let readAgainst = "0.4.2"
  /// Versions whose src/ is the same as that one's (`git diff v0.4.1 v0.4.2 -- src` is empty).
  public static let sameCode = ["0.4.1"]
  /// The first version that reads a null option as a missing one; the ones before throw on it.
  public static let nullSafeSince = "0.4.1"
  public static let defaultDir = "quartz/static/snippets"
  public static let defaultFile = "snippet.html"
  /// The `{{…}}` tokens layout-box replaces (its placeholders.ts), and `frontmatter.<key>`.
  public static let placeholders = ["title", "slug", "root", "siteTitle", "baseUrl", "locale", "lang"]
  public static let frontmatterPlaceholder = "frontmatter."
  /// Where "Bild einfügen…" copies a picture to (Snippets.imagesDirectory).
  public static let imagesDir = "quartz/static/images"

  public struct Box: Sendable, Equatable, Identifiable {
    public var plugin: PluginEntry
    public var index: Int
    /// 1-based among the boxes, in config order: the "#n" the plugin list uses for an instance.
    public var occurrence: Int
    public var id: Int { occurrence }
  }

  public enum ContentKind: String, Sendable { case html, file }

  public struct Broken: Sendable, Equatable {
    public var key: String
    /// The language whose entry breaks; nil for the base options.
    public var lang: String?
  }

  public struct SnippetRef: Sendable, Equatable {
    public var file: String
    /// The folder it is read from: a language entry may bring its own `dir`.
    public var dir: String
    /// The language whose entry names it; nil for the base options.
    public var lang: String?
    /// Named by nobody: the plugin's default file.
    public var inherited: Bool
  }

  // ── JavaScript's object spread ─────────────────────────────────────────────────────────────────

  /// `{ ...value }`: an object as it is, an array or a string by index, anything else nothing.
  static func spread(_ value: JSONValue?) -> JSONObject {
    switch value {
    case .object(let object)?: return object
    case .array(let items)?: return JSONObject(items.enumerated().map { (String($0.offset), $0.element) })
    case .string(let text)?:
      return JSONObject(text.utf16.enumerated().map { (String($0.offset), .string(String(decoding: [$0.element], as: UTF16.self))) })
    default: return JSONObject()
    }
  }

  /// `{ ...a, ...b }`.
  static func merge(_ a: JSONObject, _ b: JSONObject) -> JSONObject {
    var out = a
    for key in b.keys { out[key] = b[key] }
    return out
  }

  /// A property of the options as JavaScript reads it off any value (nil for "undefined").
  static func get(_ options: JSONValue?, _ key: String) -> JSONValue? {
    if case .object(let object)? = options { return object[key] }
    return nil
  }

  // ── the rules ──────────────────────────────────────────────────────────────────────────────────

  /// The options as the plugin reads them: keys whose value is null dropped (its withoutNulls).
  public static func withoutNulls(_ options: JSONValue?) -> JSONObject {
    guard case .object(let object)? = options else { return JSONObject() }
    return JSONObject(object.keys.compactMap { key in object[key] == .null ? nil : (key, object[key]!) })
  }

  public static func boxes(_ plugins: [PluginEntry]) -> [Box] {
    var out: [Box] = []
    for (index, plugin) in plugins.enumerated() where PluginRepository.quartzName(plugin.source) == Self.plugin {
      out.append(Box(plugin: plugin, index: index, occurrence: out.count + 1))
    }
    return out
  }

  /// A folder as the config may write it: `./quartz/static/snippets/` and `quartz/static/snippets`
  /// are one, and `''`, `.` and `./` are all the project itself, written `.`.
  public static func normalizeDir(_ dir: String) -> String {
    var text = ReadmeText.trim(dir).replacingOccurrences(of: "\\", with: "/")
    if text.hasPrefix("./") { text.removeFirst(2) }
    while text.hasSuffix("/") { text.removeLast() }
    return text.isEmpty ? "." : text
  }

  public static func dir(_ options: JSONValue?) -> String {
    normalizeDir(get(options, "dir")?.stringValue ?? defaultDir)
  }

  public static func dir(_ options: JSONObject) -> String { dir(.object(options)) }

  public static func contentKind(_ options: JSONValue?) -> ContentKind {
    let html = get(options, "html")
    return html != nil && html != .null ? .html : .file
  }

  /// The file a box reads with these (merged) options; `''` names the folder itself.
  static func file(_ merged: JSONObject) -> String { merged["file"]?.stringValue ?? defaultFile }

  /// The option the plugin throws on with these (merged, nulls dropped) options.
  static func brokenKey(_ merged: JSONObject) -> String? {
    if let html = merged["html"] { return html.stringValue == nil ? "html" : nil }
    for key in ["file", "dir"] where merged[key] != nil && merged[key]?.stringValue == nil { return key }
    return nil
  }

  static func byLangEntries(_ options: JSONValue?) -> [(lang: String, entry: JSONValue)] {
    guard case .object(let map)? = get(options, "byLang") else { return [] }
    return map.keys.compactMap { key in
      switch map[key] {
      case .object?, .array?: (key, map[key]!)
      default: nil
      }
    }
  }

  /// The base options and each language entry merged over them, both as the plugin reads them.
  public static func mergedVariants(_ options: JSONValue?) -> [(lang: String?, options: JSONObject)] {
    let base = withoutNulls(options)
    return [(nil, base)] + byLangEntries(.object(base)).map { ($0.lang, merge(base, withoutNulls($0.entry))) }
  }

  /// Whether the installed version throws on a null option. Unknown counts as current.
  public static func nullBreaks(_ installed: String?) -> Bool {
    guard let installed, !installed.isEmpty else { return false }
    return SemVer.isNewer(nullSafeSince, than: installed)
  }

  /// Where a box makes the plugin throw: the base options, and each language entry merged over
  /// them. Before `nullSafeSince` a null option throws too.
  public static func brokenOptions(_ options: JSONValue?, installed: String?) -> [Broken] {
    if nullBreaks(installed) {
      let base = options ?? .object(JSONObject())
      var out: [Broken] = []
      if let key = brokenKey(spreadIfObject(base)) { out.append(Broken(key: key)) }
      for (lang, entry) in byLangEntries(base) {
        if let key = brokenKey(merge(spread(base), spread(entry))) { out.append(Broken(key: key, lang: lang)) }
      }
      return out
    }
    return mergedVariants(options).compactMap { lang, merged in brokenKey(merged).map { Broken(key: $0, lang: lang) } }
  }

  /// The value itself when it is an object; property reads off anything else find nothing.
  private static func spreadIfObject(_ value: JSONValue) -> JSONObject { value.objectValue ?? JSONObject() }

  /// The snippet files a box actually renders: for its base options and for each language entry.
  public static func snippetRefs(_ options: JSONValue?) -> [SnippetRef] {
    mergedVariants(options).compactMap { lang, merged in
      guard merged["html"] == nil, brokenKey(merged) == nil else { return nil }
      return SnippetRef(file: file(merged), dir: dir(merged), lang: lang, inherited: merged["file"] == nil)
    }
  }

  /// Every inline text of a box, base and per language, for the question which pictures it shows.
  public static func htmls(_ options: JSONValue?) -> [String] {
    var out: [String] = []
    if let html = get(options, "html")?.stringValue { out.append(html) }
    for (_, entry) in byLangEntries(options) { if let html = get(entry, "html")?.stringValue { out.append(html) } }
    return out
  }

  /// Languages whose entry brings its own text while the base reads a file: that text wins there.
  public static func langsWithOwnText(_ options: JSONValue?) -> [String] {
    byLangEntries(options).filter { get($0.entry, "html")?.stringValue != nil }.map(\.lang)
  }

  /// True when `text` points at the picture `name` in quartz/static/images, plainly or URL-encoded.
  /// Compared by UTF-16 units, as JavaScript's `includes`: "ü" and "u + ̈" are two names.
  public static func mentionsImage(_ text: String, _ name: String) -> Bool {
    JSText.includes(text, "static/images/\(name)") || JSText.includes(text, "static/images/\(JSURI.encodeComponent(name))")
  }

  /// The plugins after renaming a snippet in `dir`: every place of a box that renders `from` from
  /// that folder, the base options or a language entry, each merged as the plugin merges them,
  /// renders `to`, and every other place goes on rendering what it did. A box that read `from` as
  /// the default names `to` explicitly; a language entry with a folder of its own is left alone; a
  /// language entry that inherited the base file keeps the old name when only the base changes.
  public static func renameSnippetRefs(_ plugins: [PluginEntry], dir: String, from: String, to: String) -> (plugins: [PluginEntry], count: Int) {
    var count = 0
    let reads = { (options: JSONObject) -> Bool in
      let merged = withoutNulls(.object(options))
      return merged["html"] == nil && brokenKey(merged) == nil && Self.dir(merged) == dir && file(merged) == from
    }
    let next = plugins.map { p -> PluginEntry in
      guard PluginRepository.quartzName(p.source) == plugin else { return p }
      let raw = p.object["options"]
      let old: JSONValue = raw == nil || raw == .null ? .object(JSONObject()) : raw!
      var options = spread(old)
      var changed = false
      if reads(old.objectValue ?? JSONObject()) {
        options["file"] = .string(to)
        changed = true
      }
      let entries = byLangEntries(old)
      if !entries.isEmpty {
        var replaced: [(String, JSONValue)] = []
        var any = false
        for (lang, entry) in entries {
          let before = merge(withoutNulls(old), withoutNulls(entry))
          if before["html"] != nil {
            replaced.append((lang, entry))
            continue
          }
          let wanted = reads(before) ? to : file(before)
          if file(merge(withoutNulls(.object(options)), withoutNulls(entry))) == wanted {
            replaced.append((lang, entry))
            continue
          }
          changed = true
          any = true
          var copy = spread(entry)
          copy["file"] = .string(wanted)
          replaced.append((lang, .object(copy)))
        }
        if any { options["byLang"] = .object(merge(spread(get(old, "byLang")), JSONObject(replaced))) }
      }
      guard changed else { return p }
      count += 1
      var entry = p
      entry.object["options"] = .object(options)
      return entry
    }
    return (next, count)
  }

  // ── the form's extras ──────────────────────────────────────────────────────────────────────────

  /// What the tiles "Text | Datei" switch: the section under them (layout-box's group Content).
  static let contentKeys: Set<String> = ["html", "file", "dir", "placeholders"]

  /// Whether a content option does nothing: while text is set, `file` and its folder. An `html:`
  /// left empty is no text: since 0.4.1 it does nothing either, before that it is the error.
  public static func silenced(_ options: JSONObject, installed: String?) -> (String) -> Bool {
    let kind = contentKind(.object(options))
    let emptyHtml = options["html"] == .null
    let emptyHtmlBreaks = emptyHtml && nullBreaks(installed)
    return { key in kind == .html ? key == "file" || key == "dir" : key == "html" && emptyHtml && !emptyHtmlBreaks }
  }

  /// The form's extras for a box (`layoutBoxRoot`): the content first, under the kind it is, then
  /// the groups both kinds share. `withTiles: false` (inspector, plugin list): no "Text | Datei"
  /// above, so the text field stands in the section too, under a title naming neither kind.
  public static func root(options: JSONObject, installed: String?, translate: @escaping OptionFormText.Translate = catalog,
                          withTiles: Bool = true) -> OptionRoot {
    let kind = contentKind(.object(options))
    let silenced = silenced(options, installed: installed)
    return OptionRoot(
      inactiveReason: { key in
        guard silenced(key) else { return nil }
        return translate(kind == .html ? silencedByText : silencedEmpty, nil)
      },
      hideUnlessSet: { $0 == "file" || $0 == "dir" || $0 == "html" },
      lead: OptionRoot.Lead(has: { contentKeys.contains($0) },
                            title: translate(!withTiles ? leadContent : kind == .html ? leadText : leadFile, nil), empty: ""),
      entryReason: { key, entry, above in
        guard key == "file" || key == "dir" else { return nil }
        let merged = merge(withoutNulls(.object(above)), withoutNulls(.object(entry)))
        return contentKind(.object(merged)) == .html ? translate(silencedByText, nil) : nil
      })
  }

  public static let catalog: OptionFormText.Translate = { key, _ in
    switch key {
    case "extraContent.silencedByText": L10n.t("extraContent.silencedByText")
    case "extraContent.silencedEmpty": L10n.t("extraContent.silencedEmpty")
    case "extraContent.leadContent": L10n.t("extraContent.leadContent")
    case "extraContent.leadText": L10n.t("extraContent.leadText")
    case "extraContent.leadFile": L10n.t("extraContent.leadFile")
    default: key
    }
  }

  static let silencedByText = "extraContent.silencedByText"
  static let silencedEmpty = "extraContent.silencedEmpty"
  static let leadContent = "extraContent.leadContent"
  static let leadText = "extraContent.leadText"
  static let leadFile = "extraContent.leadFile"

  // ── the snippet fields (snippets.tsx) ──────────────────────────────────────────────────────────

  public enum SnippetFormat: String, Sendable { case html, markdown }

  public static func format(ofFile name: String) -> SnippetFormat {
    name.lowercased().hasSuffix(".md") ? .markdown : .html
  }

  /// The reference a snippet needs to show a picture under quartz/static: `{{root}}` is the way
  /// from the page to the site root, which layout-box fills in on every page depth.
  public static func imageReference(_ relativePath: String, format: SnippetFormat) -> String {
    let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map { JSURI.encodeComponent(String($0)) }
    let url = "{{root}}/static/\(parts.joined(separator: "/"))"  // not a file path
    return format == .markdown ? "![](<\(url)>)" : "<img src=\"\(url)\" alt=\"\">"
  }

  /// The value of a sibling option as it applies: set here, set above (a byLang entry), or the default.
  public static func siblingValue(_ key: String, values: JSONObject, fields: [OptionField]) -> JSONValue? {
    if let value = values[key] { return value }
    return fields.first { $0.key == key }?.defaultValue
  }
}
