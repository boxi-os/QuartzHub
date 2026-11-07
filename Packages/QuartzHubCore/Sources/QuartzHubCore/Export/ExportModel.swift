import Foundation

/// One place in the resolved document (`DocItem`): a page with its heading level, or an
/// interposed heading.
public enum DocItem: Equatable, Sendable {
  case page(slug: String, level: Int)
  case heading(text: String)

  public var json: JSONValue {
    switch self {
    case .page(let slug, let level):
      .object(JSONObject([("kind", .string("page")), ("slug", .string(slug)), ("level", .number(Double(level)))]))
    case .heading(let text):
      .object(JSONObject([("kind", .string("heading")), ("text", .string(text)), ("level", .number(1))]))
    }
  }

  public var slug: String? {
    if case .page(let slug, _) = self { return slug }
    return nil
  }
}

/// The pure half of the document export (`shared/exportModel.ts`): how a page of the built site is
/// named, where it sits in the document, and what the book's order resolves to. Two of these run
/// in the export window as well (`slugFromPathname`, `anchorFor`, handed over as source in 9b).
public enum ExportModel {
  /// The slug the register stands under in the document: a name no Quartz page can have.
  public static let registerSlug = "__quartzcontrol/register"

  /// `slugFromPathname`: a URL path of the built site as Quartz's slug - no leading slash, no
  /// `.html`, a folder as its `index`. Escapes are decoded; a malformed one stays as it is.
  public static func slug(fromPathname pathname: String) -> String {
    var p = (try? JSURI.decodeComponent(pathname)) ?? pathname
    p = JSText.replaceAll(p, "^/+", with: "")
    if p.isEmpty || JSText.endsWith(p, "/") { p += "index" }
    if JSText.endsWith(p, ".html") { p = JSText.slice(p, 0, JSText.length(p) - 5) }
    return p
  }

