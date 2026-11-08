import Foundation
import Testing
@testable import QuartzHubCore

/// `MultilanguageOptions` against QuartzControl's own code (`scripts/multilanguage-golden.mjs`).
/// The steps are taken on the entries `languages` hands out, as the golden took them on its own.
@Suite struct MultilanguageTests {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/multilanguage")
  static let golden: JSONValue? = (try? Data(contentsOf: directory.appendingPathComponent("cases.json"))).flatMap { try? JSJSON.parse($0) }
  static let schema: NormalizedOptionSchema? = {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("schema.json")), let schema = try? JSJSON.parse(data) else { return nil }
    return OptionSchema.normalize(jsonSchema: schema, source: .configSchema)
  }()

  static func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap(\.stringValue) }

  static func apply(_ options: JSONObject, _ step: JSONValue) -> JSONObject {
    let langs = MultilanguageOptions.languages(options)
    switch step["op"]?.stringValue {
    case "rename": return MultilanguageOptions.rename(options, langs, from: step["from"]!.stringValue!, to: step["to"]!.stringValue!)
    case "remove": return MultilanguageOptions.remove(options, langs, code: step["code"]!.stringValue!)
    case "publish": return MultilanguageOptions.withPublished(options, langs, code: step["code"]!.stringValue!, on: step["on"]!.boolValue!)
    case "swap":
      var next = langs
      next.swapAt(Int(step["i"]!.numberValue!), Int(step["j"]!.numberValue!))
      return MultilanguageOptions.withLanguages(options, next)
    case "edit":
      let i = Int(step["i"]!.numberValue!)
      return MultilanguageOptions.withLanguages(options, langs.enumerated().map { $0.offset == i ? $0.element.with(step["key"]!.stringValue!, step["value"]) : $0.element })
    case "add": return MultilanguageOptions.withLanguages(options, langs + [MultilanguageOptions.Language(code: step["code"]!.stringValue!)])
    default: return MultilanguageOptions.withLanguages(options, langs)
    }
  }

  @Test func languagesAndEveryStepAsQuartzControlWritesThem() throws {
    let golden = try #require(Self.golden)
    #expect(golden["readAgainst"] == .string(MultilanguageOptions.readAgainst))
    #expect(Self.strings(golden["sameCode"]) == MultilanguageOptions.sameCode)
    #expect(Self.strings(golden["languageKeys"]) == MultilanguageOptions.languageKeys)
    let cases = try #require(golden["cases"]?.arrayValue)
    #expect(cases.count == 13)
    var steps = 0
    for item in cases {
      let options = item["options"]?.objectValue
      let label = item["options"].map(JSJSON.compact) ?? "-"
      let langs = MultilanguageOptions.languages(options)
      #expect(.array(langs.map { .object($0.fields) }) == item["languages"], "\(label)")
      #expect(MultilanguageOptions.defaultLanguage(options, langs) == item["defaultLanguage"]?.stringValue, "\(label)")
      #expect(MultilanguageOptions.published(options, langs) == Self.strings(item["published"]), "\(label)")
      for l in langs {
        #expect(MultilanguageOptions.publishedByRemoving(options, langs, code: l.code).map(\.code) == Self.strings(item["byRemoving"]?[l.code]), "\(label) \(l.code)")
      }
      for entry in item["steps"]?.arrayValue ?? [] {
        steps += 1
        let result = Self.apply(options ?? JSONObject(), entry["step"]!)
        #expect(JSJSON.compact(.object(result)) == JSJSON.compact(entry["result"]!), "\(label) \(JSJSON.compact(entry["step"]!))")
      }
      for lang in [OptionFormText.Language.de, .en] {
        let groups = MultilanguageOptions.settingsGroups(Self.schema, options: options ?? JSONObject(), lang: lang)
        let mine: JSONValue = .array(groups.map { g in
          .object(JSONObject([("id", .string(g.id)), ("title", .string(g.title)), ("keys", .array(g.keys.map(JSONValue.string))),
                              ("sole", MultilanguageOptions.soleObject(Self.schema, g).map { .string($0.key) } ?? .null)]))
        })
        #expect(mine == item["groups"]?[lang.rawValue], "\(label) \(lang)")
      }
      let bare: JSONValue = .array(MultilanguageOptions.settingsGroups(nil, options: options ?? JSONObject(), lang: .de).map { g in
        .object(JSONObject([("id", .string(g.id)), ("title", .string(g.title)), ("keys", .array(g.keys.map(JSONValue.string)))]))
      })
      #expect(bare == item["groupsWithoutSchema"], "\(label)")
    }
    #expect(steps == 188)
  }

  /// Fields without a group and without an order, which the real schema does not have.
  @Test func groupsOfASchemaWithLooseFields() throws {
    let golden = try #require(Self.golden)
    let schema = OptionSchema.normalize(jsonSchema: try #require(golden["syntheticSchema"]), source: .configSchema)
    let groups = MultilanguageOptions.settingsGroups(schema, options: JSONObject([("plain", .string("x")), ("stray", .number(1))]), lang: .de)
    let mine: JSONValue = .array(groups.map { g in
      .object(JSONObject([("id", .string(g.id)), ("title", .string(g.title)), ("keys", .array(g.keys.map(JSONValue.string))),
                          ("sole", MultilanguageOptions.soleObject(schema, g).map { .string($0.key) } ?? .null)]))
    })
    #expect(mine == golden["syntheticGroups"])
    #expect(groups.count == 5)
  }

  @Test func codesAsQuartzControlChecksThem() throws {
    let golden = try #require(Self.golden)
    let two = [MultilanguageOptions.Language(code: "de"), MultilanguageOptions.Language(code: "en")]
    for item in golden["problems"]?.arrayValue ?? [] {
      let problem = MultilanguageOptions.codeProblem(item["code"]!.stringValue!, two, own: item["own"]?.stringValue)
      #expect(problem.map { JSONValue.string($0.rawValue) } ?? .null == item["problem"], "\(item)")
    }
    for item in golden["normalized"]?.arrayValue ?? [] {
      #expect(MultilanguageOptions.normalizeCode(item["code"]!.stringValue!) == item["result"]?.stringValue, "\(item)")
    }
  }
}
