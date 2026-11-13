import Foundation

/// The two things a branch push cannot do (`githubService.ts`): create a repository and wire it up
/// as "origin", and configure Pages (source branch, custom domain, HTTPS). Everything needs a
/// token with repo scope, the same GitHub connection the marketplaces use.
///
/// A missing token is not thrown: the Pages card reads on its own whenever a GitHub branch target
/// is selected, and a user without a token would get an error for a card they only looked at. It
/// is a 401, which is what GitHub answers a bad token, so every caller's handling covers it; a
/// token that cannot be read is the same 401 with its own sentence.
///
/// A request that fails on the way (no network, the 20 s deadline) is thrown with Node's message
/// ("fetch failed", "The operation was aborted due to timeout"), as QuartzControl let fetch's
/// error through.
public struct GitHubAPI: Sendable {
  public struct Account: Equatable, Sendable {
    public var login: String
    public var name: String?
  }

  public struct RepoRef: Equatable, Sendable {
    public var owner: String
    public var repo: String
    public var htmlUrl: String
  }

  public struct PagesInfo: Equatable, Sendable {
    public var configured: Bool
    public var error: String?
    public var status: JSONValue?
    public var htmlUrl: JSONValue?
    public var cname: JSONValue?
    public var httpsEnforced: JSONValue?
    public var sourceBranch: JSONValue?
    public var sourcePath: JSONValue?

    /// `GithubPagesInfo` as QuartzControl's renderer got it.
    public var json: JSONValue {
      var object = JSONObject([("configured", .bool(configured))])
      object["error"] = error.map(JSONValue.string)
      if configured {
        object["status"] = status
        object["htmlUrl"] = htmlUrl
        object["cname"] = cname
        object["httpsEnforced"] = httpsEnforced
        object["sourceBranch"] = sourceBranch
        object["sourcePath"] = sourcePath
      }
      return .object(object)
    }
  }

  public struct ActionResult: Equatable, Sendable {
    public var success: Bool
    public var output: String
  }

  struct APIResult {
    var status: Int
    var data: JSONValue?
    var message: String?
  }

  public struct RequestFailure: Error, CustomStringConvertible {
    public let description: String
  }

  let base: String
  let session: URLSession
  let token: GitAuth.Token
  let environment: ToolEnvironment

