import QuartzHubCore
import SwiftUI

/// Dokumente: QuartzControl's `Documents/index.tsx` and `PageOrder.tsx`. A book says which pages of
/// the site go into a PDF, an ePub or an offline HTML, in which order and under which title; it is
/// a file in the project (quartz-books/<id>.json), exported by a target of the type „Dokument“ on
/// Veröffentlichen.
///
/// A list page (decisions/ui-ueberarbeitung.md): in the middle the books, then the selected book's
/// pages; the inspector holds its title, author and PDF settings. "Neues Buch" is the toolbar's +. Both halves are one draft: "Speichern" in the toolbar and ⌘S write it, and
/// every way off it asks (another book, "Neues Buch", another page, closing the window).
struct DocumentsPage: View {
  let project: ProjectContext

  @State private var model: DocumentsModel
  @Environment(\.unsavedGuard) private var unsaved
  @Environment(\.openPage) private var openPage
  /// The selected book, by id ("where was I").
  @SceneStorage("documents.book") private var storedId: String?
  /// The list's highlight: a book ("book:<id>") or a row of its own order ("entry:<n>"), which
  /// Anordnen moves. Its own state, so a switch the leave question cancels can move it back.
  @State private var highlighted: String?

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: DocumentsModel(project: project))
  }

  var body: some View {
    PageScaffold(page: .documents) {
      list
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.documents")
      .task {
        // Without a book everything below the list describes nothing, so the first one is taken
        // when none is remembered or the remembered one is gone (as on Veröffentlichen).
        model.load(select: .some(storedId))
        if model.selectedId == nil { model.open(model.books.first?.id) }
        highlighted = model.selectedId.map(Self.bookTag)
      }
      .onChange(of: highlighted) { old, new in choose(from: old, to: new) }
      .onChange(of: model.selectedId) { _, id in
        storedId = id
        highlighted = id.map(Self.bookTag)
      }
      .task(id: "\(model.draft?.id ?? "")|\(model.draft?.root ?? "")") {
        await model.settle(book: model.draft?.id, root: model.draft?.root ?? "")
      }
      .task(id: siteKey) {
        guard let siteKey else { return }
        await model.loadSite(root: siteKey.root, language: siteKey.language)
      }
      .unsavedChanges(model.dirty, save: model.saving || model.draft == nil ? nil : { await model.save() })
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(action: create) { Label(L10n.t("documents.newBook"), systemImage: "plus") }
            .help(L10n.t("documents.newBook"))
            .disabled(model.creating)
            .accessibilityIdentifier("documents.newBook")
        }
        // No badge beside Speichern: it is enabled only with something to save, and the dot in the
        // close button says the same (as on Konfiguration).
        if model.draft != nil {
          ToolbarSpacer(.fixed, placement: .primaryAction)
          ToolbarItemGroup(placement: .primaryAction) {
            Button(L10n.t("documents.discard")) { model.discard() }
              .disabled(!model.dirty || model.saving)
              .accessibilityIdentifier("documents.discard")
            Button(model.saving ? L10n.t("common.saving") : L10n.t("common.save")) { Task { await model.save() } }
              .disabled(!model.dirty || model.saving)
              .accessibilityIdentifier("documents.save")
          }
        }
      }
    } inspector: {
      if model.draft != nil {
        BookInspector(model: model) { book in delete(book) }
      } else {
        InspectorPageContext(page: .documents) {
          Section {
            Text(L10n.t("documents.noSelection")).foregroundStyle(.secondary)
          } header: {
            Text(L10n.t("documents.settingsHeading"))
          }
        }
      }
    }
  }

  private static func bookTag(_ id: String) -> String { "book:\(id)" }

  private struct SiteKey: Hashable {
    var root: String
    var language: String
  }

  /// The pages are read for the settled folder and the draft's language; another book's folder is
  /// settled at once (`DocumentsModel.settle`).
  private var siteKey: SiteKey? {
    guard let draft = model.draft, let settled = model.settled, settled.book == draft.id else { return nil }
    return SiteKey(root: settled.root, language: draft.language)
  }

  /// A click on another book, or on the empty list after a book, leaves the open one: with edits
  /// that asks the sidebar's question with its three answers (QuartzControl, measured
  /// 2026-11-05). A row of the order is no change of book.
  private func choose(from old: String?, to new: String?) {
    let target: String?
    if let new, new.hasPrefix("book:") {
      target = String(new.dropFirst(5))
    } else if new == nil, old?.hasPrefix("book:") == true {
      target = nil
    } else {
      return
    }
    guard target != model.selectedId else { return }
    guard model.dirty, let unsaved else {
      model.open(target)
      return
    }
    Task {
      if await unsaved.confirmLeave() {
        model.open(target)
      } else {
        highlighted = old
      }
    }
  }

  private func create() {
    Task {
      if model.dirty, let unsaved, await !unsaved.confirmLeave() { return }
      await model.create()
    }
  }

  private func delete(_ book: Book) {
    Task { _ = await model.delete(book, window: unsaved?.window) }
  }

  // MARK: Above the list

  /// Under the books: what a book is for, and the way to the page that exports it.
  private var howItWorks: some View {
    HStack(alignment: .firstTextBaseline) {
      Note(L10n.t("documents.howItWorks"))
      Spacer()
      Button(L10n.t("documents.toPublish")) { openPage(.publish) }
        .buttonStyle(.link)
        .font(.callout)
        .accessibilityIdentifier("documents.toPublish")
    }
  }

  // MARK: The list

  private var list: some View {
    List(selection: $highlighted) {
      booksSection
      if model.draft != nil { pagesSections }
    }
    .accessibilityIdentifier("documents.list")
    .focusedSceneValue(\.moveSelection, moveAction)
  }

  private var booksSection: some View {
    Section {
      if let error = model.listError ?? model.createError { Callout(.error, error) }
      if model.loaded && model.books.isEmpty { Text(L10n.t("documents.noBooks")).foregroundStyle(.secondary) }
      ForEach(model.books, id: \.id) { book in
        let name = book.title.isEmpty ? book.id : book.title
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(name).fontWeight(.medium)
            Text(verbatim: "\(BookFile.directory)/\(book.id).json").font(.callout.monospaced()).foregroundStyle(.secondary)
          }
          Spacer()
          Button { delete(book) } label: {
            Label(L10n.t("common.deleteNamed", ["name": name]), systemImage: "trash").labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .help(L10n.t("common.deleteNamed", ["name": name]))
        }
        .padding(.vertical, 2)
        .tag(Self.bookTag(book.id))
        .contextMenu {
          Button(L10n.t("common.deleteNamed", ["name": name]), role: .destructive) { delete(book) }
        }
        .accessibilityIdentifier("documents.book.\(book.id)")
      }
      ForEach(model.unreadable, id: \.id) { entry in
        Callout(.warning, L10n.t("documents.unreadable", ["file": "\(BookFile.directory)/\(entry.id).json", "reason": entry.reason]))
      }
    } header: {
      Text(L10n.t("documents.booksHeading"))
    } footer: {
      howItWorks
    }
  }

  // MARK: The pages

  @ViewBuilder private var pagesSections: some View {
    if model.site == nil || model.siteLoading {
      Section(L10n.t("documents.pagesHeading")) {
        if model.siteLoading {
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(L10n.t("documents.pagesLoading")).foregroundStyle(.secondary)
          }
        }
        if let error = model.siteError, !model.siteLoading {
          Callout(.error) {
            Text(error).textSelection(.enabled).accessibilityIdentifier("documents.siteError")
            Button(L10n.t("documents.toBuild")) { openPage(.server) }.buttonStyle(.link).font(.callout)
          }
        }
      }
    } else if let site = model.site, let draft = model.draft {
      if let order = draft.order {
        OwnOrderSections(model: model, site: site, order: order)
      } else {
        FollowingSections(model: model, site: site, draft: draft)
      }
    }
  }

  /// Anordnen ▸ Nach oben/unten for the highlighted row of the book's own order.
  private var moveAction: MoveSelectionAction? {
    guard let highlighted, highlighted.hasPrefix("entry:"), let id = Int(highlighted.dropFirst(6)),
          let order = model.draft?.order, let index = order.firstIndex(where: { $0.id == id }) else { return nil }
    let label = PageOrderWords.label(order[index], site: model.site)
    return MoveSelectionAction(canMoveUp: index > 0, canMoveDown: index < order.count - 1) { delta in
      model.move(index, to: index + delta, label: label)
    }
  }
}

