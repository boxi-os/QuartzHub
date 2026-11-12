import AppKit
import QuartzHubCore
import SwiftUI
import WebKit

/// What the editor beside the preview has selected (QuartzControl's `PreviewHighlight`).
struct PreviewHighlight: Equatable {
  var selector: String
  /// The entry as the editor's list names it.
  var name: String
  /// How many entries of the config the selector matches; above one, the entry cannot be told apart.
  var matches: Int
  var ownClass: Bool
  /// The pages that show the entry, when the editor knows them.
  var pages: [String]?

  static func == (a: Self, b: Self) -> Bool {
    a.selector == b.selector && a.name == b.name && a.matches == b.matches && a.ownClass == b.ownClass && a.pages == b.pages
  }
}

/// A page the editor sends the preview to ("In der Vorschau zeigen"); a new `nonce` goes again.
struct PreviewGoTo: Equatable {
  var page: String
  var nonce = UUID()
}

/// The project's real site beside a plugin editor (QuartzControl's `components/SitePreview.tsx`):
/// the dev server's page, rendered at a real device width and scaled into the column, with the
/// selected component marked by QuartzControl's own script (`PreviewScript`).
///
/// Nothing here reloads after a save: every config write makes the dev server rebuild, and Quartz's
/// page reloads itself over its websocket. A server started here takes the options of Vorschau &
/// Build, so the two pages do not start servers on different ports.
struct EditorPreview: View {
  let project: ProjectContext
  let hint: String?
  let highlight: PreviewHighlight?
  var onAssignClass: (() -> Void)?
  var goTo: PreviewGoTo?

  @SceneStorage private var page: String
  @SceneStorage private var modeID: String
  @SceneStorage private var zoom: Bool
  @SceneStorage private var decidedFor: String?
  @State private var draft = ""
  @State private var nonce = 0
  @State private var report: PreviewMarks.Report?
  @State private var reportFrame = ""
  @State private var starting = false
  @State private var hadSelection = false
  @State private var sentenceRound = 0
  @State private var breakpoints = (tablet: FrameBreakpointWidths.defaults.tablet, mobile: FrameBreakpointWidths.defaults.mobile)
  @FocusState private var pageFocused: Bool

  /// `prefix`: one per editor, for the remembered page, width and zoom.
  init(project: ProjectContext, prefix: String, hint: String? = nil, highlight: PreviewHighlight?, onAssignClass: (() -> Void)? = nil,
       goTo: PreviewGoTo? = nil) {
    self.project = project
    self.hint = hint
    self.highlight = highlight
    self.onAssignClass = onAssignClass
    self.goTo = goTo
    _page = SceneStorage(wrappedValue: "", "\(prefix).previewPage")
    _modeID = SceneStorage(wrappedValue: PreviewWidth.Mode.desktop.rawValue, "\(prefix).previewMode")
    _zoom = SceneStorage(wrappedValue: false, "\(prefix).previewZoom")
    _decidedFor = SceneStorage("\(prefix).previewDecided")
  }

  private var status: BuildService.ServerStatus { BuildMonitor.shared.status(project.id) }
  private var mode: PreviewWidth.Mode { PreviewWidth.Mode(rawValue: modeID) ?? .desktop }
  private var options: BuildService.ServerOptions { status.options ?? BuildServerMemory.shared[project.id].options }
  private var base: String { "http://\(options.host.isEmpty ? "localhost" : options.host):\(options.port)" } // not a file path
  private var path: String { String(page.drop { $0 == "/" }) }
  private var frameKey: String { "\(base)/\(path)#\(nonce)" }
  private var width: Double {
    PreviewWidth.points(mode, widths: breakpoints) ?? ScaledSite.desktopWidth(tablet: breakpoints.tablet)
  }

  /// The report counts only while it comes from the frame shown and for the selector shown.
  private var current: PreviewMarks.Report? {
    guard let report, reportFrame == frameKey, report.selector == highlight?.selector else { return nil }
    return report
  }

