import AppKit
import QuartzHubCore
import SwiftUI

/// The warning while QuartzControl runs (docs/plan.md, „Nebeneinander-Betrieb“): QuartzControl knows
/// no locks across processes, so two apps writing one project can overwrite each other. Shown in a
/// project window, updated when QuartzControl starts or quits; its dev server for this project is
/// named, since QuartzHub reports it and never stops it.
struct CoexistenceBand: View {
  let projectPath: String

  @State private var concerns = Coexistence.Concerns(quartzControlRunning: false, serverPort: nil)

  var body: some View {
    // A stack, not a Group: an empty Group has no view for `.task` to run on, so the first check
    // never happened once the band sat in a VStack above the page.
    VStack(spacing: 0) {
      if !concerns.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          if concerns.quartzControlRunning {
            Text(L10n.t("shell.coexistence.running"))
          }
          if concerns.framesAtRisk {
            Text(L10n.t("shell.coexistence.frames"))
          }
          if let port = concerns.serverPort {
            Text(port.map { L10n.t("shell.coexistence.server", ["port": String($0)]) } ?? L10n.t("shell.coexistence.serverNoPort"))
          }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coexistence.band")
      }
    }
    .task(id: projectPath) { check() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in check() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in check() }
  }

  private func check() {
    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Coexistence.quartzControlBundleID).isEmpty
    // QuartzControl's profile as the launch names it, like the takeover: a test run with
    // `-QHMigrationSource ""` reads no real servers, a measurement can point at a scratch profile.
    let servers = AppProfile.quartzControl.map { Coexistence.foreignServers(profile: $0) } ?? []
    let next = Coexistence.concerns(project: projectPath, quartzControlRunning: running, servers: servers,
                                    hasAuthoredFrames: running && !LayoutFrames.listFrames(project: projectPath).isEmpty)
    if next != concerns {
      concerns = next
      // Appears without the user doing anything: said, not only shown (docs/conventions.md).
      if !next.isEmpty { AccessibilityNotification.Announcement(L10n.t("shell.coexistence.running")).post() }
    }
  }
}
