import ClaraNetworking
import Foundation
import Observation

public enum FeatureFlag: String, CaseIterable, Sendable {
    /// Small-step suggestions with on-device AI.
    case aiStepSuggestions = "ai_step_suggestions"
    /// Upcoming holiday notice on the Today screen (BrasilAPI data).
    case holidayBanner = "holiday_banner"
}

public enum Experiment: String, CaseIterable, Sendable {
    /// A/B test: 15- or 25-minute focus session.
    case focusDuration = "focus_duration"
}

/// Remote config JSON format (see `config/remote-config.json` at the repo root).
public struct RemoteConfig: Codable, Equatable, Sendable {
    public var flags: [String: Bool]
    public var experiments: [String: [String]]

    public init(flags: [String: Bool], experiments: [String: [String]]) {
        self.flags = flags
        self.experiments = experiments
    }

    /// Values bundled in the app: if the network fails, the app works the same.
    public static let defaults = RemoteConfig(
        flags: [
            FeatureFlag.aiStepSuggestions.rawValue: true,
            FeatureFlag.holidayBanner.rawValue: true,
        ],
        experiments: [
            Experiment.focusDuration.rawValue: ["15"],
        ]
    )
}

public enum RemoteConfigSource: String, Sendable {
    case defaults
    case cache
    case remote
}

/// Current flag state, observable by the screens.
///
/// `@MainActor`: flags are read by the UI; isolating them on the main actor avoids locks
/// and guarantees that a flag change always redraws the screen on the right thread.
@MainActor
@Observable
public final class FeatureFlags {
    public private(set) var config: RemoteConfig
    public private(set) var source: RemoteConfigSource
    public private(set) var installationID: String?
    /// Local overrides (diagnostics panel). They take priority over remote values.
    public var overrides: [FeatureFlag: Bool] = [:]

    public init(
        config: RemoteConfig = .defaults,
        source: RemoteConfigSource = .defaults,
        installationID: String? = nil
    ) {
        self.config = config
        self.source = source
        self.installationID = installationID
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        overrides[flag]
            ?? config.flags[flag.rawValue]
            ?? RemoteConfig.defaults.flags[flag.rawValue]
            ?? false
    }

    /// Variant assigned stably to this installation.
    /// Without an installation ID yet, returns the first variant (control group).
    public func variant(_ experiment: Experiment) -> String? {
        let variants = config.experiments[experiment.rawValue]
            ?? RemoteConfig.defaults.experiments[experiment.rawValue]
            ?? []
        guard let installationID else { return variants.first }
        return Bucketing.variant(for: experiment.rawValue, installationID: installationID, variants: variants)
    }

    public func apply(_ config: RemoteConfig, source: RemoteConfigSource) {
        self.config = config
        self.source = source
    }

    public func setInstallationID(_ id: String) {
        installationID = id
    }
}

public enum Bucketing {
    /// Why not `hashValue`? In Swift, `Hasher` uses a random seed per process:
    /// the same text hashes differently every time the app opens, and the user
    /// would switch A/B groups. FNV-1a is deterministic.
    public static func variant(for experiment: String, installationID: String, variants: [String]) -> String? {
        guard !variants.isEmpty else { return nil }
        let hash = fnv1a("\(experiment):\(installationID)")
        return variants[Int(hash % UInt64(variants.count))]
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

struct RemoteConfigEndpoint: Endpoint {
    typealias Response = RemoteConfig
    let path: String
}

/// Fetches the remote config with layered fallback: network → last saved value → default.
public struct RemoteConfigLoader: Sendable {
    private let client: any HTTPClient
    private let path: String
    private let cacheSuiteName: String?
    private static let cacheKey = "remote-config.cache"

    public init(client: any HTTPClient, path: String, cacheSuiteName: String? = nil) {
        self.client = client
        self.path = path
        self.cacheSuiteName = cacheSuiteName
    }

    public func load() async -> (RemoteConfig, RemoteConfigSource) {
        do {
            let config = try await client.send(RemoteConfigEndpoint(path: path))
            saveToCache(config)
            return (config, .remote)
        } catch {
            if let cached = loadFromCache() {
                return (cached, .cache)
            }
            return (.defaults, .defaults)
        }
    }

    // UserDefaults is created on demand instead of stored, so the struct stays
    // trivially Sendable.
    private var defaults: UserDefaults {
        cacheSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private func saveToCache(_ config: RemoteConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    private func loadFromCache() -> RemoteConfig? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(RemoteConfig.self, from: data)
    }
}
