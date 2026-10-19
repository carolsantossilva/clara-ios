import Foundation

// Models are `struct`s: value types with no shared identity.
// Copying a FocusTask across threads is safe (Sendable for free) and needs no
// reference counting, the opposite of a shared mutable `class`.

/// A task the user wants to do.
/// Named `FocusTask` so it does not clash with Swift Concurrency's `Task`.
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

/// An idea parked in "Isso pode esperar" (this can wait), to get the distraction out of her head.
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

/// How the user described the moment. Always a label, never a numeric score.
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

/// A daily check-in or a one-off moment recorded by the user.
public struct Moment: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case daily
        case event
    }

    public let id: UUID
    public var kind: Kind
    public var occurredAt: Date
    /// The time zone where the moment happened. The summary shows that day's local time,
    /// even if the user travels later.
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

    /// Label used in the list and the summary: the chosen mood or, without one, the record kind.
    public var displayLabel: String {
        mood?.label ?? (kind == .daily ? "Check-in" : "Momento")
    }
}

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

extension Moment {
    /// Applies an edited draft. If the time did not change, keeps the original time zone;
    /// if it did, the new time was picked in the device's current time zone.
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
