import Foundation

/// Where the handbook explains a place of the app (QuartzControl's `data/handbookPages.ts` and
/// `openHandbook` in `menu.ts`). The handbook translates its chapters and their paths with them,
/// `4-einrichtung/09-formulare` is `en/4-setup/09-forms`, so a place has a page per language and the
/// app's language picks one. One table instead of two paths at every call site: whoever moves a
/// chapter changes one line, and `qh-check handbook` says which page no longer exists.
///
/// A place is a page of the project window by its `ProjectPage` raw value, on a tabbed page
/// "page/tab" with the tab's raw value, or one of the places outside it ("projects", "settings").
/// A tab without a line of its own takes its page's.
public enum Handbook {
  /// The online handbook (docs/plan.md, Phase 5, Handbuch 8). Until it is published every address
  /// answers 404; the app does not ask first, as QuartzControl did not.
  public static let base = "https://boxi-os.github.io/QuartzHub"

  public struct Page: Sendable, Equatable {
    public let de: String
    public let en: String
  }

  /// The start page, "" and "en/" (the site's index pages).
  public static let start = Page(de: "", en: "en/")

  public static let pages: [String: Page] = [
    "projects": Page(de: "2-projekte/01-das-fenster-projekte", en: "en/2-projects/01-the-projects-window"),
    "settings": Page(de: "2-projekte/05-die-einstellungen", en: "en/2-projects/05-the-settings"),
    "overview": Page(de: "3-uebersicht/01-die-uebersicht", en: "en/3-overview/01-the-overview"),
    "config": Page(de: "4-einrichtung/01-website", en: "en/4-setup/01-website"),
    "config/localization": Page(de: "4-einrichtung/04-uebersetzungen", en: "en/4-setup/04-translations"),
    "plugins": Page(de: "4-einrichtung/05-plugins", en: "en/4-setup/05-plugins"),
    "plugins/navigations": Page(de: "4-einrichtung/06-navigationen", en: "en/4-setup/06-navigations"),
    "plugins/extras": Page(de: "4-einrichtung/07-zusaetzliche-inhalte", en: "en/4-setup/07-additional-content"),
    "plugins/languages": Page(de: "4-einrichtung/08-mehrsprachigkeit", en: "en/4-setup/08-languages"),
    "plugins/forms": Page(de: "4-einrichtung/09-formulare", en: "en/4-setup/09-forms"),
    "plugins/marketplace": Page(de: "4-einrichtung/10-marktplatz", en: "en/4-setup/10-marketplace"),
    "layout": Page(de: "5-gestaltung/02-layout-uebersicht", en: "en/5-design/02-layout-overview"),
    "layout/global": Page(de: "5-gestaltung/03-layout-komponenten", en: "en/5-design/03-layout-components"),
    "layout/frames": Page(de: "5-gestaltung/04-layout-frames", en: "en/5-design/04-layout-frames"),
    "styles": Page(de: "5-gestaltung/05-stile-basis", en: "en/5-design/05-styles-basics"),
    "styles/theme": Page(de: "5-gestaltung/06-community-themes", en: "en/5-design/06-community-themes"),
    "styles/variables": Page(de: "5-gestaltung/07-variablen", en: "en/5-design/07-variables"),
    "styles/customCss": Page(de: "5-gestaltung/08-eigenes-css", en: "en/5-design/08-custom-css"),
    "templates": Page(de: "5-gestaltung/09-vorlagen", en: "en/5-design/09-templates"),
    "server": Page(de: "6-veroeffentlichung/01-die-vorschau", en: "en/6-publishing/01-the-preview"),
    "sync": Page(de: "6-veroeffentlichung/05-git-sync", en: "en/6-publishing/05-git-sync"),
    "documents": Page(de: "6-veroeffentlichung/06-dokumente", en: "en/6-publishing/06-documents"),
    "publish": Page(de: "6-veroeffentlichung/07-zugaenge-und-ziele", en: "en/6-publishing/07-connections-and-targets"),
    "updates": Page(de: "7-wartung/01-updates", en: "en/7-maintenance/01-updates"),
    "backups": Page(de: "7-wartung/02-snapshots", en: "en/7-maintenance/02-snapshots"),
  ]

  /// The page for a place: its own line, else its page's (the part before "/"), else the start.
  public static func page(for place: String?) -> Page {
    guard let place else { return start }
    if let page = pages[place] { return page }
    if let slash = place.firstIndex(of: "/"), let page = pages[String(place[..<slash])] { return page }
    return start
  }

  /// The address of a place in a language; English for "en…", German otherwise.
  public static func url(for place: String?, language: String) -> URL { // not a file path
    let page = page(for: place)
    let path = language.hasPrefix("en") ? page.en : page.de
    // The paths are ASCII letters, digits, "-" and "/"; nothing to encode.
    return URL(string: path.isEmpty ? "\(base)/" : "\(base)/\(path)")!
  }

  /// The place key for a page and, on a tabbed page, its tab.
  public static func place(page: String, tab: String?) -> String {
    guard let tab, !tab.isEmpty else { return page }
    return "\(page)/\(tab)"
  }

  /// Every page the table names, as a file of the vault ("index.md" for the start pages).
  public static var files: [String] {
    let all = [start] + pages.values.sorted { $0.de < $1.de }
    return all.flatMap { [$0.de, $0.en] }.map { $0.isEmpty || $0.hasSuffix("/") ? "\($0)index.md" : "\($0).md" }
  }
}
