import QuartzHubCore
import SwiftUI

/// Quartz 5.1's built-in processing on the Website tab: links, drafts, the content index and the
/// frontmatter, one section each, under `configuration.<key>`. The fields show what the build will
/// do (`BuiltinProcessing`, old plugin entries included) and write the configuration key, which
/// wins over an old entry. Only for a project whose Quartz has the built-ins (`QuartzFeatures`).
struct ProcessingSections: View {
  @Bindable var model: ConfigModel
  let project: ProjectContext

  private typealias Builtin = BuiltinProcessing.Builtin

  var body: some View {
    if let plan = model.builtins {
      Section {
        Note(L10n.t("builtins.description"))
        BuiltinMigration(project: project, pending: model.pendingMigrations, blockedByEdits: model.dirty, onConfigPage: true) {
          _ = try? await model.reread()
        }
      } header: {
        Label(L10n.t("builtins.heading"), systemImage: "gearshape.2")
      }
      links(plan)
      drafts(plan)
      contentIndex(plan)
      frontmatter(plan)
    }
  }

  // MARK: sections

  private func links(_ plan: BuiltinProcessing.Plan) -> some View {
    Section {
      state(plan[.links])
      FormField(hint: L10n.t("builtins.links.resolutionHint")) {
        Picker(L10n.t("builtins.links.resolution"), selection: text(.links, "markdownLinkResolution")) {
          Text(L10n.t("builtins.links.resolutionShortest")).tag("shortest")
          Text(L10n.t("builtins.links.resolutionRelative")).tag("relative")
          Text(L10n.t("builtins.links.resolutionAbsolute")).tag("absolute")
          unknown(.links, "markdownLinkResolution", known: ["shortest", "relative", "absolute"])
        }
        .accessibilityIdentifier("config.links.resolution")
      }
      FormField(hint: L10n.t("builtins.links.prettyLinksHint")) {
        Toggle(L10n.t("builtins.links.prettyLinks"), isOn: flag(.links, "prettyLinks"))
      }
      Toggle(L10n.t("builtins.links.openLinksInNewTab"), isOn: flag(.links, "openLinksInNewTab"))
      Toggle(L10n.t("builtins.links.externalLinkIcon"), isOn: flag(.links, "externalLinkIcon"))
      Toggle(L10n.t("builtins.links.lazyLoad"), isOn: flag(.links, "lazyLoad"))
      FormField(hint: L10n.t("builtins.links.brokenHint")) {
        Toggle(L10n.t("builtins.links.broken"), isOn: flag(.links, "disableBrokenWikilinks"))
      }
    } header: {
      Label(L10n.t("builtins.links.heading"), systemImage: "link")
    }
    .disabled(!plan[.links].enabled)
  }

  private func drafts(_ plan: BuiltinProcessing.Plan) -> some View {
    Section {
      state(plan[.drafts])
      FormField(hint: L10n.t("builtins.drafts.publishHint")) {
        Toggle(L10n.t("builtins.drafts.publish"), isOn: Binding(
          get: { !plan.removesDrafts },
          set: { publish in
            model.setBuiltin(.drafts, "publish", .bool(publish))
            // Off (an old remove-draft entry that is off, or `enabled: false`) also publishes
            // drafts; leaving them out again needs it on.
            if !publish, !plan[.drafts].enabled { model.setBuiltin(.drafts, "enabled", .bool(true)) }
          }))
        .accessibilityIdentifier("config.drafts.publish")
      }
    } header: {
      Label(L10n.t("builtins.drafts.heading"), systemImage: "pencil.and.outline")
    }
  }

