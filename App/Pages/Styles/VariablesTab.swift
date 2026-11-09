import QuartzHubCore
import SwiftUI

/// Where the Variablen tab is, per window: the selected variable, what is open, the search.
/// Lists are kept as lines, `@SceneStorage` has no arrays.
struct VariablesPlace {
  var selected: Binding<String?>
  var openGroups: Binding<String>
  var allOpen: Binding<Bool>
  var query: Binding<String>
  var onlyChanged: Binding<Bool>
  var kind: Binding<String>
  var openBrowseGroups: Binding<String>
  var darkOpen: Binding<String>

  static func lines(_ text: String) -> [String] { text.split(separator: "\n").map(String.init) }

  static func toggled(_ text: String, _ item: String) -> String {
    var list = lines(text)
    if let index = list.firstIndex(of: item) { list.remove(at: index) } else { list.append(item) }
    return list.joined(separator: "\n")
  }

  static func adding(_ text: String, _ item: String) -> String {
    lines(text).contains(item) ? text : (lines(text) + [item]).joined(separator: "\n")
  }
}

/// Variablen (QuartzControl's `Styles/Variables.tsx`): the only place CSS custom properties are
/// edited. Two lists: the catalogue of variables Quartz derives from the classic colours, and
/// everything a theme, a plugin or the last build brings, browsed by name prefix or searched. The
/// selected variable is in the inspector.
struct VariablesTab: View {
  let model: StylesModel
  let notes: AnyView
  let place: VariablesPlace
  /// Set by a jump from the inspector; the row is scrolled to and the request cleared.
  @Binding var scrollTarget: String?
  /// Asked on arrival, after a save and after the move: what custom.scss sets itself and wins with.
  @State private var collisions: [String] = []
  @State private var colorKeys: Set<String> = []

  static let maxResults = 150
  static let singlesGroup = "singles"

  private var ctx: VariableResolve.Context { model.context }
  private var moved: Bool { model.scss?.info.moved ?? false }

  private var curatedGroups: [(group: String, keys: [String])] {
    var out: [(group: String, keys: [String])] = []
    for def in CssVariables.all {
      if let index = out.firstIndex(where: { $0.group == def.group }) { out[index].keys.append(def.key) } else { out.append((def.group, [def.key])) }
    }
    return out
  }

  private var extraKeys: [String] {
    let curated = Set(CssVariables.all.map(\.key))
    return VariableResolve.allKnownKeys(ctx).filter { !curated.contains($0) }.sorted()
  }

