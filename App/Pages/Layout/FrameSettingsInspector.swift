import QuartzHubCore
import SwiftUI

/// The open frame in the inspector while no area is selected: its name, the grid of the chosen
/// breakpoint, width and padding, the track sizes, line names and the breakpoint widths. They stood
/// above the board and pushed it below the window's edge, while the inspector was empty (user test,
/// 2026-11-12); now the board is the middle, and nothing selected means the frame itself, as on a
/// canvas. Every change goes into the draft, like the area's settings.
struct FrameSettingsInspector: View {
  @Bindable var model: LayoutModel
  let breakpoint: String

  var body: some View {
    if let draft = model.draft {
      let layout = FrameView(draft).layout(breakpoint)
      let hasMaxWidth = !(layout.maxWidth ?? "").trimmingCharacters(in: .whitespaces).isEmpty
      Form {
        Section {
          Label(L10n.t("layoutEditor.frameBuilder.framePanelTitle"), systemImage: "rectangle.split.3x3").font(.headline)
          Note(L10n.t("layoutEditor.frameBuilder.inspectorSaves"))
          TextField(L10n.t("layoutEditor.frameBuilder.frameName"), text: Binding(get: { model.draft.map { FrameView($0).frameName } ?? "" }, set: { name in
            guard var object = model.draft?.objectValue else { return }
            object["frameName"] = .string(name)
            set(.object(object))
          }), prompt: Text(L10n.t("layoutEditor.templateCustomPlaceholder")))
          .accessibilityIdentifier("layout.frames.name")
          Note(L10n.t("layoutEditor.frameBuilder.framePanelHint"))
        }
        Section(L10n.t("layoutEditor.frameBuilder.inspectorGrid", ["breakpoint": LayoutWords.breakpoint(breakpoint)])) {
          number("rows", layout.rows, L10n.t("layoutEditor.frameBuilder.rows"))
          number("cols", layout.cols, L10n.t("layoutEditor.frameBuilder.cols"))
          text("rowGap", layout.rowGap, L10n.t("layoutEditor.frameBuilder.rowGap"))
          text("columnGap", layout.columnGap, L10n.t("layoutEditor.frameBuilder.columnGap"))
        }
        Section {
          text("maxWidth", layout.maxWidth, L10n.t("layoutEditor.frameBuilder.maxWidth"), placeholder: L10n.t("layoutEditor.frameBuilder.maxWidthPlaceholder"))
          Picker(L10n.t("layoutEditor.frameBuilder.align"), selection: Binding(get: { layout.align ?? "left" },
                                                                               set: { set(FrameEditing.withSetting(draft, breakpoint, "align", .string($0))) })) {
            Text(L10n.t("layoutEditor.frameBuilder.alignOption.left")).tag("left")
            Text(L10n.t("layoutEditor.frameBuilder.alignOption.center")).tag("center")
            Text(L10n.t("layoutEditor.frameBuilder.alignOption.right")).tag("right")
          }
          text("paddingBlock", layout.paddingBlock, L10n.t("layoutEditor.frameBuilder.paddingBlock"), placeholder: "0")
          text("paddingInline", layout.paddingInline, L10n.t("layoutEditor.frameBuilder.paddingInline"), placeholder: "0")
          Note(hasMaxWidth ? L10n.t("layoutEditor.frameBuilder.boxHint") : L10n.t("layoutEditor.frameBuilder.boxHintNoMaxWidth"))
        } header: {
          Text(L10n.t("layoutEditor.frameBuilder.inspectorBox"))
        }
        Section(L10n.t("layoutEditor.frameBuilder.columnSizesLabel")) {
          tracks(key: "columnSizes", count: layout.cols, first: 1, placeholder: "1fr", name: .column,
                 value: { i in layout.columnSizes.flatMap { $0.indices.contains(i) ? $0[i] : nil } }, line: false)
        }
        Section(L10n.t("layoutEditor.frameBuilder.rowSizesLabel")) {
          tracks(key: "rowSizes", count: layout.rows, first: 1, placeholder: "auto", name: .row,
                 value: { i in layout.rowSizes.flatMap { $0.indices.contains(i) ? $0[i] : nil } }, line: false)
          Button(L10n.t("layoutEditor.frameBuilder.resetTracks")) {
            set(FrameEditing.withSetting(FrameEditing.withSetting(draft, breakpoint, "columnSizes", nil), breakpoint, "rowSizes", nil))
          }
        }
        Section {
          DisclosureGroup(L10n.t("layoutEditor.frameBuilder.lineNamesLabel")) {
            Note(L10n.t("layoutEditor.frameBuilder.lineNamesHint"))
            Text(L10n.t("layoutEditor.frameBuilder.columnLinesLabel")).font(.callout.weight(.medium))
            tracks(key: "columnLineNames", count: layout.cols + 1, first: 0, placeholder: "", name: .line,
                   value: { i in lineName(draft, "columnLineNames", i) }, line: true)
            Text(L10n.t("layoutEditor.frameBuilder.rowLinesLabel")).font(.callout.weight(.medium))
            tracks(key: "rowLineNames", count: layout.rows + 1, first: 0, placeholder: "", name: .line,
                   value: { i in lineName(draft, "rowLineNames", i) }, line: true)
          }
        }
        Section(L10n.t("layoutEditor.frameBuilder.inspectorCopy")) {
          ForEach(LayoutBoard.breakpoints.filter { $0 != breakpoint }, id: \.self) { bp in
            Button(L10n.t("layoutEditor.frameBuilder.copyLayoutTo", ["target": LayoutWords.breakpoint(bp)])) {
              set(FrameEditing.copyLayout(draft, from: breakpoint, to: bp))
            }
          }
        }
        Section {
          BreakpointWidthsSection(model: model)
        }
      }
      .formStyle(.grouped)
    }
  }

