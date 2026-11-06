import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own SFTP and rsync adapters on a real Linux host (`scripts/vm-golden.mjs`):
/// debian-vm with rsync 3.5.0 as the receiver, OpenSSH's sftp-server for qchost and internal-sftp
/// without setstat for qcsftp, logins as accounts other than the local user. Only with
/// `QH_VM_TESTS=1` and `QH_VM_KEY=<private key>` (comment qh-8b-test in both accounts), and never at
/// the same time as the golden script: both use the same folders on the host.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["QH_VM_TESTS"] == "1", "QH_VM_TESTS=1 und QH_VM_KEY setzen"))
struct DebianVMTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/vm/steps.json")))
  static let host = "debian.local"
  static let remote = ["qchost": "/srv/qc/www/qh8b", "qcsftp": "/srv/qc/www/nochmod/qh8b"]

  final class Events: Sendable {
    let items = Mutex<[JSONValue]>([])
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let key = try #require(ProcessInfo.processInfo.environment["QH_VM_KEY"])
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 13)
    let work = TemplatePackageTests.realpath(TestFolder.make("qh-vm"))
    defer { try? FileManager.default.removeItem(atPath: work) }
    let W = { (text: String) in
      text.replacingOccurrences(of: "@W@", with: work, options: .literal).replacingOccurrences(of: "@R@", with: Self.remote["qchost"]!, options: .literal)
        .replacingOccurrences(of: "@N@", with: Self.remote["qcsftp"]!, options: .literal)
    }
    let mask = { (text: String) in
      JSText.replaceAll(text.replacingOccurrences(of: work, with: "@W@", options: .literal).replacingOccurrences(of: Self.remote["qcsftp"]!, with: "@N@", options: .literal)
        .replacingOccurrences(of: Self.remote["qchost"]!, with: "@R@", options: .literal), #"rsync\(\d+\)"#, with: "rsync(PID)")
    }
    var environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "LANG": "de_DE.UTF-8"],
                                      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system,
                                      runtime: .repository, git: nil, bundledGitFailure: nil)
    environment.base["LANG"] = "de_DE.UTF-8"
    func ssh(_ user: String, _ command: String) async -> String {
      await ProcessRunner.run(environment.command("ssh", ["-F", "/dev/null", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
                                                          "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=\(work)/kh", "-i", key,
                                                          "\(user)@\(Self.host)", command])).stdout
    }
    let listing = #"for d in /srv/qc/www/qh8b /srv/qc/www/nochmod/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2"; do [ -e "$d" ] && find "$d" -printf "%y %m %p %l\n" | sort; done; for d in /srv/qc/www/qh8b /srv/qc/www/nochmod/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2"; do [ -e "$d" ] && find "$d" -type f -readable -exec sha256sum {} + | sort -k2; done; true"#

    _ = await ssh("qchost", #"rm -rf /srv/qc/www/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2"; mkdir -p /srv/qc/www/qh8b"#)
    // qcsftp has no shell (internal-sftp only): its folder is made, listed and removed by the admin account.
    func admin(_ command: String) async -> String {
      await ProcessRunner.run(Command("/usr/bin/ssh", ["-o", "BatchMode=yes", "debian-vm", command],
                                      environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()])).stdout
    }
    _ = await admin("sudo rm -rf /srv/qc/www/nochmod/qh8b; sudo -u qcsftp mkdir -p /srv/qc/www/nochmod/qh8b")
    let project = "\(work)/Gärten-Ü"
    try Posix.mkdirs("\(project)/.git")
    let hostKey = PinnedHostKey(Self.golden["hostKey"])!
    let profile = "\(work)/profile"
    try Posix.mkdirs(profile)
    let entries: [JSONValue] = ["qchost", "qcsftp"].map { user in
      .object(JSONObject([("id", .string(user)), ("kind", .string("ssh")), ("name", .string(user)), ("host", .string(Self.host)), ("port", .number(22)),
                          ("username", .string(user)), ("authMethod", .string("privateKey")), ("keyPath", .string(key)), ("hostKey", hostKey.json)]))
    }
    try JSONStore.write(.array(entries), to: "\(profile)/connections.json")
    let connections = Connections(profile: ProfileDirectory(profile), secrets: MemorySecrets())
    let sftp = SFTPAdapter(connections: connections, environment: environment, confirm: { _, _ in false }, configFile: "/dev/null")
    let rsync = RsyncAdapter(connections: connections, environment: environment, configFile: "/dev/null")

    for step in steps {
      let name = step["name"]!.stringValue!
      for action in step["setup"]!.arrayValue! {
        if let write = action["write"]?.arrayValue {
          let path = W(write[0].stringValue!)
          try Posix.mkdirs(NodePath.dirname(path))
          try Posix.write(path, Data(write[1].stringValue!.utf8))
        }
        if let change = action["chmod"]?.arrayValue { _ = chmod(W(change[0].stringValue!), mode_t(change[1].stringValue!, radix: 8)!) }
        if let dir = action["mkdir"]?.stringValue { try Posix.mkdirs(W(dir)) }
      }
      for command in step["remote"]!.arrayValue! { _ = await ssh(command.arrayValue![0].stringValue!, W(command.arrayValue![1].stringValue!)) }
      let options = step["options"]!
      let destination = try JSJSON.parse(Data(W(JSJSON.compact(step["destination"]!)).utf8)).objectValue!
      let target = PublishTarget(object: JSONObject([("id", .string(options["id"]?.stringValue ?? "t1")), ("name", .string("Web")),
                                                     ("connectionId", .string(step["user"]!.stringValue!)), ("destination", .object(destination)),
                                                     ("excludes", .array([]))]))
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
      let adapter: any DeployAdapter = step["adapter"] == .string("rsync") ? rsync : sftp
      let actual: JSONValue
      do {
        let result = try await adapter.run(context, excluding: [])
        actual = .object(JSONObject([("ok", .object(JSONObject([("success", .bool(result.success)), ("output", .string(mask(result.output)))])))]))
      } catch {
        actual = .object(JSONObject([("error", .string(mask(error.message)))]))
      }
      let want = JSJSON.compact(GoldenText.localize(step["result"]!))
      #expect(JSJSON.compact(actual) == want, "\(name): \(JSJSON.compact(actual))\nvs \(want)")
      let gotEvents = mask(JSJSON.compact(.array(events.items.withLock { $0 })))
      #expect(gotEvents == JSJSON.compact(GoldenText.localize(step["events"]!)), "\(name): events \(gotEvents)")
      let state = mask(await ssh("qchost", listing) + (await admin(#"sudo find /srv/qc/www/nochmod/qh8b -printf "%y %m %u %p\n" 2>/dev/null | sort; true"#)))
      #expect(state == step["state"]!.stringValue!, "\(name): state\n\(state)\nvs\n\(step["state"]!.stringValue!)")
    }
    _ = await ssh("qchost", #"chmod -R u+w /srv/qc/www/qh8b 2>/dev/null; rm -rf /srv/qc/www/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2""#)
    _ = await admin("sudo rm -rf /srv/qc/www/nochmod/qh8b")
  }

  /// A server that goes silent: the session's processes stopped on the host, and the request ends
  /// with QuartzControl's sentence 45 to 60 s after the last answer (four unanswered keepalives; it
  /// measured 50 to 62 s with ssh2 after a SIGSTOP on this host).
  @Test func aSilentServerEndsAfterAMinute() async throws {
    let key = try #require(ProcessInfo.processInfo.environment["QH_VM_KEY"])
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"],
                                      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system,
                                      runtime: .repository, git: nil, bundledGitFailure: nil)
    let hostKey = PinnedHostKey(Self.golden["hostKey"])!
    let connection = Connection(stored: StoredConnection(object: JSONObject([
      ("id", .string("qchost")), ("kind", .string("ssh")), ("host", .string(Self.host)), ("port", .number(22)), ("username", .string("qchost")),
      ("authMethod", .string("privateKey")), ("keyPath", .string(key)), ("hostKey", hostKey.json)
    ])))
    let login = try SSHLogin.prepare(connection, secret: nil, hostKey: hostKey, environment: [:], configFile: "/dev/null")
    defer { login.cleanup() }
    let channel = try await SFTPChannel.open(login, environment: environment)
    #expect(try await channel.realpath(".") == "/home/qchost")
    // As the admin account, by process name: `pkill -f` over ssh would match its own command line.
    let control = { (command: String) async in
      _ = await ProcessRunner.run(Command("/usr/bin/ssh", ["-o", "BatchMode=yes", "debian-vm", command], environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]))
    }
    await control("sudo pkill -STOP -u qchost sshd-session")
    let clock = ContinuousClock()
    let start = clock.now
    var said = ""
    do {
      _ = try await channel.lstat("/home/qchost")
      Issue.record("a stopped server answered")
    } catch let failure as SFTPChannel.Failure {
      said = SSHFailure.translate(failure.description, connection: connection, sftp: true) ?? failure.description
    }
    let waited = clock.now - start
    await control("sudo pkill -CONT -u qchost sshd-session")
    await channel.close()
    #expect(waited > .seconds(40) && waited < .seconds(75), "\(waited)")
    #expect(said.hasPrefix(L10n.t("main.sshSilent", ["host": Self.host, "seconds": "60"])), "\(said)")
  }
}
