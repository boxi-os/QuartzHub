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

  /// quartz-layout-box's schema as gui-test has it (0.4.2, `Fixtures/option-schema/real`).
  static let boxFields: [OptionField] = {
    let url = PluginSchemaReaderTests.fixtures.appendingPathComponent("real/.quartz/plugins/quartz-layout-box/package.json")
    guard let data = try? Data(contentsOf: url), let package = try? JSJSON.parse(data),
          let schema = package["quartz"]?["configSchema"] else { return [] }
    return OptionSchema.normalize(jsonSchema: schema, source: .configSchema).fields
  }()

  @Test func boxStepsCoverTheSchema() throws {
    let fields = Self.boxFields
    try #require(fields.count >= 10)
    #expect(SetupSteps.unplaced(LayoutBoxes.steps, fields: fields).isEmpty)
    let assigned = SetupSteps.assign(LayoutBoxes.steps, fields: fields)
    #expect(assigned["html"] == "content" && assigned["file"] == "content" && assigned["dir"] == "content" && assigned["placeholders"] == "content")
    #expect(assigned["title"] == "look" && assigned["collapsed"] == "look")
    #expect(assigned["byLang"] == "languages" && assigned["frontmatterKey"] == "languages" && assigned["className"] == "finish")
    let steps = Dictionary(uniqueKeysWithValues: LayoutBoxes.steps.map { ($0.id, $0) })
    for id in ["kind", "content", "place", "look", "languages", "finish"] {
      #expect(LayoutBoxes.stepHasEffect(try #require(steps[id]), options: JSONObject([("html", .string("<p>x</p>"))]), fields: fields,
                                        installed: LayoutBoxes.readAgainst), "\(id)")
    }
  }

  /// Every key of a form has one step, and it is the step the plugin's messages about it go to.
  @Test func formStepsAgreeWithTheMessages() throws {
    var seen: [String: String] = [:]
    for step in FormsOptions.steps {
      for key in step.keys {
        #expect(seen[key] == nil, "\(key) twice")
        seen[key] = step.id
      }
    }
    #expect(Set(seen.keys) == FormsOptions.formKeys)
    for (key, step) in seen {
      let message = FormsOptions.PlacedMessage(text: "", form: "contact", field: nil, section: nil, rest: "\(key): wrong")
      #expect(FormsOptions.step(of: FormsOptions.part(message)) == step, "\(key)")
    }
    // An unknown key's message lands in the summary, a field's in the fields.
    #expect(FormsOptions.step(of: FormsOptions.part(FormsOptions.PlacedMessage(text: "", form: "contact", field: nil, section: nil,
                                                                               rest: "colour: wrong"))) == "finish")
    #expect(FormsOptions.step(of: FormsOptions.part(FormsOptions.PlacedMessage(text: "", form: "contact", field: 2, section: nil,
                                                                               rest: "x"))) == "fields")
    for part in FormsOptions.Part.allCases {
      #expect(FormsOptions.steps.contains { $0.id == FormsOptions.step(of: part) }, "\(part)")
    }
  }

  /// quartz-multilanguage's schema as gui-test has it: the site's steps take the languages, the
  /// detection and the switcher; what is left are the groups the summary lists.
  @Test func siteLanguageStepsAgainstTheSchema() throws {
    let url = PluginSchemaReaderTests.fixtures.appendingPathComponent("real/.quartz/plugins/quartz-multilanguage/package.json")
    let package = try JSJSON.parse(Data(contentsOf: url))
    let fields = OptionSchema.normalize(jsonSchema: try #require(package["quartz"]?["configSchema"]), source: .configSchema).fields
    try #require(fields.count > 10)
    let assigned = SetupSteps.assign(MultilanguageOptions.siteSteps, fields: fields)
    #expect(assigned["languages"] == "languages" && assigned["defaultLanguage"] == "publish" && assigned["publishLanguages"] == "publish")
    #expect(assigned["detection"] == "detection" && assigned["linking"] == "detection" && assigned["switcher"] == "switcher")
    let rest = Set(fields.filter { assigned[$0.key] == "finish" }.compactMap(\.group))
    #expect(rest == ["Addresses (SEO)", "Redirects", "Notices", "Links and dates"])
    // A language's fields: every one of an item of `languages` has its step.
    guard case .array(let items)? = fields.first(where: { $0.key == "languages" })?.node else { Issue.record("no items"); return }
    var itemKeys: [String] = []
    switch items {
    case .object(let f, _): itemKeys = f.map(\.key)
    case .union(let variants): for case .object(let f, _) in variants { itemKeys = f.map(\.key) }
    default: break
    }
    try #require(!itemKeys.isEmpty)
    let languageKeys = Set(MultilanguageOptions.languageSteps.flatMap(\.keys))
    #expect(Set(itemKeys).isSubset(of: languageKeys), "\(Set(itemKeys).subtracting(languageKeys))")
  }
}
