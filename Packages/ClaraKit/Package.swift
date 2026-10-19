// swift-tools-version: 6.0
import PackageDescription

// Every app module lives in this local package. Each feature depends only on
// protocols (ClaraCore) and platform services; no feature knows another.
// The app target wires the concrete dependencies (composition root).

// Swift 5 mode with strict concurrency checking: Sendable problems show up as
// warnings, which allows migrating to Swift 6 mode one module at a time.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
]

let package = Package(
    name: "ClaraKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ClaraCore", targets: ["ClaraCore"]),
        .library(name: "ClaraStorage", targets: ["ClaraStorage"]),
        .library(name: "ClaraNetworking", targets: ["ClaraNetworking"]),
        .library(name: "ClaraServices", targets: ["ClaraServices"]),
        .library(name: "ClaraAI", targets: ["ClaraAI"]),
        .library(name: "ClaraLegacy", targets: ["ClaraLegacy"]),
        .library(name: "ClaraDesignSystem", targets: ["ClaraDesignSystem"]),
        .library(name: "TodayFeature", targets: ["TodayFeature"]),
        .library(name: "RecordsFeature", targets: ["RecordsFeature"]),
        .library(name: "ConsultationFeature", targets: ["ConsultationFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.5"),
    ],
    targets: [
        // MARK: Base
        .target(name: "ClaraCore", swiftSettings: swiftSettings),
        .target(name: "ClaraLegacy"), // Objective-C
        .target(name: "ClaraNetworking", swiftSettings: swiftSettings),
        .target(name: "ClaraStorage", dependencies: ["ClaraCore"], swiftSettings: swiftSettings),
        .target(
            name: "ClaraServices",
            dependencies: ["ClaraCore", "ClaraNetworking", "ClaraLegacy"],
            swiftSettings: swiftSettings
        ),
        .target(name: "ClaraAI", dependencies: ["ClaraCore"], swiftSettings: swiftSettings),
        .target(name: "ClaraDesignSystem", dependencies: ["ClaraCore"], swiftSettings: swiftSettings),

        // MARK: Features
        .target(
            name: "TodayFeature",
            dependencies: ["ClaraCore", "ClaraDesignSystem", "ClaraAI", "ClaraServices", "ClaraLegacy"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RecordsFeature",
            dependencies: ["ClaraCore", "ClaraDesignSystem", "ClaraServices"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "ConsultationFeature",
            dependencies: ["ClaraCore", "ClaraDesignSystem", "ClaraServices"],
            swiftSettings: swiftSettings
        ),

        // MARK: Tests
        // Shared doubles (fakes, spies, immediate clock) so each suite does not duplicate them.
        .target(
            name: "ClaraTestSupport",
            dependencies: ["ClaraCore", "ClaraNetworking", "ClaraServices", "ClaraAI"],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "ClaraCoreTests", dependencies: ["ClaraCore", "ClaraTestSupport"]),
        .testTarget(name: "ClaraStorageTests", dependencies: ["ClaraStorage", "ClaraCore", "ClaraTestSupport"]),
        .testTarget(name: "ClaraNetworkingTests", dependencies: ["ClaraNetworking"]),
        .testTarget(name: "ClaraServicesTests", dependencies: ["ClaraServices", "ClaraCore", "ClaraLegacy", "ClaraTestSupport"]),
        .testTarget(name: "ClaraAITests", dependencies: ["ClaraAI", "ClaraTestSupport"]),
        .testTarget(
            name: "TodayFeatureTests",
            dependencies: ["TodayFeature", "ClaraCore", "ClaraAI", "ClaraServices", "ClaraStorage", "ClaraTestSupport"]
        ),
        .testTarget(
            name: "RecordsFeatureTests",
            dependencies: ["RecordsFeature", "ClaraCore", "ClaraStorage", "ClaraTestSupport"]
        ),
        .testTarget(
            name: "ConsultationFeatureTests",
            dependencies: ["ConsultationFeature", "ClaraCore", "ClaraServices", "ClaraStorage", "ClaraTestSupport"]
        ),
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "ClaraDesignSystem",
                "ClaraCore",
                "RecordsFeature",
                "TodayFeature",
                "ClaraStorage",
                "ClaraTestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
