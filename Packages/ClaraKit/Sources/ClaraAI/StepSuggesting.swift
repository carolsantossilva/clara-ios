import ClaraCore
import Foundation

/// Passos pequenos sugeridos para começar uma tarefa.
public struct StepSuggestion: Equatable, Sendable {
    public enum Source: String, Sendable {
        /// Modelo de linguagem da Apple rodando no aparelho (Foundation Models).
        case onDevice = "on_device"
        /// Regras simples com NaturalLanguage, quando não há modelo disponível.
        case heuristic
    }

    public let steps: [String]
    public let source: Source

    public init(steps: [String], source: Source) {
        self.steps = steps
        self.source = source
    }
}

/// Decisão de produto: a IA só *sugere* e sempre a pedido da usuária. Ela escolhe
/// um passo (ou nenhum). O texto não sai do aparelho e não há interpretação clínica.
public protocol StepSuggesting: Sendable {
    var isAvailable: Bool { get async }
    func suggestSteps(for taskTitle: String) async throws -> StepSuggestion
    /// Carrega o modelo antes do primeiro uso, para a resposta chegar mais rápido.
    func prewarm() async
}

extension StepSuggesting {
    public func prewarm() async {}
}

public enum StepSuggestionError: Error, Equatable {
    case emptyTitle
    case unavailable
    case noSteps
}

/// Tenta o provedor principal (IA no aparelho) e, se ele estiver indisponível,
/// falhar ou demorar demais, usa o substituto. Decorator + Open/Closed: dá para
/// trocar ou empilhar provedores sem mexer em quem chama.
public struct FallbackStepSuggester: StepSuggesting {
    private let primary: any StepSuggesting
    private let fallback: any StepSuggesting
    private let timeout: Duration

    public init(primary: any StepSuggesting, fallback: any StepSuggesting, timeout: Duration = .seconds(8)) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
    }

    public var isAvailable: Bool {
        get async {
            let primaryAvailable = await primary.isAvailable
            if primaryAvailable { return true }
            return await fallback.isAvailable
        }
    }

    public func suggestSteps(for taskTitle: String) async throws -> StepSuggestion {
        guard !taskTitle.trimmed.isEmpty else { throw StepSuggestionError.emptyTitle }
        if await primary.isAvailable {
            do {
                let primary = self.primary
                return try await withTimeout(timeout) {
                    try await primary.suggestSteps(for: taskTitle)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Cai para o substituto: a usuária sempre recebe alguma ajuda.
            }
        }
        return try await fallback.suggestSteps(for: taskTitle)
    }

    public func prewarm() async {
        await primary.prewarm()
    }
}

public enum StepSuggesterFactory {
    /// Escolhe o melhor provedor para este aparelho em tempo de execução.
    public static func makeDefault() -> any StepSuggesting {
        let heuristic = HeuristicStepSuggester()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FallbackStepSuggester(primary: FoundationModelsStepSuggester(), fallback: heuristic)
        }
        #endif
        return heuristic
    }
}
