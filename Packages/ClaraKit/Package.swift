// swift-tools-version: 6.0
import PackageDescription

// Todos os módulos do app vivem neste pacote local. Cada feature depende só de
// protocolos (ClaraCore) e de serviços de plataforma; nenhuma feature conhece outra.
// Quem monta as dependências concretas é o target do app (composition root).

// Modo Swift 5 com checagem estrita de concorrência: os problemas de Sendable
// aparecem como warnings, o que permite migrar para o modo Swift 6 módulo a módulo.
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

        // MARK: Testes
        // Dublês compartilhados (fakes, spies, relógio imediato) para não duplicar em cada suíte.
        .target(
            name: "ClaraTestSupport",
            dependencies: ["ClaraCore", "ClaraNetworking", "ClaraServices", "ClaraAI"],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "ClaraCoreTests", dependencies: ["ClaraCore", "ClaraTestSupport"]),
        .testTarget(name: "ClaraStorageTests", dependencies: ["ClaraStorage", "ClaraCore", "ClaraTestSupport"]),
        .testTarget(name: "ClaraNetworkingTests", dependencies: ["ClaraNetworking"]),
        .testTarget(name: "ClaraServicesTests", dependencies: ["ClaraServices", "ClaraCore", "ClaraTestSupport"]),
        .testTarget(name: "ClaraAITests", dependencies: ["ClaraAI", "ClaraTestSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
