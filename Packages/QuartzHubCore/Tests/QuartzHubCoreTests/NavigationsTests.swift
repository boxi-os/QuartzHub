import Foundation
import Testing
@testable import QuartzHubCore

/// `NavigationVariants`, `InstanceClass` and `LayoutEntries` against QuartzControl's own code
/// (`scripts/navigations-golden.mjs`). The schema is quartz-navigations' own from gui-test.
@Suite struct NavigationsTests {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/navigations")
  static let golden: JSONValue? = (try? Data(contentsOf: directory.appendingPathComponent("cases.json"))).flatMap { try? JSJSON.parse($0) }
  static let fields: [OptionField] = {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("schema.json")), let schema = try? JSJSON.parse(data) else { return [] }
    return OptionSchema.normalize(jsonSchema: schema, source: .configSchema).fields
  }()

  static func entries(_ value: JSONValue?) -> [PluginEntry] {
    (value?.arrayValue ?? []).compactMap { $0.objectValue.map(PluginEntry.init(object:)) }
  }

  static func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap(\.stringValue) }

  @Test func variantTableAndReasons() throws {
    let golden = try #require(Self.golden)
    let positions = try #require(golden["variantPositions"]?.objectValue)
    #expect(positions.keys == NavigationVariants.Variant.allCases.map(\.rawValue))
    for variant in NavigationVariants.Variant.allCases { #expect(positions[variant.rawValue] == .string(variant.position)) }
    #expect(golden["readAgainst"] == .string(NavigationVariants.readAgainst))
    #expect(Self.strings(golden["sameCode"]) == NavigationVariants.sameCode)

    let cases = try #require(golden["noEffect"]?.arrayValue)
    #expect(cases.count > 3000)
    var wrong: [String] = []
    for item in cases {
      let key = item["key"]!.stringValue!
      let variant = NavigationVariants.Variant(rawValue: item["variant"]!.stringValue!)!
      let mobile = item["mobile"] == .null ? nil : item["mobile"]
      let why = NavigationVariants.noEffectReason(key, variant, mobile: mobile)
      let mine: JSONValue = why.map { .object(JSONObject([("variants", .array($0.variants.map { .string($0.rawValue) })),
                                                          ("mobile", .array($0.mobile.map(JSONValue.string)))])) } ?? .null
      if NavigationVariants.hasNoEffect(key, variant, mobile: mobile) != item["none"]?.boolValue || mine != item["why"] {
        wrong.append("\(key) \(variant) \(mobile.map(JSJSON.compact) ?? "-")")
      }
    }
    #expect(wrong.isEmpty, "\(wrong.count): \(wrong.prefix(5))")
  }

  @Test func formExtrasSayWhatQuartzControlSays() throws {
    let golden = try #require(Self.golden)
    let keys = Self.strings(golden["keys"])
    let roots = try #require(golden["roots"]?.arrayValue)
    #expect(roots.count == 52)
    #expect(Self.fields.contains { $0.key == "mobile" })
    for item in roots {
      let options = item["options"]?.objectValue ?? JSONObject()
      let lang: OptionFormText.Language = item["lang"] == .string("en") ? .en : .de
      let withVariant = item["withVariant"]?.boolValue ?? false
      let root = NavigationVariants.root(options: options, fields: Self.fields, lang: lang, translate: OptionFormTextTests.echo,
                                         withVariant: withVariant)
      let label = JSJSON.compact(.object(options)) + " \(lang) \(withVariant)"
      #expect(NavigationVariants.variant(options).rawValue == item["variant"]?.stringValue, "\(label)")
      for key in keys {
        #expect(root.inactiveReason?(key).map(JSONValue.string) ?? .null == item["reasons"]?[key], "\(label) \(key)")
      }
      #expect(keys.filter { root.hideUnlessSet?($0) ?? false } == Self.strings(item["hide"]), "\(label)")
      let lead = try #require(root.lead)
      let has = keys.filter(lead.has) + (lead.has("variant") ? ["variant"] : [])
      #expect(has == Self.strings(item["lead"]?["has"]), "\(label)")
      #expect(lead.title == item["lead"]?["title"]?.stringValue, "\(label)")
      #expect(lead.empty == item["lead"]?["empty"]?.stringValue, "\(label)")
      #expect(lead.note.map(JSONValue.string) ?? .null == item["lead"]?["note"], "\(label)")
    }
  }

  @Test func classesAsQuartzControlGivesThem() throws {
    let classes = try #require(Self.golden?["classes"])
    let plugins = Self.entries(classes["plugins"])
    let styled = Set(Self.strings(classes["styled"]))
    for item in classes["slugs"]?.arrayValue ?? [] {
      let name = item["name"]!.stringValue!
      #expect(InstanceClass.suggest(prefix: "nav-", name: name, fallback: "navigation", plugins: plugins, styled: styled)
              == item["nav"]?.stringValue, "\(name)")
      #expect(InstanceClass.suggest(prefix: "layout-box-", name: name, fallback: "box", plugins: plugins) == item["box"]?.stringValue, "\(name)")
    }
    for item in classes["unique"]?.arrayValue ?? [] {
      #expect(InstanceClass.unique(item["candidate"]!.stringValue!, plugins: plugins, styled: styled) == item["result"]?.stringValue)
    }
    let perEntry = try #require(classes["perEntry"]?.arrayValue)
    #expect(perEntry.count == 12)
    for item in perEntry {
      let entry = PluginEntry(object: item["entry"]!.objectValue!)
      let label = JSJSON.compact(.object(entry.object))
      #expect(InstanceClass.tokens(entry) == Self.strings(item["tokens"]), "\(label)")
      #expect(InstanceClass.own(entry).map(JSONValue.string) ?? .null == item["own"], "\(label)")
      #expect(InstanceClass.source(entry) == item["source"]?.stringValue, "\(label)")
      var copy = entry.object
      copy["layout"] = .object(JSONObject([("position", .string("left")), ("priority", .number(1))]))
      let made = InstanceClass.withOwnForCopy(PluginEntry(object: copy), source: entry, plugins: plugins, styled: styled)
      #expect(JSONValue.object(made.object) == item["copy"], "\(label): \(JSJSON.compact(.object(made.object))) ≠ \(JSJSON.compact(item["copy"] ?? .null))")
    }
    for item in classes["withs"]?.arrayValue ?? [] {
      #expect(JSONValue.object(InstanceClass.with(item["options"]?.objectValue, "nav-x")) == item["result"])
    }
  }

  @Test func placingRenumbersAsTheBoardDoes() throws {
    let golden = try #require(Self.golden)
    let board = Self.entries(golden["board"])
    let places = try #require(golden["places"]?.arrayValue)
    #expect(places.count == 71)
    for item in places {
      let index = Int(item["index"]!.numberValue!)
      let group: String?? = switch item["group"] { case nil: nil; case .null?: .some(nil); case .string(let g)?: .some(g); default: nil }
      let mine = LayoutEntries.place(board, index: index, position: item["position"]!.stringValue!,
                                     insertIndex: item["insertIndex"]?.numberValue.map { Int($0) }, group: group)
      let layouts = mine.map { $0.object["layout"] ?? .null }
      #expect(layouts == item["layouts"]?.arrayValue, "\(JSJSON.compact(item.objectValue.map { o in var c = o; c["layouts"] = nil; return .object(c) } ?? .null))")
    }
  }

  @Test func duplicatingRenumbersAsTheBoardDoes() throws {
    let golden = try #require(Self.golden)
    let board = Self.entries(golden["board"])
    let map = LayoutEntries.positionMap(board)
    for position in LayoutEntries.positions {
      #expect(map[position]?.map { JSONValue.number(Double($0)) } == golden["positionMap"]?[position]?.arrayValue, "\(position)")
    }
    let ranks = try #require(golden["ranks"]?.objectValue)
    #expect(Set(ranks.keys) == Set(LayoutEntries.duplicateRanks(board).keys.map(String.init)))
    for (index, rank) in LayoutEntries.duplicateRanks(board) { #expect(ranks[String(index)] == .number(Double(rank))) }
    for (index, ref) in (golden["refs"]?.arrayValue ?? []).enumerated() {
      let mine = LayoutEntries.componentRef(board, index)
      #expect(mine?.name == ref["name"]?.stringValue && mine.map { JSONValue.number(Double($0.occurrence)) } == ref["occurrence"], "\(index)")
    }
    let styled = Set(Self.strings(golden["classes"]?["styled"]))
    let duplicates = try #require(golden["duplicates"]?.arrayValue)
    #expect(duplicates.contains { $0["threw"] != nil })
    for item in duplicates {
      let index = Int(item["index"]!.numberValue!)
      let mine = LayoutEntries.duplicateAfter(board, index, styled: styled)
      guard case .object(let result)? = item["result"] else {
        #expect(mine == nil, "\(index)")
        continue
      }
      #expect(mine?.newIndex == result["newIndex"]?.numberValue.map { Int($0) }, "\(index)")
      #expect(mine.map { JSONValue.array($0.plugins.map { .object($0.object) }) } == result["plugins"], "\(index)")
    }
  }
}
