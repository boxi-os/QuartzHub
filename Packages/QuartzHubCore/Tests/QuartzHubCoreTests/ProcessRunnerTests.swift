import Darwin
import Foundation
import Synchronization
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

/// Output while the process runs (the build's console) and text across read boundaries.
@Suite struct ProcessOutputTests {
  final class Pieces: Sendable {
    let items = Mutex<[(ProcessRunner.OutputStream, String, ContinuousClock.Instant)]>([])
    func add(_ stream: ProcessRunner.OutputStream, _ text: String) {
      items.withLock { $0.append((stream, text, ContinuousClock.now)) }
    }
    func text(_ stream: ProcessRunner.OutputStream) -> String {
      items.withLock { $0.filter { $0.0 == stream }.map(\.1).joined() }
    }
  }

  @Test func outputArrivesWhileTheProcessRuns() async throws {
    let pieces = Pieces()
    let start = ContinuousClock.now
    let result = await ProcessRunner.run(ProcessRunnerTests.sh("echo a; sleep 0.6; echo b >&2; echo c"), onOutput: pieces.add)
    let end = ContinuousClock.now
    #expect(result.termination == .exited(0))
    let first = try #require(pieces.items.withLock { $0.first })
    #expect(first.0 == .stdout && first.1 == "a\n")
    #expect(first.2 - start < .milliseconds(400), "the first line came \(first.2 - start) after the start")
    #expect(end - first.2 > .milliseconds(400))
    #expect(pieces.text(.stdout) == result.stdout)
    #expect(pieces.text(.stderr) == "b\n")
  }

