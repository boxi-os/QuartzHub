import Darwin
import Foundation

/// One entry of a book's own order (`BookEntry`): a page of the built site by its slug, or an
/// interposed heading that is not a page (the handbook's „Anhang“).
public enum BookEntry: Equatable, Sendable {
  case page(String)
  case heading(String)

  public var json: JSONValue {
    switch self {
    case .page(let slug): .object(JSONObject([("slug", .string(slug))]))
    case .heading(let text): .object(JSONObject([("heading", .string(text))]))
    }
  }
}

/// A book as its file holds it after `normalizeBook` (QuartzControl's `BookDefinition`): a view on
/// the object, so a key a newer version wrote survives a save by this one.
public struct Book: JSONView {
  public var object: JSONObject
  public init(object: JSONObject) { self.object = object }

  public var id: String { string("id") ?? "" }
  public var title: String { string("title") ?? "" }
  public var subtitle: String { string("subtitle") ?? "" }
  public var author: String { string("author") ?? "" }
  public var language: String { string("language") ?? "" }
  public var root: String { string("root") ?? "" }
  /// nil follows the site's navigation as it is built.
  public var order: [BookEntry]? {
    object["order"]?.arrayValue?.compactMap { entry in
      if let slug = entry["slug"]?.stringValue { return .page(slug) }
      return entry["heading"]?.stringValue.map(BookEntry.heading)
    }
  }
  public var excluded: [String] { strings("excluded") ?? [] }
  public var coverImage: String { string("coverImage") ?? "" }
  public var toc: Bool { isTrue("toc") }
  public var tagIndex: Bool { isTrue("tagIndex") }
  public var backlinks: Bool { isTrue("backlinks") }
  /// "site" or "text".
  public var outsideLinks: String { string("outsideLinks") ?? "site" }
  /// "A4", "A5" or "Letter".
  public var pageSize: String { object["pdf"]?["pageSize"]?.stringValue ?? "A4" }
  public var landscape: Bool { object["pdf"]?["landscape"] == .bool(true) }
}

/// The book file (`shared/bookDefinition.ts`): quartz-books/<id>.json in the project root,
/// versioned with it - not in .quartz-gui/, which is gitignored, so a book travels with Git-Sync
/// and a copy of the project. The file is an exchange format a person or a merge may edit, so
/// reading is a normaliser, not a cast: a missing or wrongly typed key gets its default, an unknown
/// key is kept, and only something that is not an object is refused.
public enum BookFile {
  public static let directory = "quartz-books"
  static let version = 1.0
  /// Limits that keep a hand-edited or hostile file from making the editor or the export unusable.
  static let maxEntries = 10_000
  static let maxText = 500
  static let maxSlug = 1024
  static let pageSizes = ["A4", "A5", "Letter"]

