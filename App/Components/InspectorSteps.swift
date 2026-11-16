import QuartzHubCore
import SwiftUI

/// One step as the list in `InspectorSteps` shows it.
struct InspectorStep: Identifiable, Equatable {
  let id: String
  let title: String
  /// The answers before make it do nothing: said with a word, still reachable.
  var noEffect = false
}

/// A setup in steps, in the inspector (docs/plan-assistenten.md). Every step writes at once, as the
/// editors always did, so the preview below follows each one; this only orders the questions.
///
/// Above: "Schritt n von m · Titel" as a fold over the steps, each one a button. Then the step's
/// own sections, then Zurück / Weiter. In a new entry's first run the steps already seen have a
/// check mark, the list stays open, the last step ends the run with „Fertig“, and the run can be
/// cancelled. An existing entry shows the same steps without either.
///
/// It renders `Section`s and so belongs in a grouped `Form`.
struct InspectorSteps<Content: View>: View {
  let steps: [InspectorStep]
  @Binding var current: String
  var firstRun = false
  var visited: Set<String> = []
  var finish: () -> Void = {}
  var cancel: (() -> Void)?
  @ViewBuilder let content: (InspectorStep) -> Content

  @State private var listOpen: Bool?

  private var index: Int { steps.firstIndex { $0.id == current } ?? 0 }

  var body: some View {
    let index = index
    if steps.indices.contains(index) {
      let step = steps[index]
      Section {
        Fold(isExpanded: Binding(get: { listOpen ?? firstRun }, set: { listOpen = $0 })) {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { n, item in row(item, n: n) }
          }
          .padding(.top, 4)
        } label: {
          Text(L10n.t("inspectorSteps.heading", ["n": String(index + 1), "count": String(steps.count), "title": step.title]))
            .fontWeight(.semibold)
            .accessibilityIdentifier("steps.heading")
        }
      }
      content(step)
      Section {
        HStack {
          Button(L10n.t("common.back")) { go(index - 1) }
            .disabled(index == 0)
            .accessibilityIdentifier("steps.back")
          Spacer()
          if index < steps.count - 1 {
            Button(L10n.t("inspectorSteps.next")) { go(index + 1) }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("steps.next")
          } else if firstRun {
            Button(L10n.t("inspectorSteps.done"), action: finish)
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("steps.done")
          }
        }
        // A row of its own: beside Zurück and Weiter the inspector's width cut it off.
        if firstRun, let cancel {
          Button(L10n.t("inspectorSteps.cancel"), action: cancel)
            .accessibilityIdentifier("steps.cancel")
        }
      }
      .focusedSceneValue(\.setupSteps, SetupStepsAction(canBack: index > 0, canForward: index < steps.count - 1) { go(index + $0) })
    }
  }

  private func row(_ item: InspectorStep, n: Int) -> some View {
    let isCurrent = item.id == current
    let done = firstRun && visited.contains(item.id) && !isCurrent
    let symbol = isCurrent ? "circle.inset.filled" : done ? "checkmark.circle.fill" : "circle"
    return Button { go(n) } label: {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .foregroundStyle(isCurrent || done ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
          .accessibilityHidden(true)
        Text(verbatim: "\(n + 1). \(item.title)")
          .fontWeight(isCurrent ? .semibold : .regular)
          .foregroundStyle(item.noEffect && !isCurrent ? .secondary : .primary)
        Spacer()
        if item.noEffect { WordBadge(text: L10n.t("pluginOptions.noEffect")) }
      }
      .padding(.vertical, 3)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityValue(isCurrent ? L10n.t("inspectorSteps.stateCurrent") : done ? L10n.t("inspectorSteps.stateDone") : "")
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
    .accessibilityIdentifier("steps.step.\(item.id)")
  }

  private func go(_ n: Int) {
    guard steps.indices.contains(n), steps[n].id != current else { return }
    current = steps[n].id
    Announce.post(L10n.t("inspectorSteps.announce", ["n": String(n + 1), "count": String(steps.count), "title": steps[n].title]))
  }
}

/// An entry ➕ just created, while the inspector sets it up for the first time.
struct SetupRun: Equatable {
  /// The new entry's class, its key while the run lasts.
  let className: String
  /// `plugins:` before ➕: cancelling puts back the priorities the placement step renumbered.
  let before: [PluginEntry]
}

/// Vorheriger / Nächster Schritt in Gehe zu (⌥⌘← ⌥⌘→), while a setup in steps is in the inspector;
/// ⌘[ ⌘] stay the window's history.
struct SetupStepsAction {
  let canBack: Bool
  let canForward: Bool
  let step: (Int) -> Void
}

extension FocusedValues {
  @Entry var setupSteps: SetupStepsAction?
}
