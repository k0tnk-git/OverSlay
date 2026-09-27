// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OverSlay",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OverSlay", targets: ["OverSlay"]),
        .library(name: "OverSlayCore", targets: ["OverSlayCore"])
    ],
    targets: [
        .target(name: "OverSlayCore", path: "Sources/OverSlayCore", resources: [.process("Resources")]),
        .executableTarget(name: "OverSlay", dependencies: ["OverSlayCore"], path: "Sources/OverSlay"),
        .testTarget(name: "OverSlayCoreTests", dependencies: ["OverSlayCore"], path: "Tests/OverSlayCoreTests")
    ]
)
