import AppKit
import QuartzHubCore
import SwiftUI

/// The files behind the layout boxes (QuartzControl's `ExtraContentFiles.tsx`): the snippets in
/// each folder a box reads from, and the pictures in quartz/static/images, each with the boxes or
/// snippets that use it. Every operation goes through `Snippets`; a file is never deleted, only
/// moved to the trash. Renaming a snippet updates the boxes that name it; renaming a picture does
/// not touch the text that mentions it, and asks first when something does.
struct ExtraContentFiles: View {
  let projectPath: String
  let boxes: [LayoutBoxes.Box]
  /// False when the config could not follow; the file is then renamed back.
  let onSnippetRenamed: (String, String, String) async -> Bool
  @Environment(\.unsavedGuard) private var unsaved

  @State private var snippetDirs: [String: Snippets.Listing] = [:]
  /// What each snippet says, for the question which pictures it shows. Keyed `dir/file`.
  @State private var contents: [String: String] = [:]
  @State private var images: Snippets.Listing?
  @State private var icon: ProjectIcon.Info?
  /// Two errors, because the list is read again after every action: one shared state let the
  /// successful reload clear the action's message in the same breath (QuartzControl, 41st review).
  @State private var loadError: String?
  @State private var actionError: String?
  @State private var reload = 0

  /// Each folder once, in JavaScript's default sort (UTF-16 units).
  private var dirs: [String] {
    var set: [String] = []
    for box in boxes {
      let options = box.plugin.object["options"]
      for dir in [LayoutBoxes.dir(options)] + LayoutBoxes.snippetRefs(options).map(\.dir) where !set.contains(dir) { set.append(dir) }
    }
    return set.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
  }

  var body: some View {
    let dirs = dirs
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(L10n.t("extraContent.files.title")).font(.headline)
        Note(L10n.t("extraContent.files.intro"))
        ForEach([actionError, loadError].compactMap { $0 }, id: \.self) { Callout(.error, $0) }
        ForEach(dirs, id: \.self) { dir in
          FileSection(kind: .snippet, dir: dir, heading: L10n.t("extraContent.files.snippetsIn", ["dir": dir]),
                      info: snippetDirs[dir], usersOf: { snippetUsers(dir, $0) }, projectPath: projectPath,
                      onAdd: { Task { await addSnippet(dir) } },
                      onNew: { name in await newSnippet(dir, name) },
                      onRename: { from, to in await rename(.snippet, dir, from, to) },
                      onTrash: { file, users in Task { await trash(.snippet, dir, file, users) } },
                      onSaved: { reload += 1 })
        }
        FileSection(kind: .image, dir: LayoutBoxes.imagesDir, heading: L10n.t("extraContent.files.images", ["dir": LayoutBoxes.imagesDir]),
                    note: L10n.t("extraContent.files.imagesSearched"), info: images, usersOf: imageUsers, projectPath: projectPath,
                    onAdd: { Task { await addImage() } }, onNew: nil,
                    onRename: { from, to in await rename(.image, LayoutBoxes.imagesDir, from, to) },
                    onTrash: { file, users in Task { await trash(.image, LayoutBoxes.imagesDir, file, users) } },
                    onSaved: nil)
        projectIconSection
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    // The files the boxes name are part of the key: "Neu" and "Importieren…" in a box's own field
    // write a file and name it, and without them the list went on without the new file
    // (measured 2026-11-09).
    .task(id: "\(projectPath)\n\(dirs.joined(separator: "\n"))\n\(namedFiles)\n\(reload)") { await load(dirs) }
  }

  /// Every snippet file a box renders, as folder and name.
  private var namedFiles: String {
    boxes.flatMap { LayoutBoxes.snippetRefs($0.plugin.object["options"]).map { "\($0.dir)/\($0.file)" } }.joined(separator: "\n")
  }

  private func load(_ dirs: [String]) async {
    let project = projectPath
    do {
      let read = try await Task.detached { () throws -> ([String: Snippets.Listing], [String: String], Snippets.Listing, ProjectIcon.Info) in
        let snippets = Snippets()
        var listed: [String: Snippets.Listing] = [:]
        var texts: [String: String] = [:]
        for dir in dirs {
          let info = try snippets.listSnippets(project: project, dir: dir)
          listed[dir] = info
          guard info.state == .ok || info.state == .link else { continue }
          for file in info.files { texts["\(dir)/\(file)"] = (try? snippets.readSnippet(project: project, dir: dir, file: file)) ?? "" }
        }
        return (listed, texts, try snippets.listImages(project: project), ProjectIcon.info(project: project))
      }.value
      (snippetDirs, contents, images, icon) = read
      loadError = nil
    } catch {
      loadError = SnippetFailure.text(error)
    }
  }

