import QuartzHubCore

/// The sentences of the Vorlagen page, from QuartzControl's `Templates.tsx` (`statsSummary`,
/// `planSummary`, `planNotes`) with the keys spelled out, so `qh-check i18n` can see them.
@MainActor
enum TemplateWords {
  static func label(_ id: String) -> String {
    switch id {
    case "content": L10n.t("templates.parts.content.label")
    case "appearance": L10n.t("templates.parts.appearance.label")
    case "theme": L10n.t("templates.parts.theme.label")
    case "cssVariables": L10n.t("templates.parts.cssVariables.label")
    case "styles": L10n.t("templates.parts.styles.label")
    case "fonts": L10n.t("templates.parts.fonts.label")
    case "static": L10n.t("templates.parts.static.label")
    case "layout": L10n.t("templates.parts.layout.label")
    case "frames": L10n.t("templates.parts.frames.label")
    case "plugins": L10n.t("templates.parts.plugins.label")
    case "translations": L10n.t("templates.parts.translations.label")
    case "presets": L10n.t("templates.parts.presets.label")
    default: id
    }
  }

  static func description(_ id: String) -> String {
    switch id {
    case "content": L10n.t("templates.parts.content.description")
    case "appearance": L10n.t("templates.parts.appearance.description")
    case "theme": L10n.t("templates.parts.theme.description")
    case "cssVariables": L10n.t("templates.parts.cssVariables.description")
    case "styles": L10n.t("templates.parts.styles.description")
    case "fonts": L10n.t("templates.parts.fonts.description")
    case "static": L10n.t("templates.parts.static.description")
    case "layout": L10n.t("templates.parts.layout.description")
    case "frames": L10n.t("templates.parts.frames.description")
    case "plugins": L10n.t("templates.parts.plugins.description")
    case "translations": L10n.t("templates.parts.translations.description")
    case "presets": L10n.t("templates.parts.presets.description")
    default: ""
    }
  }

  /// One count of a part's stats. QuartzControl asked `templates.stats.<id>.<key>` first; the
  /// catalog has none of those, so the shared key is the one.
  static func stat(_ key: String, _ count: Int) -> String {
    switch key {
    case "active": L10n.t("templates.stats.active", count: count)
    case "colors": L10n.t("templates.stats.colors", count: count)
    case "entries": L10n.t("templates.stats.entries", count: count)
    case "files": L10n.t("templates.stats.files", count: count)
    case "fonts": L10n.t("templates.stats.fonts", count: count)
    case "frames": L10n.t("templates.stats.frames", count: count)
    case "groups": L10n.t("templates.stats.groups", count: count)
    case "kilobytes": L10n.t("templates.stats.kilobytes", count: count)
    case "languages": L10n.t("templates.stats.languages", count: count)
    case "pageTypes": L10n.t("templates.stats.pageTypes", count: count)
    case "plugins": L10n.t("templates.stats.plugins", count: count)
    case "presets": L10n.t("templates.stats.presets", count: count)
    case "styleSettings": L10n.t("templates.stats.styleSettings", count: count)
    case "variables": L10n.t("templates.stats.variables", count: count)
    default: "\(count) \(key)"
    }
  }

  /// `statsSummary`: the counts above zero, without the "all" ones and `undetermined`.
  static func stats(_ stats: JSONObject) -> String {
    stats.keys.compactMap { key -> String? in
      let value = Int(stats[key]?.numberValue ?? 0)
      guard value > 0, !key.hasPrefix("all"), key != "undetermined" else { return nil }
      return stat(key, value)
    }.joined(separator: ", ")
  }

  /// The export row's line: for translations it follows the scope.
  static func exportSummary(_ part: TemplatePackage.Summary, scope: TemplatePackage.TranslationScope) -> String {
    guard part.id == "translations" else { return stats(part.stats) }
    if scope == .all {
      return stats(JSONObject([("languages", part.stats["allLanguages"] ?? .number(0)), ("entries", part.stats["allEntries"] ?? .number(0))]))
    }
    let text = stats(part.stats)
    return text.isEmpty ? L10n.t("templates.scopeNoChanges") : text
  }

