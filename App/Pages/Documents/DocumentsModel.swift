import AppKit
import QuartzHubCore
import SwiftUI

/// A book as the page edits it (QuartzControl's `Draft` in `Documents/index.tsx`): the fields as
/// values, the book's own order with an id per entry, and the object it was read from, so a key a
/// newer version wrote survives the save.
///
/// The ids are the page's, not the file's: an interposed heading has no name of its own that stays
/// put while it is moved or renamed (QuartzControl gave each entry object an id for the same reason).
/// Whether the book changed is asked of `json`, which carries no ids.
struct BookDraft {
  struct Entry: Identifiable, Equatable {
    let id: Int
    var value: BookEntry

    var slug: String? {
      if case .page(let slug) = value { return slug }
      return nil
    }
  }

  let id: String
  private let base: JSONObject
  var title: String
  var subtitle: String
  var author: String
  var language: String
  var root: String
  var coverImage: String
  /// nil follows the site's navigation.
  var order: [Entry]?
  var excluded: [String]
  var toc: Bool
  var tagIndex: Bool
  var backlinks: Bool
  var outsideLinks: String
  var pageSize: String
  var landscape: Bool

  init(_ book: Book, nextId: inout Int) {
    id = book.id
    base = book.object
    title = book.title
    subtitle = book.subtitle
    author = book.author
    language = book.language
    root = book.root
    coverImage = book.coverImage
    order = book.order?.map { entry in
      defer { nextId += 1 }
      return Entry(id: nextId, value: entry)
    }
    excluded = book.excluded
    toc = book.toc
    tagIndex = book.tagIndex
    backlinks = book.backlinks
    outsideLinks = book.outsideLinks
    pageSize = book.pageSize
    landscape = book.landscape
  }

  var name: String { title.isEmpty ? id : title }

  /// What `Books.save` gets: the object read, with the page's fields over it.
  var json: JSONObject {
    var object = base
    object["id"] = .string(id)
    object["title"] = .string(title)
    object["subtitle"] = .string(subtitle)
    object["author"] = .string(author)
    object["language"] = .string(language)
    object["root"] = .string(root)
    object["order"] = order.map { .array($0.map(\.value.json)) } ?? .null
    object["excluded"] = .array(excluded.map(JSONValue.string))
    object["coverImage"] = .string(coverImage)
    object["toc"] = .bool(toc)
    object["tagIndex"] = .bool(tagIndex)
    object["backlinks"] = .bool(backlinks)
    object["outsideLinks"] = .string(outsideLinks)
    var pdf = base["pdf"]?.objectValue ?? JSONObject()
    pdf["pageSize"] = .string(pageSize)
    pdf["landscape"] = .bool(landscape)
    object["pdf"] = .object(pdf)
    return object
  }

  func isExcluded(_ slug: String) -> Bool { excluded.contains(slug) }

  mutating func setExcluded(_ slug: String, _ leaveOut: Bool) {
    if leaveOut {
      if !excluded.contains(slug) { excluded.append(slug) }
    } else {
      excluded.removeAll { $0 == slug }
    }
  }
}

/// What Dokumente reads and writes (QuartzControl's `Documents/index.tsx`): the project's books,
/// the selected one as a draft, and the pages of the build that draft can take.
///
/// The page owns the selected book (docs/conventions.md, „Eine Seite besitzt ihr Dokument“): read
/// from the listing, saved explicitly (button or ⌘S), dirty by comparison with what was read, and
/// read again after every save. Not kept across pages: leaving with edits asks first.
@MainActor @Observable
final class DocumentsModel {
  let project: ProjectContext
  private var path: String { project.path }

  private(set) var books: [Book] = []
  private(set) var unreadable: [(id: String, reason: String)] = []
  private(set) var loaded = false
  private(set) var listError: String?

  private(set) var selectedId: String?
  var draft: BookDraft?
  /// The draft as read, for `dirty`.
  private var saved: JSONObject?
  private var nextEntryId = 0

