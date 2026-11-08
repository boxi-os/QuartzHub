import Foundation

/// The project picture in the site header: one quartz-layout-box instance that QuartzHub writes and
/// recognises again by its class (QuartzControl's `shared/projectImageBox.ts`, measured against it in
/// `scripts/project-image-box-golden.mjs`). The plugin does the rest: `{{root}}` and `{{siteTitle}}`
/// placeholders, and a light/dark pair through `.img-light` / `.img-dark`, which it styles itself.
///
/// Pure functions over a draft plugin list: the Konfiguration page holds quartz.config.yaml and
/// saves it; nothing here writes.
public enum ProjectImageBox {
  public static let layoutBoxSource = "github:boxi-os/quartz-layout-box"
  public static let projectImageClass = "layout-box-project-image"

  /// The size sits on the images: a site's stylesheet is not QuartzHub's to write, and without a
  /// height a 512px icon fills the header. `display` is not set inline, or it would beat the
  /// plugin's light/dark switch.
  static let imageStyle = "height:2.5rem;width:auto"

  public static func isLayoutBox(_ entry: PluginEntry) -> Bool {
    guard case .string(let source)? = entry.source else { return false }
    return source.contains("quartz-layout-box")
  }

  public static func html(hasDark: Bool) -> String {
    func img(_ cls: String, _ file: String) -> String {
      "<img\(cls.isEmpty ? "" : " class=\"\(cls)\"") src=\"{{root}}/static/\(file)\" alt=\"{{siteTitle}}\" style=\"\(imageStyle)\">"
    }
    let images = hasDark ? img("img-light", "icon.png") + img("img-dark", "icon-dark.png") : img("", "icon.png")
    return "<a class=\"project-image\" href=\"{{root}}/\">\(images)</a>"
  }

  /// `entry.options?.<key>`: only an object has properties here; a string's or an array's are
  /// undefined for every key this file reads.
  private static func option(_ entry: PluginEntry, _ key: String) -> JSONValue? {
    entry.object["options"]?.objectValue?[key]
  }

  public static func findOwn(_ plugins: [PluginEntry]) -> Int? {
    plugins.firstIndex { isLayoutBox($0) && option($0, "className") == .string(projectImageClass) }
  }

  /// The entry `quartz plugin add` writes: default options, sitting in the left sidebar. Recognised
  /// only so that the one just installed becomes the header picture instead of a second empty box.
  public static func isFresh(_ entry: PluginEntry) -> Bool {
    isLayoutBox(entry) && !JS.truthy(option(entry, "html")) && !JS.truthy(option(entry, "className"))
  }

  /// Another layout box that already shows the picture (a template's mark): recognised by what it
  /// shows, not by the template's class. The header switch cannot see it, and switching it on put
  /// the picture there twice.
  public static func findOther(_ plugins: [PluginEntry]) -> Int? {
    plugins.firstIndex { entry in
      guard isLayoutBox(entry), entry.object["enabled"] != .bool(false),
            option(entry, "className") != .string(projectImageClass) else { return false }
      let html = option(entry, "html").map(JS.string) ?? ""
      return html.contains("/static/icon.png\"") || html.contains("/static/icon.png'")
    }
  }

  /// The list with the header picture switched on, or its HTML brought up to date. `replaceIndex`
  /// names the box just installed, when there was none before.
  public static func with(_ plugins: [PluginEntry], hasDark: Bool, replaceIndex: Int? = nil) -> [PluginEntry] {
    let html = html(hasDark: hasDark)
    var plugins = plugins
    if let existing = findOwn(plugins) {
      // `{ ...p.options, html }`: findOwn matched a className, so options is an object.
      var options = plugins[existing].object["options"]?.objectValue ?? JSONObject()
      options["html"] = .string(html)
      plugins[existing].object["options"] = .object(options)
      return plugins
    }
    func instance(_ base: JSONObject) -> PluginEntry {
      var object = base
      object["enabled"] = .bool(true)
      object["options"] = .object(JSONObject([
        ("html", .string(html)), ("className", .string(projectImageClass)), ("placeholders", .bool(true)),
      ]))
      object["layout"] = .object(JSONObject([("position", .string("header")), ("priority", .number(10))]))
      return PluginEntry(object: object)
    }
    if let replaceIndex, plugins.indices.contains(replaceIndex), isFresh(plugins[replaceIndex]) {
      plugins[replaceIndex] = instance(plugins[replaceIndex].object)
      return plugins
    }
    let source = plugins.first(where: isLayoutBox)?.source ?? .string(layoutBoxSource)
    plugins.append(instance(JSONObject([("name", .string("quartz-layout-box")), ("source", source), ("enabled", .bool(true))])))
    return plugins
  }

  /// The list without the header picture; the plugin itself stays installed.
  public static func without(_ plugins: [PluginEntry]) -> [PluginEntry] {
    guard let existing = findOwn(plugins) else { return plugins }
    var plugins = plugins
    plugins.remove(at: existing)
    return plugins
  }
}
