import QuartzHubCore
import SwiftUI

// The pieces a page's grouped form is made of (first on the Übersicht): a section's heading with
// its state, the one value it leads with, notes under it, and the clock of a running build.

struct TrailingIcon: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 3) {
      configuration.title
      configuration.icon.imageScale(.small)
    }
  }
}

/// A state in a word, with a dot of its colour: the word carries it, the colour only repeats it.
struct StateBadge: View {
  let text: String
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
      Text(text)
    }
  }
}

/// The one number or name a section leads with, and its muted half on the same line ("von 21 aktiv").
struct Metric: View {
  let text: String
  var note: String?
  var muted = false
  var tint: Color?

  init(_ text: String, note: String? = nil, muted: Bool = false, tint: Color? = nil) {
    self.text = text
    self.note = note
    self.muted = muted
    self.tint = tint
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(text).font(.title3.weight(.semibold)).monospacedDigit()
        .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint ?? .primary))
      if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
    }
    .accessibilityElement(children: .combine)
  }
}

/// A section's heading: the symbol of the page it belongs to, its name, and a state at the end.
struct SectionHeader<Badge: View>: View {
  let title: String
  let symbol: String
  @ViewBuilder var badge: () -> Badge

  var body: some View {
    HStack {
      Label(title, systemImage: symbol)
      Spacer()
      badge().font(.callout).foregroundStyle(.secondary)
    }
  }
}

struct Note: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View { Text(text).font(.callout).foregroundStyle(.secondary) }
}

/// "Build läuft seit 0:42 · schreibt die Seiten" (QuartzControl's `BuildActivityLine`), ticking
/// once a second. Not announced: a line that changes every second would be read every second.
struct ActivityLine: View {
  let activity: BuildActivity

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      HStack(spacing: 6) {
        ProgressView().controlSize(.mini)
        Text(Self.kind(activity.kind, time: Formats.elapsed(since: activity.startedAt, now: context.date)))
          + Text(" · " + Self.phase(activity.phase)).foregroundStyle(.secondary)
      }
      .font(.callout)
    }
  }

  static func kind(_ kind: BuildActivity.Kind, time: String) -> String {
    switch kind {
    case .build: L10n.t("buildActivity.kind.build", ["time": time])
    case .serve: L10n.t("buildActivity.kind.serve", ["time": time])
    case .rebuild: L10n.t("buildActivity.kind.rebuild", ["time": time])
    }
  }

  static func phase(_ phase: BuildActivity.Phase) -> String {
    switch phase {
    case .preparing: L10n.t("buildActivity.phase.preparing")
    case .parsing: L10n.t("buildActivity.phase.parsing")
    case .emitting: L10n.t("buildActivity.phase.emitting")
    }
  }
}

/// A dev server's state in a word (`common.serverState.*`).
enum ServerStateText {
  static func text(_ state: BuildService.ServerStatus.State) -> String {
    switch state {
    case .stopped: L10n.t("common.serverState.stopped")
    case .starting: L10n.t("common.serverState.starting")
    case .running: L10n.t("common.serverState.running")
    case .stopping: L10n.t("common.serverState.stopping")
    case .error: L10n.t("common.serverState.error")
    }
  }
}
