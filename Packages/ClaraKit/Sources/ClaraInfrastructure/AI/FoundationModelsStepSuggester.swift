#if canImport(FoundationModels)
import ClaraCore
import Foundation
import FoundationModels

/// Structured output: with `@Generable`, the model returns this struct directly
/// (guided generation) instead of free text we would have to parse.
@available(iOS 26.0, *)
@Generable
struct GeneratedSteps {
    // The macro reads the description at compile time, so it has to be a literal.
    // The guide and the instructions are in Portuguese: they shape what the user reads.
    @Guide(description: "De 2 a 4 passos pequenos e concretos, em português do Brasil, com até 8 palavras, começando por verbo no infinitivo.")
    var steps: [String]
}

/// On-device generative AI with the Foundation Models framework (Apple Intelligence).
/// Requires iOS 26 and a compatible device with Apple Intelligence turned on.
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
        // One session per request: we do not want one task's history to
        // influence the next.
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