  static func quoted(_ name: String) -> String { L10n.t("templates.quotedName", ["value": name]) }
  static func quoted(_ names: [String]) -> String { names.map(quoted).joined(separator: ", ") }

  static func noteCount(_ plan: TemplatePackage.PartPlan, _ kind: String) -> Int {
    plan.notes.filter { $0 == kind || $0.hasPrefix("\(kind):") }.count
  }

  /// `planSummary`: added, replaced or kept, identical, refused, unreadable frames.
  static func planSummary(_ plan: TemplatePackage.PartPlan, strategy: TemplatePackage.Strategy) -> String {
    var bits: [String] = []
    if !plan.additions.isEmpty { bits.append(L10n.t("templates.planAdditions", count: plan.additions.count)) }
    // Under "Projekt gewinnt" a custom.scss that gains the package's lines is not kept, nor a
    // quartz-forms entry that gains forms; the notes say what happens to them instead.
    let merged = strategy == .projectWins
      ? (plan.notes.contains("customScssMerged") ? 1 : 0) + (plan.notes.contains { $0.hasPrefix("formsMerged:") && $0.count > "formsMerged:".count } ? 1 : 0)
      : 0
    if plan.conflicts.count - merged > 0 {
      bits.append(strategy == .packageWins ? L10n.t("templates.planReplaced", count: plan.conflicts.count - merged)
        : L10n.t("templates.planKept", count: plan.conflicts.count - merged))
    }
    let identical = noteCount(plan, "identical")
    if identical > 0 { bits.append(L10n.t("templates.planIdentical", count: identical)) }
    let outside = noteCount(plan, "outside")
    if outside > 0 { bits.append(L10n.t("templates.planOutside", count: outside)) }
    let invalid = noteCount(plan, "invalidFrame")
    if invalid > 0 { bits.append(L10n.t("templates.planInvalidFrames", count: invalid)) }
    if bits.isEmpty { bits.append(L10n.t("templates.planNoChange")) }
    return bits.joined(separator: ", ")
  }

  static let namesShown = 3

