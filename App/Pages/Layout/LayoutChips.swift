import QuartzHubCore
import SwiftUI

/// The pieces the stage, the summary and the overview share (QuartzControl's `ComponentChip.tsx`).
enum LayoutWords {
  /// The group colours, taken in the order of `LayoutBoard.groupNames`, so a group looks alike on
  /// the stage and in the overview.
  static let groupColors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan]

  static func groupColor(_ group: String?, _ names: [String]) -> Color? {
    guard let group, let index = names.firstIndex(of: group) else { return nil }
    return groupColors[index % groupColors.count]
  }

  static func position(_ position: String) -> String {
    switch position {
    case "header": L10n.t("positions.header")
    case "left": L10n.t("positions.left")
    case "right": L10n.t("positions.right")
    case "beforeBody": L10n.t("positions.beforeBody")
    case "afterBody": L10n.t("positions.afterBody")
    case "footer": L10n.t("positions.footer")
    case "pageBody": L10n.t("positions.pageBody")
    default: position
    }
  }

  /// The visibility in the inspector's words; nil for "Immer", the case that needs no mention.
  /// For VoiceOver, which read the raw value ("desktop-only") before (measured 2026-11-10).
  static func display(_ value: JSONValue?) -> String? {
    switch value {
    case .string("desktop-only")?: L10n.t("layoutEditor.displayDesktopOnly")
    case .string("mobile-only")?: L10n.t("layoutEditor.displayMobileOnly")
    default: nil
    }
  }

  static func condition(_ condition: String) -> String {
    switch condition {
    case "not-index": L10n.t("layoutEditor.inspector.conditionNotIndex")
    case "has-tags": L10n.t("layoutEditor.inspector.conditionHasTags")
    case "has-backlinks": L10n.t("layoutEditor.inspector.conditionHasBacklinks")
    case "has-toc": L10n.t("layoutEditor.inspector.conditionHasToc")
    default: condition
    }
  }

  static func pageType(_ type: String) -> String {
    switch type {
    case "404": L10n.t("layoutEditor.pageTypes.404")
    case "bases": L10n.t("layoutEditor.pageTypes.bases")
    case "canvas": L10n.t("layoutEditor.pageTypes.canvas")
    case "content": L10n.t("layoutEditor.pageTypes.content")
    case "excalidraw": L10n.t("layoutEditor.pageTypes.excalidraw")
    case "folder": L10n.t("layoutEditor.pageTypes.folder")
    case "tag": L10n.t("layoutEditor.pageTypes.tag")
    default: type
    }
  }

  static func frame(_ name: String) -> String {
    switch name {
    case "default": L10n.t("layoutEditor.templateDefault")
    case "full-width": L10n.t("layoutEditor.templateFullWidth")
    case "minimal": L10n.t("layoutEditor.templateMinimal")
    default: name
    }
  }

  static func breakpoint(_ bp: String) -> String {
    switch bp {
    case "tablet": L10n.t("layoutEditor.frameBuilder.breakpoint.tablet")
    case "mobile": L10n.t("layoutEditor.frameBuilder.breakpoint.mobile")
    default: L10n.t("layoutEditor.frameBuilder.breakpoint.desktop")
    }
  }

  static func breakpointSymbol(_ bp: String) -> String {
    switch bp {
    case "tablet": "ipad"
    case "mobile": "iphone"
    default: "desktopcomputer"
    }
  }

  static func hidden(_ reason: LayoutStage.Hidden, type: String) -> String {
    switch reason {
    case .excluded: L10n.t("layoutEditor.pageType.excludedHere", ["type": pageType(type)])
    case .cleared: L10n.t("layoutEditor.pageType.clearedHere", ["type": pageType(type)])
    case .notInView: L10n.t("layoutEditor.stage.hiddenInView")
    }
  }
}

/// One placed component on the stage: its name, and marks for what its layout says beyond the
/// place it sits in. Everything about it is changed in the inspector, so the chip stays one line.
struct ComponentChip: View {
  let plugin: PluginEntry
  let label: String
  let groupNames: [String]
  var selected = false
  /// Why it is not on the page the stage shows; drawn dashed and said with the name.
  var hiddenReason: String?
  /// On "all pages": the page types that hide it.
  var hiddenOnTypes: String?

