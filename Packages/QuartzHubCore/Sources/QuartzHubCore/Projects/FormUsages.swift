import Darwin
import Foundation

/// Which pages of a site embed which quartz-forms form, and every page's address, for the
/// Formulare tab's list and its questions before a form goes or gets another id (QuartzControl's
/// `shared/formUsages.ts` and `contentService.formUsages`, measured against both in
/// `scripts/form-usages-golden.mjs`).
///
/// The plugin finds a form in three places: a fenced code block in `codeBlockLang` (its first
/// non-empty line is the id), a placeholder `{{form:id}}` (or URL-encoded) outside code, and the
/// frontmatter key `frontmatterKey` (a string, a list, or `false`, which hides the layout form on
/// that page). This reads the text, not mdast, as QuartzControl did: it answers "where is it used",
/// not what the build does. Read only, over the files Quartz builds (the `content-files` helper);
/// the front matter is parsed by the yaml package QuartzControl used, all of it in one call.
public enum FormUsages {
  public enum Unbuilt: String, Equatable, Sendable { case draft, unpublished }

  public struct Page: Equatable, Sendable {
    /// Relative to content/, with "/".
    public var file: String
    public var slug: String
    public var title: String?
    public var forms: [String]
    public var hidesLayout: Bool
    /// A filter that is on keeps the page off the site (`draft: true` with remove-draft or, since
    /// Quartz 5.1, unless `configuration.drafts` publishes drafts; no `publish: true` with
    /// explicit-publish). It still names the form, so it counts for a rename;
    /// the preview does not go there.
    public var unbuilt: Unbuilt?
  }

  public struct Result: Equatable, Sendable {
    public var pages: [Page]
    /// Every Markdown page's slug, sorted: the pages a redirect may name.
    public var slugs: [String]
    public var listSource: ContentIndexPage.ListSource
    /// Files that could not be read, counted rather than passed over.
    public var unreadable: Int
    /// No content folder (or a link whose target is gone): nothing to scan.
    public var noContent: Bool
  }

  /// Why there is no answer. QuartzControl showed the sentences of "Startseite anlegen" here,
  /// which named a start page; these name the search.
  public enum Failure: Error, Equatable {
    case unpacking(String)
    case globbyBroken(String)
    case helper(String)

    public var message: String {
      switch self {
      case .unpacking(let name): L10n.t("formsEditor.scanGlobbyUnpacking", ["name": name])
      case .globbyBroken(let message): L10n.t("formsEditor.scanGlobbyBroken", ["message": message])
      case .helper(let reason): L10n.t("formsEditor.scanHelperBroken", ["reason": reason])
      }
    }
  }

  /// What one Markdown file says about forms.
  struct Use: Equatable {
    var forms: [String] = []
    var hidesLayout = false
    var title: String?
    var draft = false
    var publish = false
  }

  // MARK: Slugs

