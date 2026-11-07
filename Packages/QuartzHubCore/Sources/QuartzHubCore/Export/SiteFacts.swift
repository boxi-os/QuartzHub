import Darwin
import Foundation

/// What the built site says about itself (`collect.ts`), read from its own files rather than
/// reconstructed: which pages exist, their titles, tags and outgoing links
/// (static/contentIndex.json, Quartz's ContentIndex plugin), and - with quartz-multilanguage - the
/// language of each page and the start page of each language (static/multilanguage.json, which
/// the plugin writes for its own switcher). Nothing here ports Quartz's or the plugin's logic.
public struct SiteFacts: Equatable, Sendable {
  public struct Page: Equatable, Sendable {
    public var title: String
    public var filePath: String?
    public var tags: [String]
    public var links: [String]
  }

  public struct Language: Equatable, Sendable {
    public var code: String
    public var home: String
    public var locale: String?
    public var label: String
  }

  /// Every content page that has an HTML file in the build, in contentIndex.json's key order
  /// (JavaScript's: integer-like keys first).
  public var slugs: [String]
  public var pages: [String: Page]
  /// quartz-multilanguage's languages; empty when the plugin is not in the build.
  public var languages: [Language]
  public var defaultLanguage: String
  public var langOf: [String: String]
  /// The order the plugin listed its pages in, for `json`.
  var langOrder: [String]

  public var json: JSONValue {
    func page(_ p: Page) -> JSONValue {
      var object = JSONObject([("title", .string(p.title))])
      if let filePath = p.filePath { object["filePath"] = .string(filePath) }
      object["tags"] = .array(p.tags.map(JSONValue.string))
      object["links"] = .array(p.links.map(JSONValue.string))
      return .object(object)
    }
    return .object(JSONObject([
      ("pages", .array(slugs.map { .array([.string($0), page(pages[$0]!)]) })),
      ("languages", .array(languages.map { l in
        var object = JSONObject([("code", .string(l.code)), ("home", .string(l.home))])
        if let locale = l.locale { object["locale"] = .string(locale) }
        object["label"] = .string(l.label)
        return .object(object)
      })),
      ("defaultLanguage", .string(defaultLanguage)),
      ("langOf", .array(langOrder.map { .array([.string($0), .string(langOf[$0]!)]) }))
    ]))
  }