  var body: some View {
    ScrollViewReader { proxy in
      Form {
        notes
        if let themeId = model.config.flatMap(FontDelivery.activeThemeId) {
          Section { Label(L10n.t("styles.variables.themeNote", ["themeId": themeId]), systemImage: "info.circle").foregroundStyle(.secondary) }
        }
        if !collisions.isEmpty {
          Section {
            Label(L10n.t("styles.variables.collisionNote", ["names": collisions.map { "--\($0)" }.joined(separator: ", ")], count: collisions.count),
                  systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
          }
        }
        mainSection
        allSection
      }
      .formStyle(.grouped)
      .onChange(of: scrollTarget) { _, target in
        guard let target else { return }
        Task { @MainActor in
          // After the group the jump opened has laid out its rows.
          try? await Task.sleep(for: .milliseconds(350))
          // In a list-backed Form the id is the ForEach's, the key itself, not an .id modifier.
          withAnimation(nil) { proxy.scrollTo(target, anchor: .center) }
          scrollTarget = nil
        }
      }
    }
    .task(id: "\(moved)|\(model.status == .saved)") { await loadCollisions() }
    .task(id: colorSignature) { colorKeys = computeColorKeys() }
  }

  // MARK: Reading

  private func loadCollisions() async {
    guard moved else { collisions = []; return }
    let path = model.project.path
    collisions = (try? await Task.detached { try StyleSheets.variableCollisions(project: path) }.value) ?? []
  }

  /// Asked once per key and graph, not per keystroke, and of the value without the override (only
  /// the user's own keys, which have nothing else, count theirs): a row must not leave the colour
  /// filter while someone types into it.
  private var colorSignature: String {
    let curated = Set(CssVariables.all.map(\.key))
    let own = model.overrides.filter { ctx.vars?[$0.key] == nil && !curated.contains($0.key) }
    return "\(model.graph?.vars.count ?? -1)|\(extraKeys.count)|" + own.map { "\($0.key)=\($0.value.light)/\($0.value.dark)" }.joined(separator: ";")
  }

  private func computeColorKeys() -> Set<String> {
    let curated = Set(CssVariables.all.map(\.key))
    let own = model.overrides.filter { ctx.vars?[$0.key] == nil && !curated.contains($0.key) }
    let base = VariableResolve.Context(vars: ctx.vars, overrides: own, colors: ctx.colors, typography: ctx.typography)
    return Set(extraKeys.filter { VariableResolve.isColorVariable($0, base, shown: false) })
  }

  // MARK: The catalogue

  private var mainSection: some View {
    Section {
      Note(L10n.t("styles.variables.mainDescription"))
      ForEach(curatedGroups, id: \.group) { entry in
        let open = VariablesPlace.lines(place.openGroups.wrappedValue).contains(entry.group)
        DisclosureGroup(isExpanded: Binding(get: { open }, set: { _ in place.openGroups.wrappedValue = VariablesPlace.toggled(place.openGroups.wrappedValue, entry.group) })) {
          ForEach(entry.keys, id: \.self) { key in row(key) }
        } label: {
          groupHeader(Self.groupLabel(entry.group), count: entry.keys.count, changed: entry.keys.filter { model.overrides.map(\.key).contains($0) }.count)
        }
      }
    } header: {
      Text(L10n.t("styles.variables.mainHeading"))
    }
  }

  private func groupHeader(_ label: String, count: Int, changed: Int) -> some View {
    HStack(spacing: 8) {
      Text(label).fontWeight(.semibold)
      Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
      if changed > 0 { StateBadge(text: L10n.t("styles.variables.groupChanged", count: changed), color: .green).font(.caption) }
    }
  }

  /// One literal key per catalogue group, so `qh-check i18n` sees each; a name prefix is its own text.
  static func groupLabel(_ group: String) -> String {
    switch group {
    case "accentHsl": L10n.t("styles.variables.groups.accentHsl")
    case "baseColors": L10n.t("styles.variables.groups.baseColors")
    case "baseScale": L10n.t("styles.variables.groups.baseScale")
    case "fonts": L10n.t("styles.variables.groups.fonts")
    case "interaction": L10n.t("styles.variables.groups.interaction")
    case "navigation": L10n.t("styles.variables.groups.navigation")
    case "other": L10n.t("styles.variables.groups.other")
    case "surfaces": L10n.t("styles.variables.groups.surfaces")
    case "tags": L10n.t("styles.variables.groups.tags")
    case "text": L10n.t("styles.variables.groups.text")
    case singlesGroup: L10n.t("styles.variables.singlesGroup")
    default: group
    }
  }

  // MARK: Everything else

  private var allSection: some View {
    let keys = extraKeys
    let overridden = Set(model.overrides.map(\.key))
    let sources = model.graph?.sources
    return Section {
      DisclosureGroup(isExpanded: place.allOpen) {
        let themeId = model.graph?.themeId
        Note(themeId.map { L10n.t("styles.variables.allDescriptionTheme", ["themeId": $0], count: keys.count) } ?? L10n.t("styles.variables.allDescription"))
        if model.graphLoading {
          Note(L10n.t("common.loading"))
        } else if keys.isEmpty {
          Note(L10n.t("styles.variables.noSources"))
          if sources?.theme == false { Note(L10n.t("styles.variables.noTheme")) }
          if sources?.build == false { Note(L10n.t("styles.variables.noBuild")) }
          Button(L10n.t("styles.variables.reload")) { Task { await model.reloadGraph() } }
        } else {
          if sources?.build == false { Note(L10n.t("styles.variables.noBuild")) }
          filters(keys)
          results(keys, overridden: overridden)
        }
      } label: {
        HStack {
          Text(L10n.t("styles.variables.allHeading")).fontWeight(.semibold)
          Spacer()
          // Without a build the list holds only the theme's names and the page's own, and a total
          // would read as "all of them changed".
          Text(sources?.build == false
               ? L10n.t("styles.variables.counterNoBuild", ["overridden": String(keys.filter(overridden.contains).count)])
               : L10n.t("styles.variables.counter", ["overridden": String(keys.filter(overridden.contains).count), "total": String(keys.count)]))
            .font(.callout).foregroundStyle(.secondary)
        }
      }
      .accessibilityIdentifier("variables.all")
    }
  }

  private func filters(_ keys: [String]) -> some View {
    HStack {
      TextField(L10n.t("styles.variables.searchPlaceholder"), text: place.query, prompt: Text(L10n.t("styles.variables.searchPlaceholder")))
        .labelsHidden().textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("variables.search")
      Toggle(L10n.t("styles.variables.onlyChanged"), isOn: place.onlyChanged).toggleStyle(.checkbox)
      Picker(L10n.t("styles.variables.kind.label"), selection: place.kind) {
        Text(L10n.t("styles.variables.kind.all")).tag("all")
        Text(L10n.t("styles.variables.kind.color", count: colorKeys.count)).tag("color")
        Text(L10n.t("styles.variables.kind.other", count: keys.count - colorKeys.count)).tag("other")
      }
      .labelsHidden().fixedSize()
      Button(L10n.t("styles.variables.reload")) { Task { await model.reloadGraph() } }
    }
  }

  /// Without a query the list is browsed by prefix group, all collapsed; with one it is a capped
  /// search. A prefix only one variable carries goes to "Einzelne Variablen" while browsing.
  @ViewBuilder private func results(_ keys: [String], overridden: Set<String>) -> some View {
    let q = VariableResolve.normalizeQuery(place.query.wrappedValue)
    let kind = place.kind.wrappedValue
    let ofKind = kind == "all" ? keys : keys.filter { colorKeys.contains($0) == (kind == "color") }
    let onlyChanged = place.onlyChanged.wrappedValue
    let browsing = q.isEmpty && !onlyChanged
    let matches = !q.isEmpty ? ofKind.filter { $0.lowercased().contains(q) && (!onlyChanged || overridden.contains($0)) }
      : ofKind.filter { overridden.contains($0) || browsing }
    let visible = browsing ? matches : Array(matches.prefix(Self.maxResults))
    let grouped = Self.grouped(visible, browsing: browsing)
    if matches.isEmpty { Note(L10n.t("styles.variables.noResults")) }
    if browsing {
      ForEach(grouped, id: \.group) { entry in
        let open = VariablesPlace.lines(place.openBrowseGroups.wrappedValue).contains(entry.group)
        DisclosureGroup(isExpanded: Binding(get: { open }, set: { _ in place.openBrowseGroups.wrappedValue = VariablesPlace.toggled(place.openBrowseGroups.wrappedValue, entry.group) })) {
          ForEach(entry.keys, id: \.self) { key in row(key) }
        } label: {
          groupHeader(Self.groupLabel(entry.group), count: entry.keys.count, changed: 0)
        }
      }
    } else {
      ForEach(grouped, id: \.group) { entry in
        Text(Self.groupLabel(entry.group)).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
        ForEach(entry.keys, id: \.self) { key in row(key) }
      }
    }
    if matches.count > visible.count { Note(L10n.t("styles.variables.moreResults", count: matches.count - visible.count)) }
  }

  static func grouped(_ keys: [String], browsing: Bool) -> [(group: String, keys: [String])] {
    var out: [(group: String, keys: [String])] = []
    for key in keys {
      let group = VariableResolve.groupOf(key)
      if let index = out.firstIndex(where: { $0.group == group }) { out[index].keys.append(key) } else { out.append((group, [key])) }
    }
    guard browsing else { return out }
    let singles = out.filter { $0.keys.count == 1 }.flatMap(\.keys)
    out.removeAll { $0.keys.count == 1 }
    if !singles.isEmpty { out.append((singlesGroup, singles)) }
    return out
  }

  // MARK: A row

  private func row(_ key: String) -> some View {
    VariableRowView(key: key, model: model, selected: place.selected.wrappedValue == key) {
      place.selected.wrappedValue = place.selected.wrappedValue == key ? nil : key
    }
    .id("var-\(key)")
  }
}

/// One variable in a list: its swatches, name, value, dependents, origin, and resetting it.
struct VariableRowView: View {
  let key: String
  let model: StylesModel
  let selected: Bool
  let select: () -> Void
  @Environment(\.unsavedGuard) private var unsaved

