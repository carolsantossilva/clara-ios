import ClaraCore
import Foundation
import NaturalLanguage

/// Substituto sem modelo generativo: usa o NaturalLanguage (no aparelho) para
/// descobrir se o título já começa com um verbo e monta passos genéricos.
///
/// É honesto sobre ser simples — a tela mostra a origem da sugestão.
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