/// The words of the page list that depend on a value.
@MainActor
enum PageOrderWords {
  static func source(_ source: String) -> String? {
    switch source {
    case "contentIndex": L10n.t("documents.source.contentIndex")
    case "explorer": L10n.t("documents.source.explorer")
    case "links": L10n.t("documents.source.links")
    case "quartz-navigations": L10n.t("documents.source.quartz-navigations")
    default: nil
    }
  }

  static func label(_ entry: BookDraft.Entry, site: SitePages?) -> String {
    switch entry.value {
    case .page(let slug): site?.pages.first { $0.slug == slug }?.title ?? slug
    case .heading(let text): text
    }
  }

  /// One step per folder level below the book's folder.
  static func indent(_ depth: Int) -> CGFloat { CGFloat(max(0, depth - 1)) * 16 }
}

/// A book that follows the site's navigation: the navigation's order with a tick per page, then
/// the pages it does not show, which only an own order can take in.
private struct FollowingSections: View {
  let model: DocumentsModel
  let site: SitePages
  let draft: BookDraft

  var body: some View {
    let navigation = site.pages.filter(\.inNavigation)
    let hidden = site.pages.filter { !$0.inNavigation }
    let count = navigation.filter { !draft.isExcluded($0.slug) }.count
    Section {
      if let sentence = PageOrderWords.source(site.source) { Note(sentence) }
      HStack(alignment: .firstTextBaseline) {
        Note(L10n.t("documents.pages.followingHint", ["count": String(count)], count: count))
        Spacer()
        Button(L10n.t("documents.pages.ownOrder")) { model.ownOrder() }
          .accessibilityIdentifier("documents.ownOrder")
      }
      ForEach(navigation, id: \.slug) { page in
        let leftOut = draft.isExcluded(page.slug)
        Toggle(isOn: Binding(get: { !leftOut }, set: { model.draft?.setExcluded(page.slug, !$0) })) {
          Text(page.title).strikethrough(leftOut).foregroundStyle(leftOut ? .secondary : .primary)
        }
        .toggleStyle(.checkbox)
        .padding(.leading, PageOrderWords.indent(page.depth))
        .accessibilityIdentifier("documents.page.\(page.slug)")
      }
    } header: {
      Text(L10n.t("documents.pagesHeading"))
    }
    if !hidden.isEmpty {
      Section {
        Note(L10n.t("documents.pages.hiddenHint"))
        ForEach(hidden, id: \.slug) { page in
          HiddenPageRow(page: page)
        }
      } header: {
        Text(L10n.t("documents.pages.hiddenHeading", ["count": String(hidden.count)], count: hidden.count))
      }
    }
  }
}