  var body: some View {
    let ctx = model.context
    let origin = VariableResolve.originOf(key, ctx)
    let light = VariableResolve.effectiveValue(key, .light, ctx)
    let showsColor = VariableResolve.isColorVariable(key, ctx)
    let dependents = model.graph?.dependents[key]?.arrayValue?.count ?? 0
    let overridden = ctx.overrides[key] != nil
    HStack(spacing: 8) {
      Button(action: select) {
        HStack(spacing: 8) {
          HStack(spacing: 2) {
            VariableSwatch(value: showsColor ? VariableResolve.resolvedValue(key, .light, ctx) : nil, ground: VariableResolve.pageGround(.light, ctx))
            VariableSwatch(value: showsColor ? VariableResolve.resolvedValue(key, .dark, ctx) : nil, ground: VariableResolve.pageGround(.dark, ctx))
          }
          .opacity(showsColor ? 1 : 0)
          Text("--\(key)").font(.system(.body, design: .monospaced))
          Text(light ?? "—").foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if dependents > 0 { Text(L10n.t("styles.variables.dependents", count: dependents)).font(.caption).foregroundStyle(.secondary) }
      if let badge = VariableInspector.originBadge(origin) { StateBadge(text: badge, color: origin == "theme" ? .gray : .green).font(.caption) }
      if overridden && origin != "own" {
        Button {
          model.setOverride(key, nil)
        } label: {
          Label(L10n.t("styles.variables.resetNamed", ["name": "--\(key)"]), systemImage: "arrow.uturn.backward")
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
      }
      if origin == "own" {
        Button(role: .destructive) {
          Task { await VariableInspector.removeOwn(key, model: model, window: unsaved?.window) }
        } label: {
          Label(L10n.t("common.removeNamed", ["name": "--\(key)"]), systemImage: "trash")
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
      }
    }
    .padding(.vertical, 2)
    .padding(.horizontal, 4)
    // On the row itself: listRowBackground does not reach rows inside a DisclosureGroup (seen).
    .background(selected ? Color.accentColor.opacity(0.22) : (overridden ? Color.green.opacity(0.08) : Color.clear), in: RoundedRectangle(cornerRadius: 5))
    .accessibilityIdentifier("variables.row.\(key)")
  }
}

/// A colour over the website's ground, so a translucent value shows what the site paints.
struct VariableSwatch: View {
  let value: String?
  let ground: String
  var size: CGFloat = 12

  var body: some View {
    let color = value.flatMap { CssColor.isDisplayable($0) ? CssColorField.color($0) : nil }
    ZStack {
      if color != nil { CssColorField.color(ground) }
      color ?? .clear
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 2))
    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.separator))
    .help(color == nil ? L10n.t("styles.variables.swatchNone") : L10n.t("styles.variables.swatchOver", ["value": value ?? "", "ground": ground]))
  }
}

/// The selected variable: what it is in both modes, where that comes from, what it uses and what
/// uses it, and the fields to change it.
struct VariableInspector: View {
  let key: String
  let model: StylesModel
  let darkOpen: Bool
  let setDarkOpen: (Bool) -> Void
  let navigate: (String) -> Void
  @Environment(\.unsavedGuard) private var unsaved

