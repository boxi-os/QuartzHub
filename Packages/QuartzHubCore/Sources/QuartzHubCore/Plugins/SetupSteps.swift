import Foundation

/// One step of setting up a plugin's entry in the inspector (docs/plan-assistenten.md): a part
/// QuartzHub draws itself (the tiles, the placement, the summary), or a slice of the plugin's
/// options, picked by key or by the schema's group.
public struct SetupStep: Equatable, Sendable {
  public enum Part: String, Sendable {
    /// Only options from the plugin's schema.
    case options
    /// The tiles that decide what kind of entry it is (a navigation's variant, a box's content).
    case kind
    /// Position, order and display of the entry's layout block.
    case placement
    /// The last step: what is set, and the options no other step takes.
    case finish
  }

  /// Stable, for "where was I" (`@SceneStorage`) and the catalog key of its title.
  public let id: String
  public let part: Part
  /// Options of these groups (`x-quartz-group`, the plugin's English names) belong to the step,
  /// unless an earlier claim by key takes them.
  public let groups: [String]
  /// Options claimed by name, before any group.
  public let keys: [String]

  public init(id: String, part: Part = .options, groups: [String] = [], keys: [String] = []) {
    self.id = id
    self.part = part
    self.groups = groups
    self.keys = keys
  }
}

public enum SetupSteps {
  /// The step each option belongs to: a step that names the key, else the first whose groups
  /// hold its group, else the last step. Every key lands in exactly one step, so an option a new
  /// plugin version adds never disappears from the inspector.
  public static func assign(_ steps: [SetupStep], fields: [OptionField]) -> [String: String] {
    guard let last = steps.last else { return [:] }
    var out: [String: String] = [:]
    for field in fields {
      if let step = steps.first(where: { $0.keys.contains(field.key) }) {
        out[field.key] = step.id
      } else if let group = field.group, let step = steps.first(where: { $0.groups.contains(group) }) {
        out[field.key] = step.id
      } else {
        out[field.key] = last.id
      }
    }
    return out
  }

  /// The keys of one step, in the schema's order.
  public static func keys(_ step: SetupStep, in steps: [SetupStep], fields: [OptionField]) -> [String] {
    let assigned = assign(steps, fields: fields)
    return fields.map(\.key).filter { assigned[$0] == step.id }
  }

  /// Whether a step does anything with these options: a part of QuartzHub's always does, a slice
  /// of options as soon as one of them works: `noEffect` does not rule it out (the plugin's own
  /// rules, read from its code) and its `x-quartz-when` holds.
  public static func hasEffect(_ step: SetupStep, in steps: [SetupStep], options: JSONObject, fields: [OptionField],
                               noEffect: (String) -> Bool = { _ in false }) -> Bool {
    guard step.part == .options else { return true }
    return keys(step, in: steps, fields: fields).contains { key in
      guard !noEffect(key) else { return false }
      let field = fields.first { $0.key == key }
      return OptionSchema.evaluate(field?.when, values: .object(options), fields: fields)
    }
  }

  /// The keys only the fallback put into the last step: options QuartzHub has no step for yet.
  public static func unplaced(_ steps: [SetupStep], fields: [OptionField]) -> [String] {
    guard let last = steps.last else { return [] }
    return fields.filter { field in
      !steps.contains { $0.keys.contains(field.key) }
        && !(field.group.map { group in steps.contains { $0.groups.contains(group) } } ?? false)
        && !last.keys.contains(field.key)
    }.map(\.key)
  }
}

/// An entry ➕ just created, while the inspector sets it up for the first time.
public struct SetupRun: Equatable, Sendable {
  /// What names the new entry while the run lasts: a navigation's or a box's own class, a form's
  /// id, a language's code.
  public let key: String
  /// `plugins:` before ➕: cancelling puts back the priorities the run renumbered.
  public let before: [PluginEntry]
  /// The priorities the run's own steps wrote into other entries, by index. ➕ appends the new
  /// entry, so the others keep `before`'s indices.
  public private(set) var placed: [Int: Double] = [:]
  /// The steps seen, for their check marks. Here and not in the inspector: a form or a language
  /// renamed in its first run gets a new inspector (`.id`), and the marks went with the old one.
  public var visited: Set<String> = []

