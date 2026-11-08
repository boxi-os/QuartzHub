import QuartzHubCore
import SwiftUI

/// The Marktplatz's state (QuartzControl's `routes/Plugins/Marketplace.tsx`): the catalog of
/// quartz-community from `AppServices.marketplace`, read once and searched here, and what an
/// install said. What is installed comes from the plugin list the page already holds.
@MainActor @Observable
final class MarketplaceModel {
  let plugins: PluginsModel
  /// nil until the first read answers: an empty list would say "nothing found" for the second the
  /// catalog takes to arrive.
  private(set) var result: MarketplaceResult?
  private(set) var refreshing = false
  /// The full name or source being installed.
  private(set) var installing: String?
  private(set) var message: String?
  private(set) var failed = false

  init(plugins: PluginsModel) {
    self.plugins = plugins
  }

  func load() async {
    result = await AppServices.shared.marketplace.list()
  }

  /// The catalog is kept fifteen minutes; a plugin published in the meantime is otherwise out of
  /// reach until QuartzHub starts again.
  func refresh() async {
    refreshing = true
    defer { refreshing = false }
    await AppServices.shared.marketplace.invalidate()
    result = await AppServices.shared.marketplace.list()
  }

  func isInstalled(_ plugin: MarketplacePlugin) -> Bool {
    plugins.installedRepositories.contains(plugin.fullName.lowercased())
  }

  /// A catalog entry goes in as `github:owner/repo`; a hand-typed source as it was typed.
  @discardableResult
  func install(source: String, name: String) async -> Bool {
    installing = name
    message = nil
    defer { installing = nil }
    let result = await plugins.add(source: source)
    failed = !result.success
    message = result.success ? L10n.t("pluginsMarketplace.installedMessage", ["name": name]) : result.output
    if result.success { Announce.post(message!) }
    return result.success
  }
}

/// Marktplatz: the catalog in the middle, the selected entry with its README in the inspector
/// (`MarketplaceInspector`). Adding a plugin from anywhere else is the same job and sits above the
/// list: the catalog only knows one organisation.
struct MarketplaceTab: View {
  @Bindable var model: MarketplaceModel
  @Binding var selection: String?

  // "Where the user was", per window; the results are read again, so nothing shown is stale.
  @SceneStorage("marketplace.query") private var query = ""
  @SceneStorage("marketplace.showOther") private var showOther = false
  @SceneStorage("marketplace.source") private var source = ""

  private var busy: Bool { model.installing != nil || model.plugins.busy || model.plugins.maintenance != nil }

