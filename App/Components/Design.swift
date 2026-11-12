import QuartzHubCore
import SwiftUI

// The measures every page shares (decisions/ui-ueberarbeitung.md, Bausteine): one set of spacings,
// one set of curves, the widths of a form. A page that needs another value says why.

/// Spacings in points. `page` is the margin of a page's content.
enum Spacing {
  static let xxs: CGFloat = 4
  static let xs: CGFloat = 8
  static let s: CGFloat = 12
  static let m: CGFloat = 16
  static let l: CGFloat = 20
  static let xl: CGFloat = 24
  static let page: CGFloat = 20
}

/// The widths of a settings form: one column up to `column`; from `sideBySide` of room on, the
/// sections' headings move beside them, up to `wide` (variant C).
enum FormWidth {
  static let column: CGFloat = 880
  static let sideBySide: CGFloat = 900
  static let wide: CGFloat = 1120
  /// The heading column in the wide form.
  static let heading: CGFloat = 220
}

/// Curves: springs, nothing longer than about 0.35 s. With Reduce Motion a change of layout jumps
/// and only what appears or disappears fades.
enum Motion {
  static let layout = Animation.smooth(duration: 0.3)
  static let quick = Animation.snappy(duration: 0.2)

  static func layout(reduce: Bool) -> Animation? { reduce ? nil : layout }
}

extension View {
  /// Follows a value worked out from the view's width: a layout that changes with the width.
  /// Changes in the view's first half second are taken as they are, later ones are animated.
  ///
  /// A page that appears is measured several times before its width settles: Konfiguration at
  /// 1680 pt got 180, 960, then 1170 pt, the Übersicht one, two, then three columns (logged
  /// 2026-11-12). Animated from the start, every page and tab change in a wide window drew the
  /// narrow layout first and then moved into the wide one; with only the first value unanimated,
  /// it still moved from 180 to 960.
  func onWidthChange<Value: Equatable & Sendable>(_ value: @escaping @Sendable (CGFloat) -> Value, reduceMotion: Bool,
                                       perform action: @escaping (Value) -> Void) -> some View {
    modifier(WidthChange(value: value, reduceMotion: reduceMotion, action: action))
  }
}

private struct WidthChange<Value: Equatable & Sendable>: ViewModifier {
  /// How long a view that appeared counts as settling.
  static var settling: TimeInterval { 0.5 }

  let value: @Sendable (CGFloat) -> Value
  let reduceMotion: Bool
  let action: (Value) -> Void
  @State private var appeared = Date.distantFuture

  func body(content: Content) -> some View {
    content
      .onAppear { appeared = .now }
      .onGeometryChange(for: Value.self) { [value] in value($0.size.width) } action: { next in
        if Date.now.timeIntervalSince(appeared) > Self.settling {
          withAnimation(Motion.layout(reduce: reduceMotion)) { action(next) }
        } else {
          var settling = Transaction()
          settling.disablesAnimations = true
          withTransaction(settling) { action(next) }
        }
      }
  }
}

// MARK: - Callout

/// A note, a warning or an error in one form: symbol, text, the colour of its kind as a tint of the
/// background. To replace `Note`, `Warning`, `ErrorLine` and the coloured bands, page by page.
struct Callout<Content: View>: View {
  enum Kind {
    case info, warning, error

    var symbol: String {
      switch self {
      case .info: "info.circle.fill"
      case .warning: "exclamationmark.triangle.fill"
      case .error: "exclamationmark.octagon.fill"
      }
    }

    var tint: Color {
      switch self {
      case .info: .accentColor
      case .warning: .orange
      case .error: .red
      }
    }
  }

  let kind: Kind
  @ViewBuilder var content: () -> Content

  init(_ kind: Kind, @ViewBuilder content: @escaping () -> Content) {
    self.kind = kind
    self.content = content
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
      Image(systemName: kind.symbol).foregroundStyle(kind.tint).accessibilityHidden(true)
      // Selectable, so a path or a reason in a message can be copied.
      VStack(alignment: .leading, spacing: Spacing.xxs) { content() }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Spacing.s)
    .padding(.vertical, Spacing.xs + 2)
    .background(kind.tint.opacity(0.12), in: .rect(cornerRadius: 10))
    // Contain, not combine: a callout may carry a button, and combined it would be lost.
    .accessibilityElement(children: .contain)
  }
}

extension Callout where Content == Text {
  init(_ kind: Kind, _ text: String) {
    self.init(kind) { Text(text) }
  }
}

/// What is wrong with the value just typed, directly below its field: a line, not a box. A box
/// under every field of a sheet or the inspector weighed more than the field itself; a message
/// about the state of a thing, not about an entry, is a `Callout`.
struct FieldProblem: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Label {
      Text(text).textSelection(.enabled)
    } icon: {
      Image(systemName: Callout<EmptyView>.Kind.error.symbol)
    }
    .font(.caption)
    .foregroundStyle(.red)
    .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Surface