  @Test func aCharacterCutByAReadIsNotTorn() async {
    let pieces = Pieces()
    // "ä" is c3 a4; the two bytes come in two writes, a fifth of a second apart.
    let result = await ProcessRunner.run(ProcessRunnerTests.sh(#"printf '\303'; sleep 0.2; printf '\244\n'; printf '\360\237' >&2"#),
                                         onOutput: pieces.add)
    #expect(result.stdout == "ä\n")
    #expect(pieces.items.withLock { $0.filter { $0.0 == .stdout }.map(\.1) } == ["ä\n"])
    // An end that never came is said at the end of its stream, as one U+FFFD (as the whole would).
    #expect(pieces.text(.stderr) == "\u{FFFD}")
  }

  /// SplitMix64: the same bytes on every run.
  struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  @Test func thePiecesAreTheWhole() {
    // Bytes from the edges of UTF-8: every lead, the bounds of the second byte after E0/ED/F0/F4,
    // continuation bytes, what is never valid, plain ASCII.
    let alphabet: [UInt8] = [0x41, 0x0a, 0x7f, 0x80, 0x8f, 0x90, 0x9f, 0xa0, 0xa4, 0xbf, 0xc0, 0xc1, 0xc2, 0xc3, 0xdf,
                             0xe0, 0xe4, 0xed, 0xef, 0xf0, 0xf4, 0xf5, 0xff]
    var random = Seeded(state: 2026_11_06)
    var compared = 0
    for _ in 0..<5000 {
      let bytes = (0..<Int.random(in: 1...24, using: &random)).map { _ in alphabet.randomElement(using: &random)! }
      var stream = UTF8Stream()
      var text = ""
      var rest = bytes[...]
      while !rest.isEmpty {
        let take = Int.random(in: 1...min(4, rest.count), using: &random)
        text += stream.feed(rest.prefix(take))
        rest = rest.dropFirst(take)
      }
      text += stream.finish()
      #expect(text == String(decoding: bytes, as: UTF8.self), "\(bytes.map { String($0, radix: 16) })")
      compared += 1
    }
    #expect(compared == 5000)
    // What is held back is held back only as long as it can still become a character.
    var stream = UTF8Stream()
    #expect(stream.feed([0x41, 0xe4, 0xb8]) == "A")
    #expect(stream.feed([0xad]) == "中")
    #expect(stream.feed([0xe0, 0x80]) == "\u{FFFD}\u{FFFD}", "E0 80 can never become a character")
    #expect(stream.feed([0xf0, 0x9f, 0x8e]) == "")
    #expect(stream.feed([0x89]) == "🎉")
  }
}

/// `ProcessRunner.launch`: the dev server's way to start.
@Suite struct LaunchedProcessTests {
  struct Files {
    let directory: URL
    init() throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("qh-launch-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func open(_ name: String) -> Int32 {
      Darwin.open(directory.appendingPathComponent(name).path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o644)
    }
    func read(_ name: String) -> String {
      (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
  }

  static func launch(_ script: String, _ files: Files) throws -> LaunchedProcess {
    let out = files.open("out"), err = files.open("err")
    // Our copies go at once: the child has its own, as QuartzControl's spawnServer does it.
    defer { close(out); close(err) }
    return try ProcessRunner.launch(Command("/bin/sh", ["-c", script]), stdout: out, stderr: err).get()
  }

  static func waitFor(_ condition: () -> Bool) async throws {
    for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
  }

  @Test func itWritesIntoItsFilesAfterWeLetGo() async throws {
    let files = try Files()
    defer { files.remove() }
    let process = try Self.launch("sleep 0.3; echo late; echo wrong >&2; exit 4", files)
    #expect(process.termination == nil)
    #expect(await process.exit() == .exited(4))
    #expect(process.termination == .exited(4))
    #expect(await process.exit() == .exited(4), "asked again after the end")
    #expect(files.read("out") == "late\n")
    #expect(files.read("err") == "wrong\n")
  }

  @Test func withoutFilesItsOutputGoesNowhereAndStdinIsEmpty() async throws {
    // cat on an open stdin would wait; /dev/null ends it.
    let process = try ProcessRunner.launch(Command("/bin/cat")).get()
    #expect(await process.exit() == .exited(0))
  }

  @Test func itHasItsOwnGroupAndStopReachesAllOfIt() async throws {
    let files = try Files()
    defer { files.remove() }
    let process = try Self.launch("sleep 30 & echo $!; wait", files)
    try await Self.waitFor { !files.read("out").isEmpty }
    let grandchild = try #require(pid_t(files.read("out").trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(grandchild, SIGKILL) }
    #expect(getpgid(process.pid) == process.pid)
    #expect(getpgid(grandchild) == process.pid)
    #expect(getpgid(process.pid) != getpgrp())
    #expect(await process.stop(grace: .milliseconds(500)) == .signaled(SIGTERM))
    #expect(!ProcessRunnerTests.alive(grandchild))
    #expect(!process.groupIsAlive)
    #expect(!process.signal(SIGTERM), "no group any more")
  }

  @Test func stopWaitsForWhatTheProcessLeftBehind() async throws {
    // The shell ends on SIGTERM, the subshell it started ignores it and holds on, as a node under
    // npx can: the stop is over when nothing of the group is left, not when the shell is.
    let files = try Files()
    defer { files.remove() }
    let process = try Self.launch("(trap '' TERM; while :; do sleep 0.05; done) & echo $!; wait", files)
    try await Self.waitFor { !files.read("out").isEmpty }
    let stubborn = try #require(pid_t(files.read("out").trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(stubborn, SIGKILL) }
    let start = ContinuousClock.now
    #expect(await process.stop(grace: .milliseconds(400)) == .signaled(SIGTERM))
    #expect(ContinuousClock.now - start >= .milliseconds(400))
    try await Self.waitFor { !ProcessRunnerTests.alive(stubborn) }
    #expect(!ProcessRunnerTests.alive(stubborn), "\(stubborn) survived the stop")
  }

  @Test func startFailuresAreTheirOwnAnswers() {
    #expect(throws: CommandResult.StartFailure.notFound) {
      try ProcessRunner.launch(Command("qh-no-such-tool", environment: ["PATH": "/usr/bin:/bin"])).get()
    }
    #expect(throws: CommandResult.StartFailure.directoryMissing) {
      try ProcessRunner.launch(Command("/bin/pwd", in: URL(fileURLWithPath: "/nowhere-\(UUID().uuidString)"))).get()
    }
  }
}
