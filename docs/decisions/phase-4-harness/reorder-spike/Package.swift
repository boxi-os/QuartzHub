// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "reorder-spike",
  platforms: [.macOS(.v15)],
  targets: [.executableTarget(name: "Reorder"), .executableTarget(name: "Probe", swiftSettings: [.swiftLanguageMode(.v5)])]
)
