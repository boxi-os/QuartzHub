import QuartzHubCore
import SwiftUI

/// The services the Community-Themes tab shares across windows: the catalog is cached for fifteen
/// minutes, the option documentation on disk.
@MainActor
enum ThemeServices {
  static let marketplace = ThemeMarketplace(
    search: ThemeMarketplace.npmSearch(environment: { await AppServices.current() }),
    install: ThemeMarketplace.npmInstall(environment: { await AppServices.current() }),
    token: { (try? await AppDeploy.connections().gitToken()) ?? nil })
  static let schema = StyleSettingsSchema(profile: AppProfile.own)
}

/// Community-Themes (QuartzControl's `Styles/Theme.tsx`): the active `@quartz-themes` theme with the
/// options it declares itself, the saved presets, and the catalog. A theme picked in the catalog
/// shows its details in the inspector.
struct ThemeTab: View {
  let model: StylesModel
  let notes: AnyView
  let goTo: (StylesModel.Tab) -> Void
  @Binding var selection: String?
  @Binding var query: String
  /// Held by the page: the inspector shows a listing of it.
  @Binding var catalog: ThemeMarketplace.Catalog?

  @Environment(\.unsavedGuard) private var unsaved
  @State private var presets: [JSONValue] = []
  @State private var info: ThemeStyleSettingsInfo?
  @State private var infoLoading = false
  /// nil: not asked yet or asking; `.null`: the theme has no documentation.
  @State private var schema: JSONValue?
  @State private var schemaLoading = false
  @State private var refreshingSchema = false
  /// Two states, not an optional name: the text field writes its text back as it goes away, and
  /// a nil name came back as the typed one (seen: the field stayed after saving).
  @State private var savingPreset = false
  @State private var presetName = ""
  @State private var optionQuery = ""
  @State private var catalogLoading = false

  static let visibleLimit = 30

  private var config: QuartzConfig { model.config ?? QuartzConfig() }

  /// Found whether it is on or not: a disabled entry is offered back rather than "no theme".
  private var pluginIndex: Int? { config.plugins.firstIndex(where: FontDelivery.isThemePlugin) }
  private var plugin: PluginEntry? { pluginIndex.map { config.plugins[$0] } }
  private var themeId: String? { plugin?.object["options"]?["theme"]?.stringValue }
  private var activeThemeId: String? { plugin.flatMap { FontDelivery.enabled($0) ? themeId : nil } }

  var body: some View {
    Form {
      notes
      activeSection
      if let plugin, FontDelivery.enabled(plugin), info?.styleSettingsId.isEmpty == false { styleSettingsSection(plugin) }
      presetsSection
      catalogSection
    }
    .formStyle(.grouped)
    .task { await reloadPresets() }
    .task(id: "\(themeId ?? "")|\(plugin.map(FontDelivery.enabled) ?? false)") { await loadThemeInfo() }
    .task { if catalog == nil { await loadCatalog() } }
  }

  // MARK: The theme plugin

  private func updatePlugin(_ next: PluginEntry) {
    var config = config
    if let pluginIndex { config.plugins[pluginIndex] = next } else { config.plugins.append(next) }
    model.setConfig(config)
  }

  private func options(_ plugin: PluginEntry) -> JSONObject { plugin.object["options"]?.objectValue ?? JSONObject() }

  func activate(_ id: String) {
    var base = plugin ?? PluginEntry(object: JSONObject([("name", .string(id)), ("source", .string("@quartz-themes/core")), ("enabled", .bool(true)),
                                                         ("options", .object(JSONObject([("mode", .string("both"))])))]))
    var opts = options(base)
    opts["theme"] = .string(id)
    base.object["enabled"] = .bool(true)
    base.object["options"] = .object(opts)
    updatePlugin(base)
  }

  private func setEnabled(_ on: Bool) {
    guard var plugin else { return }
    plugin.object["enabled"] = .bool(on)
    updatePlugin(plugin)
  }

  // MARK: The active theme

