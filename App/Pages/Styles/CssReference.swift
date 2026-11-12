import AppKit
import CoreText
import QuartzHubCore
import SwiftUI

/// The CSS tab's reference in the inspector (QuartzControl's `CssVariableReference.tsx`): the
/// variables usable at the point custom.scss is loaded. Every click inserts at the editor's cursor:
/// the name as `var(--name)`, a swatch as the literal that half resolves to now (a rule that has to
/// match a colour rather than follow it), a callout type as its whole override scaffold. ⌥-click
/// copies instead.
struct CssVariableReference: View {
  let model: StylesModel
  let insert: (String) -> Void
  let goToVariables: () -> Void

  @SceneStorage("styleEditor.cssVars.openGroups") private var openGroups = "baseColors"
  @SceneStorage("styleEditor.cssVars.calloutsOpen") private var calloutsOpen = false
  @State private var search = ""
  @State private var copied: String?

  private var ctx: VariableResolve.Context { model.context }

  /// Unsearched: the catalogue and the user's own keys; a theme's thousand would bury the handful
  /// anyone inserts. A search goes through the whole table, at most 80.
  private var groups: [(group: String, keys: [String])] {
    let query = VariableResolve.normalizeQuery(search)
    let known = Set(CssVariables.all.map(\.key))
    let extra = (query.isEmpty ? model.overrides.map(\.key) : (ctx.vars?.keys ?? [])).filter { !known.contains($0) }
    var defs = CssVariables.all.map { (key: $0.key, group: $0.group) } + extra.map { (key: $0, group: "discovered") }
    if !query.isEmpty { defs = Array(defs.filter { $0.key.lowercased().contains(query) }.prefix(80)) }
    var out: [(group: String, keys: [String])] = []
    for def in defs {
      if let index = out.firstIndex(where: { $0.group == def.group }) { out[index].keys.append(def.key) } else { out.append((def.group, [def.key])) }
    }
    return out
  }

  var body: some View {
    Section {
      HStack(alignment: .firstTextBaseline) {
        Note(L10n.t("styleEditor.cssVars.description"))
        Button(L10n.t("styleEditor.cssVars.goToVariables"), action: goToVariables).buttonStyle(.link).font(.callout)
      }
      TextField(L10n.t("styleEditor.cssVars.searchPlaceholder"), text: $search, prompt: Text(L10n.t("styleEditor.cssVars.searchPlaceholder")))
        .labelsHidden().textFieldStyle(.roundedBorder)
      let list = groups
      if list.isEmpty { Note(L10n.t("styleEditor.cssVars.noResults")) }
      ForEach(list, id: \.group) { entry in
        let open = !search.isEmpty || VariablesPlace.lines(openGroups).contains(entry.group)
        Fold(isExpanded: Binding(get: { open }, set: { _ in openGroups = VariablesPlace.toggled(openGroups, entry.group) })) {
          ForEach(entry.keys, id: \.self) { key in row(key) }
        } label: {
          HStack {
            Text(entry.group == "discovered" ? L10n.t("styleEditor.cssVars.discoveredGroup") : VariablesTab.groupLabel(entry.group)).fontWeight(.semibold)
            Text("\(entry.keys.count)").foregroundStyle(.secondary)
          }
        }
      }
      Note(L10n.t("styleEditor.cssVars.rowHint"))
      if let copied { Text(L10n.t("common.copied", ["value": copied])).font(.caption).foregroundStyle(.green) }
    } header: {
      Text(L10n.t("styleEditor.cssVars.heading"))
    }
    Section {
      Note(L10n.t("styleEditor.cssVars.calloutsDescription"))
      Fold(isExpanded: $calloutsOpen) {
        ForEach(CssVariables.callouts, id: \.type) { callout in calloutRow(callout) }
      } label: {
        HStack {
          Text(L10n.t("styleEditor.cssVars.calloutsGroup")).fontWeight(.semibold)
          Text("\(CssVariables.callouts.count)").foregroundStyle(.secondary)
        }
      }
    } header: {
      Text(L10n.t("styleEditor.cssVars.calloutsHeading"))
    }
  }

