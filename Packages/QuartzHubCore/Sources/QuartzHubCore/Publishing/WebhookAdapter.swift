import Foundation

/// A webhook asks someone else to publish (`deploy/webhook.ts`): Netlify, Cloudflare Pages, Vercel
/// and every CI runner take "POST to this URL", and the URL itself is the credential, its path is
/// the token. Stored in the Keychain, never shown; only its origin is printed.
///
/// Printing only the origin is not enough: the provider echoes the rest back (webhook.site answers
/// with `…/#!/edit/<id>`, the same token in another URL shape), so every part of the credential of
/// eight characters or more is blanked out of what comes back, by plain search, not a regex.
///
/// Two things QuartzControl's `fetch` gave that URLSession does not, each said here: the status
/// text is the standard one for the code (RFC 9110), not the server's own phrase (HTTP/2 sends
/// none, where Node's was empty); a transport failure reads "TypeError: fetch failed", as Node's
/// `String(err)` did, without the cause.
public struct WebhookAdapter: DeployAdapter {
  public static let timeout: Duration = .seconds(30)
  /// Enough to see what the provider said, not so much that an HTML page fills the panel.
  static let maxBody = 2000
  /// Leaves ordinary path words ("hooks", "build") alone; a credential shorter is none.
  static let minSecretSegment = 8

  let session: URLSession
  let timeout: Duration

  public init(configuration: URLSessionConfiguration = .ephemeral, timeout: Duration = WebhookAdapter.timeout) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
    configuration.timeoutIntervalForResource = configuration.timeoutIntervalForRequest
    session = URLSession(configuration: configuration)
    self.timeout = timeout
  }

  static func redact(_ text: String, _ secret: WebURL.Parts) -> String {
    let parts = (JSText.split(secret.pathname, "/") + secret.searchParamValues
      + [JSText.replaceAll(secret.hash, #"\A#"#, with: ""), secret.username, secret.password])
      .filter { JSText.length($0) >= minSecretSegment }
    var out = text
    for part in parts { out = JSText.split(out, part).joined(separator: L10n.t("main.webhookRedacted")) }
    return out
  }

  /// Nothing local to compare: the page reads an empty diff here as "no file list", not as "all
  /// up to date".
  public func preview(_ context: DeployContext) async throws -> [DeployDiffEntry] { [] }

  public func run(_ context: DeployContext, excluding excludePaths: [String]) async throws -> DeployResult {
    guard context.destination["type"] == .string("webhook") else { throw PublishFailure(L10n.t("main.deployWrongType", ["adapter": "Webhook"])) }
    guard let secret = context.secret, !secret.isEmpty else { return DeployResult(success: false, output: L10n.t("main.webhookNoUrl")) }
    let parsed = WebURL(secret)
    // A host WebURL leaves to Node is refused as Node's parse failure is (`WebURL`).
    if parsed == .invalid || parsed == .unsupported { return DeployResult(success: false, output: L10n.t("main.webhookInvalidUrl")) }
    // Checked again where the credential goes on the wire.
    guard let url = parsed.parts, url.protocol == "https:" else { return DeployResult(success: false, output: L10n.t("main.webhookHttpsOnly")) }
    let failed = { (reason: String) in
      DeployResult(success: false, output: "\(L10n.t("main.webhookFailed", ["origin": url.origin]))\n\(reason)")
    }
    context.progress(0, 1, url.host)
    // fetch refuses an address with a user part before anything goes out, after the progress.
    if !url.username.isEmpty || !url.password.isEmpty {
      return failed(Self.redact("TypeError: Request cannot be constructed from a URL that includes credentials: \(url.href)", url))
    }
    guard let address = URL(string: url.href) else { return failed("TypeError: fetch failed") } // not a file path
    var request = URLRequest(url: address)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = Data("{}".utf8)
    let data: Data, response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError where error.code == .timedOut {
      return failed(L10n.t("main.webhookTimeout", ["seconds": String(Int(timeout.components.seconds))]))
    } catch {
      return failed(Self.redact("TypeError: fetch failed", url))
    }
    guard let http = response as? HTTPURLResponse else { return failed("TypeError: fetch failed") }
    let body = JSText.slice(Self.redact(String(decoding: data, as: UTF8.self), url), 0, Self.maxBody)
    context.progress(1, 1, url.host)
    // The origin, never the whole URL: this output is shown and copied around.
    let line = "POST \(url.origin) → \(http.statusCode) \(Self.reason(http.statusCode))\n"
    return DeployResult(success: (200...299).contains(http.statusCode), output: body.isEmpty ? line : "\(line)\n\(body)")
  }

  /// RFC 9110's reason phrases, as an HTTP/1.1 server normally sends them.
  static func reason(_ code: Int) -> String {
    let phrases: [Int: String] = [
      200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content",
      206: "Partial Content", 300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified",
      307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 402: "Payment Required",
      403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required",
      408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Content Too Large",
      414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 421: "Misdirected Request",
      422: "Unprocessable Content", 426: "Upgrade Required", 429: "Too Many Requests", 500: "Internal Server Error", 501: "Not Implemented",
      502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported"
    ]
    return phrases[code] ?? ""
  }
}