  /// `BOOK_ID`: the file name, lowercase ASCII, digits and dashes, a letter or digit first.
  public static func isID(_ id: String) -> Bool { JSText.test(id, #"\A[a-z0-9][a-z0-9-]{0,62}\z"#) }

  /// `emptyBook(title)`, the form a new book starts from.
  public static func empty(title: String = "") -> JSONObject {
    JSONObject([
      ("title", .string(title)), ("subtitle", .string("")), ("author", .string("")), ("language", .string("")), ("root", .string("")),
      ("order", .null), ("excluded", .array([])), ("coverImage", .string("")), ("toc", .bool(true)), ("tagIndex", .bool(false)),
      ("backlinks", .bool(false)), ("outsideLinks", .string("site")),
      ("pdf", .object(JSONObject([("pageSize", .string("A4")), ("landscape", .bool(false))])))
    ])
  }

  static func text(_ value: JSONValue?) -> String { value?.stringValue.map { JSText.slice($0, 0, maxText) } ?? "" }

  static func slug(_ value: JSONValue?) -> String? {
    guard let text = value?.stringValue, JSText.length(text) > 0, JSText.length(text) <= maxSlug else { return nil }
    return text
  }

  /// `typeof value === 'object'`: arrays count, as in JavaScript.
  static func entry(_ value: JSONValue) -> BookEntry? {
    let fields: JSONObject
    switch value {
    case .object(let object): fields = object
    case .array: return nil // no `slug` or `heading` on an array
    default: return nil
    }
    if let slug = slug(fields["slug"]) { return .page(slug) }
    if let heading = fields["heading"]?.stringValue, !JS.trim(heading).isEmpty { return .heading(JSText.slice(heading, 0, maxText)) }
    return nil
  }

  /// `normalizeBook(id, raw)`: every field read on its own, so one broken value costs that value,
  /// not the book. A duplicate slug in `order` keeps its first position.
  public static func normalize(id: String, _ raw: JSONValue) -> Book? {
    guard case .object(let r) = raw else { return nil }
    var order: JSONValue = .null
    if let items = r["order"]?.arrayValue {
      var seen = Set<String>()
      var entries: [JSONValue] = []
      for item in items.prefix(maxEntries) {
        guard let e = entry(item) else { continue }
        if case .page(let slug) = e {
          if seen.contains(slug) { continue }
          seen.insert(slug)
        }
        entries.append(e.json)
      }
      order = .array(entries)
    }
    var excluded: [JSONValue] = []
    if let items = r["excluded"]?.arrayValue {
      var seen = Set<String>()
      for item in items.prefix(maxEntries) {
        guard let s = slug(item), !seen.contains(s) else { continue }
        seen.insert(s)
        excluded.append(.string(s))
      }
    }
    // `r.pdf && typeof r.pdf === 'object'`: an array spreads its indices.
    var pdf = JSONObject()
    switch r["pdf"] {
    case .object(let object)?: pdf = object
    case .array(let items)?: for (index, item) in items.enumerated() { pdf[String(index)] = item }
    default: break
    }
    let pageSize = pdf["pageSize"]?.stringValue.flatMap { pageSizes.contains($0) ? $0 : nil } ?? "A4"
    pdf["pageSize"] = .string(pageSize)
    pdf["landscape"] = .bool(pdf["landscape"]?.boolValue ?? false)

    var book = r
    book["id"] = .string(id)
    book["title"] = .string(text(r["title"]))
    book["subtitle"] = .string(text(r["subtitle"]))
    book["author"] = .string(text(r["author"]))
    book["language"] = .string(text(r["language"]))
    book["root"] = .string(r["root"]?.stringValue.map { JSText.slice(JSText.replaceAll($0, #"^/+|/+$"#, with: ""), 0, maxSlug) } ?? "")
    book["order"] = order
    book["excluded"] = .array(excluded)
    book["coverImage"] = .string(text(r["coverImage"]))
    book["toc"] = .bool(r["toc"]?.boolValue ?? true)
    book["tagIndex"] = .bool(r["tagIndex"]?.boolValue ?? false)
    book["backlinks"] = .bool(r["backlinks"]?.boolValue ?? false)
    book["outsideLinks"] = .string(r["outsideLinks"] == .string("text") ? "text" : "site")
    book["pdf"] = .object(pdf)
    return Book(object: book)
  }

  /// `serializeBook`: the book without its id (that is the file name), with the version this
  /// writer wrote, even over a file a newer one left.
  public static func serialize(_ book: JSONObject) -> JSONObject {
    var rest = book
    rest["id"] = nil
    rest["version"] = .number(version)
    return rest
  }

  /// `bookIdFromTitle`: "Handbuch für Einsteiger" → "handbuch-fuer-einsteiger", unique among
  /// `taken` by a counter. Umlauts are spelled out, not stripped.
  public static func id(fromTitle title: String, taken: Set<String>) -> String {
    var base = title.lowercased()
    for (from, to) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] { base = base.replacingOccurrences(of: from, with: to, options: .literal) }
    base = base.decomposedStringWithCompatibilityMapping
    base = JSText.replaceAll(base, "[\\u0300-\\u036f]", with: "")
    base = JSText.replaceAll(base, "[^a-z0-9]+", with: "-")
    base = JSText.replaceAll(base, "^-+|-+$", with: "")
    base = JSText.replaceAll(JSText.slice(base, 0, 48), "-+$", with: "")
    if base.isEmpty { base = "dokument" }
    if !taken.contains(base) { return base }
    var n = 2
    while taken.contains("\(base)-\(n)") { n += 1 }
    return "\(base)-\(n)"
  }

  /// QuartzControl's `bookSaveArgs` schema for the book (it guarded the IPC boundary there; here
  /// the page and `save` share it): why the input cannot be saved, or nil. Lengths in UTF-16 units.
  public static func problem(_ input: JSONObject) -> String? {
    func text(_ key: String, max: Int = maxText) -> Bool { input[key]?.stringValue.map { JSText.length($0) <= max } ?? false }
    func bool(_ key: String) -> Bool { input[key]?.boolValue != nil }
    if let id = input["id"], !(id.stringValue.map(isID) ?? false) { return "id" }
    for key in ["title", "subtitle", "author", "language", "coverImage"] where !text(key) { return key }
    if !text("root", max: maxSlug) { return "root" }
    switch input["order"] {
    case .null?: break
    case .array(let items)?:
      guard items.count <= maxEntries else { return "order" }
      for item in items {
        guard let fields = item.objectValue else { return "order" }
        let slugOK = fields["slug"]?.stringValue.map { JSText.length($0) >= 1 && JSText.length($0) <= maxSlug } ?? false
        let headingOK = fields["heading"]?.stringValue.map { JSText.length($0) >= 1 && JSText.length($0) <= maxText } ?? false
        if !slugOK && !headingOK { return "order" }
      }
    default: return "order"
    }
    guard let excluded = input["excluded"]?.arrayValue, excluded.count <= maxEntries,
          excluded.allSatisfy({ $0.stringValue.map { JSText.length($0) >= 1 && JSText.length($0) <= maxSlug } ?? false })
    else { return "excluded" }
    for key in ["toc", "tagIndex", "backlinks"] where !bool(key) { return key }
    guard let links = input["outsideLinks"]?.stringValue, links == "site" || links == "text" else { return "outsideLinks" }
    guard let pdf = input["pdf"]?.objectValue, let size = pdf["pageSize"]?.stringValue, pageSizes.contains(size), pdf["landscape"]?.boolValue != nil
    else { return "pdf" }
    return nil
  }
}

/// The books of a project (`bookService.ts`): quartz-books/<id>.json, one file each.
///
/// Written like every other store, through a temp file and a rename. Read differently, on
/// purpose: a store only this app writes moves an unreadable file aside, but this one is
/// versioned - a merge conflict renamed to `<id>.json.corrupt-…` would travel into the user's
/// repository with the next commit. So an unreadable book stays where it is, is listed with its
/// reason, and cannot be overwritten by a save until it is readable again. Reading never creates
/// the folder; only a save does.
///
/// One difference: a reason from the JSON parser is QuartzHub's parser's ("Unexpected token at
/// byte 0"), not V8's ("Unexpected token '<', "<<<<<<< HE"... is not valid JSON").
public struct Books: Sendable {
  public struct Listing: Equatable, Sendable {
    public var books: [Book]
    public var unreadable: [(id: String, reason: String)]

    public static func == (lhs: Listing, rhs: Listing) -> Bool {
      lhs.books == rhs.books && lhs.unreadable.map(\.id) == rhs.unreadable.map(\.id) && lhs.unreadable.map(\.reason) == rhs.unreadable.map(\.reason)
    }

    public var json: JSONValue {
      .object(JSONObject([
        ("books", .array(books.map(\.json))),
        ("unreadable", .array(unreadable.map { .object(JSONObject([("id", .string($0.id)), ("reason", .string($0.reason))])) }))
      ]))
    }
  }

  enum ReadResult {
    case ok(Book)
    case missing
    case unreadable(String)
  }

  public let project: String
  public init(project: String) { self.project = project }

  var folder: String { NodePath.join(project, BookFile.directory) }

  func unreadable(_ id: String, _ reason: String) -> PublishFailure {
    PublishFailure(L10n.t("main.bookUnreadable", ["file": "\(BookFile.directory)/\(id).json", "reason": reason]))
  }

  /// `readFile(path, 'utf-8')` and `JSON.parse`: a file error is Node's sentence, invalid UTF-8
  /// becomes U+FFFD as in Node.
  func readOne(_ id: String) -> ReadResult {
    let path = NodePath.join(folder, "\(id).json")
    let fd = open(path, O_RDONLY | O_CLOEXEC)
    guard fd >= 0 else {
      if errno == ENOENT { return .missing }
      return .unreadable(Self.message(NodeFileError(code: errno, syscall: "open", path: path)))
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
      let n = Darwin.read(fd, &buffer, buffer.count)
      if n < 0 {
        if errno == EINTR { continue }
        let code = errno
        close(fd)
        return .unreadable(Self.message(NodeFileError(code: code, syscall: "read", path: nil)))
      }
      if n == 0 { break }
      data.append(buffer, count: n)
    }
    close(fd)
    let parsed: JSONValue
    do {
      parsed = try JSJSON.parse(String(decoding: data, as: UTF8.self))
    } catch {
      return .unreadable(error.description)
    }
    guard let book = BookFile.normalize(id: id, parsed) else { return .unreadable(L10n.t("main.bookNotAnObject")) }
    return .ok(book)
  }

  static func message(_ error: NodeFileError) -> String { JSText.slice(error.description, 7) }

  /// The ids of the book files present, whatever their content. A name that is not a book id
  /// (`Notizen.json`, a `.corrupt-` copy) is passed over.
  func presentIDs() throws -> [String] {
    guard let stream = opendir(folder) else {
      if errno == ENOENT || errno == ENOTDIR { return [] }
      throw PublishFailure(Self.message(NodeFileError(code: errno, syscall: "scandir", path: folder)))
    }
    var names: [String] = []
    while let entry = readdir(stream) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self) }
      if name == "." || name == ".." { continue }
      names.append(name)
    }
    closedir(stream)
    return names.filter { JSText.endsWith($0, ".json") }
      .map { JSText.slice($0, 0, JSText.length($0) - 5) }
      .filter(BookFile.isID)
      .sorted()
  }

  public func list() throws -> Listing {
    var listing = Listing(books: [], unreadable: [])
    for id in try presentIDs() {
      switch readOne(id) {
      case .ok(let book): listing.books.append(book)
      case .unreadable(let reason): listing.unreadable.append((id, reason))
      case .missing: break
      }
    }
    return listing
  }

  public func read(_ id: String) throws -> Book? {
    switch readOne(id) {
    case .ok(let book): return book
    case .missing: return nil
    case .unreadable(let reason): throw unreadable(id, reason)
    }
  }

  /// Saves the book from the page. Without an id it gets one from its title.
  public func save(_ input: JSONObject) throws -> Book {
    let id: String
    if let given = input["id"]?.stringValue {
      // A file that is there but unreadable is somebody's unfinished edit or merge; writing over it
      // would decide that conflict for them.
      if case .unreadable(let reason) = readOne(given) { throw unreadable(given, reason) }
      id = given
    } else {
      id = BookFile.id(fromTitle: input["title"]?.stringValue ?? "", taken: Set(try presentIDs()))
    }
    // Every segment, the folder included: quartz-books/ as a link into another project (or a
    // vault) would turn this save into a write there.
    guard let target = PackagePaths.writable(project, "\(BookFile.directory)/\(id).json") else {
      throw PublishFailure(L10n.t("main.bookPathBlocked", ["dir": BookFile.directory]))
    }
    try Self.mkdirs(folder)
    var book = input
    book["id"] = .string(id)
    do {
      try JSONStore.writeAtomic(Data((JSJSON.stringify(.object(BookFile.serialize(book))) + "\n").utf8), to: target)
    } catch let error as NodeFileError {
      throw PublishFailure(Self.message(error))
    }
    // Read back what the file now says, so the page holds the normalised form, not its own draft.
    switch readOne(id) {
    case .ok(let saved): return saved
    case .missing: throw unreadable(id, "missing")
    case .unreadable: throw unreadable(id, "unreadable")
    }
  }

  public func delete(_ id: String) throws {
    guard let target = PackagePaths.writable(project, "\(BookFile.directory)/\(id).json") else {
      throw PublishFailure(L10n.t("main.bookPathBlocked", ["dir": BookFile.directory]))
    }
    // `rm(target, { force: true })`: nothing there is fine, a folder is not removed.
    var info = stat()
    guard lstat(target, &info) == 0 else { return }
    if (info.st_mode & S_IFMT) == S_IFDIR {
      throw PublishFailure("Path is a directory: rm returned EISDIR (is a directory) \(target)")
    }
    guard unlink(target) == 0 else {
      if errno == ENOENT { return }
      throw PublishFailure(Self.message(NodeFileError(code: errno, syscall: "unlink", path: target)))
    }
  }

  /// `mkdir(path, { recursive: true })` with Node's sentence when something else stands there.
  static func mkdirs(_ path: String) throws {
    var info = stat()
    if stat(path, &info) == 0 {
      if (info.st_mode & S_IFMT) == S_IFDIR { return }
      throw PublishFailure(message(NodeFileError(code: EEXIST, syscall: "mkdir", path: path)))
    }
    do {
      try Posix.mkdirs(path)
    } catch let error as NodeFileError {
      throw PublishFailure(message(error))
    }
  }
}
