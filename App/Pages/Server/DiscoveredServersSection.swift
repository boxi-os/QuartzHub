import QuartzHubCore
import SwiftUI

/// Every Quartz dev server on this Mac, not only QuartzHub's (QuartzControl's `DiscoveredServers`):
/// a server left running in a terminal holds 8080, and the start above then fails on a port that is
/// taken for no visible reason. A server QuartzHub did not start is listed but never stopped without
/// asking, because whoever started it may still be using it.
///
/// Scanned when the section appears, when the window becomes key again (not on a timer: a `ps`
/// every few seconds for a list that changes a few times a day), and when any server of QuartzHub's
/// comes to rest; after a stop once more a second later, because the child holding the port can
/// outlive npx by a moment. Only the latest scan writes.
struct DiscoveredServersSection: View {
  let ports: [Int]
  /// After a stop: the page asks the service for its own server's state again.
  let changed: () -> Void

  @State private var model = ServerDiscoveryModel()
  @State private var monitor = BuildMonitor.shared
  @State private var confirming: ServerScan.Server?
  @Environment(\.controlActiveState) private var activeState

  var body: some View {
    Section {
      Text(model.summary)
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("server.discovery.status")
      ForEach(model.discovery?.servers ?? [], id: \.pid) { server in
        ServerRow(server: server, stopping: model.stopping == server.pid) { confirming = server }
      }
      if let occupied = model.discovery?.occupiedPorts, !occupied.isEmpty {
        Label(L10n.t("buildServer.discovery.portTaken", ["ports": occupied.map(String.init).joined(separator: ", ")]),
              systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.orange)
      }
      if model.discovery?.servers.contains(where: { !$0.ownedByApp }) == true {
        Label(L10n.t("buildServer.discovery.warning"), systemImage: "info.circle")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    } header: {
      SectionHeader(title: L10n.t("buildServer.discovery.title"), symbol: "server.rack") {
        HStack(spacing: 8) {
          if model.discovery?.state == .ok { Text(String(model.discovery?.servers.count ?? 0)) }
          Button {
            Task { await model.scan(ports: ports) }
          } label: {
            Label(L10n.t("buildServer.discovery.refresh"), systemImage: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
          .disabled(model.scanning)
        }
      }
    }
    .task(id: ports) { await model.scan(ports: ports) }
    .onChange(of: activeState) { _, state in
      if state == .key { Task { await model.scan(ports: ports) } }
    }
    .onChange(of: monitor.settledServers) {
      Task {
        await model.scan(ports: ports)
        guard monitor.lastSettled == .stopped else { return }
        try? await Task.sleep(for: .seconds(1))
        await model.scan(ports: ports)
      }
    }
    .alert(confirmParts.title, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
           presenting: confirming) { server in
      Button(L10n.t("common.cancel"), role: .cancel) {}
      Button(L10n.t("buildServer.discovery.stopServer"), role: .destructive) {
        Task {
          await model.stop(server, ports: ports)
          changed()
        }
      }
    } message: { _ in
      Text(confirmParts.message)
    }
  }

  /// QuartzControl's question is one text, the question and a paragraph: here the question is
  /// the alert's title and the paragraph its message.
  private var confirmParts: (title: String, message: String) {
    guard let server = confirming else { return ("", "") }
    let values = ["name": server.projectName ?? server.cwd ?? String(server.port), "port": String(server.port)]
    let text = server.ownedByApp ? L10n.t("buildServer.discovery.confirmOwn", values) : L10n.t("buildServer.discovery.confirmForeign", values)
    guard let split = text.range(of: "\n\n") else { return (text, "") }
    return (String(text[..<split.lowerBound]), String(text[split.upperBound...]))
  }
}

private struct ServerRow: View {
  let server: ServerScan.Server
  let stopping: Bool
  let stop: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          if let url = URL(string: "http://localhost:\(server.port)") {
            Link(destination: url) {
              // A String, not a literal: an interpolated literal is a LocalizedStringKey, and its
              // number came out as "8.080" (seen in the running app).
              Label("localhost:" + String(server.port), systemImage: "arrow.up.right.square").fontWeight(.semibold)
            }
            .help(L10n.t("common.openInBrowser"))
          }
          StateBadge(text: server.ownedByApp ? L10n.t("buildServer.discovery.fromApp") : L10n.t("buildServer.discovery.fromOutside"),
                     color: server.ownedByApp ? .green : .orange)
            .font(.callout)
        }
        Text(server.projectName ?? server.siteTitle ?? server.cwd ?? L10n.t("buildServer.discovery.unknownProject"))
          .textSelection(.enabled)
        Text(facts).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Button(L10n.t("buildServer.discovery.stopServer"), role: .destructive, action: stop)
        .disabled(stopping)
    }
    .accessibilityElement(children: .contain)
  }

  private var facts: String {
    var facts = "PID \(server.pid)"
    if let ws = server.wsPort { facts += " · " + L10n.t("buildServer.wsPort") + " \(ws)" }
    if let started = server.startedAt {
      facts += " · " + L10n.t("buildServer.startedAgo", ["since": Formats.relative(started) ?? "–"])
    }
    if !server.reachable { facts += " · " + L10n.t("buildServer.discovery.notAnswering") }
    return facts
  }
}

@MainActor @Observable
final class ServerDiscoveryModel {
  var discovery: ServerScan.Result?
  var scanning = false
  var stopping: Int32?
  private var latest = 0

  var summary: String {
    guard let discovery else { return L10n.t("buildServer.discovery.scanning") }
    let count = discovery.servers.count
    switch discovery.state {
    case .unavailable: return L10n.t("buildServer.discovery.unavailable")
    case .partial: return L10n.t("buildServer.discovery.partial", ["count": String(count)], count: count)
    case .ok: return count == 0 ? L10n.t("buildServer.discovery.none") : L10n.t("buildServer.discovery.found", ["count": String(count)], count: count)
    }
  }

  func scan(ports: [Int]) async {
    latest += 1
    let mine = latest
    scanning = true
    let projects = ProjectStore(profile: AppProfile.own).list()
    let owned = await AppServices.shared.builds.ownedServerPids()
    let found = await ServerScan.discover(ports: ports, projects: projects, owned: owned)
    guard mine == latest else { return }
    // Said when it changes, not read as part of the page: the scan's answer arrives later.
    if discovery != nil, found.servers.count != discovery?.servers.count { Announce.post(Self.summary(found)) }
    discovery = found
    scanning = false
  }

  private static func summary(_ result: ServerScan.Result) -> String {
    let model = ServerDiscoveryModel()
    model.discovery = result
    return model.summary
  }

  func stop(_ server: ServerScan.Server, ports: [Int]) async {
    stopping = server.pid
    let builds = AppServices.shared.builds
    let owned = await builds.ownedServerPids()
    let result = await ServerScan.stop(pid: server.pid, owned: owned) { await builds.stopServer($0) }
    Announce.post(result.stopped
      ? L10n.t("buildServer.discovery.stopped", ["port": String(server.port)])
      : L10n.t("buildServer.discovery.stopFailed", ["port": String(server.port)]))
    stopping = nil
    await scan(ports: ports)
  }
}
