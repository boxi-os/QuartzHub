import Foundation
import Testing
@testable import QuartzHubCore

/// `LayoutBoxes` against QuartzControl's own code (`scripts/layout-boxes-golden.mjs`). The schema is
/// quartz-layout-box's own from gui-test.
@Suite struct LayoutBoxesTests {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/layout-boxes")
  static let golden: JSONValue? = (try? Data(contentsOf: directory.appendingPathComponent("cases.json"))).flatMap { try? JSJSON.parse($0) }
  static let fields: [OptionField] = {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("schema.json")), let schema = try? JSJSON.parse(data) else { return [] }
    return OptionSchema.normalize(jsonSchema: schema, source: .configSchema).fields
  }()

  static func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap(\.stringValue) }
  /// `null` in the golden stands for "not there".
  static func lift(_ value: JSONValue?) -> JSONValue? { value == .null ? nil : value }
  static func json(_ broken: [LayoutBoxes.Broken]) -> JSONValue {
    .array(broken.map { b in .object(JSONObject([("key", .string(b.key))] + (b.lang.map { [("lang", .string($0))] } ?? []))) })
  }
  static func json(_ refs: [LayoutBoxes.SnippetRef]) -> JSONValue {
    .array(refs.map { r in
      .object(JSONObject([("file", .string(r.file)), ("dir", .string(r.dir))] + (r.lang.map { [("lang", .string($0))] } ?? [])
                         + [("inherited", .bool(r.inherited))]))
    })
  }

  @Test func constantsAreQuartzControls() throws {
    let c = try #require(Self.golden?["constants"])
    #expect(c["readAgainst"] == .string(LayoutBoxes.readAgainst))
    #expect(Self.strings(c["sameCode"]) == LayoutBoxes.sameCode)
    #expect(c["nullSafeSince"] == .string(LayoutBoxes.nullSafeSince))
    #expect(c["dir"] == .string(LayoutBoxes.defaultDir))
    #expect(c["file"] == .string(LayoutBoxes.defaultFile))
    #expect(Self.strings(c["placeholders"]) == LayoutBoxes.placeholders)
    #expect(c["frontmatter"] == .string(LayoutBoxes.frontmatterPlaceholder))
    #expect(c["images"] == .string(LayoutBoxes.imagesDir))
  }

  @Test func optionsReadAsThePluginReadsThem() throws {
    let golden = try #require(Self.golden)
    let cases = try #require(golden["options"]?.arrayValue)
    #expect(cases.count == 34)
    for item in cases {
      let options = Self.lift(item["options"])
      let label = options.map(JSJSON.compact) ?? "-"
      #expect(.object(LayoutBoxes.withoutNulls(options)) == item["withoutNulls"], "\(label)")
      #expect(LayoutBoxes.contentKind(options).rawValue == item["kind"]?.stringValue, "\(label)")
      #expect(LayoutBoxes.dir(options) == item["dir"]?.stringValue, "\(label)")
      let merged: JSONValue = .array(LayoutBoxes.mergedVariants(options).map { lang, merged in
        .object(JSONObject([("lang", lang.map(JSONValue.string) ?? .null), ("merged", .object(merged))]))
      })
      #expect(merged == item["merged"], "\(label)")
      for (installed, expected) in item["broken"]?.objectValue.map({ o in o.keys.map { ($0, o[$0]!) } }) ?? [] {
        #expect(Self.json(LayoutBoxes.brokenOptions(options, installed: installed == "null" ? nil : installed)) == expected, "\(label) \(installed)")
      }
      #expect(Self.json(LayoutBoxes.snippetRefs(options)) == item["refs"], "\(label)")
      #expect(LayoutBoxes.htmls(options) == Self.strings(item["htmls"]), "\(label)")
      #expect(LayoutBoxes.langsWithOwnText(options) == Self.strings(item["ownText"]), "\(label)")
    }
    for (installed, expected) in golden["nullBreaks"]?.objectValue.map({ o in o.keys.map { ($0, o[$0]!) } }) ?? [] {
      #expect(LayoutBoxes.nullBreaks(installed == "null" ? nil : installed) == expected.boolValue, "\(installed)")
    }
    for item in golden["dirs"]?.arrayValue ?? [] {
      #expect(LayoutBoxes.normalizeDir(item["dir"]!.stringValue!) == item["normalized"]?.stringValue, "\(item["dir"]!)")
    }
    for item in golden["images"]?.arrayValue ?? [] {
      #expect(LayoutBoxes.mentionsImage(item["text"]!.stringValue!, item["name"]!.stringValue!) == item["result"]?.boolValue, "\(item)")
    }
  }

  @Test func boxesAndRenamesAsQuartzControlDoesThem() throws {
    let golden = try #require(Self.golden)
    let plugins = NavigationsTests.entries(golden["plugins"])
    let boxes = LayoutBoxes.boxes(plugins).map { JSONValue.object(JSONObject([("index", .number(Double($0.index))), ("occurrence", .number(Double($0.occurrence)))])) }
    #expect(.array(boxes) == golden["boxes"])
    let renames = try #require(golden["renames"]?.arrayValue)
    #expect(renames.count == 6)
    for item in renames {
      let (dir, from, to) = (item["dir"]!.stringValue!, item["from"]!.stringValue!, item["to"]!.stringValue!)
      let result = LayoutBoxes.renameSnippetRefs(plugins, dir: dir, from: from, to: to)
      #expect(Double(result.count) == item["count"]?.numberValue, "\(dir) \(from) → \(to)")
      let expected = NavigationsTests.entries(item["plugins"])
      #expect(result.plugins.count == expected.count)
      for (mine, theirs) in zip(result.plugins, expected) {
        #expect(JSJSON.compact(.object(mine.object)) == JSJSON.compact(.object(theirs.object)), "\(dir) \(from) → \(to)")
      }
    }
  }

  @Test func formExtrasSayWhatQuartzControlSays() throws {
    let golden = try #require(Self.golden)
    let keys = Self.strings(golden["keys"])
    let roots = try #require(golden["roots"]?.arrayValue)
    #expect(roots.count == 372)
    for item in roots {
      let options = try #require(item["options"]?.objectValue)
      let installed = item["installed"]?.stringValue
      let withTiles = item["withTiles"]?.boolValue ?? true
      let label = JSJSON.compact(.object(options)) + " \(installed ?? "-") \(withTiles)"
      let silenced = LayoutBoxes.silenced(options, installed: installed)
      #expect(keys.filter(silenced) == Self.strings(item["silenced"]), "\(label)")
      let root = LayoutBoxes.root(options: options, installed: installed, translate: OptionFormTextTests.echo, withTiles: withTiles)
      for key in keys {
        #expect(root.inactiveReason?(key).map(JSONValue.string) ?? .null == item["reasons"]?[key], "\(label) \(key)")
      }
      #expect(keys.filter { root.hideUnlessSet?($0) ?? false } == Self.strings(item["hide"]), "\(label)")
      let lead = try #require(root.lead)
      #expect(keys.filter(lead.has) == Self.strings(item["lead"]?["has"]), "\(label)")
      #expect(lead.title == item["lead"]?["title"]?.stringValue, "\(label)")
      #expect(lead.empty == item["lead"]?["empty"]?.stringValue, "\(label)")
      for entry in item["entry"]?.arrayValue ?? [] {
        let values = entry["entry"]?.objectValue ?? JSONObject()
        let above = entry["above"]?.objectValue ?? JSONObject()
        for key in ["file", "dir", "html", "title"] {
          #expect(root.entryReason?(key, values, above).map(JSONValue.string) ?? .null == entry["reasons"]?[key], "\(label) \(key)")
        }
      }
    }
  }

  @Test func snippetFieldRules() throws {
    let golden = try #require(Self.golden)
    #expect(Self.fields.contains { $0.key == "dir" })
    for item in golden["formats"]?.arrayValue ?? [] {
      #expect(LayoutBoxes.format(ofFile: item["name"]!.stringValue!).rawValue == item["format"]?.stringValue, "\(item)")
    }
    let references = try #require(golden["references"]?.arrayValue)
    #expect(references.count == 12)
    for item in references {
      let format = LayoutBoxes.SnippetFormat(rawValue: item["format"]!.stringValue!)!
      #expect(LayoutBoxes.imageReference(item["path"]!.stringValue!, format: format) == item["reference"]?.stringValue, "\(item)")
    }
    for item in golden["siblings"]?.arrayValue ?? [] {
      let values = item["values"]?.objectValue ?? JSONObject()
      let value = LayoutBoxes.siblingValue(item["key"]!.stringValue!, values: values, fields: Self.fields)
      #expect(value ?? .string("__undefined") == item["value"], "\(item)")
    }
  }

  /// The plugin list's form: the editors' extras, nothing hidden, the variant or text leading.
  @Test func rootWithoutTilesPicksThePlugin() throws {
    func entry(_ source: String, _ options: JSONObject) -> PluginEntry {
      PluginEntry(object: JSONObject([("name", .string("x")), ("source", .string(source)), ("enabled", .bool(true)), ("options", .object(options))]))
    }
    let box = try #require(OptionRoot.withoutTiles(entry("github:boxi-os/quartz-layout-box", JSONObject([("html", .string("t"))])),
                                                   fields: Self.fields, packageVersion: "0.4.2", lang: .de))
    #expect(box.hideUnlessSet == nil)
    #expect(box.lead?.title == L10n.t("extraContent.leadContent"))
    #expect(box.inactiveReason?("file") == L10n.t("extraContent.silencedByText"))
    let nav = try #require(OptionRoot.withoutTiles(entry("github:boxi-os/quartz-navigations", JSONObject()), fields: [], packageVersion: nil, lang: .de))
    #expect(nav.hideUnlessSet == nil)
    #expect(nav.lead?.has("variant") == true)
    #expect(OptionRoot.withoutTiles(entry("@quartz-community/explorer", JSONObject()), fields: [], packageVersion: nil, lang: .de) == nil)
    let forms = try #require(OptionRoot.withoutTiles(entry("github:boxi-os/quartz-forms", JSONObject()), fields: [], packageVersion: nil, lang: .de))
    #expect(forms.entryReason?("pageContext", JSONObject([("anonymous", .bool(true))]), JSONObject()) == L10n.t("formsEditor.pageContextAnonymous"))
  }
}
