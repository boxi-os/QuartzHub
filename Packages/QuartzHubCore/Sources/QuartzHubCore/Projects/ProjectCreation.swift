import Foundation

/// "Neues Projekt erstellen" from start to end: what QuartzControl's start page (`Home.tsx`,
/// `onCreate`) did after `quartz create`, with the `projects:create` handler's add in front.
///
/// Once `quartz create` has succeeded the project exists and is in the list; nothing after that
/// undoes it. What did not happen is reported (`failure`, `warnings`) and the wizard offers the way
/// to the project.
public enum ProjectCreation {
  /// The example template to apply, and whether its notes come along (only into a content folder
  /// the project itself just made, see `contentAllowed`).
  public struct Template: Sendable, Equatable {
    public var path: String
    public var withContent: Bool
    public init(path: String, withContent: Bool) {
      self.path = path
      self.withContent = withContent
    }
  }

  public struct Outcome: Sendable, Equatable {
    /// nil when `quartz create` itself failed; the form stays with `output` as its message.
    public var projectId: String?
    public var output: String
    /// After the project exists: the template step that did not happen, as a sentence.
    public var failure: String?
    /// The template import's `kind:detail` strings, for `ImportWarnings.lines`.
    public var warnings: [String]
    /// Moving the stylesheet blocks failed: a sentence of its own. QuartzControl put it among the
    /// import's warnings, where it came out as "1× <the whole sentence>".
    public var styleFailure: String?

    /// The wizard has something to show before it goes to the project.
    public var hasReport: Bool { failure != nil || !warnings.isEmpty || styleFailure != nil }
  }

  /// The template's notes only into a content folder the project made. Under `copy` it holds the
  /// user's notes (and the import runs with packageWins); under `symlink` it is somebody's vault.
  public static func contentAllowed(_ strategy: ProjectCreator.Strategy) -> Bool { strategy == .new }

  /// The configuration's `locale` after a template: the app's language, since `quartz create`
  /// writes en-US and the example pages are German.
  public static func locale(forAppLanguage language: String) -> String {
    language.hasPrefix("de") ? "de-DE" : "en-US"
  }

  public static func run(
    _ options: ProjectCreator.Options,
    template: Template?,
    appLanguage: String,
    environment: ToolEnvironment,
    list: ProjectList,
    templates: TemplatePackage,
    create: @Sendable (ProjectCreator.Options, ToolEnvironment) async -> ProjectCreator.Result = { await ProjectCreator.create($0, environment: $1) }
  ) async -> Outcome {
    let created = await create(options, environment)
    guard created.success else {
      return Outcome(projectId: nil, output: created.output.isEmpty ? L10n.t("home.wizard.createFailed") : created.output, warnings: [])
    }
    let project = options.targetDirectory
    let entry: ProjectEntry
    do {
      entry = try await list.add(path: project)
    } catch {
      return Outcome(projectId: nil, output: String(describing: error), warnings: [])
    }
    var outcome = Outcome(projectId: entry.id, output: created.output, warnings: [])

    // A new project starts in the 1.1 form of the Styles page's blocks: no older state to go back
    // to, so no snapshot. A failure leaves the 1.0 form, which works too.
    do {
      _ = try await StyleSheets.migrate(project: project, snapshot: nil)
    } catch {
      outcome.styleFailure = TemplatePackage.message(error)
    }

    guard let template else { return outcome }
    do {
      // Plan first, so the parts come from the package rather than from a list here.
      guard let plan = try await templates.plan(project: project, package: template.path) else {
        outcome.failure = L10n.t("home.wizard.templateUnreadable")
        return outcome
      }
      let parts = plan.parts.map(\.id).filter { template.withContent || $0 != "content" }
      let imported = try await templates.importPackage(project: project, package: template.path, parts: parts, strategy: .packageWins)
      outcome.warnings += imported.warnings
      // The one setting the template does not carry: without it a German user gets German pages
      // under an English "Table of contents", and the package's translations are not rendered.
      var config = try await ConfigFile.read(project: project, runtime: environment.runtime)
      let wanted = locale(forAppLanguage: appLanguage)
      if config.configuration["locale"]?.stringValue != wanted {
        config.configuration["locale"] = .string(wanted)
        try await ConfigFile.write(config, project: project, runtime: environment.runtime)
      }
    } catch {
      outcome.failure = TemplatePackage.message(error)
    }
    return outcome
  }
}