  public init(key: String, before: [PluginEntry]) {
    self.key = key
    self.before = before
  }

  /// The same run under the entry's new name.
  public func renamed(_ key: String) -> SetupRun {
    var next = SetupRun(key: key, before: before)
    next.placed = placed
    next.visited = visited
    return next
  }

  /// After a write of the run's own steps (`old` → `new`): the priorities it changed in entries
  /// other than its own (`own`, an index).
  public func recording(_ old: [PluginEntry], _ new: [PluginEntry], own: Int) -> SetupRun {
    guard old.count == new.count else { return self }
    var next = self
    for index in new.indices where index != own {
      let was = LayoutEntries.layout(old[index])?["priority"]?.numberValue
      if let now = LayoutEntries.layout(new[index])?["priority"]?.numberValue, now != was { next.placed[index] = now }
    }
    return next
  }

  /// Cancelling: `plugins`, already without the run's entry, with every priority the run wrote
  /// back as it was before ➕, unless something else changed it since. A move someone made
  /// meanwhile, and every other change, stays (review 2026-11-16, M2).
  public func restoringPriorities(_ plugins: [PluginEntry]) -> [PluginEntry] {
    var out = plugins
    for (index, wrote) in placed {
      guard out.indices.contains(index), before.indices.contains(index), out[index].name == before[index].name,
            var layout = LayoutEntries.layout(out[index]), layout["priority"]?.numberValue == wrote else { continue }
      layout["priority"] = LayoutEntries.layout(before[index])?["priority"]
      var object = out[index].object
      object["layout"] = .object(layout)
      out[index] = PluginEntry(object: object)
    }
    return out
  }

  /// Whether the run still has its entry before it: `keys` are what names each entry of its kind
  /// now, `selected` the one the inspector shows. An entry removed some other way (its row, the
  /// plugin list, the file) ends the run, so a later entry under the same name, a copy with the
  /// freed class, is not taken for the new one (review 2026-11-16, M1). Choosing another entry
  /// ends it too, as „Fertig“ would: what the steps wrote stays, and the entry, chosen again, takes
  /// a snapshot before its next change like any other (N1).
  public func lasts(keys: [String], selected: String?) -> Bool {
    selected == key && keys.contains(key)
  }
}

/// When an inspector in steps takes its one snapshot (docs/plan-assistenten.md): with the first
/// write after it opened, none in a first run (➕ took it), none once taken. "Taken" counts only
/// while no write failed since: a write that failed may have failed at the snapshot, or been
/// refused before it, so the next one takes it again (review 2026-11-16, M5).
public struct SnapshotOnce: Equatable, Sendable {
  /// The writer's count of failed writes when the snapshot was asked for.
  private var takenAt: Int?

  public init() {}

  /// Whether this write takes the snapshot; `failures` is the writer's count of failed writes.
  public mutating func take(firstRun: Bool = false, failures: Int) -> Bool {
    if firstRun || takenAt == failures { return false }
    takenAt = failures
    return true
  }

  /// „Fertig“: the run's snapshot was ➕'s; the next write takes none.
  public mutating func taken(failures: Int) {
    takenAt = failures
  }
}

extension NavigationVariants {
  /// A navigation's steps: the kind first, because it decides what the later steps can do; the
  /// place next, so the preview shows it from the second step on. The groups are the plugin's
  /// (`x-quartz-group` in its package.json).
  public static let steps: [SetupStep] = [
    SetupStep(id: "variant", part: .kind, keys: ["variant"]),
    SetupStep(id: "place", part: .placement),
    SetupStep(id: "pages", groups: ["Page selection"]),
    SetupStep(id: "hide", groups: ["Hide", "Order"]),
    SetupStep(id: "look", groups: ["Variant"], keys: variantKeys.sorted()),
    SetupStep(id: "mobile", groups: ["On smartphones"]),
    SetupStep(id: "labels", groups: ["Labels and icons"]),
    SetupStep(id: "finish", part: .finish, groups: ["Technical"])
  ]

