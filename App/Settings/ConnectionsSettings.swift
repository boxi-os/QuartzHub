import QuartzHubCore
import SwiftUI

/// The tab „Zugänge“: QuartzControl's two sections for what publishing logs in with, app-wide.
/// The GitHub token on top (a token with an account check is a different thing to look at than a
/// server login), the server logins and build hooks under it. A connection is edited in a sheet,
/// which saves at once; the list in the window only shows and removes.
struct ConnectionsSettings: View {
  @State private var model = ConnectionsSettingsModel()
  @State private var token = ""
  /// The sheet: a connection to edit, or a new one of a kind.
  @State private var editing: Editing?

  struct Editing: Identifiable {
    var id: String
    var draft: ConnectionDraft
    var existing: Connection?
  }

  var body: some View {
    Form {
      githubSection
      connectionsSection
    }
    .formStyle(.grouped)
    .task { await model.reload() }
    .sheet(item: $editing) { editing in
      ConnectionSheet(title: editing.existing?.name ?? L10n.t("settings.connections.newHeading", ["kind": ConnectionWords.kind(editing.draft.kind)]),
                      existing: editing.existing, usage: editing.existing.map { model.usage[$0.id] ?? 0 } ?? 0,
                      draft: editing.draft,
                      onSaved: { _ in Task { await model.reload() } },
                      onForgetHostKey: editing.existing.map { connection in { forgetHostKey(connection) } })
    }
  }

  // MARK: GitHub

  private var githubSection: some View {
    Section {
      if let github = model.github, github.hasSecret {
        LabeledContent(L10n.t("settings.github.token")) {
          githubStatus
        }
        if let hint = statusHint {
          Note(hint)
        }
        HStack {
          Button(L10n.t("settings.github.recheck")) { Task { await model.checkGithub() } }
            .disabled(model.githubStatus == .checking)
          Button(L10n.t("settings.github.remove")) { model.removeGithub() }
        }
      }
      LabeledContent(model.github?.hasSecret == true ? L10n.t("settings.github.replaceToken") : L10n.t("settings.github.token")) {
        HStack {
          SecureField(L10n.t("settings.github.token"), text: $token,
                      prompt: Text(model.github?.hasSecret == true ? L10n.t("settings.githubTokenStored") : "ghp_…"))
            .labelsHidden()
            .accessibilityIdentifier("settings.githubToken")
          Button(model.savingGithub ? L10n.t("common.saving") : L10n.t("settings.github.saveAndCheck")) {
            Task {
              if await model.saveGithub(token) { token = "" }
            }
          }
          .disabled(model.savingGithub || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      if let failure = model.githubFailure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
      }
    } header: {
      Text(L10n.t("settings.github.title"))
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("settings.github.description"))
        Text(L10n.t("settings.github.scopeHint"))
      }
      .font(.caption).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var githubStatus: some View {
    switch model.githubStatus {
    case .valid(let account):
      HStack(spacing: 8) {
        StateBadge(text: L10n.t("settings.github.valid"), color: .green)
        Text(account.name.map { "\($0) (@\(account.login))" } ?? "@\(account.login)").foregroundStyle(.secondary)
      }
    case .rejected: StateBadge(text: L10n.t("settings.github.rejected"), color: .red)
    case .unknown: StateBadge(text: L10n.t("settings.github.unknown"), color: .orange)
    case .checking, .none: StateBadge(text: L10n.t("settings.github.checking"), color: .gray)
    }
  }

  private var statusHint: String? {
    switch model.githubStatus {
    case .rejected: L10n.t("settings.github.rejectedHint")
    case .unknown: L10n.t("settings.github.unknownHint")
    default: nil
    }
  }

  // MARK: Server logins and build hooks

  private var connectionsSection: some View {
    Section {
      if model.listed.isEmpty {
        Text(L10n.t("settings.connections.empty")).foregroundStyle(.secondary)
      }
      ForEach(model.listed, id: \.id) { connection in
        row(connection)
      }
      HStack {
        Text(L10n.t("settings.connections.add"))
        Spacer()
        Button(L10n.t("settings.connections.addSsh")) { add(.ssh) }
          .accessibilityIdentifier("settings.connections.addSsh")
        Button(L10n.t("settings.connections.addFtp")) { add(.ftp) }
        Button(L10n.t("settings.connections.addWebhook")) { add(.webhook) }
      }
      if let failure = model.failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
      }
    } header: {
      Text(L10n.t("settings.connections.title"))
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("settings.connections.description"))
        Text(L10n.t("settings.connections.targetHint"))
      }
      .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func row(_ connection: Connection) -> some View {
    let usage = model.usage[connection.id] ?? 0
    return HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(connection.name)
        Text(([ConnectionWords.summary(connection)] + (usage > 0 ? [L10n.t("settings.connections.usedBy", ["count": String(usage)], count: usage)] : []))
          .filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.caption).foregroundStyle(.secondary)
        // In words, not only as a colour: what is missing, or open.
        if ConnectionWords.missingCredential(connection) {
          Text(L10n.t("settings.connections.noSecret")).font(.caption).foregroundStyle(.orange)
        }
        if connection.kind == .ftp && !connection.secure {
          Text(L10n.t("settings.connections.plaintext")).font(.caption).foregroundStyle(.orange)
        }
      }
      Spacer()
      Text(ConnectionWords.kind(connection.kind)).font(.caption).foregroundStyle(.secondary)
      Button(L10n.t("common.edit")) { editing = Editing(id: connection.id, draft: ConnectionDraft(connection), existing: connection) }
        .accessibilityLabel(L10n.t("common.editNamed", ["name": connection.name]))
      Button {
        Task { await model.delete(connection) }
      } label: {
        Label(L10n.t("common.deleteNamed", ["name": connection.name]), systemImage: "trash")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .help(L10n.t("common.deleteNamed", ["name": connection.name]))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.connection.\(connection.name)")
  }

  private func add(_ kind: StoredConnection.Kind) {
    editing = Editing(id: "new:\(kind.rawValue)", draft: .empty(kind), existing: nil)
  }

  private func forgetHostKey(_ connection: Connection) {
    Task {
      if await model.forgetHostKey(connection) { editing = nil }
    }
  }
}

@MainActor @Observable
final class ConnectionsSettingsModel {
  enum GithubStatus: Equatable {
    case none, checking, valid(GitHubAPI.Account), rejected, unknown
  }