  /// One handler for both ways: ⌥ means the clipboard, everything else the editor.
  private func put(_ text: String, label: String) {
    if NSEvent.modifierFlags.contains(.option) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      copied = label
      Announce.post(L10n.t("common.copied", ["value": label]))
    } else {
      insert(text)
    }
  }

  private func row(_ key: String) -> some View {
    let def = CssVariables.definition(key)
    let light = VariableResolve.resolvedValue(key, .light, ctx)
    let dark = VariableResolve.resolvedValue(key, .dark, ctx)
    let raw = VariableResolve.effectiveValue(key, .light, ctx) ?? VariableResolve.effectiveValue(key, .dark, ctx) ?? ""
    let isColor = def?.kind == "color" || CssColor.hex(light) != nil
    let isFont = def?.kind == "font"
    func modeValue(_ resolved: String?) -> String { CssColor.hex(resolved) ?? resolved ?? raw }
    return HStack(spacing: 6) {
      if isColor {
        ForEach([VariableResolve.Mode.light, .dark], id: \.self) { mode in
          let resolved = mode == .light ? light : dark
          Button { put(modeValue(resolved), label: "--\(key)") } label: {
            VariableSwatch(value: resolved, ground: VariableResolve.pageGround(mode, ctx), size: 14)
          }
          .buttonStyle(.plain)
          .help(L10n.t("styleEditor.cssVars.insertValueHint", ["value": modeValue(resolved)]))
          .accessibilityLabel(L10n.t("styleEditor.cssVars.insertValueLabel", ["key": key, "mode": mode == .light ? L10n.t("styles.variables.light") : L10n.t("styles.variables.dark")]))
        }
      }
      Button("--\(key)") { put("var(--\(key))", label: "--\(key)") }
        .buttonStyle(.link).font(.system(.callout, design: .monospaced)).lineLimit(1)
        .help(L10n.t("styleEditor.cssVars.insertHint"))
      Spacer(minLength: 2)
      if isFont {
        let stack = light ?? raw
        Button("Aa") { put(stack, label: "--\(key)") }
          .buttonStyle(.borderless)
          .font(PreviewFontRegistry.font(FontDelivery.primaryFamily(stack), size: 13) ?? .body)
          .help(L10n.t("styleEditor.cssVars.insertValueHint", ["value": stack]))
      } else if !isColor && !raw.isEmpty {
        Button(L10n.t("styleEditor.cssVars.insertValue")) { put(raw, label: "--\(key)") }
          .buttonStyle(.borderless).font(.caption)
          .help(L10n.t("styleEditor.cssVars.insertValueHint", ["value": raw]))
      }
    }
  }

  /// A callout type's --color/--border/--bg mean something only inside its own selector, so the
  /// click inserts the whole scaffold, filled with today's values.
  private func calloutRow(_ callout: CssVariables.Callout) -> some View {
    let colors = ctx.colors
    let lightMode = colors["lightMode"]?.objectValue, darkMode = colors["darkMode"]?.objectValue
    let parts: [(String, String?)] = [("--color", callout.color), ("--border", callout.border), ("--bg", callout.background)]
    return HStack(spacing: 6) {
      ForEach(parts.compactMap { name, value in value.map { (name, $0) } }, id: \.0) { name, value in
        let resolved = CssVariables.resolveCalloutValue(value, lightMode: lightMode, darkMode: darkMode, dark: false)
        let literal = CssColor.hex(resolved) ?? resolved
        Button { put(literal, label: "[!\(callout.type)] \(name)") } label: {
          VariableSwatch(value: resolved, ground: VariableResolve.paletteGround(.light, lightMode), size: 14)
        }
        .buttonStyle(.plain)
        .help(L10n.t("styleEditor.cssVars.insertValueHint", ["value": literal]))
        // A swatch is a picture; without this the three buttons of every row had no name at all
        // (measured 2026-11-10 through the accessibility tree).
        .accessibilityLabel(L10n.t("styleEditor.cssVars.insertCalloutValueLabel", ["callout": "[!\(callout.type)]", "name": name]))
      }
      Button("[!\(callout.type)]") {
        var lines = [".callout[data-callout=\"\(callout.type)\"] {", "  --color: \(callout.color);", "  --border: \(callout.border);"]
        if let bg = callout.background { lines.append("  --bg: \(bg);") }
        lines.append("}\n")
        insert("\n" + lines.joined(separator: "\n"))
      }
      .buttonStyle(.link).font(.system(.callout, design: .monospaced))
      .help(L10n.t("styleEditor.cssVars.calloutsInsertHint"))
      Spacer()
    }
  }
}

