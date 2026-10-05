// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CidooCore",
  platforms: [.macOS(.v13)],
  products: [.library(name: "CidooCore", targets: ["CidooCore"])],
  targets: [.target(name: "CidooCore"), .testTarget(name: "CidooCoreTests", dependencies: ["CidooCore"])],
  swiftLanguageModes: [.v6]
)
