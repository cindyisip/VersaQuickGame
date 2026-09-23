// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QuickGameCore", platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "QuickGameCore", targets: ["QuickGameCore"])],
    targets: [.target(name: "QuickGameCore", path: "VersaQuickGame/Core"),
              .testTarget(name: "QuickGameCoreTests", dependencies: ["QuickGameCore"], path: "Tests")])