  // MARK: Who uses what

  private func label(_ box: LayoutBoxes.Box) -> String { BoxLabels.label(box, among: boxes) }

  private func snippetUsers(_ dir: String, _ file: String) -> [String] {
    boxes.compactMap { box in
      let refs = LayoutBoxes.snippetRefs(box.plugin.object["options"]).filter { $0.dir == dir && $0.file == file }
      guard !refs.isEmpty else { return nil }
      return refs.allSatisfy(\.inherited) ? L10n.t("extraContent.files.inherited", ["name": label(box)]) : label(box)
    }
  }

  /// The text's file names in key order, as QuartzControl's `Object.entries` lists them.
  private func snippetsMentioning(_ test: (String) -> Bool) -> [String] {
    contents.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
      .filter { test(contents[$0] ?? "") }
      .map { String($0[$0.index(after: $0.lastIndex(of: "/") ?? $0.startIndex)...]) }
  }

  private func imageUsers(_ name: String) -> [String] {
    boxes.filter { LayoutBoxes.htmls($0.plugin.object["options"]).contains { LayoutBoxes.mentionsImage($0, name) } }.map(label)
      + snippetsMentioning { LayoutBoxes.mentionsImage($0, name) }
  }

  /// The project picture lies in quartz/static itself, not in images/: Quartz's favicon emitter
  /// reads it from there and nowhere else, so a snippet names it as static/icon.png.
  private func iconUsers(_ name: String) -> [String] {
    boxes.filter { LayoutBoxes.htmls($0.plugin.object["options"]).contains { $0.range(of: "static/\(name)", options: .literal) != nil } }.map(label)
      + snippetsMentioning { $0.range(of: "static/\(name)", options: .literal) != nil }
  }

  // MARK: Actions

  private func run(_ action: () async throws -> Void) async {
    actionError = nil
    do { try await action() } catch { actionError = SnippetFailure.text(error) }
    reload += 1
  }

  /// An existing file: replace it or stop. Two answers here, not the field's three: "Vorhandene
  /// verwenden" selects the file for a field, and this list has nothing to select, so the
  /// answer did what "Abbrechen" does (review 2026-11-13, nebenbei).
  private func askReplace(_ name: String, _ dir: String) async -> Bool {
    let (question, detail) = Confirm.split(L10n.t("extraContent.files.exists", ["name": name, "dir": dir]))
    return await Confirm.ask(question, detail: detail, confirm: L10n.t("snippets.replace"), destructive: true, window: unsaved?.window)
  }

  private func addSnippet(_ dir: String) async {
    await run {
      guard let source = FilePick.one(extensions: ["md", "html", "htm"], message: L10n.t("snippets.snippetFilter")) else { return }
      let project = projectPath
      var result = try await Task.detached { try Snippets().importSnippet(project: project, dir: dir, source: source, name: nil, overwrite: false) }.value
      if case .exists(let name) = result {
        guard await askReplace(name, dir) else { return }
        result = try await Task.detached { try Snippets().importSnippet(project: project, dir: dir, source: source, name: nil, overwrite: true) }.value
      }
      if case .written(let name) = result { Announce.post(L10n.t("extraContent.files.addedAnnounce", ["name": name])) }
    }
  }

  private func newSnippet(_ dir: String, _ name: String) async {
    await run {
      let project = projectPath
      let result = try await Task.detached { try Snippets().writeSnippet(project: project, dir: dir, file: name, content: "", overwrite: false) }.value
      switch result {
      case .written(let file): Announce.post(L10n.t("extraContent.files.addedAnnounce", ["name": file]))
      case .exists(let file):
        guard await askReplace(file, dir) else { return }
        _ = try await Task.detached { try Snippets().writeSnippet(project: project, dir: dir, file: file, content: "", overwrite: true) }.value
        Announce.post(L10n.t("extraContent.files.addedAnnounce", ["name": file]))
      }
    }
  }

