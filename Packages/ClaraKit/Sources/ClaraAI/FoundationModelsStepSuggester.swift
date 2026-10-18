#if canImport(FoundationModels)
import ClaraCore
import Foundation
import FoundationModels

/// Saída estruturada: com `@Generable`, o modelo devolve direto esta struct
/// (guided generation) em vez de texto livre que precisaríamos interpretar.
@available(iOS 26.0, *)
@Generable
struct GeneratedSteps {
    // A macro lê a descrição em tempo de compilação, então ela precisa ser um literal.
    @Guide(description: "De 2 a 4 passos pequenos e concretos, em português do Brasil, com até 8 palavras, começando por verbo no infinitivo.")
    var steps: [String]
}

/// IA generativa no aparelho com o framework Foundation Models (Apple Intelligence).
/// Requer iOS 26 e um aparelho compatível com o Apple Intelligence ligado.
@available(iOS 26.0, *)
public struct FoundationModelsStepSuggester: StepSuggesting {
    private static let instructions = """
        Você ajuda uma pessoa a começar uma tarefa que ela mesma escolheu.
        Sugira passos pequenos, práticos e gentis para os primeiros minutos.
        Não dê conselhos médicos, diagnósticos nem julgamentos.
        Não invente informações sobre a vida da pessoa.
        """

    public init() {}

    public var isAvailable: Bool {
        get async { SystemLanguageModel.default.isAvailable }
    }

    public func suggestSteps(for taskTitle: String) async throws -> StepSuggestion {
        guard SystemLanguageModel.default.isAvailable else {
            throw StepSuggestionError.unavailable
        }
        // Uma sessão por pedido: não queremos que o histórico de uma tarefa
        // influencie a próxima.
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Tarefa: \(taskTitle.trimmed)",
            generating: GeneratedSteps.self
        )
        let steps = response.content.steps
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .prefix(4)
        guard !steps.isEmpty else { throw StepSuggestionError.noSteps }
        return StepSuggestion(steps: Array(steps), source: .onDevice)
    }

    public func prewarm() async {
        guard SystemLanguageModel.default.isAvailable else { return }
        LanguageModelSession(instructions: Self.instructions).prewarm()
    }
}
#endif