  private(set) var saving = false
  private(set) var saveError: String?
  private(set) var creating = false
  private(set) var createError: String?

  /// The pages of the build for the draft's folder and language.
  private(set) var site: SitePages?
  private(set) var siteLoading = false
  private(set) var siteError: String?
  /// The folder the page list was read for. Typed, the folder is read once the typing pauses: each
  /// keystroke was a copy of the build and a window of its own in QuartzControl, 15 copies for
  /// "quellen/artikel" (its review of 2026-11-06, N2). Another book's folder is read at once.
  private(set) var settled: (book: String, root: String)?

  init(project: ProjectContext) {
    self.project = project
  }

  var dirty: Bool {
    guard let draft, let saved else { return false }
    return draft.json != saved
  }

  // MARK: Reading

  /// The listing, and the book `select` names (nil: none) or the one already selected.
  func load(select id: String?? = nil) {
    do {
      let listing = try Books(project: path).list()
      books = listing.books
      unreadable = listing.unreadable
      listError = nil
    } catch {
      listError = PublishFailure.message(of: error)
    }
    loaded = true
    open(id ?? selectedId)
  }

  /// Takes the book as the draft, dropping whatever was edited: the page asked first.
  func open(_ id: String?) {
    let book = books.first { $0.id == id }
    let before = draft
    selectedId = book?.id
    draft = book.map { BookDraft($0, nextId: &nextEntryId) }
    // The same order read back after a save keeps its rows' ids, and with them the highlighted row.
    if let before, before.id == draft?.id, let old = before.order, let new = draft?.order, old.map(\.value) == new.map(\.value) {
      draft?.order = old
    }
    saved = draft?.json
    saveError = nil
  }

  func discard() {
    open(selectedId)
  }

  /// The names a new book's file may not take.
  var takenIDs: Set<String> { Set(books.map(\.id) + unreadable.map(\.id)) }

  // MARK: Writing

  /// The file name comes from the title here and stays (`BookFile.id(fromTitle:)`), so the title is
  /// asked first (review 2026-11-13, handbook, N14: every book was neues-buch.json).
  func create(title: String) async {
    creating = true
    defer { creating = false }
    do {
      let book = try Books(project: path).save(BookFile.empty(title: title))
      createError = nil
      load(select: book.id)
      Announce.post(L10n.t("documents.createdAnnounce", ["name": book.title]))
    } catch {
      createError = PublishFailure.message(of: error)
    }
  }

  /// true when the book is on disk; the leave question stays on the page otherwise.
  @discardableResult
  func save() async -> Bool {
    guard let draft else { return true }
    if let field = BookFile.problem(draft.json) {
      saveError = L10n.t("documents.saveInvalid", ["field": Self.fieldName(field)])
      return false
    }
    saving = true
    defer { saving = false }
    do {
      let book = try Books(project: path).save(draft.json)
      load(select: book.id)
      Announce.post(L10n.t("documents.savedAnnounce", ["name": book.title.isEmpty ? book.id : book.title]))
      return true
    } catch {
      saveError = PublishFailure.message(of: error)
      return false
    }
  }

  /// The words of the field `BookFile.problem` names.
  private static func fieldName(_ key: String) -> String {
    switch key {
    case "title": L10n.t("documents.fields.title")
    case "subtitle": L10n.t("documents.fields.subtitle")
    case "author": L10n.t("documents.fields.author")
    case "language": L10n.t("documents.fields.language")
    case "root": L10n.t("documents.fields.root")
    case "coverImage": L10n.t("documents.fields.cover")
    case "order", "excluded": L10n.t("documents.pagesHeading")
    case "toc": L10n.t("documents.fields.toc")
    case "tagIndex": L10n.t("documents.fields.tagIndex")
    case "backlinks": L10n.t("documents.fields.backlinks")
    case "outsideLinks": L10n.t("documents.fields.outsideLinks")
    case "pdf": L10n.t("documents.fields.pageSize")
    default: key
    }
  }