/// A plugin's own stylesheets, read only, for the component picked on the CSS tab.
struct PluginReferences: View {
  let references: [StyleFiles.Reference]

  var body: some View {
    if !references.isEmpty {
      Section(L10n.t("styleEditor.referenceHeading")) {
        ForEach(references, id: \.path) { reference in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(reference.label).font(.callout.weight(.medium)).lineLimit(1)
              Spacer()
              Button(L10n.t("styleEditor.openExternally")) { ExternalOpen.openFile(reference.path) }
                .buttonStyle(.link).font(.caption)
            }
            ScrollView {
              Text(reference.content).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 4))
          }
        }
      }
    }
  }
}

/// The fonts a project or its build has, in this process, so a sample shows the site's font and not
/// this machine's (QuartzControl's `loadPreviewFonts`, which added them to `document.fonts`). Each
/// file is read once; a family is drawn with its first face. Read into a descriptor, not registered
/// with the font manager: `CTFontManagerRegisterGraphicsFont` is deprecated since macOS 15, and the
/// sample needs the face, not the system to know it.
@MainActor
enum PreviewFontRegistry {
  private static var registered: Set<String> = []
  private static var descriptors: [String: CTFontDescriptor] = [:]

  static func register(_ faces: [SiteFonts.PreviewFace]) {
    for face in faces {
      let key = "\(face.family)|\(face.weight)|\(face.style)|\(face.unicodeRange ?? "")|\(face.data.count)"
      guard !registered.contains(key) else { continue }
      registered.insert(key)
      // A file this cannot read is no file, and the sample falls back and says so.
      guard let read = CTFontManagerCreateFontDescriptorsFromData(face.data as CFData) as? [CTFontDescriptor],
            let first = read.first else { continue }
      if descriptors[face.family.lowercased()] == nil { descriptors[face.family.lowercased()] = regular(first) }
    }
  }

  /// CSS's generic families: every browser draws them with a real font of the system, so they
  /// are no fallback. QuartzControl asked Chrome's canvas, which knows no `ui-sans-serif`, and
  /// called such a theme's fonts "Ersatzschrift"; here they are the system's.
  static let generic: [String: Font.Design] = [
    "system-ui": .default, "-apple-system": .default, "blinkmacsystemfont": .default, "ui-sans-serif": .default, "sans-serif": .default,
    "ui-serif": .serif, "serif": .serif, "ui-monospace": .monospaced, "monospace": .monospaced, "ui-rounded": .rounded
  ]

  /// The family's font: one of the project's files, else one installed here, else a generic
  /// family's; nil for none.
  static func font(_ family: String, size: CGFloat) -> Font? {
    if let design = generic[family.lowercased()] { return .system(size: size, design: design) }
    if let face = descriptors[family.lowercased()] { return Font(CTFontCreateWithFontDescriptor(face, size, nil)) }
    return installed(family) ? .custom(family, size: size) : nil
  }

  /// A variable face at the weight of a sample, 400. Read from its data it starts at its axis'
  /// default, and Noto Sans (400–700) drew thin where the registered font had drawn it regular
  /// (seen side by side, 2026-11-12). A face without a weight axis stays as it is.
  private static func regular(_ face: CTFontDescriptor) -> CTFontDescriptor {
    let weight = 0x7767_6874 // 'wght'
    let probe = CTFontCreateWithFontDescriptor(face, 12, nil)
    guard let axes = CTFontCopyVariationAxes(probe) as? [[CFString: Any]],
          axes.contains(where: { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue == weight }) else { return face }
    return CTFontDescriptorCreateCopyWithVariation(face, weight as CFNumber, 400)
  }

