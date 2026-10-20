// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("StrictConcurrency")]

let package = Package(
    name: "ClaraKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ClaraCore", targets: ["ClaraCore"]),
        .library(name: "ClaraInfrastructure", targets: ["ClaraInfrastructure"]),
    ],
    targets: [
        .target(name: "ClaraCore", swiftSettings: swiftSettings),
        .target(name: "ClaraInfrastructure", dependencies: ["ClaraCore"], swiftSettings: swiftSettings),
        .target(
            name: "ClaraTestSupport",
            dependencies: ["ClaraCore", "ClaraInfrastructure"],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "ClaraCoreTests", dependencies: ["ClaraCore", "ClaraTestSupport"]),
        .testTarget(name: "ClaraStorageTests", dependencies: ["ClaraCore", "ClaraInfrastructure", "ClaraTestSupport"]),
        .testTarget(name: "ClaraNetworkingTests", dependencies: ["ClaraInfrastructure"]),
    ],
    swiftLanguageModes: [.v5]
)