  /// `anchorFor`: the id a page (or a heading on it) gets in the combined document. Injective:
  /// every UTF-16 unit outside [A-Za-z0-9-], the underscore included, becomes `_<hex>_`.
  public static func anchor(_ slug: String, _ id: String? = nil) -> String {
    func esc(_ text: String) -> String {
      var out = ""
      for unit in text.utf16 {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D: out.unicodeScalars.append(Unicode.Scalar(unit)!)
        default: out += "_" + String(unit, radix: 16) + "_"
        }
      }
      return out
    }
    return "p-" + esc(slug) + ((id?.isEmpty ?? true) ? "" : "--" + esc(id!))
  }

  /// `folderOf`: the folder a slug sits in, "" for the top level.
  static func folder(of slug: String) -> String {
    var parts = JSText.split(slug, "/")
    parts.removeLast()
    return parts.joined(separator: "/")
  }

  /// `insideRoot`: whether a slug lies in the book's root folder ("" = the whole site).
  public static func insideRoot(_ slug: String, _ root: String) -> Bool {
    root.isEmpty || slug == "\(root)/index" || JSText.startsWith(slug, "\(root)/")
  }

  /// `pageDepth`: the root's own index is 0, a page or a subfolder's index directly in it 1, and
  /// so on.
  public static func pageDepth(_ slug: String, _ root: String) -> Int {
    let rel = root.isEmpty ? slug : JSText.slice(slug, JSText.length(root) + 1)
    var parts = JSText.split(rel, "/")
    if parts.last == "index" { parts.removeLast() }
    return parts.count
  }

  public static func isFolderIndex(_ slug: String) -> Bool { slug == "index" || JSText.endsWith(slug, "/index") }

  /// One page as `explorerOrder` reads it from contentIndex.json.
  public struct ExplorerPage: Sendable {
    public var slug: String
    public var title: String
    public var filePath: String?
    public init(slug: String, title: String, filePath: String? = nil) {
      self.slug = slug
      self.title = title
      self.filePath = filePath
    }
  }

  /// `explorerOrder`: the order Quartz's Explorer shows with its default options, recomputed from
  /// `@quartz-community/explorer` as built - folders before pages, each by name (numeric, blind to
  /// case and accents), depth first, a folder's own index page before its contents. A folder's
  /// name is its index page's title, else its name on disk, else its slug segment.
  public static func explorerOrder(_ pages: [ExplorerPage]) -> [String] {
    final class Node {
      let segment: String
      var folder: Bool
      var page: ExplorerPage?
      var hint: String?
      var children: [Node] = []
      init(segment: String, folder: Bool, page: ExplorerPage? = nil) {
        self.segment = segment
        self.folder = folder
        self.page = page
      }
    }
    let root = Node(segment: "", folder: true)
    for p in pages {
      let parts = JSText.split(p.slug, "/")
      let fileParts = JSText.split(p.filePath ?? "", "/")
      var node = root
      for (i, segment) in parts.enumerated() {
        let rest = parts.count - i
        if rest == 1 {
          if segment == "index" {
            if node.page == nil { node.page = p }
          } else {
            node.children.append(Node(segment: segment, folder: false, page: p))
          }
          break
        }
        // Like the Explorer: any child of that name, a page of the same name included, becomes the folder.
        let child = node.children.first { $0.segment == segment } ?? {
          let made = Node(segment: segment, folder: false)
          node.children.append(made)
          return made
        }()
        child.folder = true
        let at = fileParts.count - rest
        child.hint = at >= 0 && at < fileParts.count && !fileParts[at].isEmpty ? fileParts[at] : nil
        node = child
      }
    }
    func name(_ n: Node) -> String {
      if let page = n.page, page.title != "index", !page.title.isEmpty { return page.title }
      if let hint = n.hint { return hint }
      return n.segment
    }
    var out: [String] = []
    func walk(_ n: Node) {
      if let page = n.page { out.append(page.slug) }
      var sorted = n.children
      JS.sort(&sorted) { a, b in
        a.folder == b.folder ? JS.collate(name(a), name(b), locale: "", numeric: true, base: true) : (a.folder ? -1 : 1)
      }
      for child in sorted { walk(child) }
    }
    walk(root)
    return out
  }

  public struct ResolvedOrder: Equatable, Sendable {
    public var items: [DocItem]
    /// Pages the book's own order names that the build no longer has.
    public var missing: [String]
    /// Pages of the build that are new since the order was written; appended at the end.
    public var appended: [String]

    public var json: JSONValue {
      .object(JSONObject([
        ("items", .array(items.map(\.json))), ("missing", .array(missing.map(JSONValue.string))), ("appended", .array(appended.map(JSONValue.string)))
      ]))
    }
  }

  /// `resolveOrder`: the book's order against what the site has now. Following the navigation,
  /// the book is the navigation within its root minus `excluded`; with an own order, a page that
  /// is gone is named in `missing` and a page that is new is appended and named in `appended`.
  /// The root's start page comes first even when the navigation does not show it.
  public static func resolveOrder(order: [BookEntry]?, excluded: [String], root: String, navigation: [String], available: Set<String>) -> ResolvedOrder {
    let excludedSet = Set(excluded)
    func usable(_ slug: String) -> Bool { available.contains(slug) && insideRoot(slug, root) && !excludedSet.contains(slug) }
    let rootIndex = root.isEmpty ? "index" : "\(root)/index"
    let navigation = navigation.contains(rootIndex) ? navigation : [rootIndex] + navigation
    var entries: [BookEntry] = []
    var missing: [String] = []
    var appended: [String] = []
    if let order {
      var listed = Set<String>()
      for entry in order {
        guard case .page(let slug) = entry else {
          entries.append(entry)
          continue
        }
        listed.insert(slug)
        if !available.contains(slug) { missing.append(slug) } else if usable(slug) { entries.append(entry) }
      }
      for slug in navigation where !listed.contains(slug) && usable(slug) {
        entries.append(.page(slug))
        appended.append(slug)
      }
    } else {
      for slug in navigation where usable(slug) { entries.append(.page(slug)) }
    }
    var seen = Set<String>()
    var items: [DocItem] = []
    var inSection = false
    for entry in entries {
      switch entry {
      case .heading(let text):
        items.append(.heading(text: text))
        inSection = true
      case .page(let slug):
        if seen.contains(slug) { continue }
        seen.insert(slug)
        items.append(.page(slug: slug, level: min(6, max(1, pageDepth(slug, root)) + (inSection ? 1 : 0))))
      }
    }
    return ResolvedOrder(items: items, missing: missing, appended: appended)
  }

  /// `outsideUrl`: where a link to a page outside the book goes. With a baseUrl, to that page on
  /// the published site; without one there is no address, and the link becomes text.
  public static func outsideURL(baseUrl: String?, slug: String, hash: String) -> String? {
    guard let baseUrl, !baseUrl.isEmpty else { return nil }
    let host = JSText.replaceAll(JSText.replaceAll(baseUrl, "^https?://", with: ""), "/+$", with: "")
    if host.isEmpty { return nil }
    let path = slug == "index" ? "" : JSText.endsWith(slug, "/index") ? JSText.slice(slug, 0, JSText.length(slug) - 5) : slug
    return "https://\(host)/" + JSText.split(path, "/").map(JSURI.encodeComponent).joined(separator: "/") + hash
  }

  /// `linkSlug`: a link as contentIndex.json stores it, as a slug; a folder link is its index.
  static func linkSlug(_ link: String) -> String {
    let s = JSText.split(JSText.replaceAll(link, "^/+", with: ""), "#")[0]
    return s.isEmpty || JSText.endsWith(s, "/") ? "\(s)index" : s
  }

  /// `backlinksInBook`: which pages of the book link to each page of the book, in book order, from
  /// the links Quartz recorded (contentIndex.json), restricted to the book.
  public static func backlinksInBook(_ slugs: [String], linksOf: (String) -> [String]) -> [(slug: String, from: [String])] {
    let inBook = Set(slugs)
    var order: [String] = []
    var found: [String: [String]] = [:]
    for slug in slugs where found[slug] == nil {
      order.append(slug)
      found[slug] = []
    }
    for from in slugs {
      var targets: [String] = []
      for target in linksOf(from).map(linkSlug) where !targets.contains(target) { targets.append(target) }
      for to in targets where to != from && inBook.contains(to) { found[to]!.append(from) }
    }
    return order.map { ($0, found[$0]!) }
  }

  /// `tagRegister`: the tags of the book's pages, each with its pages in book order, sorted for
  /// `locale` (numeric, blind to case and accents).
  public static func tagRegister(_ slugs: [String], tagsOf: (String) -> [String], locale: String) -> [(tag: String, pages: [String])] {
    var order: [String] = []
    var byTag: [String: [String]] = [:]
    for slug in slugs {
      var seen = Set<String>()
      for tag in tagsOf(slug) where !seen.contains(tag) {
        seen.insert(tag)
        if byTag[tag] == nil { order.append(tag) }
        byTag[tag, default: []].append(slug)
      }
    }
    var register = order.map { (tag: $0, pages: byTag[$0]!) }
    JS.sort(&register) { JS.collate($0.tag, $1.tag, locale: locale, numeric: true, base: true) }
    return register
  }
}
