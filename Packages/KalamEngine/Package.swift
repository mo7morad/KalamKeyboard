// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KalamEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KalamEngine", targets: ["KalamEngine"]),
        .executable(name: "kalam-cli", targets: ["kalam-cli"]),
    ],
    targets: [
        .target(name: "KalamEngine", resources: [.copy("Resources/Layouts"), .copy("Resources/emoji.json")]),
        .executableTarget(name: "kalam-cli", dependencies: ["KalamEngine"]),
        .testTarget(name: "KalamEngineTests", dependencies: ["KalamEngine"], exclude: ["Fixtures"]),
        .testTarget(name: "kalam-cliTests", dependencies: ["kalam-cli"]),
    ],
    swiftLanguageModes: [.v5]
)
