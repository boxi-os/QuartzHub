import QuartzHubCore
import SwiftUI

/// A box's name in the list: its title, else the file it shows, else its own class; "#n" only where
/// two would read the same (QuartzControl's `labelOf` in ExtraContent.tsx).
enum BoxLabels {
  static func base(_ box: LayoutBoxes.Box) -> String {
    let options = box.plugin.object["options"]
    if case .string(let title)? = options?["title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if LayoutBoxes.contentKind(options) == .file {
      let file = LayoutBoxes.snippetRefs(options).first?.file ?? ""
      return file.isEmpty ? L10n.t("extraContent.unnamed") : file
    }
    // Its own class, the last one: a copy carries the original's in front.
    if let own = InstanceClass.own(box.plugin) {
      return own.hasPrefix(InstanceClass.boxPrefix) ? String(own.dropFirst(InstanceClass.boxPrefix.count)) : own
    }
    return L10n.t("extraContent.unnamed")
  }

  static func label(_ box: LayoutBoxes.Box, among boxes: [LayoutBoxes.Box]) -> String {
    let base = base(box)
    return boxes.contains { $0.occurrence != box.occurrence && Self.base($0) == base } ? "\(base) #\(box.occurrence)" : base
  }
}

/// Zusätzliche Inhalte (QuartzControl's `routes/Plugins/ExtraContent.tsx`): the boxes of
/// quartz-layout-box as a list, the files behind them, the real site below; the selected box in
/// the inspector (`BoxInspector`). It starts from the question the generic form leaves to two
/// separate fields: is the content text in the configuration or a file.
///
/// Every change of the config goes through the plugin list's write queue (`PluginsModel.commit`);
/// the files go through `Snippets`.
struct ExtraContentTab: View {
  @Bindable var model: PluginsModel
  @Binding var selection: Int?
  @Binding var styled: Set<String>
  @Environment(\.unsavedGuard) private var unsaved
  /// The installed version, for the one rule that changed with it: a key left empty throws before 0.4.1.
  @State private var installed: String?

  private var boxes: [LayoutBoxes.Box] { LayoutBoxes.boxes(model.config?.plugins ?? []) }

