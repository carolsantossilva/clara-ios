import ClaraTestSupport
import Testing
@testable import ClaraAI

@Suite("Sugestão de passos")
struct StepSuggesterTests {
    @Test("usa a IA do aparelho quando ela responde")
    func usesPrimary() async throws {
        let suggester = FallbackStepSuggester(
            primary: StubStepSuggester(.succeed(["Abrir o e-mail"])),
            fallback: HeuristicStepSuggester()
        )

        let suggestion = try await suggester.suggestSteps(for: "Responder a clínica")

        #expect(suggestion == StepSuggestion(steps: ["Abrir o e-mail"], source: .onDevice))
    }

    @Test("cai para a heurística quando a IA falha, está indisponível ou demora", arguments: [
        StubStepSuggester.Behavior.fail, .unavailable, .hang,
    ])
    func fallsBack(_ behavior: StubStepSuggester.Behavior) async throws {
        let suggester = FallbackStepSuggester(
            primary: StubStepSuggester(behavior),
            fallback: HeuristicStepSuggester(),
            timeout: .milliseconds(50)
        )

        let suggestion = try await suggester.suggestSteps(for: "Organizar os exames")

        #expect(suggestion.source == .heuristic)
        #expect(suggestion.steps.count == 3)
    }

    @Test("título vazio não chama nenhum provedor")
    func rejectsEmptyTitle() async {
        let suggester = FallbackStepSuggester(primary: StubStepSuggester(.fail), fallback: HeuristicStepSuggester())
        await #expect(throws: StepSuggestionError.emptyTitle) {
            try await suggester.suggestSteps(for: "   ")
        }
    }
}
