import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own deploy/rsync.ts (`scripts/rsync-golden.mjs`). The same 22
/// runs, here over the system's ssh and QuartzHub's SFTP client against the system's sshd
/// (`LocalSSHD`), each with its answer, the progress events and afterwards every folder and file on
/// the server with its mode, links as their target, and the project's .quartz-gui/.
@Suite(.serialized) struct RsyncAdapterTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/rsync/steps.json")))

  final class Events: Sendable {
    let items = Mutex<[JSONValue]>([])
  }

  static func tree(home: String, project: String, mask: (String) -> String) -> [String: String] {
    var found: [String: String] = [:]
    func walk(_ dir: String, _ rel: String) {
      for entry in Posix.entries(dir) ?? [] {
        let full = "\(dir)/\(entry.name)", r = "\(rel)/\(entry.name)"
        var info = stat()
        lstat(full, &info)
        let mode = String(info.st_mode & 0o7777, radix: 8)
        if info.st_mode & S_IFMT == S_IFLNK {
          found[r] = "link \(mask((try? Posix.readlink(full)) ?? ""))"
        } else if info.st_mode & S_IFMT == S_IFDIR {
          found["\(r)/"] = mode
          if info.st_mode & 0o500 != 0 { walk(full, r) }
        } else {
          found[r] = "\(mode) \(String(decoding: (try? Posix.read(full)) ?? Data(), as: UTF8.self))"
        }
      }
    }
    walk(home, "H")
    if Posix.exists("\(project)/.quartz-gui") { walk("\(project)/.quartz-gui", "gui") }
    return found
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 22)
    let sshd = try await LocalSSHD()
    let work = sshd.root, home = sshd.home
    let W = { (text: String) in text.replacingOccurrences(of: "@W@", with: work, options: .literal).replacingOccurrences(of: "@H@", with: home, options: .literal) }
    let mask = { (text: String) in
      JSText.replaceAll(text.replacingOccurrences(of: home, with: "@H@", options: .literal).replacingOccurrences(of: work, with: "@W@", options: .literal),
                        #"rsync\(\d+\)"#, with: "rsync(PID)").replacingOccurrences(of: sshd.hostKey.fingerprint, with: "@FP@", options: .literal)
    }
    let project = "\(work)/Gärten-Ü"
    try Posix.mkdirs("\(project)/.git")
    defer { _ = chmod("\(home)/site", 0o755); _ = chmod("\(home)/web/forms", 0o755) }

    let profile = "\(work)/profile"
    try Posix.mkdirs(profile)
    let stored = JSONObject([("id", .string("c1")), ("kind", .string("ssh")), ("name", .string("lokal")), ("host", .string("127.0.0.1")),
                             ("port", .number(Double(sshd.port))), ("username", .string(sshd.user)), ("authMethod", .string("privateKey")),
                             ("keyPath", .string(sshd.clientKey)), ("hostKey", sshd.hostKey.json)])
    let connections = Connections(profile: ProfileDirectory(profile), secrets: MemorySecrets())
    // A session's locale, as the app has one: rsync must not take it for its names.
    var environment = sshd.environment
    environment.base["LANG"] = "de_DE.UTF-8"
    let adapter = RsyncAdapter(connections: connections, environment: environment, configFile: "/dev/null")

    for step in steps {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! {
        if let write = action["write"]?.arrayValue {
          let path = W(write[0].stringValue!)
          try Posix.mkdirs(NodePath.dirname(path))
          try Posix.write(path, Data(write[1].stringValue!.utf8))
        }
        if let dir = action["mkdir"]?.stringValue { try Posix.mkdirs(W(dir)) }
        if let rm = action["rm"]?.stringValue { try? FileManager.default.removeItem(atPath: W(rm)) }
        if let change = action["chmod"]?.arrayValue { _ = chmod(W(change[0].stringValue!), mode_t(change[1].stringValue!, radix: 8)!) }
        if let link = action["symlink"]?.arrayValue { try Posix.symlink(W(link[0].stringValue!), W(link[1].stringValue!)) }
        if let key = action["keygen"]?.stringValue, !Posix.exists(W(key)) {
          try await LocalSSHD.shell("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "stranger", "-f", W(key)])
        }
      }
      // The connection of this step: QuartzControl's with the step's fields over it.
      var merged = stored
      for (key, value) in (step["options"]!["connection"]?.objectValue).map({ o in o.keys.map { ($0, o[$0]!) } }) ?? [] {
        merged[key] = (try? JSJSON.parse(Data(W(JSJSON.compact(value)).utf8))) ?? value
      }
      try JSONStore.write(.array([.object(merged)]), to: "\(profile)/connections.json")
      let options = step["options"]!
      let destination = try JSJSON.parse(Data(W(JSJSON.compact(step["destination"]!)).utf8)).objectValue!
      let target = PublishTarget(object: JSONObject([("id", .string(options["id"]?.stringValue ?? "t1")), ("name", .string("Web")),
                                                     ("connectionId", .string("c1")), ("destination", .object(destination)), ("excludes", .array([]))]))
      var context = DeployContext(project: project, target: target, buildDir: W(options["build"]?.stringValue ?? "@W@/build"))
      context.keepLocalModes = options["keepLocalModes"] == .bool(true)
      context.relayFolders = options["relayFolders"]?.arrayValue?.map { W($0.stringValue!) }
      context.onlyPaths = options["onlyPaths"]?.arrayValue?.map { $0.stringValue! }
      context.ownGeneration = options["ownGeneration"]?.stringValue
      let events = Events()
      context.progress = { processed, total, file in
        events.items.withLock {
          $0.append(.object(JSONObject([("processed", .number(Double(processed))), ("total", .number(Double(total))),
                                        ("currentFile", file.map(JSONValue.string) ?? .null)])))
        }
      }
      let actual: JSONValue
      do {
        if step["call"] == .string("preview") {
          actual = .object(JSONObject([("ok", .array(try await adapter.preview(context).map(\.json)))]))
        } else {
          let result = try await adapter.run(context, excluding: options["excludes"]?.arrayValue?.map { $0.stringValue! } ?? [])
          actual = .object(JSONObject([("ok", .object(JSONObject([("success", .bool(result.success)), ("output", .string(mask(result.output)))])))]))
        }
      } catch {
        actual = .object(JSONObject([("error", .string(mask(error.message)))]))
      }
      let want = JSJSON.compact(GoldenText.localize(step["result"]!))
      // stdout and stderr arrive in either order; where rsync complains, the lines are compared as a set.
      let lines = { (value: JSONValue) in JSText.split(mask(value["ok"]?["output"]?.stringValue ?? ""), "\n").sorted() }
      let wantValue = GoldenText.localize(step["result"]!)
      let interleaved = JSText.includes(want, "rsync(PID): error") && wantValue["ok"]?["success"] == actual["ok"]?["success"]
        && lines(actual) == lines(wantValue)
      #expect(interleaved || mask(JSJSON.compact(actual)) == want, "\(name): \(mask(JSJSON.compact(actual)))\nvs \(want)")
      // The one-time pass reports each file as its answer comes, eight at a time, in QuartzControl
      // too: the counts in order, the names as a set.
      let wantList = GoldenText.localize(step["events"]!).arrayValue!
      let gotList = events.items.withLock { $0 }
      let counts = { (list: [JSONValue]) in list.map { "\(JSJSON.compact($0["processed"]!))/\(JSJSON.compact($0["total"]!))" } }
      let files = { (list: [JSONValue]) in list.map { mask(JSJSON.compact($0["currentFile"] ?? .null)) }.sorted() }
      #expect(counts(gotList) == counts(wantList) && files(gotList) == files(wantList),
              "\(name): events \(JSJSON.compact(.array(gotList)))\nvs \(JSJSON.compact(.array(wantList)))")

      let have = Self.tree(home: home, project: project, mask: mask)
      let wantTree = step["tree"]!.objectValue!
      #expect(Set(have.keys) == Set(wantTree.keys), "\(name): extra \(Set(have.keys).subtracting(wantTree.keys).sorted()), missing \(Set(wantTree.keys).subtracting(have.keys).sorted())")
      for key in wantTree.keys {
        guard let got = have[key] else { continue }
        let expected = GoldenText.localize(wantTree[key]!.stringValue!)
        if JSText.test(key, #"\.(modes|tilde)\.json\z"#) {
          // A marker with the clock's time: the mode is what counts.
          let mode = { (text: String) in (try? JSJSON.parse(Data(String(text.drop { $0 != " " }.dropFirst()).utf8)))?["mode"] }
          #expect(mode(got) == mode(expected), "\(name): \(key)")
        } else if JSText.test(key, #"\Agui/deploy-manifest-[^/]*\.json\z"#) {
          #expect(DeployTests.manifestEntries(got) == DeployTests.manifestEntries(expected), "\(name): \(key)\n\(got)")
        } else {
          #expect(Array(got.utf8) == Array(expected.utf8), "\(name): \(key)\n\(got)\nvs\n\(expected)")
        }
      }
    }
  }
}
