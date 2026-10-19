import ClaraAI

// MARK: - AI

public struct StubStepSuggester: StepSuggesting {
    public enum Behavior: Sendable {
        case succeed([String])
        case fail
        case hang
        case unavailable
    }

    private let behavior: Behavior
    private let source: StepSuggestion.Source

    public init(_ behavior: Behavior, source: StepSuggestion.Source = .onDevice) {
        self.behavior = behavior
        self.source = source
    }

    public var isAvailable: Bool {
        get async {
            if case .unavailable = behavior { return false }
            return true
        }
    }

    public func suggestSteps(for taskTitle: String) async throws -> StepSuggestion {
        switch behavior {
        case .succeed(let steps):
            return StepSuggestion(steps: steps, source: source)
        case .fail, .unavailable:
            throw StepSuggestionError.unavailable
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw StepSuggestionError.unavailable
        }
    }
}