  @ViewBuilder private var activeSection: some View {
    Section {
      if let plugin {
        if FontDelivery.enabled(plugin) {
          LabeledContent(L10n.t("themes.active.heading", ["themeId": themeId ?? "—"])) {
            Button(L10n.t("themes.disableAll")) { setEnabled(false) }
              .accessibilityIdentifier("themes.disable")
          }
          Note(L10n.t("themes.active.overrideNote", ["source": plugin.source?.stringValue ?? ""]))
          if infoLoading {
            Note(L10n.t("themes.active.checkingStyleSettings"))
          } else if info?.styleSettingsId.isEmpty != false, let themeId {
            Note(L10n.t("themes.active.noStyleSettingsNote", ["themeId": themeId]))
          }
          savePresetRow(plugin)
        } else {
          // Kept with enabled: false rather than removed, so the choice and its settings survive.
          LabeledContent(L10n.t("themes.active.disabledHeading", ["themeId": themeId ?? "—"])) {
            Button(L10n.t("themes.active.reactivate")) { setEnabled(true) }
              .accessibilityIdentifier("themes.reactivate")
          }
          Note(L10n.t("themes.active.disabledNote"))
        }
      } else {
        Note(L10n.t("themes.active.none"))
      }
    } header: {
      Text(L10n.t("themes.active.title"))
    }
  }

  @ViewBuilder private func savePresetRow(_ plugin: PluginEntry) -> some View {
    if savingPreset {
      HStack {
        TextField(L10n.t("themes.active.presetNamePlaceholder"), text: $presetName,
                  prompt: Text(L10n.t("themes.active.presetNamePlaceholder")))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("themes.presetName")
        Button(L10n.t("common.cancel")) { savingPreset = false }
        Button(L10n.t("common.save")) { savePreset(plugin) }
          .disabled(StylesModel.trim(presetName).isEmpty)
          .accessibilityIdentifier("themes.presetSave")
      }
    } else {
      Button(L10n.t("themes.active.saveAsPreset")) {
        presetName = ""
        savingPreset = true
      }
        .accessibilityIdentifier("themes.saveAsPreset")
    }
  }

