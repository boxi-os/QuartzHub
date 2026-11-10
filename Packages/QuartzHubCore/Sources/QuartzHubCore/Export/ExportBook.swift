import Foundation

/// A file of an export (`ExportFile`).
public struct ExportFile: Sendable {
  public var name: String
  public var bytes: Data
}

/// What one export gave (`ExportOutcome`): the files and a report of what was done - pages,
/// sources, what was replaced, what was not loaded - so the run can say it rather than leave a
/// document that looks finished and is not.
public struct ExportOutcome: Sendable {
  public var files: [ExportFile]
  public var report: [String]
  /// Pages of an own order the build no longer has, and new pages appended at the end.
  public var missing: [String]
  public var appended: [String]
  /// Pages of the site in the document (not counting the register).
  public var pages: Int
}

/// One document export, start to end (`exportService.ts`): a copy of the build served on
/// 127.0.0.1, the export window, the book's order resolved against the site's own navigation, every
/// page collected, and the chosen writers. Writing the files into a folder is the adapter's
/// (`DocumentAdapter`).
///
/// Runs are keyed by target id so `cancel(targetId:)` can stop one; `cancelAll()` is for the app's
/// last window closing (Phase 4), which in QuartzControl stopped every run.
@MainActor
public enum ExportBook {
  static var running: [String: Task<ExportOutcome, Error>] = [:]

  @discardableResult
  public static func cancel(targetId: String) -> Bool {
    guard let task = running[targetId] else { return false }
    task.cancel()
    return true
  }

  public static func cancelAll() {
    for task in running.values { task.cancel() }
  }

  public struct Request: Sendable {
    public var targetId: String
    public var project: String
    public var buildDir: String
    public var book: Book
    /// "pdf", "epub", "html".
    public var formats: [String]
    public var runtime: RuntimeLocation
    /// false refuses even what the rule lets in from outside: for a measurement that must not
    /// reach the network.
    public var outside: Bool

    public init(targetId: String, project: String, buildDir: String, book: Book, formats: [String], runtime: RuntimeLocation = .current,
                outside: Bool = true) {
      self.targetId = targetId
      self.project = project
      self.buildDir = buildDir
      self.book = book
      self.formats = formats
      self.runtime = runtime
      self.outside = outside
    }
  }

  /// `exportBook`. `progress(done, total, label)`: the page being collected, then the format
  /// being written.
  public static func run(_ request: Request, progress: @escaping @MainActor (Int, Int, String) -> Void = { _, _, _ in }) async throws -> ExportOutcome {
    if running[request.targetId] != nil { throw PublishFailure(L10n.t("main.exportRunning")) }
    let task = Task { @MainActor in try await export(request, progress: progress) }
    running[request.targetId] = task
    defer { running[request.targetId] = nil }
    do {
      return try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
    } catch {
      if task.isCancelled || error is CancellationError { throw PublishFailure(L10n.t("main.exportCancelled")) }
      throw error
    }
  }

