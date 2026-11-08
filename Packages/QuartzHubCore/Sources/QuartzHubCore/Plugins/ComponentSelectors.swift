import Foundation

/// Which selector finds a component on the built page (QuartzControl's
/// `src/data/componentSelectors.ts`, measured against it in SitePreviewTests).
///
/// A table rather than a rule: most components build their class at render time, and for a third
/// of them the plugin's name is no class the site renders (tag-list renders `ul.tags`, footer a
/// bare `<footer>`). Measured by QuartzControl on 2026-09-24 on a real build, 349 pages.
public enum ComponentSelectors {
  static let root: [String: String] = [
    "table-of-contents": ".toc",
    "stacked-pages": ".stacked-pages-container",
    "explorer": ".explorer",
    "graph": ".graph",
    "search": ".search",
    "backlinks": ".backlinks",
    "article-title": ".article-title",
    "content-meta": ".content-meta",
    "tag-list": ".tags",
    "page-title": ".page-title",
    "darkmode": ".darkmode",
    "reader-mode": ".readermode",
    "breadcrumbs": ".breadcrumb-container",
    "comments": ".giscus",
    "footer": "footer",
    "spacer": ".spacer",
    "note-properties": ".note-properties",
    "recent-notes": ".recent-notes",
    "quartz-layout-box": ".layout-box",
    "quartz-multilanguage": ".multilanguage-switcher",
    "quartz-navigations": ".quartz-nav"
  ]

  /// The plugins whose `className` lands on the root element next to the class above.
  static let instanceClass: Set<String> = ["quartz-layout-box", "quartz-navigations"]

  public struct Entry: Sendable, Equatable {
    public var selector: String
    /// How many entries of the config the selector finds; above one, the entry cannot be told apart.
    public var matches: Int
    /// Whether the entry has a class of its own; false: the selector is the plugin's root.
    public var ownClass: Bool
  }

  /// `entrySelector`: the selector for one entry, for the preview's marks. nil for a plugin whose
  /// root has not been measured: marking the guess would mark nothing and look like "not on this
  /// page". A copy carries the original's class in front of its own, so the copies' own classes
  /// are excluded with `:not()`.
  public static func entry(_ entry: PluginEntry, siblings: [PluginEntry]) -> Entry? {
    guard let root = root[entry.name] else { return nil }
    let own = instanceClass.contains(entry.name) ? InstanceClass.own(entry) : nil
    let same = siblings.filter { $0.name == entry.name }
    guard let own else { return Entry(selector: root, matches: max(1, same.count), ownClass: false) }
    let excluded = copyClasses(own, same)
    let hits = same.filter { e in
      let tokens = InstanceClass.tokens(e)
      return tokens.contains(own) && !excluded.contains { tokens.contains($0) }
    }
    return Entry(selector: "\(root).\(own)\(notClasses(excluded))", matches: max(1, hits.count), ownClass: true)
  }

  /// The own classes of the entries that carry `own` without it being theirs, in first-seen order.
  static func copyClasses(_ own: String, _ same: [PluginEntry]) -> [String] {
    var seen: [String] = []
    for entry in same where InstanceClass.tokens(entry).contains(own) {
      if let cls = InstanceClass.own(entry), cls != own, !seen.contains(cls) { seen.append(cls) }
    }
    return seen
  }

  static func notClasses(_ classes: [String]) -> String {
    classes.map { ":not(.\($0))" }.joined()
  }
}
