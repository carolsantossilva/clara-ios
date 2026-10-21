import Foundation

/// What is in the form before it becomes a `Moment`.
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

    /// Same rule as the original app: one chosen word OR any text is enough.
    public var hasContent: Bool {
        mood != nil || [note, context, helpedOrHindered].contains { !$0.trimmed.isEmpty }
    }
}
