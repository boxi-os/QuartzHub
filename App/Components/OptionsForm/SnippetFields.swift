import QuartzHubCore
import SwiftUI

// The editors behind `x-quartz-widget: snippetFile` and the picture button of `html`/`markdown`
// (QuartzControl's `PluginOptionsForm/snippets.tsx`). Picked by the schema's widget, not by the
// plugin's name. Every file operation goes through `Snippets`, which decides what may be read and
// written.

/// "Bild einfügen…": copies a picture into quartz/static/images and hands back the reference. A
/// picture of the same name is a question: replace it, or use the one there. An SVG may go in as
/// its own markup instead (`InlineSvg`), so the site's CSS can style it.
struct ImageButton: View {
  let projectPath: String
  let format: LayoutBoxes.SnippetFormat
  /// The plugin's `placeholders` is off: `{{root}}` would stay as it is, and the picture not load.
  let placeholdersOff: Bool
  let onInsert: (String) -> Void

  @State private var busy = false
  @State private var error: String?
  @State private var note: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        Task { await pick() }
      } label: {
        Label(L10n.t("snippets.insertImage"), systemImage: "photo.badge.plus")
      }
      .disabled(busy)
      if placeholdersOff { Warning(L10n.t("snippets.placeholdersOff", ["token": "{{root}}"])) }
      if let note { Warning(note) }
      if let error { ErrorLine(error) }
    }
  }

  private func pick() async {
    guard let source = FilePick.one(extensions: ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"],
                                    message: L10n.t("snippets.imageFilter")) else { return }
    error = nil
    note = nil
    let window = NSApp.keyWindow
    if NodePath.extname(source).lowercased() == ".svg" {
      let (question, detail) = Confirm.split(L10n.t("snippets.svgHow"))
      switch await Confirm.choose(question, detail: detail, alternative: L10n.t("snippets.svgAsImage"),
                                  confirm: L10n.t("snippets.svgInline"), window: window) {
      case .cancel: return
      case .alternative: break
      case .confirm:
        let name = NodePath.basename(source)
        do {
          let text = try await Task.detached { try Snippets.svgSource(source) }.value
          guard let result = InlineSvg.clean(text, fileName: name) else {
            error = L10n.t("snippets.svgInvalid", ["name": name])
            return
          }
          onInsert(result.markup)
          if result.removed > 0 {
            let cleaned = L10n.t("snippets.svgCleaned", ["count": String(result.removed)], count: result.removed)
            note = result.styled ? "\(cleaned) \(L10n.t("snippets.svgStyleRemoved"))" : cleaned
          }
        } catch {
          self.error = String(describing: error).replacingOccurrences(of: "Error: ", with: "")
        }
        return
      }
    }
    busy = true
    defer { busy = false }
    let project = projectPath
    do {
      var result = try await Task.detached { try Snippets().importImage(project: project, source: source, name: nil, overwrite: false) }.value
      if case .exists(let name) = result {
        let (question, detail) = Confirm.split(L10n.t("snippets.imageExists", ["name": name]))
        switch await Confirm.choose(question, detail: detail, alternative: L10n.t("snippets.useExisting"),
                                    confirm: L10n.t("snippets.replace"), destructive: true, window: window) {
        case .cancel: return
        case .alternative: break
        case .confirm:
          result = try await Task.detached { try Snippets().importImage(project: project, source: source, name: nil, overwrite: true) }.value
        }
      }
      let path = switch result { case .written(let p), .exists(let p): p }
      onInsert(LayoutBoxes.imageReference(path, format: format))
    } catch {
      self.error = SnippetFailure.text(error)
    }
  }
}

/// The sentence of a failure from `Snippets`, without the "Error: " a log line carries.
enum SnippetFailure {
  /// A sentence of the page's own, thrown where the next step must not run.
  struct Said: Error { let text: String }

  static func text(_ error: Error) -> String {
    if let failure = error as? Snippets.Failure { return failure.message }
    if let said = error as? Said { return said.text }
    return error.localizedDescription
  }
}

/// The placeholders a layout box can use, folded under a summary; each token is a button that puts
/// it in at the cursor. `off`: the plugin's `placeholders` is false, and the tokens stay as text.
struct PlaceholderList: View {
  let onInsert: (String) -> Void
  let off: Bool

