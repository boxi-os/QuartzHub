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
      VStack(alignment: .leading, spacing: Spacing.xxs) { content() }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Spacing.s)
    .padding(.vertical, Spacing.xs + 2)
    .background(kind.tint.opacity(0.12), in: .rect(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }
}

extension Callout where Content == Text {
  init(_ kind: Kind, _ text: String) {
    self.init(kind) { Text(text) }
  }
}

// MARK: - PageTabs

/// The tabs of a page (Konfiguration, Plugins, Layout, Stile): one segmented control centred under
/// the toolbar, in a bar of its own (`safeAreaBar`, the scroll edge effect runs under it). When the
/// segments do not fit, a menu with the tab's name; the same rule on every page.
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
  func pageTabs(_ tabs: [PageTabs.Tab], selection: Binding<String>, identifier: String) -> some View {
    safeAreaBar(edge: .top, spacing: 0) {
      PageTabs(tabs: tabs, selection: selection, identifier: identifier)
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
    .onGeometryChange(for: Bool.self) { $0.size.width >= FormWidth.sideBySide } action: { next in
      withAnimation(Motion.layout(reduce: reduceMotion)) { wide = next }
    }
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
