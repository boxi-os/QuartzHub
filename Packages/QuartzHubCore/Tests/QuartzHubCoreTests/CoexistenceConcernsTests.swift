import Foundation
import Testing
@testable import QuartzHubCore

@Suite struct CoexistenceConcernsTests {
  let servers = [
    Coexistence.ForeignServer(projectId: "a", projectPath: "/p/G\u{E4}rten", pid: 10, port: 8080),
    Coexistence.ForeignServer(projectId: "b", projectPath: "/p/Andere", pid: 11, port: nil),
  ]

  @Test func onlyThisProjectsServer() {
    let mine = Coexistence.concerns(project: "/p/Ga\u{308}rten", quartzControlRunning: false, servers: servers)
    #expect(mine.serverPort == .some(8080) && !mine.isEmpty)
    let none = Coexistence.concerns(project: "/p/Dritte", quartzControlRunning: false, servers: servers)
    #expect(none.isEmpty)
    let unknownPort = Coexistence.concerns(project: "/p/Andere", quartzControlRunning: true, servers: servers)
    #expect(unknownPort.serverPort == .some(nil) && unknownPort.quartzControlRunning)
  }
}