  private static func installed(_ family: String) -> Bool {
    NSFontManager.shared.availableFontFamilies.contains { $0.lowercased() == family.lowercased() }
  }

  static func isAvailable(_ family: String) -> Bool {
    !family.isEmpty && (generic[family.lowercased()] != nil || descriptors[family.lowercased()] != nil || installed(family))
  }
}

/// "Aktuell geltende Farben und Schriften" (QuartzControl's `ActiveStyles`): what this file writes on
/// top of, resolved through the same chain as the Variablen tab. Collapsed it names the families.
struct ActiveStylesSection: View {
  let model: StylesModel

  @SceneStorage("styles.css.activeStyles") private var open = false
  @State private var faces: [SiteFonts.Face] = []
  @State private var built: Bool?
  @State private var fontsRound = 0
  @State private var copied: String?

  static let colors = ["light", "lightgray", "gray", "darkgray", "dark", "secondary", "tertiary", "highlight", "textHighlight"]
  static let fonts = ["titleFont", "headerFont", "bodyFont", "codeFont"]

  private var ctx: VariableResolve.Context { model.context }
  private var config: QuartzConfig { model.config ?? QuartzConfig() }
  private var families: [String] { Self.fonts.map { FontDelivery.primaryFamily(VariableResolve.resolvedValue($0, .light, ctx)) } }

  var body: some View {
    Section {
      Fold(isExpanded: $open) {
        colorTable
        fontList
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.t("styleEditor.current.heading")).fontWeight(.semibold)
          if !open {
            let unique = families.filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            Text(L10n.t("styleEditor.current.summary", ["colors": String(Self.colors.count), "fonts": unique.isEmpty ? "–" : unique.joined(separator: " · ")]))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .task(id: "\(FontDelivery.activeThemeId(config) ?? "")|\(families.joined(separator: "|"))") { await load() }
  }

  private func load() async {
    let path = model.project.path
    let theme = FontDelivery.activeThemeId(config)
    let wanted = Array(Set(families.filter { !$0.isEmpty }))
    let read = await Task.detached { (SiteFonts.faces(project: path, themeId: theme), SiteFonts.previewFonts(project: path, families: wanted)) }.value
    faces = read.0
    built = read.1.built
    PreviewFontRegistry.register(read.1.faces)
    fontsRound += 1
  }

  private func copy(_ value: String, _ label: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    copied = label
    Announce.post(L10n.t("common.copied", ["value": label]))
  }

  private var colorTable: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.t("styleEditor.current.colors")).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
        GridRow {
          Text(L10n.t("styleEditor.current.variable"))
          Text(L10n.t("styles.variables.light"))
          Text(L10n.t("styles.variables.dark"))
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(Self.colors, id: \.self) { key in
          GridRow {
            Text("--\(key)").font(.system(.caption, design: .monospaced))
            ForEach([VariableResolve.Mode.light, .dark], id: \.self) { mode in
              let value = VariableResolve.resolvedValue(key, mode, ctx)
              let hex = CssColor.hex(value) ?? value
              Button {
                if let hex { copy(hex, "--\(key) (\(mode == .light ? L10n.t("styles.variables.light") : L10n.t("styles.variables.dark")))") }
              } label: {
                HStack(spacing: 4) {
                  VariableSwatch(value: value, ground: VariableResolve.pageGround(mode, ctx), size: 12)
                  Text(hex ?? "—").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
              }
              .buttonStyle(.plain)
              .help(L10n.t("styleEditor.cssVars.copyHint", ["value": hex ?? "—"]))
            }
          }
        }
      }
      if let copied { Text(L10n.t("common.copied", ["value": copied])).font(.caption).foregroundStyle(.green) }
    }
  }

