import ClaraNetworking
import Foundation
import Observation

public enum FeatureFlag: String, CaseIterable, Sendable {
    /// Sugestão de passos pequenos com IA no aparelho.
    case aiStepSuggestions = "ai_step_suggestions"
    /// Aviso de feriado próximo na tela Hoje (dados da BrasilAPI).
    case holidayBanner = "holiday_banner"
}

public enum Experiment: String, CaseIterable, Sendable {
    /// Teste A/B: sessão de foco de 15 ou 25 minutos.
    case focusDuration = "focus_duration"
}

/// Formato do JSON de remote config (veja `config/remote-config.json` na raiz do repo).
public struct RemoteConfig: Codable, Equatable, Sendable {
    public var flags: [String: Bool]
    public var experiments: [String: [String]]

    public init(flags: [String: Bool], experiments: [String: [String]]) {
        self.flags = flags
        self.experiments = experiments
    }

    /// Valores embarcados no app: se a rede falhar, o app funciona igual.
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

/// Estado atual das flags, observável pelas telas.
///
/// `@MainActor`: as flags são lidas pela UI; isolar no main actor evita locks e
/// garante que uma mudança de flag sempre redesenha a tela na thread certa.
@MainActor
@Observable
public final class FeatureFlags {
    public private(set) var config: RemoteConfig
    public private(set) var source: RemoteConfigSource
    public private(set) var installationID: String?
    /// Sobrescritas locais (painel de diagnóstico). Têm prioridade sobre o remoto.
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

    /// Variante sorteada de forma estável para esta instalação.
    /// Sem ID de instalação ainda, devolve a primeira variante (grupo de controle).
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
    /// Por que não `hashValue`? Em Swift, `Hasher` usa uma semente aleatória por
    /// execução: o mesmo texto dá hashes diferentes a cada abertura do app, e a
    /// usuária trocaria de grupo do A/B. FNV-1a é determinístico.
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

/// Busca o remote config com fallback em camadas: rede → último valor salvo → padrão.
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

    // UserDefaults é criado na hora em vez de guardado: assim a struct continua
    // trivialmente Sendable.
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
