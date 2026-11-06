// swift-tools-version: 6.0
// The whole logic of QuartzHub, without UI. The app (App/, via project.yml) and qh-check both load
// it, so a check never re-implements what the app does (docs/conventions.md, "lädt statt
// abschreiben").
import PackageDescription

let package = Package(
  name: "QuartzHubCore",
  defaultLocalization: "de",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "QuartzHubCore", targets: ["QuartzHubCore"]),
    .executable(name: "qh-check", targets: ["qh-check"])
  ],
  targets: [
    .target(
      name: "QuartzHubCore",
      // .copy, not .process: the catalog is read as JSON by L10n (see there for why), so it must
      // arrive in the bundle as the file that is versioned, not compiled to .strings.
      resources: [.copy("Resources/Localizable.xcstrings")],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
      name: "qh-check",
      dependencies: ["QuartzHubCore"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "QuartzHubCoreTests",
      dependencies: ["QuartzHubCore"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    )
  ]
)