  /// `readSiteFacts(root)`. „fehlt“ and „kaputt“ are two answers: a missing contentIndex.json is a
  /// plugin switched off, an unreadable one a build that went wrong.
  public static func read(root: String) throws(PublishFailure) -> SiteFacts {
    let indexPath = NodePath.join(root, "static", "contentIndex.json")
    let data: Data
    do {
      data = try Posix.read(indexPath)
    } catch let error as NodeFileError where error.code == ENOENT {
      throw PublishFailure(L10n.t("main.exportNoContentIndex"))
    } catch {
      throw PublishFailure(L10n.t("main.exportBrokenContentIndex", ["reason": Self.readError(error)]))
    }
    let index: JSONObject
    do {
      guard case .object(let object) = try JSJSON.parse(String(decoding: data, as: UTF8.self)) else {
        throw PublishFailure(L10n.t("main.exportBrokenContentIndex", ["reason": "not an object"]))
      }
      index = object
    } catch let error as JSJSON.ParseError {
      throw PublishFailure(L10n.t("main.exportBrokenContentIndex", ["reason": error.description]))
    } catch let failure as PublishFailure {
      throw failure
    } catch {
      throw PublishFailure(String(describing: error))
    }
    var facts = SiteFacts(slugs: [], pages: [:], languages: [], defaultLanguage: "", langOf: [:], langOrder: [])
    for slug in index.keys {
      // Quartz's tag listings are pages of the build too (`tags/<tag>`); a document has its own
      // register for tags, so they are not pages of a book.
      if slug == "tags" || JSText.startsWith(slug, "tags/") { continue }
      var info = stat()
      guard stat(NodePath.join(root, "\(slug).html"), &info) == 0 else { continue }
      let entry = index[slug]!.objectValue
      facts.slugs.append(slug)
      facts.pages[slug] = Page(title: entry?["title"]?.stringValue ?? slug, filePath: entry?["filePath"]?.stringValue,
                               tags: entry?["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                               links: entry?["links"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    }
    facts.readLanguages(NodePath.join(root, "static", "multilanguage.json"))
    return facts
  }

  /// `String(err)` of what `readFile` threw: a folder is a failed `read` without a path.
  static func readError(_ error: Error) -> String {
    guard var file = error as? NodeFileError else { return String(describing: error) }
    if file.code == EISDIR { file.path = nil }
    return file.description
  }

  /// No quartz-multilanguage in this build, or a file it did not write: one language. Read as
  /// QuartzControl's `try` read it: a `null` where an object or a language belongs is a TypeError
  /// there, and then nothing of the file counts.
  mutating func readLanguages(_ path: String) {
    guard let data = try? Posix.read(path), let ml = try? JSJSON.parse(String(decoding: data, as: UTF8.self)), ml != .null else { return }
    var languages: [Language] = []
    if case .array(let items)? = ml["languages"] {
      if items.contains(.null) { return }
      for l in items {
        guard let code = l["code"]?.stringValue else { continue }
        languages.append(Language(code: code, home: l["home"]?.stringValue ?? "index", locale: l["locale"]?.stringValue,
                                  label: l["native"]?.stringValue ?? l["label"]?.stringValue ?? code))
      }
    }
    self.languages = languages
    defaultLanguage = ml["defaultLanguage"]?.stringValue ?? languages.first?.code ?? ""
    // `Object.entries(ml.pages ?? {})`: an object's keys, an array's indices (a string's characters
    // have no `lang`).
    let entries: [(String, JSONValue)]
    switch ml["pages"] {
    case .object(let object)?: entries = object.keys.map { ($0, object[$0]!) }
    case .array(let items)?: entries = items.enumerated().map { (String($0.offset), $0.element) }
    default: entries = []
    }
    for (slug, p) in entries {
      guard let lang = p["lang"]?.stringValue else { continue }
      if langOf[slug] == nil { langOrder.append(slug) }
      langOf[slug] = lang
    }
  }

  /// `pagesInLanguage`: the pages of one language ("" = the default one, or every page without
  /// multilanguage). A page the plugin did not list counts as the default language.
  public func pages(inLanguage language: String) -> [String] {
    if languages.isEmpty { return slugs }
    let wanted = language.isEmpty ? defaultLanguage : language
    return slugs.filter { (langOf[$0] ?? defaultLanguage) == wanted }
  }

  /// `languageHome`: the start page of a language, quartz-multilanguage's `home`, else the index.
  public func languageHome(_ language: String) -> String {
    let code = language.isEmpty ? defaultLanguage : language
    return languages.first { $0.code == code }?.home ?? "index"
  }

  /// `effectiveRoot`: the book's own root, else the folder of the language's start page (in
  /// Example the English pages live under `en/`).
  public func effectiveRoot(_ root: String, language: String) -> String {
    if !root.isEmpty { return root }
    let home = languageHome(language)
    return JSText.endsWith(home, "/index") ? JSText.slice(home, 0, JSText.length(home) - 6) : ""
  }
}

/// The site's order as its navigation shows it (`readNavigationOrder`, the part after the page is
/// read): each address as a slug, once, only pages of the build. Without a navigation on the start
/// page, the Explorer's default order from contentIndex.json.
public struct NavigationOrder: Equatable, Sendable {
  /// "explorer", "quartz-navigations", "links" or "contentIndex".
  public var source: String
  public var slugs: [String]
  /// Whether the navigation had rendered by the time the page was read.
  public var complete: Bool

  public var json: JSONValue {
    .object(JSONObject([("source", .string(source)), ("slugs", .array(slugs.map(JSONValue.string))), ("complete", .bool(complete))]))
  }

  /// `source` and `hrefs` as the page script read them ("none" when there is no navigation).
  public init(source: String, hrefs: [String], complete: Bool, facts: SiteFacts) {
    if source == "none" {
      self.source = "contentIndex"
      slugs = ExportModel.explorerOrder(facts.slugs.map { ExportModel.ExplorerPage(slug: $0, title: facts.pages[$0]!.title, filePath: facts.pages[$0]!.filePath) })
      self.complete = true
      return
    }
    var seen = Set<String>()
    var slugs: [String] = []
    for href in hrefs {
      let slug = ExportModel.slug(fromPathname: WebURL(href).parts?.pathname ?? "")
      if seen.contains(slug) || facts.pages[slug] == nil { continue }
      seen.insert(slug)
      slugs.append(slug)
    }
    self.source = source
    self.slugs = slugs
    self.complete = complete
  }
}

/// The pages of the current build for the book editor (`readSitePages`, after the navigation is
/// read): in a root folder and a language, in the order the navigation shows them, then the pages
/// it does not show - exactly what an export would find.
public struct SitePages: Equatable, Sendable {
  public struct Entry: Equatable, Sendable {
    public var slug: String
    public var title: String
    public var depth: Int
    public var inNavigation: Bool
  }

  public var source: String
  public var languages: [(code: String, label: String)]
  public var defaultLanguage: String
  public var pages: [Entry]

  public static func == (lhs: SitePages, rhs: SitePages) -> Bool {
    lhs.source == rhs.source && lhs.languages.map(\.code) == rhs.languages.map(\.code) && lhs.languages.map(\.label) == rhs.languages.map(\.label)
      && lhs.defaultLanguage == rhs.defaultLanguage && lhs.pages == rhs.pages
  }

  public var json: JSONValue {
    .object(JSONObject([
      ("source", .string(source)),
      ("languages", .array(languages.map { .object(JSONObject([("code", .string($0.code)), ("label", .string($0.label))])) })),
      ("defaultLanguage", .string(defaultLanguage)),
      ("pages", .array(pages.map {
        .object(JSONObject([("slug", .string($0.slug)), ("title", .string($0.title)), ("depth", .number(Double($0.depth))), ("inNavigation", .bool($0.inNavigation))]))
      }))
    ]))
  }

  public init(facts: SiteFacts, navigation: NavigationOrder, root: String, language: String) {
    let eff = facts.effectiveRoot(root, language: language)
    let available = facts.pages(inLanguage: language).filter { ExportModel.insideRoot($0, eff) }
    let set = Set(available)
    let rootIndex = eff.isEmpty ? "index" : "\(eff)/index"
    var ordered = navigation.slugs.filter(set.contains)
    if set.contains(rootIndex) && !ordered.contains(rootIndex) { ordered.insert(rootIndex, at: 0) }
    let shown = Set(ordered)
    var rest = available.filter { !shown.contains($0) }
    JS.sort(&rest) { JS.collate($0, $1, locale: "", numeric: true, base: false) }
    func entry(_ slug: String, _ inNavigation: Bool) -> Entry {
      Entry(slug: slug, title: facts.pages[slug]?.title ?? slug, depth: ExportModel.pageDepth(slug, eff), inNavigation: inNavigation)
    }
    source = navigation.source
    languages = facts.languages.map { ($0.code, $0.label) }
    defaultLanguage = facts.defaultLanguage
    pages = ordered.map { entry($0, true) } + rest.map { entry($0, false) }
  }
}