  var body: some View {
    let layout = LayoutEntries.layout(plugin)
    let group = layout?["group"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    let color = LayoutWords.groupColor(group, groupNames)
    HStack(spacing: 4) {
      Image(systemName: "line.3.horizontal").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
      Text(verbatim: label)
        .lineLimit(1).truncationMode(.tail)
        .foregroundStyle(plugin.enabled && hiddenReason == nil ? .primary : .secondary)
        .layoutPriority(1)
      Spacer(minLength: 0)
      if !plugin.enabled {
        Text(L10n.t("layoutEditor.componentPill.off")).font(.caption2.weight(.medium))
          .padding(.horizontal, 5).background(Capsule().fill(.quaternary))
          .help(L10n.t("layoutEditor.componentPill.disabledHint"))
      }
      if let group {
        Text(verbatim: group).font(.caption2.weight(.medium)).lineLimit(1)
          .padding(.horizontal, 5).foregroundStyle(color ?? .secondary)
          .background(Capsule().fill((color ?? .secondary).opacity(0.15)))
          .frame(maxWidth: 90)
      }
      mark("desktopcomputer", layout?["display"] == .string("desktop-only") ? L10n.t("layoutEditor.displayDesktopOnly") : nil)
      mark("iphone", layout?["display"] == .string("mobile-only") ? L10n.t("layoutEditor.displayMobileOnly") : nil)
      mark("eye.slash", hiddenOnTypes)
      mark("line.3.horizontal.decrease.circle", layout?["condition"]?.stringValue.map(LayoutWords.condition))
    }
    .font(.callout)
    .padding(.horizontal, 6).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 6).fill(hiddenReason == nil ? AnyShapeStyle(.background) : AnyShapeStyle(.clear)))
    .overlay(RoundedRectangle(cornerRadius: 6)
      .strokeBorder(color ?? Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: color == nil ? 1 : 1.5, dash: hiddenReason == nil ? [] : [3, 2])))
    .overlay(RoundedRectangle(cornerRadius: 7).inset(by: -2).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
    .contentShape(Rectangle())
    .help(hiddenReason.map { "\(label) (\($0))" } ?? label)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(hiddenReason.map { "\(label) (\($0))" } ?? label)
    // What the marks say, in their words: the raw `display` was read out as "all" and
    // "desktop-only" (measured 2026-11-10), and the condition and "aus" were not read at all.
    .accessibilityValue([
      plugin.enabled ? nil : L10n.t("layoutEditor.componentPill.off"),
      LayoutWords.display(layout?["display"]),
      layout?["condition"]?.stringValue.map(LayoutWords.condition),
      hiddenOnTypes,
      // Named as a group: after "Ausgeblendet auf: 404-Seite" a bare "custom-8" was heard as one
      // more page type.
      group.map { L10n.t("layoutEditor.overview.flexGroup", ["name": $0]) },
    ].compactMap { $0 }.joined(separator: ", "))
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  @ViewBuilder private func mark(_ symbol: String, _ text: String?) -> some View {
    if let text {
      Image(systemName: symbol).font(.caption).foregroundStyle(.secondary).help(text).accessibilityLabel(text)
    }
  }
}

/// A chip of the tray: another instance of this component, or a switched-off one waiting.
struct PaletteChip: View {
  let name: String
  let off: Bool

  var body: some View {
    HStack(spacing: 4) {
      Text(verbatim: name)
      if off {
        Text(L10n.t("layoutEditor.componentPill.off")).padding(.horizontal, 5).background(Capsule().fill(.quaternary))
      }
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 8).padding(.vertical, 4)
    .foregroundStyle(off ? .secondary : .primary)
    .background(RoundedRectangle(cornerRadius: 6).fill(off ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.1)))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(off ? Color.secondary.opacity(0.4) : Color.accentColor.opacity(0.5),
                                                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    .help(off ? L10n.t("layoutEditor.componentPill.parkedHint") : name)
  }
}

/// A placed component as a pill, in its group's colour, with the marks that hold on every page:
/// the summary's and the overview's rows.
struct ComponentPill: View {
  let plugin: PluginEntry
  let label: String
  let groupNames: [String]
  var muted = false
  var struckReason: String?
  let action: () -> Void

  var body: some View {
    let layout = LayoutEntries.layout(plugin)
    let color = LayoutWords.groupColor(layout?["group"]?.stringValue, groupNames)
    Button(action: action) {
      HStack(spacing: 4) {
        Text(verbatim: label).strikethrough(struckReason != nil).lineLimit(1)
        if layout?["display"] == .string("desktop-only") { Image(systemName: "desktopcomputer").font(.caption2) }
        if layout?["display"] == .string("mobile-only") { Image(systemName: "iphone").font(.caption2) }
        if layout?["condition"]?.stringValue != nil { Image(systemName: "line.3.horizontal.decrease.circle").font(.caption2) }
      }
      .font(.callout)
      .padding(.horizontal, 8).padding(.vertical, 2)
      .foregroundStyle(color ?? .primary)
      .background(Capsule().fill((color ?? .secondary).opacity(color == nil ? 0.08 : 0.14)))
      .overlay(Capsule().strokeBorder((color ?? .secondary).opacity(0.4)))
      .opacity(muted || struckReason != nil ? 0.7 : 1)
    }
    .buttonStyle(.plain)
    .help(struckReason ?? label)
    .accessibilityLabel(struckReason.map { "\(label) – \($0)" } ?? label)
    .accessibilityValue([LayoutWords.display(layout?["display"]), layout?["condition"]?.stringValue.map(LayoutWords.condition)].compactMap { $0 }.joined(separator: ", "))
  }
}