  private func set(_ next: JSONValue) {
    model.draft = next
    model.frameMessage = nil
  }

  private func text(_ key: String, _ value: String?, _ label: String, placeholder: String = "") -> some View {
    TextField(label, text: Binding(get: { value ?? "" }, set: { if let d = model.draft { set(FrameEditing.withSetting(d, breakpoint, key, .string($0))) } }),
              prompt: Text(placeholder))
  }

  private func number(_ key: String, _ value: Int, _ label: String) -> some View {
    Stepper(value: Binding(get: { value }, set: { if let d = model.draft { set(FrameEditing.withSetting(d, breakpoint, key, .number(Double($0)))) } }), in: 1...12) {
      LabeledContent(label, value: "\(value)")
    }
    .accessibilityLabel(label)
    .accessibilityValue("\(value)")
  }

  private func lineName(_ draft: JSONValue, _ key: String, _ index: Int) -> String? {
    draft["breakpoints"]?[breakpoint]?[key]?[String(index)]?.arrayValue?.first?.stringValue
  }

  /// One field per track or line, numbered from `first`.
  @ViewBuilder
  private func tracks(key: String, count: Int, first: Int, placeholder: String, name: Track,
                      value: @escaping (Int) -> String?, line: Bool) -> some View {
    ForEach(0..<max(count, 0), id: \.self) { i in
      TextField(label(name, i + first), text: Binding(get: { value(i) ?? "" }, set: { raw in
        guard let draft = model.draft else { return }
        set(line ? FrameEditing.withLineName(draft, breakpoint, key, i, raw) : FrameEditing.withTrackSize(draft, breakpoint, key, i, raw))
      }), prompt: Text(placeholder))
    }
  }

  enum Track { case column, row, line }

  private func label(_ track: Track, _ n: Int) -> String {
    switch track {
    case .column: L10n.t("layoutEditor.frameBuilder.trackColumn", ["n": String(n)])
    case .row: L10n.t("layoutEditor.frameBuilder.trackRow", ["n": String(n)])
    case .line: L10n.t("layoutEditor.frameBuilder.trackLine", ["n": String(n)])
    }
  }
}
