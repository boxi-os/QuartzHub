import Foundation
import Testing
@testable import QuartzHubCore

/// Review 2026-11-11, N4: the profile and window switches came from UserDefaults, which also reads
/// the app's persistent domain; one `defaults write` moved every later session.
@Suite struct LaunchArgumentTests {
  @Test func onlyThisLaunchsArgumentsCount() {
    let args = ["/Applications/QuartzHub.app/Contents/MacOS/QuartzHub", "-QHProfileDir", "/tmp/p", "-QHMigrationSource", "", "-QHLanguage"]
    #expect(LaunchArgument.string("QHProfileDir", arguments: args) == "/tmp/p")
    // Empty is a value: it turns the takeover off.
    #expect(LaunchArgument.string("QHMigrationSource", arguments: args) == "")
    // A switch without a value, or none at all, is nil.
    #expect(LaunchArgument.string("QHLanguage", arguments: args) == nil)
    #expect(LaunchArgument.string("QHWindowSize", arguments: args) == nil)
  }

  /// The counter-check: a value in the persistent domain is what UserDefaults would have read, and
  /// LaunchArgument does not.
  @Test func thePersistentDomainIsNotRead() {
    let suite = "qh-launch-argument-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("/somewhere/else", forKey: "QHProfileDir")
    #expect(defaults.string(forKey: "QHProfileDir") == "/somewhere/else")
    #expect(LaunchArgument.string("QHProfileDir", arguments: ["QuartzHub"]) == nil)
  }

  /// A development build has the repository's runtime, complete; a bundle without one is not.
  @Test func theRuntimeKnowsWhetherItIsComplete() {
    #expect(RuntimeLocation.repository.isComplete)
    #expect(!RuntimeLocation(node: "/nowhere/node", git: "/nowhere/git", helpers: "/nowhere/helpers").isComplete)
  }
}
