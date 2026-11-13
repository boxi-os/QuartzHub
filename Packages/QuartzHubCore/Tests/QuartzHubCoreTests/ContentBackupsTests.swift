import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own backupService.ts and contentService.ts (`changeContentSource`):
/// `scripts/content-golden.mjs` switched a project's content folder to a copy and to a link, moved
/// the old one aside each time, listed, restored and deleted what was moved, and was refused three
/// times; after each step the answer, the progress of the copy, the snapshots asked for and every
/// file of the work folder.
@Suite(.serialized) struct ContentBackupsTests {
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/content")

  static func listing(_ work: String) -> JSONValue {
    var files: [(String, JSONValue)] = []
    func walk(_ dir: String, _ rel: String) {
      for entry in Posix.entries(dir) ?? [] {
        let full = "\(dir)/\(entry.name)"
        let path = rel.isEmpty ? entry.name : "\(rel)/\(entry.name)"
        var info = stat()
        lstat(full, &info)
        switch info.st_mode & S_IFMT {
        case S_IFLNK: files.append((path, .string("link:\(((try? Posix.readlink(full)) ?? "").replacingOccurrences(of: work, with: "@W@", options: .literal))")))
        case S_IFDIR:
          files.append(("\(path)/", .string("dir \(String(info.st_mode & 0o777, radix: 8))")))
          walk(full, path)
        default:
          // As text with the folder masked: symlink.json names it.
          let text = String(decoding: (try? Posix.read(full)) ?? Data(), as: UTF8.self).replacingOccurrences(of: work, with: "@W@", options: .literal)
          files.append((path, .string("\(String(info.st_mode & 0o777, radix: 8)) \(SnapshotStoreTests.Harness.sha(Data(text.utf8)))")))
        }
      }
    }
    walk(work, "")
    return .object(JSONObject(files))
  }

