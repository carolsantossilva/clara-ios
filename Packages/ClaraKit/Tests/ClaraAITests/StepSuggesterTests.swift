import ClaraTestSupport
import Testing
@testable import ClaraAI

@Suite("Step suggestions")
struct StepSuggesterTests {
    @Test("uses the on-device AI when it answers")
    func usesPrimary() async throws {
        let suggester = FallbackStepSuggester(
            primary: StubStepSuggester(.succeed(["Abrir o e-mail"])),
            fallback: HeuristicStepSuggester()
        )

        let suggestion = try await suggester.suggestSteps(for: "Responder a clínica")

        #expect(suggestion == StepSuggestion(steps: ["Abrir o e-mail"], source: .onDevice))
    }

    @Test("falls back to the heuristic when the AI fails, is unavailable or is slow", arguments: [
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

    @Test("an empty title calls no provider")
    func rejectsEmptyTitle() async {
        let suggester = FallbackStepSuggester(primary: StubStepSuggester(.fail), fallback: HeuristicStepSuggester())
        await #expect(throws: StepSuggestionError.emptyTitle) {
            try await suggester.suggestSteps(for: "   ")
        }
    }
}
