import Darwin
import Foundation
import Testing
@testable import QuartzHubCore

/// The process starter against the cases QuartzControl measured for `runCommand`
/// (`docs/decisions/process-model-and-ipc.md`) and the ones that are new with posix_spawn.
@Suite struct ProcessRunnerTests {
  static func sh(_ script: String, timeout: Duration? = nil, input: Data? = nil) -> Command {
    var command = Command("/bin/sh", ["-c", script], input: input, timeout: timeout)
    command.killGrace = .milliseconds(300)
    return command
  }

  static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

  @Test func separatesStdoutAndKeepsOrderInOutput() async {
    let result = await ProcessRunner.run(Self.sh("echo one; echo two >&2; sleep 0.05; echo three; exit 3"))
    #expect(result.termination == .exited(3))
    #expect(!result.success)
    #expect(result.stdout == "one\nthree\n")
    #expect(result.output == "one\ntwo\nthree\n")
  }

  @Test func stdinIsClosedWithoutInput() async {
    // `cat` on an open, silent stdin would wait forever; /dev/null ends it at once.
    let result = await ProcessRunner.run(Command("/bin/cat", timeout: .seconds(5)))
    #expect(result.termination == .exited(0))
    #expect(result.output.isEmpty)
  }

  @Test func inputGoesToStdinWithoutDeadlock() async {
    // 4 MB through cat: more than any pipe buffer in both directions at once.
    let line = String(repeating: "äöü-xyz ", count: 64) + "\n"
    let text = String(repeating: line, count: 4 * 1024 * 1024 / line.utf8.count)
    let result = await ProcessRunner.run(Command("/bin/cat", input: Data(text.utf8), timeout: .seconds(20)))
    #expect(result.termination == .exited(0))
    #expect(result.stdout == text)
  }

  @Test func waitsForTheGrandchildThatHoldsStdout() async {
    // QuartzControl's measurement: at 'exit' "HEAD", at 'close' "HEAD\nTAIL".
    let result = await ProcessRunner.run(Self.sh("echo HEAD; (sleep 0.3; echo TAIL) &"))
    #expect(result.termination == .exited(0))
    #expect(result.stdout == "HEAD\nTAIL\n")
  }