private struct HiddenPageRow: View {
  let page: SitePages.Entry
  var body: some View {
    HStack(spacing: 6) {
      Text(page.title).foregroundStyle(.secondary)
      Text(verbatim: page.slug).font(.callout.monospaced()).foregroundStyle(.tertiary)
    }
  }
}

/// A book with its own order: dragged, or moved with Anordnen, the context menu or an
/// accessibility action (docs/conventions.md, „Umsortieren“), with interposed headings. A page the
/// build no longer has says so; a page of the navigation the list does not name is shown where an
/// export puts it, at the end.
private struct OwnOrderSections: View {
  let model: DocumentsModel
  let site: SitePages
  let order: [BookDraft.Entry]

  var body: some View {
    let pages = Dictionary(site.pages.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
    let listed = Set(order.compactMap(\.slug))
    let appended = site.pages.filter { $0.inNavigation && !listed.contains($0.slug) }
    let notTaken = site.pages.filter { !$0.inNavigation && !listed.contains($0.slug) }
    Section {
      if let sentence = PageOrderWords.source(site.source) { Note(sentence) }
      // Beside the hint where there is room; below it in a narrow window, where the second button
      // was cut to "Follow the navigation ag…" (seen at 1000 × 700, English).
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          Note(L10n.t("documents.pages.ownHint")).fixedSize()
          Spacer()
          buttons
        }
        VStack(alignment: .leading, spacing: 6) {
          Note(L10n.t("documents.pages.ownHint"))
          HStack { buttons }
        }
      }
      ForEach(Array(order.enumerated()), id: \.element.id) { index, entry in
        OrderRow(model: model, entry: entry, page: entry.slug.flatMap { pages[$0] }, index: index, count: order.count,
                 label: PageOrderWords.label(entry, site: site))
          .tag("entry:\(entry.id)")
      }
      .onMove { from, to in model.move(fromOffsets: from, toOffset: to) }
    } header: {
      Text(L10n.t("documents.pagesHeading"))
    }
    if !appended.isEmpty {
      Section {
        ForEach(appended, id: \.slug) { page in
          HStack(spacing: 6) {
            Text(page.title).foregroundStyle(.secondary)
            WordBadge(text: L10n.t("documents.pages.appendedBadge"))
          }
        }
      } header: {
        Text(L10n.t("documents.pages.appendedHeading", ["count": String(appended.count)], count: appended.count))
      }
    }
    if !notTaken.isEmpty {
      Section {
        ForEach(notTaken, id: \.slug) { page in
          HStack {
            HiddenPageRow(page: page)
            Spacer()
            Button(L10n.t("documents.pages.takeIn")) { model.takeIn(page.slug) }
              .controlSize(.small)
              .accessibilityLabel("\(L10n.t("documents.pages.takeIn")): \(page.title)")
          }
        }
      } header: {
        Text(L10n.t("documents.pages.hiddenHeading", ["count": String(notTaken.count)], count: notTaken.count))
      }
    }
  }
}