  private func addImage() async {
    await run {
      guard let source = FilePick.one(extensions: ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"], message: L10n.t("snippets.imageFilter"))
      else { return }
      let project = projectPath
      var result = try await Task.detached { try Snippets().importImage(project: project, source: source, name: nil, overwrite: false) }.value
      if case .exists(let path) = result {
        // The name alone: with the folder named after it, the question read „„images/x.png“ gibt
        // es in quartz/static/images schon“, the folder twice (measured 2026-11-09).
        guard await askReplace(String(path.dropFirst("images/".count)), LayoutBoxes.imagesDir) else { return }
        result = try await Task.detached { try Snippets().importImage(project: project, source: source, name: nil, overwrite: true) }.value
      }
      if case .written(let path) = result {
        Announce.post(L10n.t("extraContent.files.addedAnnounce", ["name": String(path.dropFirst("images/".count))]))
      }
    }
  }

  /// The sentence for the rename row when the name is taken, nil when done.
  private func rename(_ kind: Snippets.Kind, _ dir: String, _ from: String, _ to: String) async -> String? {
    let users = kind == .image ? imageUsers(from) : []
    if !users.isEmpty {
      let (question, detail) = Confirm.split(L10n.t("extraContent.files.imageRenameConfirm", ["name": from, "names": users.joined(separator: ", ")]))
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("extraContent.files.renameSubmit"), window: unsaved?.window) else { return nil }
    }
    var taken: String?
    await run {
      let project = projectPath
      let place: String? = kind == .snippet ? dir : nil
      let result = try await Task.detached { try Snippets().rename(project: project, kind: kind, dir: place, from: from, to: to) }.value
      guard case .written(let renamed) = result else {
        if case .exists(let name) = result { taken = L10n.t("extraContent.files.renameTaken", ["name": name]) }
        return
      }
      if kind != .snippet {
        Announce.post(L10n.t("extraContent.files.renamedAnnounce", ["from": from, "to": renamed]))
        return
      }
      if await onSnippetRenamed(dir, from, renamed) { return }
      // The file has its new name and the boxes the old one: put the name back, so the site shows
      // what it showed. The page already says why the config could not be written.
      let back = try? await Task.detached { try Snippets().rename(project: project, kind: kind, dir: dir, from: renamed, to: from) }.value
      throw SnippetFailure.Said(text: back == .written(from)
        ? L10n.t("extraContent.files.renameReverted", ["from": from, "to": renamed])
        : L10n.t("extraContent.files.renameStuck", ["from": from, "to": renamed]))
    }
    return taken
  }

  private func trash(_ kind: Snippets.Kind, _ dir: String, _ file: String, _ users: [String]) async {
    await run {
      let text = users.isEmpty ? L10n.t("extraContent.files.trashConfirm", ["name": file])
        : L10n.t("extraContent.files.trashConfirmUsed", ["name": file, "names": users.joined(separator: ", ")])
      let (question, detail) = Confirm.split(text)
      guard await Confirm.ask(question, detail: detail, confirm: L10n.t("extraContent.files.trashLabel"), destructive: true,
                              window: unsaved?.window) else { return }
      let project = projectPath
      let place: String? = kind == .snippet ? dir : nil
      try await Task.detached { try Snippets().moveToTrash(project: project, kind: kind, dir: place, file: file) }.value
      Announce.post(L10n.t("extraContent.files.trashedAnnounce", ["name": file]))
    }
  }

  // MARK: The project picture

  /// The project picture and its dark twin, listed because a snippet uses them the same way, but
  /// read only: they belong to "Projektbild" in the configuration, and the favicon is built from
  /// icon.png.
  @ViewBuilder private var projectIconSection: some View {
    let files = [("icon.png", icon?.thumbnail), ("icon-dark.png", icon?.darkThumbnail)].compactMap { name, data in data.map { (name, $0) } }
    if !files.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Divider()
        Text(L10n.t("extraContent.files.projectIcon", ["dir": "quartz/static"])).font(.system(.callout, design: .monospaced).weight(.semibold))
          .foregroundStyle(.secondary)
        Note(L10n.t("extraContent.files.projectIconNote"))
        ForEach(files, id: \.0) { name, data in
          let users = iconUsers(name)
          HStack(spacing: 10) {
            if let image = NSImage(data: data) {
              Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 30, height: 30)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
              Text(name).font(.system(.callout, design: .monospaced))
              Text("{{root}}/static/\(name)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
              Text(users.isEmpty ? L10n.t("extraContent.files.unused")
                   : L10n.t("extraContent.files.usedBy", ["names": users.joined(separator: ", ")]))
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "lock").foregroundStyle(.secondary)
              .help(L10n.t("extraContent.files.projectIconLocked"))
              .accessibilityLabel(L10n.t("extraContent.files.projectIconLocked"))
          }
          .padding(.vertical, 4)
        }
      }
    }
  }
}

/// One folder's files: a heading with "Neue Datei" and "Datei/Bild hinzufügen", then a row per
/// file with what uses it, and edit (snippets), rename and trash.
private struct FileSection: View {
  let kind: Snippets.Kind
  let dir: String
  let heading: String
  /// Where "benutzt von" was looked for, when that is narrower than the file's reach.
  var note: String?
  let info: Snippets.Listing?
  let usersOf: (String) -> [String]
  let projectPath: String
  let onAdd: () -> Void
  /// Snippets only: an empty file under this name.
  let onNew: ((String) async -> Void)?
  let onRename: (String, String) async -> String?
  let onTrash: (String, [String]) -> Void
  let onSaved: (() -> Void)?

