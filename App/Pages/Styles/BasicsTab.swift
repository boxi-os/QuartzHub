import QuartzHubCore
import SwiftUI

/// Basis, the bottom layer of the cascade (QuartzControl's `Styles/Basics.tsx`): the classic colours
/// and the three font slots Quartz writes straight into `:root` from the config. Everything the
/// other three tabs do sits on top of this.
struct BasicsTab: View {
  let model: StylesModel
  let goTo: (StylesModel.Tab) -> Void
  /// Bumped by the page after a save: saving may have fetched the Google fonts into the project.
  let savedRound: Int
  /// The page's save, as the toolbar runs it.
  let save: () async -> Void

  @Environment(\.unsavedGuard) private var unsaved
  @State private var faces: [SiteFonts.Face] = []
  @State private var built: Bool?
  @State private var unused: [FontService.Unused] = []
  @State private var removing: String?
  @State private var unusedError: String?
  @State private var fixBusy: String?
  @State private var fixError: String?
  @State private var fetching = false
  @State private var pendingFont: String?
  @State private var importFamily = ""
  @State private var importSlot = ""
  @State private var importing = false
  @State private var importMessage: String?

  static let slots = ["header", "body", "code"]
  static let fontVariable = ["header": "headerFont", "body": "bodyFont", "code": "codeFont"]

  private var config: QuartzConfig { model.config ?? QuartzConfig() }
  private var theme: JSONObject { config.theme }
  private var fontOrigin: String { theme["fontOrigin"]?.stringValue ?? "googleFonts" }
  private var themeId: String? { FontDelivery.activeThemeId(config) }

  var body: some View {
    SettingsForm {
      themeBanner
      fontsSection
      deliverySection
      fixesSection
      importSection
      unusedSection
      colorSections
    }
    .task(id: "\(themeId ?? "")|\(savedRound)") { await reloadFaces() }
    .task(id: "\(draftFamilies.joined(separator: "|"))|\(faces.count)|\(savedRound)") { await reloadUnused() }
  }

  // MARK: The theme above

  /// Which of these values the active theme takes over, asked per variable of the installed theme:
  /// a theme that declares no `--textHighlight` leaves that field working. Nothing is disabled.
  private func overriddenByTheme(_ variable: String) -> Bool {
    model.graph?.vars[variable]?["origin"] == .string("theme")
  }

  private var colorKeys: [String] {
    var keys: [String] = []
    if case .object(let colors)? = theme["colors"] {
      for mode in colors.keys {
        guard case .object(let palette)? = colors[mode] else { continue }
        for key in palette.keys where !keys.contains(key) { keys.append(key) }
      }
    }
    return keys
  }

  @ViewBuilder private var themeBanner: some View {
    if let plugin = config.plugins.first(where: { FontDelivery.enabled($0) && FontDelivery.isThemePlugin($0) }) {
      Callout(.warning) {
        Group {
          if model.graphLoading {
            Text(L10n.t("themeEditor.overrideChecking"))
          } else {
            Text(L10n.t("themeEditor.overrideCounted", [
              "themeId": themeId ?? (plugin.source?.stringValue ?? ""),
              "colors": String(colorKeys.filter(overriddenByTheme).count), "totalColors": String(colorKeys.count),
              "fonts": String(Self.slots.filter { overriddenByTheme(Self.fontVariable[$0]!) }.count), "totalFonts": String(Self.slots.count)
            ]))
          }
        }
        Text(L10n.t("themeEditor.overrideStillEditable")).foregroundStyle(.secondary)
        Button(L10n.t("themeEditor.goToThemeTab")) { goTo(.theme) }.buttonStyle(.link)
      }
      .padding(.horizontal, Spacing.page)
      .padding(.top, Spacing.s)
    }
  }

  // MARK: Fonts

