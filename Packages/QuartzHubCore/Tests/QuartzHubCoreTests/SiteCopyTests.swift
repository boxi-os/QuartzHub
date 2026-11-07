import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own export/siteServer.ts (`scripts/site-copy-golden.mjs`): the copy of a
/// build with four links left out, 50 URL paths resolved and answered (status, type, body), the
/// documents under `/__quartzcontrol/`, and the sweep of old copies (an hour, folders, a link). The
/// copies are QuartzHub's own (`quartzhub-export-`); the sweep is measured with that prefix in
/// place of QuartzControl's.
@Suite struct SiteCopyTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/site-copy/golden.json")))

  static func tree(_ root: String) -> JSONObject {
    var found = JSONObject()
    func walk(_ dir: String, _ rel: String) {
      for entry in (Posix.entries(dir) ?? []).sorted(by: { Array($0.name.utf16).lexicographicallyPrecedes(Array($1.name.utf16)) }) {
        let full = "\(dir)/\(entry.name)", r = rel.isEmpty ? entry.name : "\(rel)/\(entry.name)"
        var info = stat()
        lstat(full, &info)
        switch info.st_mode & S_IFMT {
        case S_IFLNK: found[r] = .object(JSONObject([("link", .string((try? Posix.readlink(full)) ?? ""))]))
        case S_IFDIR:
          found[r] = .object(JSONObject([("folder", .bool(true))]))
          walk(full, r)
        default: found[r] = .string(String(decoding: (try? Posix.read(full)) ?? Data(), as: UTF8.self))
        }
      }
    }
    walk(root, "")
    return found
  }

  /// The build of the golden with its links, and the folder the copy goes to.
  static func buildFixture(_ work: String) throws -> (build: String, temp: String) {
    let build = "\(work)/public", temp = "\(work)/tmp"
    try Posix.mkdirs(temp)
    let files = Self.golden["files"]!.objectValue!
    for path in files.keys {
      try Posix.mkdirs(NodePath.dirname("\(build)/\(path)"))
      try Posix.write("\(build)/\(path)", Data(files[path]!.stringValue!.utf8))
    }
    try Posix.write("\(work)/geheim.txt", Data("geheim".utf8))
    try Posix.write("\(temp)/neben-der-kopie.txt", Data("neben".utf8))
    try Posix.mkdirs("\(work)/draussen")
    try Posix.write("\(work)/draussen/x.html", Data("draussen".utf8))
    let links = Self.golden["links"]!.objectValue!
    for path in links.keys { try Posix.symlink(links[path]!.stringValue!.replacingOccurrences(of: "@W@", with: work), "\(build)/\(path)") }
    return (build, temp)
  }

  @Test func copiesResolvesAndAnswersAsQuartzControl() throws {
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-site-copy"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let (build, temp) = try Self.buildFixture(work)
    let site = try SiteCopy.make(from: build, tempRoot: temp)
    #expect(JSText.startsWith(NodePath.basename(site.root), SiteCopy.tempPrefix) && NodePath.dirname(site.root) == temp)
    #expect(JSJSON.compact(.object(Self.tree(site.root))) == JSJSON.compact(Self.golden["copy"]!))
    let own = [site.setDocument("epub.html", "<p>eigen</p>"), site.setDocument("drawing.html", "zeichnen"), site.setDocument("a b.html", "leer")]
    #expect(.array(own.map(JSONValue.string)) == Self.golden["own"]!)
    #expect(Self.golden["ownPrefix"] == .string(SiteCopy.ownPrefix))
    let types = Self.golden["types"]!.objectValue!
    #expect(Set(types.keys) == Set(SiteCopy.types.keys) && types.keys.allSatisfy { types[$0]!.stringValue! == SiteCopy.types[$0]! })

    let resolved = Self.golden["resolved"]!.arrayValue!, answers = Self.golden["answers"]!.arrayValue!
    #expect(resolved.count == 50)
    for (r, a) in zip(resolved, answers) {
      let path = r["path"]!.stringValue!
      let file = SiteCopy.resolveFile(site.root, path).map { JSText.slice($0, JSText.length(site.root)) }
      #expect(file.map(JSONValue.string) ?? .null == r["file"]!, "resolve \(path)")
      // What reaches the server: escaped as fetch escapes it, without query and fragment.
      let pathname = WebURL("http://127.0.0.1" + path.replacingOccurrences(of: " ", with: "%20")).parts!.pathname
      let answer = site.answer(pathname: pathname)
      #expect(Double(answer.status) == a["status"]!.numberValue! && (answer.type.map(JSONValue.string) ?? .null) == a["type"]!, "answer \(path): \(answer.status)")
      #expect(JSText.slice(String(decoding: answer.body, as: UTF8.self), 0, 40) == a["body"]!.stringValue!, "body \(path)")
    }
    site.close()
    #expect(!Posix.exists(site.root))
  }

  @Test func sweepsAsQuartzControl() throws {
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-site-sweep"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let temp = "\(work)/tmp"
    try Posix.mkdirs("\(work)/draussen")
    try Posix.mkdirs(temp)
    try Posix.write("\(temp)/neben-der-kopie.txt", Data("neben".utf8))
    let qc = Self.golden["tempPrefix"]!.stringValue!
    let mine = { (name: String) in JSText.startsWith(name, qc) ? SiteCopy.tempPrefix + JSText.slice(name, JSText.length(qc)) : name }
    // Whole seconds, so "exactly an hour" is exactly an hour.
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 2 * 3600)
    func make(_ name: String, minutes: Double, folder: Bool = true) throws {
      let path = "\(temp)/\(mine(name))"
      if folder {
        try Posix.mkdirs(path)
        try Posix.write("\(path)/index.html", Data("x".utf8))
      } else {
        try Posix.write(path, Data("x".utf8))
      }
      let t = now.addingTimeInterval(-minutes * 60).timeIntervalSince1970
      var times = [timeval(tv_sec: Int(t), tv_usec: Int32((t - floor(t)) * 1e6)), timeval(tv_sec: Int(t), tv_usec: Int32((t - floor(t)) * 1e6))]
      utimes(path, &times)
    }
    try make("\(qc)alt", minutes: 61)
    try make("\(qc)genau", minutes: 60)
    try make("\(qc)knapp", minutes: 59)
    try make("\(qc)neu", minutes: 1)
    try make("\(qc)datei", minutes: 120, folder: false)
    try make("quartzcontrol-anders-alt", minutes: 120)
    try make("qh-relay-alt", minutes: 120)
    try Posix.symlink("\(work)/draussen", "\(temp)/\(mine("\(qc)link"))")
    let swept = SiteCopy.sweep(now: now, tempRoot: temp).map { NodePath.basename($0) }.sorted()
    #expect(swept == Self.golden["swept"]!.arrayValue!.map { mine($0.stringValue!) }.sorted())
    #expect(Set((Posix.entries(temp) ?? []).map(\.name)) == Set(Self.golden["left"]!.arrayValue!.map { mine($0.stringValue!) }))
    #expect(Posix.exists("\(work)/draussen"))
  }
}
