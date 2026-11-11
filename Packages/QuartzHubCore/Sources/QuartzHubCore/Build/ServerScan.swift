import Darwin
import Foundation

/// The Quartz dev servers running on this machine, whoever started them: QuartzHub, a terminal,
/// QuartzControl, a run that was force-quit (QuartzControl's `serverDiscovery.ts`, measured in
/// ServerScanTests). The orphan check answers a narrower question (are the pids QuartzHub wrote
/// down still alive) and sees only QuartzHub's own.
///
/// What it reads, as QuartzControl measured with `npx quartz build --serve --port 8099 --wsPort
/// 3099` on macOS 26:
///
///     12877     1  npm exec quartz build --serve --port 8099 --wsPort 3099
///     12893 12877  node --no-deprecation …/.bin/quartz build --serve --port 8099 --wsPort 3099
///
/// Both lines carry the needles, the child holds the ports, and both name them, so for a server
/// started with flags no socket table is needed. `lsof` answers two narrower questions: the working
/// directory (which maps a server to a project), and which ports a candidate that named none holds.
public enum ServerScan {
  public struct Row: Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32
    /// Seconds since the start, from ps's `etime`; nil where that did not read as a time.
    public var elapsed: Double?
    public var command: String
  }

  public struct Server: Sendable, Equatable {
    /// The topmost process of the group: what a stop signals.
    public var pid: Int32
    /// The process holding the ports; the same pid without a wrapper.
    public var listenerPid: Int32
    public var port: Int
    public var wsPort: Int?
    /// Where it runs, when that could be read; what maps it to a project.
    public var cwd: String?
    public var projectId: String?
    public var projectName: String?
    /// From the elapsed time, so no locale-formatted date is read.
    public var startedAt: Date?
    /// QuartzHub started it in this session; it is stopped as QuartzHub's own.
    public var ownedByApp: Bool
    /// Did the HTTP port answer at all.
    public var reachable: Bool
    public var siteTitle: String?
    /// `<meta name="generator" content="Quartz">` in the page: a Quartz site, not necessarily a dev
    /// server (a statically served build looks the same). It confirms, it never decides.
    public var quartzGenerator: Bool?
  }

  public enum State: String, Sendable {
    case ok
    /// The process table was read, but for at least one candidate the socket table was not: the
    /// servers are real, and there may be more.
    case partial
    /// Could not read the process table: never "nothing runs".
    case unavailable
  }

  public struct Result: Sendable, Equatable {
    public var state: State
    /// Why the scan could not answer in full. English, a diagnostic.
    public var reason: String?
    public var servers: [Server]
    /// Ports asked about that answer a TCP connect but belong to no server found: something else
    /// holds the port a project wants.
    public var occupiedPorts: [Int]
  }

  public struct StopResult: Sendable, Equatable {
    /// False when the process was gone or no longer an offered server by the time of the signal.
    public var stopped: Bool
    /// Set when it was QuartzHub's own and went the normal way.
    public var projectId: String?
  }

  /// What the page on port answered.
  public enum Page: Sendable, Equatable {
    case unreachable
    /// It answered and broke off before the end; nothing of it is read.
    case brokenOff
    case body(String)
  }

  /// The outside world: the commands, the two probes, the signal, the clock. `.live` on this
  /// machine; the tests hand over QuartzControl's recorded answers.
  public struct System: Sendable {
    public var run: @Sendable (Command) async -> CommandResult
    public var probeTCP: @Sendable (Int) async -> Bool
    public var fetchPage: @Sendable (Int) async -> Page
    /// SIGTERM to the process and everything below it in `rows`; false when a signal failed for
    /// another reason than the process being gone.
    public var signalTree: @Sendable (Int32, [Row]) -> Bool
    public var now: @Sendable () -> Date

    public init(run: @escaping @Sendable (Command) async -> CommandResult, probeTCP: @escaping @Sendable (Int) async -> Bool,
                fetchPage: @escaping @Sendable (Int) async -> Page, signalTree: @escaping @Sendable (Int32, [Row]) -> Bool,
                now: @escaping @Sendable () -> Date) {
      self.run = run
      self.probeTCP = probeTCP
      self.fetchPage = fetchPage
      self.signalTree = signalTree
      self.now = now
    }

    public static let live = System(run: { await ProcessRunner.run($0) }, probeTCP: LiveProbes.tcp, fetchPage: LiveProbes.page,
                                    signalTree: LiveProbes.signalTree, now: Date.init)
  }

  /// What quartz takes without the flags, the same two numbers QuartzHub passes.
  public static let defaultPort = 8080
  public static let defaultWsPort = 3001
  static let pageLimit = 64 * 1024

  // MARK: scan

  /// `ports`: the ports a project wants, to say which of them something else holds. `owned`:
  /// QuartzHub's own servers, pid of the group → project id.
  public static func discover(ports: [Int] = [], projects: [ProjectEntry], owned: [Int32: String],
                              system: System = .live) async -> Result {
    let rows: [Row]
    switch await processTable(system) {
    case .success(let read): rows = read
    case .failure(let reason): return Result(state: .unavailable, reason: "ps failed: \(reason.message)", servers: [], occupiedPorts: [])
    }
    let resolved = await resolveGroups(groupCandidates(rows), system)
    let now = system.now()
    let servers = await withTaskGroup(of: (Int, Server).self) { tasks in
      for (index, group) in resolved.groups.enumerated() {
        tasks.addTask {
          async let cwd = workingDirectory(group.listener.pid, system)
          async let page = system.fetchPage(group.port)
          let (directory, answer) = await (cwd, page)
          let project = directory.flatMap { directory in
            projects.first { samePlace($0.path, directory) }
          }
          let probe = markers(answer)
          return (index, Server(
            pid: group.root.pid, listenerPid: group.listener.pid, port: group.port, wsPort: group.wsPort, cwd: directory,
            projectId: project?.id ?? owned[group.root.pid], projectName: project?.name,
            startedAt: group.listener.elapsed.map { Date(timeIntervalSince1970: (now.timeIntervalSince1970 * 1000 - $0 * 1000) / 1000) },
            ownedByApp: owned[group.root.pid] != nil, reachable: probe.reachable, siteTitle: probe.title,
            quartzGenerator: probe.generator))
        }
      }
      var found: [(Int, Server)] = []
      for await item in tasks { found.append(item) }
      return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // Only ports no server found explains: there "taken" is news.
    let explained = Set(servers.flatMap { [$0.port, $0.wsPort ?? 0] })
    var asked: [Int] = []
    for port in ports where !explained.contains(port) && !asked.contains(port) { asked.append(port) }
    let open = await withTaskGroup(of: (Int, Bool).self) { tasks in
      for (index, port) in asked.enumerated() { tasks.addTask { (index, await system.probeTCP(port)) } }
      var answers = [Bool](repeating: false, count: asked.count)
      for await (index, isOpen) in tasks { answers[index] = isOpen }
      return answers
    }
    let occupied = zip(asked, open).filter(\.1).map(\.0)

    if let reason = resolved.unavailable { return Result(state: .partial, reason: reason, servers: servers, occupiedPorts: occupied) }
    return Result(state: .ok, reason: nil, servers: servers, occupiedPorts: occupied)
  }

  /// Stops a server the scan offered. One of QuartzHub's own goes through `stopOwned`, so its
  /// status, log and record stay in step. Any other is checked again against a fresh process table
  /// first (a pid does not carry over time): only the root of a group whose port could be
  /// established may be signalled, which is exactly what the scan offers.
  public static func stop(pid: Int32, owned: [Int32: String], stopOwned: @Sendable (String) async -> Void,
                          system: System = .live) async -> StopResult {
    if let projectId = owned[pid] {
      await stopOwned(projectId)
      return StopResult(stopped: true, projectId: projectId)
    }
    guard case .success(let rows) = await processTable(system) else { return StopResult(stopped: false) }
    let groups = await resolveGroups(groupCandidates(rows), system).groups
    guard groups.contains(where: { $0.root.pid == pid }) else { return StopResult(stopped: false) }
    return StopResult(stopped: system.signalTree(pid, rows))
  }

  /// A pid read back from somewhere is a dev server only if it lives and its command line still
  /// has "quartz" and "--serve" (QuartzControl's `isAlive` + `looksLikeQuartzServer`): the system
  /// hands numbers out again. The tracked pid is npx's, whose title npm rewrites to the arguments
  /// QuartzHub passed; QuartzHub's own path says "QuartzHub", capital Q.
  public static func isQuartzServer(_ pid: Int32) -> Bool {
    guard pid > 0, kill(pid, 0) == 0, let command = Coexistence.commandLine(pid) else { return false }
    return command.contains("quartz") && command.contains("--serve")
  }

  // MARK: process table

  struct Failure: Error {
    let message: String
  }

  static func processTable(_ system: System) async -> Swift.Result<[Row], Failure> {
    // -ww: a long command line is not cut at the terminal width; the ports are at its end.
    let command = Command("/bin/ps", ["-ww", "-Ao", "pid=,ppid=,etime=,command="], timeout: .seconds(4))
    let result = await system.run(command)
    guard result.success else { return .failure(Failure(message: nodeMessage(command, result))) }
    return .success(parseTable(result.stdout))
  }

  static func parseTable(_ text: String) -> [Row] {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
      guard let match = line.wholeMatch(of: /\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)/),
            let pid = Int32(match.1), let ppid = Int32(match.2) else { return nil }
      return Row(pid: pid, ppid: ppid, elapsed: parseElapsed(String(match.3)), command: String(match.4))
    }
  }

  /// ps's `etime`, `[[dd-]hh:]mm:ss`, read the way QuartzControl reads it (`parseInt` per part,
  /// `Number` for the days). Not `lstart`: that is a date in the user's language.
  static func parseElapsed(_ text: String) -> Double? {
    let pieces = text.split(separator: "-", omittingEmptySubsequences: false)
    let (days, clock) = text.contains("-") ? (String(pieces[0]), String(pieces[1])) : ("0", text)
    let parts = clock.split(separator: ":", omittingEmptySubsequences: false).map { jsParseInt(String($0)) }
    if parts.contains(where: { $0 == nil }) { return nil }
    let values = parts.map { Double($0!) }
    let (h, m, s): (Double, Double?, Double?) = values.count == 3 ? (values[0], values[1], values[2])
      : (0, values.first, values.count > 1 ? values[1] : nil)
    guard let m, let s, let d = jsNumber(days) else { return nil }
    return d * 86_400 + h * 3600 + m * 60 + s
  }

  /// JavaScript's `parseInt(text, 10)`: leading space, a sign, the digits that follow; nil (NaN)
  /// without a digit.
  static func jsParseInt(_ text: String) -> Int? {
    var rest = Substring(text).drop { $0.isWhitespace }
    var sign = 1
    if let first = rest.first, first == "-" || first == "+" {
      sign = first == "-" ? -1 : 1
      rest = rest.dropFirst()
    }
    let digits = rest.prefix { $0.isASCII && $0.isNumber }
    return Int(digits).map { $0 * sign }
  }

  /// JavaScript's `Number(text)` for what a day count can look like: "" is 0.
  static func jsNumber(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? 0 : Double(trimmed).flatMap { $0.isFinite ? $0 : nil }
  }

  /// `--serve` as a whole word (`appleeventsd --server` is in every process table) and "quartz"
  /// anywhere, both after lowercasing: a project in "QuartzProjekte" carries no lowercase "quartz".
  static func looksLikeQuartzServer(_ command: String) -> Bool {
    let lowered = command.lowercased()
    return lowered.contains("quartz") && lowered.contains(/(?:^|\s)--serve(?:\s|$)/)
  }

  static func portArgument(_ command: String, _ flag: String) -> Int? {
    let pattern = try! Regex("(?:^|\\s)--\(flag)(?:=|\\s+)(\\d{1,5})(?:\\s|$)")
    guard let match = command.firstMatch(of: pattern), let text = match.output[1].substring, let port = Int(text) else { return nil }
    return (1...65535).contains(port) ? port : nil
  }

  struct Candidate {
    var root: Row
    var listener: Row
    var port: Int?
    var wsPort: Int?
  }

  struct Group {
    var root: Row
    var listener: Row
    var port: Int
    var wsPort: Int?
  }

  /// One entry per server, not per process: npx is two processes with the same arguments. The
  /// root is what gets signalled, the deepest is what holds the ports (ps lists parents first).
  static func groupCandidates(_ rows: [Row]) -> [Candidate] {
    var order: [Int32] = []
    var candidates: [Int32: Row] = [:]
    for row in rows where looksLikeQuartzServer(row.command) {
      if candidates[row.pid] == nil { order.append(row.pid) }
      candidates[row.pid] = row
    }
    var groupOrder: [Int32] = []
    var groups: [Int32: Candidate] = [:]
    for pid in order {
      let row = candidates[pid]!
      var root = row
      var seen: Set<Int32> = [row.pid]
      while let parent = candidates[root.ppid], !seen.contains(root.ppid) {
        seen.insert(root.ppid)
        root = parent
      }
      if groups[root.pid] == nil {
        groupOrder.append(root.pid)
      } else if row.pid == root.pid {
        continue
      }
      groups[root.pid] = Candidate(root: root, listener: row, port: portArgument(row.command, "port"),
                                   wsPort: portArgument(row.command, "wsPort"))
    }
    return groupOrder.map { groups[$0]! }
  }

  /// Candidates become servers; one whose port cannot be established is left out. Without
  /// `--port` the default is a guess the socket table has to confirm: a process that only had
  /// "quartz" in its path and `--serve` somewhere was once listed on 8080, wearing the title of
  /// whatever answered there (QuartzControl measured it).
  static func resolveGroups(_ candidates: [Candidate], _ system: System) async -> (groups: [Group], unavailable: String?) {
    let answers = await withTaskGroup(of: (Int, Group?, String?).self) { tasks in
      for (index, candidate) in candidates.enumerated() {
        tasks.addTask {
          if let port = candidate.port {
            return (index, Group(root: candidate.root, listener: candidate.listener, port: port, wsPort: candidate.wsPort), nil)
          }
          switch await listeningPorts(candidate.listener.pid, system) {
          case .failure(let failure): return (index, nil, failure.message)
          case .success(let held):
            guard held.contains(defaultPort) else { return (index, nil, nil) }
            return (index, Group(root: candidate.root, listener: candidate.listener, port: defaultPort,
                                 wsPort: candidate.wsPort ?? (held.contains(defaultWsPort) ? defaultWsPort : nil)), nil)
          }
        }
      }
      var all: [(Int, Group?, String?)] = []
      for await item in tasks { all.append(item) }
      return all.sorted { $0.0 < $1.0 }
    }
    return (answers.compactMap(\.1), answers.lazy.compactMap(\.2).first)
  }

  /// The TCP ports a process listens on, or why that could not be found out, which is not "none".
  /// lsof's exit 1 with an empty stderr is its "no open file matched"; anything else is a reason.
  static func listeningPorts(_ pid: Int32, _ system: System) async -> Swift.Result<[Int], Failure> {
    // -P and -n keep ports and addresses numeric: `n*:8080`, never a name from /etc/services.
    let command = Command("/usr/sbin/lsof", ["-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-Fn"], timeout: .seconds(2))
    let result = await system.run(command)
    switch result.termination {
    case .exited(0):
      var ports: [Int] = []
      for line in result.stdout.split(separator: "\n") {
        if let match = line.wholeMatch(of: /n.*:(\d{1,5})/), let port = Int(match.1), !ports.contains(port) { ports.append(port) }
      }
      return .success(ports)
    case .exited(1) where result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
      return .success([])
    case .couldNotStart(.notFound):
      return .failure(Failure(message: "lsof: not installed"))
    default:
      let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return .failure(Failure(message: "lsof: \(stderr.isEmpty ? nodeMessage(command, result) : stderr)"))
    }
  }

  /// `lsof -Fn` prints one field per line, so a path with spaces needs no splitting. Without a
  /// UTF-8 locale it writes every byte outside ASCII as text (`G\xc3\xa4rten`), and an app started
  /// from the Finder or the Dock has none (neither has LANG; `open` in a terminal passes the
  /// shell's on, measured 2026-11-11): a server in a folder with an umlaut belonged to no project,
  /// and one of the same project started elsewhere was not refused. The locale is set for lsof,
  /// whatever QuartzHub was started with.
  static func workingDirectory(_ pid: Int32, _ system: System,
                               environment: [String: String] = ProcessInfo.processInfo.environment) async -> String? {
    var utf8 = environment
    utf8["LC_ALL"] = "en_US.UTF-8"
    let result = await system.run(Command("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"], environment: utf8, timeout: .seconds(2)))
    guard result.success else { return nil }
    return result.stdout.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
  }

  /// Beyond QuartzControl, which compared the strings: the same folder by its real path too, so a
  /// project registered through a symlink or in another spelling is still recognised (lsof names
  /// the real directory).
  static func samePlace(_ projectPath: String, _ cwd: String) -> Bool {
    let a = BuildOutputGuard.resolve(projectPath), b = BuildOutputGuard.resolve(cwd)
    return a == b || BuildOutputGuard.realPath(a) == BuildOutputGuard.realPath(b)
  }

  /// Node's `error.message` of `execFile` for the failures a diagnostic shows.
  static func nodeMessage(_ command: Command, _ result: CommandResult) -> String {
    let name = NodePath.basename(command.executable)
    if case .couldNotStart(.notFound) = result.termination { return "spawn \(name) ENOENT" }
    return "Command failed: \(([name] + command.arguments).joined(separator: " "))\n\(result.stderr)"
  }

  // MARK: page

  static func markers(_ page: Page) -> (reachable: Bool, title: String?, generator: Bool?) {
    switch page {
    case .unreachable: return (false, nil, nil)
    case .brokenOff: return (true, nil, nil)
    case .body(let full):
      // The head is all this needs.
      let body = String(decoding: full.utf8.prefix(pageLimit), as: UTF8.self)
      let title = body.firstMatch(of: /(?i)<title>([^<]*)<\/title>/).map { String($0.1).trimmingCharacters(in: .whitespacesAndNewlines) }
      return (true, title?.isEmpty == false ? title : nil, body.contains(/(?i)<meta\s+name="generator"\s+content="Quartz"/))
    }
  }
}

