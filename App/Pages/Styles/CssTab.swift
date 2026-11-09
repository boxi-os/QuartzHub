import QuartzHubCore
import SwiftUI

/// Eigenes CSS (QuartzControl's `Styles/CustomCss.tsx`): the last layer of the cascade. custom.scss,
/// `_quartzcontrol.scss` and every stylesheet under custom/ and imported/ in one editor with a tab
/// per open file, the SCSS check with the project's own Sass, and the load order in the inspector.
/// The drafts live in the page's model, so a switch to another tab keeps them.
struct CssTab: View {
  static let mainTab = ":main"

  let model: StylesModel
  let notes: AnyView
  @Binding var openTabs: String
  @Binding var activeTab: String
  /// Bumped by the page after a save: the check runs again.
  @Binding var check: ScssCheck.Result?
  @Binding var checking: Bool
  let runCheck: () async -> Void

  @Environment(\.unsavedGuard) private var unsaved
  @State private var insertion: CodeInsertion?
  @State private var jump: CodeJump?
  @State private var component = ""
  @State private var consolidating = false
  @State private var consolidated: String?
  @State private var actionError: String?

  private var scss: StylesModel.Scss? { model.scss }
  private var files: [StyleFiles.File] { model.fileSet?.files ?? [] }
  private var imported: [StyleFiles.File] { files.filter(\.imported) }

  static func label(_ tab: String, files: [StyleFiles.File]) -> String {
    tab == mainTab ? "custom.scss" : (files.first { $0.relativePath == tab }?.name ?? tab)
  }

  // MARK: Contents

  func contentOf(_ tab: String) -> String {
    if tab == Self.mainTab { return scss?.content ?? "" }
    if tab == StylesModel.managedStylesheet { return model.fileDrafts[tab] ?? scss?.info.managed?.content ?? "" }
    return model.fileDrafts[tab] ?? model.loadedFiles[tab] ?? ""
  }

  func onDisk(_ tab: String) -> String? {
    tab == StylesModel.managedStylesheet ? scss?.info.managed?.content : model.loadedFiles[tab]
  }

  func isDirty(_ tab: String) -> Bool {
    tab == Self.mainTab ? (scss?.dirty ?? false) : (model.fileDrafts[tab].map { $0 != onDisk(tab) } ?? false)
  }

  /// Typing a file's own content back drops the draft rather than keeping an identical one.
  private func setContent(_ value: String) {
    if activeTab == Self.mainTab {
      model.setScssContent(value)
    } else if value == onDisk(activeTab) {
      model.clearFileDrafts([activeTab])
    } else {
      model.setFileDraft(activeTab, value)
    }
  }

  private var tabs: [String] { [Self.mainTab] + VariablesPlace.lines(openTabs).filter { $0 != Self.mainTab } }

  func open(_ tab: String) {
    openTabs = VariablesPlace.adding(openTabs, tab)
    activeTab = tab
  }

  private func close(_ tab: String) {
    guard tab != Self.mainTab else { return }
    openTabs = VariablesPlace.lines(openTabs).filter { $0 != tab }.joined(separator: "\n")
    if activeTab == tab { activeTab = Self.mainTab }
  }

  private var activePath: String {
    if activeTab == Self.mainTab { return scss?.info.path ?? "" }
    if activeTab == StylesModel.managedStylesheet { return scss?.info.managed?.path ?? "" }
    return files.first { $0.relativePath == activeTab }?.path ?? ""
  }

  /// A diagnostic names a file on disk; only some of them are tabs here.
  private func tab(forFile relativePath: String) -> String? {
    if relativePath == "custom.scss" { return Self.mainTab }
    if relativePath == StylesModel.managedStylesheet { return scss?.info.managed == nil ? nil : StylesModel.managedStylesheet }
    return files.contains { $0.relativePath == relativePath } ? relativePath : nil
  }

