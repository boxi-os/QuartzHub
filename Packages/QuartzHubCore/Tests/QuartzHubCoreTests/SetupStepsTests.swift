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
  static let current = fields("schema-0.5.1.json")

  @Test func everyOptionHasExactlyOneStep() throws {
    for fields in [Self.old, Self.current] {
      try #require(fields.count > 40)
      // That every key lands in exactly one step follows from `assign`; what can go wrong is the
      // table: an option caught only by the fallback, or a step of options left without any
      // (review 2026-11-16, N2: two expectations here could not fail).
      #expect(SetupSteps.unplaced(NavigationVariants.steps, fields: fields).isEmpty)
      for step in NavigationVariants.steps where step.part == .options {
        #expect(!SetupSteps.keys(step, in: NavigationVariants.steps, fields: fields).isEmpty, "\(step.id) is empty")
      }
    }
    let assigned = SetupSteps.assign(NavigationVariants.steps, fields: Self.current)
    #expect(assigned["variant"] == "variant")
    #expect(assigned["rail"] == "look" && assigned["align"] == "look")
    // 0.5.1: the dividers stand with the labels and icons, `rail.startPinned` inside `rail`.
    #expect(assigned["dividers"] == "labels")
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

  /// Cancelling puts back the priorities the run's own steps renumbered, and nothing else: not a
  /// title another step set, not a move someone made meanwhile (review 2026-11-16, M2).
  @Test func cancellingRestoresWhatTheRunRenumbered() throws {
    func entry(_ name: String, _ position: String, _ priority: Double, title: String? = nil) -> PluginEntry {
      var object = JSONObject([("name", .string(name)),
                               ("layout", .object(JSONObject([("position", .string(position)), ("priority", .number(priority))])))])
      if let title { object["options"] = .object(JSONObject([("title", .string(title))])) }
      return PluginEntry(object: object)
    }
    let before = [entry("a", "header", 15), entry("b", "header", 25), entry("c", "left", 7), entry("d", "left", 9)]
    let added = before + [entry("nav", "header", 5)]
    // The new one moved behind "a": the header renumbered in steps of ten.
    let placed = LayoutEntries.place(added, index: 4, position: "header", insertIndex: 1)
    #expect(placed[0] != before[0] && placed[1] != before[1] && placed[2] == before[2])
    let run = SetupRun(key: "nav", before: before).recording(added, placed, own: 4)
    #expect(run.placed == [0: 10, 1: 30])
    // Meanwhile "c" got a title, "b" was moved on purpose and "d" renumbered by some other move.
    var edited = placed
    edited[1] = entry("b", "header", 5)
    edited[2] = entry("c", "left", 7, title: "kept")
    edited[3] = entry("d", "left", 20)
    let restored = run.restoringPriorities(Array(edited.prefix(4)))
    #expect(restored[0] == before[0])
    #expect(restored[1] == entry("b", "header", 5))
    #expect(restored[2] == entry("c", "left", 7, title: "kept"))
    #expect(restored[3] == entry("d", "left", 20))
    // Gegenprobe: a run that recorded nothing puts nothing back.
    #expect(SetupRun(key: "nav", before: before).restoringPriorities(Array(edited.prefix(4))) == Array(edited.prefix(4)))
    // A renamed run keeps what it recorded, and the steps seen.
    var seen = run
    seen.visited = ["place", "pages"]
    #expect(seen.renamed("nav-2").placed == run.placed && seen.renamed("nav-2").key == "nav-2")
    #expect(seen.renamed("nav-2").visited == ["place", "pages"])
  }

  /// A first run ends with its entry: removed some other way, the run must not live on and take
  /// the next entry under the same name (review 2026-11-16, M1); nor with another entry chosen (N1).
  @Test func aRunLastsWhileItsEntryIsThereAndChosen() {
    let run = SetupRun(key: "nav-bar-2", before: [])
    #expect(run.lasts(keys: ["nav-bar", "nav-bar-2"], selected: "nav-bar-2"))
    #expect(!run.lasts(keys: ["nav-bar"], selected: "nav-bar-2"))
    #expect(!run.lasts(keys: [], selected: nil))
    #expect(!run.lasts(keys: ["nav-bar", "nav-bar-2"], selected: "nav-bar"))
    #expect(!run.lasts(keys: ["nav-bar", "nav-bar-2"], selected: nil))
  }

  /// One snapshot per inspector, and again after a write failed (review 2026-11-16, M5).
  @Test func theOneSnapshotIsTakenAgainAfterAFailedWrite() {
    var once = SnapshotOnce()
    // `#expect` cannot call a mutating method: each answer first, then the expectation.
    let inFirstRun = once.take(firstRun: true, failures: 0)
    let first = once.take(failures: 0)
    let second = once.take(failures: 0)
    // The first write failed (at the snapshot, or refused): the next one takes it again.
    let afterFailure = once.take(failures: 1)
    let thenNone = once.take(failures: 1)
    #expect(!inFirstRun && first && !second && afterFailure && !thenNone)
    var done = SnapshotOnce()
    done.taken(failures: 2)
    let afterDone = done.take(failures: 2)
    #expect(!afterDone)
    // Gegenprobe, the rule before: a flag set when asked, whatever became of the write.
    var flag = false
    func old() -> Bool { if flag { return false }; flag = true; return true }
    let oldFirst = old()
    let oldAfterFailure = old()
    #expect(oldFirst && !oldAfterFailure)
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
    // And the other way: a key of the steps that is no field of an item is one of the plugin's
    // options, not a name the schema no longer has (N2).
    let beyond = languageKeys.subtracting(itemKeys)
    #expect(beyond == ["defaultLanguage", "publishLanguages"])
    #expect(beyond.allSatisfy { key in fields.contains { $0.key == key } })
  }
}