/// The probes and the signal on this machine.
enum LiveProbes {
  /// A TCP connect to 127.0.0.1, at most 1.5 s.
  @Sendable static func tcp(_ port: Int) async -> Bool {
    await ServerPorts.answers(host: "127.0.0.1", port: port, timeoutMs: 1500)
  }

  /// GET / on 127.0.0.1, 1.5 s, no redirect followed, at most 64 KiB read.
  @Sendable static func page(_ port: Int) async -> ServerScan.Page {
    guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return .unreachable }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 1.5
    configuration.timeoutIntervalForResource = 1.5
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let bytes: URLSession.AsyncBytes
    do {
      (bytes, _) = try await session.bytes(for: URLRequest(url: url), delegate: NoRedirects())
    } catch {
      return .unreachable
    }
    var data = Data()
    do {
      for try await byte in bytes {
        data.append(byte)
        if data.count >= ServerScan.pageLimit { bytes.task.cancel(); break }
      }
    } catch let error as URLError where error.code == .timedOut {
      return .unreachable
    } catch {
      return .brokenOff
    }
    return .body(String(decoding: data, as: UTF8.self))
  }

  final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
  }

  /// SIGTERM to `pid` and every process below it in `rows` (tree-kill's walk, on the table that
  /// was just read): the root first, then down. ESRCH is a process already gone, not a failure.
  @Sendable static func signalTree(_ pid: Int32, _ rows: [ServerScan.Row]) -> Bool {
    var children: [Int32: [Int32]] = [:]
    for row in rows { children[row.ppid, default: []].append(row.pid) }
    var queue = [pid]
    var seen: Set<Int32> = [pid]
    var index = 0
    while index < queue.count {
      for child in children[queue[index]] ?? [] where !seen.contains(child) {
        seen.insert(child)
        queue.append(child)
      }
      index += 1
    }
    var ok = true
    for target in queue where kill(target, SIGTERM) != 0 && errno != ESRCH { ok = false }
    return ok
  }
}
