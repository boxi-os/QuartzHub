import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct LogBufferTests {
  @Test func capsPerProjectAndKind() {
    let buffer = LogBuffer()
    for index in 0..<(LogBuffer.maxLines + 5) {
      buffer.record(.build, LogLine(projectId: "busy", stream: .stdout, text: "\(index)\n"))
    }
    buffer.record(.server, LogLine(projectId: "busy", stream: .stderr, text: "server\n"))
    buffer.record(.server, LogLine(projectId: "quiet", stream: .warn, text: "quiet\n"))
    let busy = buffer.history("busy")
    #expect(busy.build.count == LogBuffer.maxLines)
    #expect(busy.build.first?.text == "5\n" && busy.build.last?.text == "\(LogBuffer.maxLines + 4)\n")
    #expect(busy.server.map(\.text) == ["server\n"])
    #expect(buffer.history("quiet").server.map(\.text) == ["quiet\n"])
    #expect(buffer.history("nobody") == LogBuffer.History())

    buffer.clear("busy", .build)
    #expect(buffer.history("busy").build.isEmpty)
    #expect(buffer.history("busy").server.count == 1)
  }
}
