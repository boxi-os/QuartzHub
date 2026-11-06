import Darwin
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own serverDiscovery.ts: `scripts/server-discovery-golden.mjs` handed it
/// recorded process tables, lsof answers, open ports and pages, and wrote what discoverServers and
/// killServer answered. Here the same world goes in through `ServerScan.System`.
@Suite struct ServerScanTests {
  static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/server-discovery/scenarios.json")

  final class Log: Sendable {
    let entries = Mutex<[String]>([])
    func add(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
  }

  /// The world of a scenario, answered as the golden script's stand-ins answered.
  static func system(_ world: JSONValue, now: Date, log: Log) -> ServerScan.System {
    @Sendable func answer(_ spec: JSONValue?) -> CommandResult {
      guard let spec else { return CommandResult(termination: .exited(1), output: "", stdout: "") }
      if spec["enoent"] == .bool(true) { return CommandResult(termination: .couldNotStart(.notFound), output: "", stdout: "") }
      let stdout = spec["stdout"]?.stringValue ?? "", stderr = spec["stderr"]?.stringValue ?? ""
      let code = spec["code"]?.numberValue.map { Int32($0) } ?? 0
      return CommandResult(termination: .exited(code), output: stdout + stderr, stdout: stdout, stderr: stderr)
    }
    return ServerScan.System(
      run: { command in
        let name = (command.executable as NSString).lastPathComponent
        log.add(([name] + command.arguments).joined(separator: " "))
        if name == "ps" { return answer(world["ps"]) }
        let pid = command.arguments[command.arguments.firstIndex(of: "-p")! + 1]
        return answer(command.arguments.contains("cwd") ? world["cwd"]?[pid] : world["lsof"]?[pid])
      },
      probeTCP: { port in world["tcp"]?.arrayValue?.contains(.number(Double(port))) ?? false },
      fetchPage: { port in
        guard let page = world["http"]?[String(port)] else { return .unreachable }
        if page["timeout"] == .bool(true) { return .unreachable }
        if page["breaks"] == .bool(true) { return .brokenOff }
        return .body(page["body"]?.stringValue ?? "")
      },
      signalTree: { pid, _ in
        log.add("treeKill \(pid)")
        return !(world["killFails"]?.arrayValue?.contains(.number(Double(pid))) ?? false)
      },
      now: { now })
  }

  /// QuartzControl's JSON of a server: its keys in its order, absent ones left out.
  static func json(_ server: ServerScan.Server) -> JSONValue {
    var pairs: [(String, JSONValue)] = [("pid", .number(Double(server.pid))), ("listenerPid", .number(Double(server.listenerPid))),
                                        ("port", .number(Double(server.port)))]
    if let wsPort = server.wsPort { pairs.append(("wsPort", .number(Double(wsPort)))) }
    if let cwd = server.cwd { pairs.append(("cwd", .string(cwd))) }
    if let id = server.projectId { pairs.append(("projectId", .string(id))) }
    if let name = server.projectName { pairs.append(("projectName", .string(name))) }
    if let startedAt = server.startedAt { pairs.append(("startedAt", .string(JS.isoString(startedAt)))) }
    pairs.append(("ownedByApp", .bool(server.ownedByApp)))
    pairs.append(("reachable", .bool(server.reachable)))
    if let title = server.siteTitle { pairs.append(("siteTitle", .string(title))) }
    if let generator = server.quartzGenerator { pairs.append(("quartzGenerator", .bool(generator))) }
    return .object(JSONObject(pairs))
  }

  static func json(_ result: ServerScan.Result) -> JSONValue {
    var pairs: [(String, JSONValue)] = [("state", .string(result.state.rawValue))]
    if let reason = result.reason { pairs.append(("reason", .string(reason))) }
    pairs.append(("servers", .array(result.servers.map(json))))
    pairs.append(("occupiedPorts", .array(result.occupiedPorts.map { .number(Double($0)) })))
    return .object(JSONObject(pairs))
  }

