import Foundation
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own gitStatusService.ts with real git (`scripts/git-golden.mjs`): no
/// repository, a broken index, a repository without a commit, every kind of change (paths with
/// spaces, quotes, a newline, umlauts), copies, an upstream ahead and behind and one that is gone,
/// detached, a merge, rebase, cherry-pick and revert with a conflict, a linked worktree, the cap.
@Suite(.serialized) struct GitStatusTests {
  static func json(_ status: GitStatus) -> JSONValue {
    func optional(_ text: String?) -> JSONValue { text.map(JSONValue.string) ?? .null }
    let changes: [JSONValue] = status.changes.map { change in
      var fields: [(String, JSONValue)] = [("path", .string(change.path))]
      if let orig = change.origPath { fields.append(("origPath", .string(orig))) }
      fields += [("staged", .bool(change.staged)), ("unstaged", .bool(change.unstaged)), ("status", .string(change.status.rawValue))]
      return .object(JSONObject(fields))
    }
    let commit: JSONValue = status.lastCommit.map { c in
      .object(JSONObject([("sha", .string(c.sha)), ("shortSha", .string(c.shortSha)), ("author", .string(c.author)),
                          ("date", .string(c.date)), ("subject", .string(c.subject))]))
    } ?? .null
    return .object(JSONObject([
      ("isRepo", .bool(status.isRepo)), ("readError", optional(status.readError)), ("branch", optional(status.branch)),
      ("detached", .bool(status.detached)), ("upstream", optional(status.upstream)), ("ahead", .number(Double(status.ahead))),
      ("behind", .number(Double(status.behind))), ("remoteUrl", optional(status.remoteUrl)), ("changes", .array(changes)),
      ("changeCount", .number(Double(status.changeCount))), ("conflictCount", .number(Double(status.conflictCount))),
      ("inProgress", optional(status.inProgress?.rawValue)), ("lastCommit", commit)
    ]))
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let golden = try GitGolden()
    var seen = 0
    try await golden.replay("status") { step in
      seen += 1
      let name = step["name"]!.stringValue!
      let status = await GitStatus.read(project: golden.url(step["args"]!.arrayValue![0].stringValue!), environment: golden.environment)
      var actual = Self.json(status).masked(golden.work)
      var expected = step["result"]!
      if name == "missing folder" {
        // QuartzControl's Node said "Error: spawn git ENOENT", as if git were missing; here the
        // folder is named.
        #expect(status.readError?.contains("ENOTDIR @W@/nowhere") == true || status.readError?.contains("ENOTDIR \(golden.work)/nowhere") == true,
                "\(String(describing: status.readError))")
        actual = actual.setting("readError", .null)
        expected = expected.setting("readError", .null)
      }
      #expect(actual == expected, "\(name)\n\(JSJSON.compact(actual))\n\(JSJSON.compact(expected))")
    }
    #expect(seen == 19)
  }

  /// A git that does not answer: the deadline's sentence is the read error, not a hang.
  @Test func aGitThatHangsIsAReadError() async throws {
    let scratch = try HostPathTests.Scratch()
    try scratch.script("bin/git", "sleep 30")
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"],
                                      hostPath: HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"],
                                                         source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    let started = ContinuousClock.now
    let status = await GitStatus.read(project: scratch.url.path, environment: environment, timeout: .milliseconds(300))
    #expect(ContinuousClock.now - started < .seconds(10))
    #expect(status.isRepo == false)
    #expect(status.readError == L10n.t("main.commandTimeout", ["ms": "300", "command": "git status"]))
  }

  static func fakeGit(_ body: String) throws -> (HostPathTests.Scratch, ToolEnvironment) {
    let scratch = try HostPathTests.Scratch()
    try scratch.script("bin/git", body)
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "LANG": "de_DE.UTF-8", "LC_ALL": "de_DE.UTF-8"],
                                      hostPath: HostPath(entries: [scratch.url.appendingPathComponent("bin").path, "/usr/bin", "/bin"],
                                                         source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    return (scratch, environment)
  }

  /// A German git says "Kein Git-Repository"; the sentence is matched in English, so git is asked
  /// in English (`LC_MESSAGES=C`, `LANGUAGE` empty, `LC_ALL` moved aside).
  @Test func aGermanGitIsAskedInEnglish() async throws {
    let (scratch, environment) = try Self.fakeGit("""
      if [ "$LC_MESSAGES" = C ] && [ -z "$LANGUAGE" ] && [ -z "$LC_ALL" ]; then echo 'fatal: not a git repository (or any of the parent directories): .git' >&2
      else echo 'fatal: Kein Git-Repository (oder irgendeines der Elternverzeichnisse): .git' >&2; fi
      exit 128
      """)
    let status = await GitStatus.read(project: scratch.url.path, environment: environment)
    #expect(status == GitStatus())
  }

  /// A warning on stderr is not read as a record.
  @Test func onlyStdoutIsParsed() async throws {
    let (scratch, environment) = try Self.fakeGit("""
      case "$1" in
        status) printf 'warning: unable to unlink ._pack\\n' >&2; sleep 0.2; printf '# branch.head main\\0? a.md\\0'; exit 0 ;;
        *) exit 1 ;;
      esac
      """)
    let status = await GitStatus.read(project: scratch.url.path, environment: environment)
    #expect(status.isRepo)
    #expect(status.branch == "main", "\(status)")
    #expect(status.changes == [GitStatus.Change(path: "a.md", staged: false, unstaged: true, status: .untracked)])
  }

  @Test func theDeadlineIsThirtySeconds() {
    #expect(GitStatus.timeout == .seconds(30))
    #expect(GitStatus.maxListedChanges == 500)
  }
}

extension JSONValue {
  func setting(_ key: String, _ value: JSONValue) -> JSONValue {
    guard case .object(let object) = self else { return self }
    return .object(JSONObject(object.keys.map { ($0, $0 == key ? value : object[$0]!) }))
  }
}
