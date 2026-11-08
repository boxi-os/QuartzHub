import Foundation

/// The two steps of `collect.ts` that need the export window: the site's order as its navigation
/// renders it, and every page of the book loaded and extracted. The pure halves are
/// `NavigationOrder` and `ExportModel`.
@MainActor
public enum ExportCollect {
  /// How long a page may take to settle (QuartzControl's SETTLE_MS).
  public static let settleMs = 15_000

  /// `readNavigationOrder`: the start page of the language, settled with its navigation, read.
  public static func navigationOrder(_ window: ExportWindow, origin: String, facts: SiteFacts, language: String) async throws -> NavigationOrder {
    try await window.load("\(origin)/\(facts.languageHome(language))")
    let settled = try await window.run("settlePage", [.object(JSONObject([("navigation", .bool(true)), ("timeoutMs", .number(Double(settleMs)))]))])
    let nav = try await window.run("readNavigation", [])
    return NavigationOrder(source: nav["source"]?.stringValue ?? "none", hrefs: nav["hrefs"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                           complete: settled["navigation"] == .bool(true), facts: facts)
  }

  public struct Options: Sendable {
    public var items: [DocItem]
    public var baseUrl: String?
    /// "site" or "text".
    public var outsideLinks: String
    /// The document's language, for the sentences that replace forms, frames and media.
    public var language: String

    public init(items: [DocItem], baseUrl: String?, outsideLinks: String, language: String) {
      self.items = items
      self.baseUrl = baseUrl
      self.outsideLinks = outsideLinks
      self.language = language
    }
  }

  /// `collectPages`: every page item, loaded, settled and extracted in order. Stops at the first page
  /// that does not load or has no article. `onPage(done, total, slug)` before each page and once at
  /// the end with an empty slug.
  public static func pages(_ window: ExportWindow, origin: String, _ options: Options,
                           onPage: (Int, Int, String) -> Void = { _, _, _ in }) async throws -> [CollectedPage] {
    let pages: [(slug: String, level: Int)] = options.items.compactMap { if case .page(let slug, let level) = $0 { (slug, level) } else { nil } }
    let inBook = pages.map { JSONValue.string($0.slug) }
    let lang = options.language
    let texts = JSONValue.object(JSONObject([
      ("form", .string(L10n.t(in: lang, "main.docForm"))), ("frame", .string(L10n.t(in: lang, "main.docFrame"))),
      ("media", .string(L10n.t(in: lang, "main.docMedia"))), ("canvas", .string(L10n.t(in: lang, "main.docCanvas"))),
      ("noUrl", .object(JSONObject([
        ("form", .string(L10n.t(in: lang, "main.docFormNoUrl"))), ("frame", .string(L10n.t(in: lang, "main.docFrameNoUrl"))),
        ("media", .string(L10n.t(in: lang, "main.docMediaNoUrl"))), ("canvas", .string(L10n.t(in: lang, "main.docCanvasNoUrl")))
      ])))
    ]))
    var out: [CollectedPage] = []
    for (i, page) in pages.enumerated() {
      try Task.checkCancellation()
      onPage(i, pages.count, page.slug)
      do {
        try await window.load("\(origin)/\(page.slug)")
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw PublishFailure(L10n.t("main.exportPageFailed", ["slug": page.slug, "reason": reason(error)]))
      }
      _ = try await window.run("settlePage", [.object(JSONObject([("navigation", .bool(false)), ("timeoutMs", .number(Double(settleMs)))]))])
      var args = JSONObject([
        ("slug", .string(page.slug)), ("level", .number(Double(page.level))),
        ("signpost", .bool(page.level == 1 && ExportModel.isFolderIndex(page.slug))),
        ("inBook", .array(inBook)), ("outsideLinks", .string(options.outsideLinks))
      ])
      // undefined in QuartzControl when the config has none: JSON leaves it out.
      if let base = options.baseUrl { args["baseUrl"] = .string(base) }
      args["texts"] = texts
      let extracted: JSONValue
      do {
        extracted = try await window.run("extractArticle", [.object(args)], helpers: ["slugFromPathname", "anchorFor", "outsideUrl"])
      } catch let failure as ExportWindow.ScriptFailure where failure.description.contains("no <article>") {
        throw PublishFailure(L10n.t("main.exportNoArticle", ["slug": page.slug]))
      }
      out.append(collected(extracted, level: page.level))
    }
    onPage(pages.count, pages.count, "")
    return out
  }

  /// What extractArticle answered, as a collected page at its level.
  nonisolated static func collected(_ value: JSONValue, level: Int) -> CollectedPage {
    var counts = CollectedPage.Counts()
    let c = value["counts"]
    let n = { (key: String) in Int(c?[key]?.numberValue ?? 0) }
    counts.outsideLinks = n("outsideLinks")
    counts.textLinks = n("textLinks")
    counts.forms = n("forms")
    counts.frames = n("frames")
    counts.media = n("media")
    counts.canvases = n("canvases")
    counts.unrenderedDiagrams = n("unrenderedDiagrams")
    return CollectedPage(slug: value["slug"]?.stringValue ?? "", title: value["title"]?.stringValue ?? "", lang: value["lang"]?.stringValue ?? "",
                         html: value["html"]?.stringValue ?? "", images: value["images"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                         level: level, counts: counts)
  }

  /// An error as `(err as Error).message` would read it.
  nonisolated static func reason(_ error: Error) -> String {
    if let failure = error as? PublishFailure { return failure.description }
    return (error as NSError).localizedDescription
  }
}