/// The surface of a card, a figure and a workspace head: the same grey as a grouped Form's section,
/// so a page of cards and a page of forms read alike. Measured against the window background
/// (2026-11-12): a section is 248 on 255 in light and 49 on 40 in dark; `.fill.quaternary` is 248
/// and 46, `.fill.quinary` was 253 and 42 and left the cards barely visible on white.
enum Surface {
  static let card = AnyShapeStyle(.fill.quaternary)
}

// MARK: - Save

/// Speichern in the toolbar: enabled only with something to save, no "Gespeichert" beside it (the
/// dot in the close button says that).
struct SaveButton: View {
  let saving: Bool
  let disabled: Bool
  let identifier: String
  let action: () async -> Void

  var body: some View {
    Button {
      Task { await action() }
    } label: {
      Label(saving ? L10n.t("common.saving") : L10n.t("common.save"), systemImage: "square.and.arrow.down")
    }
    .labelStyle(.titleOnly)
    .disabled(disabled)
    .accessibilityIdentifier(identifier)
  }
}

// MARK: - PageTabs

/// The tabs of a page (Konfiguration, Plugins, Layout, Stile): one segmented control centred under
/// the toolbar, in a row of its own above the content. When the segments do not fit, a menu with
/// the tab's name; the same rule on every page.
struct PageTabs: View {
  struct Tab: Identifiable {
    let id: String
    let title: String
  }

  let tabs: [Tab]
  @Binding var selection: String
  let identifier: String

  private var picker: some View {
    Picker(L10n.t("common.viewSwitcher"), selection: $selection) {
      ForEach(tabs) { Text($0.title).tag($0.id) }
    }
    .labelsHidden()
    .accessibilityIdentifier(identifier)
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      picker.pickerStyle(.segmented).fixedSize()
      picker.pickerStyle(.menu).fixedSize()
    }
    .padding(.horizontal, Spacing.page)
    .padding(.vertical, Spacing.xs)
    .frame(maxWidth: .infinity)
  }
}

extension View {
  /// The page's tabs above its content, the same height and spacing on every page.
  ///
  /// A row above, not a `safeAreaBar`: the bar's inset does not reach an AppKit view, and the four
  /// Plugins editors (a `VSplitView`) drew their first lines under the tabs (seen at 1200 × 780).
  func pageTabs(_ tabs: [PageTabs.Tab], selection: Binding<String>, identifier: String) -> some View {
    VStack(spacing: 0) {
      PageTabs(tabs: tabs, selection: selection, identifier: identifier)
      self.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

// MARK: - Settings form (variant C)

extension EnvironmentValues {
  /// True once the form has room for its headings beside the sections.
  @Entry var settingsWide = false
}

/// A page's settings: the sections one under the other, up to `FormWidth.column` wide. From
/// `FormWidth.sideBySide` on, each section's heading and note stand to the left of its rows
/// (decision of 2026-11-12, variant C); the change of layout is animated.
///
/// Each section is a grouped `Form` of its own, sized to its rows: so the rows keep the platform's
/// look (label left, control right) while the heading can stand beside them, which one `Form`
/// cannot do (measured in decisions/ui-ueberarbeitung.md, Formulare).
struct SettingsForm<Content: View>: View {
  @ViewBuilder var content: () -> Content

  @State private var wide = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Group(subviews: content()) { sections in
          ForEach(sections) { section in
            // Beside each other the sections need a line between them; one under the other the
            // groups' own spacing separates them.
            if wide, section.id != sections.first?.id { Divider().padding(.horizontal, Spacing.page) }
            section
          }
        }
      }
        .environment(\.settingsWide, wide)
        .frame(maxWidth: wide ? FormWidth.wide : FormWidth.column)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity)
    }
    .onWidthChange({ $0 >= FormWidth.sideBySide }, reduceMotion: reduceMotion) { wide = $0 }
  }
}

/// One section of a `SettingsForm`: its heading with the page's symbol, an optional state beside
/// it (a `StateBadge`: "Läuft", "Update verfügbar"), an optional note, its rows.
struct SettingsSection<Content: View, Accessory: View>: View {
  let title: String
  var symbol: String?
  var note: String?
  /// For tests, on the heading: it is always there, and a Form's own identifier does not reach the
  /// accessibility tree.
  var identifier: String?
  @ViewBuilder var content: () -> Content
  @ViewBuilder var accessory: () -> Accessory

  @Environment(\.settingsWide) private var wide