extension OwnOrderSections {
  @ViewBuilder fileprivate var buttons: some View {
    Button { model.addHeading() } label: { Label(L10n.t("documents.pages.addHeading"), systemImage: "plus") }
      .accessibilityIdentifier("documents.addHeading")
    Button(L10n.t("documents.pages.followNavigation")) { model.followNavigation() }
      .accessibilityIdentifier("documents.followNavigation")
  }
}

private struct OrderRow: View {
  let model: DocumentsModel
  let entry: BookDraft.Entry
  /// nil for a heading, and for a page the build no longer has.
  let page: SitePages.Entry?
  let index: Int
  let count: Int
  let label: String

  var body: some View {
    let missing = entry.slug != nil && page == nil
    HStack(spacing: 8) {
      switch entry.value {
      case .heading(let text):
        Image(systemName: "textformat.size").foregroundStyle(.secondary).accessibilityHidden(true)
        TextField(L10n.t("documents.pages.headingText"), text: Binding(get: { text }, set: { model.rename(entry.id, $0) }))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .fontWeight(.semibold)
          .accessibilityLabel(L10n.t("documents.pages.headingText"))
      case .page(let slug):
        let leftOut = model.draft?.isExcluded(slug) == true
        Toggle(isOn: Binding(get: { !leftOut }, set: { model.draft?.setExcluded(slug, !$0) })) {
          Text(label).strikethrough(leftOut || missing).foregroundStyle(leftOut || missing ? .secondary : .primary)
        }
        .toggleStyle(.checkbox)
        .disabled(missing)
        .padding(.leading, PageOrderWords.indent(page?.depth ?? 1))
        if missing { WordBadge(text: L10n.t("documents.pages.missingBadge"), tint: .orange) }
      }
      Spacer()
      if entry.slug == nil || missing {
        Button { model.remove(entry.id, label: label) } label: {
          Label(L10n.t("common.removeNamed", ["name": label]), systemImage: "trash").labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(L10n.t("common.removeNamed", ["name": label]))
      }
    }
    .contextMenu {
      Button(L10n.t("shell.menu.moveUp")) { model.move(index, to: index - 1, label: label) }.disabled(index == 0)
      Button(L10n.t("shell.menu.moveDown")) { model.move(index, to: index + 1, label: label) }.disabled(index == count - 1)
      if entry.slug == nil || missing {
        Divider()
        Button(L10n.t("common.removeNamed", ["name": label]), role: .destructive) { model.remove(entry.id, label: label) }
      }
    }
    .accessibilityActions {
      if index > 0 { Button(L10n.t("pluginsInstalled.moveUp", ["name": label])) { model.move(index, to: index - 1, label: label) } }
      if index < count - 1 { Button(L10n.t("pluginsInstalled.moveDown", ["name": label])) { model.move(index, to: index + 1, label: label) } }
    }
    .accessibilityIdentifier("documents.entry.\(index)")
  }
}

/// The selected book's title, author and export settings. Edits go into the page's draft; the
/// toolbar's "Speichern" writes them with the page order.
private struct BookInspector: View {
  @Bindable var model: DocumentsModel
  let onDelete: (Book) -> Void

