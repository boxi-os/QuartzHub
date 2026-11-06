import Darwin
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// The dev server against a stand-in for `npx quartz build --serve` (Fixtures/fake-quartz-server.py,
/// a Python process that answers HTTP and holds the websocket port), and once against the real
/// Quartz on a copy of gui-test (`QH_QUARTZ_TESTS=1`).
@Suite struct BuildServerTests {
  static let fake = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/fake-quartz-server.py")
  let scratch: HostPathTests.Scratch
  var project: URL { scratch.url.appendingPathComponent("Projekt") }
  var profile: ProfileDirectory { ProfileDirectory(scratch.url.appendingPathComponent("Profile")) }

  init() throws {
    scratch = try HostPathTests.Scratch()
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try "{}".write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
  }

  func environment(npx: Bool = true) throws -> ToolEnvironment {
    if npx { try scratch.script("bin/npx", "exec /usr/bin/python3 '\(Self.fake.path)' \"$@\"") }
    let hostPath = HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"], source: .inherited, added: [])
    return ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "QH_FAKE_DIR": scratch.url.path],
                           hostPath: hostPath, nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
  }

  func service(_ environment: ToolEnvironment, _ events: BuildServiceTests.Events = .init(), logs: LogBuffer = LogBuffer(),
               preparation: [BuildService.PreparationStep] = []) -> BuildService {
    BuildService(logs: logs, environment: { environment }, preparation: preparation, store: RunningServersStore(profile: profile),
                 stopGrace: .seconds(2), onEvent: events.add)
  }

  func mode(_ text: String) throws { try text.write(to: scratch.url.appendingPathComponent("mode"), atomically: true, encoding: .utf8) }
  var calls: [String] { ((try? String(contentsOf: scratch.url.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

  /// Two ports nobody holds right now.
  static func freePorts() -> (Int, Int) {
    func one() -> Int {
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      defer { close(fd) }
      var address = sockaddr_in()
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      address.sin_family = sa_family_t(AF_INET)
      address.sin_addr.s_addr = inet_addr("127.0.0.1")
      _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
      var length = socklen_t(MemoryLayout<sockaddr_in>.size)
      _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
      return Int(UInt16(bigEndian: address.sin_port))
    }
    var a = one(), b = one()
    while b == a || b == a + 1 { b = one() }
    while a + 1 == b { a = one() }
    return (a, b)
  }

  /// A listener on 127.0.0.1 alone, as a foreign server holds a port; closed by the caller.
  static func occupy(_ port: Int) -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port).bigEndian)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(fd, 4)
    return fd
  }

  static func until(_ seconds: Double = 8, _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline, !(await condition()) { try await Task.sleep(for: .milliseconds(30)) }
  }

  @Test func aServerStartsRunsAndStops() async throws {
    let events = BuildServiceTests.Events()
    let logs = LogBuffer()
    let servers = service(try environment(), events, logs: logs)
    let (port, wsPort) = Self.freePorts()
    let options = BuildService.ServerOptions(port: port, wsPort: wsPort)
    let started = await servers.startServer(projectId: "p", project: project, options: options)
    #expect(started.state == .starting && started.pid != nil)
    try await Self.until { await servers.serverStatus("p").state == .running }
    let status = await servers.serverStatus("p")
    #expect(status.state == .running && status.options == options)
    let pid = try #require(status.pid)
    #expect(await servers.ownedServerPids() == [pid: "p"])
    #expect(await servers.runningServerSummaries().map { "\($0.projectId) \($0.port)" } == ["p \(port)"])
    #expect(await LiveProbes.page(port) != .unreachable)
    #expect(RunningServersStore(profile: profile).peek()["p"]?.pid == pid)
    #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(".quartz-gui/logs/dev-server-\(pid).out.log").path))
    try await Self.until { logs.history("p").server.map(\.text).joined().contains("Started a Quartz server") }
    #expect(logs.history("p").server.map(\.text).joined().contains("Parsing input files"))
    #expect(calls == ["\(pid) quartz build --serve --port \(port) --wsPort \(wsPort) @ \(BuildOutputGuard.realPath(project.path))"])
    // The server's first build is its activity, and over once it runs.
    let kinds = events.activities.map { $0.map { "\($0.kind) \($0.phase)" } }
    #expect(kinds.first == "serve preparing" && kinds.last == .some(nil), "\(kinds)")
    #expect(await servers.activity("p") == nil)

    await servers.stopServer("p")
    #expect(await servers.serverStatus("p") == BuildService.ServerStatus(state: .stopped))
    #expect(kill(pid, 0) != 0, "the server outlived its stop")
    #expect(RunningServersStore(profile: profile).peek()["p"] == nil)
    let states = events.all.withLock { $0 }.compactMap { if case .status(_, let s) = $0 { s.state } else { nil } }
    #expect(states.first == .starting && states.suffix(2) == [.stopping, .stopped], "\(states)")
  }

  @Test func aTakenPortMovesAndTheConsoleSaysWhere() async throws {
    let logs = LogBuffer()
    let servers = service(try environment(), logs: logs)
    let (port, wsPort) = Self.freePorts()
    let holder = Self.occupy(port)
    defer { close(holder) }
    #expect(await ServerPorts.state(port) == .taken, "a listener on 127.0.0.1 alone is taken although the wildcard bind works")
    _ = await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    let moved = try #require(await servers.serverStatus("p").options)
    #expect(moved.port != port && moved.port > port && moved.port != wsPort)
    #expect(logs.history("p").server.map(\.text).contains(L10n.t("main.serverPortTaken", ["from": String(port), "to": String(moved.port)]) + "\n"))
    try await Self.until { await servers.serverStatus("p").state == .running }
    #expect(await servers.serverStatus("p").state == .running)

    // A second project asking for the same ports does not land on the first one's.
    let other = scratch.url.appendingPathComponent("Zweites")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    _ = await servers.startServer(projectId: "q", project: other, options: moved)
    let second = try #require(await servers.serverStatus("q").options)
    #expect(Set([second.port, second.wsPort]).isDisjoint(with: [moved.port, moved.wsPort]))
    await servers.stopServer("p")
    await servers.stopServer("q")
  }

  @Test func behindATunnelATakenPortIsRefused() async throws {
    let servers = service(try environment())
    let (port, wsPort) = Self.freePorts()
    let holder = Self.occupy(wsPort)
    defer { close(holder) }
    let status = await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort, host: "tunnel.example"))
    #expect(status.state == .error)
    #expect(status.error == L10n.t("main.serverPortTakenBehindTunnel", ["ports": String(wsPort), "host": "tunnel.example"]))
    #expect(calls.isEmpty)
  }

  @Test func missingPackagesAreAnErrorUntilTheyAreInstalled() async throws {
    try #"{"dependencies":{"left-pad":"1"}}"#.write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    let servers = service(try environment())
    let status = await servers.startServer(projectId: "p", project: project)
    #expect(status.state == .error && status.error == L10n.t("main.dependenciesMissing", ["names": "left-pad"]))
    #expect(calls.isEmpty)
    await servers.forgetDependencyErrors(project: project)
    #expect(await servers.serverStatus("p").state == .stopped)
  }

  @Test func aServerOfThisProjectStartedElsewhereIsRefused() async throws {
    let (port, wsPort) = Self.freePorts()
    var outside = Command("/usr/bin/python3", [Self.fake.path, "quartz", "build", "--serve", "--port", String(port), "--wsPort", String(wsPort)],
                          in: project)
    outside.environment["QH_FAKE_DIR"] = scratch.url.path
    let stranger = try ProcessRunner.launch(outside).get()
    defer { stranger.signal(SIGKILL) }
    try await Self.until { await ServerPorts.state(port) == .taken }
    let (mine, myWs) = Self.freePorts()
    let status = await service(try environment()).startServer(projectId: "p", project: project, options: .init(port: mine, wsPort: myWs))
    #expect(status.state == .error)
    #expect(status.error == L10n.t("main.serverAlreadyRunningOutside", ["port": String(port), "pid": String(stranger.pid)]))
  }

  @Test func aBuildAndTheServerTakeTurnsOnPublic() async throws {
    let logs = LogBuffer()
    let servers = service(try environment(), logs: logs)
    let (port, wsPort) = Self.freePorts()
    let project = self.project
    // A build into public/ is running; the start waits for it and says so.
    try "".write(to: scratch.url.appendingPathComponent("hold"), atomically: true, encoding: .utf8)
    let build = Task { try await servers.build(projectId: "p", project: project, outputDir: nil) }
    try await Self.until { !calls.isEmpty }
    let start = Task { await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort)) }
    try await Self.until { logs.history("p").server.contains { $0.stream == .warn } }
    #expect(logs.history("p").server.first?.text == L10n.t("main.serverWaitsForBuild", ["dir": project.path + "/public"]) + "\n")
    #expect(await servers.serverStatus("p").state == .starting)
    // While it waits, a build into public/ is the server's folder.
    await #expect(throws: BuildService.Refusal.serverWriting(directory: project.path + "/public")) {
      try await servers.assertOutputFree(projectId: "p", project: project, outputDir: "public")
    }
    try FileManager.default.removeItem(at: scratch.url.appendingPathComponent("hold"))
    #expect(try await build.value.success)
    _ = await start.value
    try await Self.until { await servers.serverStatus("p").state == .running }
    // Running: public/ is refused, another folder is not.
    await #expect(throws: BuildService.Refusal.serverWriting(directory: project.path + "/public")) {
      try await servers.build(projectId: "p", project: project, outputDir: nil)
    }
    #expect(try await servers.build(projectId: "p", project: project, outputDir: "dist").success)
    await servers.stopServer("p")
  }

  @Test func stoppingAWaitingStartCallsItOff() async throws {
    let prepared = Mutex(0)
    let step: BuildService.PreparationStep = { _, _ in prepared.withLock { $0 += 1 } }
    let servers = service(try environment(), preparation: [step])
    let project = self.project
    try "".write(to: scratch.url.appendingPathComponent("hold"), atomically: true, encoding: .utf8)
    let build = Task { try await servers.build(projectId: "p", project: project, outputDir: nil) }
    try await Self.until { !calls.isEmpty }
    let (port, wsPort) = Self.freePorts()
    let start = Task { await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort)) }
    try await Self.until { await servers.serverStatus("p").state == .starting }
    await servers.stopServer("p")
    #expect(await servers.serverStatus("p").state == .stopped)
    try FileManager.default.removeItem(at: scratch.url.appendingPathComponent("hold"))
    _ = try await build.value
    #expect(await start.value.state == .stopped)
    #expect(calls.count == 1, "only the build ran: \(calls)")
    #expect(prepared.withLock { $0 } == 1, "the called-off start prepared nothing (the build did once)")
  }

  /// The page port moves onto the port asked for the websocket: the websocket moves on, and the
  /// console says it is the page's now, not "in use".
  @Test func theWebsocketPortMakesWayForThePage() async throws {
    var start = 30_000 + Int(getpid() % 5000) * 3
    while await [start, start + 1, start + 2].asyncAllFree() == false { start += 3 }
    let holder = Self.occupy(start)
    defer { close(holder) }
    let logs = LogBuffer()
    let servers = service(try environment(), logs: logs)
    _ = await servers.startServer(projectId: "p", project: project, options: .init(port: start, wsPort: start + 1))
    let chosen = try #require(await servers.serverStatus("p").options)
    #expect(chosen.port == start + 1 && chosen.wsPort == start + 2, "\(chosen)")
    #expect(logs.history("p").server.map(\.text).contains(
      L10n.t("main.serverWsPortIsHttpPort", ["from": String(start + 1), "to": String(start + 2)]) + "\n"))
    await servers.stopServer("p")
  }

  @Test func aServerThatDiesOnItsOwnSaysHow() async throws {
    try mode("die")
    let servers = service(try environment())
    let (port, wsPort) = Self.freePorts()
    _ = await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    try await Self.until { await servers.serverStatus("p").state == .error }
    #expect(await servers.serverStatus("p") == BuildService.ServerStatus(state: .error, ended: .exited(2)))
    #expect(RunningServersStore(profile: profile).peek().keys.isEmpty)
  }

  @Test func withoutNpxTheStartFailsWithTheSystemsWord() async throws {
    let servers = service(try environment(npx: false))
    let status = await servers.startServer(projectId: "p", project: project)
    #expect(status == BuildService.ServerStatus(state: .error, error: "spawn npx ENOENT"))
  }

  @Test func withoutALogFileTheServerStillRuns() async throws {
    // A file where the folder belongs: .quartz-gui/logs cannot be made.
    try "".write(to: project.appendingPathComponent(".quartz-gui"), atomically: true, encoding: .utf8)
    let logs = LogBuffer()
    let servers = service(try environment(), logs: logs)
    let (port, wsPort) = Self.freePorts()
    _ = await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    // No line to hear: running once the websocket port is open too.
    try await Self.until { await servers.serverStatus("p").state == .running }
    #expect(await servers.serverStatus("p").state == .running)
    let said = logs.history("p").server
    #expect(said.count == 1 && said[0].stream == .warn && said[0].text.hasPrefix(L10n.t("main.serverLogUnavailable", ["reason": ""]).prefix(20)))
    await servers.stopServer("p")
  }

  @Test func withoutQuartzsLineTheWebsocketPortDecides() async throws {
    try mode("noline")
    let servers = service(try environment())
    let (port, wsPort) = Self.freePorts()
    _ = await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    try await Self.until { await servers.serverStatus("p").state == .running }
    #expect(await servers.serverStatus("p").state == .running)
    await servers.stopServer("p")
  }

  /// The page port alone proves nothing (whoever binds it first answers): without Quartz's line
  /// and without the websocket port the server stays "starting", and after five seconds says why.
  @Test func thePagePortAloneIsNotRunning() async throws {
    try mode("noline-nows")
    let logs = LogBuffer()
    let servers = service(try environment(), logs: logs)
    let (port, wsPort) = Self.freePorts()
    _ = await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    try await Self.until { await ServerPorts.state(port) == .taken }
    try await Self.until(8) { logs.history("p").server.contains { $0.stream == .warn } }
    #expect(await servers.serverStatus("p").state == .starting)
    #expect(logs.history("p").server.last { $0.stream == .warn }?.text
      == L10n.t("main.serverWaitsForWsPort", ["port": String(port), "wsPort": String(wsPort)]) + "\n")
    await servers.stopServer("p")
  }

  @Test func twoProjectsAtOnceGetPortsOfTheirOwn() async throws {
    let servers = service(try environment())
    let (port, wsPort) = Self.freePorts()
    let first = project, second = scratch.url.appendingPathComponent("Zweites")
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    async let a = servers.startServer(projectId: "p", project: first, options: .init(port: port, wsPort: wsPort))
    async let b = servers.startServer(projectId: "q", project: second, options: .init(port: port, wsPort: wsPort))
    let (p, q) = await (a, b)
    let ports = [p.options?.port, p.options?.wsPort, q.options?.port, q.options?.wsPort].compactMap { $0 }
    #expect(Set(ports).count == 4, "\(ports)")
    await servers.stopServer("p")
    await servers.stopServer("q")
  }

  @Test func onlyTheLogsOfEndedRunsAreRemoved() async throws {
    let logs = try QuartzGuiDirectory(project: project).create("logs")
    for name in ["dev-server-999999.out.log", "dev-server-tmp-1.err.log", "dev-server.out.log", "notes.txt", "build.log"] {
      try "".write(to: logs.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let servers = service(try environment())
    let (port, wsPort) = Self.freePorts()
    _ = await servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    let pid = try #require(await servers.serverStatus("p").pid)
    let left = Set(try FileManager.default.contentsOfDirectory(atPath: logs.path))
    #expect(left == ["notes.txt", "build.log", "dev-server-\(pid).out.log", "dev-server-\(pid).err.log"])
    // A second start (after a restart) keeps the files of a server that still runs.
    ServerLogFiles.prune(logs)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: logs.path)) == left)
    await servers.stopServer("p")
  }

  @Test func twoClicksOnStartAreOneServerAndARestartKeepsItsPorts() async throws {
    let servers = service(try environment())
    let (port, wsPort) = Self.freePorts()
    let project = self.project
    async let a = servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    async let b = servers.startServer(projectId: "p", project: project, options: .init(port: port, wsPort: wsPort))
    _ = await (a, b)
    try await Self.until { await servers.serverStatus("p").state == .running }
    #expect(calls.count == 1, "\(calls)")
    let first = try #require(await servers.serverStatus("p").pid)
    let restarted = await servers.restartServer(projectId: "p", project: project)
    #expect(restarted.pid != first && restarted.options?.port == port, "\(restarted)")
    try await Self.until { await servers.serverStatus("p").state == .running }
    #expect(await servers.serverStatus("p").state == .running)
    await servers.stopServer("p")
  }

  /// The real `quartz build --serve` of a copy of gui-test.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["QH_QUARTZ_TESTS"] == "1", "QH_QUARTZ_TESTS=1"))
  func theRealQuartzServesACopyOfGuiTest() async throws {
    let original = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/QuartzProjekte/gui-test")
    let copy = scratch.url.appendingPathComponent("gui-test")
    try #require(await ProcessRunner.run(Command("/bin/cp", ["-cR", original.path, copy.path])).success)
    let environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    let logs = LogBuffer()
    let servers = BuildService(logs: logs, environment: { environment }, store: RunningServersStore(profile: profile))
    let (port, wsPort) = Self.freePorts()
    let clock = ContinuousClock()
    let start = clock.now
    _ = await servers.startServer(projectId: "g", project: copy, options: .init(port: port, wsPort: wsPort))
    try await Self.until(120) { await servers.serverStatus("g").state != .starting }
    let took = clock.now - start
    #expect(await servers.serverStatus("g").state == .running, "\(logs.history("g").server.map(\.text).joined())")
    guard case .body(let page) = await LiveProbes.page(port) else { Issue.record("no page on \(port)"); return }
    #expect(page.contains("generator"))
    let pid = try #require(await servers.serverStatus("g").pid)
    let rows = try #require(try? await ServerScan.processTable(.live).get())
    let children = rows.filter { $0.ppid == pid }.map(\.pid)
    await servers.stopServer("g")
    #expect(kill(pid, 0) != 0)
    #expect(children.allSatisfy { kill($0, 0) != 0 }, "npx's node outlived the stop")
    #expect(await ServerPorts.state(port) == .free)
    print("gui-test served after \(took), \(children.count) Kind(er) unter npx")
  }
}

extension Array where Element == Int {
  func asyncAllFree() async -> Bool {
    for port in self where await ServerPorts.state(port) != .free { return false }
    return true
  }
}
