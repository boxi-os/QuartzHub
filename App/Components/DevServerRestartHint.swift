import QuartzHubCore
import SwiftUI

/// QuartzControl's `DevServerRestartHint`: after a write the running dev server cannot pick up (an
/// edited frame, new breakpoint widths) the sentence and a restart, and only while a server runs:
/// nothing running means nothing to say, the next build reads the files anyway. A prompt rather
/// than an automatic restart, because a frame is saved many times while it is being built.
///
/// The Layout page said the sentence after every save of a frame, in the toolbar right after
/// „Gespeichert“, and without a server running claimed one ("Der laufende Dev-Server …", measured
/// 2026-11-10).
struct DevServerRestartHint: View {
  let project: ProjectContext
  /// Whether the last write needs one; the caller decides that, this view whether there is a server.
  var show: Bool

  @State private var restarting = false
  @State private var restarted = false
  @State private var error: String?

  var body: some View {
    let running = BuildMonitor.shared.status(project.id).state == .running
    Group {
      if show, restarted {
        Text(L10n.t("devServer.restarted")).font(.caption).foregroundStyle(.green)
      } else if show, running || restarting {
        HStack(spacing: 8) {
          Text(L10n.t("devServer.staleHint")).font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
          Button(restarting ? L10n.t("devServer.restarting") : L10n.t("devServer.restart"), action: restart)
            .disabled(restarting)
          if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .accessibilityElement(children: .contain)
      }
    }
    // A new save is a new question: the previous answer ("neu gestartet") must not stand for it.
    .onChange(of: show) {
      if !show {
        restarted = false
        error = nil
      }
    }
  }

  private func restart() {
    restarting = true
    error = nil
    let project = project
    Task {
      let status = await AppServices.shared.builds.restartServer(projectId: project.id, project: project.path)
      restarting = false
      if status.state == .error {
        error = status.error
      } else {
        restarted = true
        Announce.post(L10n.t("devServer.restarted"))
      }
    }
  }
}
