import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Gives GitHub's answers of one step in order and writes down every request.
final class GitHubNet: URLProtocol, @unchecked Sendable {
  struct State {
    var answers: [JSONValue] = []
    var requests: [JSONValue] = []
  }

  static let state = Mutex(State())

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GitHubNet.self]
    return configuration
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var body: Data?
    if let stream = request.httpBodyStream {
      var data = Data()
      stream.open()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
      }
      stream.close()
      body = data
    } else {
      body = request.httpBody
    }
    let header = { (name: String) in self.request.value(forHTTPHeaderField: name).map(JSONValue.string) ?? .null }
    let answer: JSONValue? = Self.state.withLock { state in
      state.requests.append(.object(JSONObject([
        ("method", .string(request.httpMethod ?? "")), ("url", .string(request.url!.absoluteString)), ("accept", header("accept")),
        ("version", header("x-github-api-version")), ("authorization", header("authorization")), ("contentType", header("content-type")),
        ("body", body.map { .string(String(decoding: $0, as: UTF8.self)) } ?? .null)
      ])))
      return state.answers.isEmpty ? nil : state.answers.removeFirst()
    }
    guard let answer else { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
    if answer["timeout"] == .bool(true) { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
    if answer["network"] == .bool(true) { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
    let response = HTTPURLResponse(url: request.url!, statusCode: Int(answer["status"]!.numberValue!), httpVersion: "HTTP/1.1", headerFields: [:])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data((answer["body"]?.stringValue ?? "").utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

/// Against QuartzControl's own githubService.ts with a scripted fetch (`scripts/github-golden.mjs`):
/// 33 calls, each with its answer, every request (method, URL, headers, body) and the origins of
/// the three projects afterwards.
@Suite(.serialized) struct GitHubAPITests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/github/steps.json")))

  final class Token: Sendable {
    let value = Mutex<JSONValue>(.null)
  }

  @Test func answersAsQuartzControl() async throws {
    let steps = Self.golden["steps"]!.arrayValue!
    #expect(steps.count == 33)
    let root = TemplatePackageTests.realpath(TestFolder.make("qh-github"))
    defer { try? FileManager.default.removeItem(atPath: root) }
    try Posix.write("\(root)/gitconfig", Data())
    let environment = ToolEnvironment(
      base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "\(root)/gitconfig", "GIT_CONFIG_NOSYSTEM": "1"],
      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system, runtime: .repository, git: nil,
      bundledGitFailure: nil)
    func git(_ args: [String], _ dir: String) async -> CommandResult { await ProcessRunner.run(environment.command("git", args, in: dir)) }
    let projects = ["none": "\(root)/ohne Origin", "github": "\(root)/Gärten-Ü", "gitlab": "\(root)/gitlab"]
    for path in projects.values {
      try Posix.mkdirs(path)
      _ = await git(["init", "-q"], path)
    }
    _ = await git(["remote", "add", "origin", "https://github.com/boxi-os/site.git"], projects["github"]!)
    _ = await git(["remote", "add", "origin", "git@gitlab.com:boxi/site.git"], projects["gitlab"]!)

    let token = Token()
    let api = GitHubAPI(environment: environment, token: {
      let given = token.value.withLock { $0 }
      if given["unreadable"] == .bool(true) { throw PublishFailure(L10n.t("main.secretStorageUnreadableMac")) }
      return given["value"]?.stringValue
    }, configuration: GitHubNet.configuration)

    for step in steps {
      let name = step["name"]!.stringValue!
      token.value.withLock { $0 = step["token"]! }
      GitHubNet.state.withLock { $0 = GitHubNet.State(answers: step["scripted"]!.arrayValue!) }
      let args = step["args"]!.arrayValue!
      let project = args[0].stringValue.flatMap { projects[$0] } ?? root
      var actual: JSONValue
      do {
        switch step["call"]!.stringValue! {
        case "viewer":
          actual = try await api.viewer().map { account in
            var object = JSONObject([("login", .string(account.login))])
            object["name"] = account.name.map(JSONValue.string)
            return .object(object)
          } ?? .null
        case "originRepo":
          actual = await api.originRepo(project).map {
            .object(JSONObject([("owner", .string($0.owner)), ("repo", .string($0.repo)), ("htmlUrl", .string($0.htmlUrl))]))
          } ?? .null
        case "createRepo":
          let input = args[1]
          let result = try await api.createRepo(project, name: input["name"]!.stringValue!, isPrivate: input["private"]!.boolValue!,
                                                description: input["description"]?.stringValue)
          actual = .object(JSONObject([("success", .bool(result.success)), ("output", .string(result.output))]))
        case "pagesInfo": actual = try await api.pagesInfo(project)?.json ?? .null
        case "configurePages":
          let input = args[1]
          var cname: String?? = nil
          if let given = input["cname"] { cname = .some(given.stringValue) }
          let result = try await api.configurePages(project, branch: input["branch"]!.stringValue!, cname: cname,
                                                    httpsEnforced: input["httpsEnforced"]?.boolValue)
          actual = .object(JSONObject([("success", .bool(result.success)), ("output", .string(result.output))]))
        default:
          Issue.record("unknown call"); continue
        }
        actual = .object(JSONObject([("ok", actual)]))
      } catch {
        actual = .object(JSONObject([("error", .string(String(describing: error)))]))
      }
      let want = JSJSON.compact(GoldenText.localize(step["result"]!))
      #expect(JSJSON.compact(actual) == want, "\(name): \(JSJSON.compact(actual))\nvs \(want)")
      let requests = GitHubNet.state.withLock { $0.requests }
      #expect(JSJSON.compact(.array(requests)) == JSJSON.compact(step["requests"]!), "\(name): requests \(JSJSON.compact(.array(requests)))")
      let origins = step["origins"]!.objectValue!
      for key in origins.keys {
        let got = JS.trim(await git(["remote", "get-url", "origin"], projects[key]!).stdout)
        #expect((got.isEmpty ? JSONValue.null : .string(got)) == origins[key]!, "\(name): origin of \(key) \(got)")
      }
    }
  }

  /// Not in QuartzControl's golden file, which has its mistake (review 2026-11-13, handbook, M2):
  /// a new site with a domain sends the domain in a PUT after the POST, and says so; a refused PUT
  /// is a failure that still names the created site.
  @Test func aNewSiteKeepsItsDomain() async throws {
    let root = TemplatePackageTests.realpath(TestFolder.make("qh-github-domain"))
    defer { try? FileManager.default.removeItem(atPath: root) }
    try Posix.write("\(root)/gitconfig", Data())
    let environment = ToolEnvironment(
      base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "\(root)/gitconfig", "GIT_CONFIG_NOSYSTEM": "1"],
      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []), nodeMode: .system, runtime: .repository, git: nil,
      bundledGitFailure: nil)
    let project = "\(root)/Gärten-Ü"
    try Posix.mkdirs(project)
    _ = await ProcessRunner.run(environment.command("git", ["init", "-q"], in: project))
    _ = await ProcessRunner.run(environment.command("git", ["remote", "add", "origin", "https://github.com/boxi-os/site.git"], in: project))
    let api = GitHubAPI(environment: environment, token: { "ghp_token" }, configuration: GitHubNet.configuration)

    GitHubNet.state.withLock { $0 = GitHubNet.State(answers: [
      .object(JSONObject([("status", .number(404)), ("body", .string("{}"))])),
      .object(JSONObject([("status", .number(201)), ("body", .string("{}"))])),
      .object(JSONObject([("status", .number(204))])),
    ]) }
    let result = try await api.configurePages(project, branch: "gh-pages", cname: .some("blog.example.org"))
    let requests = GitHubNet.state.withLock { $0.requests }
    #expect(result.success)
    #expect(requests.map { "\($0["method"]!.stringValue!) \($0["body"]?.stringValue ?? "")" } == [
      "GET ", #"POST {"source":{"branch":"gh-pages","path":"/"}}"#,
      #"PUT {"source":{"branch":"gh-pages","path":"/"},"cname":"blog.example.org"}"#,
    ])
    #expect(result.output.contains(L10n.t("main.githubDomainSet", ["domain": "blog.example.org"])), "\(result.output)")

    GitHubNet.state.withLock { $0 = GitHubNet.State(answers: [
      .object(JSONObject([("status", .number(404)), ("body", .string("{}"))])),
      .object(JSONObject([("status", .number(201)), ("body", .string("{}"))])),
      .object(JSONObject([("status", .number(422)), ("body", .string(#"{"message":"The CNAME is already taken"}"#))])),
    ]) }
    let refused = try await api.configurePages(project, branch: "gh-pages", cname: .some("blog.example.org"))
    #expect(!refused.success)
    #expect(refused.output.contains(L10n.t("main.githubPagesCreated", ["branch": "gh-pages"])) && refused.output.contains("The CNAME is already taken"))
  }
}
