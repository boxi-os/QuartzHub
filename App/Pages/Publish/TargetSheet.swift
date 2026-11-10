import AppKit
import QuartzHubCore
import SwiftUI

/// The target form's state (`SavePublishTargetInput`). The destination stays the loose object it
/// is in the file, so a field a later version wrote survives an edit; only a change of type starts
/// it over. The exclusions are kept as typed and split on save: a binding that dropped empty lines
/// while typing swallowed Return.
struct TargetDraft: Equatable {
  var id: String?
  var name = ""
  var connectionId: String?
  var destination: JSONObject
  var excludesText = ""
  var withDocuments: [String] = []

  /// Each provider serves a different branch by convention; GitLab has none (a CI job publishes
  /// there), so it gets the same default as Codeberg and a hint.
  static let branchDefaults = ["github": "gh-pages", "gitlab": "pages", "codeberg": "pages"]

  /// Not "/": that is the login's own root, which the store refuses, so a fresh draft started on
  /// a value that could not be saved.
  static func empty() -> TargetDraft { TargetDraft(destination: emptyDestination("sftp")) }

  static func emptyDestination(_ type: String) -> JSONObject {
    switch type {
    case "sftp": JSONObject([("type", .string("sftp")), ("remotePath", .string("")), ("transfer", .string("sftp")), ("deleteRemoved", .bool(true))])
    case "ftp": JSONObject([("type", .string("ftp")), ("remotePath", .string("")), ("deleteRemoved", .bool(true))])
    case "folder": JSONObject([("type", .string("folder")), ("path", .string("")), ("deleteRemoved", .bool(true))])
    case "webhook": JSONObject([("type", .string("webhook"))])
    case "git-branch": JSONObject([("type", .string("git-branch")), ("branch", .string("gh-pages")), ("provider", .string("github"))])
    default: JSONObject([("type", .string("document")), ("path", .string("")), ("bookId", .string("")), ("formats", .array([.string("pdf")]))])
    }
  }

  /// The order the document target writes them in, whatever order they were ticked in.
  static let formatOrder = ["pdf", "epub", "html"]

  init(destination: JSONObject) { self.destination = destination }

  /// `draftOf`: with `withDocuments`, or saving an opened target switched its documents off.
  init(_ target: PublishTarget) {
    id = target.id
    name = target.name
    connectionId = target.connectionId
    destination = target.destination
    excludesText = target.excludes.joined(separator: "\n")
    withDocuments = target.withDocuments
  }

  var type: String { destination["type"]?.stringValue ?? "" }

  func text(_ key: String) -> String { destination[key]?.stringValue ?? "" }
  mutating func set(_ key: String, _ value: String) { destination[key] = .string(value) }
  var hasRemotePath: Bool { destination["remotePath"] != nil }
  var deleteRemoved: Bool? { destination["deleteRemoved"]?.boolValue }
  var formats: [String] { (destination["formats"]?.arrayValue ?? []).compactMap(\.stringValue) }

  var excludes: [String] {
    excludesText.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  var input: SavePublishTargetInput {
    SavePublishTargetInput(id: id, name: name, connectionId: connectionId, destination: destination, excludes: excludes,
                           withDocuments: withDocuments)
  }

  var remotePathProblem: RemotePath.Problem? {
    guard hasRemotePath else { return nil }
    return RemotePath.problem(text("remotePath"), deleteRemoved: deleteRemoved ?? false)
  }

  /// The rsync adapter refuses these at preview and upload; a target saved with one was useless.
  var rsyncChar: String? {
    guard type == "sftp", text("transfer") == "rsync" else { return nil }
    return RemotePath.rsyncUnsafeChar(text("remotePath"))
  }

  /// "Ready to save" is per destination, from `requiredKind`: a type that needs no credential is
  /// not held back for one.
  var ready: Bool {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, remotePathProblem == nil, rsyncChar == nil else { return false }
    switch type {
    case "folder": return !text("path").trimmingCharacters(in: .whitespaces).isEmpty
    case "document": return !text("path").trimmingCharacters(in: .whitespaces).isEmpty && !text("bookId").isEmpty && !formats.isEmpty
    case "git-branch": return !text("branch").trimmingCharacters(in: .whitespaces).isEmpty
    default: return connectionId != nil
    }
  }
}

/// QuartzControl's target form (`Publish/index.tsx`, `DocumentFields.tsx`) as a sheet with its own
/// "Speichern". A connection begun inside it is a second sheet over it, saved at once and then the
/// one this target uses.
struct TargetSheet: View {
  let model: PublishModel
  @State var draft: TargetDraft
  /// The draft as it was opened: only a changed one asks before "Abbrechen" lets it go.
  let opened: TargetDraft
  /// The page's selection is its own (scene storage): it hears which target was saved.
  let onSaved: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openSettings) private var openSettings
  @State private var failure: String?
  @State private var newConnection: Identified<ConnectionDraft>?
  @State private var copied = false