  @State private var newName: String?
  @State private var newExtension = ".md"
  @State private var editing: String?
  @State private var renaming: String?

  var body: some View {
    let writable = info?.state == .ok || info?.state == .missing
    let files = info?.files ?? []
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      HStack {
        Text(heading).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(.secondary)
          .lineLimit(2).truncationMode(.middle)
        Spacer()
        if writable {
          if onNew != nil {
            Button { newName = newName == nil ? "" : nil } label: {
              Label(L10n.t("extraContent.files.newSnippet"), systemImage: "doc.badge.plus")
            }
          }
          Button(action: onAdd) {
            Label(kind == .image ? L10n.t("extraContent.files.addImage") : L10n.t("extraContent.files.addSnippet"),
                  systemImage: kind == .image ? "photo.badge.plus" : "square.and.arrow.down")
          }
        }
      }
      if let note { Note(note).font(.caption) }
      if info?.state == .missing { Note(L10n.t("extraContent.files.dirMissing")) }
      if info?.state == .link { Note(L10n.t("extraContent.files.dirLink")) }
      if info?.state == .outside || info?.state == .reserved { Callout(.warning, L10n.t("extraContent.files.dirUnusable")) }
      if newName != nil, let onNew {
        NewSnippetRow(name: Binding(get: { newName ?? "" }, set: { newName = $0 }), fileExtension: $newExtension) {
          let base = (newName ?? "").trimmingCharacters(in: .whitespaces)
          guard !base.isEmpty else { return }
          let name = base.range(of: #"\.(md|html?)$"#, options: [.regularExpression, .caseInsensitive]) != nil ? base : base + newExtension
          Task {
            await onNew(name)
            newName = nil
          }
        }
      }
      if info?.state == .ok, files.isEmpty { Note(L10n.t("extraContent.files.empty")) }
      ForEach(files, id: \.self) { file in
        let users = usersOf(file)
        VStack(alignment: .leading, spacing: 6) {
          if renaming == file {
            RenameRow(file: file, onSubmit: { await onRename(file, $0) }, onDone: { renaming = nil })
          } else {
            HStack(spacing: 8) {
              VStack(alignment: .leading, spacing: 1) {
                Text(file).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Text(users.isEmpty ? L10n.t("extraContent.files.unused")
                     : L10n.t("extraContent.files.usedBy", ["names": users.joined(separator: ", ")]))
                  .font(.caption).foregroundStyle(.secondary).lineLimit(2)
              }
              Spacer()
              if writable, kind == .snippet {
                iconButton(L10n.t("extraContent.files.editNamed", ["name": file]), "pencil") { editing = editing == file ? nil : file }
              }
              if writable {
                iconButton(L10n.t("extraContent.files.renameNamed", ["name": file]), "character.cursor.ibeam") { renaming = file }
                iconButton(L10n.t("extraContent.files.trashNamed", ["name": file]), "trash") { onTrash(file, users) }
              }
            }
          }
          if editing == file, kind == .snippet {
            SnippetEditor(projectPath: projectPath, dir: dir, file: file, placeholdersOff: false, onSaved: onSaved) { editing = nil }
              .id("\(dir)/\(file)")
          }
        }
        .padding(.vertical, 3)
      }
    }
  }
}

/// The new name of a file, in place of its row.
private struct RenameRow: View {
  let file: String
  /// The sentence when the name is taken, nil when done.
  let onSubmit: (String) async -> String?
  let onDone: () -> Void

  @State private var value: String
  @State private var problem: String?
  @FocusState private var focused: Bool

  init(file: String, onSubmit: @escaping (String) async -> String?, onDone: @escaping () -> Void) {
    self.file = file
    self.onSubmit = onSubmit
    self.onDone = onDone
    _value = State(initialValue: file)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        TextField(L10n.t("extraContent.files.renameLabel", ["name": file]), text: $value)
          .textFieldStyle(.roundedBorder)
          .font(.system(.callout, design: .monospaced))
          .labelsHidden()
          .focused($focused)
          .onSubmit(submit)
          .onChange(of: value) { _, _ in problem = nil }
          .onExitCommand(perform: onDone)
        Button(L10n.t("extraContent.files.renameSubmit"), action: submit)
        Button(L10n.t("extraContent.files.cancel"), action: onDone)
      }
      if let problem { FieldProblem(problem) }
    }
    .onAppear { focused = true }
  }

  private func submit() {
    let to = value.trimmingCharacters(in: .whitespaces)
    guard !to.isEmpty, to != file else { return onDone() }
    Task {
      if let taken = await onSubmit(to) { problem = taken } else { onDone() }
    }
  }
}
