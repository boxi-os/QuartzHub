import Foundation
import Testing
@testable import QuartzHubCore

/// The steps of the inspector (docs/plan-assistenten.md) against the plugins' real schemas:
/// quartz-navigations 0.4 (QuartzControl's fixture) and 0.5.0 (copied from its package.json).
@Suite struct SetupStepsTests {
  static func fields(_ name: String) -> [OptionField] {
    let url = NavigationsTests.directory.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url), let schema = try? JSJSON.parse(data) else { return [] }
    return OptionSchema.normalize(jsonSchema: schema, source: .configSchema).fields
  }

  static let old = fields("schema.json")
  static let current = fields("schema-0.5.0.json")

  @Test func everyOptionHasExactlyOneStep() throws {
    for fields in [Self.old, Self.current] {
      try #require(fields.count > 40)
      let assigned = SetupSteps.assign(NavigationVariants.steps, fields: fields)
      #expect(Set(assigned.keys) == Set(fields.map(\.key)))
      let perStep = NavigationVariants.steps.map { SetupSteps.keys($0, in: NavigationVariants.steps, fields: fields) }
      #expect(perStep.flatMap { $0 }.count == fields.count)
      // No option lands in the last step only because no step names its group.
      #expect(SetupSteps.unplaced(NavigationVariants.steps, fields: fields).isEmpty)
    }
    let assigned = SetupSteps.assign(NavigationVariants.steps, fields: Self.current)
    #expect(assigned["variant"] == "variant")
    #expect(assigned["rail"] == "look" && assigned["align"] == "look")
    #expect(assigned["rootPath"] == "pages" && assigned["hideDrafts"] == "hide" && assigned["sort"] == "hide")
    #expect(assigned["mobile"] == "mobile" && assigned["title"] == "labels" && assigned["className"] == "finish")
  }

  /// Gegenprobe: a group no step names falls to the last step and is reported.
  @Test func anUnknownGroupFallsToTheLastStep() throws {
    var fields = Self.current
    let index = try #require(fields.firstIndex { $0.key == "hideDrafts" })
    fields[index].group = "Something new"
    #expect(SetupSteps.assign(NavigationVariants.steps, fields: fields)["hideDrafts"] == "finish")
    #expect(SetupSteps.unplaced(NavigationVariants.steps, fields: fields) == ["hideDrafts"])
  }

  @Test func whichStepsDoSomething() throws {
    let steps = Dictionary(uniqueKeysWithValues: NavigationVariants.steps.map { ($0.id, $0) })
    let look = try #require(steps["look"])
    func effect(_ step: SetupStep, _ options: JSONObject) -> Bool {
      NavigationVariants.stepHasEffect(step, options: options, fields: Self.current)
    }
    // A tree reads none of the variants' options, nor do columns: the plugin reads `columns.max`
    // and uses it nowhere (render.tsx 0.5.0). Every other variant reads some.
    #expect(!effect(look, JSONObject([("variant", .string("tree"))])))
    #expect(!effect(look, JSONObject([("variant", .string("columns"))])))
    #expect(!effect(look, JSONObject()))
    for variant in NavigationVariants.Variant.allCases where variant != .tree && variant != .columns {
      #expect(effect(look, JSONObject([("variant", .string(variant.rawValue))])), "\(variant)")
    }
    // A tree that folds on smartphones reads chevrons and the folding options again.
    #expect(effect(look, JSONObject([("variant", .string("tree")), ("mobile", .string("accordion"))])))
    // The parts QuartzHub draws itself, and the steps every variant reads, always do something.
    for id in ["variant", "place", "pages", "hide", "mobile", "labels", "finish"] {
      for variant in NavigationVariants.Variant.allCases {
        #expect(effect(try #require(steps[id]), JSONObject([("variant", .string(variant.rawValue))])), "\(id) \(variant)")
      }
    }
  }

  /// Cancelling puts back what the placement step renumbered, and nothing else.
  @Test func cancellingRestoresThePriorities() throws {
    func entry(_ name: String, _ position: String, _ priority: Double, title: String? = nil) -> PluginEntry {
      var object = JSONObject([("name", .string(name)),
                               ("layout", .object(JSONObject([("position", .string(position)), ("priority", .number(priority))])))])
      if let title { object["options"] = .object(JSONObject([("title", .string(title))])) }
      return PluginEntry(object: object)
    }
    let before = [entry("a", "header", 15), entry("b", "header", 25), entry("c", "left", 7)]
    let added = before + [entry("nav", "header", 5)]
    // The new one moved behind "a": the header renumbered in steps of ten.
    let placed = LayoutEntries.place(added, index: 3, position: "header", insertIndex: 1)
    #expect(placed[0] != before[0] && placed[1] != before[1])
    // Meanwhile "c" got a title in another step: that stays.
    var edited = placed
    edited[2] = entry("c", "left", 7, title: "kept")
    let removed = Array(edited.prefix(3))
    let restored = LayoutEntries.restoringPriorities(removed, from: before)
    #expect(Array(restored.prefix(2)) == Array(before.prefix(2)))
    #expect(restored[2] == entry("c", "left", 7, title: "kept"))
    // Gegenprobe: without it the file keeps the renumbered priorities.
    #expect(Array(removed.prefix(2)) != Array(before.prefix(2)))
  }
}