  @Test func timeoutAnswersAtOnceAndKillsTheGroup() async throws {
    let clock = ContinuousClock()
    let start = clock.now
    // The grandchild prints its pid and then holds stdout, as rsync's ssh does.
    let result = await ProcessRunner.run(Self.sh("sleep 30 & echo $!; wait", timeout: .milliseconds(300)))
    let took = clock.now - start
    #expect(result.termination == .timedOut)
    #expect(took < .seconds(2), "took \(took)")
    let grandchild = try #require(pid_t(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
    // SIGTERM to the group reaches the grandchild too.
    var gone = false
    for _ in 0..<40 where !gone {
      try await Task.sleep(for: .milliseconds(50))
      gone = !Self.alive(grandchild)
    }
    #expect(gone, "grandchild \(grandchild) still running")
    #expect(result.report(for: Self.sh("", timeout: .milliseconds(300))).hasSuffix("Zeitüberschreitung nach 300 ms: /bin/sh -c")
      || result.report(for: Self.sh("", timeout: .milliseconds(300))).hasSuffix("Timed out after 300 ms: /bin/sh -c"))
  }

  @Test func timeoutReachesAGrandchildThatLetGoOfThePipes() async throws {
    // Without the pipes there is no SIGKILL round: the shell dies, both pipes close, and only
    // SIGTERM to the group reaches the grandchild (npm's node writing into a log file).
    let result = await ProcessRunner.run(Self.sh("sleep 30 >/dev/null 2>&1 & echo $!; wait", timeout: .milliseconds(200)))
    #expect(result.termination == .timedOut)
    let grandchild = try #require(pid_t(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(grandchild, SIGKILL) }
    var gone = false
    for _ in 0..<40 where !gone {
      try await Task.sleep(for: .milliseconds(50))
      gone = !Self.alive(grandchild)
    }
    #expect(gone, "grandchild \(grandchild) still running")
  }

  @Test func sigkillFollowsWhenSigtermIsIgnored() async throws {
    let result = await ProcessRunner.run(Self.sh("trap '' TERM; echo $$; while :; do sleep 0.05; done", timeout: .milliseconds(200)))
    #expect(result.termination == .timedOut)
    let pid = try #require(pid_t(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
    var gone = false
    for _ in 0..<40 where !gone {
      try await Task.sleep(for: .milliseconds(50))
      gone = !Self.alive(pid)
    }
    #expect(gone, "\(pid) survived SIGKILL")
  }

  @Test func cancellingTheTaskKillsTheProcess() async throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("qh-cancel-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let task = Task { await ProcessRunner.run(Self.sh("echo $$ > '\(marker.path)'; sleep 30")) }
    var pid: pid_t?
    for _ in 0..<100 where pid == nil {
      try await Task.sleep(for: .milliseconds(20))
      pid = (try? String(contentsOf: marker, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    let child = try #require(pid)
    task.cancel()
    let result = await task.value
    #expect(result.termination == .cancelled)
    try await Task.sleep(for: .milliseconds(100))
    #expect(!Self.alive(child))
  }

  @Test func argumentsKeepTheirBytes() async {
    // Foundation's Process sent "wört" as 6f cc 88 (NFD); the shell and Node send c3 b6.
    let result = await ProcessRunner.run(Command("/usr/bin/printf", ["%s", "wört"]))
    #expect(Array(result.stdout.utf8) == [0x77, 0xc3, 0xb6, 0x72, 0x74])
  }

  @Test func childInheritsNoDescriptors() async {
    // A descriptor of the app's without close-on-exec, at a high number. F_DUPFD takes the lowest
    // free one from 200 on; dup2 to a fixed number would silently replace a pipe of a test running
    // in parallel (it did once: environmentIsExactlyTheGivenOne read nothing).
    let fd = open("/dev/null", O_RDONLY)
    let high = fcntl(fd, F_DUPFD, 200)
    close(fd)
    defer { close(high) }
    #expect(high >= 200)
    let result = await ProcessRunner.run(Command("/bin/ls", ["/dev/fd"]))
    // 0, 1, 2 and what ls opens for the listing itself (3 and 4 on macOS 27).
    let listed = result.stdout.split(separator: "\n").compactMap { Int32($0) }
    #expect(!listed.contains(high) && listed.allSatisfy { $0 < 10 }, "\(listed)")
  }

  @Test func childRunsInItsOwnProcessGroup() async {
    let result = await ProcessRunner.run(Self.sh("echo $$; ps -o pgid= -p $$"))
    let lines = result.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(lines.count == 2 && lines[0] == lines[1], "\(lines)")
    #expect(lines.last != String(getpgrp()))
  }

  @Test func looksUpTheNameInTheChildsPath() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qh-path-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let tool = directory.appendingPathComponent("qh-probe-tool")
    try "#!/bin/sh\necho found \"$@\"\n".write(to: tool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

    let found = await ProcessRunner.run(Command("qh-probe-tool", ["x"], environment: ["PATH": "/nowhere:\(directory.path)"]))
    #expect(found.stdout == "found x\n")
    let missing = await ProcessRunner.run(Command("qh-probe-tool", environment: ["PATH": "/usr/bin:/bin"]))
    #expect(missing.termination == .couldNotStart(.notFound))
  }

  @Test func startFailuresAreTheirOwnAnswers() async {
    let missingDirectory = await ProcessRunner.run(Command("/bin/pwd", in: URL(fileURLWithPath: "/nowhere-\(UUID().uuidString)")))
    #expect(missingDirectory.termination == .couldNotStart(.directoryMissing))
    let directory = await ProcessRunner.run(Command("/bin/pwd", in: URL(fileURLWithPath: "/private/tmp")))
    #expect(directory.stdout == "/private/tmp\n")
    // QuartzControl measured 18000 paths / 940 KB failing with E2BIG.
    let paths = (0..<30000).map { "content/some/longer/folder/note-\($0).md" }
    let tooLong = await ProcessRunner.run(Command("/usr/bin/true", paths))
    #expect(tooLong.termination == .couldNotStart(.argumentsTooLong))
    // Exit 127 from a shell is a process that ran, not one that could not start.
    let exited = await ProcessRunner.run(Self.sh("exit 127"))
    #expect(exited.termination == .exited(127))
  }

  @Test func signalIsReportedAsSuch() async {
    let result = await ProcessRunner.run(Self.sh("kill -USR1 $$"))
    #expect(result.termination == .signaled(SIGUSR1))
  }

  @Test func environmentIsExactlyTheGivenOne() async {
    let result = await ProcessRunner.run(Command("/usr/bin/env", environment: ["ONLY": "this"]))
    #expect(result.stdout == "ONLY=this\n")
    let added = await ProcessRunner.run(Command("/usr/bin/env", environment: ["A": "1"]).adding(["B": "2", "A": "3"]))
    #expect(Set(added.stdout.split(separator: "\n")) == ["A=3", "B=2"])
  }
}
