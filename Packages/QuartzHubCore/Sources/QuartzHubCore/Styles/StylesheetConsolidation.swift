import Foundation

/// Putting a project's 31 template stylesheets of 1.0 together into the twelve of 1.1: a port of
/// `shared/stylesheetConsolidation.ts`. Pure concatenation, every section opened by a marker line
/// naming the stylesheet it came from, base.scss split at its own headings into foundation, layout
/// and content. What the user changed in those files stays; only the load order moves.
///
/// Left alone: a template stylesheet switched off (put into a file that loads, it would be on);
/// every other stylesheet (it keeps its place after the template file it followed; one whose name
/// one of the twelve takes is renamed with a number); and a project put together once, told apart
/// by the header line each of the twelve gets or the first line the 1.1 template gives them. Both
/// lines name QuartzControl and stay as they are: they are how both apps recognise the form.
public enum StylesheetConsolidation {
  /// The twelve, in load order.
  public static let order = ["foundation", "layout", "components-header", "plugin-multilanguage", "components-navigation",
                             "plugin-navigations", "components-note", "content", "callouts", "pages", "plugin-layout-box", "a11y"]

  static let baseFoundation = ["box model", "icons", "disclosure icons", "focus", "skip navigation", "motion"]
  static let baseContent = ["typographic rhythm"]

  /// What each of the twelve is made of; `base` stands for its share of base.scss.
  static let parts: [String: [String]] = [
    "foundation": ["base"],
    "layout": ["base", "site-footer"],
    "components-header": ["nav-header", "nav-search", "page-search-results", "nav-darkmode", "nav-reader-mode"],
    "plugin-multilanguage": ["nav-language-switcher"],
    "components-navigation": ["nav-explorer", "meta-breadcrumbs"],
    "plugin-navigations": ["nav-navigations"],
    "components-note": ["meta-note-properties", "meta-tag-list", "aside-toc", "aside-backlinks", "aside-graph", "aside-recent-notes"],
    "content": ["meta-title-and-date", "base", "body-content", "body-code", "body-math", "body-mermaid", "body-media"],
    "callouts": ["body-callouts"],
    "pages": ["page-listing", "page-bases", "page-canvas", "page-popover", "page-404"],
    "plugin-layout-box": ["plugin-layout-box"],
    "a11y": ["a11y"]
  ]

  /// The 31 stylesheets of the template before 1.1.
  public static let legacy: Set<String> = Set(parts.values.flatMap { $0 })
  static let names: Set<String> = Set(order)

