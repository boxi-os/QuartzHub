import QuartzHubCore
import SwiftUI

/// Frames, the frame editor (QuartzControl's `FrameBuilder.tsx`): Quartz's standard frame to look
/// at and copy, or an own frame to edit, one breakpoint at a time. The grid is the stage's
/// geometry with columns no narrower than 24 pt; an area is dragged onto a cell or back into the
/// tray, a selected one has handles on its edges. Everything about the selected area is in the
/// inspector. A frame is written on its own, by "Speichern" on this tab.
struct FramesTab: View {
  @Bindable var model: LayoutModel
  @Binding var breakpoint: String
  @Binding var selectedArea: String
  @Environment(\.unsavedGuard) private var unsaved

  /// The board's cells in its own coordinates, for dragging an edge onto the nearest grid line.
  @State private var cells: [String: CGRect] = [:]
  @State private var resize: (id: String, start: FrameView.Placement, preview: FrameView.Placement)?
  @State private var trayTargeted = false
  /// The width the board has: inside its sideways scroller nothing proposes one.
  @State private var boardWidth: CGFloat = 600

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let message = model.frameMessage {
          Label(message, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
            .accessibilityIdentifier("layout.frames.message")
        }
        head
        if let draft = model.draft {
          editor(draft)
        } else {
          standard
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onExitCommand { selectedArea = "" }
    .accessibilityIdentifier("layout.frames")
  }

  // MARK: the head

  /// Whether a dirty draft may be left: asks, the safe answer first.
  private func leaveDraft() async -> Bool {
    guard model.draftDirty, let draft = model.draft else { return true }
    let name = FrameView(draft).frameName
    let (question, detail) = Confirm.split(L10n.t("layoutEditor.frameBuilder.discardConfirm",
                                                  ["name": name.isEmpty ? L10n.t("layoutEditor.frameBuilder.unnamed") : name]))
    return await Confirm.ask(question, detail: detail, confirm: L10n.t("layoutEditor.frameBuilder.discardConfirmAction"),
                             destructive: true, window: unsaved?.window)
  }

  private func switchTo(_ action: @escaping @MainActor () -> Void) {
    Task {
      guard await leaveDraft() else { return }
      action()
      selectedArea = ""
      breakpoint = "desktop"
    }
  }

  private var widths: LayoutFrames.Widths {
    if model.draft == nil { return (model.standardMeasures.breakpoints.desktop, model.standardMeasures.breakpoints.mobile) }
    return model.widths
  }

  private var head: some View {
    let view = model.draft.map(FrameView.init)
    let label = view.map { $0.frameName.isEmpty ? L10n.t("layoutEditor.frameBuilder.unnamed") : $0.frameName }
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "rectangle.split.3x3").font(.title3).foregroundStyle(.tint)
          .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.15)))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
          Text(view == nil ? L10n.t("layoutEditor.context.builtinFrame") : L10n.t("layoutEditor.context.ownFrame"))
            .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
          Text(label ?? L10n.t("layoutEditor.frameBuilder.standardTitle")).font(.title3.weight(.semibold))
        }
        Spacer(minLength: 8)
        if view == nil { Text(L10n.t("layoutEditor.context.viewOnly")).font(.caption).foregroundStyle(.secondary) }
        if view != nil, model.draftIsNew { Text(L10n.t("layoutEditor.context.newDraft")).font(.caption).foregroundStyle(.tint) }
      }
      .accessibilityElement(children: .combine)
      Divider()
      FlowLayout(spacing: 10, minItem: 0, stretch: false) {
        Picker(L10n.t("layoutEditor.frameBuilder.frameLabel"), selection: Binding(get: { view?.id ?? "" }, set: { id in
          guard id != (view?.id ?? "") else { return }
          if id.isEmpty {
            switchTo { model.open(nil, isNew: false) }
          } else if let frame = model.frames.first(where: { $0.id == id }) {
            switchTo { model.open(frame.json, isNew: false) }
          }
        })) {
          Text(L10n.t("layoutEditor.frameBuilder.standardOption")).tag("")
          if !model.frames.isEmpty {
            Section(L10n.t("layoutEditor.frameBuilder.ownFrames")) {
              ForEach(model.frames) { frame in Text(verbatim: frame.id == view?.id ? (label ?? frame.frameName) : frame.frameName).tag(frame.id) }
            }
          }
          if let view, model.draftIsNew {
            Text(L10n.t("layoutEditor.frameBuilder.newDraftOption", ["name": label ?? ""])).tag(view.id)
          }
        }
        .fixedSize()
        .accessibilityIdentifier("layout.frames.picker")
        Button { switchTo { model.newFrame() } } label: { Label(L10n.t("layoutEditor.frameBuilder.newFrame"), systemImage: "plus") }
        if view != nil {
          Button { model.duplicateDraft() } label: { Label(L10n.t("layoutEditor.frameBuilder.duplicate"), systemImage: "plus.square.on.square") }
        }
        if let view, !model.draftIsNew {
          Button(role: .destructive) {
            Task {
              guard await Confirm.ask(L10n.t("layoutEditor.frameBuilder.deleteConfirm", ["name": view.frameName]),
                                      confirm: L10n.t("layoutEditor.frameBuilder.deleteConfirmAction"), destructive: true,
                                      window: unsaved?.window) else { return }
              await model.deleteFrame(view.id)
            }
          } label: { Label(L10n.t("common.deleteNamed", ["name": view.frameName]), systemImage: "trash") }
            .labelStyle(.iconOnly)
            .help(L10n.t("common.deleteNamed", ["name": view.frameName]))
        }
      }
      ViewThatFits(in: .horizontal) {
        breakpointPicker(ranges: true).pickerStyle(.segmented).fixedSize()
        breakpointPicker(ranges: false).pickerStyle(.segmented).fixedSize()
        breakpointPicker(ranges: true).pickerStyle(.menu).fixedSize()
      }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.06)))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.3)))
  }

  private func breakpointPicker(ranges: Bool) -> some View {
    Picker(L10n.t("layoutEditor.frameBuilder.breakpointLabel"), selection: $breakpoint) {
      ForEach(LayoutBoard.breakpoints, id: \.self) { bp in
        Text(ranges ? "\(LayoutWords.breakpoint(bp)) · \(LayoutBoard.rangeLabel(bp, widths: widths))" : LayoutWords.breakpoint(bp)).tag(bp)
      }
    }
    .accessibilityIdentifier("layout.frames.breakpoint")
  }

  // MARK: Quartz's standard frame

  private var standard: some View {
    let measures = model.standardMeasures
    let frame = FrameView(FrameEditing.quartzDefaultFrame(id: "standard", frameName: "standard", measures: measures))
    let desktop = measures.grids["desktop"]
    let values: [String: String] = [
      "columns": desktop?.columns.joined(separator: " ") ?? "",
      "gap": desktop.map { $0.rowGap == $0.columnGap ? $0.rowGap : "\($0.rowGap) / \($0.columnGap)" } ?? "",
      "max": measures.pageMaxWidth ?? L10n.t("layoutEditor.frameBuilder.standardCapUnread", ["max": FrameEditing.quartzMeasures.pageMaxWidth ?? ""]),
      "desktop": JSJSON.compact(.number(measures.breakpoints.desktop)), "mobile": JSJSON.compact(.number(measures.breakpoints.mobile)),
    ]
    let differs = LayoutBoard.breakpoints.filter { !FrameEditing.columnsFit(measures, $0) }
    return VStack(alignment: .leading, spacing: 16) {
      Note(L10n.t("layoutEditor.frameBuilder.whatIsAFrame"))
      GroupBox { preview(frame).padding(6) }
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.t("layoutEditor.frameBuilder.standardText"))
          Note(L10n.t("layoutEditor.frameBuilder.standardCopyHint"))
          switch model.measures {
          case .ok?:
            Note(L10n.t("layoutEditor.frameBuilder.standardSource", values))
          case .unavailable(let reason)?:
            Note(L10n.t("layoutEditor.frameBuilder.standardSourceUnavailable", values.merging(["reason": reason]) { a, _ in a }))
          case nil:
            EmptyView()
          }
          if !differs.isEmpty {
            Note(L10n.t("layoutEditor.frameBuilder.standardShapeDiffers", ["breakpoints": differs.map(LayoutWords.breakpoint).joined(separator: ", ")]))
          }
          HStack {
            Button(L10n.t("layoutEditor.frameBuilder.customizeStandard")) { switchTo { model.customizeStandard() } }
              .buttonStyle(.borderedProminent)
            Button(L10n.t("layoutEditor.frameBuilder.newEmptyFrame")) { switchTo { model.newFrame() } }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
      } label: {
        Text(L10n.t("layoutEditor.frameBuilder.standardTitle")).font(.headline)
      }
      BreakpointWidthsSection(model: model)
    }
  }

  /// A frame drawn and not edited (`FramePreview.tsx`), by the same geometry as the board.
  private func preview(_ frame: FrameView) -> some View {
    let layout = frame.layout(breakpoint)
    let stage = StageGeometry.frame(layout, breakpoint)
    return StageGridLayout(weights: stage.tracks.weights, rows: layout.rows, columnGap: max(stage.columnGap / 100, 0.003),
                           rowGap: max(stage.rowGap / 100, 0.003), width: stage.width / 100, align: stage.align,
                           paddingInline: stage.paddingInline / 100, paddingBlock: stage.paddingBlock / 100) {
      ForEach(frame.areas.filter { frame.isShown($0, on: breakpoint) }) { area in
        let p = frame.placement(breakpoint, area.id)!
        Text(area.slot.map(LayoutWords.position) ?? area.name).font(.caption.weight(.medium)).lineLimit(1)
          .padding(6)
          .frame(maxWidth: .infinity, minHeight: area.slot == "pageBody" ? 110 : 44, maxHeight: .infinity, alignment: .topLeading)
          .background(RoundedRectangle(cornerRadius: 6).fill(.background))
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
          .gridCell(row: p.row, col: p.col, rowSpan: p.rowSpan, colSpan: p.colSpan)
      }
    }
    .frame(maxWidth: StageGeometry.referenceWidth[breakpoint] ?? 1456)
    .frame(maxWidth: .infinity)
  }

  // MARK: an own frame

  private func set(_ next: JSONValue) {
    model.draft = next
    model.frameMessage = nil
  }

  private func editor(_ draft: JSONValue) -> some View {
    let view = FrameView(draft)
    let layout = view.layout(breakpoint)
    return VStack(alignment: .leading, spacing: 16) {
      settings(draft, layout)
      board(draft, view, layout)
      warnings(view)
    }
  }

  private func text(_ key: String, _ value: String?, _ label: String, placeholder: String = "", width: CGFloat = 130) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      TextField(label, text: Binding(get: { value ?? "" }, set: { if let d = model.draft { set(FrameEditing.withSetting(d, breakpoint, key, .string($0))) } }),
                prompt: Text(placeholder))
        .labelsHidden()
        .frame(width: width)
    }
  }

  private func number(_ key: String, _ value: Int, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Stepper(value: Binding(get: { value }, set: { if let d = model.draft { set(FrameEditing.withSetting(d, breakpoint, key, .number(Double($0)))) } }), in: 1...12) {
        Text(verbatim: "\(value)").monospacedDigit().frame(minWidth: 20)
      }
      .accessibilityLabel(label)
      .accessibilityValue("\(value)")
    }
  }

  private func settings(_ draft: JSONValue, _ layout: FrameView.Layout) -> some View {
    let hasMaxWidth = !(layout.maxWidth ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    return GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(L10n.t("layoutEditor.frameBuilder.appliesTo", ["breakpoint": LayoutWords.breakpoint(breakpoint)])).font(.caption).foregroundStyle(.secondary)
          Spacer()
          ForEach(LayoutBoard.breakpoints.filter { $0 != breakpoint }, id: \.self) { bp in
            Button(L10n.t("layoutEditor.frameBuilder.copyLayoutTo", ["target": LayoutWords.breakpoint(bp)])) {
              set(FrameEditing.copyLayout(draft, from: breakpoint, to: bp))
            }
            .controlSize(.small)
          }
        }
        FlowLayout(spacing: 14, minItem: 0, stretch: false) {
          VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("layoutEditor.frameBuilder.frameName")).font(.caption).foregroundStyle(.secondary)
            TextField(L10n.t("layoutEditor.frameBuilder.frameName"), text: Binding(get: { model.draft.map { FrameView($0).frameName } ?? "" }, set: { name in
              guard var object = model.draft?.objectValue else { return }
              object["frameName"] = .string(name)
              set(.object(object))
            }), prompt: Text(L10n.t("layoutEditor.templateCustomPlaceholder")))
              .labelsHidden().frame(width: 220)
              .accessibilityIdentifier("layout.frames.name")
          }
          number("rows", layout.rows, L10n.t("layoutEditor.frameBuilder.rows"))
          number("cols", layout.cols, L10n.t("layoutEditor.frameBuilder.cols"))
          text("rowGap", layout.rowGap, L10n.t("layoutEditor.frameBuilder.rowGap"), width: 100)
          text("columnGap", layout.columnGap, L10n.t("layoutEditor.frameBuilder.columnGap"), width: 100)
          text("maxWidth", layout.maxWidth, L10n.t("layoutEditor.frameBuilder.maxWidth"), placeholder: L10n.t("layoutEditor.frameBuilder.maxWidthPlaceholder"), width: 110)
          VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("layoutEditor.frameBuilder.align")).font(.caption).foregroundStyle(.secondary)
            Picker(L10n.t("layoutEditor.frameBuilder.align"), selection: Binding(get: { layout.align ?? "left" },
                                                                                 set: { set(FrameEditing.withSetting(draft, breakpoint, "align", .string($0))) })) {
              Text(L10n.t("layoutEditor.frameBuilder.alignOption.left")).tag("left")
              Text(L10n.t("layoutEditor.frameBuilder.alignOption.center")).tag("center")
              Text(L10n.t("layoutEditor.frameBuilder.alignOption.right")).tag("right")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
          }
          text("paddingBlock", layout.paddingBlock, L10n.t("layoutEditor.frameBuilder.paddingBlock"), placeholder: "0")
          text("paddingInline", layout.paddingInline, L10n.t("layoutEditor.frameBuilder.paddingInline"), placeholder: "0")
        }
        tracks(L10n.t("layoutEditor.frameBuilder.columnSizesLabel"), key: "columnSizes", count: layout.cols, first: 1, placeholder: "1fr",
               value: { i in layout.columnSizes.flatMap { $0.indices.contains(i) ? $0[i] : nil } }, line: false)
        tracks(L10n.t("layoutEditor.frameBuilder.rowSizesLabel"), key: "rowSizes", count: layout.rows, first: 1, placeholder: "auto",
               value: { i in layout.rowSizes.flatMap { $0.indices.contains(i) ? $0[i] : nil } }, line: false)
        HStack(alignment: .firstTextBaseline) {
          Note(hasMaxWidth ? L10n.t("layoutEditor.frameBuilder.boxHint") : L10n.t("layoutEditor.frameBuilder.boxHintNoMaxWidth"))
          Spacer()
          Button(L10n.t("layoutEditor.frameBuilder.resetTracks")) {
            set(FrameEditing.withSetting(FrameEditing.withSetting(draft, breakpoint, "columnSizes", nil), breakpoint, "rowSizes", nil))
          }
          .buttonStyle(.link).font(.caption)
        }
        DisclosureGroup(L10n.t("layoutEditor.frameBuilder.lineNamesLabel")) {
          VStack(alignment: .leading, spacing: 8) {
            Note(L10n.t("layoutEditor.frameBuilder.lineNamesHint"))
            tracks(L10n.t("layoutEditor.frameBuilder.columnLinesLabel"), key: "columnLineNames", count: layout.cols + 1, first: 0, placeholder: "",
                   value: { i in lineName(draft, "columnLineNames", i) }, line: true)
            tracks(L10n.t("layoutEditor.frameBuilder.rowLinesLabel"), key: "rowLineNames", count: layout.rows + 1, first: 0, placeholder: "",
                   value: { i in lineName(draft, "rowLineNames", i) }, line: true)
          }
          .padding(.top, 6)
        }
        BreakpointWidthsSection(model: model)
      }
      .padding(4)
    } label: {
      Label(L10n.t("layoutEditor.frameBuilder.framePanelTitle"), systemImage: "rectangle.split.3x3").font(.headline)
    }
  }

  private func lineName(_ draft: JSONValue, _ key: String, _ index: Int) -> String? {
    draft["breakpoints"]?[breakpoint]?[key]?[String(index)]?.arrayValue?.first?.stringValue
  }

  /// One field per track or line (`TrackInputs`), numbered from `first`.
  private func tracks(_ label: String, key: String, count: Int, first: Int, placeholder: String, value: @escaping (Int) -> String?, line: Bool) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      FlowLayout(spacing: 6, minItem: 0, stretch: false) {
        ForEach(0..<max(count, 0), id: \.self) { i in
          HStack(spacing: 3) {
            Text(verbatim: "\(i + first)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            TextField("\(label) \(i + first)", text: Binding(get: { value(i) ?? "" }, set: { raw in
              guard let draft = model.draft else { return }
              set(line ? FrameEditing.withLineName(draft, breakpoint, key, i, raw) : FrameEditing.withTrackSize(draft, breakpoint, key, i, raw))
            }), prompt: Text(placeholder))
              .labelsHidden().frame(width: 90)
          }
        }
      }
    }
  }

  // MARK: the board

  private func board(_ draft: JSONValue, _ view: FrameView, _ layout: FrameView.Layout) -> some View {
    let stage = StageGeometry.frame(layout, breakpoint)
    let unplaced = view.areas.filter { !view.isShown($0, on: breakpoint) }
    return GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(L10n.t("layoutEditor.frameBuilder.availableAreasLabel")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
          Spacer()
          Button(L10n.t("layoutEditor.frameBuilder.newArea")) {
            let id = LayoutModel.newId("area")
            set(FrameEditing.addingArea(draft, id: id))
            selectedArea = id
          }
          .accessibilityIdentifier("layout.frames.newArea")
        }
        FlowLayout(spacing: 6, minItem: 0, stretch: false) {
          if unplaced.isEmpty { Text(L10n.t("layoutEditor.frameBuilder.allPlaced")).font(.caption).foregroundStyle(.secondary) }
          ForEach(unplaced) { area in
            HStack(spacing: 4) {
              Text(verbatim: area.name)
              if view.placement(breakpoint, area.id) != nil {
                Text(L10n.t("layoutEditor.frameBuilder.hiddenShort")).font(.caption2).foregroundStyle(.secondary)
              }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selectedArea == area.id ? Color.accentColor : Color.accentColor.opacity(0.4),
                                                                    lineWidth: selectedArea == area.id ? 2 : 1))
            .fixedSize()
            .onTapGesture { selectedArea = selectedArea == area.id ? "" : area.id }
            .draggable("area:\(area.id)")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L10n.t("layoutEditor.frameBuilder.selectArea", ["name": area.name]))
          }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(trayTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .dropDestination(for: String.self) { items, _ in
          guard let id = Self.areaId(items.first), FrameView(draft).placement(breakpoint, id) != nil else { return false }
          set(FrameEditing.unplacing(draft, breakpoint, id))
          selectedArea = id
          return true
        } isTargeted: { trayTargeted = $0 }
        Note(L10n.t("layoutEditor.frameBuilder.hintDragToPlace"))
        ScrollView(.horizontal) {
          StageGridLayout(weights: stage.tracks.weights, rows: max(layout.rows, 1), columnGap: stage.columnGap / 100, rowGap: stage.rowGap / 100,
                          width: stage.width / 100, align: stage.align, paddingInline: stage.paddingInline / 100,
                          paddingBlock: stage.paddingBlock / 100, minColumn: 24) {
            ForEach(1...max(layout.rows, 1), id: \.self) { r in
              ForEach(1...max(layout.cols, 1), id: \.self) { c in
                cell(draft, r, c).gridCell(row: r, col: c)
              }
            }
            ForEach(view.areas.filter { view.isShown($0, on: breakpoint) }) { area in
              let p = resize?.id == area.id ? resize!.preview : view.placement(breakpoint, area.id)!
              placedBox(area, view, p).gridCell(row: p.row, col: p.col, rowSpan: p.rowSpan, colSpan: p.colSpan)
            }
          }
          .coordinateSpace(.named("board"))
          .frame(width: max(min(boardWidth - 16, StageGeometry.referenceWidth[breakpoint] ?? 1456), 120))
          .padding(FrameEditing.hasBox(layout) ? 4 : 0)
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(FrameEditing.hasBox(layout) ? Color.blue.opacity(0.5) : .clear,
                                                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
          .frame(minWidth: boardWidth - 8)
          .padding(4)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardWidth = $0 }
        .accessibilityIdentifier("layout.frames.board")
      }
      .padding(4)
    }
  }

  static func areaId(_ payload: String?) -> String? {
    guard let payload, payload.hasPrefix("area:") else { return nil }
    return String(payload.dropFirst(5))
  }

  private func cell(_ draft: JSONValue, _ row: Int, _ col: Int) -> some View {
    RoundedRectangle(cornerRadius: 4)
      .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
      .frame(minHeight: 48)
      .contentShape(Rectangle())
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("board")) } action: { cells["\(row):\(col)"] = $0 }
      .dropDestination(for: String.self) { items, _ in
        guard let id = Self.areaId(items.first), let current = model.draft else { return false }
        let before = FrameView(current).placement(breakpoint, id)
        if let before, !before.hidden, before.row == row, before.col == col { return true }
        switch FrameEditing.dropping(current, breakpoint, id, row: row, col: col) {
        case .success(let next)?:
          set(next)
          selectedArea = id
          let name = FrameView(next).areas.first { $0.id == id }?.name ?? id
          let landed = FrameView(next).placement(breakpoint, id)
          var cut: [String] = []
          if let before, let landed, landed.colSpan < before.colSpan {
            cut.append(L10n.t("layoutEditor.frameBuilder.colSpanCut", ["now": String(landed.colSpan), "before": String(before.colSpan)]))
          }
          if let before, let landed, landed.rowSpan < before.rowSpan {
            cut.append(L10n.t("layoutEditor.frameBuilder.rowSpanCut", ["now": String(landed.rowSpan), "before": String(before.rowSpan)]))
          }
          let target = L10n.t("layoutEditor.frameBuilder.cellName", ["row": String(row), "col": String(col)])
          Announce.post(cut.isEmpty ? L10n.t("dnd.dropped", ["name": name, "target": target])
                        : L10n.t("layoutEditor.frameBuilder.dropNarrowed", ["name": name, "target": target, "changes": cut.joined(separator: ", ")]))
          return true
        case .failure?:
          let name = FrameView(current).areas.first { $0.id == id }?.name ?? id
          model.frameMessage = L10n.t("layoutEditor.frameBuilder.overlapError")
          Announce.post(L10n.t("layoutEditor.frameBuilder.dropRefused", ["name": name]))
          return false
        case nil:
          return false
        }
      }
      .accessibilityLabel(L10n.t("layoutEditor.frameBuilder.cellName", ["row": String(row), "col": String(col)]))
  }

  private func placedBox(_ area: FrameView.Area, _ view: FrameView, _ p: FrameView.Placement) -> some View {
    let selected = selectedArea == area.id
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: "line.3.horizontal").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
        Text(verbatim: area.name).fontWeight(.medium).lineLimit(1)
        Spacer(minLength: 0)
        Text((area.slot.map(LayoutWords.position) ?? L10n.t("layoutEditor.frameBuilder.slotNone"))
             + (area.group != nil ? " · \(L10n.t("layoutEditor.frameBuilder.ownGroupShort"))" : ""))
          .font(.caption2).lineLimit(1).padding(.horizontal, 5).background(Capsule().fill(.quaternary))
      }
      if area.slot == "pageBody" {
        Text(L10n.t("layoutEditor.frameBuilder.preview.pageContent")).font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity).padding(.vertical, 8)
          .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
      }
    }
    .font(.caption)
    .padding(6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(selected ? 0.18 : 0.1)))
    .background(RoundedRectangle(cornerRadius: 6).fill(.background))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Color.accentColor : Color.accentColor.opacity(0.4), lineWidth: selected ? 2 : 1))
    .overlay { if selected { handles(area, p) } }
    .contentShape(Rectangle())
    .onTapGesture { selectedArea = selected ? "" : area.id }
    .draggable("area:\(area.id)") {
      Text(verbatim: area.name).font(.caption.weight(.medium)).padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.3)))
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    .accessibilityLabel(L10n.t("layoutEditor.frameBuilder.selectArea", ["name": area.name]))
    .accessibilityIdentifier("layout.frames.area.\(area.name)")
  }

  // MARK: dragging an edge

  /// Eight handles: four edges, four corners. An edge snaps to the nearest grid line of the board
  /// and stops before another area; written once, on release, and said.
  private func handles(_ area: FrameView.Area, _ p: FrameView.Placement) -> some View {
    let specs: [(FrameEditing.Sides, Alignment)] = [
      (.top, .top), (.bottom, .bottom), (.left, .leading), (.right, .trailing),
      ([.top, .left], .topLeading), ([.top, .right], .topTrailing), ([.bottom, .left], .bottomLeading), ([.bottom, .right], .bottomTrailing),
    ]
    return ZStack {
      ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in
        let corner = spec.0.contains(.top) || spec.0.contains(.bottom) ? (spec.0.contains(.left) || spec.0.contains(.right)) : false
        let horizontal = spec.0 == .top || spec.0 == .bottom
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.accentColor)
          .frame(width: corner ? 9 : horizontal ? 22 : 5, height: corner ? 9 : horizontal ? 5 : 22)
          .padding(1)
          .contentShape(Rectangle().inset(by: -4))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: spec.1)
          .gesture(DragGesture(coordinateSpace: .named("board"))
            .onChanged { value in resizing(area, from: p, sides: spec.0, at: value.location) }
            .onEnded { _ in endResize(area) })
          .help(L10n.t("layoutEditor.frameBuilder.resizeHandle"))
      }
    }
    .accessibilityHidden(true)
  }

  private func nearest(_ candidates: [Int], _ edge: (Int) -> CGFloat?, _ at: CGFloat) -> Int {
    var best = candidates.first ?? 1
    var distance = CGFloat.infinity
    for i in candidates {
      guard let e = edge(i) else { continue }
      if abs(e - at) < distance { distance = abs(e - at); best = i }
    }
    return best
  }

  private func resizing(_ area: FrameView.Area, from p: FrameView.Placement, sides: FrameEditing.Sides, at point: CGPoint) {
    guard let draft = model.draft else { return }
    let view = FrameView(draft)
    let layout = view.layout(breakpoint)
    let start = resize?.id == area.id ? resize!.start : p
    let c0 = start.col, c1 = start.col + start.colSpan - 1, r0 = start.row, r1 = start.row + start.rowSpan - 1
    var toCol = c1, toRow = r1
    if sides.contains(.right) { toCol = nearest(Array(c0...max(c0, layout.cols)), { cells["1:\($0)"]?.maxX }, point.x) }
    if sides.contains(.left) { toCol = nearest(Array(1...max(1, c1)), { cells["1:\($0)"]?.minX }, point.x) }
    if sides.contains(.bottom) { toRow = nearest(Array(r0...max(r0, layout.rows)), { cells["\($0):1"]?.maxY }, point.y) }
    if sides.contains(.top) { toRow = nearest(Array(1...max(1, r1)), { cells["\($0):1"]?.minY }, point.y) }
    selectedArea = area.id
    let preview = FrameEditing.resized(view, breakpoint, area.id, from: start, sides: sides, toCol: toCol, toRow: toRow)
    resize = (area.id, start, preview)
  }

  private func endResize(_ area: FrameView.Area) {
    guard let current = resize, current.id == area.id, let draft = model.draft else {
      resize = nil
      return
    }
    resize = nil
    let p = current.preview, s = current.start
    guard p != s else { return }
    set(FrameEditing.withPlacement(draft, breakpoint, area.id, p))
    Announce.post(L10n.t("layoutEditor.frameBuilder.resized", ["name": area.name, "row": String(p.row), "col": String(p.col),
                                                               "rowSpan": String(p.rowSpan), "colSpan": String(p.colSpan)]))
  }

  // MARK: warnings

  @ViewBuilder private func warnings(_ view: FrameView) -> some View {
    let slots = FrameEditing.slotWarnings(view, breakpoint)
    let placements = FrameEditing.placementWarnings(view, breakpoint)
    let name = { (id: String) in view.areas.first { $0.id == id }?.name ?? id }
    let here = Set(FrameEditing.warningKeys(view, breakpoint))
    let others = LayoutBoard.breakpoints.filter { $0 != breakpoint && FrameEditing.warningKeys(view, $0).contains { !here.contains($0) } }
    let never = view.areas.filter { a in LayoutBoard.breakpoints.allSatisfy { !view.isShown(a, on: $0) } }
    let positions = { (list: [String]) in list.map(LayoutWords.position).joined(separator: ", ") }
    VStack(alignment: .leading, spacing: 6) {
      if !placements.overlapping.isEmpty {
        Note(L10n.t("layoutEditor.frameBuilder.overlapWarning", ["pairs": placements.overlapping.map { "\(name($0.0)) + \(name($0.1))" }.joined(separator: ", ")]))
      }
      if !placements.outside.isEmpty { Note(L10n.t("layoutEditor.frameBuilder.outsideWarning", ["areas": placements.outside.map(name).joined(separator: ", ")])) }
      if !slots.unassigned.isEmpty { Note(L10n.t("layoutEditor.frameBuilder.unassignedWarning", ["slots": positions(slots.unassigned)])) }
      if !slots.homeless.isEmpty { Note(L10n.t("layoutEditor.frameBuilder.homelessWarning", ["slots": positions(slots.homeless)])) }
      if !slots.doubled.isEmpty { Note(L10n.t("layoutEditor.frameBuilder.doubledWarning", ["slots": positions(slots.doubled)])) }
      if !slots.hiddenGroups.isEmpty {
        Note(L10n.t("layoutEditor.frameBuilder.hiddenGroupsWarning", ["breakpoint": LayoutWords.breakpoint(breakpoint), "areas": slots.hiddenGroups.map(name).joined(separator: ", ")]))
      }
      if !others.isEmpty { Note(L10n.t("layoutEditor.frameBuilder.otherBreakpointsWarning", ["breakpoints": others.map(LayoutWords.breakpoint).joined(separator: ", ")])) }
      if !never.isEmpty { Note(L10n.t("layoutEditor.frameBuilder.neverVisibleWarning", ["areas": never.map(\.name).joined(separator: ", ")])) }
    }
    .foregroundStyle(.orange)
    .accessibilityIdentifier("layout.frames.warnings")
  }
}