  private var fontsSection: some View {
    SettingsSection(L10n.t("themeEditor.fonts"), note: fontOrigin == "local" ? L10n.t("themeEditor.localHint")
                    : L10n.t("themeEditor.googleFontsHint", ["count": String(GoogleFontList.families.count)])) {
      Picker(L10n.t("themeEditor.fontSource"), selection: Binding(get: { fontOrigin }, set: { setTheme("fontOrigin", .string($0)) })) {
        Text(L10n.t("themeEditor.googleFonts")).tag("googleFonts")
        Text(L10n.t("themeEditor.local")).tag("local")
        if fontOrigin != "googleFonts" && fontOrigin != "local" { Text(verbatim: fontOrigin).tag(fontOrigin) }
      }
      .accessibilityIdentifier("styles.fontSource")
      ForEach(Self.slots, id: \.self) { slot in fontField(slot) }
    }
  }

  private func family(_ slot: String) -> String {
    FontDelivery.familyOf(theme["typography"]?[slot])
  }

  private var draftFamilies: [String] { Self.slots.map(family).filter { !$0.isEmpty } }

  /// The field edits the name and leaves the weights of an object entry alone.
  private func setFamily(_ slot: String, _ name: String) {
    var typography = theme["typography"]?.objectValue ?? JSONObject()
    if case .object(var entry)? = typography[slot] {
      entry["name"] = .string(name)
      typography[slot] = .object(entry)
    } else {
      typography[slot] = .string(name)
    }
    setTheme("typography", .object(typography))
  }

  private func setTheme(_ key: String, _ value: JSONValue) {
    var next = config
    next.theme[key] = value
    model.setConfig(next)
  }