  var body: some View {
    if let current = model.draft {
      // Not `Binding($model.draft)`, which force-unwraps: deleting the open book left the rows
      // below reading it once more after the draft was gone, and QuartzHub crashed in
      // `BindingOperations.ForceUnwrapping` (measured 2026-11-10). A write after that is dropped.
      let draft = Binding<BookDraft>(get: { model.draft ?? current }, set: { if model.draft != nil { model.draft = $0 } })
      Form {
        if let error = model.saveError {
          Section {
            Label(error, systemImage: "exclamationmark.octagon.fill")
              .foregroundStyle(.red)
              .textSelection(.enabled)
              .accessibilityIdentifier("documents.saveError")
          }
        }
        Section {
          field(L10n.t("documents.fields.title"), text: draft.title, hint: L10n.t("documents.fields.titleHint"), id: "title")
          field(L10n.t("documents.fields.subtitle"), text: draft.subtitle, id: "subtitle")
          field(L10n.t("documents.fields.author"), text: draft.author, id: "author")
          if let languages = model.site?.languages, languages.count > 1 {
            let main = languages.first { $0.code == model.site?.defaultLanguage }?.label ?? model.site?.defaultLanguage ?? ""
            Picker(L10n.t("documents.fields.language"), selection: draft.language) {
              Text(L10n.t("documents.fields.languageDefault", ["language": main])).tag("")
              ForEach(languages, id: \.code) { Text($0.label).tag($0.code) }
              // A language the site no longer has stays what the file says.
              if !draft.wrappedValue.language.isEmpty, !languages.contains(where: { $0.code == draft.wrappedValue.language }) {
                Text(verbatim: draft.wrappedValue.language).tag(draft.wrappedValue.language)
              }
            }
            .accessibilityIdentifier("documents.field.language")
          }
          field(L10n.t("documents.fields.root"), text: draft.root, prompt: L10n.t("documents.fields.rootPlaceholder"),
                hint: L10n.t("documents.fields.rootHint"), id: "root")
          field(L10n.t("documents.fields.cover"), text: draft.coverImage, prompt: "quartz/static/icon.png",
                hint: L10n.t("documents.fields.coverHint"), id: "cover")
        } header: {
          Text(L10n.t("documents.settingsHeading"))
        }
        Section {
          toggle(L10n.t("documents.fields.toc"), isOn: draft.toc, hint: L10n.t("documents.fields.tocHint"), id: "toc")
          toggle(L10n.t("documents.fields.backlinks"), isOn: draft.backlinks, hint: L10n.t("documents.fields.backlinksHint"), id: "backlinks")
          toggle(L10n.t("documents.fields.tagIndex"), isOn: draft.tagIndex, hint: L10n.t("documents.fields.tagIndexHint"), id: "tagIndex")
          Picker(L10n.t("documents.fields.outsideLinks"), selection: draft.outsideLinks) {
            Text(L10n.t("documents.fields.outsideSite")).tag("site")
            Text(L10n.t("documents.fields.outsideText")).tag("text")
          }
          .pickerStyle(.radioGroup)
          .accessibilityIdentifier("documents.field.outsideLinks")
        }
        Section {
          Picker(L10n.t("documents.fields.pageSize"), selection: draft.pageSize) {
            ForEach(["A4", "A5", "Letter"], id: \.self) { Text(verbatim: $0).tag($0) }
          }
          .accessibilityIdentifier("documents.field.pageSize")
          Toggle(L10n.t("documents.fields.landscape"), isOn: draft.landscape)
            .accessibilityIdentifier("documents.field.landscape")
        }
        if let book = model.books.first(where: { $0.id == draft.wrappedValue.id }) {
          Section {
            Button(L10n.t("documents.deleteBook"), role: .destructive) { onDelete(book) }
              .accessibilityIdentifier("documents.delete")
          }
        }
      }
      .formStyle(.grouped)
    }
  }

  private func field(_ label: String, text: Binding<String>, prompt: String? = nil, hint: String? = nil, id: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(label, text: text, prompt: prompt.map { Text($0) })
        .accessibilityIdentifier("documents.field.\(id)")
      if let hint { Note(hint) }
    }
  }

  private func toggle(_ label: String, isOn: Binding<Bool>, hint: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle(label, isOn: isOn).accessibilityIdentifier("documents.field.\(id)")
      Note(hint)
    }
  }
}