  public init(environment: ToolEnvironment, token: @escaping GitAuth.Token, base: String = "https://api.github.com",
              configuration: URLSessionConfiguration = .ephemeral, timeout: Duration = .seconds(20)) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = Double(timeout.components.seconds)
    configuration.timeoutIntervalForResource = Double(timeout.components.seconds)
    Offline.apply(configuration)
    session = URLSession(configuration: configuration)
    self.base = base
    self.token = token
    self.environment = environment
  }

  func api(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> APIResult {
    let token: String?
    do {
      token = try await self.token()
    } catch {
      return APIResult(status: 401, data: nil, message: PublishFailure.message(of: error))
    }
    guard let token, !token.isEmpty else { return APIResult(status: 401, data: nil, message: L10n.t("main.githubNoToken")) }
    guard let url = URL(string: base + path) else { throw RequestFailure(description: "Invalid URL") } // not a file path
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "x-github-api-version")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "content-type")
      request.httpBody = Data(JSJSON.compact(body).utf8)
    }
    let data: Data, response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError where error.code == .timedOut {
      throw RequestFailure(description: "The operation was aborted due to timeout")
    } catch {
      throw RequestFailure(description: "fetch failed")
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    // A 204 has no body, an error page need not be JSON: the parse may fail.
    let text = String(decoding: data, as: UTF8.self)
    let parsed = text.isEmpty ? nil : try? JSJSON.parse(Data(text.utf8))
    let message = parsed?.objectValue?["message"].map { JS.string($0) }
    return APIResult(status: status, data: parsed == .null ? nil : parsed, message: message)
  }

  static func failure(_ result: APIResult, _ fallback: String) -> ActionResult {
    ActionResult(success: false, output: result.message.map { "\(fallback)\n\(result.status): \($0)" } ?? "\(fallback) (HTTP \(result.status))")
  }

  /// Who the token belongs to, and so whether it works at all.
  public func viewer() async throws -> Account? {
    let result = try await api("/user")
    guard result.status == 200, let data = result.data else { return nil }
    return Account(login: JS.string(data.objectValue?["login"]), name: data.objectValue?["name"]?.stringValue)
  }

  func origin(_ project: String) async -> CommandResult {
    await ProcessRunner.run(environment.command("git", ["remote", "get-url", "origin"], in: project))
  }

  public func originRepo(_ project: String) async -> RepoRef? {
    let result = await origin(project)
    guard result.success, let repo = GitHubRemote.parse(result.stdout) else { return nil }
    return RepoRef(owner: repo.owner, repo: repo.repo, htmlUrl: "https://github.com/\(repo.owner)/\(repo.repo)")
  }

  /// Closes the gap the project creator opens on purpose (a new project has no origin, so a push
  /// can never reach jackyzha0/quartz). The https clone URL goes into the remote, never one with the
  /// token: `git remote -v` prints it, and it would sit in the project's config.
  public func createRepo(_ project: String, name: String, isPrivate: Bool, description: String? = nil) async throws -> ActionResult {
    let existing = await origin(project)
    if existing.success { return ActionResult(success: false, output: L10n.t("main.githubOriginExists", ["remote": JS.trim(existing.stdout)])) }
    var body = JSONObject([("name", .string(name)), ("private", .bool(isPrivate))])
    body["description"] = description.map(JSONValue.string)
    body["auto_init"] = .bool(false)
    let result = try await api("/user/repos", method: "POST", body: .object(body))
    guard result.status == 201, let data = result.data?.objectValue else { return Self.failure(result, L10n.t("main.githubRepoCreateFailed")) }
    let fullName = JS.string(data["full_name"])
    let command = environment.command("git", ["remote", "add", "origin", JS.string(data["clone_url"])], in: project)
    let added = await ProcessRunner.run(command)
    if !added.success {
      return ActionResult(success: false, output: "\(L10n.t("main.githubRemoteSetFailed", ["repo": fullName]))\n\(added.report(for: command))")
    }
    return ActionResult(success: true, output: "\(L10n.t("main.githubRepoCreated", ["repo": fullName]))\n\(JS.string(data["html_url"]))")
  }

  /// nil: the origin is not on github.com at all, a state of its own. 404 is a repo without Pages.
  public func pagesInfo(_ project: String) async throws -> PagesInfo? {
    guard let repo = await originRepo(project) else { return nil }
    let result = try await api("/repos/\(repo.owner)/\(repo.repo)/pages")
    if result.status == 404 { return PagesInfo(configured: false) }
    guard result.status == 200, let data = result.data?.objectValue else {
      return PagesInfo(configured: false, error: result.message ?? "HTTP \(result.status)")
    }
    let source = data["source"]?.objectValue
    return PagesInfo(configured: true, status: data["status"], htmlUrl: data["html_url"], cname: data["cname"],
                     httpsEnforced: data["https_enforced"], sourceBranch: source?["branch"], sourcePath: source?["path"])
  }

  /// A domain set here is stored by GitHub and survives the branch being replaced; a CNAME file on
  /// the branch does not. HTTPS goes as a second request: GitHub can enforce it only once it has a
  /// certificate for the domain, minutes later, and both in one call failed the domain as well.
  /// `cname`: nil leaves it, `.some(nil)` or "" clears it.
  public func configurePages(_ project: String, branch: String, cname: String?? = nil, httpsEnforced: Bool? = nil) async throws -> ActionResult {
    guard let repo = await originRepo(project) else { return ActionResult(success: false, output: L10n.t("main.githubNoGithubOrigin")) }
    let path = "/repos/\(repo.owner)/\(repo.repo)/pages"
    let existing = try await api(path)
    let source = JSONValue.object(JSONObject([("branch", .string(branch)), ("path", .string("/"))]))
    var output = ""
    if existing.status == 404 {
      let created = try await api(path, method: "POST", body: .object(JSONObject([("source", source)])))
      if created.status != 201 { return Self.failure(created, L10n.t("main.githubPagesSetupFailed")) }
      output += "\(L10n.t("main.githubPagesCreated", ["branch": branch]))\n"
      // GitHub's POST takes only the source (docs.github.com/en/rest/pages/pages); the domain goes
      // in a PUT after it. QuartzControl sent none, so a domain typed before the first set-up was
      // lost (review 2026-11-13, handbook, M2; a deviation from its golden file).
      if let domain = cname ?? nil, !domain.isEmpty {
        let named = try await api(path, method: "PUT", body: .object(JSONObject([("source", source), ("cname", .string(domain))])))
        if named.status != 204 {
          let failed = Self.failure(named, L10n.t("main.githubPagesSaveFailed"))
          return ActionResult(success: false, output: output + failed.output)
        }
        output += "\(L10n.t("main.githubDomainSet", ["domain": domain]))\n"
      }
    } else {
      var body = JSONObject([("source", source)])
      if let cname { body["cname"] = (cname ?? "").isEmpty ? .null : .string(cname!) }
      let updated = try await api(path, method: "PUT", body: .object(body))
      if updated.status != 204 { return Self.failure(updated, L10n.t("main.githubPagesSaveFailed")) }
      output += "\(L10n.t("main.githubPagesSourceSet", ["branch": branch]))\n"
      if let cname {
        output += "\((cname ?? "").isEmpty ? L10n.t("main.githubDomainCleared") : L10n.t("main.githubDomainSet", ["domain": cname!]))\n"
      }
    }
    if let httpsEnforced {
      let https = try await api(path, method: "PUT", body: .object(JSONObject([("https_enforced", .bool(httpsEnforced))])))
      output += https.status == 204
        ? "\(L10n.t("main.githubHttpsEnforced", ["state": httpsEnforced ? L10n.t("main.githubOn") : L10n.t("main.githubOff")]))\n"
        : "\(L10n.t("main.githubHttpsPending"))\n\(https.message ?? "")\n"
    }
    return ActionResult(success: true, output: output)
  }
}
