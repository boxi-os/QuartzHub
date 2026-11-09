import Foundation
import Testing
@testable import QuartzHubCore

/// `FormsOptions` against QuartzControl's own code (`scripts/forms-options-golden.mjs`). The
/// schema is quartz-forms' own from gui-test.
@Suite struct FormsOptionsTests {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/forms-options")
  static let golden: JSONValue? = (try? Data(contentsOf: directory.appendingPathComponent("cases.json"))).flatMap { try? JSJSON.parse($0) }
  static let schema: NormalizedOptionSchema? = {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("schema.json")), let schema = try? JSJSON.parse(data) else { return nil }
    return OptionSchema.normalize(jsonSchema: schema, source: .configSchema)
  }()

  static func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap(\.stringValue) }
  static func c(_ value: JSONValue?) -> String { value.map(JSJSON.compact) ?? "-" }
  static func c(_ object: JSONObject) -> String { JSJSON.compact(.object(object)) }
  static func undefinedOr(_ value: JSONValue?) -> JSONValue { value ?? .string("__undefined") }

  @Test func constantsAreQuartzControls() throws {
    let k = try #require(Self.golden?["constants"])
    #expect(k["readAgainst"] == .string(FormsOptions.readAgainst))
    #expect(k["layoutSince"] == .string(FormsOptions.layoutSince))
    #expect(k["textsSince"] == .string(FormsOptions.textsSince))
    #expect(k["envelopeSenderSince"] == .string(FormsOptions.envelopeSenderSince))
    #expect(Self.strings(k["reserved"]) == FormsOptions.reservedNames)
    #expect(Self.strings(k["templateNames"]) == FormsOptions.templateNames)
    for name in FormsOptions.templateNames {
      #expect(Self.c(k["templates"]?[name]) == Self.c(FormsOptions.templates[name]!), "\(name)")
    }
    #expect(Self.strings(k["transportKinds"]) == FormsOptions.transportKinds)
    #expect(Self.strings(k["encryptionModes"]) == FormsOptions.encryptionModes)
    let sections = (k["sections"]?.arrayValue ?? []).map { ($0["id"]!.stringValue!, Self.strings($0["keys"])) }
    #expect(sections.map(\.0) == FormsOptions.sections.map(\.id))
    #expect(sections.map(\.1) == FormsOptions.sections.map(\.keys))
    let groups = try #require(k["fieldGroups"]?.objectValue)
    #expect(groups.keys == FormsOptions.fieldGroups.map(\.id))
    for (id, types) in FormsOptions.fieldGroups { #expect(Self.strings(groups[id]) == types, "\(id)") }
    #expect((k["sameShape"]?.arrayValue ?? []).map(Self.strings) == FormsOptions.sameShape)
    let input = try #require(k["inputKeys"]?.objectValue)
    #expect(Set(input.keys) == Set(FormsOptions.inputKeys.keys))
    for key in input.keys { #expect(Self.strings(input[key]) == FormsOptions.inputKeys[key], "\(key)") }
    #expect(Self.strings(k["personalAutocomplete"]) == FormsOptions.personalAutocomplete)
    #expect(Self.strings(k["controllerTypes"]) == FormsOptions.controllerTypes)
    #expect(Set(Self.strings(k["formKeys"])) == FormsOptions.formKeys)
    #expect(Set(Self.strings(k["relayOwnWords"])) == FormsOptions.relayOwnWords)
  }

  @Test func formsAsQuartzControlReadsAndWritesThem() throws {
    let golden = try #require(Self.golden)
    let sets = try #require(golden["forms"]?.arrayValue)
    #expect(sets.count == 8)
    for item in sets {
      let options = item["options"]?.objectValue
      let label = Self.c(item["options"])
      let forms = FormsOptions.forms(options)
      #expect(.array(forms.map { .array([.string($0.id), .object($0.def)]) }) == item["forms"], "\(label)")
      for (per, (id, def)) in zip(item["perForm"]?.arrayValue ?? [], forms) {
        #expect(per["id"] == .string(id))
        #expect(Self.c(per["effective"]) == Self.c(FormsOptions.effectiveForm(def)), "\(label) \(id)")
        #expect(per["usesTemplate"]?.boolValue == FormsOptions.usesTemplateFields(def), "\(label) \(id)")
        #expect(per["transport"]?.stringValue == FormsOptions.transportKind(def, options), "\(label) \(id)")
        #expect(per["encryption"]?.stringValue == FormsOptions.encryptionMode(def), "\(label) \(id)")
        #expect(per["anonymous"]?.boolValue == FormsOptions.isAnonymous(def), "\(label) \(id)")
        let embed = FormsOptions.embed(id, options)
        #expect(per["embed"]?["codeBlock"]?.stringValue == embed.codeBlock, "\(label) \(id)")
        #expect(per["embed"]?["placeholder"]?.stringValue == embed.placeholder, "\(label) \(id)")
        #expect(per["embed"]?["frontmatter"]?.stringValue == embed.frontmatter, "\(label) \(id)")
      }
      let base = options ?? JSONObject()
      for r in item["renamed"]?.arrayValue ?? [] {
        let result = FormsOptions.rename(base, from: r["id"]!.stringValue!, to: r["to"]!.stringValue!)
        #expect(Self.c(result) == Self.c(r["options"]), "\(label) rename \(r["id"]!)")
      }
      for r in item["removed"]?.arrayValue ?? [] {
        #expect(Self.c(FormsOptions.remove(base, id: r["id"]!.stringValue!)) == Self.c(r["options"]), "\(label) remove \(r["id"]!)")
      }
      for d in item["duplicated"]?.arrayValue ?? [] {
        let result = FormsOptions.duplicate(base, id: d["from"]!.stringValue!)
        #expect(Self.c(result.options) == Self.c(d["options"]), "\(label) duplicate \(d["from"]!)")
        #expect(.string(result.id) == d["id"]!, "\(label) duplicate \(d["from"]!)")
      }
      let firstId = forms.first?.id ?? "neu"
      let withForm = item["withForm"]?.arrayValue ?? []
      #expect(Self.c(FormsOptions.withForm(base, id: firstId, def: JSONObject([("title", .string("T"))]))) == Self.c(withForm.first), "\(label)")
      #expect(Self.c(FormsOptions.withForm(base, id: "0", def: JSONObject([("title", .string("Null"))]))) == Self.c(withForm.last), "\(label)")
      let spam = FormsOptions.resolvedGlobal(Self.schema, options, key: "spam")
      #expect(Self.c(spam) == Self.c(item["globals"]?["spam"]), "\(label)")
      #expect(Self.c(FormsOptions.resolvedGlobal(Self.schema, options, key: "transport")) == Self.c(item["globals"]?["transport"]), "\(label)")
      let needs = FormsOptions.captchaNeeds(options, globalSpam: spam)
      let theirs = item["captcha"]
      #expect(needs.global.map { JSONValue.object(JSONObject([("provider", .string($0))])) } ?? .null == theirs?["global"], "\(label)")
      #expect(.array(needs.forms.map { .object(JSONObject([("id", .string($0.id)), ("provider", .string($0.provider))])) }) == theirs?["forms"], "\(label)")
    }
  }

  @Test func namesAndTextsAsQuartzControlChecksThem() throws {
    let golden = try #require(Self.golden)
    for item in golden["texts"]?.arrayValue ?? [] {
      #expect(FormsOptions.text(item["text"], item["lang"]!.stringValue!) == item["result"]?.stringValue, "\(Self.c(item))")
    }
    for item in golden["ids"]?.arrayValue ?? [] {
      let problem = FormsOptions.formIdProblem(item["id"]!.stringValue!, existing: ["kontakt", "umfrage"], own: item["own"]?.stringValue)
      #expect(problem.map { JSONValue.string($0.rawValue) } ?? .null == item["problem"], "\(Self.c(item))")
    }
    for item in golden["names"]?.arrayValue ?? [] {
      let problem = FormsOptions.fieldNameProblem(item["name"]!.stringValue!, others: ["name", "email"])
      #expect(problem.map { JSONValue.string($0.rawValue) } ?? .null == item["problem"], "\(Self.c(item))")
    }
    for item in golden["freeIds"]?.arrayValue ?? [] {
      #expect(FormsOptions.freeId(item["base"]!.stringValue!, existing: ["kontakt", "kontakt-2", "umfrage", "form"]) == item["id"]?.stringValue, "\(Self.c(item))")
    }
    for item in golden["freeNames"]?.arrayValue ?? [] {
      #expect(FormsOptions.freeFieldName(item["base"]!.stringValue!, taken: ["name", "name2", "email"]) == item["name"]?.stringValue, "\(Self.c(item))")
    }
    for item in golden["newForms"]?.arrayValue ?? [] {
      #expect(Self.c(FormsOptions.newForm(item["start"]!.stringValue!, messageLabel: "Nachricht")) == Self.c(item["def"]), "\(Self.c(item))")
    }
    for item in golden["entryKeys"]?.arrayValue ?? [] {
      #expect(FormsOptions.entryKey(item["texts"]!.objectValue!, code: item["code"]!.stringValue!) == item["key"]?.stringValue, "\(Self.c(item))")
    }
  }

  @Test func keysAsQuartzControlTakesThemOut() throws {
    let golden = try #require(Self.golden)
    let keys = golden["keys"]?.arrayValue ?? []
    #expect(keys.count == 15)
    for item in keys {
      let options = item["options"]?.objectValue ?? JSONObject()
      let name = item["name"]!.stringValue!
      #expect(FormsOptions.formsUsingKey(options, name: name).map(JSONValue.string) == item["using"]?.arrayValue, "\(Self.c(item))")
      #expect(Self.c(FormsOptions.withoutKey(options, name: name)) == Self.c(item["without"]), "\(Self.c(item))")
    }
    for item in golden["keyNames"]?.arrayValue ?? [] {
      let problem = FormsOptions.keyNameProblem(item["name"]!.stringValue!, existing: ["taken"])
      #expect(problem.map { JSONValue.string($0.rawValue) } ?? .null == item["problem"], "\(Self.c(item))")
    }
  }

  @Test func theRelaysRulesAsQuartzControlHasThem() throws {
    let golden = try #require(Self.golden)
    for item in golden["recipientNames"]?.arrayValue ?? [] {
      #expect(FormsOptions.isRecipientName(item["name"]!.stringValue!) == item["ok"]?.boolValue, "\(Self.c(item))")
    }
    for item in golden["exampleAddresses"]?.arrayValue ?? [] {
      #expect(FormsOptions.isExampleAddress(item["address"]!.stringValue!) == item["example"]?.boolValue, "\(Self.c(item))")
    }
    for item in golden["originTexts"]?.arrayValue ?? [] {
      #expect(FormsOptions.origins(item["text"]!.stringValue!).map(JSONValue.string) == item["origins"]?.arrayValue, "\(Self.c(item))")
    }
    #expect((golden["recipientNames"]?.arrayValue?.count ?? 0) == 13)
  }

  @Test func fieldsAndConditionsAsQuartzControlReadsThem() throws {
    let golden = try #require(Self.golden)
    let items = try #require(golden["fields"]?.arrayValue)
    #expect(items.count == 22)
    var all: [JSONObject] = []
    for item in items {
      let field = try #require(item["field"]?.objectValue)
      all.append(field)
      let label = Self.c(field)
      #expect(item["personal"]?.boolValue == FormsOptions.isPersonalField(field), "\(label)")
      let showIf = FormsOptions.showIf(field).map { JSONValue.object(JSONObject([("field", .string($0.field)), ("equals", .array($0.equals.map(JSONValue.string)))])) }
      #expect(Self.undefinedOr(showIf) == item["showIf"], "\(label)")
      #expect(item["controller"]?.boolValue == FormsOptions.isController(field), "\(label)")
      let values: JSONValue = .array(FormsOptions.controllerValues(field, lang: "de").map {
        .object(JSONObject([("value", .string($0.value)), ("label", .string($0.label))]))
      })
      #expect(values == item["values"], "\(label)")
      #expect(Self.undefinedOr(FormsOptions.fieldLabel(field, lang: "de").map(JSONValue.string)) == item["label"], "\(label)")
      #expect(item["pageBreak"]?.boolValue == FormsOptions.isPageBreak(field), "\(label)")
    }
    let renamed = FormsOptions.renameInConditions(all, from: "s", to: "auswahl")
    #expect(.array(renamed.map(JSONValue.object)) == golden["renamedConditions"])
    #expect(FormsOptions.stepCount(all) == 2)
    let values = golden["showIfValues"]?.arrayValue ?? []
    #expect(Self.c(FormsOptions.showIfValue(field: "s", equals: ["a"])) == Self.c(values[0]))
    #expect(Self.c(FormsOptions.showIfValue(field: "s", equals: ["a", "b"])) == Self.c(values[1]))
    #expect(Self.c(FormsOptions.showIfValue(field: "s", equals: [])) == Self.c(values[2]))
  }

  @Test func messagesLandWhereQuartzControlPutsThem() throws {
    let golden = try #require(Self.golden)
    let messages = try #require(golden["messages"]?.arrayValue)
    #expect(messages.count == 30)
    for item in messages {
      let text = item["text"]!.stringValue!
      let placed = FormsOptions.place(text)
      let theirs = try #require(item["placed"])
      #expect(placed.form.map(JSONValue.string) ?? .string("__undefined") == (theirs["form"] ?? .string("__undefined")), "\(text)")
      #expect(placed.field.map { JSONValue.number(Double($0)) } ?? .string("__undefined") == (theirs["field"] ?? .string("__undefined")), "\(text)")
      #expect(placed.section.map(JSONValue.string) ?? .string("__undefined") == (theirs["section"] ?? .string("__undefined")), "\(text)")
      #expect(placed.rest == theirs["rest"]?.stringValue, "\(text)")
      #expect(FormsOptions.part(placed).rawValue == item["part"]?.stringValue, "\(text)")
    }
  }

  @Test func theSchemasPartsAsQuartzControlFindsThem() throws {
    let parts = try #require(Self.golden?["schemaParts"])
    let form = FormsOptions.formSchema(Self.schema)
    #expect(form.map { .array($0.fields.map { .string($0.key) }) } ?? .null == parts["formKeys"])
    for key in ["spam", "transport", "keys", "forms", "nothing"] {
      let mine = FormsOptions.objectSchema(Self.schema, key: key).map { JSONValue.array($0.fields.map { .string($0.key) }) } ?? .null
      #expect(mine == parts["objectKeys"]?[key], "\(key)")
    }
    let variants = try #require(parts["variants"]?.objectValue)
    for type in variants.keys {
      #expect(FormsOptions.fieldVariant(form, type: type).map(\.key) == Self.strings(variants[type]), "\(type)")
    }
    let defaults = try #require(parts["defaults"]?.objectValue)
    for key in defaults.keys {
      #expect(Self.c(Self.undefinedOr(FormsOptions.defaultOf(Self.schema, key: key))) == Self.c(defaults[key]), "\(key)")
    }
  }

  @Test func anAnonymousFormSendsNoPageContext() {
    let root = FormsOptions.root(translate: OptionFormTextTests.echo)
    let anonymous = JSONObject([("template", .string("survey"))])
    #expect(root.entryReason?("pageContext", anonymous, JSONObject()) == OptionFormTextTests.echo("formsEditor.pageContextAnonymous", nil))
    #expect(root.entryReason?("pageContext", JSONObject([("template", .string("contact"))]), JSONObject()) == nil)
    #expect(root.entryReason?("title", anonymous, JSONObject()) == nil)
  }
}