  private var rows: [(token: String, meaning: String)] {
    LayoutBoxes.placeholders.map { ("{{\($0)}}", Self.meaning($0)) }
      + [("{{\(LayoutBoxes.frontmatterPlaceholder)author}}", L10n.t("snippets.placeholders.frontmatter"))]
  }

  static func meaning(_ name: String) -> String {
    switch name {
    case "title": L10n.t("snippets.placeholders.title")
    case "slug": L10n.t("snippets.placeholders.slug")
    case "root": L10n.t("snippets.placeholders.root", ["example": "{{root}}/static/images/logo.png"])
    case "siteTitle": L10n.t("snippets.placeholders.siteTitle")
    case "baseUrl": L10n.t("snippets.placeholders.baseUrl")
    case "locale": L10n.t("snippets.placeholders.locale")
    case "lang": L10n.t("snippets.placeholders.lang")
    default: name
    }
  }

  var body: some View {
    let rows = rows
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.t("snippets.placeholders.introInsert")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if off { Warning(L10n.t("snippets.placeholders.off")) }
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
          ForEach(rows, id: \.token) { row in
            GridRow {
              Button(row.token) { onInsert(row.token) }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .font(.system(.caption, design: .monospaced))
                .fixedSize()
                .help(L10n.t("snippets.placeholders.insertNamed", ["token": row.token]))
                .accessibilityLabel(L10n.t("snippets.placeholders.insertNamed", ["token": row.token]))
              Text(row.meaning).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      .padding(.top, 4)
    } label: {
      Label(L10n.t("snippets.placeholders.summary", ["count": String(rows.count)]), systemImage: "curlybraces")
    }
    .font(.caption)
  }
}

/// A layout box's `file`: a choice from the files in `dir`, with "Neu", "Importieren…" and
/// "Bearbeiten". `dir` is the sibling option the schema names (`x-quartz-dir-option`).
struct SnippetFileField: View {
  let projectPath: String
  let dir: String
  let value: JSONValue?
  let defaultValue: JSONValue?
  let hasDefault: Bool
  let placeholdersOff: Bool
  /// The field does nothing right now (text wins): a missing file then empties nothing.
  var silenced = false
  let onValue: (JSONValue?) -> Void
  let name: String

  @State private var listing: Snippets.Listing?
  @State private var reload = 0
  @State private var error: String?
  @State private var newName: String?
  @State private var newExtension = ".md"
  /// Which file this field has open. Not sticky: a key per folder opened the editor in every box
  /// that shares the folder (QuartzControl, 1.1 P6). The draft itself is sticky, per file.
  @State private var editing: String?

  private static let notSet = "\u{0}notSet"