  private(set) var connections: [Connection] = []
  /// How many projects' targets use each connection, across every project in the list: a
  /// connection is app-wide, its targets are not.
  private(set) var usage: [String: Int] = [:]
  private(set) var githubStatus: GithubStatus = .none
  var savingGithub = false
  var githubFailure: String?
  var failure: String?

  private var store: Connections { AppDeploy.connections() }

  var github: Connection? { connections.first { $0.kind == .github } }
  var listed: [Connection] { connections.filter { $0.kind != .github } }

  func reload() async {
    connections = store.list()
    let projects = ProjectStore(profile: AppProfile.own).list().map(\.path)
    let ids = connections.map(\.id)
    usage = await Task.detached {
      var counts: [String: Int] = [:]
      for project in projects {
        for target in PublishTargets(project: project).list() {
          if let id = target.connectionId, ids.contains(id) { counts[id, default: 0] += 1 }
        }
      }
      return counts
    }.value
    await checkGithub()
  }

  /// Four answers, not two: "abgelehnt" is GitHub's own answer about the token, an unreachable
  /// API is no answer at all.
  func checkGithub() async {
    guard let github, github.hasSecret else {
      githubStatus = .none
      return
    }
    githubStatus = .checking
    let api = GitHubAPI(environment: await AppServices.current(), token: store.gitToken)
    do {
      githubStatus = try await api.viewer().map(GithubStatus.valid) ?? .rejected
    } catch {
      githubStatus = .unknown
    }
  }

  func saveGithub(_ token: String) async -> Bool {
    savingGithub = true
    defer { savingGithub = false }
    do {
      try store.save(SaveConnectionInput(id: github?.id, kind: .github, name: "GitHub", secret: token))
      githubFailure = nil
    } catch {
      githubFailure = error.message
      return false
    }
    await reload()
    return true
  }

  func removeGithub() {
    guard let github else { return }
    do {
      try store.delete(github.id)
      githubFailure = nil
    } catch {
      githubFailure = error.message
    }
    Task { await reload() }
  }

  /// Asked either way: even an unused connection holds a password or key that exists only here.
  func delete(_ connection: Connection) async {
    let used = usage[connection.id] ?? 0
    let text = used > 0 ? L10n.t("settings.connections.confirmDeleteInUse", ["count": String(used)], count: used)
      : L10n.t("settings.connections.confirmDelete")
    let (question, detail) = Confirm.split(text)
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("settings.connections.confirmDeleteAction"), destructive: true,
                            window: NSApp.keyWindow) else { return }
    do {
      try store.delete(connection.id)
      failure = nil
    } catch {
      failure = error.message
    }
    await reload()
  }

  /// A separate, confirmed action, not an answer in the mismatch dialog. The pin belongs to the
  /// host, so forgetting it here affects every project that reaches that server.
  func forgetHostKey(_ connection: Connection) async -> Bool {
    let (question, detail) = Confirm.split(L10n.t("publish.confirmForgetHostKey", ["host": connection.host]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("publish.confirmForgetHostKeyAction"), destructive: true,
                            window: NSApp.keyWindow) else { return false }
    do {
      try store.forgetHostKey(connection.id)
      failure = nil
    } catch {
      failure = error.message
    }
    await reload()
    return true
  }
}
