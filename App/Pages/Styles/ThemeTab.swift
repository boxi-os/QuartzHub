import QuartzHubCore
import SwiftUI

/// Community-Themes with `@quartz-themes/core` 3 (docs/plan-themes-core-3.md, step 6): a list like
/// the marketplace's. On top Obsidian's built-in theme and a theme from another source, below
/// Obsidian's list with picture, name, author and modes. The project's theme is marked; its
/// settings and every theme's details are the inspector's (`ThemeInspector`,
/// `ThemeSettingsInspector`). A project with core 2 gets only the way to the core update.
struct ThemeTab: View {
  let theme: ThemeModel
  @Binding var selection: String?
  @Binding var query: String
  /// The page's Speichern, after this tab's actions in the toolbar.
  let saveButton: SaveButton
  /// Bumped by the page after a save: the cleanup looks at the file again.
  let savedRound: Int

  @Environment(\.openPage) private var openPage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var styles: StylesModel { theme.styles }

  var body: some View {
    Group {
      if styles.features.themesCore3 {
        VStack(alignment: .leading, spacing: 0) {
          header
          list
        }
      } else {
        needsCore3
      }
    }
    .toolbar { toolbar }
    .task { if theme.listing == nil { await theme.loadCatalog() } }
    .task { await theme.reloadPresets() }
    .task(id: theme.fetchKey) { await theme.loadTheme() }
    .task(id: "\(savedRound)|\(theme.info != nil)|\(theme.fetchKey)") { await theme.findLegacy() }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    if styles.features.themesCore3 {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await theme.loadCatalog(refresh: true) }
        } label: {
          Label(theme.catalogLoading ? L10n.t("themes.catalog.refreshing") : L10n.t("themes.catalog.refresh"), systemImage: "arrow.clockwise")
        }
        .help(L10n.t("themes.catalog.refresh"))
        .disabled(theme.catalogLoading)
      }
      ToolbarSpacer(.fixed, placement: .primaryAction)
    }
    ToolbarItem(placement: .primaryAction) { saveButton }
  }

  private var needsCore3: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      Callout(.info) {
        Text(L10n.t("themes.needsCore3"))
        Button(L10n.t("themes.goToUpdates")) { openPage(.updates) }
          .accessibilityIdentifier("themes.goToUpdates")
      }
    }
    .frame(maxWidth: FormWidth.column, alignment: .leading)
    .padding(Spacing.page)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  // MARK: The list

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      TextField(L10n.t("themes.list.searchPlaceholder"), text: $query, prompt: Text(L10n.t("themes.list.searchPlaceholder")))
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 260)
        .accessibilityIdentifier("themes.search")
      if theme.catalogMissing {
        Callout(.warning, L10n.t("themes.list.unavailable"))
      } else if let listing = theme.listing, !listing.current {
        Callout(.info, L10n.t("themes.list.notCurrent", ["date": listing.fetched.formatted(date: .abbreviated, time: .shortened)]))
      }
    }
    .padding(.horizontal, Spacing.page)
    .padding(.vertical, Spacing.s)
    .animation(Motion.layout(reduce: reduceMotion), value: "\(theme.catalogMissing)|\(theme.listing?.current ?? true)")
  }

  /// By name as Finder sorts; searched in name, author and repo, accents and case aside. Obsidian's
  /// file keeps the order themes were added in.
  private var filtered: [ThemeCatalog.Theme] {
    let themes = (theme.listing?.themes ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let q = StylesModel.trim(query)
    guard !q.isEmpty else { return themes }
    return themes.filter { $0.name.localizedStandardContains(q) || ($0.author ?? "").localizedStandardContains(q) || $0.repo.localizedStandardContains(q) }
  }

  private var list: some View {
    let themes = filtered
    // Once per drawing: for a name core does not know, finding it compares every slug of the list,
    // and asked per row that was 1064 × 1064 on the main thread (measured, the tab hung for ~10 s).
    let active = theme.activeRow
    return List(selection: $selection) {
      // The project's theme first, whatever its source; the rest below it once.
      if let active {
        Section(L10n.t("themes.list.mineHeading")) {
          if active == ThemeModel.builtInRow {
            builtInRow(active)
          } else if active == ThemeModel.otherRow, let spec = theme.spec {
            otherRow(spec, active)
          } else if let item = theme.catalogTheme {
            catalogRow(item, active)
          }
        }
      }
      Section(L10n.t("themes.list.catalogHeading")) {
        if active != ThemeModel.builtInRow, StylesModel.trim(query).isEmpty { builtInRow(active) }
        if theme.listing == nil {
          Text(theme.catalogLoading ? L10n.t("themes.loading") : L10n.t("themes.catalog.noResults")).foregroundStyle(.secondary)
            .selectionDisabled()
        } else if themes.isEmpty {
          Text(L10n.t("themes.catalog.noResults")).foregroundStyle(.secondary).selectionDisabled()
        }
        ForEach(themes.filter { $0.name != active }) { catalogRow($0, active) }
      }
    }
    .accessibilityIdentifier("themes.list")
  }

  @ViewBuilder private func badge(_ row: String, _ active: String?) -> some View {
    if active == row {
      if theme.enabled {
        StateBadge(text: L10n.t("themes.catalog.active"), color: .green)
      } else {
        StateBadge(text: L10n.t("themes.list.off"), color: .secondary)
      }
    }
  }

  private func builtInRow(_ active: String?) -> some View {
    ThemeRow(picture: .symbol("circle.lefthalf.filled"), name: L10n.t("themes.list.builtIn"), detail: L10n.t("themes.list.builtInDetail"),
             modes: ["light", "dark"], legacy: false) { badge(ThemeModel.builtInRow, active) }
      .tag(ThemeModel.builtInRow)
      .accessibilityIdentifier("themes.row.builtin")
  }

  private func otherRow(_ spec: String, _ active: String?) -> some View {
    let kind = ThemeSource.kind(of: spec)
    let name: String = if case .loaded(let loaded) = theme.load { loaded.name } else { ThemeSource.display(spec) }
    return ThemeRow(picture: .symbol(ThemeTab.symbol(kind)), name: name, detail: "\(ThemeTab.title(kind)) · \(ThemeSource.display(spec))",
                    modes: { if case .loaded(let loaded) = theme.load { loaded.modes ?? [] } else { [] } }(), legacy: false) {
      badge(ThemeModel.otherRow, active)
    }
    .tag(ThemeModel.otherRow)
    .accessibilityIdentifier("themes.row.other")
  }

  private func catalogRow(_ item: ThemeCatalog.Theme, _ active: String?) -> some View {
    ThemeRow(picture: item.screenshotURL.map { .screenshot($0) } ?? .none, name: item.name,
             detail: item.author.map { L10n.t("themes.list.byAuthor", ["author": $0]) }, modes: item.modes, legacy: item.legacy) {
      badge(item.name, active)
    }
    .tag(item.name)
    .accessibilityIdentifier("themes.row.\(item.name)")
  }

  static func title(_ kind: ThemeSource.Kind) -> String {
    switch kind {
    case .catalog: L10n.t("themes.source.catalog")
    case .repo: L10n.t("themes.source.repo")
    case .address: L10n.t("themes.source.address")
    case .file: L10n.t("themes.source.file")
    }
  }

  static func symbol(_ kind: ThemeSource.Kind) -> String {
    switch kind {
    case .catalog: "list.bullet"
    case .repo: "shippingbox"
    case .address: "link"
    case .file: "doc"
    }
  }
}