  init(_ title: String, symbol: String? = nil, note: String? = nil, identifier: String? = nil,
       @ViewBuilder content: @escaping () -> Content, @ViewBuilder accessory: @escaping () -> Accessory) {
    self.title = title
    self.symbol = symbol
    self.note = note
    self.identifier = identifier
    self.content = content
    self.accessory = accessory
  }

  var body: some View {
    let layout = wide
      ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
    layout {
      heading
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
        .frame(width: wide ? FormWidth.heading : nil, alignment: .leading)
        .padding(.leading, Spacing.page)
        .padding(.top, wide ? Spacing.l : Spacing.xs)
        // A long note beside a short group keeps its distance to the line under the section.
        .padding(.bottom, wide ? Spacing.l : 0)
        .zIndex(1)
      Form {
        Section { content() }
      }
      .formStyle(.grouped)
      // The page's background shows through; the group keeps its own.
      .scrollContentBackground(.hidden)
      .scrollDisabled(true)
      // The rows' height, inside the page's scroll view (not outside one: docs/conventions.md).
      .fixedSize(horizontal: false, vertical: true)
      // A grouped form keeps about 20 pt above and below its group, and `contentMargins` does not
      // change that (measured, neither for `.scrollContent` nor for all placements). Under its
      // heading the group moves up by part of it.
      .padding(.top, wide ? 0 : -Spacing.s)
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      // The state beside the heading in one column, under it in the narrow heading column.
      let row = wide ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s))
      row {
        Group {
          if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
        accessory().font(.callout).foregroundStyle(.secondary)
      }
      if let note {
        Text(note)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

extension SettingsSection where Accessory == EmptyView {
  init(_ title: String, symbol: String? = nil, note: String? = nil, identifier: String? = nil,
       @ViewBuilder content: @escaping () -> Content) {
    self.init(title, symbol: symbol, note: note, identifier: identifier, content: content) { EmptyView() }
  }
}

// MARK: - Workspace header

/// The head of a workspace (Layout ▸ Komponenten, Layout ▸ Frames): what is open, a few facts about
/// it, and under a line the controls that choose it. One look for both, not two copies.
struct WorkspaceHeader<Facts: View, Controls: View>: View {
  let symbol: String
  /// The kind of thing open, above its name ("Seitentyp", "Eigener Frame").
  let kicker: String
  let title: String
  @ViewBuilder var facts: () -> Facts
  @ViewBuilder var controls: () -> Controls

  init(symbol: String, kicker: String, title: String, @ViewBuilder facts: @escaping () -> Facts,
       @ViewBuilder controls: @escaping () -> Controls) {
    self.symbol = symbol
    self.kicker = kicker
    self.title = title
    self.facts = facts
    self.controls = controls
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      HStack(spacing: Spacing.s) {
        Image(systemName: symbol).font(.title3).foregroundStyle(.tint)
          .frame(width: 32, height: 32)
          .background(.tint.opacity(0.15), in: .rect(cornerRadius: 8))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
          Text(kicker).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
          Text(title).font(.title3.weight(.semibold))
        }
        Spacer(minLength: Spacing.xs)
        facts()
      }
      .accessibilityElement(children: .combine)
      Divider()
      controls()
    }
    .padding(Spacing.m)
    .background(Surface.card, in: .rect(cornerRadius: 12))
  }
}

// MARK: - Card

/// One tile of an overview (Übersicht, Layout ▸ Übersicht): its heading with the page's symbol and
/// a state, the one number or name it is about, and the way to the page that owns it. Cards stand
/// in a `CardGrid`, one column in a narrow window, up to three in a wide one.
struct Card<Content: View, Accessory: View, Footer: View>: View {
  let title: String
  var symbol: String?
  @ViewBuilder var content: () -> Content
  @ViewBuilder var accessory: () -> Accessory
  @ViewBuilder var footer: () -> Footer

  init(_ title: String, symbol: String? = nil, @ViewBuilder content: @escaping () -> Content,
       @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder footer: @escaping () -> Footer) {
    self.title = title
    self.symbol = symbol
    self.content = content
    self.accessory = accessory
    self.footer = footer
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        Group {
          if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
        Spacer(minLength: Spacing.xs)
        accessory().font(.callout).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: Spacing.xxs + 2) { content() }
        .labeledContentStyle(CardRow())
      Spacer(minLength: 0)
      footer()
    }
    .padding(Spacing.m)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Surface.card, in: .rect(cornerRadius: 12))
    .accessibilityElement(children: .contain)
  }
}

/// A fact in a card: its name muted on the left, the value on the right.
struct CardRow: LabeledContentStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
      configuration.label.foregroundStyle(.secondary)
      Spacer(minLength: Spacing.xs)
      configuration.content.multilineTextAlignment(.trailing).lineLimit(1)
    }
  }
}

