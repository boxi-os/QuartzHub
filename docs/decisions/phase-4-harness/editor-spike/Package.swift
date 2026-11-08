// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "editor-spike",
  platforms: [.macOS(.v15)],
  dependencies: [.package(url: "https://github.com/krzyzanowskim/STTextView", exact: "2.4.1")],
  targets: [
    .target(name: "Shared"),
    .executableTarget(name: "Spike", dependencies: ["Shared", .product(name: "STTextView", package: "STTextView")],
                      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "AXProbe"),
  ]
)
