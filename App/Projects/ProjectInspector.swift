import AppKit
import QuartzHubCore
import SwiftUI

/// The selected project in the Projects window: what QuartzControl's card showed, and its actions.
struct ProjectInspector: View {
  let row: ProjectOverview
  let open: () -> Void
  let duplicate: () -> Void
  let remove: () -> Void

  @State private var relocateFailure: String?
  @State private var relocating = false

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          ProjectAvatar(row: row, size: 44)
          VStack(alignment: .leading, spacing: 2) {
            Text(row.name).font(.title3.weight(.semibold))
            Text(row.lastOpenedLine).font(.caption).foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inspector.project")
        if let problem = row.problem {
          Label(problem, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
        if row.serverRunning {
          LabeledContent(L10n.t("common.serverState.running")) {
            Text(row.serverPort.map { L10n.t("home.serverRunningOnPort", ["port": String($0)]) } ?? L10n.t("home.serverRunning"))
          }
        }
      }
      Section {
        if let title = row.siteTitle {
          LabeledContent(L10n.t("shell.projects.siteTitle"), value: title)
        }
        if let address = row.baseUrl {
          LabeledContent(L10n.t("shell.projects.baseUrl"), value: address)
        }
        LabeledContent(L10n.t("shell.projects.folder")) {
          Text(row.path).textSelection(.enabled).multilineTextAlignment(.trailing)
        }
      }
      Section {
        Button(L10n.t("shell.projects.open"), action: open)
          .keyboardShortcut(.defaultAction)
          .disabled(row.missing || !row.isQuartzProject)
          .accessibilityIdentifier("projects.open")
        if row.missing {
          Button(L10n.t("home.locateFolder")) { relocate() }
            .disabled(relocating)
          if let relocateFailure {
            Text(relocateFailure).foregroundStyle(.red).font(.callout)
          }
        } else {
          Button(L10n.t("shell.projects.showInFinder")) {
            ExternalOpen.reveal([URL(fileURLWithPath: row.path)]) // path boundary
          }
        }
        if !row.missing && row.isQuartzProject {
          Button(L10n.t("home.duplicate.action") + "…", action: duplicate)
            .accessibilityIdentifier("projects.duplicate")
        }
        Button(L10n.t("home.confirmRemoveAction") + "…", role: .destructive, action: remove)
          .accessibilityIdentifier("projects.remove")
      }
    }
    .formStyle(.grouped)
    .onChange(of: row.id) { relocateFailure = nil }
  }

  private func relocate() {
    relocating = true
    relocateFailure = nil
    Task {
      defer { relocating = false }
      do { try await ProjectsModel.shared.relocate(row.id) } catch { relocateFailure = error.localizedMessage }
    }
  }
}

/// The Projects window without a selection: what QuartzControl's start page put beside the list.
struct ProjectsContext: View {
  @State private var model = ProjectsModel.shared

  var body: some View {
    Form {
      Section {
        Text(L10n.t("home.subtitle")).foregroundStyle(.secondary)
          .accessibilityIdentifier("inspector.projectsContext")
        // Named rather than implied by the band's absence: "no warning" and "ready" look alike.
        if let report = model.environment, report.ok {
          Label {
            Text("\(Text(L10n.t("home.environment.ready")).fontWeight(.medium))\(Text(" · " + report.toolSummary()).foregroundStyle(.secondary))")
          } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
          }
          .font(.caption)
          .accessibilityIdentifier("environment.ready")
        }
      }
      Section(L10n.t("home.aboutQuartz.title")) {
        Text(L10n.t("home.aboutQuartz.body")).foregroundStyle(.secondary)
        Link(L10n.t("home.aboutQuartz.docs"), destination: URL(string: "https://quartz.jzhao.xyz/")!)
        Link(L10n.t("home.aboutQuartz.catalog"), destination: URL(string: "https://github.com/quartz-community")!)
      }
      Section(L10n.t("home.capabilities.title")) {
        capability(L10n.t("home.capabilities.setup.title"), L10n.t("home.capabilities.setup.body"), "slider.horizontal.3")
        capability(L10n.t("home.capabilities.design.title"), L10n.t("home.capabilities.design.body"), "paintbrush")
        capability(L10n.t("home.capabilities.publish.title"), L10n.t("home.capabilities.publish.body"), "icloud.and.arrow.up")
        capability(L10n.t("home.capabilities.maintenance.title"), L10n.t("home.capabilities.maintenance.body"), "arrow.triangle.2.circlepath")
      }
    }
    .formStyle(.grouped)
  }

  private func capability(_ title: String, _ body: String, _ symbol: String) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
        Text(body).font(.caption).foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: symbol)
    }
  }
}

/// No project yet: the three steps and the two ways in, creating first (QuartzControl's order
/// with an empty list).
struct GettingStarted: View {
  let create: () -> Void
  let addExisting: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label(L10n.t("home.gettingStarted.title"), systemImage: "sparkles")
    } description: {
      VStack(alignment: .leading, spacing: 6) {
        let steps = [L10n.t("home.gettingStarted.step1"), L10n.t("home.gettingStarted.step2"), L10n.t("home.gettingStarted.step3")]
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
          Text("\(index + 1). \(step)")
        }
      }
      .frame(maxWidth: 420, alignment: .leading)
    } actions: {
      Button(L10n.t("home.createNew"), action: create)
        .buttonStyle(.borderedProminent)
      Button(L10n.t("home.openExisting"), action: addExisting)
    }
    .accessibilityIdentifier("projects.gettingStarted")
  }
}

/// Tools that are missing or do not run: QuartzControl's warning band above the list. Two kinds of
/// failing, two sentences: "reinstall" helps a tool of QuartzHub's that is broken, not one this
/// system cannot load.
struct EnvironmentBand: View {
  let report: EnvironmentReport
  let recheck: () -> Void

  var body: some View {
    let broken = report.broken
    VStack(alignment: .leading, spacing: 6) {
      Label {
        // "Fehlen" is only true while none of them is there.
        Text(broken.allSatisfy { $0.path == nil } ? L10n.t("home.environment.titleProblem") : L10n.t("home.environment.titleUnusable"))
          .font(.headline)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      }
      Text(L10n.t("home.environment.description")).foregroundStyle(.secondary)
      ForEach(broken, id: \.name) { tool in
        Text("\(tool.name) — \(tool.incompatible ? L10n.t("home.environment.incompatibleTool") : tool.path != nil ? L10n.t("home.environment.brokenTool") : L10n.t("home.environment.missing"))")
          .font(.callout.monospaced())
      }
      Text(broken.contains { $0.incompatible } ? L10n.t("home.environment.embeddedIncompatible") : L10n.t("home.environment.embeddedBroken"))
        .font(.caption)
        .foregroundStyle(.secondary)
      Button(L10n.t("home.environment.recheck"), action: recheck)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    .padding([.horizontal, .top], 12)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("environment.band")
  }
}