  /// The PDF's keywords etc. come from `ExportExtras`; this is the run.
  static func export(_ request: Request, progress: @escaping @MainActor (Int, Int, String) -> Void) async throws -> ExportOutcome {
    let book = request.book
    var report: [String] = []
    let config = try? await ConfigFile.read(project: request.project, runtime: request.runtime)
    let baseUrl = config?.configuration["baseUrl"]?.stringValue
    let scripts = try ExportWindow.pageScripts(location: request.runtime)
    let server = try await SiteServer.start(try SiteCopy.make(from: request.buildDir))
    defer { server.close() }
    let facts = try SiteFacts.read(root: server.copy.root)
    let window = ExportWindow(origin: server.origin, size: CGSize(width: DocumentHTML.printWidthPx(book.pageSize, landscape: book.landscape), height: 1000),
                              pageScripts: scripts, outside: request.outside)
    defer { window.close() }
    try await window.prepare()
    try Task.checkCancellation()

    let nav = try await ExportCollect.navigationOrder(window, origin: server.origin, facts: facts, language: book.language)
    let root = facts.effectiveRoot(book.root, language: book.language)
    let resolved = ExportModel.resolveOrder(order: book.order, excluded: book.excluded, root: root, navigation: nav.slugs,
                                            available: Set(facts.pages(inLanguage: book.language)))
    let pageItems = resolved.items.filter { if case .page = $0 { true } else { false } }
    if pageItems.isEmpty { throw PublishFailure(L10n.t("main.exportNoPages")) }
    // With an own order the navigation only decides what is new; saying the order came from it
    // would describe the wrong book.
    report.append(book.order == nil ? sourceLine(nav.source, count: pageItems.count) : L10n.t("main.exportReportOwnOrder", ["count": String(pageItems.count)], count: pageItems.count))
    if !resolved.missing.isEmpty {
      report.append(L10n.t("main.exportReportMissing", ["count": String(resolved.missing.count), "pages": resolved.missing.prefix(5).joined(separator: ", ")], count: resolved.missing.count))
    }
    if !resolved.appended.isEmpty {
      report.append(L10n.t("main.exportReportAppended", ["count": String(resolved.appended.count), "pages": resolved.appended.prefix(5).joined(separator: ", ")], count: resolved.appended.count))
    }

    let configLocale = config?.configuration["locale"]?.stringValue ?? ""
    let docLanguage = [book.language, facts.defaultLanguage, configLocale].first { !$0.isEmpty } ?? "en"
    var pages = try await ExportCollect.pages(window, origin: server.origin,
                                              .init(items: resolved.items, baseUrl: baseUrl, outsideLinks: book.outsideLinks, language: docLanguage),
                                              onPage: progress)
    let lang0 = [pages.first?.lang ?? "", book.language].first { !$0.isEmpty } ?? "en"
    // Read right after collecting: the pages of the site, not the documents the writers load later.
    let unfinished = window.unfinished.map { JSText.slice(WebURL($0).parts?.pathname ?? $0, 1) }
    if !unfinished.isEmpty {
      report.append(L10n.t("main.exportReportUnfinished", ["count": String(unfinished.count), "pages": unfinished.prefix(5).joined(separator: ", ")]))
    }
    var items = resolved.items
    let extras = ExportExtras.addBacklinksAndRegister(&pages, &items, backlinks: book.backlinks, tagIndex: book.tagIndex, facts: facts, lang: lang0)
    if extras.backlinks > 0 { report.append(L10n.t("main.exportReportBacklinks", ["count": String(extras.backlinks)], count: extras.backlinks)) }
    if extras.tags > 0 { report.append(L10n.t("main.exportReportRegister", ["count": String(extras.tags)], count: extras.tags)) }
    let stylesheets = try await window.evaluate("return [...document.querySelectorAll('head link[rel=\"stylesheet\"]')].map((l) => l.href);")
      .arrayValue?.compactMap(\.stringValue) ?? []
    let lang = lang0
    let pageTitle = config?.configuration["pageTitle"]?.stringValue ?? ""
    let title = [book.title, pageTitle].first { !$0.isEmpty } ?? NodePath.basename(request.project)
    let coverFound = try ExportExtras.coverPicture(project: request.project, buildRoot: server.copy.root, coverImage: book.coverImage)
    let cover = coverFound.picture
    if coverFound.ownMissing { report.append(L10n.t("main.exportReportCoverMissing", ["file": book.coverImage])) }
    func sum(_ key: KeyPath<CollectedPage.Counts, Int>) -> Int { pages.reduce(0) { $0 + $1.counts[keyPath: key] } }
    let replaced = sum(\.forms) + sum(\.frames) + sum(\.media) + sum(\.canvases)
    if replaced > 0 { report.append(L10n.t("main.exportReportReplaced", ["count": String(replaced)], count: replaced)) }
    if sum(\.outsideLinks) > 0 { report.append(L10n.t("main.exportReportOutsideLinks", ["count": String(sum(\.outsideLinks))], count: sum(\.outsideLinks))) }
    if sum(\.textLinks) > 0 { report.append(L10n.t("main.exportReportTextLinks", ["count": String(sum(\.textLinks))], count: sum(\.textLinks))) }
    if sum(\.unrenderedDiagrams) > 0 { report.append(L10n.t("main.exportReportUnrendered", ["count": String(sum(\.unrenderedDiagrams))], count: sum(\.unrenderedDiagrams))) }

    var files: [ExportFile] = []
    let now = Date()
    // In the document's language, like every other sentence in it.
    let meta = L10n.t(in: lang, "main.exportCoverDate", ["date": coverDate(now, lang: lang)])
    if request.formats.contains("pdf") {
      try Task.checkCancellation()
      progress(pages.count, pages.count, "PDF")
      let parts = DocumentHTML.Parts(lang: lang, title: title, subtitle: book.subtitle, author: book.author, meta: meta,
                                     coverImage: cover.map { "data:\($0.type);base64,\($0.data.base64EncodedString())" },
                                     stylesheets: stylesheets, items: items, pages: pages, toc: book.toc, pageSize: book.pageSize, landscape: book.landscape)
      let pdf = try await PDFWrite.write(window, server: server, parts,
                                         PdfMeta(title: title, subtitle: book.subtitle, author: book.author,
                                                 keywords: ExportExtras.bookKeywords(pageItems, facts: facts), lang: lang),
                                         otherFormats: request.formats.contains { $0 != "pdf" })
      files.append(ExportFile(name: "\(book.id).pdf", bytes: pdf.bytes))
      report.append(L10n.t("main.exportReportPdf", ["pages": String(pdf.pages), "outline": pdf.outline.map(String.init).joined(separator: "/"),
                                                    "mb": ExportExtras.mb(pdf.bytes.count)]))
    }
    if request.formats.contains("epub") || request.formats.contains("html") {
      try Task.checkCancellation()
      progress(pages.count, pages.count, request.formats.contains("epub") ? "ePub" : "HTML")
      let parts = BookParts(lang: lang, title: title, subtitle: book.subtitle, author: book.author,
                            identifier: ExportExtras.bookIdentifier(site: (baseUrl ?? "").isEmpty ? request.project : baseUrl!, bookId: book.id), modified: now)
      let content = try await BookContentPrep.prepare(window, server: server, .init(lang: lang, items: items, pages: pages, stylesheets: stylesheets, cover: cover))
      if request.formats.contains("epub") {
        let epub = try EpubPack.pack(content, parts)
        files.append(ExportFile(name: "\(book.id).epub", bytes: epub.bytes))
        report.append(L10n.t("main.exportReportEpub", ["chapters": String(epub.chapters), "images": String(epub.images), "mb": ExportExtras.mb(epub.bytes.count)]))
      }
      if request.formats.contains("html") {
        let html = try HtmlPack.pack(content, parts)
        files.append(ExportFile(name: "\(book.id).html", bytes: html.bytes))
        report.append(L10n.t("main.exportReportHtml", ["mb": ExportExtras.mb(html.bytes.count)]))
      }
      if content.drawings.formulas > 0 { report.append(L10n.t("main.exportReportFormulas", ["count": String(content.drawings.formulas)], count: content.drawings.formulas)) }
      if content.drawings.diagrams > 0 { report.append(L10n.t("main.exportReportDiagrams", ["count": String(content.drawings.diagrams)], count: content.drawings.diagrams)) }
      if content.counts.externalImages > 0 { report.append(L10n.t("main.exportReportExternalImages", ["count": String(content.counts.externalImages)], count: content.counts.externalImages)) }
      if content.counts.unsupportedImages > 0 { report.append(L10n.t("main.exportReportUnsupportedImages", ["count": String(content.counts.unsupportedImages)], count: content.counts.unsupportedImages)) }
    }
    report += networkLines(fetched: window.fetched, refused: window.refused)
    return ExportOutcome(files: files, report: report, missing: resolved.missing, appended: resolved.appended, pages: pageItems.count)
  }