  /// Whether a step does anything for this navigation: "Darstellung" of a tree does nothing, every
  /// option there belongs to other variants.
  public static func stepHasEffect(_ step: SetupStep, options: JSONObject, fields: [OptionField]) -> Bool {
    let variant = variant(options)
    let mobile = options["mobile"]
    return SetupSteps.hasEffect(step, in: steps, options: options, fields: fields) { hasNoEffect($0, variant, mobile: mobile) }
  }
}

extension LayoutBoxes {
  /// A box's steps: what its content is, the content, then its place, so the preview shows the box
  /// where it belongs from the third step on. The groups are the plugin's.
  public static let steps: [SetupStep] = [
    SetupStep(id: "kind", part: .kind),
    SetupStep(id: "content", groups: ["Content"], keys: contentKeys.sorted()),
    SetupStep(id: "place", part: .placement),
    SetupStep(id: "look", groups: ["Box"]),
    SetupStep(id: "languages", groups: ["Per language and page"]),
    SetupStep(id: "finish", part: .finish, groups: ["Technical"])
  ]

  public static func stepHasEffect(_ step: SetupStep, options: JSONObject, fields: [OptionField], installed: String?) -> Bool {
    let silenced = silenced(options, installed: installed)
    return SetupSteps.hasEffect(step, in: steps, options: options, fields: fields) { silenced($0) }
  }
}

extension FormsOptions {
  /// A form's steps: the parts its inspector had as folds, in their order, then a summary with the
  /// plugin's check and the keys QuartzHub does not know. The keys are the form's own (`formKeys`);
  /// the inspector draws every step itself, so they say only which step a key and the plugin's
  /// messages about it belong to.
  public static let steps: [SetupStep] = [
    SetupStep(id: "general", keys: ["template", "title", "description", "submitLabel", "success", "className"]),
    SetupStep(id: "fields", keys: ["fields"]),
    SetupStep(id: "sending", keys: ["recipient", "subject", "transport"]),
    SetupStep(id: "privacy", keys: ["encryption", "anonymous", "pageContext"]),
    SetupStep(id: "spam", keys: ["spam"]),
    SetupStep(id: "embed"),
    SetupStep(id: "finish", part: .finish)
  ]

  /// The step that shows a part's messages: the unknown keys stand in the summary.
  public static func step(of part: Part) -> String {
    part == .more ? "finish" : part.rawValue
  }
}

extension MultilanguageOptions {
  /// One language's steps, keyed by the fields of an item of `languages`: its code and names, its
  /// home page and flag, then default, published and order, which live in the plugin's options.
  public static let languageSteps: [SetupStep] = [
    SetupStep(id: "name", keys: ["code", "label", "native", "locale"]),
    SetupStep(id: "home", keys: ["home", "flag"]),
    SetupStep(id: "publish", keys: ["defaultLanguage", "publishLanguages"]),
    SetupStep(id: "finish", part: .finish)
  ]

  /// Setting up the site's languages, while it has fewer than two: the languages, which of them is
  /// the default and published, how a page finds its language, where the switcher stands. The
  /// groups after that (addresses, redirects, notices, links) are the summary's, each a row of the
  /// list as before.
  public static let siteSteps: [SetupStep] = [
    SetupStep(id: "languages", keys: ["languages"]),
    SetupStep(id: "publish", keys: ["defaultLanguage", "publishLanguages"]),
    SetupStep(id: "detection", groups: ["Detection and linking"]),
    SetupStep(id: "switcher", part: .placement, groups: ["Language switcher"]),
    SetupStep(id: "finish", part: .finish)
  ]
}