  static func stem(_ path: String) -> String {
    JSText.replaceAll(JSText.slice(path, 7), #"\.scss\z"#, with: "")
  }

  static func isLegacy(_ path: String) -> Bool {
    JSText.startsWith(path, "custom/") && JSText.endsWith(path, ".scss") && legacy.contains(stem(path))
  }

  /// One only the 31 have: a11y and plugin-layout-box are named alike before and after.
  public static func isLegacyOnly(_ path: String) -> Bool {
    isLegacy(path) && !names.contains(stem(path))
  }

  /// One of the ten names only the twelve have.
  public static func isConsolidatedOnly(_ path: String) -> Bool {
    JSText.startsWith(path, "custom/") && JSText.endsWith(path, ".scss") && names.contains(stem(path)) && !legacy.contains(stem(path))
  }

  /// A template package's order of the twelve: one new name, none only the 31 have.
  public static func isConsolidatedOrder(_ order: [String]) -> Bool {
    order.contains(where: isConsolidatedOnly) && !order.contains(where: isLegacyOnly)
  }

  static func header(_ target: String) -> String {
    "// \(target) - put together by QuartzControl; each section is named after its former stylesheet."
  }

  /// The header before QuartzControl shortened it; projects were put together with it (gui-test).
  static func earlierHeader(_ target: String) -> String {
    "// \(target) - put together by QuartzControl from the stylesheets named in the sections below."
  }

  /// The first line of each of the ten new names as the 1.1 template writes it.
  public static let templateFirstLines: [String: String] = [
    "foundation": "// Foundation: box model, icons, disclosure chevron, focus, skip link, reduced motion.",
    "layout": "// Layout: sticky header, columns and their scrolling, panels, breakpoints, footer.",
    "components-header": "// Header components: the bar, search and its results, colour scheme, reader mode.",
    "plugin-multilanguage": "// quartz-multilanguage: language switcher and translation notice.",
    "components-navigation": "// Navigation components: Quartz's explorer and the breadcrumbs.",
    "plugin-navigations": "// quartz-navigations: all ten variants. This site uses the accordion (left column, drawer on",
    "components-note": "// Note components: properties and tags above it; outline, backlinks, graph and recent notes beside it.",
    "content": "// Content: title and date, typographic rhythm, text, code, maths, diagrams and media.",
    "callouts": "// Callouts: colours per type, fold, nesting.",
    "pages": "// Generated pages: folder and tag listings, Bases, Canvas, Excalidraw, link preview, 404."
  ]

  /// Whether a loaded one of the twelve was written by a run before (its header) or comes from the
  /// 1.1 template (its first line). `files`: `custom/<name>.scss` → content for the twelve on disk.
  public static func wasConsolidated(_ files: [String: String], _ order: [String]) -> Bool {
    let loaded = Set(order)
    return Self.order.contains { target in
      let path = "custom/\(target).scss"
      guard loaded.contains(path) else { return false }
      let content = files[path] ?? ""
      let firstLine = trimEnd(JSText.split(content, "\n")[0])
      return JSText.startsWith(content, header(target)) || JSText.startsWith(content, earlierHeader(target))
        || (templateFirstLines[target].map { firstLine == $0 } ?? false)
    }
  }

  /// `trimEnd()`.
  static func trimEnd(_ text: String) -> String {
    let scalars = text.unicodeScalars
    guard let last = scalars.lastIndex(where: { !JS.isTrimmed($0) }) else { return "" }
    return String(scalars[...last])
  }

  public static func canConsolidate(_ order: [String], consolidated: Bool) -> Bool {
    !consolidated && order.contains(where: isLegacyOnly)
  }

  public static func legacyCount(_ order: [String], consolidated: Bool) -> Int {
    canConsolidate(order, consolidated: consolidated) ? order.filter(isLegacy).count : 0
  }

  /// `// ===… name`, 100 characters wide.
  public static func sectionMarker(_ name: String) -> String {
    "// \(String(repeating: "=", count: max(3, 100 - 4 - JSText.length(name)))) \(name)"
  }

  static func trimNewlines(_ text: String) -> String {
    JSText.replaceAll(text, #"\A\n+|\n+\z"#, with: "")
  }

  /// base.scss in three shares at its `/* ---- title */` headings; what stands before the first
  /// opens foundation, an unknown heading goes to layout.
  public static func splitBase(_ text: String) -> (foundation: String, layout: String, content: String) {
    var shares: [String: [String]] = ["foundation": [], "layout": [], "content": []]
    var current = "foundation"
    for line in JSText.split(text, "\n") {
      if let match = JSText.firstMatch(line, #"\A/\* -{3,} ([^\n\r\x{2028}\x{2029}]*?) \*/["# + JSText.space + #"]*\z"#) {
        let title = JS.trim(match.groups[1] ?? "")
        current = baseFoundation.contains(title) ? "foundation" : baseContent.contains(title) ? "content" : "layout"
      }
      shares[current]!.append(line)
    }
    let join = { (lines: [String]) in trimNewlines(lines.joined(separator: "\n")) }
    return (join(shares["foundation"]!), join(shares["layout"]!), join(shares["content"]!))
  }

  public struct Plan: Equatable, Sendable {
    /// The new files in order, `custom/<name>.scss` → content.
    public var write: [(path: String, content: String)]
    /// The template stylesheets that went into them and are not one of them.
    public var remove: [String]
    /// User files whose name one of the twelve takes, in order.
    public var rename: [(from: String, to: String)]
    public var order: [String]

    public static func == (a: Plan, b: Plan) -> Bool {
      a.write.map(\.path) == b.write.map(\.path) && a.write.map(\.content) == b.write.map(\.content)
        && a.remove == b.remove && a.rename.map(\.from) == b.rename.map(\.from) && a.rename.map(\.to) == b.rename.map(\.to) && a.order == b.order
    }
  }

  /// The plan for one project: `order` its load order, `files` the content of every stylesheet in it
  /// and of every one on disk with one of the twelve names, `onDisk` every stylesheet in custom/.
  public static func plan(_ order: [String], _ files: [String: String], _ onDisk: [String]) -> Plan {
    guard canConsolidate(order, consolidated: wasConsolidated(files, order)) else { return Plan(write: [], remove: [], rename: [], order: order) }
    var loaded: [String] = []
    for path in order where isLegacy(path) && !loaded.contains(stem(path)) { loaded.append(stem(path)) }
    let read = { (name: String) in trimNewlines(files["custom/\(name).scss"] ?? "") }
    let base = loaded.contains("base") ? splitBase(read("base")) : nil

    var write: [(String, String)] = []
    for target in Self.order {
      var sections: [String] = []
      for part in parts[target]! where loaded.contains(part) {
        if part == "base" {
          let share = target == "foundation" ? base!.foundation : target == "layout" ? base!.layout : base!.content
          if !share.isEmpty { sections.append("\(sectionMarker("base"))\n\n\(share)") }
        } else {
          sections.append("\(sectionMarker(part))\n\n\(read(part))")
        }
      }
      if sections.isEmpty { continue }
      write.append(("custom/\(target).scss", "\(header(target))\n\n\(sections.joined(separator: "\n\n"))\n"))
    }
    let written = Set(write.map(\.0))

    var taken = Set(onDisk.filter { !isLegacy($0) })
    var rename: [(String, String)] = []
    for (path, _) in write where taken.contains(path) {
      let stemmed = JSText.replaceAll(path, #"\.scss\z"#, with: "")
      var n = 2
      while taken.contains("\(stemmed)-\(n).scss") || written.contains("\(stemmed)-\(n).scss") { n += 1 }
      rename.append((path, "\(stemmed)-\(n).scss"))
      taken.insert("\(stemmed)-\(n).scss")
    }
    let renamed = Dictionary(rename, uniquingKeysWith: { first, _ in first })

    var leading: [String] = []
    var after: [String: [String]] = [:]
    var anchor: String?
    for path in order {
      if isLegacy(path) {
        let name = stem(path)
        if name == "base" { anchor = "layout" } else { anchor = Self.order.first { parts[$0]!.contains(name) } ?? anchor }
        continue
      }
      let placed = renamed[path] ?? path
      if let anchor { after[anchor, default: []].append(placed) } else { leading.append(placed) }
    }
    var newOrder = leading
    var pending: [String] = []
    for target in Self.order {
      let path = "custom/\(target).scss"
      if written.contains(path) {
        newOrder.append(contentsOf: pending)
        newOrder.append(path)
        pending = []
      }
      pending.append(contentsOf: after[target] ?? [])
    }
    newOrder.append(contentsOf: pending)

    let remove = loaded.map { "custom/\($0).scss" }.filter { !written.contains($0) }
    return Plan(write: write, remove: remove, rename: rename, order: newOrder)
  }
}
