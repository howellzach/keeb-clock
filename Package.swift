// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "KeebClock",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "KeebClock", targets: ["KeebClock"])],
  dependencies: [.package(path: "CidooCore")],
  targets: [
    .executableTarget(
      name: "KeebClock",
      dependencies: [.product(name: "CidooCore", package: "CidooCore")],
      path: "KeebClock",
      exclude: ["Assets.xcassets"]
    )
  ],
  swiftLanguageModes: [.v6]
)
