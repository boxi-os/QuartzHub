import AppKit
import QuartzHubCore
import SwiftUI

// QuartzControl's `ConnectionForm.tsx`: one form for a connection, reached from two places, the
// settings (where connections are managed) and Veröffentlichen (where one is created in the
// middle of setting up a target). Two copies would be two places for a new way to log in.

/// The form's state. Every field is text as typed; `input` makes the saved shape of it.
struct ConnectionDraft: Equatable {
  var id: String?
  var kind: StoredConnection.Kind
  var name = ""
  var host = ""
  var port = ""
  var username = ""
  var authMethod: StoredConnection.AuthMethod = .password
  var keyPath = ""
  var secure = true
  var login: String?
  /// Never filled from the store: the secret does not come back out, and an empty field on an
  /// edit leaves the stored one alone.
  var secret = ""

  static func empty(_ kind: StoredConnection.Kind) -> ConnectionDraft {
    switch kind {
    case .ssh: ConnectionDraft(kind: .ssh, port: "22")
    case .ftp: ConnectionDraft(kind: .ftp, port: "21", secure: true)
    case .github: ConnectionDraft(kind: .github, name: "GitHub")
    case .webhook: ConnectionDraft(kind: .webhook)
    }
  }

  /// `draftFromConnection`.
  init(_ connection: Connection) {
    id = connection.id
    kind = connection.kind ?? .webhook
    name = connection.name
    switch kind {
    case .ssh:
      host = connection.host
      port = String(connection.port)
      username = connection.username
      authMethod = connection.authMethod
      keyPath = connection.keyPath ?? ""
    case .ftp:
      host = connection.host
      port = String(connection.port)
      username = connection.username
      secure = connection.secure
    case .github:
      login = connection.login
    case .webhook:
      break
    }
  }

  init(id: String? = nil, kind: StoredConnection.Kind, name: String = "", port: String = "", secure: Bool = true) {
    self.id = id
    self.kind = kind
    self.name = name
    self.port = port
    self.secure = secure
  }

  var hasServer: Bool { kind == .ssh || kind == .ftp }

  /// `connectionDraftIncomplete`: the Save button's guard, so a missing field is said at the field
  /// and not by the store's check.
  var incomplete: Bool {
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
    if hasServer {
      if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
      guard let port = Int(port), (1...65535).contains(port) else { return true }
    }
    // An edit may leave the URL empty: that keeps the stored one. A new webhook has none to keep.
    if kind == .webhook && id == nil && secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
    return false
  }

  /// What is saved, with `normalizeConnectionDraft`'s one change: a key file typed as "~/…" is
  /// made absolute, which the store requires.
  var input: SaveConnectionInput {
    var input = SaveConnectionInput(id: id, kind: kind, name: name, secret: secret)
    switch kind {
    case .ssh:
      input.host = host
      input.port = Int(port)
      input.username = username
      input.authMethod = authMethod
      input.keyPath = keyPath.isEmpty ? nil : Self.expandHome(keyPath)
    case .ftp:
      input.host = host
      input.port = Int(port)
      input.username = username
      input.secure = secure
    case .github:
      input.login = login
    case .webhook:
      break
    }
    return input
  }

  static func expandHome(_ path: String, home: String = NSHomeDirectory()) -> String {
    if path == "~" { return home }
    if path.hasPrefix("~/") { return NodePath.join(home, String(path.dropFirst(2))) }
    return path
  }
}

/// The words around a connection that both lists say alike.
enum ConnectionWords {
  /// `CONNECTION_KIND_LABEL`: names, the same in both languages.
  static func kind(_ kind: StoredConnection.Kind?) -> String {
    switch kind {
    case .ssh: "SFTP / SSH"
    case .ftp: "FTP"
    case .github: "GitHub"
    case .webhook, nil: "Webhook"
    }
  }

  /// `connectionSummary`.
  static func summary(_ connection: Connection) -> String {
    switch connection.kind {
    case .ssh, .ftp: "\(connection.username)@\(connection.host):\(connection.port)"
    case .github: connection.login.map { "@\($0)" } ?? ""
    case .webhook, nil: connection.displayOrigin ?? ""
    }
  }

  /// `connectionMissingCredential`: a key given as a file or the agent stores no secret, and needs none.
  static func missingCredential(_ connection: Connection) -> Bool {
    guard connection.kind == .ssh else { return !connection.hasSecret }
    if connection.authMethod == .agent { return false }
    if connection.authMethod == .privateKey, !(connection.keyPath ?? "").isEmpty { return false }
    return !connection.hasSecret
  }

  static func hostKey(_ connection: Connection) -> String {
    connection.hostKey.map { "\(L10n.t("publish.hostKeyPinned")): \($0.fingerprint)" } ?? L10n.t("publish.hostKeyUnknown")
  }
}

/// `ConnectionFormFields`, as rows of a grouped form.
struct ConnectionFields: View {
  @Binding var draft: ConnectionDraft

