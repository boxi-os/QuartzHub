import QuartzHubCore
import SwiftUI

/// Layout (QuartzControl's `routes/LayoutEditor`): the three levels of a layout in the order they
/// are read. Übersicht compares the page types, Komponenten is the stage where a component's place
/// is set, Frames is how a page is divided. Übersicht and Komponenten edit quartz.config.yaml and
/// share "Speichern" (⌘S); a frame is written on its own from the Frames tab.
struct LayoutPage: View {
  let project: ProjectContext

  @State private var model: LayoutModel
  /// "Where was I" per window, by stable names; the Plugins page sets them for "Auf der Bühne
  /// zeigen" (`OpenLayoutAction`).
  @SceneStorage("layout.tab") private var tabID = LayoutModel.Tab.global.rawValue
  @SceneStorage("layout.pageType") private var pageType = ""
  /// The selected component as "name\noccurrence": an index belongs to whatever sits there after a
  /// removal (docs/conventions.md, „Wo war ich“).
  @SceneStorage("layout.selected") private var selected = ""
  @State private var breakpoint = "desktop"
  /// The frame the Frames tab opens on, by id; set by "Frame bearbeiten" and from the Plugins page.
  @SceneStorage("layout.frame") private var openFrameId = ""

  init(project: ProjectContext) {
    self.project = project
    _model = State(initialValue: LayoutModel(project: project))
  }

  static let tabs: [LayoutModel.Tab] = [.overview, .global]

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
    PageScaffold(page: .layout) {
      VStack(spacing: 0) {
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
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("page.layout")
      .task { await model.load() }
      .task(id: model.pluginFramesKey) { if model.config != nil { await model.readPluginFrames() } }
      .unsavedChanges(model.dirty, save: model.saving || model.config == nil ? nil : { await model.save() })
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          if model.status == .saved {
            Text(L10n.t("common.saved")).foregroundStyle(.green)
          } else if model.dirty, !model.saving {
            UnsavedBadge().accessibilityIdentifier("layout.unsaved")
          }
          Button {
            Task { await model.save() }
          } label: {
            Label(model.saving ? L10n.t("common.saving") : L10n.t("common.save"), systemImage: "square.and.arrow.down")
          }
          .labelStyle(.titleOnly)
          .disabled(model.saving || model.config == nil)
          .accessibilityIdentifier("layout.save")
        }
      }
    } inspector: {
      inspector
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
          tabID = LayoutModel.Tab.global.rawValue
        }, openFrame: { name in
          openFrameId = model.frames.first { $0.frameName == name }?.id ?? ""
          tabID = LayoutModel.Tab.frames.rawValue
        })
      case .global, .frames:
        StageTab(model: model, selected: $selected, storedPageType: $pageType, breakpoint: $breakpoint, editFrame: { _ in })
      }
    }
  }

  @ViewBuilder private var inspector: some View {
    if tab == .overview {
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
}