  /// Where the order came from, one sentence per source (the keys are QuartzControl's
  /// `exportReportSource_${source}`).
  nonisolated static func sourceLine(_ source: String, count: Int) -> String {
    let n = ["count": String(count)]
    switch source {
    case "quartz-navigations": return L10n.t("main.exportReportSource_quartz-navigations", n, count: count)
    case "explorer": return L10n.t("main.exportReportSource_explorer", n, count: count)
    case "links": return L10n.t("main.exportReportSource_links", n, count: count)
    default: return L10n.t("main.exportReportSource_contentIndex", n, count: count)
    }
  }

  /// `toLocaleDateString(lang, { day: 'numeric', month: 'long', year: 'numeric' })`: both are ICU's
  /// pattern for the skeleton yMMMMd ("8. November 2026", "November 8, 2026").
  nonisolated static func coverDate(_ date: Date, lang: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: lang)
    formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
    return formatter.string(from: date)
  }

  /// What came from the network and what was refused, hosts of the web only: the window names
  /// anything else in parentheses.
  nonisolated static func networkLines(fetched: [(host: String, count: Int)], refused: [(key: String, count: Int)]) -> [String] {
    func webHosts(_ hosts: [String]) -> [String] {
      var seen = Set<String>()
      return hosts.filter { !JSText.startsWith($0, "(") && seen.insert($0).inserted }
    }
    var lines: [String] = []
    let from = webHosts(fetched.map(\.host))
    if !from.isEmpty { lines.append(L10n.t("main.exportReportNetwork", ["hosts": from.prefix(6).joined(separator: ", ")])) }
    if !refused.isEmpty {
      // The key is "<type> <host>"; split(' ')[1] as in JavaScript.
      let hosts = webHosts(refused.map { key, _ in
        let parts = key.components(separatedBy: " ")
        return parts.count > 1 ? parts[1] : "undefined"
      })
      lines.append(L10n.t("main.exportReportRefused", ["count": String(refused.reduce(0) { $0 + $1.count }), "hosts": hosts.prefix(6).joined(separator: ", ")], count: refused.reduce(0) { $0 + $1.count }))
    }
    return lines
  }

  /// `readSitePages`: the pages of the current build for the book editor, read like an export
  /// reads them - a copy of the build, the export window, the navigation as rendered.
  public static func sitePages(project: String, root: String, language: String, runtime: RuntimeLocation = .current) async throws -> SitePages {
    let buildDir = ProjectPrefsStore.read(project: project).buildDirectory(project: project)
    if !Posix.exists(buildDir) { throw PublishFailure(L10n.t("main.deployNoBuild", ["dir": buildDir])) }
    let scripts = try ExportWindow.pageScripts(location: runtime)
    let server = try await SiteServer.start(try SiteCopy.make(from: buildDir))
    defer { server.close() }
    let facts = try SiteFacts.read(root: server.copy.root)
    let window = ExportWindow(origin: server.origin, size: CGSize(width: 1200, height: 900), pageScripts: scripts)
    defer { window.close() }
    try await window.prepare()
    let nav = try await ExportCollect.navigationOrder(window, origin: server.origin, facts: facts, language: language)
    return SitePages(facts: facts, navigation: nav, root: root, language: language)
  }
}
