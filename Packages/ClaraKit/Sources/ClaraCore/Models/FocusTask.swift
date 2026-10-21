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
