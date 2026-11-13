import Foundation
import Testing
@testable import QuartzHubCore

/// The answer to GitHub's latest release (`AppUpdateCheck.status`), without the network.
@Suite struct AppUpdateCheckTests {
  static func json(_ tag: String, _ url: String = "https://github.com/boxi-os/QuartzHub/releases/tag/v1.0.0") -> Data {
    Data(#"{"tag_name": "\#(tag)", "html_url": "\#(url)", "draft": false}"#.utf8)
  }

  @Test func aLaterReleaseIsNewerWithItsPage() {
    #expect(AppUpdateCheck.status(data: Self.json("v1.0.0"), statusCode: 200, current: "0.1.0")
      == .newer(current: "0.1.0", latest: "1.0.0", url: "https://github.com/boxi-os/QuartzHub/releases/tag/v1.0.0"))
    // A release before the prerelease one has installed: 1.0.0 is later than 1.0.0-beta.2.
    #expect(AppUpdateCheck.status(data: Self.json("1.0.0"), statusCode: 200, current: "1.0.0-beta.2")
      == .newer(current: "1.0.0-beta.2", latest: "1.0.0", url: "https://github.com/boxi-os/QuartzHub/releases/tag/v1.0.0"))
  }

  /// Same or older is current; a page outside this repository is not offered.
  @Test func sameOrOlderIsCurrentAndAForeignPageIsDropped() {
    #expect(AppUpdateCheck.status(data: Self.json("v0.1.0"), statusCode: 200, current: "0.1.0") == .current(current: "0.1.0", latest: "0.1.0"))
    #expect(AppUpdateCheck.status(data: Self.json("v0.0.9"), statusCode: 200, current: "0.1.0") == .current(current: "0.1.0", latest: "0.0.9"))
    #expect(AppUpdateCheck.status(data: Self.json("v2.0.0", "https://example.com/x"), statusCode: 200, current: "0.1.0")
      == .newer(current: "0.1.0", latest: "2.0.0", url: nil))
  }

  /// 404 (private repository, no release yet), a broken body or a tag that is no version: never
  /// "up to date", and never "newer".
  @Test func whatCannotBeReadIsUnknown() {
    #expect(AppUpdateCheck.status(data: Data(#"{"message":"Not Found"}"#.utf8), statusCode: 404, current: "0.1.0") == .unknown(current: "0.1.0"))
    #expect(AppUpdateCheck.status(data: Data("<html>".utf8), statusCode: 200, current: "0.1.0") == .unknown(current: "0.1.0"))
    #expect(AppUpdateCheck.status(data: Self.json("nightly"), statusCode: 200, current: "0.1.0") == .current(current: "0.1.0", latest: "nightly"))
  }
}
