import Foundation
import Testing
@testable import QuartzHubCore

/// `OptionFormText`, `QuartzConfig.siteLanguages` and `PluginRepository` against QuartzControl's
/// own form code (`scripts/option-form-golden.mjs`). The fields are normalized here with
/// OptionSchema from the same JSON Schemas QuartzControl's normalizer read for the golden.
@Suite struct OptionFormTextTests {
  static let golden: JSONValue? = {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/option-form/cases.json")
    return (try? Data(contentsOf: file)).flatMap { try? JSJSON.parse($0) }
  }()

  /// The sentence as the golden's `t` wrote it: `{"key":…,"args":{…}}`.
  static let echo: OptionFormText.Translate = { key, args in
    var object = JSONObject([("key", .string(key))])
    if let args { object["args"] = .object(JSONObject(args.map { ($0.0, .string($0.1)) })) }
    return JSJSON.compact(.object(object))
  }

  /// Every field with its path and its siblings, depth first, as the golden walked them.
  static func walk(_ fields: [OptionField], _ path: [String] = [], _ visit: (OptionField, [String], [OptionField]) -> Void) {
    for field in fields {
      visit(field, path + [field.key], fields)
      func nested(_ node: OptionNode) {
        switch node {
        case .object(let inner, _): walk(inner, path + [field.key], visit)
        case .record(let value, _): nested(value)
        case .array(let items): nested(items)
        case .union(let variants): variants.forEach(nested)
        default: break
        }
      }
      nested(field.node)
    }
  }

