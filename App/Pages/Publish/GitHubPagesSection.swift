import AppKit
import QuartzHubCore
import SwiftUI

/// QuartzControl's `GithubPages.tsx`, the other half of a branch deploy: which branch Pages reads,
/// under which domain, and whether HTTPS is enforced live in the repository's settings, so without
/// this the first deploy succeeds and the site stays 404. GitHub keeps the domain as a CNAME file on
/// the branch, which the branch deploy carries over (`GitBranchAdapter.keepPagesDomain`).
struct GitHubPagesSection: View {
  let project: String
  let branch: String

  @State private var info: GitHubAPI.PagesInfo?
  /// "Not asked yet" apart from "asked, and the origin is not on github.com".
  @State private var loaded = false
  @State private var loading = false
  @State private var loadError: String?
  @State private var cname = ""
  @State private var httpsEnforced = true
  @State private var applying = false
  @State private var applyError: String?
  @State private var output: String?

  var body: some View {
    Section {
      if let loadError { Callout(.error, loadError) }
      if loaded && info == nil { Note(L10n.t("publish.pages.noGithubOrigin")) }
      if let error = info?.error { Callout(.error, error) }
      if let info, !info.configured, info.error == nil { Note(L10n.t("publish.pages.notConfigured")) }
      if let info, info.configured { state(info) }
      if info != nil { settings }
      if let applyError { Callout(.error, applyError) }
      if let output { RunOutput(text: output, label: L10n.t("publish.pages.title"), identifier: "publish.pages.output") }
    } header: {
      HStack {
        Label(L10n.t("publish.pages.title"), systemImage: "globe")
        Spacer()
        Button(loading ? L10n.t("common.loading") : L10n.t("publish.pages.reload")) { Task { await load() } }
          .disabled(loading)
          .controlSize(.small)
      }
    }
    // The token is a connection: saved or removed in the settings window, the card asks again.
    .task(id: "\(project)|\(branch)|\(AppDeploy.ConnectionsVersion.shared.value)") { await load() }
  }

  private func state(_ info: GitHubAPI.PagesInfo) -> some View {
    HStack(spacing: 10) {
      let status = info.status?.stringValue
      StateBadge(text: PublishWords.pagesStatus(status), color: status == "built" ? .green : status == "errored" ? .red : .orange)
      // The one moment the user wants to look at the result.
      if let address = info.htmlUrl?.stringValue, let url = URL(string: address) { // not a file path
        Link(address, destination: url).font(.callout.monospaced())
      }
      Spacer()
      // A target that pushes to gh-pages while Pages reads main publishes nothing, and nothing
      // else would show the mismatch.
      if let source = info.sourceBranch?.stringValue {
        Text(L10n.t("publish.pages.source", ["branch": source])).font(.callout)
          .foregroundStyle(source == branch ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
      }
    }
  }

  @ViewBuilder private var settings: some View {
    // A List row shows no TextField label of its own.
    LabeledContent(L10n.t("publish.pages.cname")) {
      TextField(L10n.t("publish.pages.cname"), text: $cname, prompt: Text(L10n.t("publish.pages.cnamePlaceholder")))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 320)
        .accessibilityIdentifier("publish.pages.cname")
    }
    // Only a custom domain has a choice: github.io is always HTTPS, and GitHub reports it so. It
    // follows the field, not the stored value, because that domain is the one this saves.
    let domain = !cname.trimmingCharacters(in: .whitespaces).isEmpty
    Toggle(L10n.t("publish.pages.httpsEnforced"), isOn: $httpsEnforced)
      .disabled(!domain)
    if !domain { Note(L10n.t("publish.pages.httpsOnlyWithDomain")) }
    HStack {
      // Two actions behind one button: before Pages reads this branch it points it here, after
      // that it only saves the domain and HTTPS.
      Button(applying ? L10n.t("publish.github.applying")
        : info?.configured == true && info?.sourceBranch?.stringValue == branch ? L10n.t("publish.pages.saveSettings")
        : L10n.t("publish.pages.apply", ["branch": branch])) { Task { await apply() } }
        .disabled(applying)
      Spacer()
    }
    Note(L10n.t("publish.pages.cnameHint"))
  }

  private func api() async -> GitHubAPI {
    GitHubAPI(environment: await AppServices.current(), token: AppDeploy.connections().gitToken)
  }

  private func load() async {
    loading = true
    defer { loading = false }
    do {
      let next = try await api().pagesInfo(project)
      info = next
      loaded = true
      loadError = nil
      // From what GitHub reports, so the fields are the live state and not a blank form that
      // would clear the domain on the next save.
      cname = next?.cname?.stringValue ?? ""
      httpsEnforced = next?.httpsEnforced?.boolValue ?? true
    } catch {
      loadError = PublishFailure.message(of: error)
    }
  }

  private func apply() async {
    applying = true
    defer { applying = false }
    let domain = cname.trimmingCharacters(in: .whitespaces)
    do {
      let applied = try await api().configurePages(project, branch: branch, cname: .some(domain.isEmpty ? nil : domain), httpsEnforced: httpsEnforced)
      // A refusal from the Pages API is an error, not output beside a success (review
      // 2026-11-13, nebenbei).
      if applied.success {
        output = applied.output
        applyError = nil
      } else {
        output = nil
        applyError = applied.output
      }
    } catch {
      applyError = PublishFailure.message(of: error)
    }
    await load()
  }
}