  init(model: PublishModel, draft: TargetDraft, onSaved: @escaping (String) -> Void) {
    self.model = model
    self.onSaved = onSaved
    _draft = State(initialValue: draft)
    opened = draft
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField(L10n.t("publish.targetForm.name"), text: $draft.name)
            .accessibilityIdentifier("target.name")
          Picker(L10n.t("publish.targetForm.type"), selection: Binding(get: { draft.type }, set: { type in
            // The connection goes with the type: an FTP account cannot serve an SFTP target, and
            // keeping it would fail only at the deploy.
            draft.connectionId = nil
            draft.destination = TargetDraft.emptyDestination(type)
          })) {
            ForEach(PublishWords.types, id: \.self) { type in Text(PublishWords.type(type)).tag(type) }
            if !PublishWords.types.contains(draft.type) { Text(PublishWords.type(draft.type)).tag(draft.type) }
          }
          .accessibilityIdentifier("target.type")
        } header: {
          Text(draft.id == nil ? L10n.t("publish.newTarget") : L10n.t("publish.targetForm.heading")).font(.headline)
        } footer: {
          Text(L10n.t("publish.targetForm.explainer")).font(.caption).foregroundStyle(.secondary)
        }
        destinationSection
        if let kind = PublishWords.requiredKind(draft.type) { connectionSection(kind) }
        optionsSection
        if let failure {
          Text(failure).foregroundStyle(.red).textSelection(.enabled)
        }
      }
      .formStyle(.grouped)
      HStack {
        Spacer()
        Button(L10n.t("common.cancel"), role: .cancel) { Task { await cancel() } }
          .keyboardShortcut(.cancelAction)
        Button(L10n.t("common.save"), action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(!draft.ready)
          .accessibilityIdentifier("target.save")
      }
      .padding(16)
    }
    .frame(width: 560, height: 640)
    // Escape closed the sheet by itself, past "Abbrechen" and its question, and a changed draft
    // was gone without a word (measured 2026-11-10). Held, Escape reaches the cancel button.
    .interactiveDismissDisabled(draft != opened)
    .sheet(item: $newConnection) { item in
      ConnectionSheet(title: L10n.t("settings.connections.newHeading", ["kind": ConnectionWords.kind(item.value.kind)]),
                      explainer: L10n.t("publish.connectionForm.explainer"), draft: item.value) { saved in
        model.reloadConnections()
        // Made from inside the form, so it is what this target uses.
        draft.connectionId = saved.id
        if draft.type == "sftp", blocked(saved) { draft.set("transfer", "sftp") }
      }
    }
  }

  // MARK: Where

  @ViewBuilder private var destinationSection: some View {
    Section {
      switch draft.type {
      case "sftp", "ftp":
        TextField(L10n.t("publish.targetForm.remotePath"), text: binding("remotePath"),
                  prompt: Text(L10n.t("publish.targetForm.remotePathPlaceholder")))
          .accessibilityIdentifier("target.remotePath")
        if let problem = draft.remotePathProblem {
          Text(PublishWords.remotePathError(problem)).font(.callout).foregroundStyle(.red)
        } else if let char = draft.rsyncChar {
          Text(char.contains(where: \.isWhitespace) ? L10n.t("publish.targetForm.rsyncPathSpace")
            : L10n.t("publish.targetForm.rsyncPathChar", ["char": char])).font(.callout).foregroundStyle(.red)
        } else {
          Note(L10n.t("publish.targetForm.remotePathHint"))
        }
        if draft.type == "sftp" { transferRows }
      case "folder":
        folderRow(L10n.t("publish.targetForm.folderPath"), identifier: "target.folder")
      case "git-branch":
        Picker(L10n.t("publish.targetForm.provider"), selection: Binding(get: { draft.text("provider") }, set: { provider in
          // The branch follows the provider only while it is still a provider's default.
          let branch = draft.text("branch")
          draft.set("provider", provider)
          if TargetDraft.branchDefaults.values.contains(branch) { draft.set("branch", TargetDraft.branchDefaults[provider] ?? branch) }
        })) {
          Text(verbatim: "GitHub Pages").tag("github")
          Text(verbatim: "Codeberg Pages").tag("codeberg")
          Text(verbatim: "GitLab Pages").tag("gitlab")
        }
        TextField(L10n.t("publish.targetForm.branch"), text: binding("branch"))
          .accessibilityIdentifier("target.branch")
        Note(PublishWords.branchHint(draft.text("provider")))
      case "document":
        documentRows
      default:
        EmptyView()
      }
    }
  }

  @ViewBuilder private var transferRows: some View {
    let blocker = rsyncBlocker
    Picker(L10n.t("publish.targetForm.transfer"), selection: binding("transfer")) {
      Text(L10n.t("publish.targetForm.transferSftp")).tag("sftp")
      Text(L10n.t("publish.targetForm.transferRsync")).tag("rsync")
    }
    .disabled(blocker.blocked)
    Note(blocker.blocked ? PublishWords.rsyncBlocked(blocker.reason)
      : draft.text("transfer") == "rsync" ? L10n.t("publish.rsyncHint") : L10n.t("publish.sftpHint"))
  }

  /// Asked of the picked connection with the adapter's own rule, so the form never offers a
  /// transfer the deploy would refuse. Without a connection, rsync stays closed.
  private var rsyncBlocker: (blocked: Bool, reason: RsyncSupport.BlockReason?) {
    guard let connection = draft.connectionId.flatMap({ id in model.connections.first { $0.id == id } }), connection.kind == .ssh else {
      return (true, nil)
    }
    let reason = RsyncSupport.blockReason(connection, rsyncAvailable: model.rsyncAvailable)
    return (reason != nil, reason)
  }

  private func blocked(_ connection: Connection) -> Bool {
    connection.kind != .ssh || RsyncSupport.blockReason(connection, rsyncAvailable: model.rsyncAvailable) != nil
  }

  private func folderRow(_ label: String, identifier: String) -> some View {
    LabeledContent(label) {
      HStack {
        TextField(label, text: binding("path")).labelsHidden().accessibilityIdentifier(identifier)
        Button(L10n.t("common.select")) {
          if let folder = ProjectsModel.pickFolder(start: draft.text("path").isEmpty ? nil : draft.text("path")) { draft.set("path", folder) }
        }
      }
    }
  }

  // MARK: A document

  @ViewBuilder private var documentRows: some View {
    folderRow(L10n.t("publish.targetForm.documentFolder"), identifier: "target.documentFolder")
    let bookId = draft.text("bookId")
    // A book the target names that is gone stays selected and says so.
    let gone = !bookId.isEmpty && !model.books.contains { $0.id == bookId }
    Picker(L10n.t("publish.targetForm.documentBook"), selection: binding("bookId")) {
      Text(L10n.t("publish.targetForm.documentPickBook")).tag("")
      if gone { Text(L10n.t("publish.targetForm.documentBookGoneOption", ["id": bookId])).tag(bookId) }
      ForEach(model.books, id: \.id) { book in Text(bookLabel(book)).tag(book.id) }
    }
    .accessibilityIdentifier("target.book")
    Note(gone ? L10n.t("publish.targetForm.documentBookGone", ["id": bookId])
      : model.books.isEmpty ? L10n.t("publish.targetForm.documentNoBooks") : L10n.t("publish.targetForm.documentBookHint"))
    LabeledContent(L10n.t("publish.targetForm.documentFormats")) {
      HStack(spacing: 16) {
        ForEach(TargetDraft.formatOrder, id: \.self) { format in
          Toggle(PublishWords.format(format), isOn: Binding(get: { draft.formats.contains(format) }, set: { on in
            let next = TargetDraft.formatOrder.filter { $0 == format ? on : draft.formats.contains($0) }
            draft.destination["formats"] = .array(next.map(JSONValue.string))
          }))
          .toggleStyle(.checkbox)
        }
      }
    }
  }

  /// Two books of one title are told apart by their file name.
  private func bookLabel(_ book: Book) -> String {
    if book.title.isEmpty { return book.id }
    return model.books.filter { $0.title == book.title }.count > 1 ? "\(book.title) (\(book.id))" : book.title
  }

  // MARK: The connection

  private func connectionSection(_ kind: StoredConnection.Kind) -> some View {
    Section {
      Picker(L10n.t("publish.targetForm.connection"), selection: Binding(get: { draft.connectionId ?? "" }, set: { id in
        draft.connectionId = id.isEmpty ? nil : id
        // A credential rsync cannot use falls back to SFTP, which every credential can do.
        if draft.type == "sftp", let picked = model.connections.first(where: { $0.id == id }), blocked(picked) { draft.set("transfer", "sftp") }
        if draft.type == "sftp", id.isEmpty { draft.set("transfer", "sftp") }
      })) {
        Text(L10n.t("publish.targetForm.pickConnection")).tag("")
        ForEach(model.connections.filter { $0.kind == kind }, id: \.id) { connection in
          Text(connection.kind == .webhook ? connection.name : "\(connection.name) (\(connection.username)@\(connection.host))").tag(connection.id)
        }
        // One this target names that is not in the list (deleted, or another machine's).
        if let id = draft.connectionId, !model.connections.contains(where: { $0.id == id && $0.kind == kind }) {
          Text(L10n.t("publish.targetForm.connectionGone")).tag(id)
        }
      }
      .accessibilityIdentifier("target.connection")
      HStack {
        Button(L10n.t("publish.newConnectionOfKind", ["kind": ConnectionWords.kind(kind)])) { newConnection = Identified(value: .empty(kind)) }
          .accessibilityIdentifier("target.newConnection")
        Button(L10n.t("publish.manageConnections")) { PublishModel.openConnectionSettings(openSettings) }
      }
      Note(L10n.t("publish.connectionKindFixed", ["kind": ConnectionWords.kind(kind)]))
    }
  }

  // MARK: What else

  @ViewBuilder private var optionsSection: some View {
    let documentTargets = model.targets.filter { $0.destination["type"] == .string("document") && $0.id != draft.id }
    let excludable = draft.type != "git-branch" && draft.type != "document"
    let offersDocuments = draft.type != "document" && draft.type != "webhook" && !documentTargets.isEmpty
    if excludable || offersDocuments || draft.deleteRemoved != nil {
      Section {
        if let deleteRemoved = draft.deleteRemoved {
          Toggle(L10n.t("publish.targetForm.deleteRemoved"), isOn: Binding(get: { deleteRemoved }, set: { draft.destination["deleteRemoved"] = .bool($0) }))
            .accessibilityIdentifier("target.deleteRemoved")
        }
        // The paths this target never publishes, kept between runs; not for a branch, where
        // leaving a file out deletes it from the live site.
        if excludable {
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("publish.targetForm.excludes"))
            TextEditor(text: $draft.excludesText)
              .font(.body.monospaced())
              .frame(minHeight: 64)
              .scrollContentBackground(.hidden)
              .padding(4)
              .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
              .overlay(alignment: .topLeading) {
                if draft.excludesText.isEmpty {
                  Text(L10n.t("publish.targetForm.excludesPlaceholder")).font(.body.monospaced()).foregroundStyle(.tertiary)
                    .padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false)
                }
              }
              .accessibilityLabel(L10n.t("publish.targetForm.excludes"))
              .accessibilityIdentifier("target.excludes")
          }
        }
        if offersDocuments { withDocumentsRows(documentTargets) }
      }
    }
  }

  /// `WithDocumentsFields`: which document targets go up with the site under downloads/, and the
  /// link to put on a page, as a full address from baseUrl (a site under a sub-path breaks one
  /// that starts with /downloads/).
  @ViewBuilder private func withDocumentsRows(_ targets: [PublishTarget]) -> some View {
    let host = Self.host(model.baseUrl)
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.t("publish.targetForm.withDocuments"))
      Note(L10n.t("publish.targetForm.withDocumentsHint"))
      ForEach(targets, id: \.id) { target in
        let on = draft.withDocuments.contains(target.id)
        Toggle(target.name, isOn: Binding(get: { on }, set: { next in
          draft.withDocuments = next ? draft.withDocuments + [target.id] : draft.withDocuments.filter { $0 != target.id }
        }))
        .toggleStyle(.checkbox)
        if on {
          let book = target.destination["bookId"]?.stringValue ?? ""
          ForEach((target.destination["formats"]?.arrayValue ?? []).compactMap(\.stringValue), id: \.self) { format in
            let file = "\(book).\(format)"
            let markdown = host.isEmpty ? "downloads/\(file)" : "[\(PublishWords.downloadLink(format))](https://\(host)/downloads/\(file))"
            HStack {
              Text(verbatim: markdown).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
              if !host.isEmpty {
                Button(L10n.t("publish.targetForm.copyLink")) {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(markdown, forType: .string)
                  copied = true
                  Announce.post(L10n.t("publish.targetForm.linkCopied"))
                }
                .controlSize(.small)
                // Three of them in a row, each "Kopieren" alone (measured 2026-11-10).
                .accessibilityLabel("\(L10n.t("publish.targetForm.copyLink")): \(PublishWords.downloadLink(format))")
              }
            }
            .padding(.leading, 20)
          }
        }
      }
      if host.isEmpty { Note(L10n.t("publish.targetForm.withDocumentsNoBaseUrl")) }
      if copied { Note(L10n.t("publish.targetForm.linkCopied")) }
    }
  }

  static func host(_ baseUrl: String?) -> String {
    var host = baseUrl ?? ""
    for scheme in ["https://", "http://"] where host.hasPrefix(scheme) { host.removeFirst(scheme.count) }
    while host.hasSuffix("/") { host.removeLast() }
    return host
  }

  // MARK: Saving

  private func binding(_ key: String) -> Binding<String> {
    Binding(get: { draft.text(key) }, set: { draft.set(key, $0) })
  }

  private func save() {
    do {
      let saved = try PublishTargets(project: model.project.path).save(draft.input)
      model.saved(saved.id)
      onSaved(saved.id)
      dismiss()
    } catch {
      failure = error.message
    }
  }

  /// A changed draft is gone for good once closed, so that asks; an untouched one closes silently.
  private func cancel() async {
    if draft != opened {
      let window = NSApp.keyWindow
      guard await Confirm.ask(L10n.t("publish.confirmDiscardTargetDraft"), confirm: L10n.t("publish.confirmDiscardTargetDraftAction"),
                              window: window) else { return }
    }
    dismiss()
  }
}

/// A value for `sheet(item:)` that is not Identifiable itself.
struct Identified<Value>: Identifiable {
  let id = UUID()
  let value: Value
}