  var body: some View {
    let lists = model.result?.split(query: query) ?? (plugins: [], other: [])
    VStack(alignment: .leading, spacing: 0) {
      header
      List(selection: $selection) {
        if model.result == nil {
          Text(L10n.t("pluginsMarketplace.loading")).foregroundStyle(.secondary)
        } else if lists.plugins.isEmpty {
          Text(L10n.t("pluginsMarketplace.noResults")).foregroundStyle(.secondary)
        }
        if !lists.plugins.isEmpty {
          Section {
            ForEach(lists.plugins, id: \.fullName) { row($0) }
          }
        }
        if !lists.other.isEmpty {
          // In rows, not the section header: a header is cut to one line, and the sentence that
          // says what these repositories are is the point.
          Section {
            VStack(alignment: .leading, spacing: 2) {
              Button(showOther ? L10n.t("pluginsMarketplace.hideOther", ["count": String(lists.other.count)])
                     : L10n.t("pluginsMarketplace.showOther", ["count": String(lists.other.count)])) {
                showOther.toggle()
              }
              .buttonStyle(.link)
              .accessibilityIdentifier("marketplace.showOther")
              Text(L10n.t("pluginsMarketplace.otherDescription"))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .selectionDisabled()
            if showOther {
              ForEach(lists.other, id: \.fullName) { row($0) }
            }
          }
        }
      }
      .accessibilityIdentifier("marketplace.list")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        TextField(L10n.t("pluginsMarketplace.searchPlaceholder"), text: $query,
                  prompt: Text(L10n.t("pluginsMarketplace.searchPlaceholder")))
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 260)
          .accessibilityIdentifier("marketplace.search")
        Spacer()
        Button {
          Task { await model.refresh() }
        } label: {
          Label(model.refreshing ? L10n.t("pluginsMarketplace.refreshing") : L10n.t("pluginsMarketplace.refresh"),
                systemImage: "arrow.clockwise")
        }
        .disabled(model.refreshing)
      }
      HStack(spacing: 8) {
        Text(L10n.t("pluginsMarketplace.addFromGithub")).foregroundStyle(.secondary)
        TextField(L10n.t("pluginsMarketplace.addFromGithub"), text: $source,
                  prompt: Text(verbatim: L10n.t("pluginsMarketplace.addPlaceholder")))
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
          .frame(maxWidth: 240)
          .labelsHidden()
          .onSubmit(addFromSource)
          .accessibilityIdentifier("marketplace.source")
        Button(model.installing != nil && model.installing == trimmedSource ? L10n.t("pluginsMarketplace.installing")
               : L10n.t("pluginsMarketplace.add"), action: addFromSource)
          .disabled(busy || trimmedSource.isEmpty)
      }
      if model.result?.unavailable == true {
        Text(L10n.t("pluginsMarketplace.unavailable"))
          .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
      }
      if let message = model.message {
        Text(message).foregroundStyle(model.failed ? .red : .secondary).textSelection(.enabled).lineLimit(8)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var trimmedSource: String { source.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func addFromSource() {
    let typed = trimmedSource
    guard !typed.isEmpty, !busy else { return }
    Task {
      if await model.install(source: typed, name: typed) { source = "" }
    }
  }

  private func row(_ plugin: MarketplacePlugin) -> some View {
    let installed = model.isInstalled(plugin)
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(plugin.name).fontWeight(.medium)
        if let description = plugin.description {
          Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
      }
      Spacer()
      if installed { WordBadge(text: L10n.t("pluginsMarketplace.installed")).foregroundStyle(.green) }
      if !installed, plugin.archived == true { WordBadge(text: L10n.t("pluginsMarketplace.archived")).foregroundStyle(.orange) }
      Text(verbatim: "★ \(plugin.stars ?? 0)")
        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        .frame(minWidth: 40, alignment: .trailing)
    }
    .padding(.vertical, 2)
    .tag(plugin.fullName)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("marketplace.row.\(plugin.fullName)")
  }
}

/// The selected catalog entry: what it is, the button to install it, its README.
struct MarketplaceInspector: View {
  let plugin: MarketplacePlugin
  @Bindable var model: MarketplaceModel
  @Environment(\.openURL) private var openURL

  private enum Readme {
    case loading, missing, unavailable
    case ok([ReadmeText.Block], truncated: Bool)
  }

  @State private var readme: Readme = .loading

  var body: some View {
    let installed = model.isInstalled(plugin)
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline) {
            Label(plugin.name, systemImage: "storefront").font(.headline)
              .accessibilityIdentifier("marketplace.inspector.name")
            Spacer()
            if installed { WordBadge(text: L10n.t("pluginsMarketplace.installed")).foregroundStyle(.green) }
            if !installed, plugin.archived == true { WordBadge(text: L10n.t("pluginsMarketplace.archived")).foregroundStyle(.orange) }
          }
          // Not a file path: the repository on github.com.
          if let url = URL(string: plugin.url) {
            Button { openURL(url) } label: {
              Label(plugin.fullName, systemImage: "arrow.up.right.square").font(.caption)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.link)
            .help(L10n.t("pluginsMarketplace.openRepo"))
          }
          if let description = plugin.description { Text(description).foregroundStyle(.secondary) }
        }
        HStack {
          Text(verbatim: "★ \(plugin.stars ?? 0)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
          Spacer()
          // An installed plugin says so once, in the badge at the top.
          if !installed {
            Button(model.installing == plugin.fullName ? L10n.t("pluginsMarketplace.installing") : L10n.t("pluginsMarketplace.install")) {
              Task { await model.install(source: "github:\(plugin.fullName)", name: plugin.name) }
            }
            .disabled(model.installing != nil || model.plugins.busy || model.plugins.maintenance != nil)
            .accessibilityIdentifier("marketplace.install")
          }
        }
      }
      Section {
        switch readme {
        case .loading: Text(L10n.t("pluginsMarketplace.readmeLoading")).foregroundStyle(.secondary)
        case .missing: Text(L10n.t("pluginsMarketplace.readmeMissing")).foregroundStyle(.secondary)
        case .unavailable: Text(L10n.t("pluginsMarketplace.readmeUnavailable")).foregroundStyle(.secondary)
        case .ok(let blocks, let truncated):
          ReadmeView(blocks: blocks)
          if truncated { Note(L10n.t("pluginsMarketplace.readmeTruncated")) }
        }
      }
    }
    .formStyle(.grouped)
    .task(id: plugin.fullName) { await loadReadme() }
  }

  /// Read off the main thread: a README of up to 256 KB made of unclosed links took 1.4 s to read
  /// (docs/decisions/phase-4-oberflaeche.md), and the window must not wait for it.
  private func loadReadme() async {
    readme = .loading
    let answer = await AppServices.shared.marketplace.readme(plugin.fullName)
    switch answer {
    case .missing: readme = .missing
    case .unavailable: readme = .unavailable
    case .ok(let text, let truncated):
      let repo = plugin.url
      let blocks = await Task.detached(priority: .userInitiated) { ReadmeText.blocks(text, repoUrl: repo) }.value
      if !Task.isCancelled { readme = .ok(blocks, truncated: truncated) }
    }
  }
}