  /// Quartz's `slugifyFilePath` (@quartz-community/utils 1.0.1), for a content-relative path.
  public static func slug(_ filePath: String) -> String {
    var fp = JSText.replaceAll(JSText.replaceAll(filePath, #"\A/+"#, with: ""), #"/+\z"#, with: "")
    let ext = JSText.firstMatch(fp, #"\.[A-Za-z0-9]+\z"#)?.groups[0]
    let withoutExt = ext.map { JSText.slice(fp, 0, JSText.length(fp) - JSText.length($0)) } ?? fp
    let finalExt = ext == nil || ext == ".md" || ext == ".html" ? "" : ext!
    var slug = JSText.split(withoutExt, "/").map { segment in
      var s = JSText.replaceAll(segment, "[\(JSText.space)]", with: "-")
      s = JSText.replaceAll(s, "&", with: "-and-")
      s = JSText.replaceAll(s, "%", with: "-percent")
      s = JSText.replaceAll(s, #"\?"#, with: "")
      s = JSText.replaceAll(s, "#", with: "")
      s = JSText.replaceAll(s, #"[<>:"|*]"#, with: "")
      return (s as NSString).lowercased
    }.joined(separator: "/")
    slug = JSText.replaceAll(slug, #"/\z"#, with: "")
    if slug == "_index" || JSText.endsWith(slug, "/_index") { slug = JSText.replaceAll(slug, #"_index\z"#, with: "index") }
    var segments = JSText.split(slug, "/")
    if segments.count >= 2 && same(segments[segments.count - 1], segments[segments.count - 2]) {
      segments[segments.count - 1] = "index"
      slug = segments.joined(separator: "/")
    }
    fp = slug + finalExt
    return fp
  }

  /// The address of a slug below the site's root, as the preview takes it: `index` is the folder.
  public static func slugPath(_ slug: String) -> String {
    if slug == "index" { return "" }
    return JSText.endsWith(slug, "/index") ? JSText.slice(slug, 0, JSText.length(slug) - "index".count) : slug
  }

  // MARK: One page

  /// The front matter's YAML and where the body starts, as
  /// `/^---\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)\s*(?:\r?\n|$)/` finds it.
  static func frontmatter(_ text: String) -> (yaml: String, bodyStart: Int)? {
    guard let match = JSText.firstMatch(text, #"\A---\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)["# + JSText.space + #"]*(?:\r?\n|\z)"#) else { return nil }
    return (match.groups[1] ?? "", match.end)
  }

  /// `parse` turns a front matter's YAML into a value; nil where it cannot (QuartzControl's
  /// `parseYaml` in a try).
  static func use(_ text: String, codeBlockLang: String, frontmatterKey: String, parse: (String) -> JSONValue?) -> Use {
    var use = Use()
    func add(_ id: String?) {
      guard let id else { return }
      let clean = JS.trim(id)
      if !clean.isEmpty && !use.forms.contains(where: { same($0, clean) }) { use.forms.append(clean) }
    }
    var body = text
    if let fm = frontmatter(text) {
      body = JSText.slice(text, fm.bodyStart)
      if case .object(let record)? = parse(fm.yaml) {
        switch record[frontmatterKey] {
        case .bool(false)?: use.hidesLayout = true
        case .string(let value)?: add(value)
        case .array(let items)?: for case .string(let value) in items { add(value) }
        default: break
        }
        if case .string(let title)? = record["title"], !JS.trim(title).isEmpty { use.title = JS.trim(title) }
        use.draft = record["draft"] == .bool(true) || record["draft"] == .string("true")
        use.publish = record["publish"] == .bool(true) || record["publish"] == .string("true")
      }
    }

    // Fenced code: a block in the plugin's language names a form; any other block hides what is in
    // it from the placeholder search, as mdast does.
    var outside: [String] = []
    let lines = splitLines(body)
    var i = 0
    while i < lines.count {
      guard let open = fence(lines[i]) else {
        outside.append(lines[i])
        i += 1
        continue
      }
      let lang = InstanceClass.splitWhitespace(JS.trim(open.rest)).first ?? ""
      var inner: [String] = []
      var j = i + 1
      while j < lines.count {
        if let close = fence(lines[j]), close.marker.utf16.first == open.marker.utf16.first,
           close.marker.utf16.count >= open.marker.utf16.count, JS.trim(close.rest).isEmpty { break }
        inner.append(lines[j])
        j += 1
      }
      if same(lang, codeBlockLang) { add(inner.map(JS.trim).first { !$0.isEmpty }) }
      i = j + 1
    }
    // Inline code is code too.
    let prose = JSText.replaceAll(outside.joined(separator: "\n"), #"(`+)[\s\S]*?\1"#, with: "")
    // `/…/gi` without the u flag folds only ASCII; ICU's (?i) would also take the Kelvin sign
    // for a k, so the cases are spelled out.
    let id = "([A-Za-z0-9-]+)"
    let pattern = #"\{\{["# + JSText.space + #"]*[Ff][Oo][Rr][Mm]:"# + id + #"["# + JSText.space + #"]*\}\}|%7[Bb]%7[Bb][Ff][Oo][Rr][Mm]:"# + id + "%7[Dd]%7[Dd]"
    for match in JSText.matches(prose, pattern) { add(match.groups[1] ?? match.groups[2]) }
    return use
  }

  /// JavaScript's `===`: Swift's `==` takes "ü" and "u\u{308}" for one string.
  static func same(_ a: String, _ b: String) -> Bool { a.utf16.elementsEqual(b.utf16) }

  /// `text.split(/\r?\n/)`, in UTF-16: a lone \r stays in its line.
  static func splitLines(_ text: String) -> [String] {
    let units = Array(text.utf16)
    var lines: [String] = []
    var start = 0
    var index = 0
    while index < units.count {
      if units[index] == 0x0A {
        let end = index > start && units[index - 1] == 0x0D ? index - 1 : index
        lines.append(String(decoding: units[start..<end], as: UTF16.self))
        start = index + 1
      }
      index += 1
    }
    lines.append(String(decoding: units[start...], as: UTF16.self))
    return lines
  }

  /// `/^ {0,3}(`{3,}|~{3,})(.*)$/` on one line; `.` stops at \r, U+2028 and U+2029 (ICU's would
  /// also stop at U+0085, \v and \f).
  static func fence(_ line: String) -> (marker: String, rest: String)? {
    guard let match = JSText.firstMatch(line, #"\A {0,3}(`{3,}|~{3,})([^\n\r\x{2028}\x{2029}]*)\z"#) else { return nil }
    return (match.groups[1] ?? "", match.groups[2] ?? "")
  }

  // MARK: The site

  public static func scan(project: String, codeBlockLang: String, frontmatterKey: String,
                          runtime: RuntimeLocation = .current) async throws(Failure) -> Result {
    let empty = Result(pages: [], slugs: [], listSource: .quartz, unreadable: 0, noContent: true)
    guard let status = try? ContentFolder.status(project: project), status.exists,
          !(status.isSymlink && status.targetExists != true) else { return empty }
    var patterns: [String] = []
    // The two filters of Quartz that leave a page out by its frontmatter, when they are on.
    var removeDraft = false
    var explicitPublish = false
    // An unreadable config still leaves hidden entries out.
    if let config = try? await ConfigFile.read(project: project, runtime: runtime) {
      if case .array(let items)? = config.configuration["ignorePatterns"] { patterns = items.compactMap(\.stringValue) }
      let on = { (name: String) in config.plugins.contains { $0.enabled && $0.name == name } }
      // Since Quartz 5.1 drafts are left out by Quartz itself unless `configuration.drafts` says
      // otherwise; a remove-draft entry still counts, as Quartz reads it (`BuiltinProcessing`).
      removeDraft = QuartzFeatures.read(project: project).builtins
        ? BuiltinProcessing.plan(configuration: config.configuration, plugins: config.plugins).removesDrafts
        : on("remove-draft")
      explicitPublish = on("explicit-publish")
    }
    let listed: (files: [String], source: ContentIndexPage.ListSource)
    do {
      listed = try await ContentIndexPage.inputFiles(project: project, cwd: ContentFolder.path(project: project), patterns: patterns, runtime: runtime)
    } catch {
      switch error {
      case .unpacking(let name): throw .unpacking(name)
      case .globbyBroken(let message): throw .globbyBroken(message)
      default: throw .helper(error.message)
      }
    }
    let markdown = listed.files.filter { $0.hasSuffix(".md") }
    guard let dir = ContentFolder.realPath(ContentFolder.path(project: project)) else { return empty }

    var texts: [(file: String, text: String)] = []
    var unreadable = 0
    for file in markdown {
      guard let data = try? Posix.read("\(dir)/\(file)") else {
        unreadable += 1
        continue
      }
      texts.append((file, String(decoding: data, as: UTF8.self)))
    }

    // Every front matter in one call, each distinct text once.
    var yamls: [String] = []
    var seen = Set<[UInt16]>()
    for (_, text) in texts {
      if let fm = frontmatter(text), seen.insert(Array(fm.yaml.utf16)).inserted { yamls.append(fm.yaml) }
    }
    var parsed: [[UInt16]: JSONValue] = [:]
    if !yamls.isEmpty {
      let request = JSONObject([("op", .string("parse")), ("texts", .array(yamls.map(JSONValue.string)))])
      let answer: JSONObject
      do {
        answer = try await Helper.call("content-files", request, runtime: runtime, timeout: .seconds(60))
      } catch {
        throw .helper(error.description)
      }
      guard case .array(let values)? = answer["values"], values.count == yamls.count else { throw .helper("no values") }
      for (yaml, value) in zip(yamls, values) { parsed[Array(yaml.utf16)] = value }
    }

    var pages: [Page] = []
    for (file, text) in texts {
      let found = use(text, codeBlockLang: codeBlockLang.isEmpty ? "quartz-form" : codeBlockLang,
                      frontmatterKey: frontmatterKey.isEmpty ? "form" : frontmatterKey) { parsed[Array($0.utf16)] }
      if found.forms.isEmpty && !found.hidesLayout { continue }
      let unbuilt: Unbuilt? = removeDraft && found.draft ? .draft : explicitPublish && !found.publish ? .unpublished : nil
      pages.append(Page(file: file, slug: slug(file), title: found.title, forms: found.forms, hidesLayout: found.hidesLayout, unbuilt: unbuilt))
    }
    // `localeCompare(b, undefined, { numeric: true, sensitivity: 'base' })`.
    let order = { (a: String, b: String) in JS.collate(a, b, locale: "", numeric: true, base: true) }
    JS.sort(&pages) { order($0.file, $1.file) }
    var slugs: [String] = []
    var known = Set<[UInt16]>()
    for file in markdown {
      let s = slug(file)
      if known.insert(Array(s.utf16)).inserted { slugs.append(s) }
    }
    JS.sort(&slugs, by: order)
    return Result(pages: pages, slugs: slugs, listSource: listed.source, unreadable: unreadable, noContent: false)
  }
}
