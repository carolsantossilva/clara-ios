import ClaraCore
import Foundation
import NaturalLanguage

/// Fallback without a generative model: uses NaturalLanguage (on device) to
/// find out whether the title already starts with a verb and builds generic steps.
///
/// It is honest about being simple: the screen shows where the suggestion came from.
public struct HeuristicStepSuggester: StepSuggesting {
    public init() {}

    public var isAvailable: Bool {
        get async { true }
    }

    public func suggestSteps(for taskTitle: String) async throws -> StepSuggestion {
        let title = taskTitle.trimmed
        guard !title.isEmpty else { throw StepSuggestionError.emptyTitle }

        let subject = Self.startsWithVerb(title) ? Self.lowercasingFirstLetter(title) : "começar “\(title)”"
        return StepSuggestion(
            steps: [
                "Separar o que precisa para \(subject)",
                "Fazer só os primeiros 5 minutos",
                "Anotar onde parou",
            ],
            source: .heuristic
        )
    }

    static func startsWithVerb(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(.portuguese, range: text.startIndex..<text.endIndex)
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .word, scheme: .lexicalClass)
        return tag == .verb
    }

    private static func lowercasingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
