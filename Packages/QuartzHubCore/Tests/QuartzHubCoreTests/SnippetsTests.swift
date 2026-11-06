import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own snippetService.ts and templatePackage/shared.ts:
/// `scripts/snippets-golden.mjs` laid out one project with snippet folders, pictures, links in and
/// out, reserved folders and the build output, and ran 74 calls on it.
@Suite struct SnippetsTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/snippets")

  @Test func asQuartzControl() throws {
    let golden = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("cases.json")))
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let work = try Snippets.realPath(scratch.path)
    let project = "\(work)/project"
    try Posix.mkdirs("\(project)/.quartz-gui")
    try Posix.write("\(project)/.quartz-gui/project-prefs.json", Data("{ \"outputDir\": \"\" }".utf8))
    let big = String(repeating: "x", count: Int(golden["bigLength"]!.numberValue!))
    let tree = golden["tree"]?.objectValue ?? JSONObject()
    for path in tree.keys {
      let file = NodePath.join(project, path)
      try Posix.mkdirs(NodePath.dirname(file))
      let spec = tree[path]!
      if let text = spec.stringValue { try Posix.write(file, Data(text.utf8)) }
      else if spec["length"] != nil { try Posix.write(file, Data((path.hasSuffix(".svg") ? "<svg>" + big + "</svg>" : big).utf8)) }
      else if let link = spec["link"]?.stringValue { try Posix.symlink(link, file) }
      else if spec["dir"] != nil { try Posix.mkdirs(file) }
    }
    let trashed = Mutex<[String]>([])
    let fails = Mutex(false)
    let snippets = Snippets(trash: { path in
      if fails.withLock({ $0 }) { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no trash here"]) }
      trashed.withLock { $0.append(path) }
      try FileManager.default.removeItem(atPath: path)
    })
    var before = Self.files(work)
    for step in golden["steps"]?.arrayValue ?? [] {
      let call = step["call"]!.stringValue!
      let raw = step["args"]?.arrayValue ?? []
      let args = raw.map { arg -> JSONValue in
        guard case .string(let text) = arg else { return arg }
        return .string(text.replacingOccurrences(of: "@OUT@", with: "\(work)/outside", options: .literal).replacingOccurrences(of: "@P@", with: project, options: .literal))
      }
      trashed.withLock { $0 = [] }
      var result: JSONValue
      do {
        result = try Self.run(call, args, snippets, project, fails)
      } catch {
        result = .object(JSONObject([("threw", .string(String(describing: error)))]))
      }
      let expected = FontServiceTests.rendered(step["result"] ?? .null)
      #expect(Array(JSJSON.compact(Self.masked(result, work)).utf8) == Array(JSJSON.compact(expected).utf8), "\(call) \(JSJSON.compact(.array(raw)))")
      #expect(JSONValue.array(trashed.withLock { $0 }.map { .string($0.replacingOccurrences(of: work, with: "@W@", options: .literal)) }) == step["trash"], "\(call) trash")
      let after = Self.files(work)
      var changed = JSONObject()
      for path in Set(before.keys).union(after.keys).sorted() where before[path] != after[path] { changed[path] = after[path] ?? .null }
      #expect(.object(changed) == step["changed"].map { value -> JSONValue in
        var sorted = JSONObject()
        let object = value.objectValue ?? JSONObject()
        for key in object.keys.sorted() { sorted[key] = object[key] }
        return .object(sorted)
      }, "\(call) \(JSJSON.compact(.array(raw))) changed")
      before = after
    }
    for entry in golden["paths"]?.arrayValue ?? [] {
      let dir = entry["dir"]!.stringValue!, name = entry["name"]!.stringValue!
      if let expected = entry["contained"] {
        #expect(PackagePaths.contained(dir, name).map { JSONValue.string($0) } ?? .null == expected, "contained \(dir) \(name)")
      } else {
        let got = PackagePaths.writable(project, name).map { JSONValue.string($0.replacingOccurrences(of: work, with: "@W@", options: .literal)) } ?? .null
        #expect(got == entry["writable"], "writable \(name)")
      }
    }
  }

  static func masked(_ value: JSONValue, _ work: String) -> JSONValue { StyleFilesTests.masked(value, work).replacing("@P@", with: "@W@") }

  static func written(_ result: Snippets.Written, _ key: String) -> JSONValue {
    switch result {
    case .written(let name): .object(JSONObject([("status", .string("written")), (key, .string(name))]))
    case .exists(let name): .object(JSONObject([("status", .string("exists")), (key, .string(name))]))
    }
  }

  static func listing(_ listing: Snippets.Listing) -> JSONValue {
    .object(JSONObject([("state", .string(listing.state.rawValue)), ("files", .array(listing.files.map { .string($0) }))]))
  }

  static func run(_ call: String, _ args: [JSONValue], _ snippets: Snippets, _ project: String, _ fails: borrowing Mutex<Bool>) throws -> JSONValue {
    let s = { (i: Int) in args[i].stringValue }
    switch call {
    case "listSnippets": return listing(try snippets.listSnippets(project: project, dir: s(0)!))
    case "listStaticImages": return listing(try snippets.listImages(project: project))
    case "readSnippet": return .string(try snippets.readSnippet(project: project, dir: s(0)!, file: s(1)!))
    case "writeSnippet": return written(try snippets.writeSnippet(project: project, dir: s(0)!, file: s(1)!, content: s(2)!, overwrite: args[3] == .bool(true)), "file")
    case "importSnippet": return written(try snippets.importSnippet(project: project, dir: s(0)!, source: s(1)!, name: s(2), overwrite: args[3] == .bool(true)), "file")
    case "importStaticImage": return written(try snippets.importImage(project: project, source: s(0)!, name: s(1), overwrite: args[2] == .bool(true)), "relativePath")
    case "readSvgSource": return .string(try Snippets.svgSource(s(0)!))
    case "renameStaticFile":
      return written(try snippets.rename(project: project, kind: Snippets.Kind(rawValue: s(0)!)!, dir: s(1), from: s(2)!, to: s(3)!), "file")
    case "trashStaticFile":
      try snippets.moveToTrash(project: project, kind: Snippets.Kind(rawValue: s(0)!)!, dir: s(1), file: s(2)!)
      return .null
    case "trashFails":
      fails.withLock { $0 = true }
      return .null
    default:
      Issue.record("unknown \(call)")
      return .null
    }
  }

  static func files(_ root: String) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    func walk(_ dir: String) {
      for entry in LayoutFrames.directoryEntriesWithKind(dir) {
        let full = NodePath.join(dir, entry.name)
        let relative = NodePath.relative(root, full)
        switch entry.kind {
        case .link: result[relative] = .object(JSONObject([("link", .string((try? Posix.readlink(full)) ?? ""))]))
        case .directory: walk(full)
        default:
          let data = FileManager.default.contents(atPath: full) ?? Data()
          let text = String(decoding: data, as: UTF8.self)
          result[relative] = text.utf16.count > 1000 ? .object(JSONObject([("length", .number(Double(data.count)))])) : .string(text)
        }
      }
    }
    walk(root)
    return result
  }
}

private extension JSONValue {
  func replacing(_ a: String, with b: String) -> JSONValue {
    switch self {
    case .string(let text): .string(text.replacingOccurrences(of: a, with: b, options: .literal))
    case .array(let items): .array(items.map { $0.replacing(a, with: b) })
    case .object(let object):
      { var out = JSONObject(); for key in object.keys { out[key] = object[key]!.replacing(a, with: b) }; return .object(out) }()
    default: self
    }
  }
}
