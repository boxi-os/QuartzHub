import QuartzHubCore
import SwiftUI

/// Layout (QuartzControl's `routes/LayoutEditor`): the three levels of a layout in the order they
/// are read. Übersicht compares the page types, Komponenten is the stage where a component's place
/// is set, Frames is how a page is divided. Übersicht and Komponenten edit quartz.config.yaml and
/// share "Speichern" (⌘S); a frame is written on its own from the Frames tab.
struct LayoutPage: View {
  let project: ProjectContext

  @State private var model: LayoutModel
  /// "Where was I" per window, by stable names. The Plugins page hands its "Auf der Bühne zeigen"
  /// over through `LayoutHandOver`, which the page writes into these when it appears.
  @SceneStorage("layout.tab") private var tabID = LayoutModel.Tab.global.rawValue
  @SceneStorage("layout.pageType") private var pageType = ""
  /// The selected component as "name\noccurrence": an index belongs to whatever sits there after a
  /// removal (docs/conventions.md, „Wo war ich“).
  @SceneStorage("layout.selected") private var selected = ""
  @State private var breakpoint = "desktop"
  @Environment(\.layoutHandOver) private var handOver
  @Environment(\.returnLink) private var returnLink
  /// The frame the Frames tab opens on, by id; set by "Frame bearbeiten" and from the Plugins page.
  @SceneStorage("layout.frame") private var openFrameId = ""
  @SceneStorage("frames.selectedArea") private var selectedArea = ""
  @SceneStorage("frames.breakpoint") private var frameBreakpoint = "desktop"

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: LayoutModel(project: project))
  }

  static let tabs: [LayoutModel.Tab] = LayoutModel.Tab.allCases

  private var tab: LayoutModel.Tab {
    LayoutModel.Tab(rawValue: tabID).flatMap { Self.tabs.contains($0) ? $0 : nil } ?? .global
  }

  private var tabPicker: some View {
    Picker(L10n.t("common.viewSwitcher"), selection: $tabID) {
      ForEach(Self.tabs) { Text($0.title).tag($0.rawValue) }
    }
    .labelsHidden()
    .accessibilityIdentifier("layout.tabs")
  }

  var body: some View {
    // The selection is read here, in the page's own body: read only inside the inspector, a
    // selection handed over from the Plugins page on the first visit never reached it, and the
    // inspector stayed on the summary (measured 2026-11-09, three of three cold starts).
    let chosen = selected
    PageScaffold(page: .layout) {
      VStack(spacing: 0) {
        // Three tabs and the inspector are wider than the smallest window: there they become a menu.
        ViewThatFits(in: .horizontal) {
          tabPicker.pickerStyle(.segmented).fixedSize()
          tabPicker.pickerStyle(.menu).fixedSize()
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        if model.status == .failed, let error = model.saveError {
          Label(error, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
            .padding(.horizontal, 16).padding(.top, 8)
            .accessibilityIdentifier("layout.saveError")
        }
        content
      }
      .returnTab(page: .layout, tab: $tabID)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.layout")
      .onAppear(perform: takeHandOver)
      .task { await model.load() }
      .task(id: model.pluginFramesKey) { if model.config != nil { await model.readPluginFrames() } }
      .onChange(of: model.framesLoaded, initial: true) { openRequestedFrame() }
      .onChange(of: openFrameId) { openRequestedFrame() }
      // Two documents: the config and the frame being edited. Leaving asks for both, and saves
      // whichever is changed; ⌘S saves the one of the tab in front.
      .unsavedChanges(model.dirty || model.draftDirty, save: model.saving || model.config == nil ? nil : { await saveAll() },
                      command: false)
      .focusedSceneValue(\.pageSave, frontDirty && !model.saving && !model.frameSaving ? PageSaveAction { await saveFront() } : nil)
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          if tab == .frames {
            if model.frameSavedAt != nil, model.frameSavedAt == model.draft {
              Text(L10n.t("layoutEditor.frameBuilder.saved")).foregroundStyle(.green)
              if model.frameSavedWasEdit { Text(L10n.t("devServer.staleHint")).font(.caption).foregroundStyle(.secondary) }
            } else if model.draftDirty {
              UnsavedBadge().accessibilityIdentifier("layout.unsaved")
            }
          } else if model.status == .saved {
            Text(L10n.t("common.saved")).foregroundStyle(.green)
          } else if model.dirty, !model.saving {
            UnsavedBadge().accessibilityIdentifier("layout.unsaved")
          }
          Button {
            Task { await saveFront() }
          } label: {
            Label(model.saving || model.frameSaving ? L10n.t("common.saving") : L10n.t("common.save"), systemImage: "square.and.arrow.down")
          }
          .labelStyle(.titleOnly)
          .disabled(model.saving || model.frameSaving || model.config == nil || (tab == .frames && model.draft == nil))
          .accessibilityIdentifier("layout.save")
        }
      }
    } inspector: {
      inspector(selected: chosen)
    }
  }

  @ViewBuilder private var content: some View {
    if let error = model.loadError {
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.t("configEditor.loadError")).fontWeight(.medium).foregroundStyle(.red)
        Text(error).font(.system(.callout, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
      }
      .padding(16)
      .accessibilityIdentifier("layout.loadError")
    } else if model.config == nil {
      ProgressView(L10n.t("layoutEditor.loading")).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      switch tab {
      case .overview:
        OverviewTab(model: model, openPageType: { type, index in
          pageType = type
          selected = index.flatMap { LayoutEntries.componentRef(model.config?.plugins ?? [], $0) }.map { "\($0.name)\n\($0.occurrence)" } ?? ""
          returnLink?.markTab(.layout, to: LayoutModel.Tab.global.rawValue)
          tabID = LayoutModel.Tab.global.rawValue
        }, openFrame: { name in
          openFrameId = name == "default" ? "default" : model.frames.first { $0.frameName == name }?.id ?? ""
          returnLink?.markTab(.layout, to: LayoutModel.Tab.frames.rawValue)
          tabID = LayoutModel.Tab.frames.rawValue
        })
      case .global:
        StageTab(model: model, selected: $selected, storedPageType: $pageType, breakpoint: $breakpoint, editFrame: editFrame)
      case .frames:
        FramesTab(model: model, breakpoint: $frameBreakpoint, selectedArea: $selectedArea)
      }
    }
  }

  @ViewBuilder private func inspector(selected: String) -> some View {
    if tab == .frames {
      FrameAreaInspector(model: model, areaId: selectedArea, breakpoint: frameBreakpoint, selectedArea: $selectedArea)
        .id(selectedArea)
    } else if tab == .overview {
      InspectorPageContext(page: .layout) {
        Section { Note(L10n.t("layoutEditor.overview.inspectorHint")) }
      }
    } else if let config = model.config {
      let facts = StageFacts(model: model, config: config, storedPageType: pageType)
      if let index = StageTab.resolve(selected, config.plugins) {
        ComponentInspector(model: model, index: index, facts: facts, selected: $selected)
          .id(selected)
      } else {
        LayoutSummary(facts: facts, selected: $selected)
      }
    } else {
      InspectorPageContext(page: .layout)
    }
  }

  // MARK: saving and frames

  /// What ⌘S and the toolbar's Save write: the frame on the Frames tab, the config elsewhere.
  private var frontDirty: Bool { tab == .frames ? model.draftDirty : model.dirty }

  @discardableResult
  private func saveFront() async -> Bool {
    if tab == .frames { return await model.saveFrame() }
    return await model.save()
  }

  private func saveAll() async -> Bool {
    if model.dirty, !(await model.save()) { return false }
    if model.draftDirty, !(await model.saveFrame()) { return false }
    return true
  }

  /// "Frame bearbeiten" on the stage: the frame editor on this frame and in the view the stage
  /// showed. A draft of another frame with unsaved changes is not thrown away; it is said.
  private func editFrame(_ frame: FrameView) {
    if model.draftDirty, let draft = model.draft, FrameView(draft).id != frame.id {
      Announce.post(L10n.t("layoutEditor.stage.otherDraftOpen", ["name": FrameView(draft).frameName]))
      model.frameMessage = L10n.t("layoutEditor.stage.otherDraftOpen", ["name": FrameView(draft).frameName])
    } else {
      if model.draft.map(FrameView.init)?.id != frame.id {
        model.open(frame.json, isNew: false)
        selectedArea = ""
      }
      frameBreakpoint = breakpoint
    }
    returnLink?.markTab(.layout, to: LayoutModel.Tab.frames.rawValue)
    tabID = LayoutModel.Tab.frames.rawValue
  }

  /// "Auf der Bühne zeigen" and "Im Layout-Editor" from the Plugins page.
  private func takeHandOver() {
    guard let target = handOver?.target else { return }
    handOver?.target = nil
    switch target {
    case .component(let plugins, let index):
      tabID = LayoutModel.Tab.global.rawValue
      pageType = ""
      selected = LayoutEntries.componentRef(plugins, index).map { "\($0.name)\n\($0.occurrence)" } ?? ""
    case .frame(let id):
      tabID = LayoutModel.Tab.frames.rawValue
      openFrameId = id
    }
  }

  /// A frame asked for from elsewhere (the overview, the Plugins page), once the frames are read.
  private func openRequestedFrame() {
    guard model.framesLoaded, !openFrameId.isEmpty else { return }
    let id = openFrameId
    openFrameId = ""
    if model.draftDirty, let draft = model.draft, FrameView(draft).id != id {
      model.frameMessage = L10n.t("layoutEditor.stage.otherDraftOpen", ["name": FrameView(draft).frameName])
      return
    }
    if id == "default" || !model.frames.contains(where: { $0.id == id }) {
      if id == "default" { model.open(nil, isNew: false) }
    } else if model.draft.map(FrameView.init)?.id != id, let frame = model.frames.first(where: { $0.id == id }) {
      model.open(frame.json, isNew: false)
    }
    selectedArea = ""
    frameBreakpoint = "desktop"
  }
}