  private func contentIndex(_ plan: BuiltinProcessing.Plan) -> some View {
    let planned = plan[.contentIndex]
    return Section {
      if case .replacedBy? = planned.note { state(planned) }
      FormField(hint: L10n.t("builtins.contentIndex.enabledHint")) {
        Toggle(L10n.t("builtins.contentIndex.enabled"), isOn: Binding(
          get: { planned.enabled },
          set: { model.setBuiltin(.contentIndex, "enabled", .bool($0)) }))
        .accessibilityIdentifier("config.contentIndex.enabled")
      }
      Group {
        Toggle(L10n.t("builtins.contentIndex.siteMap"), isOn: flag(.contentIndex, "enableSiteMap"))
        Toggle(L10n.t("builtins.contentIndex.rss"), isOn: flag(.contentIndex, "enableRSS"))
        Group {
          TextField(L10n.t("builtins.contentIndex.rssLimit"), value: number(.contentIndex, "rssLimit"), format: .number)
          FormField(hint: L10n.t("builtins.contentIndex.rssFullHtmlHint")) {
            Toggle(L10n.t("builtins.contentIndex.rssFullHtml"), isOn: flag(.contentIndex, "rssFullHtml"))
          }
          FormField(hint: L10n.t("builtins.contentIndex.rssSlugHint")) {
            TextField(L10n.t("builtins.contentIndex.rssSlug"), text: text(.contentIndex, "rssSlug"))
          }
        }
        .disabled(model.builtinValue(.contentIndex, "enableRSS") == .bool(false))
        Toggle(L10n.t("builtins.contentIndex.includeEmptyFiles"), isOn: flag(.contentIndex, "includeEmptyFiles"))
      }
      .disabled(!planned.enabled)
    } header: {
      Label(L10n.t("builtins.contentIndex.heading"), systemImage: "list.bullet.rectangle")
    }
  }

  private func frontmatter(_ plan: BuiltinProcessing.Plan) -> some View {
    Section {
      state(plan[.frontmatter])
      FormField(hint: L10n.t("builtins.frontmatter.delimitersHint")) {
        TextField(L10n.t("builtins.frontmatter.delimiters"), text: text(.frontmatter, "delimiters"))
      }
      Picker(L10n.t("builtins.frontmatter.language"), selection: text(.frontmatter, "language")) {
        Text(verbatim: "YAML").tag("yaml")
        Text(verbatim: "TOML").tag("toml")
        unknown(.frontmatter, "language", known: ["yaml", "toml"])
      }
    } header: {
      Label(L10n.t("builtins.frontmatter.heading"), systemImage: "doc.text")
    }
    .disabled(!plan[.frontmatter].enabled)
  }

  // MARK: pieces

  /// Why a built-in is off, in one line; nothing while it runs.
  @ViewBuilder private func state(_ planned: BuiltinProcessing.Planned) -> some View {
    switch planned.note {
    case .disabledInConfiguration?:
      Label(L10n.t("builtins.offInConfiguration"), systemImage: "pause.circle").foregroundStyle(.secondary)
    case .disabledByEntry(let plugin)?:
      Label(L10n.t("builtins.offByEntry", ["plugin": plugin]), systemImage: "pause.circle").foregroundStyle(.secondary)
    case .replacedBy(let plugin)?:
      Label(L10n.t("builtins.replacedBy", ["plugin": plugin]), systemImage: "arrow.triangle.swap").foregroundStyle(.secondary)
    case nil:
      EmptyView()
    }
  }

  /// A value the file has that QuartzHub has no word for stays selectable as it is.
  @ViewBuilder private func unknown(_ builtin: Builtin, _ key: String, known: [String]) -> some View {
    if let value = model.builtinValue(builtin, key)?.stringValue, !known.contains(value) {
      Text(verbatim: value).tag(value)
    }
  }

  private func flag(_ builtin: Builtin, _ key: String) -> Binding<Bool> {
    Binding(get: { model.builtinValue(builtin, key)?.boolValue ?? false },
            set: { model.setBuiltin(builtin, key, .bool($0)) })
  }

  private func text(_ builtin: Builtin, _ key: String) -> Binding<String> {
    Binding(get: { JSRead.string(model.builtinValue(builtin, key)) },
            set: { model.setBuiltin(builtin, key, .string($0)) })
  }

  private func number(_ builtin: Builtin, _ key: String) -> Binding<Double> {
    Binding(get: { model.builtinValue(builtin, key)?.numberValue ?? 0 },
            set: { model.setBuiltin(builtin, key, .number($0.rounded())) })
  }
}