  var body: some View {
    let current = value?.stringValue
    let effective = current ?? defaultValue?.stringValue
    let files = listing?.files ?? []
    let writable = listing?.state == .ok || listing?.state == .missing
    let unlisted = current.map { !files.contains($0) } ?? false
    let effectiveExists = effective.map(files.contains) ?? false
    Group {
      if let listing, listing.state == .outside || listing.state == .reserved {
        // Nothing to choose from: the value stays editable as text, and the sentence says why.
        VStack(alignment: .leading, spacing: 4) {
          CommitField(name: name, text: current ?? "", placeholder: hasDefault ? defaultValue.map(OptionFormText.inline) : nil) { raw in
            if raw != (current ?? "") { onValue(raw.isEmpty ? nil : .string(raw)) }
            return true
          }
          Warning(listing.state == .outside ? L10n.t("snippets.dir.outside", ["dir": dir]) : L10n.t("snippets.dir.reserved", ["dir": dir]))
        }
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Picker(name, selection: Binding(get: { current ?? Self.notSet }, set: { onValue($0 == Self.notSet ? nil : .string($0)) })) {
            Text(hasDefault ? L10n.t("pluginOptions.defaultChoice", ["value": defaultValue.map(OptionFormText.inline) ?? ""])
                 : L10n.t("pluginOptions.notSet")).tag(Self.notSet)
            if let current, unlisted { Text(L10n.t("snippets.notInDir", ["name": current])).tag(current) }
            ForEach(files, id: \.self) { Text($0).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
          // Below the choice: beside it, the three were cut to their first letter in the inspector.
          HStack(spacing: 6) {
            if writable {
              Button(L10n.t("snippets.new")) { newName = newName == nil ? "" : nil }
              Button(L10n.t("snippets.import")) { Task { await importFile() } }
            }
            if writable, effectiveExists, let effective {
              Button(L10n.t("snippets.edit")) { editing = editing == effective ? nil : effective }
            }
          }
          if listing?.state == .link { Note(L10n.t("snippets.dir.link", ["dir": dir])) }
          if listing?.state == .missing { Note(L10n.t("snippets.dir.missing", ["dir": dir])) }
          if listing != nil, !silenced, let effective, !effectiveExists, listing?.state != .missing {
            Warning(L10n.t("snippets.missingFile", ["name": effective, "dir": dir]))
          }
          if newName != nil {
            NewSnippetRow(name: Binding(get: { newName ?? "" }, set: { newName = $0 }), fileExtension: $newExtension) {
              Task { await create() }
            }
          }
          if let error { ErrorLine(error) }
          if let editing, writable, files.contains(editing) {
            SnippetEditor(projectPath: projectPath, dir: dir, file: editing, placeholdersOff: placeholdersOff) { self.editing = nil }
              .id("\(dir)/\(editing)")
          }
        }
      }
    }
    .task(id: "\(projectPath)\n\(dir)\n\(reload)") { await load() }
  }

  private func load() async {
    let (project, dir) = (projectPath, dir)
    do {
      listing = try await Task.detached { try Snippets().listSnippets(project: project, dir: dir) }.value
    } catch {
      self.error = SnippetFailure.text(error)
    }
  }

  /// An existing file is a question with three answers: replace, use it, or stop.
  private func resolveExists(_ file: String, replace: @escaping @Sendable () throws -> Void) async throws -> Bool {
    let (question, detail) = Confirm.split(L10n.t("snippets.fileExists", ["name": file, "dir": dir]))
    switch await Confirm.choose(question, detail: detail, alternative: L10n.t("snippets.useExisting"),
                                confirm: L10n.t("snippets.replace"), destructive: true, window: NSApp.keyWindow) {
    case .cancel: return false
    case .alternative: return true
    case .confirm:
      try await Task.detached(operation: replace).value
      return true
    }
  }

  private func run(_ action: () async throws -> Void) async {
    error = nil
    do { try await action() } catch { self.error = SnippetFailure.text(error) }
    reload += 1
  }

  private func create() async {
    await run {
      let base = (newName ?? "").trimmingCharacters(in: .whitespaces)
      guard !base.isEmpty else { return }
      let file = base.range(of: #"\.(md|html?)$"#, options: [.regularExpression, .caseInsensitive]) != nil ? base : base + newExtension
      let (project, dir) = (projectPath, dir)
      let result = try await Task.detached { try Snippets().writeSnippet(project: project, dir: dir, file: file, content: "", overwrite: false) }.value
      let written: String
      switch result {
      case .written(let name): written = name
      case .exists(let name):
        guard try await resolveExists(name, replace: {
          _ = try Snippets().writeSnippet(project: project, dir: dir, file: name, content: "", overwrite: true)
        }) else { return }
        written = name
      }
      newName = nil
      onValue(.string(written))
      editing = written
    }
  }

  private func importFile() async {
    await run {
      guard let source = FilePick.one(extensions: ["md", "html", "htm"], message: L10n.t("snippets.snippetFilter")) else { return }
      let (project, dir) = (projectPath, dir)
      let result = try await Task.detached { try Snippets().importSnippet(project: project, dir: dir, source: source, name: nil, overwrite: false) }.value
      switch result {
      case .written(let name): onValue(.string(name))
      case .exists(let name):
        guard try await resolveExists(name, replace: {
          _ = try Snippets().importSnippet(project: project, dir: dir, source: source, name: nil, overwrite: true)
        }) else { return }
        onValue(.string(name))
      }
    }
  }
}

/// Name and format of a new snippet, then "Anlegen".
struct NewSnippetRow: View {
  @Binding var name: String
  @Binding var fileExtension: String
  let create: () -> Void

  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 6) {
      TextField(L10n.t("snippets.newName"), text: $name, prompt: Text(L10n.t("snippets.newNamePlaceholder")))
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onAppear { focused = true }
        .frame(maxWidth: 170)
        .onSubmit(create)
      Picker(L10n.t("snippets.newFormat"), selection: $fileExtension) {
        Text(L10n.t("snippets.formatMarkdown")).tag(".md")
        Text(L10n.t("snippets.formatHtml")).tag(".html")
      }
      .labelsHidden()
      .fixedSize()
      Button(L10n.t("snippets.create"), action: create)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
}

/// One snippet file in the code editor. It writes the file with its own button, "Snippet
/// speichern", not with the options: a knob that saves part of a page carries its reach in its
/// name. The draft survives a change of page (per file, in the window's scene storage); closing
/// with unsaved changes asks.
struct SnippetEditor: View {
  let projectPath: String
  let dir: String
  let file: String
  let placeholdersOff: Bool
  let onClose: () -> Void
  /// After the file is written: for a list that shows what the files contain.
  var onSaved: (() -> Void)?

  @SceneStorage private var draft: String?
  @State private var saved: String?
  @State private var status: String?
  @State private var error: String?
  @State private var insertion: CodeInsertion?

  init(projectPath: String, dir: String, file: String, placeholdersOff: Bool, onSaved: (() -> Void)? = nil, onClose: @escaping () -> Void) {
    self.projectPath = projectPath
    self.dir = dir
    self.file = file
    self.placeholdersOff = placeholdersOff
    self.onSaved = onSaved
    self.onClose = onClose
    _draft = SceneStorage("snippets.draft:\(dir)/\(file)")
  }

  private var format: LayoutBoxes.SnippetFormat { LayoutBoxes.format(ofFile: file) }
  private var dirty: Bool { draft != nil && saved != nil && draft != saved }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(file).font(.system(.callout, design: .monospaced).weight(.semibold))
          .lineLimit(1).truncationMode(.middle)
        Text(format == .markdown ? L10n.t("snippets.formatMarkdown") : L10n.t("snippets.formatHtml"))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        if dirty { Text(L10n.t("snippets.unsaved")).font(.caption).foregroundStyle(.secondary) }
      }
      // A line of its own: beside the name, the sentence squeezed it to "side…te.md".
      if !dirty, let status { Text(status).font(.caption).foregroundStyle(.secondary) }
      if saved == nil, error == nil {
        Text(L10n.t("common.loading")).font(.caption).foregroundStyle(.secondary)
      } else {
        CodeEditor(text: Binding(get: { draft ?? saved ?? "" }, set: { draft = $0; status = nil }),
                   language: format == .markdown ? .markdown : .html, insertion: insertion, name: file)
          .frame(height: 240)
          .clipShape(RoundedRectangle(cornerRadius: 5))
          .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
      }
      Note(L10n.t("snippets.saveHint"))
      PlaceholderList(onInsert: { insertion = CodeInsertion(text: $0) }, off: placeholdersOff)
      // The picture on a line of its own: in the inspector's width, three in a row were cut short.
      ImageButton(projectPath: projectPath, format: format, placeholdersOff: placeholdersOff) { insertion = CodeInsertion(text: $0) }
      HStack(spacing: 6) {
        Spacer()
        Button(L10n.t("snippets.close")) { Task { await close() } }
        Button(L10n.t("snippets.save")) { Task { await save() } }
          .disabled(!dirty)
      }
      if let error { ErrorLine(error) }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.4)))
    .task(id: "\(projectPath)\n\(dir)\n\(file)") { await load() }
  }

  private func load() async {
    let (project, dir, file) = (projectPath, dir, file)
    do {
      saved = try await Task.detached { try Snippets().readSnippet(project: project, dir: dir, file: file) }.value
    } catch {
      self.error = SnippetFailure.text(error)
    }
  }

  private func save() async {
    guard let text = draft else { return }
    error = nil
    let (project, dir, file) = (projectPath, dir, file)
    do {
      _ = try await Task.detached { try Snippets().writeSnippet(project: project, dir: dir, file: file, content: text, overwrite: true) }.value
      saved = text
      draft = nil
      status = L10n.t("snippets.saved", ["name": file])
      Announce.post(L10n.t("snippets.saved", ["name": file]))
      onSaved?()
    } catch {
      self.error = SnippetFailure.text(error)
    }
  }

  private func close() async {
    if dirty {
      let (question, detail) = Confirm.split(L10n.t("snippets.discardConfirm", ["name": file]))
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("snippets.discard"), destructive: true, window: NSApp.keyWindow) else { return }
    }
    draft = nil
    onClose()
  }
}

/// A sentence in the warning colour: something will not work as one expects.
struct Warning: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
  }
}

/// A sentence in the error colour: something failed.
struct ErrorLine: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
  }
}