  var body: some View {
    TextField(L10n.t("publish.connectionForm.name"), text: $draft.name)
      .accessibilityIdentifier("connection.name")
    if draft.hasServer {
      TextField(L10n.t("publish.connectionForm.host"), text: $draft.host)
        .accessibilityIdentifier("connection.host")
      TextField(L10n.t("publish.connectionForm.port"), text: $draft.port)
        .accessibilityIdentifier("connection.port")
      TextField(L10n.t("publish.connectionForm.username"), text: $draft.username)
        .accessibilityIdentifier("connection.username")
    }
    if draft.kind == .ssh {
      Picker(L10n.t("publish.connectionForm.authMethod"), selection: Binding(get: { draft.authMethod }, set: { method in
        // What was typed belongs to the method it was typed for.
        draft.authMethod = method
        draft.secret = ""
      })) {
        Text(L10n.t("publish.connectionForm.authPassword")).tag(StoredConnection.AuthMethod.password)
        Text(L10n.t("publish.connectionForm.authPrivateKey")).tag(StoredConnection.AuthMethod.privateKey)
        Text(L10n.t("publish.connectionForm.authAgent")).tag(StoredConnection.AuthMethod.agent)
      }
      .accessibilityIdentifier("connection.authMethod")
    }
    if draft.kind == .ftp {
      Toggle(L10n.t("publish.connectionForm.secure"), isOn: $draft.secure)
        .accessibilityIdentifier("connection.secure")
    }
    if draft.kind == .ssh && draft.authMethod == .privateKey {
      LabeledContent(L10n.t("publish.connectionForm.keyPath")) {
        HStack {
          TextField(L10n.t("publish.connectionForm.keyPath"), text: $draft.keyPath, prompt: Text(verbatim: "~/.ssh/id_ed25519"))
            .labelsHidden()
            .accessibilityIdentifier("connection.keyPath")
          Button(L10n.t("common.select")) {
            if let file = Self.pickKeyFile() { draft.keyPath = file }
          }
        }
      }
    }
    if draft.kind == .ssh && draft.authMethod == .agent {
      Note(L10n.t("publish.connectionForm.agentHint"))
    } else if draft.kind == .webhook {
      // Not a password field: a build hook has to be readable while pasting it, since a mistyped
      // one fails with a 404 that names nothing. It is still a secret (its path is the token), so
      // an edit opens on an empty field that keeps the stored one.
      TextField(L10n.t("publish.connectionForm.webhookUrl"), text: $draft.secret,
                prompt: Text(draft.id != nil ? L10n.t("publish.connectionForm.secretUnchangedPlaceholder") : "https://api.netlify.com/build_hooks/…"))
        .accessibilityIdentifier("connection.secret")
    } else {
      SecureField(secretLabel, text: $draft.secret,
                  prompt: Text(draft.id != nil ? L10n.t("publish.connectionForm.secretUnchangedPlaceholder") : draft.kind == .github ? "ghp_…" : ""))
        .accessibilityIdentifier("connection.secret")
    }
    if draft.kind == .ftp && !draft.secure {
      Label(L10n.t("publish.ftpPlaintextWarning"), systemImage: "exclamationmark.triangle")
        .font(.callout).foregroundStyle(.orange)
    }
  }

  private var secretLabel: String {
    if draft.kind == .github { return L10n.t("settings.github.token") }
    if draft.kind == .ssh && draft.authMethod == .privateKey { return L10n.t("publish.connectionForm.privateKey") }
    return L10n.t("publish.connectionForm.password")
  }

  /// Keys live in a hidden folder, so the panel shows hidden files and starts there.
  @MainActor static func pickKeyFile() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true
    let ssh = NodePath.join(NSHomeDirectory(), ".ssh")
    if FileManager.default.fileExists(atPath: ssh) { panel.directoryURL = URL(fileURLWithPath: ssh, isDirectory: true) } // path boundary
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return Posix.path(url)
  }
}

/// A connection in a sheet: new, or one to edit. Saving writes it at once (the Keychain first),
/// then the sheet closes and the caller hears which connection it was.
struct ConnectionSheet: View {
  let title: String
  /// The stored connection when editing: its host key and how many projects use it.
  var existing: Connection?
  var usage = 0
  var explainer: String?
  @State var draft: ConnectionDraft
  let onSaved: (Connection) -> Void
  var onForgetHostKey: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var failure: String?

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          ConnectionFields(draft: $draft)
        } header: {
          Text(title).font(.headline)
        } footer: {
          if let explainer { Text(explainer).font(.caption).foregroundStyle(.secondary) }
        }
        if let existing, existing.kind == .ssh || usage > 0 {
          Section {
            if usage > 0 {
              Text(L10n.t("settings.connections.usedBy", ["count": String(usage)], count: usage)).foregroundStyle(.secondary)
            }
            if existing.kind == .ssh {
              Text(ConnectionWords.hostKey(existing)).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
              if existing.hostKey != nil, let onForgetHostKey {
                Button(L10n.t("publish.forgetHostKey"), action: onForgetHostKey)
              }
            }
          }
        }
        if let failure {
          Text(failure).foregroundStyle(.red).textSelection(.enabled)
        }
      }
      .formStyle(.grouped)
      HStack {
        Spacer()
        Button(L10n.t("common.cancel"), role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(L10n.t("common.save"), action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(draft.incomplete)
          .accessibilityIdentifier("connection.save")
      }
      .padding(16)
    }
    .frame(width: 480)
    .frame(minHeight: 360)
  }

  private func save() {
    do {
      let saved = try AppDeploy.connections().save(draft.input)
      AppDeploy.ConnectionsVersion.shared.bump()
      onSaved(saved)
      dismiss()
    } catch {
      failure = error.message
    }
  }
}
