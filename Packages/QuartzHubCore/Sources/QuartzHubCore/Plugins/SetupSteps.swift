import Foundation

/// One step of setting up a plugin's entry in the inspector (docs/plan-assistenten.md): a part
/// QuartzHub draws itself (the tiles, the placement, the summary), or a slice of the plugin's
/// options, picked by key or by the schema's group.
public struct SetupStep: Equatable, Sendable {
  public enum Part: String, Sendable {
    /// Only options from the plugin's schema.
    case options
    /// quartz-navigations' tiles.
    case variant
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

extension NavigationVariants {
  /// A navigation's steps: the kind first, because it decides what the later steps can do; the
  /// place next, so the preview shows it from the second step on. The groups are the plugin's
  /// (`x-quartz-group` in its package.json).
  public static let steps: [SetupStep] = [
    SetupStep(id: "variant", part: .variant, keys: ["variant"]),
    SetupStep(id: "place", part: .placement),
    SetupStep(id: "pages", groups: ["Page selection"]),
    SetupStep(id: "hide", groups: ["Hide", "Order"]),
    SetupStep(id: "look", groups: ["Variant"], keys: variantKeys.sorted()),
    SetupStep(id: "mobile", groups: ["On smartphones"]),
    SetupStep(id: "labels", groups: ["Labels and icons"]),
    SetupStep(id: "finish", part: .finish, groups: ["Technical"])
  ]

  /// Whether a step does anything with these options: a part of QuartzHub's always does, a slice
  /// of options as soon as one of them works for the variant and its `x-quartz-when` holds.
  /// "Darstellung" of a tree does nothing: every option there belongs to other variants.
  public static func stepHasEffect(_ step: SetupStep, options: JSONObject, fields: [OptionField]) -> Bool {
    guard step.part == .options else { return true }
    let variant = variant(options)
    let mobile = options["mobile"]
    let keys = SetupSteps.keys(step, in: steps, fields: fields)
    return keys.contains { key in
      guard !hasNoEffect(key, variant, mobile: mobile) else { return false }
      let field = fields.first { $0.key == key }
      return OptionSchema.evaluate(field?.when, values: .object(options), fields: fields)
    }
  }
}