  private func savePreset(_ plugin: PluginEntry) {
    let name = StylesModel.trim(presetName)
    guard !name.isEmpty else { return }
    let opts = options(plugin)
    var presetOptions = JSONObject([("theme", .string(themeId ?? "default")), ("mode", .string(opts["mode"]?.stringValue ?? "both"))])
    if let variation = opts["variation"]?.stringValue { presetOptions["variation"] = .string(variation) }
    if let callout = opts["calloutStyle"]?.stringValue { presetOptions["calloutStyle"] = .string(callout) }
    presetOptions["styleSettings"] = .object(opts["styleSettings"]?.objectValue ?? JSONObject())
    let now = Date()
    let preset = JSONObject([
      ("id", .string("preset-\(Int((now.timeIntervalSince1970 * 1000).rounded()))")), ("name", .string(name)),
      ("createdAt", .string(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now))),
      ("baseThemeId", .string(themeId ?? "default")), ("options", .object(presetOptions))
    ])
    do {
      try ThemePresets.save(.object(preset), project: model.project.path)
      savingPreset = false
      Task { await reloadPresets() }
    } catch {
      Announce.post(StylesModel.message(error))
    }
  }

  private func loadThemeInfo() async {
    info = nil
    schema = nil
    guard let themeId, let plugin, FontDelivery.enabled(plugin) else { return }
    infoLoading = true
    let path = model.project.path
    let read = await Task.detached { PluginSchemaReader.themeStyleSettings(project: path, themeId: themeId) }.value
    guard themeId == self.themeId else { return }
    info = read
    infoLoading = false
    guard read?.styleSettingsId.isEmpty == false else { return }
    schemaLoading = true
    let fetched = (try? await ThemeServices.schema.schema(themeId: themeId)) ?? .null
    guard themeId == self.themeId else { return }
    schema = fetched
    schemaLoading = false
  }

  /// The documentation lives upstream and is kept on disk for good; this asks again.
  private func refreshSchema() async {
    guard let themeId else { return }
    refreshingSchema = true
    try? await ThemeServices.schema.clearCache(themeId: themeId)
    schema = (try? await ThemeServices.schema.schema(themeId: themeId)) ?? .null
    refreshingSchema = false
  }

  // MARK: Style Settings

  private func styleSettingsSection(_ plugin: PluginEntry) -> some View {
    let values = options(plugin)["styleSettings"]?.objectValue ?? JSONObject()
    let ids = info?.styleSettingsId ?? []
    return Section {
      if schemaLoading || schema == nil {
        Note(L10n.t("styles.styleSettings.loading"))
      } else if let schema, schema != .null, let info {
        StyleSettingsForm(schema: schema, info: info, values: values, query: $optionQuery) { patch in apply(patch) }
      } else {
        Note(L10n.t("styles.styleSettings.unavailable"))
        ForEach(info?.classSettingKeys ?? [], id: \.self) { key in
          let fullKey = "\(ids.first ?? "")@@\(key)"
          Toggle(key, isOn: Binding(get: { values[fullKey] == .bool(true) }, set: { apply([(fullKey, $0 ? .bool(true) : nil)]) }))
        }
      }
      // Only what the theme declares: writing any custom property is the Variablen tab's job.
      HStack(alignment: .firstTextBaseline) {
        Note(L10n.t("themes.active.ownValuesHint"))
        Button(L10n.t("themes.active.goToVariables")) { goTo(.variables) }.buttonStyle(.link).font(.callout)
      }
    } header: {
      HStack {
        Text(L10n.t("themes.active.styleSettingsHeading", ["ids": ids.joined(separator: ", ")]))
        Spacer()
        Button(refreshingSchema ? L10n.t("common.loading") : L10n.t("styles.styleSettings.refresh")) { Task { await refreshSchema() } }
          .disabled(refreshingSchema || schemaLoading)
          .font(.callout)
      }
    }
  }

  /// One patch at a time on one copy: a themed hsl-split colour writes six keys.
  private func apply(_ patch: [(key: String, value: JSONValue?)]) {
    guard var plugin else { return }
    var opts = options(plugin)
    opts["styleSettings"] = .object(StyleSettingsValues.apply(patch, to: opts["styleSettings"]?.objectValue ?? JSONObject()))
    plugin.object["options"] = .object(opts)
    updatePlugin(plugin)
  }

  // MARK: Presets

  private var presetsSection: some View {
    Section {
      Note(L10n.t("themes.presets.description"))
      if presets.isEmpty { Note(L10n.t("themes.presets.none")) }
      ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
        let name = preset["name"]?.stringValue ?? ""
        HStack {
          Text(name)
          Text(L10n.t("themes.presets.basisLabel", ["base": preset["baseThemeId"]?.stringValue ?? ""])).foregroundStyle(.secondary)
          Spacer()
          if let theme = preset["options"]?["theme"]?.stringValue, theme == activeThemeId {
            StateBadge(text: L10n.t("themes.presets.active"), color: .green)
          } else {
            Button(L10n.t("themes.presets.apply")) { Task { await applyPreset(preset) } }
          }
          Button(role: .destructive) {
            Task { await deletePreset(preset) }
          } label: {
            Label(L10n.t("common.deleteNamed", ["name": name]), systemImage: "trash")
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
        }
      }
    } header: {
      Text(L10n.t("themes.presets.title"))
    }
  }

  private func reloadPresets() async {
    let path = model.project.path
    presets = await Task.detached { ThemePresets.list(project: path) }.value
  }

  /// Installs the preset's theme first (npm), then takes over its options.
  private func applyPreset(_ preset: JSONValue) async {
    guard let base = preset["baseThemeId"]?.stringValue else { return }
    _ = try? await ThemeServices.marketplace.install(themeId: base, project: model.project.path)
    var next = plugin ?? PluginEntry(object: JSONObject([("name", .string(base)), ("source", .string("@quartz-themes/core")), ("enabled", .bool(true))]))
    next.object["enabled"] = .bool(true)
    next.object["options"] = .object(preset["options"]?.objectValue ?? JSONObject())
    updatePlugin(next)
  }

  private func deletePreset(_ preset: JSONValue) async {
    let name = preset["name"]?.stringValue ?? ""
    let (question, detail) = Confirm.split(L10n.t("themes.presets.confirmDelete", ["name": name]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("themes.presets.confirmDeleteAction"), destructive: true,
                            window: unsaved?.window) else { return }
    try? ThemePresets.delete(id: preset["id"]?.stringValue ?? "", project: model.project.path)
    await reloadPresets()
  }

  // MARK: The catalog

  private var catalogSection: some View {
    let q = StylesModel.trim(query).lowercased()
    let themes = catalog?.themes ?? []
    let filtered = q.isEmpty ? themes : themes.filter { $0.id.lowercased().contains(q) }
    return Section {
      Note(L10n.t("themes.catalog.description"))
      HStack {
        TextField(L10n.t("themes.catalog.searchPlaceholder"), text: $query, prompt: Text(L10n.t("themes.catalog.searchPlaceholder")))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("themes.search")
        Button(catalogLoading ? L10n.t("themes.catalog.refreshing") : L10n.t("themes.catalog.refresh")) {
          Task {
            await ThemeServices.marketplace.invalidate()
            await loadCatalog()
          }
        }
        .disabled(catalogLoading)
      }
      if catalog?.unavailable == true {
        Label(L10n.t("themes.catalog.unavailable"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
      }
      if filtered.isEmpty {
        Note(catalogLoading || catalog == nil ? L10n.t("themes.loading") : L10n.t("themes.catalog.noResults"))
      }
      ForEach(filtered.prefix(Self.visibleLimit), id: \.id) { listing in catalogRow(listing) }
      if filtered.count > Self.visibleLimit {
        Note(L10n.t("themes.catalog.moreResults", count: filtered.count - Self.visibleLimit))
      }
    } header: {
      Text(L10n.t("themes.catalog.title"))
    }
  }

  private func catalogRow(_ listing: ThemeMarketplace.Listing) -> some View {
    Button {
      selection = selection == listing.id ? nil : listing.id
    } label: {
      HStack {
        Text(listing.id).font(.system(.body, design: .monospaced))
        if let stars = listing.stars, stars > 0 { Text("★ \(stars)").font(.caption).foregroundStyle(.secondary) }
        Spacer()
        ForEach(listing.topics ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        if listing.id == activeThemeId { StateBadge(text: L10n.t("themes.catalog.active"), color: .green) }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(selection == listing.id ? Color.accentColor.opacity(0.15) : nil)
    .accessibilityIdentifier("themes.row.\(listing.id)")
  }

  private func loadCatalog() async {
    catalogLoading = true
    catalog = await ThemeServices.marketplace.list()
    catalogLoading = false
  }
}

/// A theme of the catalog, in the inspector: what it brings, and installing it.
struct ThemeInspector: View {
  let id: String
  let listing: ThemeMarketplace.Listing?
  let model: StylesModel
  let active: Bool
  let activate: (String) -> Void

  @State private var detail: ThemeDetail??
  @State private var installing = false
  @State private var message: String?

  var body: some View {
    Form {
      Section {
        Text(id).font(.system(.title3, design: .monospaced))
        if let text = listing?.githubDescription ?? listing?.description { Text(text).foregroundStyle(.secondary) }
        if active {
          StateBadge(text: L10n.t("themes.catalog.active"), color: .green)
        } else {
          Button(installing ? L10n.t("themes.catalog.installing") : L10n.t("themes.catalog.install")) { Task { await install() } }
            .disabled(installing)
            .accessibilityIdentifier("themes.install")
        }
        if let message { Text(message).font(.callout).textSelection(.enabled) }
      }
      Section {
        switch detail {
        case nil: Note(L10n.t("themes.catalog.detailLoading"))
        case .some(nil): Note(L10n.t("themes.catalog.detailNone"))
        case .some(let detail?):
          Text(L10n.t("themes.catalog.modes", ["modes": detail.modes.isEmpty ? "—" : detail.modes.joined(separator: ", ")]))
          Text(L10n.t("themes.catalog.variations", ["variations": detail.variations.isEmpty ? "—" : detail.variations.joined(separator: ", ")]))
          Text(L10n.t("themes.catalog.customColorsLabel", ["value": detail.styleSettingsId.isEmpty ? L10n.t("themes.catalog.no") : L10n.t("themes.catalog.yes")]))
          Text(L10n.t("themes.catalog.fonts", ["fonts": detail.fonts.isEmpty ? "—" : detail.fonts.joined(separator: ", ")]))
        }
      }
    }
    .formStyle(.grouped)
    .task(id: id) {
      detail = nil
      let read = (try? await ThemeServices.marketplace.detail(themeId: id, project: model.project.path)) ?? nil
      detail = .some(read)
    }
  }

  private func install() async {
    installing = true
    message = nil
    defer { installing = false }
    do {
      let result = try await ThemeServices.marketplace.install(themeId: id, project: model.project.path)
      if result.success {
        activate(id)
        message = L10n.t("themes.catalog.installSuccess", ["id": id])
      } else {
        message = L10n.t("themes.catalog.installFailed", ["id": id, "output": String(result.output.prefix(300))])
      }
    } catch {
      message = StylesModel.message(error)
    }
    if let message { Announce.post(message) }
  }
}

/// A theme's own options, built from the upstream theme's `@settings` block, grouped by its
/// headings (QuartzControl's `StyleSettingsForm`). Class settings the port does not ship are left
/// out: they would be switches that do nothing.
struct StyleSettingsForm: View {
  let schema: JSONValue
  let info: ThemeStyleSettingsInfo
  let values: JSONObject
  @Binding var query: String
  let onChange: ([(key: String, value: JSONValue?)]) -> Void

  var body: some View {
    let shipped = Set(info.classSettingKeys)
    let usable = StyleSettingsValues.usable(StyleSettingsValues.fields(schema), shippedClassKeys: shipped)
    let groups = StyleSettingsValues.groups(StyleSettingsValues.filter(usable, query: query))
    let count = usable.filter { $0.kind != "heading" && $0.kind != "info-text" }.count
    Note(L10n.t("styles.styleSettings.sourceNote", ["theme": schema["themeName"]?.stringValue ?? "", "author": schema["author"]?.stringValue ?? ""], count: count))
    TextField(L10n.t("styles.styleSettings.searchPlaceholder"), text: $query, prompt: Text(L10n.t("styles.styleSettings.searchPlaceholder")))
      .labelsHidden()
      .textFieldStyle(.roundedBorder)
      .accessibilityIdentifier("styleSettings.search")
    ForEach(groups) { group in
      StyleSettingsGroupView(group: group, values: values, shipped: shipped, forceOpen: !StylesModel.trim(query).isEmpty, onChange: onChange)
    }
  }
}

struct StyleSettingsGroupView: View {
  let group: StyleSettingsValues.Group
  let values: JSONObject
  let shipped: Set<String>
  let forceOpen: Bool
  let onChange: ([(key: String, value: JSONValue?)]) -> Void
  /// The theme author's `collapsed` decides the first state, as in Obsidian.
  @State private var open: Bool?

  var body: some View {
    if let heading = group.heading {
      if group.hasAnyField {
        DisclosureGroup(isExpanded: Binding(get: { forceOpen || (open ?? !heading.collapsed) }, set: { open = $0 })) {
          if let description = heading.description { Note(description) }
          content
        } label: {
          Text(heading.title).fontWeight(.semibold)
        }
      }
    } else {
      content
    }
  }

  @ViewBuilder private var content: some View {
    ForEach(Array(group.fields.enumerated()), id: \.offset) { _, field in
      StyleSettingRow(field: field, values: values, shipped: shipped, onChange: onChange)
    }
    ForEach(group.children) { child in
      AnyView(StyleSettingsGroupView(group: child, values: values, shipped: shipped, forceOpen: forceOpen, onChange: onChange))
    }
  }
}

struct StyleSettingRow: View {
  let field: StyleSettingsValues.Field
  let values: JSONObject
  let shipped: Set<String>
  let onChange: ([(key: String, value: JSONValue?)]) -> Void

  private var key: String { StyleSettingsValues.optionKey(field) }

  var body: some View {
    if field.kind == "info-text" {
      Note(field.description.map { "\(field.title) — \($0)" } ?? field.title)
    } else {
      let keys = StyleSettingsValues.keysOf(field)
      let isSet = keys.contains { values[$0] != nil }
      VStack(alignment: .leading, spacing: 2) {
        LabeledContent {
          HStack {
            control
            if isSet {
              Button(L10n.t("styles.styleSettings.reset")) { onChange(keys.map { ($0, nil) }) }
                .buttonStyle(.link).font(.caption)
            }
          }
        } label: {
          Text(field.title).help(field.id)
        }
        if let description = field.description { Text(description).font(.caption).foregroundStyle(.secondary) }
      }
    }
  }

  @ViewBuilder private var control: some View {
    switch field.kind {
    case "class-toggle":
      Toggle(field.title, isOn: Binding(get: { values[key] == .bool(true) }, set: { onChange([(key, $0 ? .bool(true) : nil)]) }))
        .labelsHidden()
    case "class-select", "variable-select":
      // A class select stores the option's class key, and core emits it only when the port ships it.
      let options = field.kind == "class-select" ? field.options.filter { shipped.contains($0.value) } : field.options
      if !options.isEmpty || field.kind == "variable-select" {
        Picker(field.title, selection: Binding(get: { values[key]?.stringValue ?? "" }, set: { onChange([(key, $0.isEmpty ? nil : .string($0))]) })) {
          Text(L10n.t("styles.styleSettings.themeDefault")).tag("")
          ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
      }
    case "variable-number", "variable-number-slider":
      numberControl
    case "variable-text":
      TextField(field.title, text: Binding(get: { values[key]?.stringValue ?? "" }, set: { onChange([(key, $0.isEmpty ? nil : .string($0))]) }),
                prompt: Text(field.defaultValue?.stringValue ?? ""))
        .labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: 220)
    case "variable-color":
      colorControl(mode: nil, label: nil)
    case "variable-themed-color":
      HStack(spacing: 12) {
        colorControl(mode: .light, label: L10n.t("styles.variables.light"))
        colorControl(mode: .dark, label: L10n.t("styles.variables.dark"))
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder private var numberControl: some View {
    let stored = values[key]
    let text = stored.map { $0.stringValue ?? $0.numberValue.map(JSONValue.number).map(JSJSON.compact) ?? "" } ?? ""
    let placeholder = field.defaultValue.map { $0.stringValue ?? JSJSON.compact($0) } ?? ""
    HStack {
      if field.kind == "variable-number-slider", let min = field.min, let max = field.max, min < max {
        let current = Double(text) ?? Double(placeholder) ?? min
        Slider(value: Binding(get: { Swift.min(Swift.max(current, min), max) }, set: { onChange([(key, .number(($0 / (field.step ?? 1)).rounded() * (field.step ?? 1)))]) }),
               in: min...max)
          .frame(width: 140)
      }
      TextField(field.title, text: Binding(get: { text }, set: { next in
        if next.isEmpty { onChange([(key, nil)]) } else if let number = Double(next) { onChange([(key, .number(number))]) }
      }), prompt: Text(placeholder))
        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 70)
    }
  }

  private func colorControl(mode: StyleSettingsValues.Mode?, label: String?) -> some View {
    let read = StyleSettingsValues.readColor(field, values: values, mode: mode)
    return HStack(spacing: 4) {
      if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
      ColorPicker(selection: Binding(get: { CssColorField.color(read.hex ?? "") }, set: { color in
        let css = CssColorField.css(color)
        let hex = css.hasPrefix("#") ? css : (CssColor.hexAlpha(css)?.hex ?? "#000000")
        onChange(StyleSettingsValues.colorEntries(field, hex: hex, mode: mode).map { ($0.key, .string($0.value)) })
      }), supportsOpacity: false) {
        Text(field.title)
      }
      .labelsHidden()
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(read.isSet ? Color.green : .clear))
    }
  }
}
