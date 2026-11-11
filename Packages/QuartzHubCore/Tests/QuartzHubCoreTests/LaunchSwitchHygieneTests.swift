import Foundation
import Testing
@testable import QuartzHubCore

/// "Startschalter kommen nur aus den Startargumenten" (docs/conventions.md): UserDefaults also
/// reads the app's persistent domain, so a value once set with `defaults write` held for every
/// later start. Review 2026-11-11, N4 moved the profile and window switches; the second round
/// found QHNoUpdateCheck, QHMemorySecrets, QHOpenProject and QHStartServerFor still read there
/// (Review 2026-11-11 (2), nebenbei 5). This keeps every `QH…` key out of UserDefaults.
@Suite struct LaunchSwitchHygieneTests {
  static let pattern = #"UserDefaults\.standard\.[a-zA-Z]+\(forKey:\s*"QH"#

  static func offending() throws -> [String] {
    let regex = try NSRegularExpression(pattern: pattern)
    var found: [String] = []
    for (root, label) in [(PathHygieneTests.sources, ""), (PathHygieneTests.app, "App/")] {
      for relative in try FileManager.default.subpathsOfDirectory(atPath: root) where relative.hasSuffix(".swift") {
        let text = try String(contentsOfFile: "\(root)/\(relative)", encoding: .utf8)
        for (number, line) in text.components(separatedBy: "\n").enumerated()
        where regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
          found.append("\(label)\(relative):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
        }
      }
    }
    return found
  }

  @Test func noSwitchComesFromUserDefaults() throws {
    let found = try Self.offending()
    #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
  }

  @Test func theScannerSeesTheForm() throws {
    let regex = try NSRegularExpression(pattern: Self.pattern)
    let line = #"if UserDefaults.standard.bool(forKey: "QHNoUpdateCheck") { return }"#
    #expect(regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil)
  }

  @Test func aFlagIsReadAsUserDefaultsReadIt() {
    #expect(LaunchArgument.flag("QHX", arguments: ["app", "-QHX", "YES"]))
    #expect(LaunchArgument.flag("QHX", arguments: ["app", "-QHX", "1"]))
    #expect(!LaunchArgument.flag("QHX", arguments: ["app", "-QHX", "NO"]))
    #expect(!LaunchArgument.flag("QHX", arguments: ["app"]))
  }
}
