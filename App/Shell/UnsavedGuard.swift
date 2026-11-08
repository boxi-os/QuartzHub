import AppKit
import QuartzHubCore
import SwiftUI

/// "This page has edits that are not on disk", per project window, so leaving it asks first
/// (QuartzControl's `unsavedGuard.tsx` and `saveCommand.ts`). It is not a draft store: confirmed,
/// the edits are gone; what changes is that the user is asked.
///
/// A page registers while it is dirty (`.unsavedChanges(_:save:)`), with its save when it has one
/// to offer right now. Four doors ask: the sidebar, a link on a page (`openPage`), closing the
/// window, and quitting. QuartzControl had one window, so its doors were the sidebar and the way
/// back to the project list; here closing a project window is the way edits get lost.
///
/// Three answers where the page can save, two where it cannot; the safe one first, and
/// "Änderungen verwerfen" is the destructive one. A save that fails stays on the page, where its
/// error is shown.
@MainActor @Observable
final class UnsavedGuard {
  struct Page {
    let token: UUID
    let save: (@MainActor () async -> Bool)?
  }

  private(set) var page: Page?
  @ObservationIgnored weak var window: NSWindow? {
    didSet { window?.isDocumentEdited = page != nil }
  }
  @ObservationIgnored private var asking = false
  /// Retained here: a window holds its delegate weakly.
  @ObservationIgnored var closeDelegate: CloseGuardDelegate?

  /// Every project window's guard, for the question at quit.
  private static var all: [WeakGuard] = []
  private struct WeakGuard { weak var value: UnsavedGuard? }

  init() {
    Self.all.removeAll { $0.value == nil }
    Self.all.append(WeakGuard(value: self))
  }

  var dirty: Bool { page != nil }

  func register(_ token: UUID, save: (@MainActor () async -> Bool)?) {
    page = Page(token: token, save: save)
    // The dot in the close button: the platform's own way of saying "not saved".
    window?.isDocumentEdited = true
  }

  /// Only what this page registered: the incoming page may already have its own.
  func clear(_ token: UUID) {
    guard page?.token == token else { return }
    page = nil
    window?.isDocumentEdited = false
  }

  /// true: go on (nothing unsaved, discarded, or saved). A second door while the question is up
  /// opens no second one.
  func confirmLeave() async -> Bool {
    guard let page else { return true }
    guard !asking else { return false }
    asking = true
    defer { asking = false }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = page.save != nil ? L10n.t("projectLayout.unsavedWarningWithSave") : L10n.t("projectLayout.unsavedWarning")
    alert.addButton(withTitle: L10n.t("common.cancel"))
    if page.save != nil { alert.addButton(withTitle: L10n.t("projectLayout.unsavedSave")) }
    let discard = alert.addButton(withTitle: L10n.t("projectLayout.unsavedLeave"))
    discard.hasDestructiveAction = true
    let response: NSApplication.ModalResponse
    if let window {
      window.makeKeyAndOrderFront(nil)
      response = await alert.beginSheetModal(for: window)
    } else {
      response = alert.runModal()
    }
    switch response {
    case .alertFirstButtonReturn:
      return false
    case .alertSecondButtonReturn where page.save != nil:
      guard let save = page.save, await save() else { return false }
      return true
    default:
      self.page = nil
      window?.isDocumentEdited = false
      return true
    }
  }

  /// At quit: every window with edits asks in turn; one "Abbrechen" keeps the app running.
  static func confirmAll() async -> Bool {
    for entry in all {
      guard let unsaved = entry.value, unsaved.dirty else { continue }
      if await !unsaved.confirmLeave() { return false }
    }
    return true
  }
}

/// The window's close button asks too. SwiftUI owns the window's delegate, so this one stands in
/// front of it: `windowShouldClose` is answered here, everything else goes on to SwiftUI's.
final class CloseGuardDelegate: NSObject, NSWindowDelegate {
  weak var original: NSWindowDelegate?
  weak var unsaved: UnsavedGuard?

