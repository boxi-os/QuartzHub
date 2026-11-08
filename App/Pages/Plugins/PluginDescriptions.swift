import QuartzHubCore

// Generated from QuartzControl's KNOWN_PLUGIN_DESCRIPTION_KEYS (routes/Plugins/Installed.tsx): one
// literal key per name, so qh-check i18n can read them. Short descriptions of the plugins that
// ship with Quartz, compiled from its docs; a plugin not listed shows none rather than a guess.
enum PluginDescriptions {
  static func text(_ name: String) -> String? {
    switch name {
    case "created-modified-date": L10n.t("pluginDescriptions.created-modified-date")
    case "syntax-highlighting": L10n.t("pluginDescriptions.syntax-highlighting")
    case "obsidian-flavored-markdown": L10n.t("pluginDescriptions.obsidian-flavored-markdown")
    case "github-flavored-markdown": L10n.t("pluginDescriptions.github-flavored-markdown")
    case "table-of-contents": L10n.t("pluginDescriptions.table-of-contents")
    case "crawl-links": L10n.t("pluginDescriptions.crawl-links")
    case "description": L10n.t("pluginDescriptions.description")
    case "latex": L10n.t("pluginDescriptions.latex")
    case "citations": L10n.t("pluginDescriptions.citations")
    case "hard-line-breaks": L10n.t("pluginDescriptions.hard-line-breaks")
    case "ox-hugo": L10n.t("pluginDescriptions.ox-hugo")
    case "roam": L10n.t("pluginDescriptions.roam")
    case "quartz-fonts": L10n.t("pluginDescriptions.quartz-fonts")
    case "core": L10n.t("pluginDescriptions.core")
    case "remove-draft": L10n.t("pluginDescriptions.remove-draft")
    case "explicit-publish": L10n.t("pluginDescriptions.explicit-publish")
    case "unlisted-pages": L10n.t("pluginDescriptions.unlisted-pages")
    case "encrypted-pages": L10n.t("pluginDescriptions.encrypted-pages")
    case "stacked-pages": L10n.t("pluginDescriptions.stacked-pages")
    case "alias-redirects": L10n.t("pluginDescriptions.alias-redirects")
    case "content-index": L10n.t("pluginDescriptions.content-index")
    case "favicon": L10n.t("pluginDescriptions.favicon")
    case "og-image": L10n.t("pluginDescriptions.og-image")
    case "cname": L10n.t("pluginDescriptions.cname")
    case "canvas-page": L10n.t("pluginDescriptions.canvas-page")
    case "content-page": L10n.t("pluginDescriptions.content-page")
    case "folder-page": L10n.t("pluginDescriptions.folder-page")
    case "tag-page": L10n.t("pluginDescriptions.tag-page")
    case "bases-page": L10n.t("pluginDescriptions.bases-page")
    case "explorer": L10n.t("pluginDescriptions.explorer")
    case "graph": L10n.t("pluginDescriptions.graph")
    case "search": L10n.t("pluginDescriptions.search")
    case "backlinks": L10n.t("pluginDescriptions.backlinks")
    case "article-title": L10n.t("pluginDescriptions.article-title")
    case "content-meta": L10n.t("pluginDescriptions.content-meta")
    case "tag-list": L10n.t("pluginDescriptions.tag-list")
    case "page-title": L10n.t("pluginDescriptions.page-title")
    case "darkmode": L10n.t("pluginDescriptions.darkmode")
    case "reader-mode": L10n.t("pluginDescriptions.reader-mode")
    case "breadcrumbs": L10n.t("pluginDescriptions.breadcrumbs")
    case "comments": L10n.t("pluginDescriptions.comments")
    case "footer": L10n.t("pluginDescriptions.footer")
    case "recent-notes": L10n.t("pluginDescriptions.recent-notes")
    case "spacer": L10n.t("pluginDescriptions.spacer")
    case "note-properties": L10n.t("pluginDescriptions.note-properties")
    case "assets": L10n.t("pluginDescriptions.assets")
    case "static": L10n.t("pluginDescriptions.static")
    case "component-resources": L10n.t("pluginDescriptions.component-resources")
    default: nil
    }
  }
}