  // MARK: The view

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      toolbar
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          notes
          consolidateNote
          staleBanners
          checkBanner
          if let actionError { Label(actionError, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled) }
          componentRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 220)
      .fixedSize(horizontal: false, vertical: true)
      tabBar
      if activeTab == StylesModel.managedStylesheet {
        Label(L10n.t("styleEditor.managedFile.warning"), systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
      }
      CodeEditor(text: Binding(get: { contentOf(activeTab) }, set: setContent),
                 language: activeTab.lowercased().hasSuffix(".css") ? .css : .scss, wraps: false,
                 insertion: insertion, jump: jump, name: Self.label(activeTab, files: files))
        .id(activeTab)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("css.editor")
    }
    .padding(16)
    .task(id: openTabs) { await loadOpenFiles() }
    .task(id: model.fileSet?.files.map(\.relativePath).joined(separator: "\n") ?? "") { pruneTabs() }
  }

  private var toolbar: some View {
    HStack {
      Text(activePath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      Spacer()
      Button(checking ? L10n.t("styleEditor.check.running") : L10n.t("styleEditor.check.checkActive")) { Task { await checkActive() } }
        .disabled(checking)
        .accessibilityIdentifier("css.checkActive")
      Button(L10n.t("styleEditor.openExternally")) { NSWorkspace.shared.open(URL(fileURLWithPath: activePath)) } // path boundary
        .disabled(activePath.isEmpty)
      Button(L10n.t("styleEditor.importFile")) { Task { await importFile() } }
    }
  }

  // MARK: Reading

  private func loadOpenFiles() async {
    let path = model.project.path
    for tab in VariablesPlace.lines(openTabs) where tab != Self.mainTab && tab != StylesModel.managedStylesheet && model.loadedFiles[tab] == nil {
      if let content = try? await Task.detached(operation: { try StyleFiles.read(tab, project: path) }).value { model.setLoaded(tab, content) }
    }
  }

  /// A tab whose file was deleted or renamed does not stay open on nothing.
  private func pruneTabs() {
    guard model.fileSet != nil else { return }
    var known: Set<String> = [Self.mainTab]
    if scss?.info.managed != nil { known.insert(StylesModel.managedStylesheet) }
    for file in files { known.insert(file.relativePath) }
    let kept = VariablesPlace.lines(openTabs).filter(known.contains)
    if kept != VariablesPlace.lines(openTabs) { openTabs = kept.joined(separator: "\n") }
    if !known.contains(activeTab) { activeTab = Self.mainTab }
  }

  /// What is in the editor right now, unsaved included: each stylesheet is its own Sass module, so
  /// compiling one alone is how the build sees it.
  private func checkActive() async {
    checking = true
    let environment = await AppServices.current()
    let entry = activeTab == Self.mainTab ? "custom.scss" : activeTab
    check = try? await ScssCheck.checkSource(entry, contentOf(activeTab), project: model.project.path, runtime: environment.runtime)
    checking = false
  }

  // MARK: Banners

  @ViewBuilder private var consolidateNote: some View {
    let legacy = StylesheetConsolidation.legacyCount(imported.map(\.relativePath), consolidated: model.fileSet?.consolidated ?? false)
    if legacy > 0 {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.t("styles.consolidate.note", ["count": String(legacy)]))
          HStack {
            Button(consolidating ? L10n.t("styles.consolidate.running") : L10n.t("styles.consolidate.action")) { Task { await consolidate(legacy) } }
              .disabled(consolidating || model.dirty)
            if model.dirty { Text(L10n.t("styles.migrate.saveFirst")).foregroundStyle(.secondary) }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    if let consolidated { Text(consolidated).font(.callout).foregroundStyle(.secondary) }
  }

  /// Asked natively because it removes files; not while the page holds drafts.
  private func consolidate(_ count: Int) async {
    let (question, detail) = Confirm.split(L10n.t("styles.consolidate.confirm", ["count": String(count)]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("styles.consolidate.action"), window: unsaved?.window) else { return }
    consolidating = true
    actionError = nil
    defer { consolidating = false }
    let environment = await AppServices.current()
    do {
      let result = try await StyleFiles.consolidate(project: model.project.path, snapshot: StyleFiles.snapshot(SnapshotStore.live(environment: environment).take))
      let renamed = result.renamed.map { L10n.t("styles.consolidate.renamed", ["from": $0.from, "to": $0.to]) }.joined(separator: " ")
      let sentence = [L10n.t("styles.consolidate.done", ["merged": String(result.merged), "written": String(result.written.count)]), renamed]
        .filter { !$0.isEmpty }.joined(separator: " ")
      await model.reloadFiles()
      await model.reloadScss(after: .stylesheets)
      consolidated = sentence
      Announce.post(sentence)
    } catch {
      actionError = StylesModel.message(error)
    }
  }

  static func staleSentence(_ writer: StylesModel.Writer, file: String) -> String {
    switch writer {
    case .variables: L10n.t("styles.scssStaleBy.variables", ["file": file])
    case .fontImport: L10n.t("styles.scssStaleBy.fontImport", ["file": file])
    case .fontRemoval: L10n.t("styles.scssStaleBy.fontRemoval", ["file": file])
    case .googleFonts: L10n.t("styles.scssStaleBy.googleFonts", ["file": file])
    case .stylesheets: L10n.t("styles.scssStaleBy.stylesheets", ["file": file])
    }
  }

  @ViewBuilder private var staleBanners: some View {
    if let writer = scss?.staleBy {
      HStack {
        Label(Self.staleSentence(writer, file: "custom.scss"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        Button(L10n.t("styles.scssStaleReload")) { Task { await model.reloadScss(after: nil) } }.buttonStyle(.link)
      }
      .accessibilityIdentifier("css.stale")
    }
    if let writer = model.managedStale, model.fileDrafts[StylesModel.managedStylesheet] != nil {
      HStack {
        Label(Self.staleSentence(writer, file: StylesModel.managedStylesheet), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        Button(L10n.t("styles.scssStaleReload")) { model.discardManagedDraft() }.buttonStyle(.link)
      }
    }
  }

  /// The whole chain compiled with the project's Sass: an error in any file is said, with the file
  /// and line it came from.
  @ViewBuilder private var checkBanner: some View {
    switch check {
    case .error(let diagnostic)?:
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Label(L10n.t("styleEditor.check.failed"), systemImage: "exclamationmark.octagon.fill").fontWeight(.medium)
          Spacer()
          Button(checking ? L10n.t("styleEditor.check.running") : L10n.t("styleEditor.check.recheck")) { Task { await runCheck() } }
            .buttonStyle(.link).disabled(checking)
        }
        Text(diagnostic.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        if let file = diagnostic.relativePath {
          let line = diagnostic.line.map(String.init) ?? "?"
          if let tab = tab(forFile: file) {
            Button(L10n.t("styleEditor.check.location", ["file": file, "line": line])) {
              open(tab)
              if let number = diagnostic.line { jump = CodeJump(line: number) }
            }
            .buttonStyle(.link)
          } else {
            Text(L10n.t("styleEditor.check.locationExternal", ["file": file, "line": line]))
          }
        }
        if diagnostic.managedFileMissing { Text(L10n.t("styleEditor.check.managedFileMissing")) }
        if diagnostic.nestedImportBlock {
          HStack(alignment: .firstTextBaseline) {
            Text(L10n.t("styleEditor.check.nestedImports"))
            Button(L10n.t("styleEditor.check.nestedImportsRepair")) { Task { await applyOrder(imported.map(\.relativePath)) } }
              .buttonStyle(.link).disabled(checking)
          }
        }
      }
      .font(.callout)
      .foregroundStyle(.red)
      .padding(8)
      .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
      .accessibilityIdentifier("css.checkFailed")
    case .unavailable(let reason)?:
      Note(L10n.t("styleEditor.check.unavailable", ["reason": reason]))
    case .ok?:
      HStack(spacing: 6) {
        Label(L10n.t("styleEditor.check.ok"), systemImage: "checkmark").foregroundStyle(.green)
        Button(checking ? L10n.t("styleEditor.check.running") : L10n.t("styleEditor.check.recheck")) { Task { await runCheck() } }
          .buttonStyle(.link).disabled(checking)
      }
      .font(.callout)
      .accessibilityIdentifier("css.checkOk")
    case nil:
      EmptyView()
    }
  }

  // MARK: Components

  private var componentRow: some View {
    let options = ComponentSelectors.list(model.config?.plugins ?? [])
    return HStack {
      Picker(L10n.t("styleEditor.componentPlaceholder"), selection: $component) {
        Text(L10n.t("styleEditor.componentPlaceholder")).tag("")
        ForEach(options, id: \.selector) { Text(Self.optionLabel($0)).tag($0.selector) }
      }
      .labelsHidden()
      .frame(maxWidth: 380)
      Button(L10n.t("styleEditor.insertSelector")) { insertion = CodeInsertion(text: "\n\(component) {\n  \n}\n") }
        .disabled(component.isEmpty)
      Text(L10n.t("styleEditor.componentHint")).font(.caption).foregroundStyle(.secondary)
    }
  }

  static func optionLabel(_ option: ComponentSelectors.Option) -> String {
    let args = ["name": option.name, "selector": option.selector]
    if let reach = option.reach {
      return reach.kind == "all" ? L10n.t("styleEditor.componentOptionWithCopies", args, count: reach.copies)
        : L10n.t("styleEditor.componentOptionOnly", args, count: reach.copies)
    }
    return option.measured ? L10n.t("styleEditor.componentOption", args) : L10n.t("styleEditor.componentOptionUnverified", args)
  }

  // MARK: Tabs

  private var tabBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 2) {
        ForEach(tabs, id: \.self) { tab in
          let active = tab == activeTab
          HStack(spacing: 4) {
            Button(Self.label(tab, files: files)) { activeTab = tab }
              .buttonStyle(.plain)
              .lineLimit(1)
            if isDirty(tab) {
              Circle().fill(Color.accentColor).frame(width: 6, height: 6).help(L10n.t("styleEditor.files.unsaved"))
                .accessibilityLabel(L10n.t("styleEditor.files.unsaved"))
            }
            if tab != Self.mainTab {
              Button { close(tab) } label: { Label(L10n.t("styleEditor.files.closeTab"), systemImage: "xmark") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).imageScale(.small)
            }
          }
          .font(.callout)
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(active ? AnyShapeStyle(.background) : AnyShapeStyle(.quaternary), in: UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("css.tab.\(tab)")
        }
      }
    }
  }

  // MARK: File operations

  /// Every file operation rewrites custom.scss's load order: its draft is read again (kept and
  /// flagged when it has edits), and the check runs.
  func afterFileOp() async {
    await model.reloadFiles()
    await model.reloadScss(after: .stylesheets)
    await runCheck()
  }

  func applyOrder(_ next: [String]) async {
    actionError = nil
    do {
      try await StyleSheets.setImportOrder(next, project: model.project.path)
      await afterFileOp()
    } catch {
      actionError = StylesModel.message(error)
    }
  }

  /// A stylesheet from anywhere is copied into imported/ and wired into the order.
  private func importFile() async {
    guard let picked = FilePick.one(extensions: ["scss", "css"], message: L10n.t("styleEditor.importFile")) else { return }
    actionError = nil
    do {
      let result = try await StyleFiles.importFile(picked, project: model.project.path)
      try await StyleSheets.setImportOrder(imported.map(\.relativePath) + [result.relativePath], project: model.project.path)
      await afterFileOp()
      open(result.relativePath)
    } catch {
      actionError = StylesModel.message(error)
    }
  }
}

/// The load order, in the inspector: which files custom.scss loads and in which order, the
/// managed file and custom.scss itself at the end, the files that exist but are not loaded, and
/// creating, renaming and deleting one.
struct CssFilesInspector: View {
  let model: StylesModel
  let activeTab: String
  let open: (String) -> Void
  let afterFileOp: () async -> Void
  let applyOrder: ([String]) async -> Void
  let extra: AnyView

  @Environment(\.unsavedGuard) private var unsaved
  @State private var creating: String?
  @State private var renaming: (path: String, name: String)?
  @State private var error: String?

  private var files: [StyleFiles.File] { model.fileSet?.files ?? [] }
  private var imported: [StyleFiles.File] { files.filter(\.imported) }

  var body: some View {
    Form {
      Section {
        Note(L10n.t("styleEditor.files.description"))
        ForEach(Array(imported.enumerated()), id: \.element.relativePath) { index, file in row(file, index: index) }
        if model.scss?.info.managed != nil {
          Button { open(StylesModel.managedStylesheet) } label: {
            LabeledContent(StylesModel.managedStylesheet, value: L10n.t("styleEditor.files.managedRow"))
              .font(.system(.callout, design: .monospaced))
          }
          .buttonStyle(.plain)
        }
        LabeledContent("custom.scss", value: L10n.t("styleEditor.files.alwaysLast")).font(.system(.callout, design: .monospaced))
        createRow
        if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
      } header: {
        Text(L10n.t("styleEditor.files.heading"))
      }
      // A stylesheet in no @use line does nothing, and looks like a working file in Finder.
      let orphans = files.filter { !$0.imported }
      if !orphans.isEmpty {
        Section(L10n.t("styleEditor.files.orphansHeading")) {
          ForEach(orphans, id: \.relativePath) { file in
            HStack {
              Text(file.name).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
              Spacer()
              Button(L10n.t("styleEditor.files.include")) { Task { await applyOrder(imported.map(\.relativePath) + [file.relativePath]) } }
            }
          }
        }
      }
      extra
    }
    .formStyle(.grouped)
  }

  @ViewBuilder private func row(_ file: StyleFiles.File, index: Int) -> some View {
    if let renaming, renaming.path == file.relativePath {
      HStack {
        TextField(L10n.t("styleEditor.files.rename"), text: Binding(get: { renaming.name }, set: { self.renaming?.name = $0 }))
          .labelsHidden().textFieldStyle(.roundedBorder)
        Button(L10n.t("common.save")) {
          Task { await run { _ = try await StyleFiles.rename(file.relativePath, to: StylesModel.trim(renaming.name), project: model.project.path); self.renaming = nil } }
        }
        Button(L10n.t("common.cancel")) { self.renaming = nil }
      }
    } else {
      HStack(spacing: 6) {
        Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 18, alignment: .trailing)
        Button(file.name) { open(file.relativePath) }
          .buttonStyle(.plain)
          .font(.system(.callout, design: .monospaced))
          .fontWeight(activeTab == file.relativePath ? .semibold : .regular)
          .lineLimit(1)
        Spacer()
        iconButton(L10n.t("styleEditor.files.moveUp"), "arrow.up", disabled: index == 0) { await move(file, -1) }
        iconButton(L10n.t("styleEditor.files.moveDown"), "arrow.down", disabled: index == imported.count - 1) { await move(file, 1) }
        iconButton(L10n.t("styleEditor.files.rename"), "pencil") { renaming = (file.relativePath, file.name) }
        iconButton(L10n.t("common.deleteNamed", ["name": file.name]), "trash") { await delete(file) }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("css.file.\(file.relativePath)")
    }
  }

  private func iconButton(_ name: String, _ symbol: String, disabled: Bool = false, action: @escaping () async -> Void) -> some View {
    Button { Task { await action() } } label: { Label(name, systemImage: symbol) }
      .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(disabled).help(name)
  }

  @ViewBuilder private var createRow: some View {
    if let creating {
      VStack(alignment: .trailing) {
        TextField(L10n.t("styleEditor.files.namePlaceholder"), text: Binding(get: { creating }, set: { self.creating = $0 }),
                  prompt: Text(L10n.t("styleEditor.files.namePlaceholder")))
          .labelsHidden().textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("css.newName")
        HStack {
        Button(L10n.t("common.cancel")) { self.creating = nil }
        Button(L10n.t("styleEditor.files.createConfirm")) {
          Task {
            await run {
              let created = try await StyleFiles.create(StylesModel.trim(creating), project: model.project.path)
              self.creating = nil
              open(created.relativePath)
            }
          }
        }
        .disabled(StylesModel.trim(creating).isEmpty)
        .accessibilityIdentifier("css.createConfirm")
        }
      }
    } else {
      Button { creating = "" } label: { Label(L10n.t("styleEditor.files.create"), systemImage: "plus") }
        .accessibilityIdentifier("css.create")
    }
  }

  private func run(_ action: () async throws -> Void) async {
    error = nil
    do {
      try await action()
      await afterFileOp()
    } catch {
      self.error = StylesModel.message(error)
    }
  }

  private func move(_ file: StyleFiles.File, _ delta: Int) async {
    var order = imported.map(\.relativePath)
    guard let from = order.firstIndex(of: file.relativePath), order.indices.contains(from + delta) else { return }
    order.swapAt(from, from + delta)
    await applyOrder(order)
    Announce.post(file.name)
  }

  private func delete(_ file: StyleFiles.File) async {
    let (question, detail) = Confirm.split(L10n.t("styleEditor.files.confirmDelete", ["name": file.name]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("styleEditor.files.confirmDeleteAction"), destructive: true,
                            window: unsaved?.window) else { return }
    await run { try await StyleFiles.delete(file.relativePath, project: model.project.path) }
  }
}
