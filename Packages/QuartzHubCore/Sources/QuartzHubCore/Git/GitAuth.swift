import Darwin
import Foundation

/// Credentials for a push to a project's origin: QuartzHub's GitHub token, handed to git only
/// through `GIT_ASKPASS`. A port of `gitAuth.ts`, measured against it (`scripts/git-golden.mjs`).
///
/// - Not in the remote URL: git writes that into the project's `.git/config` and prints it from
///   `git remote -v`. Not in argv (`-c http.extraHeader=…`): `ps` shows it. The token reaches the
///   helper through the environment of that one call, as git's documentation and the GitHub CLI do.
/// - Only for exactly github.com (`GitHubRemote`) over http(s): another host never got the token,
///   and an ssh remote authenticates with a key.
/// - `GIT_TERMINAL_PROMPT=0`: a git that cannot use the helper would otherwise ask on the terminal
///   and hang behind the closed stdin.
///
/// The token's variable is `QH_GIT_TOKEN` (QuartzControl: `QC_GIT_TOKEN`); the helper is QuartzHub's
/// own, so the name is no format.
public struct GitAuth: Sendable {
  /// QuartzHub's GitHub token, or nil. The connections come with point 8; until then the caller
  /// hands it over.
  public typealias Token = @Sendable () async -> String?

  /// For the command that pushes, on top of its environment.
  public var variables: [String: String]
  let directory: String?

  public static let none = GitAuth(variables: [:], directory: nil)

  /// Removes the helper. Safe to call more than once.
  public func cleanup() {
    guard let directory else { return }
    try? FileManager.default.removeItem(atPath: directory)
  }

  /// Throws only when the helper cannot be written; QuartzControl's call failed then as well,
  /// rather than pushing without the token.
  public static func forOrigin(project: URL, environment: ToolEnvironment, token: Token) async throws -> GitAuth {
    let origin = await ProcessRunner.run(environment.command("git", ["remote", "get-url", "origin"], in: project))
    guard origin.success, GitHubRemote.parse(origin.stdout) != nil else { return .none }
    guard JSText.test(JS.trim(origin.stdout), #"\Ahttps?://"#) else { return .none }
    guard let token = await token(), !token.isEmpty else { return .none }

    var template = Array("\(NSTemporaryDirectory())qh-git-XXXXXX".utf8CString)
    guard let made = mkdtemp(&template) else { throw Posix.error("mkdtemp", String(cString: template)) }
    let directory = String(cString: made)
    let script = "\(directory)/askpass.sh"
    // git calls the helper once per prompt with the prompt as $1; GitHub takes any user name with a
    // token, so it is the literal x-access-token rather than the login looked up.
    let body = "#!/bin/sh\ncase \"$1\" in\n  *[Uu]sername*) printf %s \"x-access-token\" ;;\n  *) printf %s \"$QH_GIT_TOKEN\" ;;\nesac\n"
    do {
      try Posix.write(script, Data(body.utf8))
      guard chmod(script, 0o700) == 0 else { throw Posix.error("chmod", script) }
    } catch {
      try? FileManager.default.removeItem(atPath: directory)
      throw error
    }
    return GitAuth(variables: ["GIT_ASKPASS": script, "QH_GIT_TOKEN": token, "GIT_TERMINAL_PROMPT": "0"], directory: directory)
  }
}