  /// `planNotes`: the sentences a part's plan wants said before the click.
  static func planNotes(_ plan: TemplatePackage.PartPlan, strategy: TemplatePackage.Strategy, pluginsSelected: Bool) -> [String] {
    var notes: [String] = []
    func listed(_ kind: String) -> [String] {
      plan.notes.filter { $0.hasPrefix("\(kind):") }.flatMap { $0.dropFirst(kind.count + 1).split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }
    func after(_ prefix: String) -> String? {
      plan.notes.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
    if plan.notes.contains("contentIsSymlink") { notes.append(L10n.t("templates.planContentIsSymlink")) }
    let icons = noteCount(plan, "projectIcon")
    if icons > 0 { notes.append(L10n.t("templates.planProjectIconKept", count: icons)) }
    // A picture that is neither Quartz's nor recorded as chosen here.
    let unrecorded = plan.notes.filter { $0.hasPrefix("unrecordedIcon:") }.map { String($0.dropFirst("unrecordedIcon:".count)) }
    if !unrecorded.isEmpty {
      let names = unrecorded.map(quoted).joined(separator: L10n.t("templates.namesAnd"))
      notes.append(strategy == .packageWins ? L10n.t("templates.planUnrecordedIconReplaced", ["names": names], count: unrecorded.count)
        : L10n.t("templates.planUnrecordedIconKept", ["names": names], count: unrecorded.count))
    }
    if let legacy = after("legacyStyles:") {
      let count = Int(legacy) ?? 0
      notes.append(strategy == .packageWins ? L10n.t("templates.planLegacyStylesReplaced", ["count": legacy], count: count)
        : L10n.t("templates.planLegacyStylesKept", ["count": legacy], count: count))
    }
    if let newer = after("newerStyles:") {
      let count = Int(newer) ?? 0
      notes.append(strategy == .packageWins ? L10n.t("templates.planNewerStylesReplaced", ["count": newer], count: count)
        : L10n.t("templates.planNewerStylesKept", ["count": newer], count: count))
    }
    if strategy == .projectWins, plan.notes.contains("customScssMerged") { notes.append(L10n.t("templates.planCustomScssMerged")) }
    // What replacing does besides the options and files it counts, only where it happens.
    if strategy == .packageWins {
      let on = listed("pluginOn"), off = listed("pluginOff")
      if !on.isEmpty { notes.append(L10n.t("templates.planPluginsOn", ["names": quoted(on)], count: on.count)) }
      if !off.isEmpty { notes.append(L10n.t("templates.planPluginsOff", ["names": quoted(off)], count: off.count)) }
      let byPosition = listed("byPosition")
      if !byPosition.isEmpty { notes.append(L10n.t("templates.planByPosition", ["names": quoted(byPosition)], count: byPosition.count)) }
      let fonts = listed("fontsRemoved")
      if !fonts.isEmpty { notes.append(L10n.t("templates.planFontsRemoved", ["names": quoted(fonts)], count: fonts.count)) }
    }
    // quartz-forms is merged, the same under both strategies.
    if let formsMerged = after("formsMerged:") {
      let added = formsMerged.split(separator: ",").map(String.init)
      notes.append(added.isEmpty ? L10n.t("templates.planFormsKept")
        : L10n.t("templates.planFormsMerged", ["names": quoted(added)], count: added.count))
      if let pinned = after("formsPinned:"), !pinned.isEmpty {
        notes.append(L10n.t("templates.planFormsPinned", ["kind": FormsView.kindLabel(pinned)], count: added.count))
      }
      let own = listed("formsOwn")
      if !own.isEmpty { notes.append(L10n.t("templates.planFormsOwn", ["names": quoted(own)], count: own.count)) }
    }
    // The content part's pages embed forms the plugins part adds.
    let formsMissing = listed("formsMissing")
    if !formsMissing.isEmpty, !pluginsSelected {
      notes.append(L10n.t("templates.planFormsMissing", ["names": quoted(formsMissing)], count: formsMissing.count))
    }
    if let missing = after("missingVariables:") {
      let names = missing.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      let shown = names.prefix(namesShown).joined(separator: ", ")
      let text = names.count > namesShown ? L10n.t("templates.planOutsideMore", ["names": shown], count: names.count - namesShown) : shown
      notes.append(L10n.t("templates.planMissingVariables", ["names": text], count: names.count))
    }
    let outside = plan.notes.filter { $0.hasPrefix("outside:") }.map { String($0.dropFirst("outside:".count)) }
    if !outside.isEmpty {
      // Quoted one by one: the marks belong around a name, not around "… und 2 weitere".
      let shown = outside.prefix(namesShown).map(quoted).joined(separator: ", ")
      let names = outside.count > namesShown ? L10n.t("templates.planOutsideMore", ["names": shown], count: outside.count - namesShown) : shown
      notes.append(L10n.t("templates.planOutsideDetail", ["names": names], count: outside.count))
    }
    // One line per frame: each is a finished "name — why" sentence from the plan.
    let invalid = plan.notes.filter { $0.hasPrefix("invalidFrame:") }.map { String($0.dropFirst("invalidFrame:".count)) }
    for detail in invalid.prefix(namesShown) { notes.append(L10n.t("templates.planInvalidFrameDetail", ["detail": detail])) }
    if invalid.count > namesShown { notes.append(L10n.t("templates.planInvalidFramesMore", count: invalid.count - namesShown)) }
    return notes
  }
}
