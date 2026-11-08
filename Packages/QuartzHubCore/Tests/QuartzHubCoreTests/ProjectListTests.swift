import Foundation
import Testing
@testable import QuartzHubCore

/// The steps around the store that QuartzControl's `projects:*` handlers took together.
@Suite struct ProjectListTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  func list() -> (ProjectList, MemorySecrets) {
    let profile = ProfileDirectory("\(scratch.path)/Profil")
    let secrets = MemorySecrets()
    let environment = ToolEnvironment(base: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"],
                                      hostPath: HostPath(entries: ["/usr/bin", "/bin"], source: .inherited, added: []),
                                      nodeMode: .system, runtime: .repository, git: nil, bundledGitFailure: nil)
    let builds = BuildService(logs: LogBuffer(), environment: { environment })
    return (ProjectList(store: ProjectStore(profile: profile), builds: builds,
                        connections: Connections(profile: profile, secrets: secrets), runtime: .repository), secrets)
  }

  /// Removing takes the relay secrets with it and leaves the folder.
  @Test func removeTakesTheRelaySecretsAndLeavesTheFolder() async throws {
    let (list, secrets) = list()
    defer { withExtendedLifetime(secrets) {} }
    let folder = "\(scratch.path)/Gärten-Ü"
    try Posix.mkdirs(folder)
    let entry = try list.store.add(path: folder)
    let other = try list.store.add(path: scratch.path)
    let recipients = JSONObject([("kontakt", .string("a@example.com"))])
    try list.connections.saveRelaySecrets(entry.id, RelaySecretsChange(recipients: recipients))
    try list.connections.saveRelaySecrets(other.id, RelaySecretsChange(recipients: recipients))
    #expect(list.connections.projectsWithRelaySecrets() == [entry.id, other.id])

    try await list.remove(id: entry.id)
    #expect(list.store.list().map(\.id) == [other.id])
    #expect(list.connections.projectsWithRelaySecrets() == [other.id])
    #expect(!list.connections.relaySecretInfo(entry.id).stored)
    #expect(try list.connections.relaySecrets(entry.id) == nil)
    #expect(try list.connections.relaySecrets(other.id) != nil)
    #expect(Posix.exists(folder))
  }

  @Test func openStampsTheEntry() throws {
    let (list, _) = list()
    let entry = try list.store.add(path: scratch.path)
    #expect(entry.lastOpenedAt == nil)
    let now = Date(timeIntervalSince1970: 1_793_000_000.123)
    #expect(try list.open(id: entry.id, now: now)?.lastOpenedAt == JS.isoString(now))
    #expect(try list.open(id: "unbekannt") == nil)
  }

  /// Relocating onto a folder another entry names is refused, and the entry stays where it was.
  @Test func relocateRefusesASecondEntryForOneFolder() async throws {
    let (list, _) = list()
    let a = "\(scratch.path)/A", b = "\(scratch.path)/B"
    try Posix.mkdirs(a)
    try Posix.mkdirs(b)
    let first = try list.store.add(path: a)
    _ = try list.store.add(path: b)
    await #expect(throws: ProjectStore.Failure.alreadyRegistered) { try await list.relocate(id: first.id, to: b) }
    #expect(list.store.project(id: first.id)?.path == a)
    #expect(try await list.relocate(id: first.id, to: "\(scratch.path)/C")?.name == "C")
  }
}
