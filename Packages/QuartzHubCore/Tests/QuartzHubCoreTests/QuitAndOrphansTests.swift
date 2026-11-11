import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// What happens to dev servers at quit, and to the ones a previous run left behind.
@Suite struct QuitAndOrphansTests {
  let base: BuildServerTests
  init() throws { base = try BuildServerTests() }

  @Test func atQuitEveryServerStopsAndAWaitingStartIsCalledOff() async throws {
    let servers = base.service(try base.environment())
    let (p1, w1) = BuildServerTests.freePorts()
    let other = base.scratch.url.appendingPathComponent("Zweites")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    _ = await servers.startServer(projectId: "p", project: base.project.path, options: .init(port: p1, wsPort: w1))
    _ = await servers.startServer(projectId: "q", project: other.path, options: .init(port: p1, wsPort: w1))
    let pids = [await servers.serverStatus("p").pid, await servers.serverStatus("q").pid].compactMap { $0 }
    #expect(pids.count == 2)
    // A third project's start waits for its build.
    let third = base.scratch.url.appendingPathComponent("Drittes")
    try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
    try "".write(to: base.scratch.url.appendingPathComponent("hold"), atomically: true, encoding: .utf8)
    let build = Task { try await servers.build(projectId: "r", project: third.path, outputDir: nil) }
    try await BuildServerTests.until { base.calls.count == 3 }
    let waiting = Task { await servers.startServer(projectId: "r", project: third.path) }
    try await BuildServerTests.until { await servers.serverStatus("r").state == .starting }

    await servers.stopAllServers()
    #expect(pids.allSatisfy { kill($0, 0) != 0 })
    #expect(await servers.runningServerSummaries().isEmpty)
    #expect(await servers.serverStatus("r").state == .stopped)
    #expect(RunningServersStore(profile: base.profile).peek().keys.isEmpty)
    try FileManager.default.removeItem(at: base.scratch.url.appendingPathComponent("hold"))
    _ = try await build.value
    #expect(await waiting.value.state == .stopped)
    #expect(base.calls.count == 3, "the called-off start spawned nothing")
  }

  /// A server that ignores SIGTERM does not hold the quit: the deadline ends the wait, and what
  /// survives stays recorded for the next start's question.
  @Test func atQuitTheDeadlineWins() async throws {
    try base.mode("stubborn")
    let servers = base.service(try base.environment())
    let (port, wsPort) = BuildServerTests.freePorts()
    _ = await servers.startServer(projectId: "p", project: base.project.path, options: .init(port: port, wsPort: wsPort))
    let pid = try #require(await servers.serverStatus("p").pid)
    let server = ProcessRunnerTests.Foreign(pid)
    defer { server.killGroup() }
    try await BuildServerTests.until { base.calls.count == 1 }
    let clock = ContinuousClock()
    let start = clock.now
    await servers.stopAllServers(grace: .seconds(10), deadline: .milliseconds(500))
    #expect(clock.now - start < .seconds(2))
    #expect(kill(pid, 0) == 0, "it ignores SIGTERM and lives")
    #expect(RunningServersStore(profile: base.profile).peek()["p"]?.pid == pid)
  }

  @Test func orphansAreTheRecordedServersThatStillRun() async throws {
    let store = RunningServersStore(profile: base.profile)
    let (port, wsPort) = BuildServerTests.freePorts()
    var command = Command("/usr/bin/python3", [BuildServerTests.fake.path, "quartz", "build", "--serve", "--port", String(port),
                                               "--wsPort", String(wsPort)], in: base.project.path)
    command.environment["QH_FAKE_DIR"] = base.scratch.url.path
    let left = try ProcessRunner.launch(command).get()
    defer { ProcessRunnerTests.endGroup(left) }
    let other = try ProcessRunner.launch(Command("/bin/sleep", ["30"])).get()
    defer { ProcessRunnerTests.endGroup(other) }
    try await BuildServerTests.until { await ServerPorts.state(port) == .taken }
    try store.record(projectId: "left", server: TrackedServer(pid: left.pid, port: port, startedAt: "t"))
    try store.record(projectId: "reused", server: TrackedServer(pid: other.pid, port: 1, startedAt: "t"))
    try store.record(projectId: "gone", server: TrackedServer(pid: 99_999_999, port: 2, startedAt: "t"))

    let orphans = OrphanedServers.detect(store: store)
    #expect(orphans == [OrphanedServers.Orphan(projectId: "left", pid: left.pid, port: port)])
    #expect(store.peek().keys.isEmpty, "asked once, whatever the answer")
    #expect(OrphanedServers.detect(store: store).isEmpty)

    // Between question and answer the number changed hands: no signal.
    #expect(OrphanedServers.stop(orphans, isRunning: { _ in false }).isEmpty)
    #expect(kill(left.pid, 0) == 0)
    #expect(OrphanedServers.stop(orphans) == [left.pid])
    #expect(await left.exit() == .signaled(SIGTERM))
    #expect(kill(other.pid, 0) == 0, "not a server, not touched")
  }
}