  private var deciding: Bool {
    guard let highlight, highlight.pages != nil else { return false }
    return decidedFor != highlight.selector
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(L10n.t("sitePreview.title"), systemImage: "play.display").font(.headline)
        Spacer()
        if status.state == .running, options.host.isEmpty {
          Button { nonce += 1 } label: { Label(L10n.t("buildServer.reloadPreview"), systemImage: "arrow.clockwise") }
        }
        if status.state == .running || status.state == .starting {
          Button { stop() } label: { Label(L10n.t("sitePreview.stop"), systemImage: "stop.fill") }
            .help(L10n.t("sitePreview.stopHint"))
        }
      }
      if let hint { Note(hint) }
      content
    }
    .padding(12)
    .task { loadBreakpoints() }
    .onAppear { draft = page }
    .onChange(of: highlight?.selector) { _, selector in
      if selector != nil { hadSelection = true } else if hadSelection { decidedFor = nil }
    }
    .onChange(of: current) { _, report in decide(report) }
    // A page asked for is the page: the jump to a page with the entry does not undo it.
    .onChange(of: goTo) { _, target in
      guard let target else { return }
      page = target.page
      draft = target.page
      decidedFor = highlight?.selector
    }
    // Said once it has held for a moment: a page's first report can come before its scripts have
    // built what is marked (quartz-forms renders its forms on the page), and the jump to a page
    // with a form was followed by „… kommt auf dieser Seite nicht vor.“, then „Markiert“
    // (measured 2026-11-09).
    .onChange(of: sentence) { _, text in
      sentenceRound += 1
      let round = sentenceRound
      guard let text else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(800))
        if round == sentenceRound { Announce.post(text) }
      }
    }
  }

  @ViewBuilder private var content: some View {
    if status.state != .running {
      VStack(alignment: .leading, spacing: 8) {
        Text(status.state == .starting ? L10n.t("sitePreview.starting") : L10n.t("sitePreview.notRunning")).foregroundStyle(.secondary)
        if let error = ProjectAttention.serverErrorText(status) { Callout(.error, error) }
        if status.state == .stopped || status.state == .error {
          Button { start() } label: { Label(L10n.t("sitePreview.start"), systemImage: "play.fill") }
            .disabled(starting)
            .accessibilityIdentifier("preview.start")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else if !options.host.isEmpty {
      Text(L10n.t("sitePreview.remote")).foregroundStyle(.secondary)
    } else {
      HStack(spacing: 8) {
        Text(verbatim: "\(base)/").foregroundStyle(.secondary).lineLimit(1)
        TextField(L10n.t("sitePreview.page"), text: $draft, prompt: Text(L10n.t("sitePreview.pagePlaceholder")))
          .textFieldStyle(.roundedBorder)
          // With a prompt the title did not reach the accessibility tree: the field had only its
          // placeholder, and filled it was read as "kontakt, Textfeld" (measured 2026-11-09).
          .accessibilityLabel(L10n.t("sitePreview.page"))
          .focused($pageFocused)
          .onSubmit(commitPage)
          .onChange(of: pageFocused) { _, now in if !now { commitPage() } }
          .accessibilityIdentifier("preview.page")
        Picker(L10n.t("buildServer.viewport.label"), selection: $modeID) {
          ForEach(PreviewWidth.Mode.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        if highlight != nil {
          Toggle(L10n.t("sitePreview.zoom"), isOn: $zoom).toggleStyle(.checkbox).fixedSize()
        }
      }
      GeometryReader { geometry in
        let box = geometry.size
        let scale = box.width > 0 ? min(1, box.width / width) : 1
        let frameHeight = box.height / scale
        let zoomed = zoom && highlight != nil && box.width > 0 ? current?.rect.map {
          PreviewMarks.zoom(onto: $0, frame: (width, frameHeight), box: (box.width, box.height), baseScale: scale)
        } : nil
        let shown = zoomed?.scale ?? scale
        MarkedSite(url: URL(string: "\(base)/\(path)")!, frameKey: frameKey, label: L10n.t("sitePreview.title"),
                   size: CGSize(width: width, height: frameHeight),
                   cut: CGRect(x: zoomed?.x ?? 0, y: zoomed?.y ?? 0, width: box.width / shown, height: box.height / shown),
                   offsetX: width * shown < box.width ? (box.width - width * shown) / 2 : 0,
                   selector: highlight?.selector, focus: zoom) { report, frame in
          self.report = report
          reportFrame = frame
        }
        .id(frameKey)
        .overlay(alignment: .bottomTrailing) {
          Text(L10n.t("sitePreview.scaled", ["width": String(Int(width)), "percent": String(Int((shown * 100).rounded()))]))
            .font(.caption2).padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4)).padding(6)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      .frame(minHeight: 120)
      // The sentence first, the site takes what is left: with 240 pt for the site, a sentence on
      // two lines ran out of the pane's 365 pt at 1200×800 and its second line was cut off; with
      // 160 pt, beside "Eigene Klasse vergeben" in Zusätzliche Inhalte' 310 pt pane, it was cut
      // after one (measured 2026-11-09). A larger pane there leaves the list of boxes one row.
      HStack(spacing: 8) {
        if let sentence { Text(sentence).font(.callout).foregroundStyle(.secondary) }
        if let highlight, highlight.matches > 1, let onAssignClass {
          Button(L10n.t("sitePreview.assignClass"), action: onAssignClass)
        }
      }
      .layoutPriority(1)
    }
  }

  /// The sentence under the preview (`markSentence`); nil while there is nothing to say.
  private var sentence: String? {
    guard let highlight, let current, !deciding else { return nil }
    let name = ["name": highlight.name]
    switch PreviewMarks.sentence(current, matches: highlight.matches, ownClass: highlight.ownClass, pages: highlight.pages, page: page) {
    case .notFound: return L10n.t("sitePreview.markNotFound", name)
    case .stale: return L10n.t("sitePreview.markStale", name)
    case .hidden: return L10n.t("sitePreview.markHidden", name)
    case .marked: return L10n.t("sitePreview.marked", name)
    case .shared(let count): return L10n.t("sitePreview.markShared", ["name": highlight.name, "count": String(count)], count: count)
    case .noClass(let count): return L10n.t("sitePreview.markNoClass", ["name": highlight.name, "count": String(count)], count: count)
    }
  }

  /// The first report since the selection changed decides whether the preview goes to a page that
  /// has the entry; later ones do not, so a page opened by hand stays.
  private func decide(_ report: PreviewMarks.Report?) {
    guard deciding, let report, let highlight, let pages = highlight.pages else { return }
    decidedFor = highlight.selector
    if report.found > 0 || pages.isEmpty || pages.contains(where: { PreviewMarks.samePage($0, page) }) { return }
    guard let target = PreviewMarks.nearestPage(pages, to: page) else { return }
    page = target
    draft = target
    Announce.post(L10n.t("sitePreview.jumped", ["page": "/\(target)", "name": highlight.name]))
  }

  private func commitPage() {
    if draft != page { page = draft }
  }

  private func loadBreakpoints() {
    let widths = LayoutFrames.widths(project: project.path)
    breakpoints = (widths.tablet, widths.mobile)
  }

  private func start() {
    starting = true
    let project = project, options = BuildServerMemory.shared[project.id].options
    Task {
      _ = await AppServices.shared.builds.startServer(projectId: project.id, project: project.path, options: options)
      starting = false
    }
  }

  private func stop() {
    let id = project.id
    Task { await AppServices.shared.builds.stopServer(id) }
  }
}
