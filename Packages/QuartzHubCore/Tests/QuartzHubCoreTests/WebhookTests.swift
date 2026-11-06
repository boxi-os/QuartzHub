import Foundation
import Synchronization
import Testing
@testable import QuartzHubCore

/// Answers the webhook's POST from a case of `Fixtures/webhook/cases.json`.
final class HookNet: URLProtocol, @unchecked Sendable {
  struct State {
    var answer: JSONValue = .null
    var requests: [JSONValue] = []
  }

  static let state = Mutex(State())

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HookNet.self]
    return configuration
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var body = Data()
    if let stream = request.httpBodyStream {
      stream.open()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(buffer, count: count)
      }
      stream.close()
    } else if let given = request.httpBody {
      body = given
    }
    let answer = Self.state.withLock { state in
      state.requests.append(.object(JSONObject([
        ("url", .string(request.url!.absoluteString)), ("method", .string(request.httpMethod ?? "")),
        ("contentType", request.value(forHTTPHeaderField: "content-type").map(JSONValue.string) ?? .null),
        ("body", .string(String(decoding: body, as: UTF8.self)))
      ])))
      return state.answer
    }
    if answer["timeout"] == .bool(true) { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
    if answer["network"] == .bool(true) { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
    let response = HTTPURLResponse(url: request.url!, statusCode: Int(answer["status"]!.numberValue!), httpVersion: "HTTP/1.1", headerFields: [:])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(answer["body"]!.stringValue!.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

/// Against QuartzControl's own deploy/webhook.ts with a scripted fetch (`scripts/webhook-golden.mjs`):
/// 17 cases, each with the request, the answer and the progress events.
@Suite(.serialized) struct WebhookTests {
  static let golden: JSONValue = try! JSJSON.parse(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/webhook/cases.json")))

  final class Events: Sendable {
    let items = Mutex<[JSONValue]>([])
  }

  @Test func answersAsQuartzControl() async throws {
    let cases = Self.golden["cases"]!.arrayValue!
    #expect(cases.count == 17)
    let adapter = WebhookAdapter(configuration: HookNet.configuration)
    let target = PublishTarget(object: JSONObject([("id", .string("t")), ("name", .string("Hook")),
                                                   ("destination", .object(JSONObject([("type", .string("webhook"))])))]))
    for item in cases {
      let name = item["name"]!.stringValue!
      HookNet.state.withLock { $0 = HookNet.State(answer: item["answer"] ?? .null) }
      let events = Events()
      var context = DeployContext(project: "/p", target: target, buildDir: "/b", secret: item["secret"]?.stringValue)
      context.progress = { processed, total, file in
        events.items.withLock {
          $0.append(.object(JSONObject([("processed", .number(Double(processed))), ("total", .number(Double(total))),
                                        ("currentFile", file.map(JSONValue.string) ?? .null)])))
        }
      }
      let result = try await adapter.run(context, excluding: [])
      let got = JSJSON.compact(.object(JSONObject([("success", .bool(result.success)), ("output", .string(result.output))])))
      let want = JSJSON.compact(GoldenText.localize(item["result"]!))
      #expect(got == want, "\(name): \(got)\nvs \(want)")
      // The credentials case never leaves the machine in either app.
      let requests = HookNet.state.withLock { $0.requests }
      let expected = item["answer"]?["real"] == .bool(true) ? [] : item["requests"]!.arrayValue!
      #expect(JSJSON.compact(.array(requests)) == JSJSON.compact(.array(expected)), "\(name): requests \(JSJSON.compact(.array(requests)))")
      #expect(JSJSON.compact(.array(events.items.withLock { $0 })) == JSJSON.compact(item["events"]!), "\(name): events")
    }
    #expect(try await adapter.preview(DeployContext(project: "/p", target: target, buildDir: "/b")).isEmpty)
  }
}
