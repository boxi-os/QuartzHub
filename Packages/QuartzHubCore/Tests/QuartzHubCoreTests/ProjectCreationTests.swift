import Foundation
import Testing
@testable import QuartzHubCore

/// The steps after `quartz create` (QuartzControl's `Home.tsx`, `onCreate`): what stays when a
/// later step fails. `quartz create` itself is replaced by a function that makes the folder; the
/// template import is measured in `TemplatePackageTests`.
@Suite(.enabled(if: HelperRuntime.available, "Runtime/ oder Helpers/dist fehlt"))
struct ProjectCreationTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  func setup() async -> (ProjectList, TemplatePackage, ToolEnvironment) {
    let profile = ProfileDirectory("\(scratch.path)/Profil")
    let environment = await ToolEnvironment.resolve(runtime: .repository, nodeMode: .embedded)
    let builds = BuildService(logs: LogBuffer(), environment: { environment })
    let list = ProjectList(store: ProjectStore(profile: profile), builds: builds,
                           connections: Connections(profile: profile, secrets: MemorySecrets()), runtime: .repository)
    let read: LayoutFrames.ReadConfig = { try await ConfigFile.read(project: $0, runtime: .repository) }
    let stub = PluginCommands.Result(success: true, output: "")
    let templates = TemplatePackage(
      runtime: .repository, locales: LocaleFiles(environment: environment), frames: LayoutFrames(readConfig: read),
      fonts: FontService(readConfig: read), npm: { _, _ in stub }, addPlugin: { _, _ in stub }, head: { _ in nil },
      snapshot: { _, _, _ in }, app: ("QuartzHub", "0.0.0-test"))
    return (list, templates, environment)
  }

  /// A `quartz create` that writes a config and nothing else.
  static let makesFolder: @Sendable (ProjectCreator.Options, ToolEnvironment) async -> ProjectCreator.Result = { options, _ in
    try? Posix.mkdirs(options.targetDirectory)
    try? Posix.write(ConfigFile.path(project: options.targetDirectory), Data("configuration:\n  pageTitle: Neu\n  locale: en-US\n".utf8))
    return ProjectCreator.Result(success: true, output: "erstellt")
  }

  @Test func aFailedCreateListsNothing() async {
    let (list, templates, environment) = await setup()
    let outcome = await ProjectCreation.run(
      ProjectCreator.Options(targetDirectory: "\(scratch.path)/Neu"), template: nil, appLanguage: "de",
      environment: environment, list: list, templates: templates,
      create: { _, _ in ProjectCreator.Result(success: false, output: "git: kaputt") })
    #expect(outcome.projectId == nil && outcome.output == "git: kaputt" && !outcome.hasReport)
    #expect(list.store.list().isEmpty)
  }

  /// Without a stylesheet to move the project still stands, listed, and the step says what failed.
  @Test func laterFailuresKeepTheProject() async throws {
    let (list, templates, environment) = await setup()
    let target = "\(scratch.path)/Gärten-Ü"
    let outcome = await ProjectCreation.run(
      ProjectCreator.Options(targetDirectory: target), template: .init(path: "\(scratch.path)/fehlt.qtpl", withContent: true),
      appLanguage: "de", environment: environment, list: list, templates: templates, create: Self.makesFolder)
    let id = try #require(outcome.projectId)
    #expect(list.store.project(id: id)?.path == target)
    #expect(outcome.failure != nil, "an unreadable template is reported")
    #expect(outcome.warnings.isEmpty)
    #expect(outcome.hasReport)
    // The template never ran, so the locale stays what quartz create wrote.
    #expect(try await ConfigFile.read(project: target, runtime: .repository).configuration["locale"]?.stringValue == "en-US")
  }

  @Test func theSiteSpeaksTheAppsLanguage() {
    #expect(ProjectCreation.locale(forAppLanguage: "de") == "de-DE")
    #expect(ProjectCreation.locale(forAppLanguage: "de-CH") == "de-DE")
    #expect(ProjectCreation.locale(forAppLanguage: "en") == "en-US")
    #expect(ProjectCreation.locale(forAppLanguage: "fr") == "en-US")
    #expect(ProjectCreation.contentAllowed(.new) && !ProjectCreation.contentAllowed(.copy) && !ProjectCreation.contentAllowed(.symlink))
  }
}