  /// Deleting another book keeps the open one's edits: QuartzControl read the open book afresh
  /// from the new listing and dropped them.
  func delete(_ book: Book, window: NSWindow?) async -> Bool {
    let name = book.title.isEmpty ? book.id : book.title
    let (question, detail) = Confirm.split(L10n.t("documents.confirmDelete", ["name": name, "file": "\(BookFile.directory)/\(book.id).json"]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("documents.deleteBook"), destructive: true, window: window) else { return false }
    do {
      try Books(project: path).delete(book.id)
      listError = nil
    } catch {
      listError = PublishFailure.message(of: error)
      return false
    }
    let keep = draft
    let keepSaved = saved
    let next: String? = book.id == selectedId ? nil : selectedId
    load(select: .some(next))
    if book.id != selectedId, let keep, selectedId == keep.id {
      draft = keep
      saved = keepSaved
    }
    Announce.post(L10n.t("documents.deletedAnnounce", ["name": name]))
    return true
  }

  // MARK: The pages of the build

  /// Called with every change of the draft's folder: another book's folder is taken at once, the
  /// same book's after half a second without typing.
  func settle(book: String?, root: String) async {
    guard let book else {
      settled = nil
      return
    }
    if let settled, settled.book == book {
      guard settled.root != root else { return }
      try? await Task.sleep(for: .milliseconds(500))
      if Task.isCancelled { return }
    }
    settled = (book, root)
  }

  /// A new read for every folder and language; a read overtaken by the next one is dropped.
  func loadSite(root: String, language: String) async {
    siteLoading = true
    do {
      let pages = try await ExportBook.sitePages(project: path, root: root, language: language)
      if Task.isCancelled { return }
      site = pages
      siteError = nil
    } catch {
      if Task.isCancelled { return }
      site = nil
      siteError = PublishFailure.message(of: error)
    }
    siteLoading = false
  }

  // MARK: The order

  func ownOrder() {
    guard let site, draft != nil else { return }
    draft?.order = site.pages.filter(\.inNavigation).map(newEntry)
  }

  private func newEntry(_ page: SitePages.Entry) -> BookDraft.Entry {
    defer { nextEntryId += 1 }
    return BookDraft.Entry(id: nextEntryId, value: .page(page.slug))
  }

  func followNavigation() {
    draft?.order = nil
  }

  func addHeading() {
    guard draft?.order != nil else { return }
    draft?.order?.append(BookDraft.Entry(id: nextEntryId, value: .heading(L10n.t("documents.pages.newHeading"))))
    nextEntryId += 1
    Announce.post(L10n.t("documents.pages.headingAddedAnnounce"))
  }

  func takeIn(_ slug: String) {
    guard draft?.order != nil else { return }
    draft?.order?.append(BookDraft.Entry(id: nextEntryId, value: .page(slug)))
    nextEntryId += 1
  }

  func rename(_ id: Int, _ heading: String) {
    guard let index = draft?.order?.firstIndex(where: { $0.id == id }) else { return }
    draft?.order?[index].value = .heading(heading)
  }

  func remove(_ id: Int, label: String) {
    draft?.order?.removeAll { $0.id == id }
    Announce.post(L10n.t("documents.pages.removedAnnounce", ["name": label]))
  }

  /// Every way of moving (drag, Anordnen, context menu, accessibility) ends here; a drag is not
  /// announced, it was seen.
  func move(_ from: Int, to: Int, label: String, said: Bool = true) {
    guard let count = draft?.order?.count, from != to, from >= 0, from < count, to >= 0, to < count else { return }
    let item = draft!.order!.remove(at: from)
    draft?.order?.insert(item, at: to)
    if said { Announce.post(L10n.t("documents.pages.movedAnnounce", ["name": label, "n": String(to + 1), "count": String(count)])) }
  }

  func move(fromOffsets: IndexSet, toOffset: Int) {
    draft?.order?.move(fromOffsets: fromOffsets, toOffset: toOffset)
  }
}