/// Cards from 300 pt wide, as many columns as fit; a change of column count is animated.
struct CardGrid<Content: View>: View {
  @ViewBuilder var content: () -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var columns = 1

  var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.m, alignment: .top), count: columns),
              alignment: .leading, spacing: Spacing.m) {
      content()
    }
    .onWidthChange({ max(1, min(3, Int(($0 + Spacing.m) / (300 + Spacing.m)))) }, reduceMotion: reduceMotion) { columns = $0 }
  }
}

// MARK: - Panes

extension EnvironmentValues {
  /// The height `SplitPanes` gives its bottom pane, nil while it is folded: for content that cannot
  /// fill by itself (a DisclosureGroup's). Measuring the pane from inside it fed back into its own
  /// height and grew it without end (2026-11-12, the app at 99 % CPU).
  @Entry var paneHeight: CGFloat?
}

/// The bottom pane's height, handed to content that needs it as a number.
struct PaneHeight<Content: View>: View {
  @Environment(\.paneHeight) private var height
  @ViewBuilder var content: (CGFloat?) -> Content

  var body: some View { content(height) }
}

extension View {
  /// One pane of a workspace split: on the card surface, its content clipped to the card's corners.
  /// A list in it leaves its own background off, so the card shows through.
  func paneCard() -> some View {
    self
      .scrollContentBackground(.hidden)
      .background(Surface.card, in: .rect(cornerRadius: 12))
      .clipShape(.rect(cornerRadius: 12))
  }
}

/// Two panes of a workspace one above the other, with a grip between them that shows it can be
/// dragged: a `VSplitView`'s divider is a hairline between two areas of the same grey, and nobody
/// saw that the Plugins editors could be resized (user test, 2026-11-12). The position is the top
/// pane's share of the height, kept per window; a double click on the grip returns to `initial`.
/// Three panes are two splits, the second one the bottom pane of the first; the panes put
/// themselves on cards (`paneCard`). A bottom pane that folds away (the output under Vorschau &
/// Build) passes `collapsed`: then it keeps its own height, the top pane takes the rest and the grip
/// goes; the top pane stays the same view, so a web view in it is not loaded again.
struct SplitPanes<Top: View, Bottom: View>: View {
  static var grip: CGFloat { Spacing.s }

  @SceneStorage private var share: Double
  private let initial: Double
  private let topMin: CGFloat
  private let bottomMin: CGFloat
  private let top: Top
  private let bottom: Bottom
  private let collapsed: Bool
  @State private var dragFrom: CGFloat?
  @State private var hovering = false

  init(_ key: String, initial: Double, topMin: CGFloat, bottomMin: CGFloat, collapsed: Bool = false,
       @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
    self.collapsed = collapsed
    _share = SceneStorage(wrappedValue: initial, "split.\(key)")
    self.initial = initial
    self.topMin = topMin
    self.bottomMin = bottomMin
    self.top = top()
    self.bottom = bottom()
  }

  private func clamped(_ height: CGFloat, in available: CGFloat) -> CGFloat {
    max(min(height, available - bottomMin), min(topMin, available))
  }

  var body: some View {
    GeometryReader { geometry in
      let available = max(0, geometry.size.height - Self.grip)
      let height = clamped(available * share, in: available)
      VStack(spacing: 0) {
        top.frame(height: collapsed ? nil : height).frame(maxHeight: collapsed ? .infinity : nil)
        if !collapsed { grip(height: height, available: available) }
        bottom.frame(maxHeight: collapsed ? nil : .infinity)
          .environment(\.paneHeight, collapsed ? nil : available - height)
      }
      .coordinateSpace(.named("split"))
    }
  }

  private func grip(height: CGFloat, available: CGFloat) -> some View {
    let dragging = dragFrom != nil
    return Capsule()
      .fill(dragging || hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
      .frame(width: 40, height: 5)
      .frame(maxWidth: .infinity)
      .frame(height: Self.grip)
      .contentShape(Rectangle())
      .pointerStyle(.rowResize)
      .onHover { hovering = $0 }
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .named("split"))
          .onChanged { value in
            let from = dragFrom ?? height
            dragFrom = from
            guard available > 0 else { return }
            share = clamped(from + value.translation.height, in: available) / available
          }
          .onEnded { _ in dragFrom = nil }
      )
      .onTapGesture(count: 2) { share = initial }
      .help(L10n.t("common.splitGrip"))
      .accessibilityElement()
      .accessibilityLabel(L10n.t("common.splitGripName"))
      .accessibilityValue("\(Int((share * 100).rounded())) %")
      .accessibilityAdjustableAction { direction in
        guard available > 0 else { return }
        let step: CGFloat = direction == .increment ? 40 : -40
        share = clamped(height + step, in: available) / available
      }
  }
}
