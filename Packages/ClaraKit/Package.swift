// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("StrictConcurrency")]

let package = Package(
    name: "ClaraKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ClaraCore", targets: ["ClaraCore"]),
        .library(name: "ClaraInfrastructure", targets: ["ClaraInfrastructure"]),
        .library(name: "ClaraUI", targets: ["ClaraUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6"),
    ],
    targets: [
        .target(
            name: "ClaraCore",
            resources: [.copy("Reports/Resources")],
            swiftSettings: swiftSettings
        ),
        .target(name: "ClaraInfrastructure", dependencies: ["ClaraCore"], swiftSettings: swiftSettings),
        .target(name: "ClaraUI", dependencies: ["ClaraCore", "ClaraInfrastructure"], swiftSettings: swiftSettings),
        .target(
            name: "ClaraTestSupport",
            dependencies: ["ClaraCore", "ClaraInfrastructure"],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "CoreTests", dependencies: ["ClaraCore", "ClaraTestSupport"]),
        .testTarget(name: "StorageTests", dependencies: ["ClaraCore", "ClaraInfrastructure", "ClaraTestSupport"]),
        .testTarget(name: "NetworkingTests", dependencies: ["ClaraInfrastructure", "ClaraTestSupport"]),
        .testTarget(name: "ServicesTests", dependencies: ["ClaraCore", "ClaraInfrastructure", "ClaraTestSupport"]),
        .testTarget(name: "AITests", dependencies: ["ClaraCore", "ClaraInfrastructure", "ClaraTestSupport"]),
        .testTarget(name: "TodayTests", dependencies: ["ClaraCore", "ClaraInfrastructure", "ClaraUI", "ClaraTestSupport"]),
        .testTarget(name: "RecordsTests", dependencies: ["ClaraCore", "ClaraInfrastructure", "ClaraUI", "ClaraTestSupport"]),
        .testTarget(name: "ConsultationTests", dependencies: ["ClaraCore", "ClaraInfrastructure", "ClaraUI", "ClaraTestSupport"]),
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "ClaraCore",
                "ClaraInfrastructure",
                "ClaraUI",
                "ClaraTestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
