import CryptoKit
import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own zipArchive.ts: `scripts/zip-golden.mjs` let `readZip` read 56
/// archives (built by hand with every edge, and from Python, Info-ZIP and ditto) and `createZip`
/// write six, and bundled the reader as `read-zip.cjs` for the other direction.
@Suite struct ZipArchiveTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/zip")
  static let cases = (try? JSJSON.parse(Data(contentsOf: fixtures.appendingPathComponent("cases.json")))) ?? .null

  /// What the golden's `describe` makes of an answer.
  static func describe(_ run: () throws -> ZipArchive.Files) -> JSONValue {
    do {
      let files = try run()
      return .object(JSONObject([("files", .array(files.names.map { name in
        let data = files[name]!
        var pairs: [(String, JSONValue)] = [("name", .string(name)), ("length", .number(Double(data.count))),
                                            ("sha256", .string(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))]
        if data.count <= 64 && !data.contains(0) { pairs.append(("text", .string(String(decoding: data, as: UTF8.self)))) }
        return .object(JSONObject(pairs))
      }))]))
    } catch {
      return .object(JSONObject([("threw", .string((error as? ZipArchive.Failure)?.message ?? String(describing: error)))]))
    }
  }

  static func expected(_ value: JSONValue) -> JSONValue {
    guard let threw = value["threw"]?.stringValue else { return value }
    return .object(JSONObject([("threw", .string(QC.render(threw, mask: "")))]))
  }

  @Test func readsAsQuartzControl() throws {
    let read = Self.cases["read"]?.arrayValue ?? []
    #expect(read.count >= 56)
    let damaged = [L10n.t("main.zipBadDirectory"), L10n.t("main.zipBadHeader")]
    for entry in read {
      let name = entry["name"]!.stringValue!
      let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("files").appendingPathComponent(entry["file"]!.stringValue!))
      let got = Self.describe { try ZipArchive.read(data) }
      let result = entry["result"]!
      if result["range"] == .bool(true) {
        // Node ran past the buffer and threw a RangeError; here it is a damaged archive.
        #expect(damaged.contains(got["threw"]?.stringValue ?? ""), "\(name): \(JSJSON.compact(got))")
      } else {
        #expect(JSJSON.compact(got) == JSJSON.compact(Self.expected(result)), "\(name)")
      }
    }
  }

  static func entries(_ spec: JSONValue) throws -> [ZipArchive.Entry] {
    let random = try Data(contentsOf: fixtures.appendingPathComponent("files/random.bin"))
    let samples: [String: Data] = [
      "text": Data(String(repeating: "Ein Absatz, der sich wiederholt. ", count: 40).utf8), "short": Data("abc".utf8), "empty": Data(),
      "random": random, "zeros": Data(count: 20000)
    ]
    return (spec.arrayValue ?? []).map { item in
      let fields = item.arrayValue!
      return ZipArchive.Entry(name: fields[0].stringValue!, data: samples[fields[1].stringValue!]!, store: fields.count > 2 && fields[2] == .bool(true))
    }
  }

  /// `new Date(y, m, d, h, mi, s)`: local time, the month from 0.
  static func date(_ when: JSONValue) -> Date {
    let n = (when.arrayValue ?? []).map { Int($0.numberValue!) }
    return Calendar.current.date(from: DateComponents(year: n[0], month: n[1] + 1, day: n[2], hour: n[3], minute: n[4], second: n[5]))!
  }

  /// The central directory's fixed fields of each entry, without the two the deflater decides
  /// (compressed size and, through it, every later local offset).
  static func directory(_ data: Data) -> [[Int]] {
    let b = [UInt8](data)
    func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
    let end = b.count - 22
    var cursor = u32(end + 16)
    var rows: [[Int]] = []
    for _ in 0..<u16(end + 10) {
      let nameLength = u16(cursor + 28)
      rows.append([u32(cursor), u16(cursor + 4), u16(cursor + 6), u16(cursor + 8), u16(cursor + 10), u16(cursor + 12), u16(cursor + 14),
                   u32(cursor + 16), u32(cursor + 24), nameLength, u16(cursor + 30), u16(cursor + 32), u32(cursor + 38)] + b[(cursor + 46)..<(cursor + 46 + nameLength)].map(Int.init))
      cursor += 46 + nameLength
    }
    return rows
  }

  @Test func writesAsQuartzControl() throws {
    let created = Self.cases["created"]?.arrayValue ?? []
    #expect(created.count == 6)
    for entry in created {
      let name = entry["name"]!.stringValue!
      let theirs = try Data(contentsOf: Self.fixtures.appendingPathComponent("files").appendingPathComponent(entry["file"]!.stringValue!))
      let ours = try ZipArchive.create(Self.entries(entry["entries"]!), modified: Self.date(entry["when"]!))
      #expect(Self.directory(ours) == Self.directory(theirs), "\(name): Verzeichnis")
      #expect(JSJSON.compact(Self.describe { try ZipArchive.read(ours) }) == JSJSON.compact(entry["read"]!), "\(name): gelesen")
      // Only deflate's own bytes may differ.
      if name != "deflated" { #expect(ours == theirs, "\(name): Bytes") }
    }
  }

  @Test func readsWhatQuartzControlWrote() throws {
    for entry in Self.cases["created"]?.arrayValue ?? [] {
      let theirs = try Data(contentsOf: Self.fixtures.appendingPathComponent("files").appendingPathComponent(entry["file"]!.stringValue!))
      #expect(JSJSON.compact(Self.describe { try ZipArchive.read(theirs) }) == JSJSON.compact(entry["read"]!), "\(entry["name"]!)")
    }
  }

  static func run(_ tool: String, _ arguments: [String], in directory: String? = nil) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    guard (try? process.run()) != nil else { return (-1, "\(tool) startet nicht") }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self))
  }

  /// QuartzHub's archives in four foreign readers: QuartzControl's own, Info-ZIP's `unzip -t`,
  /// Python's zipfile and ditto, with unicode names, an empty file and stored and deflated entries.
  @Test(.enabled(if: ToolEnvironmentTests.hasRuntime, "Runtime/ fehlt: scripts/fetch-runtime.sh"))
  func foreignReadersReadQuartzHubsArchives() throws {
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let deflated = Self.cases["created"]!.arrayValue!.first { $0["name"] == .string("deflated") }!
    var entries = try Self.entries(deflated["entries"]!)
    entries.append(ZipArchive.Entry(name: "files/content/Kapitel 1/Über uns.md", data: Data(String(repeating: "# Über uns\n\nText. ", count: 500).utf8)))
    entries.append(ZipArchive.Entry(name: "mimetype", data: Data("application/epub+zip".utf8), store: true))
    let archive = "\(scratch.path)/quartzhub.zip"
    try ZipArchive.write(entries, to: archive)
    let files = try ZipArchive.read(contentsOf: archive)
    let expected = Self.describe { files }
    #expect(entries.map(\.name) == files.names)
    for entry in entries { #expect(files[entry.name] == entry.data, "\(entry.name)") }

    let node = "\(RuntimeLocation.repository.nodeBin)/node"
    let quartzControl = Self.run(node, [Self.fixtures.appendingPathComponent("read-zip.cjs").path, archive])
    #expect(quartzControl.status == 0)
    #expect(quartzControl.output.trimmingCharacters(in: .whitespacesAndNewlines) == JSJSON.compact(expected), "QuartzControls readZip")

    let unzip = Self.run("/usr/bin/unzip", ["-t", archive])
    #expect(unzip.status == 0 && unzip.output.contains("No errors detected"), "unzip -t: \(unzip.output)")

    let python = Self.run("/usr/bin/env", ["python3", "-I", "-c", "import zipfile, sys; z = zipfile.ZipFile(sys.argv[1]); print(z.testzip()); print(len(z.namelist()))", archive])
    #expect(python.status == 0 && python.output == "None\n\(entries.count)\n", "zipfile: \(python.output)")

    let target = "\(scratch.path)/ditto"
    let ditto = Self.run("/usr/bin/ditto", ["-x", "-k", archive, target])
    #expect(ditto.status == 0, "ditto: \(ditto.output)")
    for entry in entries {
      #expect(FileManager.default.contents(atPath: "\(target)/\(entry.name)") == entry.data, "ditto: \(entry.name)")
    }
    // 0o644 from the external attributes, as QuartzControl writes them.
    let mode = try FileManager.default.attributesOfItem(atPath: "\(target)/mimetype")[.posixPermissions] as? Int
    #expect(mode == 0o644)
  }

  /// Deflate has to gain to be taken (`deflated.length < entry.data.length`): a tie is stored. The
  /// golden has no tie, because where one falls depends on the deflater; this finds one for
  /// Apple's: random bytes, then zeros until the deflated size meets the raw one.
  @Test func aTieIsStored() throws {
    var generator = SystemRandomNumberGenerator()
    let noise = (0..<200).map { _ in UInt8.random(in: 0...255, using: &generator) }
    var tie: [UInt8]?
    for zeros in 0..<400 {
      let data = noise + [UInt8](repeating: 0, count: zeros)
      if ZipArchive.deflateRaw(data).count == data.count { tie = data; break }
    }
    let data = try #require(tie, "kein Gleichstand gefunden")
    let zip = [UInt8](try ZipArchive.create([ZipArchive.Entry(name: "a", data: Data(data))]))
    #expect(zip[8] == 0 && zip[9] == 0, "Methode \(zip[8])")
  }

  @Test func aMissingFileIsSaidSo() {
    #expect(throws: ZipArchive.Failure(message: L10n.t("main.zipFileMissing"))) { try ZipArchive.read(contentsOf: "/nonexistent/x.qtpl") }
  }

  @Test func crc32IsZlibs() {
    #expect(ZipArchive.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
    #expect(ZipArchive.crc32([UInt8]()) == 0)
  }
}