  static func json(_ entry: ContentBackups.Entry) -> JSONValue {
    var fields: [(String, JSONValue)] = [("id", .string(entry.id)), ("createdAt", .string(entry.createdAt)), ("kind", .string(entry.kind.rawValue)),
                                         ("sizeBytes", .number(Double(entry.sizeBytes))), ("fileCount", .number(Double(entry.fileCount)))]
    if let target = entry.target { fields.append(("target", .string(target))) }
    return .object(JSONObject(fields))
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let golden = try JSJSON.parse(Data(contentsOf: Self.fixtures.appendingPathComponent("steps.json")))
    let steps = golden["steps"]!.arrayValue!
    #expect(steps.count == 23)
    let scratch = try HostPathTests.Scratch(umlaut: true)
    let work = TemplatePackageTests.realpath(scratch.path)
    let project = "\(work)/p"
    let content = "\(work)/p/content"
    var now = SnapshotStore.date("2026-11-06T10:00:00Z")!  // the golden's first instant
    let snapshots = Mutex<[[String]]>([])

    for step in steps {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! {
        let path = action["path"].map { "\(work)/\($0.stringValue!)" }
        switch action["do"]!.stringValue! {
        case "write": try SnapshotStoreTests.Harness.write(path!, action["text"]!.stringValue!)
        case "mkdir": try Posix.mkdirs(path!)
        case "remove": try? FileManager.default.removeItem(atPath: path!)
        case "symlink":
          try Posix.mkdirs((path! as NSString).deletingLastPathComponent)
          try Posix.symlink(action["target"]!.stringValue!.replacingOccurrences(of: "@W@", with: work, options: .literal), path!)
        case "clock": now = SnapshotStore.date(action["at"]!.stringValue!)!
        default: Issue.record("unknown action")
        }
      }
      snapshots.withLock { $0 = [] }
      var progress: [(Int, Int, String)] = []
      let args = step["args"]!.arrayValue!
      let arg = { (i: Int) in args[i].stringValue!.replacingOccurrences(of: "@W@", with: work, options: .literal) }
      var result: JSONValue = .null
      var failure: Error?
      do {
        switch step["op"]!.stringValue! {
        case "list": result = .array(ContentBackups.list(project: project).map(Self.json))
        case "change":
          try await ContentFolder.changeSource(
            project: project, source: arg(0), strategy: ContentFolder.SourceStrategy(rawValue: arg(1))!,
            snapshot: { p, kind, label in snapshots.withLock { $0.append([p.replacingOccurrences(of: work, with: "@W@", options: .literal), kind, label]) } },
            now: now, progress: { progress.append(($0, $1, $2.replacingOccurrences(of: work, with: "@W@", options: .literal))) })
        case "restore": try ContentBackups.restore(project: project, content: content, id: arg(0), now: now)
        case "delete": try ContentBackups.delete(project: project, id: arg(0))
        default: Issue.record("unknown op")
        }
      } catch {
        failure = error
      }

      if let expected = step["error"] {
        // Node's own errors by their code; the app's by their sentence; a JSON error only as one.
        if case .string(let code) = expected["code"] {
          #expect((failure as? NodeFileError).map { "\($0)".contains("Error: \(code):") } == true, "\(name): \(String(describing: failure))")
        } else if let message = expected["message"]?.stringValue, message.hasPrefix("{\"key\"") {
          #expect(failure.map { "\($0)" } == QC.render(message, mask: "@W@").replacingOccurrences(of: "@W@", with: work, options: .literal), "\(name): \(String(describing: failure))")
        } else {
          #expect(failure != nil, "\(name)")
        }
      } else {
        #expect(failure == nil, "\(name): \(String(describing: failure))")
        // A link's size is the length of its target, and an absolute one names the work folder,
        // which is longer or shorter here: per such link the difference comes off.
        let longer = work.utf8.count - Int(golden["workLength"]!.numberValue!)
        let adjusted: JSONValue = if case .array(let entries) = result, step["op"] == .string("list") {
          .array(entries.map { entry in
            let prefix = "p/.quartz-gui/content-backups/\(entry["id"]!.stringValue!)/content/"
            let links = step["files"]!.objectValue!.keys.filter { $0.hasPrefix(prefix) && step["files"]![$0]!.stringValue!.hasPrefix("link:@W@") }.count
            guard case .object(var object) = entry, let size = object["sizeBytes"]?.numberValue else { return entry }
            object["sizeBytes"] = .number(size - Double(links * longer))
            return .object(object)
          })
        } else { result }
        #expect(adjusted.masked(work) == step["result"], "\(name): \(JSJSON.compact(adjusted.masked(work)))")
      }
      // A deliberate deviation (review 2026-11-13, handbook, N13): QuartzControl reported every entry
      // the copy took, folders and hidden ones too, so its count ran past the total. QuartzHub
      // reports the files the total counts and stops at it: QuartzControl's list less the source
      // itself, folders and hidden entries, numbered 1…n up to the total.
      let expectedProgress = step["progress"]!
      let source = step["op"]!.stringValue! == "change" ? arg(0) : ""
      let counted = (expectedProgress["files"]?.arrayValue ?? []).compactMap(\.stringValue).filter { masked in
        let path = masked.replacingOccurrences(of: "@W@", with: work, options: .literal)
        guard path != source, path.hasPrefix(source + "/") else { return false }
        var info = stat()
        if stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR { return false }
        return !path.dropFirst(source.count + 1).split(separator: "/").contains { $0.hasPrefix(".") }
      }
      let total = Int(expectedProgress["totals"]?.arrayValue?.first?.numberValue ?? 0)
      #expect(progress.count == counted.count, "\(name): progress")
      #expect(progress.allSatisfy { $0.0 <= $0.1 }, "\(name): the count ran past the total")
      #expect(JSONValue.array(Array(Set(progress.map(\.1))).sorted().map { .number(Double($0)) }) == (progress.isEmpty ? .array([]) : expectedProgress["totals"]), "\(name): totals")
      #expect(progress.map(\.2).sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) } == counted, "\(name): files")
      #expect(progress.map(\.0) == Array((0..<counted.count).map { min($0 + 1, total) }), "\(name): numbers")
      #expect(JSONValue.array(snapshots.withLock { $0 }.map { .array($0.map(JSONValue.string)) }) == step["snapshots"], "\(name): snapshots")
      let files = Self.listing(work)
      // By bytes: Swift's == takes "Ü" and "U\u{308}" for one string, and the disk does not.
      #expect(Array(JSJSON.compact(files).utf8) == Array(JSJSON.compact(step["files"]!).utf8), "\(name): files\n\(JSJSON.compact(files))\n\(JSJSON.compact(step["files"]!))")
    }
  }
}

extension JSONValue {
  /// Every string with the work folder as "@W@".
  func masked(_ work: String) -> JSONValue {
    switch self {
    case .string(let text): .string(text.replacingOccurrences(of: work, with: "@W@", options: .literal))
    case .array(let items): .array(items.map { $0.masked(work) })
    case .object(let object): .object(JSONObject(object.keys.map { ($0, object[$0]!.masked(work)) }))
    default: self
    }
  }
}