/// The two widths every own frame switches at (`FrameBreakpoints.tsx`), with their own Save: they
/// are written to `.quartz-gui/layout-breakpoints.json` and rewrite every frame's CSS.
struct BreakpointWidthsSection: View {
  @Bindable var model: LayoutModel
  @State private var tablet = ""
  @State private var mobile = ""
  @State private var saving = false
  @State private var saved = false
  @State private var error: String?

  var body: some View {
    let t = Int(tablet), m = Int(mobile)
    let valid = t != nil && m != nil && m! >= 240 && t! <= 3840 && m! < t!
    let changed = Double(t ?? 0) != model.widths.tablet || Double(m ?? 0) != model.widths.mobile
    DisclosureGroup(L10n.t("layoutEditor.breakpoints.title")) {
      VStack(alignment: .leading, spacing: 8) {
        Note(L10n.t("layoutEditor.breakpoints.hint"))
        HStack(spacing: 14) {
          LabeledContent(L10n.t("layoutEditor.breakpoints.tablet")) { TextField("", text: $tablet).labelsHidden().frame(width: 70) }
          LabeledContent(L10n.t("layoutEditor.breakpoints.mobile")) { TextField("", text: $mobile).labelsHidden().frame(width: 70) }
          Button(saving ? L10n.t("common.saving") : L10n.t("common.save")) {
            Task {
              saving = true
              error = await model.saveWidths(tablet: Double(t!), mobile: Double(m!))
              saved = error == nil
              saving = false
            }
          }
          .disabled(saving || !valid || !changed)
        }
        if !valid { Text(L10n.t("layoutEditor.breakpoints.invalid")).font(.caption).foregroundStyle(.red) }
        if saved && !changed { Text(L10n.t("layoutEditor.breakpoints.saved")).font(.caption).foregroundStyle(.green) }
        if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      }
      .padding(.top, 6)
    }
    .onAppear { reset() }
    .onChange(of: "\(model.widths.tablet)|\(model.widths.mobile)") { reset() }
    .onChange(of: tablet) { saved = false }
    .onChange(of: mobile) { saved = false }
  }

