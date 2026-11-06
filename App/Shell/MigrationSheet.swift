import QuartzHubCore
import SwiftUI

/// Where the profiles are. Launch arguments move them for tests and measurements, so a run never
/// has to touch the real profiles: `-QHProfileDir <dir>` for QuartzHub's own,
/// `-QHMigrationSource <dir>` for QuartzControl's (an empty value turns the takeover off; the UI
/// smoke test does that).
enum AppProfile {
  static var own: ProfileDirectory {
    UserDefaults.standard.string(forKey: "QHProfileDir").map { ProfileDirectory(Posix.onDisk($0)) } ?? .quartzHub
  }

  static var quartzControl: ProfileDirectory? {
    guard let value = UserDefaults.standard.string(forKey: "QHMigrationSource") else { return .quartzControl }
    return value.isEmpty ? nil : ProfileDirectory(Posix.onDisk(value))
  }
}

/// The takeover on first start (docs/decisions/phase-2-formate.md, „Übernahme“): what will be
/// taken over, then one button. Reading QuartzControl's Keychain item happens only after that
/// button, and only when there are secrets; the system asks the user then.
struct MigrationSheet: View {
  let source: ProfileDirectory
  let plan: ProfileMigration.Plan
  let onFinish: () -> Void

  private enum Phase: Equatable {
    case asking
    case running
    case done(ProfileMigration.Report)
    case failed(String)

    var isDone: Bool {
      if case .done = self { return true }
      return false
    }
  }

  @State private var phase = Phase.asking

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(phase.isDone ? L10n.t("migration.doneTitle") : L10n.t("migration.title"))
        .font(.title2.bold())
      switch phase {
      case .asking, .running: overview
      case .done(let report): result(report)
      case .failed(let file):
        Text(L10n.t("migration.failed", ["file": file]))
          .foregroundStyle(.red)
      }
      buttons
    }
    .padding(24)
    .frame(width: 480)
    // A container of its own: an identifier on a plain stack goes to every child and hides
    // theirs (measured: "migration.confirm" was not found, every element answered "migration").
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("migration")
  }

  private var overview: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.t("migration.intro"))
        .fixedSize(horizontal: false, vertical: true)
      Form {
        if !plan.projects.isEmpty {
          LabeledContent {
            if !plan.missingProjectPaths.isEmpty {
              Text(L10n.t("migration.projectsMissing", count: plan.missingProjectPaths.count))
                .foregroundStyle(.secondary)
            }
          } label: {
            Label(L10n.t("migration.projects", count: plan.projects.count), systemImage: "folder")
          }
          .accessibilityIdentifier("migration.projects")
        }
        if plan.settings != nil {
          Label(L10n.t("migration.settings"), systemImage: "gearshape")
        }
        if !plan.connections.isEmpty {
          Label(L10n.t("migration.connections", count: plan.connections.count), systemImage: "network")
        }
        if plan.secretCount > 0 {
          VStack(alignment: .leading, spacing: 2) {
            Label(L10n.t("migration.secrets", count: plan.secretCount), systemImage: "key")
            Text(L10n.t("migration.secretsHint"))
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      .fixedSize(horizontal: false, vertical: true)
      notes
    }
  }

  @ViewBuilder private var notes: some View {
    if !plan.unreadable.isEmpty {
      Text(L10n.t("migration.unreadable", ["names": plan.unreadable.joined(separator: ", ")]))
        .font(.callout)
    }
    if !plan.legacy.isEmpty {
      Text(L10n.t("migration.legacy", ["names": plan.legacy.joined(separator: ", ")]))
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private func result(_ report: ProfileMigration.Report) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(L10n.t("migration.projects", count: report.projects), systemImage: "folder")
      if report.connections > 0 {
        Label(L10n.t("migration.connections", count: report.connections), systemImage: "network")
      }
      if report.secretsMoved > 0 {
        Text(L10n.t("migration.secretsMoved", count: report.secretsMoved))
      }
      if !report.secretsLost.isEmpty {
        Text(L10n.t("migration.secretsLost", count: report.secretsLost.count))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("migration.report")
  }

  private var buttons: some View {
    HStack {
      Spacer()
      switch phase {
      case .asking:
        Button(L10n.t("migration.later"), role: .cancel, action: onFinish)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("migration.later")
        Button(L10n.t("migration.confirm"), action: start)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("migration.confirm")
      case .running:
        ProgressView()
          .controlSize(.small)
        Text(L10n.t("migration.running"))
      case .done, .failed:
        Button(L10n.t("migration.done"), action: onFinish)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("migration.done")
      }
    }
  }

  private func start() {
    phase = .running
    let plan = plan
    let target = AppProfile.own
    let needsKey = plan.secretCount > 0
    Task.detached {
      // The Keychain prompt is the system's; a "deny" means: take everything but the secrets.
      let key = needsKey ? try? ProfileMigration.quartzControlKey() : nil
      let outcome: Phase
      do {
        let report = try ProfileMigration.run(plan, target: target, secretKey: key) { account, label, secret in
          try Keychain.write(secret, account: account, label: label)
        }
        outcome = .done(report)
      } catch let error as ProfileMigration.Failure {
        switch error {
        case .alreadyTakenOver: outcome = .failed("projects.json")
        case .write(let file): outcome = .failed(file)
        }
      } catch {
        outcome = .failed(String(describing: error))
      }
      await MainActor.run { phase = outcome }
    }
  }
}