  static func originBadge(_ origin: String) -> String? {
    switch origin {
    case "user": L10n.t("styles.variables.origin.user")
    case "own": L10n.t("styles.variables.origin.own")
    case "theme": L10n.t("styles.variables.origin.theme")
    default: nil
    }
  }

  static func originText(_ origin: String, file: String?) -> String {
    switch origin {
    case "core": L10n.t("styles.variables.origin.core")
    case "theme": L10n.t("styles.variables.origin.theme")
    case "project": L10n.t("styles.variables.origin.project", ["file": file ?? ""])
    case "user": L10n.t("styles.variables.origin.user")
    case "own": L10n.t("styles.variables.origin.own")
    default: L10n.t("styles.variables.origin.build")
    }
  }

  /// Taking an own variable away is deleting it, asked like any entry taken out of a list.
  static func removeOwn(_ key: String, model: StylesModel, window: NSWindow?) async {
    let name = "--\(key)"
    let (question, detail) = Confirm.split(L10n.t("styles.variables.confirmRemoveOwn", ["name": name]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("styles.variables.confirmRemoveOwnAction"), destructive: true, window: window) else { return }
    model.setOverride(key, nil)
  }

  var body: some View {
    let ctx = model.context
    let moved = model.scss?.info.moved ?? false
    let edit = VariableEditing(key: key, context: ctx, moved: moved)
    let origin = VariableResolve.originOf(key, ctx)
    let light = VariableResolve.effectiveValue(key, .light, ctx)
    let dark = VariableResolve.effectiveValue(key, .dark, ctx)
    let lightResolved = VariableResolve.resolvedValue(key, .light, ctx)
    let darkResolved = VariableResolve.resolvedValue(key, .dark, ctx)
    let isColor = VariableResolve.isColorVariable(key, ctx, shown: false)
    let split = edit.splitModes(context: ctx, darkOpen: darkOpen)
    let uses = Array(NSOrderedSet(array: VariableResolve.referencedVariables(light ?? "") + VariableResolve.referencedVariables(dark ?? ""))) as? [String] ?? []
    let dependents = (model.graph?.dependents[key]?.arrayValue ?? []).compactMap(\.stringValue)
    let file = model.graph?.vars[key]?["source"]?.stringValue
    Form {
      Section {
        HStack {
          if VariableResolve.isColorVariable(key, ctx) {
            VariableSwatch(value: lightResolved, ground: VariableResolve.pageGround(.light, ctx), size: 14)
            VariableSwatch(value: darkResolved, ground: VariableResolve.pageGround(.dark, ctx), size: 14)
          }
          Text("--\(key)").font(.system(.title3, design: .monospaced)).textSelection(.enabled)
        }
        if let badge = Self.originBadge(origin) { StateBadge(text: badge, color: origin == "theme" ? .gray : .green) }
      }
      Section(L10n.t("styles.variables.section.current")) {
        let modes: [VariableResolve.Mode] = (isColor || lightResolved != darkResolved) ? [.light, .dark] : [.light]
        ForEach(modes, id: \.self) { mode in
          let resolved = VariableResolve.resolvedValue(key, mode, ctx)
          LabeledContent(modes.count == 2 ? (mode == .light ? L10n.t("styles.variables.light") : L10n.t("styles.variables.dark")) : L10n.t("styles.variables.bothModes")) {
            HStack(spacing: 6) {
              if CssColor.isDisplayable(resolved) { VariableSwatch(value: resolved, ground: VariableResolve.pageGround(mode, ctx), size: 14) }
              Text(resolved ?? (VariableResolve.effectiveValue(key, mode, ctx) == nil ? L10n.t("styles.variables.unresolved") : L10n.t("styles.variables.unresolvedReference")))
                .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
              if let hex = CssColor.hex(resolved), hex.lowercased() != (resolved ?? "").lowercased() {
                Text(hex).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      Section(L10n.t("styles.variables.section.origin")) {
        Note(origin == "own" ? L10n.t("styles.variables.ownHint")
             : origin == "user" ? L10n.t("styles.variables.changedOver", ["base": Self.originText(VariableResolve.baseOriginOf(key, ctx), file: file)])
             : Self.originText(origin, file: file))
        chain(.light, ctx: ctx, label: L10n.t("styles.variables.light"))
        if dark != light || darkResolved != lightResolved { chain(.dark, ctx: ctx, label: L10n.t("styles.variables.dark")) }
      }
      Section(L10n.t("styles.variables.section.uses")) {
        if uses.isEmpty { Note(L10n.t("styles.variables.usesNone")) } else { chips(uses) }
      }
      Section(L10n.t("styles.variables.section.dependents")) {
        if dependents.isEmpty {
          Note(L10n.t("styles.variables.dependentsNone"))
        } else {
          Note(L10n.t("styles.variables.dependentsWarning", count: dependents.count))
          chips(dependents)
        }
      }
      Section(L10n.t("styles.variables.section.edit")) {
        valueField(edit, .light, label: split ? L10n.t("styles.variables.light") : L10n.t("styles.variables.bothModes"), value: edit.draft.light, ctx: ctx)
        if split { valueField(edit, .dark, label: L10n.t("styles.variables.dark"), value: edit.draft.dark, ctx: ctx) }
        if !split {
          Button(L10n.t("styles.variables.splitDark")) { setDarkOpen(true) }.buttonStyle(.link)
        } else if !isColor && !edit.baseDiffers {
          Button(L10n.t("styles.variables.unsplitDark")) {
            model.setOverride(key, edit.followingLight())
            setDarkOpen(false)
          }
          .buttonStyle(.link)
        }
        if edit.override != nil && !edit.isOwn {
          Button(L10n.t("styles.variables.resetToOriginal")) { model.setOverride(key, nil) }
            .accessibilityIdentifier("variables.reset")
        }
        if edit.isOwn {
          Button(L10n.t("styles.variables.removeOwn"), role: .destructive) { Task { await Self.removeOwn(key, model: model, window: unsaved?.window) } }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func chain(_ mode: VariableResolve.Mode, ctx: VariableResolve.Context, label: String) -> some View {
    let steps = VariableResolve.resolveChain(key, mode, ctx)
    let text = steps.isEmpty ? L10n.t("styles.variables.unresolved")
      : steps.map { "--\($0.key)" }.joined(separator: " → ") + " → " + (steps.last?.value ?? "")
    return LabeledContent(label) {
      Text(text).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
    }
  }

  /// At most 24, as there: the rest is a count.
  private func chips(_ keys: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(keys.prefix(24), id: \.self) { name in
        Button("--\(name)") { navigate(name) }
          .buttonStyle(.link)
          .font(.system(.callout, design: .monospaced))
          .help(L10n.t("styles.variables.chipHint"))
      }
      if keys.count > 24 { Note(L10n.t("styles.variables.moreKeys", count: keys.count - 24)) }
    }
  }

  /// The well is fed the resolved literal, not the draft: `var(--secondary)` is a colour the well
  /// cannot read, and picking writes a literal, a deliberate replacement.
  private func valueField(_ edit: VariableEditing, _ mode: VariableEditing.Mode, label: String, value: String, ctx: VariableResolve.Context) -> some View {
    let resolveMode: VariableResolve.Mode = mode == .light ? .light : .dark
    let resolved = VariableResolve.resolveValueLiteral(value, resolveMode, ctx)
    let isColor = CssVariables.definition(key)?.kind == "color" || CssColor.hexAlpha(resolved) != nil
    return LabeledContent(label) {
      HStack(spacing: 6) {
        if isColor {
          ColorPicker(selection: Binding(get: { CssColorField.color(resolved ?? value) }, set: { model.setOverride(key, edit.setting(mode, CssColorField.css($0))) }),
                      supportsOpacity: true) { Text(label) }
            .labelsHidden()
        }
        TextField(label, text: Binding(get: { value }, set: { model.setOverride(key, edit.setting(mode, $0)) }))
          .labelsHidden().textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
          .accessibilityIdentifier("variables.value.\(mode == .light ? "light" : "dark")")
      }
    }
  }
}