  var body: some View {
    let boxes = boxes
    if let error = model.loadError {
      Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
    } else if model.config == nil {
      Text(L10n.t("common.loading")).foregroundStyle(.secondary).padding()
    } else if boxes.isEmpty {
      ContentUnavailableView {
        Label(L10n.t("extraContent.notInstalledTitle"), systemImage: "rectangle.topthird.inset.filled")
      } description: {
        Text(L10n.t("extraContent.notInstalledText"))
      }
    } else {
      VSplitView {
        list(boxes)
          .frame(minHeight: 170)
        ExtraContentFiles(projectPath: model.project.path, boxes: boxes, onSnippetRenamed: snippetRenamed)
          .frame(minHeight: 120)
        EditorPreview(project: model.project, prefix: "extraContent", hint: L10n.t("extraContent.previewHint"),
                      highlight: highlight(boxes), onAssignClass: assignClass)
          .frame(minHeight: 300)
      }
      .task(id: boxes.first?.plugin.source.map(JSJSON.compact) ?? "") {
        guard let source = PluginSource(boxes.first?.plugin.source) else { return }
        let environment = await AppServices.current()
        installed = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime).packageVersion
      }
    }
  }

  private func list(_ boxes: [LayoutBoxes.Box]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Note(L10n.t("extraContent.intro"))
      if let message = model.message { Text(message).foregroundStyle(.red).textSelection(.enabled).lineLimit(6) }
      HStack {
        Text(L10n.t("extraContent.listTitle", ["count": String(boxes.count)], count: boxes.count)).font(.headline)
        Spacer()
        Button { Task { await add(boxes) } } label: { Label(L10n.t("extraContent.add"), systemImage: "plus") }
          .disabled(model.busy)
          .accessibilityIdentifier("extras.add")
      }
      List(selection: $selection) {
        ForEach(boxes) { box in row(box, boxes: boxes).tag(box.occurrence) }
      }
      .accessibilityIdentifier("extras.list")
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
  }

  private func row(_ box: LayoutBoxes.Box, boxes: [LayoutBoxes.Box]) -> some View {
    let options = box.plugin.object["options"]
    let kind = LayoutBoxes.contentKind(options)
    let label = BoxLabels.label(box, among: boxes)
    var parts = LayoutBoxes.brokenOptions(options, installed: installed).prefix(1).map { L10n.t("extraContent.brokenRow", ["key": $0.key]) }
    parts.append(kind == .html ? L10n.t("extraContent.kindText")
      : L10n.t("extraContent.kindFile", ["file": "\(LayoutBoxes.dir(options))/\(LayoutBoxes.snippetRefs(options).first?.file ?? "")"]))
    if let layout = LayoutEntries.layout(box.plugin), case .string(let position)? = layout["position"] {
      parts.append(InstalledTab.positionTitle(position))
      if layout["display"] == .string("desktop-only") { parts.append(L10n.t("layoutEditor.displayDesktopOnly")) }
      if layout["display"] == .string("mobile-only") { parts.append(L10n.t("layoutEditor.displayMobileOnly")) }
    } else {
      parts.append(L10n.t("extraContent.notPlaced"))
    }
    return HStack(spacing: 8) {
      Image(systemName: kind == .html ? "chevron.left.forwardslash.chevron.right" : "doc.text")
        .foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(label).fontWeight(.medium)
        Text(parts.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      if !box.plugin.enabled { WordBadge(text: L10n.t("extraContent.off")) }
      Button { Task { await duplicate(box, boxes: boxes) } } label: {
        Label(L10n.t("extraContent.duplicateNamed", ["name": label]), systemImage: "plus.square.on.square").labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.t("extraContent.duplicateNamed", ["name": label]))
      .disabled(model.busy)
      // The last one is the plugin itself; removing that is the plugin list's job.
      if boxes.count > 1 {
        Button { Task { await remove(box, boxes: boxes) } } label: {
          Label(L10n.t("common.removeNamed", ["name": label]), systemImage: "trash").labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(L10n.t("common.removeNamed", ["name": label]))
        .disabled(model.busy)
      }
    }
    .padding(.vertical, 2)
    .contextMenu {
      Button(L10n.t("extraContent.duplicateNamed", ["name": label])) { Task { await duplicate(box, boxes: boxes) } }
      if boxes.count > 1 {
        Button(L10n.t("common.removeNamed", ["name": label]), role: .destructive) { Task { await remove(box, boxes: boxes) } }
      }
    }
    .accessibilityIdentifier("extras.row.\(box.occurrence)")
  }

  // MARK: Preview

  private func highlight(_ boxes: [LayoutBoxes.Box]) -> PreviewHighlight? {
    guard let selection, let current = boxes.first(where: { $0.occurrence == selection }),
          let found = ComponentSelectors.entry(current.plugin, siblings: boxes.map(\.plugin)) else { return nil }
    return PreviewHighlight(selector: found.selector, name: BoxLabels.label(current, among: boxes), matches: found.matches,
                            ownClass: found.ownClass, pages: nil)
  }

  // MARK: Writing

  private func add(_ boxes: [LayoutBoxes.Box]) async {
    guard let plugins = model.config?.plugins, let first = boxes.first else { return }
    // The plugin's own default place (its manifest: left), last there, ten after the rest.
    let position = "left"
    let priorities = plugins.compactMap { entry -> Double? in
      guard let layout = LayoutEntries.layout(entry), layout["position"] == .string(position) else { return nil }
      return layout["priority"]?.numberValue
    }
    let title = L10n.t("extraContent.newTitle")
    var object = JSONObject([("name", .string(LayoutBoxes.plugin))])
    object["source"] = first.plugin.object["source"]
    object["enabled"] = .bool(true)
    if let order = first.plugin.object["order"] { object["order"] = order }
    // A class of its own from the start, so a stylesheet and the preview can tell it apart.
    object["options"] = .object(JSONObject([
      ("title", .string(title)),
      ("html", .string(L10n.t("extraContent.newHtml"))),
      ("className", .string(InstanceClass.suggest(prefix: InstanceClass.boxPrefix, name: title, fallback: "box", plugins: plugins, styled: styled)))
    ]))
    object["layout"] = .object(JSONObject([("position", .string(position)), ("priority", .number((priorities.max() ?? 0) + 10))]))
    selection = boxes.count + 1
    if await model.commit({ $0 + [PluginEntry(object: object)] }) {
      Announce.post(L10n.t("extraContent.addedAnnounce", ["position": InstalledTab.positionTitle(position)]))
    }
  }

  private func duplicate(_ box: LayoutBoxes.Box, boxes: [LayoutBoxes.Box]) async {
    guard let plugins = model.config?.plugins, let result = LayoutEntries.duplicateAfter(plugins, box.index, styled: styled) else { return }
    // The copy lands right after the original, so it is the next box by number.
    selection = box.occurrence + 1
    if await model.commit({ _ in result.plugins }) {
      Announce.post(L10n.t("extraContent.duplicatedAnnounce", ["name": BoxLabels.label(box, among: boxes)]))
    }
  }

  private func remove(_ box: LayoutBoxes.Box, boxes: [LayoutBoxes.Box]) async {
    let name = BoxLabels.label(box, among: boxes)
    let (question, detail) = Confirm.split(L10n.t("extraContent.removeConfirm", ["name": name]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("common.remove"), destructive: true, window: unsaved?.window) else { return }
    if selection == box.occurrence { selection = nil } else if let s = selection, s > box.occurrence { selection = s - 1 }
    if await model.commit({ plugins in plugins.enumerated().filter { $0.offset != box.index }.map(\.element) }) {
      Announce.post(L10n.t("extraContent.removedAnnounce", ["name": name]))
    }
  }

  /// „Eigene Klasse vergeben“ beside the sentence that says the selected one has none.
  private func assignClass() {
    let boxes = boxes
    guard let selection, let plugins = model.config?.plugins, let box = boxes.first(where: { $0.occurrence == selection }) else { return }
    let cls = InstanceClass.suggest(prefix: InstanceClass.boxPrefix, name: InstanceClass.source(box.plugin), fallback: "box",
                                    plugins: plugins, styled: styled)
    let name = BoxLabels.label(box, among: boxes)
    Task {
      let done = await model.commit { plugins in
        plugins.enumerated().map { offset, plugin in
          guard offset == box.index else { return plugin }
          var object = plugin.object
          object["options"] = .object(InstanceClass.with(plugin.object["options"]?.objectValue, cls))
          return PluginEntry(object: object)
        }
      }
      if done { Announce.post(L10n.t("sitePreview.classAssigned", ["name": name, "cls": cls])) }
    }
  }

  /// False when the boxes that name the file could not be updated: the caller renames it back.
  private func snippetRenamed(dir: String, from: String, to: String) async -> Bool {
    guard let plugins = model.config?.plugins else { return false }
    let result = LayoutBoxes.renameSnippetRefs(plugins, dir: dir, from: from, to: to)
    if result.count == 0 {
      Announce.post(L10n.t("extraContent.files.renamedAnnounce", ["from": from, "to": to]))
      return true
    }
    let done = await model.commit { _ in result.plugins }
    if done {
      Announce.post(L10n.t("extraContent.files.renamedWithBoxes", ["from": from, "to": to, "count": String(result.count)], count: result.count))
    }
    return done
  }
}

/// The selected box in the inspector: on or off, its content as "Text | Datei", then the options
/// for that answer; the other one, if it is still set, stays in sight greyed as "wirkt nicht".
struct BoxInspector: View {
  let box: LayoutBoxes.Box
  let label: String
  @Bindable var model: PluginsModel
  let showAllOptions: () -> Void
  @Environment(\.openLayout) private var openLayout
  @Environment(\.unsavedGuard) private var unsaved
  @State private var schema: PluginOptionSchemaResult?
  @State private var loaded = false

  private var options: JSONObject { box.plugin.object["options"]?.objectValue ?? JSONObject() }

  var body: some View {
    let options = options
    let kind = LayoutBoxes.contentKind(.object(options))
    let installed = schema?.packageVersion
    let ownText = kind == .file ? LayoutBoxes.langsWithOwnText(.object(options)) : []
    let broken = LayoutBoxes.brokenOptions(box.plugin.object["options"], installed: installed)
    Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label(label, systemImage: "rectangle.topthird.inset.filled").font(.headline)
            .accessibilityIdentifier("extras.inspector.name")
          HStack(spacing: 6) {
            if case .string(let position)? = LayoutEntries.layout(box.plugin)?["position"] {
              Text(InstalledTab.positionTitle(position)).font(.caption).foregroundStyle(.secondary)
            } else {
              Text(L10n.t("extraContent.notPlaced")).font(.caption).foregroundStyle(.secondary)
            }
            if model.savedIndex == box.index { Text(L10n.t("pluginsInstalled.savedFlash")).font(.caption).foregroundStyle(.green) }
          }
          Note(L10n.t("plugins.savesImmediately"))
          if let installed, installed != LayoutBoxes.readAgainst, !LayoutBoxes.sameCode.contains(installed) {
            Text(L10n.t("plugins.readAgainst", ["plugin": LayoutBoxes.plugin, "read": LayoutBoxes.readAgainst, "installed": installed]))
              .font(.caption).foregroundStyle(.orange)
          }
        }
        Toggle(L10n.t("extraContent.enabled"), isOn: Binding(get: { box.plugin.enabled }, set: { _ in
          Task { await model.toggleEnabled(box.index) }
        }))
        .accessibilityIdentifier("extras.inspector.enabled")
      }
      Section(L10n.t("extraContent.contentHeading")) {
        // Below each other: side by side, "Konfiguration" broke in the middle of the word.
        VStack(alignment: .leading, spacing: 6) {
          tile(.html, current: kind, title: L10n.t("extraContent.contentText"), text: L10n.t("extraContent.contentTextHint"),
               symbol: "chevron.left.forwardslash.chevron.right")
          tile(.file, current: kind, title: L10n.t("extraContent.contentFile"), text: L10n.t("extraContent.contentFileHint"), symbol: "doc.text")
        }
        if !ownText.isEmpty { Note(L10n.t("extraContent.langOverride", ["langs": ownText.joined(separator: ", ")])) }
        ForEach(Array(broken.enumerated()), id: \.offset) { _, b in
          ErrorLine(b.lang == nil ? L10n.t("extraContent.broken", ["key": b.key])
                    : L10n.t("extraContent.brokenLang", ["key": b.key, "lang": b.lang ?? ""]))
        }
        VStack(alignment: .leading, spacing: 6) {
          Button(L10n.t("pluginsInstalled.showOnStage")) { openLayout(.component(model.config?.plugins ?? [], box.index)) }
          Button(L10n.t("extraContent.allOptions"), action: showAllOptions)
            .accessibilityIdentifier("extras.allOptions")
        }
      }
      if !loaded {
        Section(L10n.t("extraContent.optionsHeading")) {
          Text(L10n.t("layoutEditor.inspector.optionsLoading")).foregroundStyle(.secondary)
        }
      } else if let schema {
        Section {} header: { Text(L10n.t("extraContent.optionsHeading")) }
        // Text is not offered while a file is the content: the tile above switches to it. An
        // `html:` without a value is shown, greyed, or as the error it is before 0.4.1.
        OptionsForm(schema: schema.schema, values: options,
                    onChange: { next in Task { await model.updateField(box.index, path: ["options"], value: next.map(JSONValue.object)) } },
                    explicitEmpty: true, languages: model.config?.siteLanguages ?? [],
                    pick: { !(kind == .file && $0 == "html" && options["html"] == nil) }, freeKeys: false,
                    root: LayoutBoxes.root(options: options, installed: installed), projectPath: model.project.path)
      } else {
        Section(L10n.t("extraContent.optionsHeading")) {
          Text(L10n.t("layoutEditor.inspector.optionsError", ["reason": ""])).foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .disabled(model.busy)
    .task(id: box.plugin.source.map(JSJSON.compact) ?? "") {
      loaded = false
      if let source = PluginSource(box.plugin.source) {
        let environment = await AppServices.current()
        schema = await PluginSchemaReader.shared.optionSchema(project: model.project.path, source: source, runtime: environment.runtime)
      } else {
        schema = nil
      }
      loaded = true
    }
  }

  private func tile(_ kind: LayoutBoxes.ContentKind, current: LayoutBoxes.ContentKind, title: String, text: String, symbol: String) -> some View {
    let on = kind == current
    return Button { Task { await switchTo(kind) } } label: {
      VStack(alignment: .leading, spacing: 2) {
        Label(title, systemImage: symbol).fontWeight(.medium)
        Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
      .contentShape(Rectangle())
      .background(on ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.4)), in: RoundedRectangle(cornerRadius: 7))
      .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator)))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
    .accessibilityIdentifier("extras.kind.\(kind.rawValue)")
  }

  private func switchTo(_ next: LayoutBoxes.ContentKind) async {
    let values = options
    guard next != LayoutBoxes.contentKind(.object(values)) else { return }
    if next == .file {
      let text = values["html"]?.stringValue ?? ""
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let (question, detail) = Confirm.split(L10n.t("extraContent.toFileConfirm"))
        guard await Confirm.ask(question, detail: detail, confirm: L10n.t("extraContent.toFileConfirmLabel"), destructive: true,
                                window: unsaved?.window) else { return }
      }
      var rest = values
      rest["html"] = nil
      await model.updateField(box.index, path: ["options"], value: rest.isEmpty ? nil : .object(rest))
      return
    }
    // Into text: an HTML file the box showed becomes the starting text, so the box looks the same
    // until it is edited. Markdown is not HTML and is left behind; the file option stays, so a
    // switch back finds it. Without a text to start from, the new box's sample text: an empty one
    // renders nothing, and the box would vanish.
    var html = ""
    if let ref = LayoutBoxes.snippetRefs(.object(values)).first, ref.file.range(of: #"\.html?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
      let (project, dir, file) = (model.project.path, LayoutBoxes.dir(values), ref.file)
      html = (try? await Task.detached { try Snippets().readSnippet(project: project, dir: dir, file: file) }.value) ?? ""
    }
    var withText = values
    withText["html"] = .string(html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.t("extraContent.newHtml") : html)
    await model.updateField(box.index, path: ["options"], value: .object(withText))
  }
}
