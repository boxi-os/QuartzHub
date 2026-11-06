import Darwin
import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Against QuartzControl's own gitAuth.ts and githubService.ts (`scripts/git-golden.mjs`):
/// `parseGithubRemote` over 110 remotes, and `gitAuthForOrigin` for twelve origins and tokens; for
/// each the variables (the token's own as "<token>"), the prompt switch, what the helper answers to
/// git's two prompts and to anything else, its mode, and that the cleanup removes it.
@Suite(.serialized) struct GitAuthTests {
  /// WHATWG decodes and maps a host before it compares it; here such a host is nothing
  /// (`GitHubRemote`). Each one is a remote QuartzControl gave the token to.
  static let failsClosed: Set<String> = ["https://\u{ff47}ithub.com/o/r", "https://github%2Ecom/o/r"]

  @Test func parsesRemotesAsQuartzControl() throws {
    let step = try #require(GitGolden.steps.first { $0["op"] == .string("remotes") })
    let remotes = step["args"]!.arrayValue![1].arrayValue!.map { $0.stringValue! }
    let expected = step["result"]!.arrayValue!
    #expect(remotes.count == 110)
    var closed: Set<String> = []
    for (remote, answer) in zip(remotes, expected) {
      let parsed = GitHubRemote.parse(remote)
      let actual: JSONValue = parsed.map { .object(JSONObject([("owner", .string($0.owner)), ("repo", .string($0.repo))])) } ?? .null
      if Self.failsClosed.contains(remote) {
        closed.insert(remote)
        #expect(actual == .null, "\(remote)")
        #expect(answer != .null, "\(remote): QuartzControl did not take it either")
      } else {
        #expect(actual == answer, "\(JSJSON.compact(.string(remote))): \(JSJSON.compact(actual)) vs \(JSJSON.compact(answer))")
      }
    }
    #expect(closed == Self.failsClosed)
  }

  @Test func replaysQuartzControlsSteps() async throws {
    let golden = try GitGolden()
    var seen = 0
    try await golden.replay("auth") { step in
      seen += 1
      let name = step["name"]!.stringValue!
      let token = golden.token.withLock { $0 }
      let auth = try await GitAuth.forOrigin(project: golden.url(step["args"]!.arrayValue![0].stringValue!), environment: golden.environment,
                                             token: { token })
      let keys = auth.variables.keys.map { token != nil && auth.variables[$0] == token ? "<token>" : $0 }.sorted()
      var askpass: JSONValue = .null
      if let script = auth.variables["GIT_ASKPASS"] {
        func ask(_ prompt: String) async -> String {
          await ProcessRunner.run(Command(script, [prompt], environment: ["PATH": "/usr/bin:/bin"].merging(auth.variables) { $1 })).stdout
        }
        var info = stat()
        stat(script, &info)
        askpass = .object(JSONObject([
          ("mode", .string(String(info.st_mode & 0o777, radix: 8))), ("user", .string(await ask("Username for 'https://github.com': "))),
          ("pass", .string(await ask("Password for 'https://x-access-token@github.com': "))),
          ("lower", .string(await ask("username: "))), ("other", .string(await ask("Anything else? ")))
        ]))
      }
      let actual = JSONValue.object(JSONObject([
        ("keys", .array(keys.map(JSONValue.string))), ("prompt", auth.variables["GIT_TERMINAL_PROMPT"].map(JSONValue.string) ?? .null),
        ("askpass", askpass)
      ]))
      #expect(actual == step["result"], "\(name)\n\(JSJSON.compact(actual))\n\(JSJSON.compact(step["result"]!))")
      auth.cleanup()
      let removed: JSONValue = auth.variables["GIT_ASKPASS"].map { .bool(!Posix.exists(($0 as NSString).deletingLastPathComponent)) } ?? .null
      #expect(removed == step["removedAfterCleanup"], "\(name): cleanup")
      auth.cleanup()
    }
    #expect(seen == 12)
  }

  /// The token is in the environment of the one call, nowhere else: not in argv, not in the
  /// helper's text, not in the project.
  @Test func theTokenIsOnlyInTheEnvironment() async throws {
    let golden = try GitGolden()
    let project = golden.url("p")
    try Posix.mkdirs(project.path)
    _ = await ProcessRunner.run(golden.environment.command("git", ["init", "-q"], in: project))
    _ = await ProcessRunner.run(golden.environment.command("git", ["remote", "add", "origin", "https://github.com/o/r.git"], in: project))
    let auth = try await GitAuth.forOrigin(project: project, environment: golden.environment, token: { "ghp_needle" })
    defer { auth.cleanup() }
    let script = try #require(auth.variables["GIT_ASKPASS"])
    #expect(!String(decoding: try Posix.read(script), as: UTF8.self).contains("ghp_needle"))
    #expect(!String(decoding: try Posix.read("\(project.path)/.git/config"), as: UTF8.self).contains("ghp_needle"))
    #expect(script.hasPrefix(NSTemporaryDirectory()))
    var info = stat()
    stat((script as NSString).deletingLastPathComponent, &info)
    #expect(info.st_mode & 0o777 == 0o700)
  }

  /// The token is asked for only when the origin would get it.
  @Test func theTokenIsNotAskedForOtherHosts() async throws {
    let golden = try GitGolden()
    let project = golden.url("p")
    try Posix.mkdirs(project.path)
    _ = await ProcessRunner.run(golden.environment.command("git", ["init", "-q"], in: project))
    _ = await ProcessRunner.run(golden.environment.command("git", ["remote", "add", "origin", "https://gitlab.com/o/r.git"], in: project))
    let asked = Mutex(false)
    let auth = try await GitAuth.forOrigin(project: project, environment: golden.environment, token: { asked.withLock { $0 = true }; return "x" })
    #expect(auth.variables.isEmpty)
    #expect(asked.withLock { $0 } == false)
  }
}
