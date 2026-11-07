import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own shared/bookDefinition.ts and bookService.ts
/// (`scripts/books-golden.mjs`): the normaliser over 32 raw values, serializeBook, 51 ids from
/// titles, the id rule, the input rules against the zod schema over 43 books, and 37 steps in a
/// project folder with umlauts, each with its answer and every file under quartz-books/ afterwards.
/// A reason from V8's JSON.parse is compared as "a parse error", since QuartzHub's parser words its
/// own (docs/decisions/phase-3-dienste.md, 9a).
@Suite(.serialized) struct BooksTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/books/golden.json")))

  static func compact(_ value: JSONValue) -> String { JSJSON.compact(value) }

  /// The raw value with a generated order or excluded list built back.
  static func expand(_ raw: JSONValue) -> JSONValue {
    guard var object = raw.objectValue else { return raw }
    if let n = object["order"]?["generated"]?.numberValue {
      object["order"] = .array((0..<Int(n)).map { .object(JSONObject([("slug", .string("p\($0 % 10002)"))])) })
    }
    if let n = object["excluded"]?["generated"]?.numberValue {
      object["excluded"] = .array((0..<Int(n)).map { .string("e\($0)") })
    }
    return .object(object)
  }

  @Test func normalizesAsQuartzControl() {
    let cases = Self.golden["normalized"]!.arrayValue!
    #expect(cases.count == 32)
    for item in cases {
      let raw = item["raw"]!
      var actual = BookFile.normalize(id: "buch", Self.expand(raw))?.json ?? .null
      for key in ["order", "excluded"] where raw[key]?["generated"] != nil {
        let list = actual[key]!.arrayValue!
        var object = actual.objectValue!
        object[key] = .object(JSONObject([("length", .number(Double(list.count))), ("first", .array(Array(list.prefix(3)))), ("last", .array(Array(list.suffix(3))))]))
        actual = .object(object)
      }
      #expect(Self.compact(actual) == Self.compact(item["result"]!), "\(Self.compact(raw).prefix(200))")
    }
  }

  @Test func serializesAndNamesAsQuartzControl() {
    for item in Self.golden["serialized"]!.arrayValue! {
      #expect(Self.compact(.object(BookFile.serialize(item["book"]!.objectValue!))) == Self.compact(item["result"]!))
    }
    let ids = Self.golden["ids"]!.arrayValue!
    #expect(ids.count == 51)
    for item in ids {
      let title = item["title"]!.stringValue!
      let taken = Set(item["taken"]!.arrayValue!.map { $0.stringValue! })
      #expect(BookFile.id(fromTitle: title, taken: taken) == item["result"]!.stringValue!, "\(title) \(taken)")
    }
    for item in Self.golden["bookIdCases"]!.arrayValue! {
      #expect(BookFile.isID(item["id"]!.stringValue!) == item["valid"]!.boolValue!, "\(item["id"]!)")
    }
    #expect(Self.compact(.object(BookFile.empty(title: "Neu"))) == Self.compact(Self.golden["serialized"]!.arrayValue![2]["book"]!))
  }

  @Test func checksInputAsTheSchema() {
    let rules = Self.golden["rules"]!.arrayValue!
    #expect(rules.count == 43)
    for item in rules {
      var book = item["book"]!.objectValue!
      for key in ["order", "excluded"] {
        if let n = book[key]?["generated"]?.numberValue { book[key] = .array(Array(repeating: book[key]!["entry"]!, count: Int(n))) }
      }
      #expect((BookFile.problem(book) == nil) == item["valid"]!.boolValue!, "\(Self.compact(item["book"]!).prefix(160)): \(BookFile.problem(book) ?? "valid")")
    }
  }

  /// A reason V8's JSON.parse gave, which QuartzHub words itself.
  static func isParseReason(_ text: String) -> Bool {
    JSText.includes(text, "JSON") || JSText.startsWith(text, "Unexpected") || JSText.startsWith(text, "Expected")
  }

  /// The answer with every parse reason replaced, inside listings and sentences alike.
  static func normalizeReasons(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(var object):
      if let reason = object["reason"]?.stringValue, isParseReason(reason) { object["reason"] = .string("<parse>") }
      for key in object.keys { object[key] = normalizeReasons(object[key]!) }
      return .object(object)
    case .array(let items): return .array(items.map { normalizeReasons($0) })
    default: return value
    }
  }

  static func files(_ project: String, _ work: String) -> JSONObject {
    var found = JSONObject()
    func describe(_ full: String, _ rel: String) {
      var info = stat()
      guard lstat(full, &info) == 0 else { return }
      switch info.st_mode & S_IFMT {
      case S_IFLNK:
        found[rel] = .object(JSONObject([("link", .string((try? Posix.readlink(full))?.replacingOccurrences(of: work, with: "@W@") ?? ""))]))
      case S_IFDIR:
        guard let entries = Posix.entries(full) else {
          found[rel] = .object(JSONObject([("unreadableFolder", .bool(true))]))
          return
        }
        if entries.isEmpty { found[rel] = .object(JSONObject([("folder", .bool(true))])) }
        for name in entries.map(\.name).sorted() { describe("\(full)/\(name)", "\(rel)/\(name)") }
      default:
        let key = JSText.replaceAll(rel, #"\.tmp-\d+-[0-9a-f]{8}$"#, with: ".tmp-*")
        if let data = try? Posix.read(full) { found[key] = .string(String(decoding: data, as: UTF8.self)) } else {
          found[rel] = .object(JSONObject([("unreadableFile", .bool(true))]))
        }
      }
    }
    describe("\(project)/quartz-books", "quartz-books")
    return found
  }

  @Test func replaysQuartzControlsSteps() throws {
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 37)
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-books"))
    defer {
      chmod("\(work)/Gärten-Ü/quartz-books", 0o755)
      try? FileManager.default.removeItem(atPath: work)
    }
    let project = "\(work)/Gärten-Ü"
    try Posix.mkdirs(project)
    let books = Books(project: project)

    for step in steps {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! {
        func path(_ value: JSONValue) -> String { NodePath.join(project, value.stringValue!) }
        if let write = action["write"]?.arrayValue {
          try Posix.mkdirs(NodePath.dirname(path(write[0])))
          try Posix.write(path(write[0]), Data(write[1].stringValue!.utf8))
        }
        if let bytes = action["bytes"]?.arrayValue {
          try Posix.mkdirs(NodePath.dirname(path(bytes[0])))
          try Posix.write(path(bytes[0]), Data(base64Encoded: bytes[1].stringValue!)!)
        }
        if let dir = action["mkdir"] { try Posix.mkdirs(path(dir)) }
        if let rm = action["rm"] { try? FileManager.default.removeItem(atPath: path(rm)) }
        if let link = action["link"]?.arrayValue {
          try Posix.mkdirs(NodePath.dirname(path(link[1])))
          try Posix.symlink(link[0].stringValue!.replacingOccurrences(of: "@W@", with: work), path(link[1]))
        }
        if let mode = action["chmod"]?.arrayValue { chmod(path(mode[0]), mode_t(mode[1].numberValue!)) }
      }
      let args = step["args"]!.arrayValue!
      let expected = Self.normalizeReasons(GoldenText.localize(step["result"]!))
      var actual: JSONValue
      do {
        switch step["op"]!.stringValue! {
        case "list": actual = try books.list().json
        case "read": actual = try books.read(args[0].stringValue!)?.json ?? .null
        case "save": actual = try books.save(args[0].objectValue!).json
        case "delete":
          try books.delete(args[0].stringValue!)
          actual = .null
        default:
          Issue.record("unknown op"); continue
        }
        let masked = Self.compact(actual).replacingOccurrences(of: project, with: "@P@").replacingOccurrences(of: work, with: "@W@")
        actual = .object(JSONObject([("ok", try JSJSON.parse(masked))]))
      } catch {
        let message = PublishFailure.message(of: error).replacingOccurrences(of: project, with: "@P@").replacingOccurrences(of: work, with: "@W@")
        actual = .object(JSONObject([("error", .string(JSText.replaceAll(message, #"\.tmp-\d+-[0-9a-f]{8}"#, with: ".tmp-*")))]))
      }
      actual = Self.normalizeReasons(actual)
      #expect(Self.compact(Self.sentenceReasons(actual)) == Self.compact(Self.sentenceReasons(expected)), "\(name)")
      #expect(Self.compact(.object(Self.files(project, work))) == Self.compact(step["files"]!), "\(name): files")
    }
  }

  /// A parse reason inside the sentence "… konnte nicht gelesen werden (reason). …".
  static func sentenceReasons(_ value: JSONValue) -> JSONValue {
    guard let error = value["error"]?.stringValue,
          let open = JSText.indexOf(error, " ("), let close = JSText.indexOf(error, "). ", from: open),
          isParseReason(JSText.slice(error, open + 2, close)) else { return value }
    return .object(JSONObject([("error", .string(JSText.slice(error, 0, open) + " (<parse>" + JSText.slice(error, close)))]))
  }
}
