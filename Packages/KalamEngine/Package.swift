// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KalamEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KalamEngine", targets: ["KalamEngine"]),
    ],
    targets: [
        .target(name: "KalamEngine"),
    ],
    swiftLanguageModes: [.v5]
)