  private func reset() {
    tablet = JSJSON.compact(.number(model.widths.tablet))
    mobile = JSJSON.compact(.number(model.widths.mobile))
  }
}

/// The selected area in the inspector (QuartzControl's `areaForm`): wherever it lies, on the grid
/// or in the tray, with what describes a placement only where it has one.
struct FrameAreaInspector: View {
  @Bindable var model: LayoutModel
  let areaId: String
  let breakpoint: String
  @Binding var selectedArea: String
  @Environment(\.unsavedGuard) private var unsaved
  @State private var nameDraft: String?
  @State private var refusal: String?

  var body: some View {
    if let draft = model.draft, let area = FrameView(draft).areas.first(where: { $0.id == areaId }) {
      let view = FrameView(draft)
      let layout = view.layout(breakpoint)
      let placement = view.placement(breakpoint, area.id)
      Form {
        Section {
          Label(L10n.t("layoutEditor.frameBuilder.areaPanelTitle", ["name": area.name]), systemImage: "slider.horizontal.3").font(.headline)
          Note(L10n.t("layoutEditor.frameBuilder.inspectorSaves"))
          TextField(L10n.t("layoutEditor.frameBuilder.areaName"), text: Binding(get: { nameDraft ?? area.name }, set: { raw in
            nameDraft = raw
            set(FrameEditing.withAreaName(draft, area.id, raw))
          }))
          .accessibilityIdentifier("layout.frames.areaName")
          Picker(L10n.t("layoutEditor.frameBuilder.areaSlot"), selection: Binding(get: { area.slot ?? "" }, set: {
            set(FrameEditing.withAreaSlot(draft, area.id, $0.isEmpty ? nil : $0))
          })) {
            Text(L10n.t("layoutEditor.frameBuilder.slotNone")).tag("")
            ForEach(FrameEditing.slots, id: \.self) { Text(LayoutWords.position($0)).tag($0) }
          }
          if let slot = area.slot, slot != "pageBody" {
            Toggle(L10n.t("layoutEditor.frameBuilder.ownGroup"), isOn: Binding(get: { area.group != nil }, set: {
              set(FrameEditing.withAreaGroup(draft, area.id, own: $0))
            }))
            Note(area.group != nil && area.group != area.name ? L10n.t("layoutEditor.frameBuilder.ownGroupRenamed", ["group": area.group!])
                 : L10n.t("layoutEditor.frameBuilder.ownGroupHint"))
          }
        }
        if let placement {
          Section {
            Stepper(value: Binding(get: { placement.rowSpan }, set: { span($0, nil) }), in: 1...max(1, layout.rows)) {
              LabeledContent(L10n.t("layoutEditor.frameBuilder.rowSpanLabel"), value: "\(placement.rowSpan)")
            }
            Stepper(value: Binding(get: { placement.colSpan }, set: { span(nil, $0) }), in: 1...max(1, layout.cols)) {
              LabeledContent(L10n.t("layoutEditor.frameBuilder.colSpanLabel"), value: "\(placement.colSpan)")
            }
            Note(L10n.t("layoutEditor.frameBuilder.placementSummary", ["row": String(placement.row), "col": String(placement.col)]))
            Toggle(L10n.t("layoutEditor.frameBuilder.visibleOnBreakpoint", ["breakpoint": LayoutWords.breakpoint(breakpoint)]), isOn: Binding(
              get: { !placement.hidden },
              set: { shown in
                switch FrameEditing.withHidden(draft, breakpoint, area.id, !shown) {
                case .success(let next): set(next)
                case .failure(.outside): refuse(L10n.t("layoutEditor.frameBuilder.showRefusedOutside", ["name": area.name]))
                case .failure(.overlap): refuse(L10n.t("layoutEditor.frameBuilder.showRefused", ["name": area.name]))
                }
              }))
          }
        }
        Section {
          HStack {
            if placement != nil {
              Button(L10n.t("layoutEditor.frameBuilder.unplace")) { set(FrameEditing.unplacing(draft, breakpoint, area.id)) }
            }
            Button(L10n.t("layoutEditor.frameBuilder.removeArea"), role: .destructive) { Task { await remove(area, view) } }
          }
          if let refusal { Text(refusal).foregroundStyle(.red).accessibilityIdentifier("layout.frames.refusal") }
        }
      }
      .formStyle(.grouped)
    } else {
      InspectorPageContext(page: .layout) {
        Section { Note(L10n.t("layoutEditor.frameBuilder.framePanelHint")) }
      }
    }
  }

