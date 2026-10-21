import Foundation

/// A daily check-in or a one-off moment recorded by the user.
public struct Moment: Identifiable, Codable, Hashable, Sendable {
    // MARK: - Kind

    public enum Kind: String, Codable, Sendable {
        case daily
        case event
    }

    // MARK: - Stored properties

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

    // MARK: - Initialization

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

    // MARK: - Derived properties

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

// MARK: - Editing

extension Moment {
    /// Applies an edited draft. If the time did not change, keeps the original time zone;
    /// if it did, the new time was picked in the device's current time zone.
    public func applying(_ draft: MomentDraft, currentTimeZone: TimeZone) -> Moment {
        var updated = self
        updated.kind = draft.kind
        updated.mood = draft.mood
        updated.note = draft.note
        updated.context = draft.context
        updated.helpedOrHindered = draft.helpedOrHindered
        if draft.kind == .event, draft.occurredAt != occurredAt {
            updated.occurredAt = draft.occurredAt
            updated.timeZoneIdentifier = currentTimeZone.identifier
        }
        return updated
    }
}