  init(original: NSWindowDelegate?, unsaved: UnsavedGuard) {
    self.original = original
    self.unsaved = unsaved
  }

  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || original?.responds(to: selector) == true
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    original?.responds(to: selector) == true ? original : nil
  }

  @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let unsaved, unsaved.dirty else { return original?.windowShouldClose?(sender) ?? true }
    Task { @MainActor in
      // `close()`, not `performClose`: the question was this one.
      if await unsaved.confirmLeave() { sender.close() }
    }
    return false
  }
}

/// Hands the project window to its guard and puts the close question in front of SwiftUI's
/// delegate, once per window.
struct UnsavedWindowHook: NSViewRepresentable {
  let unsaved: UnsavedGuard

  func makeNSView(context: Context) -> HookView {
    let view = HookView()
    view.unsaved = unsaved
    return view
  }

  func updateNSView(_ view: HookView, context: Context) {}

  final class HookView: NSView {
    weak var unsaved: UnsavedGuard?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window, let unsaved else { return }
      unsaved.window = window
      if window.delegate !== unsaved.closeDelegate {
        let proxy = CloseGuardDelegate(original: window.delegate, unsaved: unsaved)
        unsaved.closeDelegate = proxy
        window.delegate = proxy
      }
    }
  }
}

/// File ▸ Speichern, ⌘S: whatever the frontmost page offers to save. Greyed out when it has
/// nothing, which QuartzControl's Electron menu could not do (its ⌘S stayed enabled and idle).
struct SaveCommand: Commands {
  @FocusedValue(\.pageSave) private var save

  var body: some Commands {
    let _ = AppAppearance.shared.revision
    // After "Öffnen", not in `.saveItem`: SwiftUI leaves that group out of an app without
    // documents, whether replaced, before or after it (measured 2026-11-08, macOS 27: no item).
    CommandGroup(after: .newItem) {
      Divider()
      Button(L10n.t("common.save")) {
        if let save { Task { _ = await save.run() } }
      }
      .keyboardShortcut("s", modifiers: .command)
      .disabled(save == nil)
    }
  }
}

struct PageSaveAction {
  let run: @MainActor () async -> Bool
}

extension FocusedValues {
  /// The frontmost page's save, while it has something to save and no save is running.
  @Entry var pageSave: PageSaveAction?
}

extension EnvironmentValues {
  @Entry var unsavedGuard: UnsavedGuard?
}

extension View {
  /// A page that edits a document: registered with its window's guard while `dirty`, and its save
  /// on ⌘S. `save` nil while there is nothing it can do (a save running).
  func unsavedChanges(_ dirty: Bool, save: (@MainActor () async -> Bool)?) -> some View {
    modifier(UnsavedChanges(dirty: dirty, save: save))
  }
}

private struct UnsavedChanges: ViewModifier {
  let dirty: Bool
  let save: (@MainActor () async -> Bool)?

  @Environment(\.unsavedGuard) private var unsaved
  @State private var token = UUID()

  func body(content: Content) -> some View {
    content
      .onChange(of: dirty, initial: true) { _, dirty in sync(dirty) }
      .onChange(of: save == nil) { sync(dirty) }
      .onDisappear { unsaved?.clear(token) }
      .focusedSceneValue(\.pageSave, dirty ? save.map(PageSaveAction.init) : nil)
  }

  private func sync(_ dirty: Bool) {
    if dirty { unsaved?.register(token, save: save) } else { unsaved?.clear(token) }
  }
}

/// The visible half: a page whose Save has work waiting says so (QuartzControl's `UnsavedBadge`).
struct UnsavedBadge: View {
  var body: some View {
    Label {
      Text(L10n.t("projectLayout.unsavedBadge"))
    } icon: {
      Image(systemName: "circle.fill").font(.system(size: 6))
    }
    .labelStyle(.titleAndIcon)
    .font(.callout)
    .foregroundStyle(.orange)
  }
}
