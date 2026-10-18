import Foundation

// Os modelos são `struct`: tipos de valor, sem identidade compartilhada.
// Copiar um FocusTask entre threads é seguro (Sendable de graça) e não exige
// contagem de referências — o oposto de uma `class` mutável compartilhada.

/// Uma tarefa que a usuária quer fazer.
/// Chama `FocusTask` para não colidir com `Task` do Swift Concurrency.
public struct FocusTask: Identifiable, Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable {
        case open
        case done
    }

    public let id: UUID
    public var title: String
    public var nextAction: String
    public var whereStopped: String
    public var state: State
    public var revision: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        nextAction: String = "",
        whereStopped: String = "",
        state: State = .open,
        revision: Int = 1,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.nextAction = nextAction
        self.whereStopped = whereStopped
        self.state = state
        self.revision = revision
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Uma ideia guardada em "Isso pode esperar", para tirar a distração da cabeça.
public struct ParkingNote: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var completed: Bool
    public var revision: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        text: String,
        completed: Bool = false,
        revision: Int = 1,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.completed = completed
        self.revision = revision
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Como a usuária descreveu o momento. Sempre com rótulo, nunca nota numérica.
public enum Mood: String, Codable, CaseIterable, Sendable {
    case good
    case okay
    case difficult

    public var label: String {
        switch self {
        case .good: "Bem"
        case .okay: "Ok"
        case .difficult: "Difícil"
        }
    }

    public var symbol: String {
        switch self {
        case .good: "☀"
        case .okay: "◒"
        case .difficult: "☁"
        }
    }
}

/// Um check-in diário ou um momento avulso registrado pela usuária.
public struct Moment: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case daily
        case event
    }

    public let id: UUID
    public var kind: Kind
    public var occurredAt: Date
    /// O fuso em que o momento aconteceu. O resumo mostra a hora local daquele dia,
    /// mesmo que a usuária viaje depois.
    public var timeZoneIdentifier: String
    public var mood: Mood?
    public var note: String
    public var context: String
    public var helpedOrHindered: String
    public var revision: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        occurredAt: Date,
        timeZoneIdentifier: String,
        mood: Mood? = nil,
        note: String = "",
        context: String = "",
        helpedOrHindered: String = "",
        revision: Int = 1,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.mood = mood
        self.note = note
        self.context = context
        self.helpedOrHindered = helpedOrHindered
        self.revision = revision
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    public var hasWrittenDetails: Bool {
        !note.isEmpty || !context.isEmpty || !helpedOrHindered.isEmpty
    }

    /// Rótulo usado na lista e no resumo: o humor escolhido ou, sem ele, o tipo do registro.
    public var displayLabel: String {
        mood?.label ?? (kind == .daily ? "Check-in" : "Momento")
    }
}

/// O que está no formulário antes de virar um `Moment`.
public struct MomentDraft: Equatable, Sendable {
    public var kind: Moment.Kind
    public var occurredAt: Date
    public var mood: Mood?
    public var note: String
    public var context: String
    public var helpedOrHindered: String

    public init(
        kind: Moment.Kind,
        occurredAt: Date,
        mood: Mood? = nil,
        note: String = "",
        context: String = "",
        helpedOrHindered: String = ""
    ) {
        self.kind = kind
        self.occurredAt = occurredAt
        self.mood = mood
        self.note = note
        self.context = context
        self.helpedOrHindered = helpedOrHindered
    }

    public init(editing moment: Moment) {
        self.init(
            kind: moment.kind,
            occurredAt: moment.occurredAt,
            mood: moment.mood,
            note: moment.note,
            context: moment.context,
            helpedOrHindered: moment.helpedOrHindered
        )
    }

    /// Mesmo critério do app original: basta uma palavra escolhida OU qualquer texto.
    public var hasContent: Bool {
        mood != nil || [note, context, helpedOrHindered].contains { !$0.trimmed.isEmpty }
    }
}

extension Moment {
    /// Aplica um rascunho editado. Se a hora não mudou, preserva o fuso original;
    /// se mudou, a nova hora foi escolhida no fuso atual do aparelho.
    public func applying(_ draft: MomentDraft, currentTimeZone: TimeZone) -> Moment {
        var updated = self
        updated.mood = draft.mood
        updated.note = draft.note
        updated.context = draft.context
        updated.helpedOrHindered = draft.helpedOrHindered
        if kind == .event, draft.occurredAt != occurredAt {
            updated.occurredAt = draft.occurredAt
            updated.timeZoneIdentifier = currentTimeZone.identifier
        }
        return updated
    }
}

extension String {
    public var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