  @ViewBuilder private var fontList: some View {
    let loaders = FontDelivery.loaders(config)
    let typography = config.theme["typography"]?.objectValue ?? JSONObject()
    let requests = ["header", "body", "code"].compactMap { GoogleFontRequest.request($0, typography[$0]) }
    let googleFamilies = Set(requests.map { $0.family.lowercased() })
    let heldByProject = loaders.contains { $0.via == "core" && $0.mode == "selfHosted" }
    let selfHosted = loaders.contains { $0.via == "plugin" && $0.mode == "selfHosted" }
    let atPageView = loaders.contains { $0.via != "theme" && $0.mode == "google" }
    let _ = fontsRound
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.t("styleEditor.current.fonts")).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
      ForEach(Self.fonts, id: \.self) { key in
        if let stack = VariableResolve.resolvedValue(key, .light, ctx) {
          let family = FontDelivery.primaryFamily(stack)
          let summary = FontDelivery.summarizeFaces(faces, family: family)
          let available = PreviewFontRegistry.isAvailable(family)
          VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(key).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
              Button(family) { copy(stack, "--\(key)") }.buttonStyle(.link).font(.callout.weight(.semibold))
                .help(L10n.t("styleEditor.cssVars.copyHint", ["value": stack]))
              Text(summary.map { $0.weights.joined(separator: " · ") + ($0.italic ? " · \(L10n.t("styleEditor.current.italic"))" : "") }
                   ?? (googleFamilies.contains(family.lowercased()) && heldByProject ? L10n.t("styleEditor.current.faceOnSave")
                       : googleFamilies.contains(family.lowercased()) && selfHosted ? L10n.t("styleEditor.current.faceAtBuild")
                       : googleFamilies.contains(family.lowercased()) && atPageView ? L10n.t("styleEditor.current.faceFromGoogle")
                       : L10n.t("styleEditor.current.noFace")))
                .font(.caption).foregroundStyle(.secondary)
              if !available { Text(L10n.t("styleEditor.current.notInstalled")).font(.caption).foregroundStyle(.orange) }
            }
            Text(L10n.t("styleEditor.current.sample"))
              .font(PreviewFontRegistry.font(family, size: 18) ?? .system(size: 18))
              .foregroundStyle(available ? .primary : .secondary)
          }
        }
      }
      if families.contains(where: { !$0.isEmpty && !PreviewFontRegistry.isAvailable($0) }) {
        Callout(.warning, L10n.t("styleEditor.current.notInstalledExplainer"))
      }
      switch FontDelivery.buildState(config, faces: faces, built: built) {
      case .notBuilt?: Callout(.warning, L10n.t("styleEditor.current.fontsNotBuilt"))
      case .missing(let list)?: Callout(.warning, L10n.t("styleEditor.current.fontsMissingFromBuild", ["families": list.joined(separator: ", ")]))
      case .notFetched(let list)?: Callout(.warning, L10n.t("styleEditor.current.fontsNotFetched", ["families": list.joined(separator: ", ")]))
      case .noRule(let list)?: Callout(.warning, L10n.t("styleEditor.current.fontsNoRule", ["families": list.joined(separator: ", ")]))
      case nil: EmptyView()
      }
      let specs = requests.map { r in
        "\(r.family) \(r.singleWeightDropped ? L10n.t("styleEditor.current.familyDefault") : r.weights.map { String(format: "%g", $0) }.joined(separator: "/"))"
          + (r.italic ? " + \(L10n.t("styleEditor.current.italic"))" : "")
      }.joined(separator: " · ")
      if loaders.isEmpty { Note(L10n.t("styleEditor.current.noLoader")) }
      ForEach(loaders, id: \.self) { loader in
        Text(Self.loaderText(loader, specs: specs)).font(.caption)
          .foregroundStyle(loader.mode == "google" ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
      }
    }
  }

  static func loaderText(_ loader: FontDelivery.Loader, specs: String) -> String {
    switch (loader.via, loader.mode) {
    case ("core", "google"): L10n.t("styleEditor.current.loader.core.google", ["specs": specs])
    case ("core", _): L10n.t("styleEditor.current.loader.core.selfHosted", ["specs": specs])
    case ("plugin", "google"): L10n.t("styleEditor.current.loader.plugin.google")
    case ("plugin", _): L10n.t("styleEditor.current.loader.plugin.selfHosted")
    default: L10n.t("styleEditor.current.loader.theme.cdn")
    }
  }
}