  /// The suggestions: under "local" the families the project declares, else Google's list.
  private func suggestions(_ text: String) -> [(name: String, meta: String)] {
    let query = StylesModel.trim(text)
    if fontOrigin == "local" {
      var seen: [String: String] = [:]
      var order: [String] = []
      for face in faces {
        if seen[face.family] == nil { order.append(face.family) }
        seen[face.family] = face.origin == "theme" ? L10n.t("themeEditor.fontFromTheme") : face.source
      }
      return order.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }.prefix(40).map { ($0, seen[$0] ?? "") }
    }
    return GoogleFontList.families.lazy.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
      .prefix(40).map { ($0.name, Self.categoryLabel($0.category)) }
  }

  static func categoryLabel(_ category: GoogleFontList.Category) -> String {
    switch category {
    case .sansSerif: L10n.t("themeEditor.fontCategory.sansSerif")
    case .serif: L10n.t("themeEditor.fontCategory.serif")
    case .monospace: L10n.t("themeEditor.fontCategory.monospace")
    case .display: L10n.t("themeEditor.fontCategory.display")
    case .handwriting: L10n.t("themeEditor.fontCategory.handwriting")
    }
  }

  @ViewBuilder private func fontField(_ slot: String) -> some View {
    let name = family(slot)
    let label = L10n.t("themeEditor.fontFor", ["slot": Self.slotTitle(slot)])
    let overridden = overriddenByTheme(Self.fontVariable[slot]!)
    let ownVariable = model.overrides.contains { $0.key == Self.fontVariable[slot]! }
    let trimmed = StylesModel.trim(name)
    // Google's CSS2 API is case-sensitive and leaves an unknown family out without a word; the list
    // is from a fixed date, so a name missing from it is worth a sentence, not a refusal, and not
    // even that when the project declares the family itself.
    let declaredHere = faces.contains { $0.family.lowercased() == trimmed.lowercased() }
    let unknownToGoogle = fontOrigin != "local" && !trimmed.isEmpty && !GoogleFontList.names.contains(trimmed) && !declaredHere
    let spelledDifferently = unknownToGoogle ? GoogleFontList.families.first { $0.name.lowercased() == trimmed.lowercased() }?.name : nil
    VStack(alignment: .leading, spacing: 4) {
      LabeledContent(label) {
        TextField(label, text: Binding(get: { name }, set: { setFamily(slot, $0) }))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .foregroundStyle(overridden || ownVariable ? .secondary : .primary)
          .textInputSuggestions {
            ForEach(suggestions(name), id: \.name) { item in
              HStack {
                Text(item.name)
                Spacer()
                Text(item.meta).foregroundStyle(.secondary)
              }
              .textInputCompletion(item.name)
            }
          }
          .accessibilityIdentifier("styles.font.\(slot)")
      }
      if let spelledDifferently {
        warning(L10n.t("themeEditor.fontSpelledDifferently", ["name": spelledDifferently]))
      } else if unknownToGoogle {
        warning(L10n.t("themeEditor.fontUnknownToGoogle", ["date": GoogleFontList.fetchedOn]))
      }
      if overridden { warning(L10n.t("themeEditor.overriddenByTheme")) }
      if ownVariable {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          warning(L10n.t("themeEditor.overriddenByVariable", ["variable": Self.fontVariable[slot]!]))
          Button(L10n.t("themeEditor.goToVariablesTab")) { goTo(.variables) }.buttonStyle(.link).font(.caption)
        }
      }
    }
  }

  private func warning(_ text: String) -> some View {
    Callout(.warning, text)
  }

  // MARK: Where the fonts come from

  /// One question for the user, two settings underneath: Quartz's own `cdnCaching` and the Fonts
  /// plugin's `fontOrigin`. Both are reported and both are flipped together.
  private var deliverySection: some View {
    let loaders = FontDelivery.loaders(config)
    let google = FontDelivery.callsGoogle(config)
    let state = FontDelivery.buildState(config, faces: faces, built: built)
    let baseUrl = config.configuration["baseUrl"]?.stringValue ?? ""
    return SettingsSection(L10n.t("themeEditor.delivery.heading"), note: L10n.t("themeEditor.delivery.description")) {
      VStack(alignment: .leading, spacing: 2) {
        if loaders.isEmpty { Note(L10n.t("styleEditor.current.noLoader")) }
        ForEach(loaders, id: \.self) { loader in
          Text(Self.loaderText(loader)).font(.callout)
            .foregroundStyle(loader.mode == "google" ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
      }
      Toggle(L10n.t("themeEditor.delivery.selfHost"), isOn: Binding(
        get: { loaders.contains { $0.mode == "selfHosted" } && !google },
        set: { model.setConfig(FontDelivery.withSelfHostedFonts(config, $0)) }))
        .accessibilityIdentifier("styles.selfHost")
      if case .notBuilt? = state { warning(L10n.t("styleEditor.current.fontsNotBuilt")) }
      if case .missing(let families)? = state {
        warning(L10n.t("styleEditor.current.fontsMissingFromBuild", ["families": families.joined(separator: ", ")]))
      }
      if model.quartzStillDownloadsFonts {
        HStack(alignment: .firstTextBaseline) {
          warning(L10n.t("themeEditor.delivery.quartzStillDownloads"))
          Spacer()
          // The page's own save: it also writes whatever else is pending, and resets `dirty`. With
          // other edits pending the button says so; "Jetzt ins Projekt holen" saved them silently
          // (review 2026-11-13, nebenbei).
          Button(fetching ? L10n.t("themeEditor.delivery.fetching")
                 : model.dirty ? L10n.t("themeEditor.delivery.saveAndFetch") : L10n.t("themeEditor.delivery.fetchNow")) {
            Task {
              fetching = true
              await savePage()
              fetching = false
            }
          }
          .disabled(fetching || model.saving)
        }
      } else if case .notFetched(let families)? = state {
        warning(L10n.t("styleEditor.current.fontsNotFetched", ["families": families.joined(separator: ", ")]))
      }
      if case .noRule(let families)? = state {
        warning(L10n.t("styleEditor.current.fontsNoRule", ["families": families.joined(separator: ", ")]))
      }
      // Its own control: there is no option to serve the theme's fonts locally, so the only way to
      // stop the requests to unpkg is to drop them, which changes how the site looks.
      if FontDelivery.themeFontsEnabled(config) || FontDelivery.hasTheme(config) {
        let on = FontDelivery.themeFontsEnabled(config)
        Toggle(L10n.t("themeEditor.delivery.themeFonts"), isOn: Binding(get: { on }, set: { model.setConfig(FontDelivery.withThemeFonts(config, $0)) }))
        Note(on ? L10n.t("themeEditor.delivery.themeFontsHint") : L10n.t("themeEditor.delivery.themeFontsOff"))
      }
      // The plugin's self-hosting rewrites the font URLs to the base URL and stops the build without one.
      if loaders.contains(where: { $0.via == "plugin" && $0.mode == "selfHosted" }) && baseUrl.isEmpty {
        Callout(.error, L10n.t("themeEditor.delivery.baseUrlMissing"))
      }
    }
  }

  /// One literal key per loader, so `qh-check i18n` sees every one.
  static func loaderText(_ loader: FontDelivery.Loader) -> String {
    switch (loader.via, loader.mode) {
    case ("core", "google"): L10n.t("themeEditor.delivery.state.core.google")
    case ("core", _): L10n.t("themeEditor.delivery.state.core.selfHosted")
    case ("plugin", "google"): L10n.t("themeEditor.delivery.state.plugin.google")
    case ("plugin", _): L10n.t("themeEditor.delivery.state.plugin.selfHosted")
    default: L10n.t("themeEditor.delivery.state.theme.cdn")
    }
  }

  private func savePage() async {
    await save()
  }

  // MARK: Known conflicts

  /// The ready-made stylesheets, only for conflicts this project has. Nothing is written until the
  /// button: the fix lands as an ordinary file under quartz/styles/custom/.
  @ViewBuilder private var fixesSection: some View {
    let applicable = FontDelivery.cssFixes.filter { $0.appliesTo(config) }
    if !applicable.isEmpty {
      SettingsSection(L10n.t("styles.fixes.heading"), note: L10n.t("styles.fixes.description")) {
        ForEach(applicable, id: \.id) { fix in
          let existing = model.fileSet?.files.first { $0.name == fix.fileName }
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
              Text(Self.fixTitle(fix.id))
              Text(Self.fixSummary(fix.id)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let existing {
              Text(L10n.t("styles.fixes.alreadyAdded", ["file": existing.name])).font(.callout).foregroundStyle(.secondary)
              Button(L10n.t("styles.fixes.open")) { goTo(.customCss) }.buttonStyle(.link)
            } else {
              Button(fixBusy == fix.id ? L10n.t("styles.fixes.adding") : L10n.t("styles.fixes.add")) { Task { await add(fix) } }
                .disabled(fixBusy != nil)
            }
          }
        }
        if let fixError { Callout(.error, fixError) }
      }
    }
  }

  /// The texts a fix's comment is written from, one literal key each.
  static func fixText(_ key: String) -> String {
    switch key {
    case "styles.fixes.heading-fonts.title": L10n.t("styles.fixes.heading-fonts.title")
    case "styles.fixes.heading-fonts.comment": L10n.t("styles.fixes.heading-fonts.comment")
    default: key
    }
  }

  static func fixTitle(_ id: String) -> String {
    id == "heading-fonts" ? L10n.t("styles.fixes.heading-fonts.title") : id
  }

  static func fixSummary(_ id: String) -> String {
    id == "heading-fonts" ? L10n.t("styles.fixes.heading-fonts.summary") : ""
  }

  private func add(_ fix: FontDelivery.CssFix) async {
    fixBusy = fix.id
    fixError = nil
    defer { fixBusy = nil }
    do {
      let created = try await StyleFiles.create(fix.fileName, project: model.project.path)
      try await StyleFiles.write(created.relativePath, fix.content(Self.fixText), project: model.project.path)
      await model.reloadFiles()
      // Creating rewrote the load order in custom.scss: the CSS tab's draft is read again.
      await model.reloadScss(after: .stylesheets)
      goTo(.customCss)
    } catch {
      fixError = StylesModel.message(error)
    }
  }

  // MARK: A font file of one's own

  private var importSection: some View {
    SettingsSection(L10n.t("themeEditor.localFontHeading"), note: L10n.t("themeEditor.localFontDescription")) {
      if pendingFont == nil {
        Button(L10n.t("themeEditor.localFontPick")) { pick() }
          .accessibilityIdentifier("styles.fontImport")
      } else {
        TextField(L10n.t("themeEditor.localFontFamily"), text: $importFamily)
        Picker(L10n.t("themeEditor.localFontSlot"), selection: $importSlot) {
          Text(L10n.t("themeEditor.localFontNoSlot")).tag("")
          ForEach(Self.slots, id: \.self) { Text(L10n.t("themeEditor.fontFor", ["slot": Self.slotTitle($0)])).tag($0) }
        }
        HStack {
          Spacer()
          Button(L10n.t("common.cancel")) { pendingFont = nil }
          Button(importing ? L10n.t("themeEditor.localFontImporting") : L10n.t("themeEditor.localFontConfirm")) { Task { await importFont() } }
            .disabled(importing || StylesModel.trim(importFamily).isEmpty)
        }
      }
      if let importMessage { Note(importMessage).textSelection(.enabled) }
    }
  }

  private func pick() {
    importMessage = nil
    guard let picked = FilePick.one(extensions: ["ttf", "otf", "woff", "woff2"], message: L10n.t("themeEditor.localFontPick")) else { return }
    let base = picked.split(separator: "/").last.map(String.init) ?? picked
    let stem = base.replacing(/\.(ttf|otf|woff2?|)$/.ignoresCase(), with: "")
    importFamily = StylesModel.trim(stem.replacing(/[-_]+/, with: " "))
    pendingFont = picked
  }

  private func importFont() async {
    guard let source = pendingFont else { return }
    let family = StylesModel.trim(importFamily)
    guard !family.isEmpty else { return }
    importing = true
    importMessage = nil
    defer { importing = false }
    let environment = await AppServices.current()
    let fonts = FontService(readConfig: { try await ConfigFile.read(project: $0, runtime: environment.runtime) })
    do {
      let imported = try await fonts.importFontFile(source, family: family, project: model.project.path)
      if !importSlot.isEmpty { setFamily(importSlot, family) }
      await reloadFaces()
      // The import wrote an @font-face rule into the stylesheets: the CSS tab's draft is read again.
      await model.reloadScss(after: .fontImport)
      // What the rule says now: the weight comes out of the file, and when the file names none
      // that is worth saying too.
      if let face = imported.face {
        importMessage = face.italic ? L10n.t("themeEditor.fontImportDetectedItalic", ["family": family, "weight": face.weight])
          : L10n.t("themeEditor.fontImportDetected", ["family": family, "weight": face.weight])
      } else {
        importMessage = L10n.t("themeEditor.fontImportUndetected", ["family": family])
      }
      Announce.post(importMessage ?? "")
      pendingFont = nil
      importFamily = ""
      importSlot = ""
    } catch {
      importMessage = StylesModel.message(error)
    }
  }

  // MARK: Fonts nothing names any more

  /// Offered one by one and never removed by itself: a family can be named in ways the search
  /// does not see.
  @ViewBuilder private var unusedSection: some View {
    if !unused.isEmpty {
      SettingsSection(L10n.t("themeEditor.unusedFonts.heading"), note: L10n.t("themeEditor.unusedFonts.description")) {
        ForEach(unused, id: \.family) { font in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(font.family)
              Text(font.files.isEmpty ? L10n.t("themeEditor.unusedFonts.noFile") : font.files.joined(separator: ", "))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .help(font.files.joined(separator: ", "))
            }
            Spacer()
            Button(role: .destructive) {
              Task { await remove(font) }
            } label: {
              Label(removing == font.family ? L10n.t("themeEditor.unusedFonts.removing") : L10n.t("common.removeNamed", ["name": font.family]),
                    systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(removing != nil)
          }
        }
        if let unusedError { Callout(.error, unusedError) }
      }
    }
  }

  private func remove(_ font: FontService.Unused) async {
    let text = font.files.isEmpty ? L10n.t("themeEditor.unusedFonts.confirmNoFiles", ["family": font.family])
      : L10n.t("themeEditor.unusedFonts.confirm", ["family": font.family], count: font.files.count)
    let (question, detail) = Confirm.split(text)
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("themeEditor.unusedFonts.confirmButton"), destructive: true,
                            window: unsaved?.window) else { return }
    removing = font.family
    unusedError = nil
    defer { removing = nil }
    let environment = await AppServices.current()
    let fonts = FontService(readConfig: { try await ConfigFile.read(project: $0, runtime: environment.runtime) })
    do {
      _ = try await fonts.removeImportedFont(font.family, project: model.project.path)
      await reloadFaces()
      await model.reloadScss(after: .fontRemoval)
    } catch {
      unusedError = StylesModel.message(error)
    }
  }

  // MARK: Colours

  /// The palettes under each other, each mode with its own rows: side by side every cell was half
  /// as wide (QuartzControl's `ColorGroup`). Leaves at the top level come first.
  @ViewBuilder private var colorSections: some View {
    let colors = theme["colors"]?.objectValue ?? JSONObject()
    let leaves = colors.keys.filter { colors[$0]?.stringValue != nil }
    if !leaves.isEmpty || colors.isEmpty {
      SettingsSection(L10n.t("themeEditor.colors")) {
        ForEach(leaves, id: \.self) { key in colorRow(path: [key], name: key) }
      }
    }
    ForEach(colors.keys.filter { colors[$0]?.objectValue != nil }, id: \.self) { mode in
      SettingsSection(leaves.isEmpty ? "\(L10n.t("themeEditor.colors")) · \(Self.modeTitle(mode))" : Self.modeTitle(mode)) {
        ForEach((colors[mode]?.objectValue?.keys ?? []).filter { colors[mode]?[$0]?.stringValue != nil }, id: \.self) { key in
          colorRow(path: [mode, key], name: key)
        }
      }
    }
  }

  /// The palettes and font slots in words; their keys are Quartz's ("lightMode", "header"), shown
  /// as they are only when QuartzHub has no word (review 2026-11-13, nebenbei).
  static func modeTitle(_ mode: String) -> String {
    switch mode {
    case "lightMode": L10n.t("themeEditor.modes.light")
    case "darkMode": L10n.t("themeEditor.modes.dark")
    default: mode
    }
  }

  static func slotTitle(_ slot: String) -> String {
    switch slot {
    case "header": L10n.t("themeEditor.slots.header")
    case "body": L10n.t("themeEditor.slots.body")
    case "code": L10n.t("themeEditor.slots.code")
    default: slot
    }
  }

  private func colorValue(_ path: [String]) -> String {
    var value: JSONValue? = theme["colors"]
    for key in path { value = value?[key] }
    return value?.stringValue ?? ""
  }

  private func setColor(_ path: [String], _ text: String) {
    var colors = theme["colors"]?.objectValue ?? JSONObject()
    if path.count == 1 {
      colors[path[0]] = .string(text)
    } else {
      var palette = colors[path[0]]?.objectValue ?? JSONObject()
      palette[path[1]] = .string(text)
      colors[path[0]] = .object(palette)
    }
    setTheme("colors", .object(colors))
  }

  /// Dimmed, not disabled: the value has no effect while the theme is on, but it is the one that
  /// applies when the theme goes, and right now for a theme that does not declare it.
  private func colorRow(path: [String], name: String) -> some View {
    let overridden = overriddenByTheme(name)
    return LabeledContent {
      CssColorField(name: name, value: Binding(get: { colorValue(path) }, set: { setColor(path, $0) }),
                    identifier: "styles.color.\(path.joined(separator: "."))")
    } label: {
      HStack(spacing: 6) {
        Text(name).foregroundStyle(overridden ? .secondary : .primary)
        if overridden {
          Text(L10n.t("themeEditor.overriddenShort")).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.orange)
        }
      }
    }
    .help(overridden ? L10n.t("themeEditor.overriddenByTheme") : "")
  }

  // MARK: Reading

  private func reloadFaces() async {
    let path = model.project.path
    let theme = themeId
    let read = await Task.detached { (SiteFonts.faces(project: path, themeId: theme), SiteFonts.previewFonts(project: path, families: []).built) }.value
    faces = read.0
    built = read.1
  }

  private func reloadUnused() async {
    let environment = await AppServices.current()
    let fonts = FontService(readConfig: { try await ConfigFile.read(project: $0, runtime: environment.runtime) })
    unused = (try? await fonts.unusedImportedFonts(project: model.project.path, draftFamilies: draftFamilies)) ?? []
  }
}