/// One row of the theme list: picture, name with author or source below, the modes, a state.
struct ThemeRow<Badge: View>: View {
  enum Picture: Equatable {
    case screenshot(String)
    case symbol(String)
    case none
  }

  let picture: Picture
  let name: String
  let detail: String?
  let modes: [String]
  let legacy: Bool
  @ViewBuilder let badge: () -> Badge

  static var thumbnail: CGSize { CGSize(width: 96, height: 60) }

  var body: some View {
    HStack(spacing: Spacing.s) {
      Group {
        switch picture {
        case .screenshot(let address): ThemeScreenshot(address: address, contentMode: .fill)
        case .symbol(let name): Image(systemName: name).font(.title2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .none: Color.clear
        }
      }
      .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
      .background(.quaternary.opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(name).fontWeight(.medium)
        if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
        if legacy { Text(L10n.t("themes.list.legacy")).font(.caption).foregroundStyle(.secondary) }
      }
      Spacer(minLength: Spacing.xs)
      ThemeModes(modes: modes)
      badge()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

/// A theme's modes as a sun and a moon, each with its name for VoiceOver.
struct ThemeModes: View {
  let modes: [String]

  var body: some View {
    HStack(spacing: 4) {
      if modes.contains("light") {
        Image(systemName: "sun.max").accessibilityLabel(L10n.t("styles.variables.light")).help(L10n.t("styles.variables.light"))
      }
      if modes.contains("dark") {
        Image(systemName: "moon").accessibilityLabel(L10n.t("styles.variables.dark")).help(L10n.t("styles.variables.dark"))
      }
    }
    .foregroundStyle(.secondary)
  }
}

/// A catalog screenshot, loaded when it appears (`ThemeScreenshots`: scaled, kept in the profile).
struct ThemeScreenshot: View {
  let address: String
  var contentMode: ContentMode = .fit

  /// nil: not asked yet or asking; `.some(nil)`: none to be had.
  @State private var image: NSImage??

  var body: some View {
    Group {
      switch image {
      case .some(let image?):
        Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
      case .some(nil):
        Image(systemName: "photo").foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity)
          .help(L10n.t("themes.inspector.noScreenshot"))
      case nil:
        Color.clear
      }
    }
    .task(id: address) {
      image = nil
      let data = await ThemeServices.screenshots.image(address)
      image = .some(data.flatMap(NSImage.init(data:)))
    }
  }
}