  @Test func sameAsQuartzControl() async throws {
    let spec = try JSJSON.parse(Data(contentsOf: Self.fixture))
    let scenarios = try #require(spec["scenarios"]?.arrayValue)
    #expect(scenarios.count == 12, "scripts/server-discovery-golden.mjs")
    let now = try Date(spec["now"]!.stringValue!, strategy: .iso8601)
    for scenario in scenarios {
      let name = scenario["name"]!.stringValue!
      let world = scenario["world"]!
      let projects = (world["projects"]?.arrayValue ?? []).map { ProjectEntry(object: $0.objectValue!) }
      var owned: [Int32: String] = [:]
      for key in world["owned"]?.objectValue?.keys ?? [] { owned[Int32(key)!] = world["owned"]![key]!.stringValue! }
      let log = Log()
      let ports = scenario["ports"]!.arrayValue!.map { Int($0.numberValue!) }
      let result = await ServerScan.discover(ports: ports, projects: projects, owned: owned, system: Self.system(world, now: now, log: log))
      #expect(JSJSON.stringify(Self.json(result)) == JSJSON.stringify(scenario["expected"]!), "\(name)")
      #expect(Double(log.all.filter { $0.hasPrefix("lsof") }.count) == scenario["lsofAsked"]?.numberValue, "\(name): lsof calls")

      for kill in scenario["kills"]!.arrayValue! {
        let pid = Int32(kill["pid"]!.numberValue!)
        let actions = Log()
        let stopped = await ServerScan.stop(pid: pid, owned: owned, stopOwned: { actions.add("stopServer \($0)") },
                                            system: Self.system(world, now: now, log: actions))
        var expected: [(String, JSONValue)] = [("stopped", .bool(stopped.stopped))]
        if let id = stopped.projectId { expected.append(("projectId", .string(id))) }
        #expect(JSJSON.stringify(.object(JSONObject(expected))) == JSJSON.stringify(kill["expected"]!), "\(name) kill \(pid)")
        let theirs = kill["actions"]!.arrayValue!.map { $0.arrayValue!.prefix(2).map { $0.stringValue ?? String(Int($0.numberValue!)) }.joined(separator: " ") }
        #expect(actions.all.filter { $0.hasPrefix("treeKill") || $0.hasPrefix("stopServer") } == theirs, "\(name) kill \(pid)")
      }
    }
  }

  // MARK: beyond QuartzControl's answers

  @Test func aProjectRegisteredThroughALinkIsRecognised() async throws {
    let scratch = try HostPathTests.Scratch()
    let real = scratch.url.appendingPathComponent("Echt")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    let link = scratch.url.appendingPathComponent("Verknüpfung")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let world = try JSJSON.parse(#"{"ps":{"stdout":"5 1 00:01 node quartz build --serve --port 8501\n"},"cwd":{"5":{"stdout":"n\#(BuildOutputGuard.realPath(real.path))\n"}}}"#)
    let projects = [ProjectEntry(id: "p", path: link.path, addedAt: "t")]
    let result = await ServerScan.discover(projects: projects, owned: [:], system: Self.system(world, now: Date(), log: Log()))
    #expect(result.servers.first?.projectId == "p")
  }

  /// The real thing on this machine: a listening process that looks like a dev server is found
  /// with its port, folder and page, and stopping it ends it and what it started.
  @Test func aRealServerIsFoundAndStopped() async throws {
    let scratch = try HostPathTests.Scratch()
    let folder = scratch.url.appendingPathComponent("quartz site")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let port = 18_000 + Int(getpid() % 1000)
    // The shell carries both needles in its command line (ps shows the whole script, comment and
    // all), python serves the page, and a sleep stands for what a server starts.
    try "<html><head><title>Echt</title><meta name=\"generator\" content=\"Quartz\"></head></html>"
      .write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    let script = "sleep 60 & /usr/bin/python3 -m http.server \(port) --bind 127.0.0.1 --directory . # quartz --serve --port \(port)"
    let process = try ProcessRunner.launch(Command("/bin/sh", ["-c", script], in: folder)).get()
    defer { process.signal(SIGKILL) }
    var found: ServerScan.Server?
    for _ in 0..<50 where found?.reachable != true {
      try await Task.sleep(for: .milliseconds(100))
      found = await ServerScan.discover(ports: [port], projects: [], owned: [:]).servers.first { $0.port == port }
    }
    let server = try #require(found)
    #expect(server.pid == process.pid)
    #expect(server.cwd == BuildOutputGuard.realPath(folder.path))
    #expect(server.reachable && server.siteTitle == "Echt" && server.quartzGenerator == true)
    #expect(server.startedAt.map { abs($0.timeIntervalSinceNow) < 30 } == true)
    let rows = try #require(try? await ServerScan.processTable(.live).get())
    let sleeper = try #require(rows.first { $0.ppid == process.pid && $0.command.hasPrefix("sleep") }?.pid)
    #expect(await ServerScan.stop(pid: process.pid, owned: [:], stopOwned: { _ in }) == ServerScan.StopResult(stopped: true))
    #expect(await process.exit() == .signaled(SIGTERM))
    try await LaunchedProcessTests.waitFor { kill(sleeper, 0) != 0 }
    #expect(kill(sleeper, 0) != 0, "the child of the server survived")
  }

  @Test func aPortNobodyHoldsIsClosedAndAPortSomeoneHoldsIsOpen() async throws {
    // Closed once, by hand: a second close would hit whatever descriptor a parallel test has
    // been given that number since (it did: a pipe of ProcessRunner, which then read as cancelled).
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(fd, 1)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
    let port = Int(UInt16(bigEndian: address.sin_port))
    #expect(await LiveProbes.tcp(port))
    close(fd)
    #expect(!(await LiveProbes.tcp(port)))
    #expect(await LiveProbes.page(port) == .unreachable)
  }
}
