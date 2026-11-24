import QuartzHubCore
import SwiftUI

/// A theme of the list that is not the project's: its picture, who made it, its modes, and
/// „Verwenden“. Obsidian's built-in theme is one too (`item` nil).
struct ThemeInspector: View {
  let theme: ThemeModel
  let item: ThemeCatalog.Theme?

  var body: some View {
    Form {
      Section {
        if let address = item?.screenshotURL {
          ThemeScreenshot(address: address)
            .frame(maxWidth: .infinity, minHeight: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        Text(item?.name ?? L10n.t("themes.list.builtIn")).font(.title3).fontWeight(.semibold)
        if let item {
          if let author = item.author { Text(L10n.t("themes.list.byAuthor", ["author": author])).foregroundStyle(.secondary) }
          if item.legacy { Text(L10n.t("themes.list.legacy")).foregroundStyle(.secondary) }
        } else {
          Text(L10n.t("themes.list.builtInDetail")).foregroundStyle(.secondary)
        }
      }
      Section {
        if let item {
          LabeledContent(L10n.t("themes.inspector.repo")) {
            Button(item.repo) {
              if let url = URL(string: "https://github.com/\(item.repo)") { ExternalOpen.open(url) } // an address, not a path
            }
            .buttonStyle(.link)
          }
        }
        LabeledContent(L10n.t("themes.inspector.modesLabel")) {
          Text(ThemeSettingsInspector.modesText(item?.modes ?? ["dark", "light"]))
        }
      }
      Section {
        Button(L10n.t("themes.inspector.use")) { theme.use(item?.name ?? "default") }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("themes.use")
        Note(L10n.t("themes.inspector.useNote"))
      }
    }
    .formStyle(.grouped)
  }
}

/// The project's theme: whether core loads it, where it comes from (catalog, repo, address, file),
/// the release, the mode, snippets, its Style Settings, the presets, and the cleanup when
/// `ThemeLegacy` finds something. Everything but the cleanup goes into the page's draft and is
/// saved with „Speichern“.
struct ThemeSettingsInspector: View {
  let theme: ThemeModel
  let goToVariables: () -> Void

  @Environment(\.unsavedGuard) private var unsaved
  /// A source kind picked before its field has a value.
  @State private var pendingKind: ThemeSource.Kind?
  @State private var sourceProblem: String?
  @State private var snippetDraft = ""
  @State private var optionQuery = ""
  @State private var savingPreset = false
  @State private var presetName = ""
  @State private var presetMessage: String?

  private var styles: StylesModel { theme.styles }
  private var spec: String { theme.spec ?? "" }
  private var kind: ThemeSource.Kind { pendingKind ?? (theme.isBuiltIn ? .catalog : ThemeSource.kind(of: spec)) }

  var body: some View {
    Form {
      stateSection
      sourceSection
      snippetsSection
      if theme.enabled { styleSettingsSection }
      presetsSection
      if !theme.legacy.isEmpty || theme.cleanupMessage != nil { cleanupSection }
    }
    .formStyle(.grouped)
    .onChange(of: spec) { pendingKind = nil; sourceProblem = nil }
  }

  // MARK: State

  private var displayName: String {
    if case .loaded(let loaded) = theme.load { return loaded.name }
    if theme.isBuiltIn { return L10n.t("themes.list.builtIn") }
    return theme.catalogTheme?.name ?? ThemeSource.display(spec)
  }

  private var stateSection: some View {
    Section {
      if let address = theme.catalogTheme?.screenshotURL {
        ThemeScreenshot(address: address)
          .frame(maxWidth: .infinity, minHeight: 120)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      Text(displayName).font(.title3).fontWeight(.semibold)
      if let author = theme.catalogTheme?.author { Text(L10n.t("themes.list.byAuthor", ["author": author])).foregroundStyle(.secondary) }
      if theme.enabled {
        switch theme.load {
        case .idle, .loading:
          Note(L10n.t("themes.state.loading"))
        case .loaded(let loaded):
          Label(loaded.version.map { L10n.t("themes.state.loaded", ["version": $0]) } ?? L10n.t("themes.state.loadedBare"), systemImage: "checkmark.circle")
            .foregroundStyle(.green)
            .accessibilityIdentifier("themes.state")
        case .failed(let reason):
          Callout(.warning, L10n.t("themes.active.notLoaded", ["reason": reason]))
            .accessibilityIdentifier("themes.state")
        }
        Button(L10n.t("themes.disableAll")) { theme.setEnabled(false) }
          .accessibilityIdentifier("themes.disable")
      } else {
        Note(L10n.t("themes.active.disabledNote"))
        Button(L10n.t("themes.active.reactivate")) { theme.setEnabled(true) }
          .accessibilityIdentifier("themes.reactivate")
      }
    }
  }

  // MARK: Source, release, mode

  private var sourceSection: some View {
    Section(L10n.t("themes.source.title")) {
      Picker(L10n.t("themes.source.title"), selection: Binding(get: { kind }, set: { next in
        sourceProblem = nil
        pendingKind = next == (theme.isBuiltIn ? .catalog : ThemeSource.kind(of: spec)) ? nil : next
      })) {
        ForEach(ThemeSource.Kind.allCases, id: \.self) { Text(ThemeTab.title($0)).tag($0) }
      }
      .accessibilityIdentifier("themes.sourceKind")
      sourceField
      if let sourceProblem { FieldProblem(sourceProblem) }
      if ThemeSource.takesVersion(spec), pendingKind == nil {
        LabeledContent(L10n.t("themes.version.label")) {
          CommitField(name: L10n.t("themes.version.label"), text: theme.options["version"]?.stringValue ?? "",
                      placeholder: L10n.t("themes.version.placeholder")) { typed in
            let trimmed = StylesModel.trim(typed)
            theme.setOption("version", trimmed.isEmpty ? nil : .string(trimmed))
            return true
          }
          .frame(maxWidth: 120)
        }
        Note(L10n.t("themes.version.note"))
      }
      modeRow
    }
  }

  @ViewBuilder private var sourceField: some View {
    let current = pendingKind == nil ? ThemeSource.display(spec) : ""
    switch kind {
    case .catalog:
      Note(L10n.t("themes.source.catalogNote"))
    case .repo:
      CommitField(name: L10n.t("themes.source.repo"), text: current, placeholder: L10n.t("themes.source.repoPlaceholder"), monospaced: true) {
        write($0, .repo)
      }
    case .address:
      CommitField(name: L10n.t("themes.source.address"), text: current, placeholder: L10n.t("themes.source.addressPlaceholder"), monospaced: true) {
        write($0, .address)
      }
    case .file:
      CommitField(name: L10n.t("themes.source.file"), text: current, placeholder: L10n.t("themes.source.filePlaceholder"), monospaced: true) {
        write($0, .file)
      }
      Button(L10n.t("themes.source.chooseFile")) {
        if let path = FilePick.one(extensions: ["css"], message: L10n.t("themes.source.file"), start: styles.project.path, folders: true) {
          _ = write(ThemeSource.projectPath(path, project: styles.project.path), .file)
        }
      }
    }
  }

  /// A source field's text into `theme:`, or the problem under the field.
  private func write(_ typed: String, _ kind: ThemeSource.Kind) -> Bool {
    switch ThemeSource.value(typed, kind: kind) {
    case .success(let value):
      sourceProblem = nil
      theme.use(value)
      pendingKind = nil
      return true
    case .failure(let problem):
      sourceProblem = switch problem {
      case .empty: L10n.t("themes.source.empty")
      case .notRepo: L10n.t("themes.source.notRepo")
      case .notAddress: L10n.t("themes.source.notAddress")
      }
      return false
    }
  }

  static func modeName(_ mode: String) -> String {
    switch mode {
    case "light": L10n.t("styles.variables.light")
    case "dark": L10n.t("styles.variables.dark")
    default: mode
    }
  }

  static func modesText(_ modes: [String]) -> String {
    modes.isEmpty ? "—" : modes.map(modeName).joined(separator: ", ")
  }

  /// The modes core knows for the theme: from its answer, else from the list.
  private var knownModes: [String]? {
    if case .loaded(let loaded) = theme.load, let modes = loaded.modes { return modes }
    return theme.catalogTheme?.modes
  }

  @ViewBuilder private var modeRow: some View {
    if let modes = knownModes, modes.count == 1 {
      // core 3 sets a single mode itself and hides the switch (transformer, `supported.length === 1`).
      LabeledContent(L10n.t("themes.mode.label"), value: Self.modeName(modes[0]))
      Note(L10n.t("themes.mode.fixed", ["mode": Self.modeName(modes[0])]))
    } else {
      Picker(L10n.t("themes.mode.label"), selection: Binding(get: { theme.options["mode"]?.stringValue ?? "both" },
                                                             set: { theme.setOption("mode", .string($0)) })) {
        Text(L10n.t("themes.mode.both")).tag("both")
        Text(L10n.t("themes.mode.light")).tag("light")
        Text(L10n.t("themes.mode.dark")).tag("dark")
      }
      .accessibilityIdentifier("themes.mode")
    }
  }

  // MARK: Snippets

  private var snippets: [String] { (theme.options["snippets"]?.arrayValue ?? []).compactMap(\.stringValue) }

  private func setSnippets(_ list: [String]) {
    theme.setOption("snippets", list.isEmpty ? nil : .array(list.map(JSONValue.string)))
  }

  private var snippetsSection: some View {
    Section {
      ForEach(Array(snippets.enumerated()), id: \.offset) { index, snippet in
        HStack {
          Text(snippet).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
          Spacer()
          Button(role: .destructive) {
            var list = snippets
            list.remove(at: index)
            setSnippets(list)
          } label: {
            Label(L10n.t("common.removeNamed", ["name": snippet]), systemImage: "minus.circle")
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
        }
      }
      TextField(L10n.t("themes.snippets.placeholder"), text: $snippetDraft, prompt: Text(L10n.t("themes.snippets.placeholder")))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .onSubmit(addSnippet)
        .accessibilityIdentifier("themes.snippetField")
      HStack {
        Button(L10n.t("themes.snippets.add"), action: addSnippet)
          .disabled(StylesModel.trim(snippetDraft).isEmpty)
        Button(L10n.t("themes.source.chooseFile")) {
          if let path = FilePick.one(extensions: ["css"], message: L10n.t("themes.snippets.title"), start: styles.project.path) {
            setSnippets(snippets + [ThemeSource.projectPath(path, project: styles.project.path)])
          }
        }
      }
    } header: {
      Text(L10n.t("themes.snippets.title"))
    } footer: {
      Note(L10n.t("themes.snippets.note"))
    }
  }

  private func addSnippet() {
    let typed = StylesModel.trim(snippetDraft)
    guard !typed.isEmpty else { return }
    setSnippets(snippets + [typed])
    snippetDraft = ""
  }

  // MARK: Style Settings

  @ViewBuilder private var styleSettingsSection: some View {
    let values = theme.options["styleSettings"]?.objectValue ?? JSONObject()
    if let info = theme.info, !info.styleSettingsId.isEmpty, let schema = theme.schema, schema != .null {
      Section(L10n.t("themes.styleSettings.title")) {
        StyleSettingsForm(schema: schema, info: info, values: values, query: $optionQuery) { theme.applyStyleSettings($0) }
        // Only what the theme declares: writing any custom property is the Variablen tab's job.
        Note(L10n.t("themes.active.ownValuesHint"))
        Button(L10n.t("themes.active.goToVariables"), action: goToVariables).buttonStyle(.link)
      }
    } else if case .loaded = theme.load {
      Section {
        Note(L10n.t("themes.active.noStyleSettingsNote", ["themeId": displayName]))
      }
    }
  }

  // MARK: Presets

  private var presetsSection: some View {
    Section {
      if theme.presets.isEmpty { Note(L10n.t("themes.presets.none")) }
      ForEach(Array(theme.presets.enumerated()), id: \.offset) { _, preset in presetRow(preset) }
      if savingPreset {
        HStack {
          TextField(L10n.t("themes.active.presetNamePlaceholder"), text: $presetName, prompt: Text(L10n.t("themes.active.presetNamePlaceholder")))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("themes.presetName")
          Button(L10n.t("common.cancel")) { savingPreset = false }
          Button(L10n.t("common.save")) { savePreset() }
            .disabled(StylesModel.trim(presetName).isEmpty)
            .accessibilityIdentifier("themes.presetSave")
        }
      } else if theme.enabled {
        Button(L10n.t("themes.active.saveAsPreset")) {
          presetName = ""
          savingPreset = true
        }
        .accessibilityIdentifier("themes.saveAsPreset")
      }
      if let presetMessage { Callout(.error, presetMessage) }
    } header: {
      Text(L10n.t("themes.presets.title"))
    } footer: {
      Note(L10n.t("themes.presets.description"))
    }
  }

  private func presetRow(_ preset: JSONValue) -> some View {
    let name = preset["name"]?.stringValue ?? ""
    return HStack {
      VStack(alignment: .leading) {
        Text(name)
        Text(L10n.t("themes.presets.basisLabel", ["base": preset["baseThemeId"]?.stringValue ?? ""])).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      // Active when the theme runs with exactly the preset's options, as core reads them.
      if theme.enabled, Self.sameValue(.object(theme.options), .object(Self.presetOptions(preset))) {
        StateBadge(text: L10n.t("themes.presets.active"), color: .green)
      } else {
        Button(L10n.t("themes.presets.apply")) { applyPreset(preset) }
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

  /// A preset's options without what core 3 passes over (`calloutStyle` of a QuartzControl preset).
  static func presetOptions(_ preset: JSONValue) -> JSONObject {
    var options = preset["options"]?.objectValue ?? JSONObject()
    for key in ThemeLegacy.ignoredOptions { options[key] = nil }
    return options
  }

  /// Equal as data, whatever order the keys were written in (the config's YAML may reorder them).
  static func sameValue(_ a: JSONValue, _ b: JSONValue) -> Bool {
    switch (a, b) {
    case (.object(let x), .object(let y)):
      Set(x.keys) == Set(y.keys) && x.keys.allSatisfy { sameValue(x[$0]!, y[$0]!) }
    case (.array(let x), .array(let y)):
      x.count == y.count && zip(x, y).allSatisfy { sameValue($0, $1) }
    default:
      a == b
    }
  }

  /// The preset's options become the entry's; nothing to install with core 3.
  private func applyPreset(_ preset: JSONValue) {
    presetMessage = nil
    let options = Self.presetOptions(preset)
    theme.updateEntry { $0 = options }
    theme.setEnabled(true)
  }

  private func savePreset() {
    let name = StylesModel.trim(presetName)
    guard !name.isEmpty else { return }
    var options = theme.options
    for key in ThemeLegacy.ignoredOptions { options[key] = nil }
    if options["mode"] == nil { options["mode"] = .string("both") }
    if options["styleSettings"] == nil { options["styleSettings"] = .object(JSONObject()) }
    let now = Date()
    let preset = JSONObject([
      ("id", .string("preset-\(Int((now.timeIntervalSince1970 * 1000).rounded()))")), ("name", .string(name)),
      ("createdAt", .string(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now))),
      ("baseThemeId", .string(spec.isEmpty ? "default" : spec)), ("options", .object(options))
    ])
    do {
      try ThemePresets.save(.object(preset), project: styles.project.path)
      savingPreset = false
      Task { await theme.reloadPresets() }
    } catch {
      presetMessage = StylesModel.message(error)
      Announce.post(presetMessage!)
    }
  }

  private func deletePreset(_ preset: JSONValue) async {
    let name = preset["name"]?.stringValue ?? ""
    let (question, detail) = Confirm.split(L10n.t("themes.presets.confirmDelete", ["name": name]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("themes.presets.confirmDeleteAction"), destructive: true,
                            window: unsaved?.window) else { return }
    presetMessage = nil
    do {
      try ThemePresets.delete(id: preset["id"]?.stringValue ?? "", project: styles.project.path)
      Announce.post(L10n.t("themes.presets.deletedAnnounce", ["name": name]))
    } catch {
      presetMessage = StylesModel.message(error)
      Announce.post(presetMessage!)
    }
    await theme.reloadPresets()
  }

  // MARK: Cleanup

  private var cleanupSection: some View {
    let found = theme.legacy
    return Section(L10n.t("themes.cleanup.title")) {
      if !found.packages.isEmpty { Text(L10n.t("themes.cleanup.packages", ["list": found.packages.joined(separator: ", ")])) }
      if !found.options.isEmpty { Text(L10n.t("themes.cleanup.options", ["list": found.options.joined(separator: ", ")])) }
      if found.colors > 0 {
        Text(L10n.t("themes.cleanup.colors", ["count": String(found.colors)], count: found.colors))
      } else if !found.styleSettingsPatch.isEmpty {
        Text(L10n.t("themes.cleanup.parts"))
      }
      if !found.isEmpty {
        Note(L10n.t("themes.cleanup.note"))
        HStack {
          Button(theme.cleaning ? L10n.t("themes.cleanup.running") : L10n.t("themes.cleanup.action")) { Task { await theme.clean() } }
            .disabled(theme.cleaning || styles.dirty)
            .accessibilityIdentifier("themes.cleanup")
          if styles.dirty { Text(L10n.t("styles.migrate.saveFirst")).foregroundStyle(.secondary) }
        }
      }
      if let message = theme.cleanupMessage { Callout(.warning, message) }
    }
  }
}