  @Test func fieldTextsMatchesAndConditions() throws {
    let cases = try #require(Self.golden?["fields"]?.arrayValue)
    #expect(cases.count == 2)
    for item in cases {
      let schema = try #require(item["schema"])
      let id = item["id"]?.stringValue ?? ""
      let normalized = OptionSchema.normalize(jsonSchema: schema, source: .configSchema)
      var seen: [(OptionField, [String], [OptionField])] = []
      Self.walk(normalized.fields) { seen.append(($0, $1, $2)) }
      let expected = try #require(item["fields"]?.arrayValue)
      #expect(seen.count == expected.count, "\(id)")
      for ((field, path, siblings), want) in zip(seen, expected) {
        let at = "\(id) \(path.joined(separator: "."))"
        #expect(.array(path.map(JSONValue.string)) == want["path"], "\(at)")
        for language in [OptionFormText.Language.de, .en] {
          let text = OptionFormText.texts(field, language)
          let wantText = want["text"]?[language.rawValue]
          #expect(text.title == wantText?["title"]?.stringValue, "\(at) title \(language)")
          #expect(text.description == wantText?["description"]?.stringValue, "\(at) description \(language)")
          #expect(text.group == wantText?["group"]?.stringValue, "\(at) group \(language)")

          let values: [OptionEnumValue] = switch field.node {
          case .enumeration(let values): values
          case .union(let variants): variants.flatMap { node -> [OptionEnumValue] in
            switch node {
            case .enumeration(let values): values
            case .boolean: [.bool(true), .bool(false)]
            default: []
            }
          }
          default: []
          }
          let labels = values.map { JSONValue.string(OptionFormText.enumLabel(field, $0, language)) }
          #expect(.array(labels) == want["enumLabels"]?[language.rawValue], "\(at) labels \(language)")

          for (query, answers) in want["match"]?.objectValue.map({ object in object.keys.map { ($0, object[$0]!) } }) ?? [] {
            let got = OptionFormText.match(field, query: query, language)
            #expect(got.rawValue == answers[language.rawValue]?.stringValue, "\(at) match \(query) \(language)")
          }
        }
        #expect((OptionFormText.empty(of: field.node) ?? .null) == want["empty"], "\(at) empty")
        if case .object(let condition)? = want["condition"] {
          #expect(OptionFormText.conditionText(field, siblings: siblings, .de, translate: Self.echo) == condition["de"]?.stringValue, "\(at) condition de")
          #expect(OptionFormText.conditionText(field, siblings: siblings, .en, translate: Self.echo) == condition["en"]?.stringValue, "\(at) condition en")
          #expect(OptionFormText.conditionText(field, siblings: siblings, .de, keyPrefix: "switcher.", translate: Self.echo)
                  == condition["prefixed"]?.stringValue, "\(at) condition prefixed")
        } else {
          #expect(field.when == nil, "\(at) has a condition the golden did not")
        }
      }
      for language in [OptionFormText.Language.de, .en] {
        let groups = OptionFormText.groups(normalized.fields, language).map { group, fields in
          JSONValue.array([group.map(JSONValue.string) ?? .null, .array(fields.map { .string($0.key) })])
        }
        #expect(.array(groups) == item["groups"]?[language.rawValue], "\(id) groups \(language)")
      }
    }
  }

  @Test func inlineValues() throws {
    let cases = try #require(Self.golden?["inline"]?.arrayValue)
    #expect(cases.count == 19)
    for item in cases {
      let value = try #require(item["value"])
      #expect(OptionFormText.inline(value) == item["text"]?.stringValue, "\(JSJSON.compact(value))")
    }
  }

  @Test func typedValues() throws {
    let cases = try #require(Self.golden?["typed"]?.arrayValue)
    #expect(cases.count == 37)
    for item in cases {
      let raw = try #require(item["raw"]?.stringValue)
      let got = OptionFormText.typedValue(raw)
      if item["value"]?["nonFinite"] != nil {
        // The deviation: the text as typed, not a number JSON cannot carry.
        #expect(got == .string(raw), "\(raw)")
      } else {
        #expect(got == item["value"], "\(raw.debugDescription)")
      }
    }
  }

  @Test func siteLanguages() throws {
    let cases = try #require(Self.golden?["languages"]?.arrayValue)
    #expect(cases.count == 9)
    for item in cases {
      let config: QuartzConfig? = switch item["config"] {
      case .object(let object)?:
        QuartzConfig(configuration: object["configuration"]?.objectValue ?? JSONObject(),
                     plugins: (object["plugins"]?.arrayValue ?? []).compactMap { $0.objectValue.map(PluginEntry.init) })
      default: nil
      }
      let got = config?.siteLanguages ?? []
      #expect(.array(got.map(JSONValue.string)) == item["languages"], "\(item["id"]?.stringValue ?? "")")
    }
  }

  @Test func repositories() throws {
    let cases = try #require(Self.golden?["sources"]?.arrayValue)
    #expect(cases.count == 18)
    for item in cases {
      let source = item["source"]
      #expect((PluginRepository.id(source).map(JSONValue.string) ?? .null) == item["id"], "\(JSJSON.compact(source ?? .null))")
      #expect((PluginRepository.url(source).map(JSONValue.string) ?? .null) == item["url"], "\(JSJSON.compact(source ?? .null))")
    }
  }

  @Test func orderedKeepsTheSchemaOrderWhereNothingOrders() {
    let schema = OptionSchema.normalize(jsonSchema: try! JSJSON.parse(#"""
      {"type":"object","properties":{"c":{"type":"string"},"b":{"type":"string","x-quartz-order":2},
       "a":{"type":"string"},"d":{"type":"string","x-quartz-order":-1},"e":{"type":"string","x-quartz-order":2}}}
      """#), source: .configSchema)
    #expect(OptionFormText.ordered(schema.fields).map(\.key) == ["d", "b", "e", "c", "a"])
    let plain = OptionSchema.normalize(jsonSchema: try! JSJSON.parse(#"{"type":"object","properties":{"z":{"type":"string"},"a":{"type":"string"}}}"#),
                                       source: .configSchema)
    #expect(OptionFormText.ordered(plain.fields).map(\.key) == ["z", "a"])
  }
}