  private func set(_ next: JSONValue) {
    model.draft = next
    model.frameMessage = nil
    refusal = nil
  }

  private func refuse(_ text: String) {
    refusal = text
    Announce.post(text)
  }

  private func span(_ rows: Int?, _ cols: Int?) {
    guard let draft = model.draft else { return }
    switch FrameEditing.withSpan(draft, breakpoint, areaId, rowSpan: rows, colSpan: cols) {
    case .success(let next): set(next)
    case .failure:
      refuse(L10n.t("layoutEditor.frameBuilder.spanRefused", ["name": FrameView(draft).areas.first { $0.id == areaId }?.name ?? areaId]))
    }
  }

  private func remove(_ area: FrameView.Area, _ view: FrameView) async {
    let placedOn = LayoutBoard.breakpoints.filter { view.placement($0, area.id) != nil }
    if !placedOn.isEmpty || area.slot != nil || area.group != nil {
      let consequence = placedOn.isEmpty ? L10n.t("layoutEditor.frameBuilder.removeAreaUnplaced")
        : L10n.t("layoutEditor.frameBuilder.removeAreaPlaced", ["breakpoints": placedOn.map(LayoutWords.breakpoint).joined(separator: ", ")])
      let (question, detail) = Confirm.split(L10n.t("layoutEditor.frameBuilder.removeAreaConfirm", ["name": area.name.isEmpty ? area.id : area.name, "consequence": consequence]))
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("layoutEditor.frameBuilder.removeArea"), destructive: true,
                              window: unsaved?.window) else { return }
    }
    guard let draft = model.draft else { return }
    set(FrameEditing.deletingArea(draft, area.id))
    selectedArea = ""
  }
}
